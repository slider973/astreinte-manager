-- 0041 — Échanger ou céder une astreinte entre pompiers. Ticket 073, chantier base.
-- Référence : docs/SCHEMA.md § 2.19 (table), § 3 (« Échanges d'astreintes »),
-- § 4 (RLS), § 8 (tâche `expire_exchanges`) ; docs/WORKFLOWS.md § 3 bis
-- (machine à états), § 5 bis (séquence) et § 8 (notifications, liens profonds).
--
-- S'applique après 0040 (ticket 072), dont il utilise `member_taken_elsewhere`
-- (règle « pas pris ailleurs ») et le verrou consultatif par pompier
-- d'`apply_auto_proposal`.
--
-- Ce que la migration pose
-- ------------------------
--   1. Deux énumérations (`exchange_kind`, `exchange_status`) et cinq types de
--      notification (`exchange_requested`, `exchange_accepted`,
--      `exchange_approved`, `exchange_rejected`, `exchange_closed`).
--   2. Deux clés **facultatives** dans `stations.settings` :
--      `exchange_auto_approve` (booléen, faux par défaut) et
--      `exchange_deadline_hours` (entier 1–168, 24 par défaut).
--   3. La table `shift_exchanges`, sa RLS (lecture seule pour les clients) et le
--      déclencheur qui tient sa machine à états.
--   4. Les fonctions internes : début d'un créneau, échéance, contrôle des
--      règles du remplaçant, charge utile, clôture, exécution.
--   5. Les quatre fonctions ouvertes à `authenticated` : `request_exchange`,
--      `respond_exchange`, `decide_exchange`, `cancel_exchange` ; et la lecture
--      `exchangeable_shifts_of`, sans laquelle un échange ne se compose pas sur
--      un planning seulement publié.
--   6. Le déclencheur qui fait échouer une demande dont la garde a changé de
--      main par l'administrateur (`reassign_shift`, `cancel_assignment`).
--   7. La tâche `expire_exchanges` et sa fonction.
--
-- **L'ordre des verrous, une fois pour toutes.** `reassign_shift` (0020) et la
-- réponse d'un membre prennent l'attribution, puis le planning. Les fonctions de
-- ce fichier prennent : les attributions concernées (garde cédée, garde rendue)
-- **dans l'ordre de leurs identifiants**, puis la ligne de `shift_exchanges`,
-- puis les plannings dans l'ordre de leurs identifiants. Le déclencheur du § 6
-- prend la demande **après** l'attribution qu'on vient de modifier : même sens.
-- Personne ne prend une demande puis une attribution, donc aucun cycle. La
-- tâche d'expiration ne prend que des demandes, en `skip locked`. Enfin, à
-- l'exécution seulement, le verrou consultatif par pompier du ticket 072
-- (0040), après les plannings — voir `exchange_apply`.
--
-- **Pourquoi verrouiller l'attribution avant la demande**, et pas l'inverse :
-- c'est ce qui sérialise la validation d'un échange avec une réattribution de
-- l'administrateur sur la même garde. Les deux commencent par la même ligne ;
-- la seconde arrivée lit l'état laissé par la première et refuse
-- (`assignment_not_replaceable` côté réattribution, demande déjà `failed` côté
-- échange). Et c'est aussi ce qui départage deux repreneurs : le second attend
-- sur l'attribution, puis trouve la demande déjà prise (`exchange_not_open`).

-- ===========================================================================
-- 1. Types
-- ===========================================================================
create type exchange_kind as enum ('give', 'swap');

create type exchange_status as enum (
  'open',              -- en attente d'un repreneur
  'accepted_by_peer',  -- le repreneur a dit oui, l'administrateur doit valider
  'approved',          -- validée : les attributions ont changé de main
  'rejected',          -- refusée, par le collègue sollicité ou par l'administrateur
  'cancelled',         -- annulée par le demandeur
  'expired',           -- échéance atteinte sans décision
  'failed'             -- une règle ne tenait plus au moment d'agir : rien n'a changé
);

-- `add value` est permis dans une transaction depuis PostgreSQL 12 ; les
-- valeurs ne servent que dans des corps plpgsql, résolus à l'exécution.
alter type notification_type add value if not exists 'exchange_requested';
alter type notification_type add value if not exists 'exchange_accepted';
alter type notification_type add value if not exists 'exchange_approved';
alter type notification_type add value if not exists 'exchange_rejected';
alter type notification_type add value if not exists 'exchange_closed';

-- ===========================================================================
-- 2. Deux réglages de caserne, facultatifs
-- ===========================================================================
-- `station_settings_valid` est réécrite à l'identique de 0033, à trois endroits
-- près : les deux clés dans `connues` (et **pas** dans `obligatoires`, pour la
-- raison donnée en 0032 et 0033 : la contrainte est rejouée à chaque écriture,
-- une clé rendue obligatoire condamnerait toute caserne existante), leurs
-- bornes, et le commentaire.
--
-- `exchange_auto_approve` est le **seul booléen** du document : `true` ou
-- `false` JSON, jamais `"true"` ni `1`. Absente, elle vaut faux — la validation
-- par l'administrateur est le défaut (décision 3 du ticket).
--
-- `exchange_deadline_hours` : combien d'heures avant le début du créneau une
-- demande expire, de 1 à 168 (une semaine), 24 par défaut — bornes retenues par
-- le brief de design du ticket (design/073-echange-astreintes.md § 9). Une
-- demande n'expire donc jamais plus tard qu'une heure avant le créneau.
create or replace function station_settings_valid(p_settings jsonb) returns boolean
language plpgsql immutable
set search_path = public, pg_temp
as $$
declare
  connues constant text[] := array[
    'day_start', 'day_end',
    'required_day', 'required_night', 'required_overrides',
    'availability_deadline_day',
    'response_reminder_hours', 'response_email_hours', 'late_report_hours',
    'invitation_hourly_limit',
    'notification_hour',
    'exchange_auto_approve',
    'exchange_deadline_hours'
  ];
  -- Ni `invitation_hourly_limit` (0032), ni `notification_hour` (0033), ni les
  -- deux clés des échanges (0041) ne sont obligatoires : les casernes écrites
  -- avant ces migrations ne les portent pas, et la contrainte est rejouée à leur
  -- première mise à jour.
  obligatoires constant text[] := array[
    'day_start', 'day_end',
    'required_day', 'required_night',
    'availability_deadline_day',
    'response_reminder_hours', 'response_email_hours', 'late_report_hours'
  ];
  effectif_max constant integer := 50;
  jour_limite_max constant integer := 28;
  delai_max constant integer := 336;
  invitations_max constant integer := 500;
  heure_min constant integer := 6;
  heure_max constant integer := 20;
  echeance_echange_max constant integer := 168;
  cle text;
  surcharge jsonb;
  sous_cle text;
begin
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    return false;
  end if;

  for cle in select jsonb_object_keys(p_settings) loop
    if not (cle = any (connues)) then return false; end if;
  end loop;

  foreach cle in array obligatoires loop
    if not (p_settings ? cle) then return false; end if;
  end loop;

  if not station_settings_heure_valide(p_settings -> 'day_start')
     or not station_settings_heure_valide(p_settings -> 'day_end') then
    return false;
  end if;

  if (p_settings ->> 'day_start') = (p_settings ->> 'day_end') then
    return false;
  end if;

  if not station_settings_entier_valide(p_settings -> 'required_day', 0, effectif_max)
     or not station_settings_entier_valide(p_settings -> 'required_night', 0, effectif_max) then
    return false;
  end if;

  if not station_settings_entier_valide(
       p_settings -> 'availability_deadline_day', 1, jour_limite_max) then
    return false;
  end if;

  if not station_settings_entier_valide(p_settings -> 'response_reminder_hours', 1, delai_max)
     or not station_settings_entier_valide(p_settings -> 'response_email_hours', 1, delai_max)
     or not station_settings_entier_valide(p_settings -> 'late_report_hours', 1, delai_max) then
    return false;
  end if;

  if p_settings ? 'invitation_hourly_limit'
     and not station_settings_entier_valide(
           p_settings -> 'invitation_hourly_limit', 1, invitations_max) then
    return false;
  end if;

  if p_settings ? 'notification_hour'
     and not station_settings_entier_valide(
           p_settings -> 'notification_hour', heure_min, heure_max) then
    return false;
  end if;

  -- 0041 : un vrai booléen JSON, rien d'autre.
  if p_settings ? 'exchange_auto_approve'
     and jsonb_typeof(p_settings -> 'exchange_auto_approve') is distinct from 'boolean' then
    return false;
  end if;

  -- 0041 : de 1 à 168 heures.
  if p_settings ? 'exchange_deadline_hours'
     and not station_settings_entier_valide(
           p_settings -> 'exchange_deadline_hours', 1, echeance_echange_max) then
    return false;
  end if;

  if p_settings ? 'required_overrides' then
    if jsonb_typeof(p_settings -> 'required_overrides') <> 'object' then
      return false;
    end if;

    for cle, surcharge in
      select * from jsonb_each(p_settings -> 'required_overrides')
    loop
      if not station_settings_cle_surcharge_valide(cle) then return false; end if;
      if jsonb_typeof(surcharge) <> 'object' then return false; end if;

      if surcharge = '{}'::jsonb then return false; end if;

      for sous_cle in select jsonb_object_keys(surcharge) loop
        if sous_cle not in ('day', 'night') then return false; end if;
        if not station_settings_entier_valide(
             surcharge -> sous_cle, 0, effectif_max) then
          return false;
        end if;
      end loop;
    end loop;
  end if;

  return true;
end $$;

comment on function station_settings_valid(jsonb) is
  'Valide le document stations.settings (docs/SCHEMA.md § 2.1). Support de la contrainte stations_settings_valide et miroir exact de la validation côté application. invitation_hourly_limit (ticket 038), notification_hour (ticket 041), exchange_auto_approve et exchange_deadline_hours (ticket 073) sont facultatives : les casernes écrites avant 0032, 0033 et 0041 restent valides.';

create function station_exchange_auto_approve(p_station uuid) returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select (s.settings -> 'exchange_auto_approve') = 'true'::jsonb
       from stations s where s.id = p_station),
    false);
$$;

comment on function station_exchange_auto_approve(uuid) is
  'Validation automatique des échanges : settings.exchange_auto_approve, faux quand la clé est absente (docs/SCHEMA.md § 2.1, ticket 073).';

create function station_exchange_deadline_hours(p_station uuid) returns integer
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select nullif(s.settings ->> 'exchange_deadline_hours', '')::integer
       from stations s where s.id = p_station),
    24);
$$;

comment on function station_exchange_deadline_hours(uuid) is
  'Heures avant le début du créneau où une demande d''échange expire : settings.exchange_deadline_hours, 24 quand la clé est absente (docs/SCHEMA.md § 2.1, ticket 073).';

revoke execute on function station_exchange_auto_approve(uuid) from public, anon, authenticated;
revoke execute on function station_exchange_deadline_hours(uuid) from public, anon, authenticated;

-- ===========================================================================
-- 3. La table
-- ===========================================================================
-- Une ligne par demande. Elle ne se supprime pas : c'est l'historique (« qui a
-- demandé, qui a accepté, qui a validé, quand »). Les colonnes `shift_id` et
-- `return_shift_id` recopient le créneau des attributions : un repreneur
-- potentiel lit les créneaux d'un planning publié mais **pas** l'attribution
-- d'un collègue, et c'est par le créneau qu'il sait de quoi on lui parle.
create table shift_exchanges (
  id                       uuid primary key default gen_random_uuid(),
  station_id               uuid not null references stations(id) on delete cascade,
  kind                     exchange_kind not null,
  status                   exchange_status not null default 'open',
  -- A : le demandeur, et la garde qu'il cède.
  requester_id             uuid not null references profiles(id) on delete cascade,
  assignment_id            uuid not null references assignments(id) on delete cascade,
  shift_id                 uuid not null references shifts(id) on delete cascade,
  -- B désigné. Nul : demande « à la caserne », ouverte aux disponibles.
  target_id                uuid references profiles(id) on delete cascade,
  -- Échange seulement : la garde de B que A prend en retour.
  return_assignment_id     uuid references assignments(id) on delete cascade,
  return_shift_id          uuid references shifts(id) on delete cascade,
  -- B qui a dit oui (le destinataire, ou le premier disponible).
  taker_id                 uuid references profiles(id) on delete cascade,
  -- Les attributions nées de la validation : B sur la garde de A, et A sur
  -- celle de B pour un échange.
  new_assignment_id        uuid references assignments(id) on delete cascade,
  new_return_assignment_id uuid references assignments(id) on delete cascade,
  auto_approved            boolean not null default false,
  -- Qui a tranché : l'administrateur qui a validé ; celui qui a refusé — B
  -- (`peer_declined`) ou l'administrateur (`admin_rejected`) ; l'administrateur
  -- dont la validation a échoué. Nul pour une validation automatique
  -- (`auto_approved`), une expiration, une annulation, ou un échec né d'un
  -- geste de l'administrateur ailleurs (`assignment_changed`).
  decided_by               uuid references profiles(id),
  -- Le motif de clôture, **dans une liste fermée** (contrainte
  -- `shift_exchanges_reason_code` ci-dessous), et, pour un refus de
  -- l'administrateur seulement, sa phrase facultative.
  reason_code              text,
  reason                   text,
  expires_at               timestamptz not null,
  accepted_at              timestamptz,
  decided_at               timestamptz,
  closed_at                timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),

  constraint shift_exchanges_swap_has_return
    check ((kind = 'swap') = (return_assignment_id is not null)),
  constraint shift_exchanges_return_shift
    check ((return_assignment_id is null) = (return_shift_id is null)),
  constraint shift_exchanges_swap_has_target
    check (kind = 'give' or target_id is not null),
  constraint shift_exchanges_target_not_self
    check (target_id is distinct from requester_id),
  constraint shift_exchanges_taker_not_self
    check (taker_id is distinct from requester_id),
  constraint shift_exchanges_taker_is_target
    check (target_id is null or taker_id is null or taker_id = target_id),
  constraint shift_exchanges_taker_when_accepted
    check (status not in ('accepted_by_peer', 'approved') or taker_id is not null),
  constraint shift_exchanges_approved_has_assignments
    check (status <> 'approved'
           or (new_assignment_id is not null
               and (kind = 'give') = (new_return_assignment_id is null))),
  constraint shift_exchanges_closed_at
    check ((status in ('open', 'accepted_by_peer')) = (closed_at is null)),
  constraint shift_exchanges_reason_longueur
    check (reason is null or char_length(reason) <= 500),
  constraint shift_exchanges_reason_admin_only
    check (reason is null or reason_code = 'admin_rejected'),
  -- La liste fermée des motifs, par statut. Une demande ouverte ou validée n'en
  -- porte aucun. « Pris dans une autre caserne » (ticket 072) n'y figure pas :
  -- A et B lisent ce motif, il devient `*_already_assigned`, et le détail va au
  -- journal des administrateurs (`audit_log.data.detail`).
  constraint shift_exchanges_reason_code check (
    case status
      when 'open'             then reason_code is null
      when 'accepted_by_peer' then reason_code is null
      when 'approved'         then reason_code is null
      when 'rejected'         then reason_code in ('peer_declined', 'admin_rejected')
      when 'cancelled'        then reason_code = 'requester_cancelled'
      when 'expired'          then reason_code = 'deadline_reached'
      when 'failed'           then reason_code in (
        'station_suspended',
        'assignment_changed',
        'assignment_not_accepted',
        'return_assignment_not_accepted',
        'schedule_not_published',
        'requester_not_active',
        'peer_not_active',
        'peer_already_assigned',
        'peer_shift_quota_reached',
        'peer_weekend_quota_reached',
        'requester_already_assigned',
        'requester_shift_quota_reached',
        'requester_weekend_quota_reached')
    end)
);

-- « Une seule demande ouverte par attribution » : l'index tient la garde cédée.
-- La garde **rendue** d'un échange compte aussi ; deux colonnes ne tiennent pas
-- dans un index unique, c'est donc `request_exchange` qui la vérifie, sous le
-- verrou des deux attributions.
create unique index shift_exchanges_open_uniq
  on shift_exchanges (assignment_id)
  where status in ('open', 'accepted_by_peer');
create index shift_exchanges_return_open_idx
  on shift_exchanges (return_assignment_id)
  where status in ('open', 'accepted_by_peer') and return_assignment_id is not null;
create index on shift_exchanges (station_id, status, created_at desc);
create index on shift_exchanges (requester_id, created_at desc);
create index on shift_exchanges (target_id) where target_id is not null;
create index on shift_exchanges (taker_id) where taker_id is not null;
create index on shift_exchanges (shift_id) where status = 'open' and target_id is null;
create index shift_exchanges_expiry_idx
  on shift_exchanges (expires_at)
  where status in ('open', 'accepted_by_peer');

create trigger shift_exchanges_set_updated_at
  before update on shift_exchanges
  for each row execute function set_updated_at();

comment on table shift_exchanges is
  'Demandes d''échange ou de cession d''une astreinte entre pompiers (ticket 073). Écrites par request_exchange, respond_exchange, decide_exchange, cancel_exchange et la tâche expire_exchanges ; jamais par un client. docs/SCHEMA.md § 2.19, docs/WORKFLOWS.md § 3 bis.';

-- ---------------------------------------------------------------------------
-- La machine à états, pour tout le monde (rôle de service compris)
-- ---------------------------------------------------------------------------
-- docs/WORKFLOWS.md § 3 bis. Une demande naît `open` ; `open` va vers
-- `accepted_by_peer` ou une clôture ; `accepted_by_peer` vers `approved` ou une
-- clôture ; une demande close ne bouge plus. La clé (qui, quelle garde, quel
-- destinataire, quelle échéance) est gelée dès la naissance.
--
-- À l'insertion, la cohérence des attributions avec la demande : la garde
-- cédée est celle du demandeur, sur le créneau recopié, dans la caserne ; la
-- garde rendue est celle du destinataire. Les fonctions le garantissent déjà ;
-- la règle est ici pour qu'elle le reste quel que soit l'écrivain.
--
-- Security invoker, comme `schedules_guard_transition` (0019) : une machine à
-- états est une propriété du domaine.
create function shift_exchanges_guard() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'open' then
      raise exception 'exchange_invalid_transition'
        using hint = 'Une demande d''échange naît ouverte.';
    end if;

    if not exists (
      select 1 from assignments a
       where a.id = new.assignment_id
         and a.shift_id = new.shift_id
         and a.station_id = new.station_id
         and a.user_id = new.requester_id
    ) then
      raise exception 'exchange_assignment_mismatch'
        using hint = 'La garde cédée appartient au demandeur, sur ce créneau, dans cette caserne.';
    end if;

    if new.return_assignment_id is not null and not exists (
      select 1 from assignments a
       where a.id = new.return_assignment_id
         and a.shift_id = new.return_shift_id
         and a.station_id = new.station_id
         and a.user_id = new.target_id
    ) then
      raise exception 'exchange_assignment_mismatch'
        using hint = 'La garde rendue appartient au destinataire, sur ce créneau, dans cette caserne.';
    end if;

    return new;
  end if;

  if new.station_id <> old.station_id
     or new.kind <> old.kind
     or new.requester_id <> old.requester_id
     or new.assignment_id <> old.assignment_id
     or new.shift_id <> old.shift_id
     or new.target_id is distinct from old.target_id
     or new.return_assignment_id is distinct from old.return_assignment_id
     or new.return_shift_id is distinct from old.return_shift_id
     or new.expires_at <> old.expires_at
     or new.created_at <> old.created_at then
    raise exception 'exchange_key_immutable'
      using hint = 'Qui demande, quelle garde, à qui et jusqu''à quand ne se réécrivent pas : une autre demande se crée.';
  end if;

  if old.status not in ('open', 'accepted_by_peer') then
    raise exception 'exchange_closed'
      using hint = format('Une demande %s ne bouge plus : c''est l''historique.', old.status);
  end if;

  if new.status is distinct from old.status and not (
       (old.status = 'open'
        and new.status in ('accepted_by_peer', 'rejected', 'cancelled', 'expired', 'failed'))
    or (old.status = 'accepted_by_peer'
        and new.status in ('approved', 'rejected', 'cancelled', 'expired', 'failed'))
  ) then
    raise exception 'exchange_invalid_transition'
      using hint = format('%s -> %s n''existe pas (docs/WORKFLOWS.md § 3 bis).', old.status, new.status);
  end if;

  return new;
end $$;

comment on function shift_exchanges_guard() is
  'Machine à états de shift_exchanges (docs/WORKFLOWS.md § 3 bis) : naissance en open, transitions permises seulement, demande close immuable, clé gelée, attributions cohérentes avec le demandeur et le destinataire.';

revoke execute on function shift_exchanges_guard() from public, anon, authenticated;

create trigger shift_exchanges_guard
  before insert or update on shift_exchanges
  for each row execute function shift_exchanges_guard();

-- ---------------------------------------------------------------------------
-- RLS : lecture seule pour les clients
-- ---------------------------------------------------------------------------
-- Aucune politique d'écriture : tout passe par les fonctions du § 5, qui
-- verrouillent, vérifient et notifient. Les privilèges d'écriture sont en plus
-- retirés, pour que l'absence de politique ne soit pas la seule barrière.
alter table shift_exchanges enable row level security;

revoke all on shift_exchanges from anon;
revoke insert, update, delete, truncate, references, trigger on shift_exchanges from authenticated;
grant select on shift_exchanges to authenticated;

-- A, le destinataire désigné et le repreneur voient la leur, quel qu'en soit
-- l'état — c'est leur historique. Membre **actif** : une appartenance
-- désactivée ne lit plus rien de la caserne.
create policy "shift_exchanges_select_party"
  on shift_exchanges for select to authenticated
  using (
    is_member(station_id)
    and auth.uid() in (requester_id, target_id, taker_id)
  );

-- « À la caserne » : visible **exactement** de ceux à qui elle a été — ou
-- aurait été — envoyée : membres actifs qui ont déclaré `available` sur ce
-- créneau et que les règles du remplaçant laissent la reprendre (pas déjà sur
-- le créneau, plafonds du mois, pas pris ailleurs). Les autres ne la voient pas :
-- pas de bruit pour qui n'est pas libre (décision 1 du ticket), et pas de
-- demande visible qu'on ne pourrait pas prendre. Une fois prise, elle sort de
-- leur vue ; le repreneur la garde par la politique précédente.
--
-- Le test est porté par `exchange_open_to_me` : il lit des plafonds et des
-- attributions que la RLS de l'appelant ne lui montrerait pas, d'où
-- `security definer`. Il ne parle **que de l'appelant** (`auth.uid()`) : ouvert
-- à `authenticated` — une politique s'évalue sous les droits de qui lit —, il
-- n'est un oracle sur personne d'autre. Les fonctions qu'il appelle sont
-- déclarées plus bas ; plpgsql ne les résout qu'à l'exécution.
create function exchange_open_to_me(p_station uuid, p_shift uuid, p_requester uuid)
returns boolean
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  return auth.uid() is not null
     and p_requester <> auth.uid()
     and exchange_declared_available(auth.uid(), p_shift)
     and exchange_rule_check(p_station, auth.uid(), p_shift) is null;
end $$;

comment on function exchange_open_to_me(uuid, uuid, uuid) is
  'Vrai si l''appelant est de ceux à qui une demande « à la caserne » sur ce créneau est envoyée : disponibilité available déclarée, et règles du remplaçant tenues (pas déjà sur le créneau, plafonds, pas pris ailleurs). Support de shift_exchanges_select_candidate. Ticket 073.';

revoke execute on function exchange_open_to_me(uuid, uuid, uuid) from public, anon;
grant  execute on function exchange_open_to_me(uuid, uuid, uuid) to authenticated;

create policy "shift_exchanges_select_candidate"
  on shift_exchanges for select to authenticated
  using (
    target_id is null
    and status = 'open'
    and exchange_open_to_me(station_id, shift_id, requester_id)
  );

create policy "shift_exchanges_select_admin"
  on shift_exchanges for select to authenticated
  using (is_admin(station_id));

-- ===========================================================================
-- 4. Fonctions internes (aucune n'est appelable par un client)
-- ===========================================================================

-- Le début d'un créneau, en instant : la borne basse de `shift_window` (0040),
-- seule définition des heures réelles d'un créneau — le jour commence à
-- `day_start`, la nuit à `day_end`, dans le fuseau de la caserne. Le créneau
-- reste une `date` partout ailleurs ; seule l'échéance a besoin d'heure.
create function exchange_shift_start(p_shift uuid) returns timestamptz
language sql stable security definer
set search_path = public, pg_temp
as $$
  select lower(shift_window(s.date, s.slot, st.timezone, st.settings))
    from shifts s
    join stations st on st.id = s.station_id
   where s.id = p_shift;
$$;

comment on function exchange_shift_start(uuid) is
  'Instant de début d''un créneau : borne basse de shift_window (0040), dans le fuseau et aux heures de la caserne. Ticket 073.';

-- L'échéance d'une demande sur ce créneau : son début, moins
-- `exchange_deadline_hours`. Calculée **à la création** et gelée : changer le
-- réglage ne déplace pas les demandes déjà parties.
create function exchange_expires_at(p_shift uuid) returns timestamptz
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exchange_shift_start(s.id)
         - make_interval(hours => station_exchange_deadline_hours(s.station_id))
    from shifts s
   where s.id = p_shift;
$$;

comment on function exchange_expires_at(uuid) is
  'Échéance d''une demande d''échange sur un créneau : début du créneau moins settings.exchange_deadline_hours (24 h par défaut). Ticket 073.';

-- Le nom d'un membre dans sa caserne : surnom, puis prénom et nom, puis « Un
-- membre ». **Jamais l'adresse** : ce nom part dans des notifications lues par
-- des collègues, et une adresse n'est pas un nom.
create function exchange_member_name(p_station uuid, p_user uuid) returns text
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
           (select coalesce(
                     nullif(btrim(m.display_name), ''),
                     nullif(btrim(coalesce(pr.first_name, '') || ' ' || coalesce(pr.last_name, '')), ''))
              from profiles pr
              left join memberships m
                on m.station_id = p_station and m.user_id = pr.id
             where pr.id = p_user),
           'Un membre');
$$;

-- Les règles du remplaçant (docs/SCHEMA.md § 3, « Échanges d'astreintes ») :
-- membre actif, pas déjà sur ce créneau, plafonds `max_shifts` et
-- `max_weekends` du mois **comptés comme `v_member_load`** (proposées et
-- acceptées, la caserne seule, le mois du créneau). `p_leaving` est la garde
-- que la personne quitte dans le même mouvement — la garde rendue d'un
-- échange : elle ne compte plus, sinon un échange à l'intérieur d'un même mois
-- serait refusé à quelqu'un qui reste exactement à sa charge.
--
-- Rend `null` quand tout tient, sinon le code du premier refus.
create function exchange_rule_check(
  p_station uuid,
  p_user    uuid,
  p_shift   uuid,
  p_leaving uuid default null
) returns text
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  creneau            shifts;
  premier            date;
  suivant            date;
  plafond_astreintes integer;
  plafond_weekends   integer;
  unite              date;
begin
  if not exists (
    select 1 from memberships m
     where m.station_id = p_station and m.user_id = p_user and m.status = 'active'
  ) then
    return 'member_not_active';
  end if;

  select * into creneau from shifts where id = p_shift and station_id = p_station;
  if creneau.id is null then
    return 'shift_not_found';
  end if;

  if exists (
    select 1 from assignments a
     where a.shift_id = p_shift
       and a.user_id  = p_user
       and a.status in ('proposed', 'accepted')
  ) then
    return 'already_assigned';
  end if;

  -- Ticket 072 (migration 0040) : pas pris sur un créneau qui chevauche dans
  -- une autre caserne — proposé ou accepté, brouillon compris, aux heures et
  -- dans le fuseau de chaque caserne. `member_taken_elsewhere` ne rend qu'un
  -- booléen : rien de l'autre caserne ne sort d'ici. `request_exchange`,
  -- `respond_exchange` et `exchange_apply` passent tous par cette fonction.
  if member_taken_elsewhere(p_station, p_user, creneau.date, creneau.slot) then
    return 'taken_elsewhere';
  end if;

  premier := date_trunc('month', creneau.date)::date;
  suivant := (premier + interval '1 month')::date;

  select prefs.max_shifts, prefs.max_weekends
    into plafond_astreintes, plafond_weekends
    from availability_preferences prefs
    join schedules sc on sc.period_id = prefs.period_id
   where sc.id = creneau.schedule_id
     and prefs.station_id = p_station
     and prefs.user_id = p_user;

  if plafond_astreintes is not null and (
    select count(*)
      from assignments a
      join shifts s on s.id = a.shift_id and s.station_id = p_station
     where a.user_id    = p_user
       and a.station_id = p_station
       and a.status in ('proposed', 'accepted')
       and a.id is distinct from p_leaving
       and s.date >= premier
       and s.date <  suivant
  ) >= plafond_astreintes then
    return 'shift_quota_reached';
  end if;

  unite := unite_weekend(creneau.date);

  -- Même règle que `apply_auto_proposal` (0028) : un créneau de semaine ne
  -- coûte aucun weekend, un créneau dans une unité déjà couverte non plus.
  if plafond_weekends is not null and unite is not null and not exists (
    select 1
      from assignments a
      join shifts s on s.id = a.shift_id and s.station_id = p_station
     where a.user_id    = p_user
       and a.station_id = p_station
       and a.status in ('proposed', 'accepted')
       and a.id is distinct from p_leaving
       and s.date >= premier
       and s.date <  suivant
       and unite_weekend(s.date) = unite
  ) and (
    select count(distinct unite_weekend(s.date))
      from assignments a
      join shifts s on s.id = a.shift_id and s.station_id = p_station
     where a.user_id    = p_user
       and a.station_id = p_station
       and a.status in ('proposed', 'accepted')
       and a.id is distinct from p_leaving
       and s.date >= premier
       and s.date <  suivant
  ) >= plafond_weekends then
    return 'weekend_quota_reached';
  end if;

  return null;
end $$;

comment on function exchange_rule_check(uuid, uuid, uuid, uuid) is
  'Règles du remplaçant d''un échange : membre actif, pas déjà sur le créneau, plafonds max_shifts et max_weekends du mois comptés comme v_member_load, hors la garde quittée dans le même mouvement. Rend null ou le code du refus. Point d''extension du ticket 072 (pris ailleurs). Ticket 073.';

-- Vrai si le membre a déclaré une disponibilité `available` sur ce créneau.
create function exchange_declared_available(p_user uuid, p_shift uuid) returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from shifts s
      join availabilities av
        on av.station_id = s.station_id
       and av.date = s.date
       and av.slot = s.slot
     where s.id = p_shift
       and av.user_id = p_user
       and av.status = 'available'
  );
$$;

-- La charge utile commune d'une notification d'échange. Des codes et des
-- noms, jamais une phrase : le français vit dans `_shared/notification_content.ts`.
create function exchange_payload(p_exchange uuid) returns jsonb
language sql stable security definer
set search_path = public, pg_temp
as $$
  select jsonb_strip_nulls(jsonb_build_object(
           'exchange_id',    e.id,
           'kind',           e.kind,
           'broadcast',      e.target_id is null,
           'period',         to_char(s.date, 'YYYY-MM'),
           'shifts',         jsonb_build_array(jsonb_build_object(
                               'date', s.date, 'slot', s.slot)),
           'return_shift',   case when rs.id is not null then
                               jsonb_build_object('date', rs.date, 'slot', rs.slot) end,
           'requester_name', exchange_member_name(e.station_id, e.requester_id),
           'taker_name',     case when coalesce(e.taker_id, e.target_id) is not null then
                               exchange_member_name(e.station_id, coalesce(e.taker_id, e.target_id)) end))
    from shift_exchanges e
    join shifts s on s.id = e.shift_id
    left join shifts rs on rs.id = e.return_shift_id
   where e.id = p_exchange;
$$;

-- Clôt une demande ouverte — refus, annulation, expiration, échec — et dit à
-- qui elle concerne ce qui s'est passé. Une seule écriture de la règle « qui
-- est prévenu » (docs/WORKFLOWS.md § 8) :
--
--   destinataires = { A, le repreneur ou à défaut le destinataire désigné }
--                   moins l'acteur, qui sait ce qu'il vient de faire.
--
-- Une demande « à la caserne » encore ouverte n'a pas de second intéressé : les
-- disponibles qui l'ont vue passer ne la voient simplement plus.
--
-- `exchange_rejected` pour un refus, `exchange_closed` pour le reste, avec
-- `outcome` dans la charge utile. Clé de dédoublonnage par demande : une
-- demande ne se clôt qu'une fois (déclencheur `shift_exchanges_guard`).
create function exchange_close(
  p_exchange    uuid,
  p_status      exchange_status,
  p_reason_code text,
  p_actor       uuid default null,
  p_reason      text default null,
  p_reference   timestamptz default null,
  p_channels    text[] default null,
  -- Le motif précis, quand `p_reason_code` est volontairement neutre : écrit
  -- au seul `audit_log`, lu par les seuls administrateurs (« pris ailleurs »).
  p_detail      text default null
) returns shift_exchanges
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant       timestamptz := coalesce(p_reference, now());
  demande       shift_exchanges;
  destinataires uuid[];
  type_notif    notification_type;
  motif         text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if p_status not in ('rejected', 'cancelled', 'expired', 'failed') then
    raise exception 'exchange_close_invalid_status';
  end if;

  update shift_exchanges e
     set status      = p_status,
         reason_code = p_reason_code,
         reason      = motif,
         closed_at   = instant,
         -- Un refus garde son auteur, B ou l'administrateur ; un échec, celui
         -- de l'administrateur dont la validation n'a pas pu aboutir.
         decided_by  = case
                         when p_status = 'rejected' then p_actor
                         when p_status = 'failed'
                              and p_reason_code <> 'assignment_changed'
                              and p_actor is distinct from e.requester_id
                              and p_actor is distinct from coalesce(e.taker_id, e.target_id)
                         then p_actor
                       end,
         decided_at  = case when p_status in ('rejected', 'failed') then instant end
   where e.id = p_exchange
   returning * into demande;

  select array_agg(distinct u) into destinataires
    from unnest(array[demande.requester_id, coalesce(demande.taker_id, demande.target_id)]) as u
   where u is not null
     and u is distinct from p_actor;

  type_notif := case when p_status = 'rejected'
                     then 'exchange_rejected'::notification_type
                     else 'exchange_closed'::notification_type end;

  if destinataires is not null and cardinality(destinataires) > 0 then
    perform notify(
      type_notif,
      p_user_ids   => destinataires,
      p_station    => demande.station_id,
      p_payload    => exchange_payload(demande.id) || jsonb_strip_nulls(jsonb_build_object(
                        'outcome',     p_status,
                        'reason_code', p_reason_code,
                        'reason',      motif)),
      p_channels   => p_channels,
      p_dedupe_key => type_notif::text || ':' || demande.id::text);
  end if;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    demande.station_id, p_actor,
    'exchange.' || p_status::text, 'shift_exchange', demande.id,
    jsonb_strip_nulls(jsonb_build_object(
      'kind',          demande.kind,
      'assignment_id', demande.assignment_id,
      'requester_id',  demande.requester_id,
      'target_id',     demande.target_id,
      'taker_id',      demande.taker_id,
      'reason_code',   p_reason_code,
      'detail',        p_detail,
      'reason',        motif)));

  return demande;
end $$;

-- Prend les verrous d'une demande dans l'ordre du fichier : les attributions
-- (ordre des identifiants), puis la demande. Rend la demande relue sous verrou,
-- ou une ligne nulle si elle n'existe pas.
create function exchange_lock(p_exchange uuid) returns shift_exchanges
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  demande shift_exchanges;
begin
  -- Lecture sans verrou : seulement pour connaître les attributions, qui sont
  -- gelées dès la naissance de la demande (`exchange_key_immutable`).
  select * into demande from shift_exchanges where id = p_exchange;
  if demande.id is null then
    return demande;
  end if;

  perform 1
     from assignments a
    where a.id in (demande.assignment_id, demande.return_assignment_id)
    order by a.id
      for update;

  select * into demande from shift_exchanges where id = p_exchange for update;
  return demande;
end $$;

-- L'exécution d'une demande acceptée par son repreneur : **tout ou rien**.
--
-- L'appelant tient déjà les verrous des attributions et de la demande
-- (`exchange_lock`), et la demande est `accepted_by_peer`. Cette fonction
-- prend les plannings, revérifie **chaque** condition des deux mouvements, et
-- seulement ensuite écrit. Si une seule ne tient plus, rien n'est écrit sur
-- les attributions et la demande passe `failed` avec le motif : c'est le sens de
-- « les deux mouvements passent ou échouent ensemble ».
--
-- Les écritures, dans cet ordre :
--   1. B naît `accepted` sur la garde de A (il a déjà dit oui) — et A sur celle
--      de B pour un échange. Avant de retirer quoi que ce soit : le compte des
--      acceptations du créneau ne passe jamais par un trou, le planning validé
--      le reste ;
--   2. la demande passe `approved` **avant** que les anciennes attributions ne
--      bougent : le déclencheur `assignments_close_exchanges` ne la confond donc
--      pas avec une garde retirée par l'administrateur ;
--   3. l'ancienne garde de A passe `replaced`, `replaced_by` vers celle de B —
--      et la même chose en miroir ;
--   4. notifications, journal, réévaluation des plannings.
create function exchange_apply(p_exchange uuid, p_actor uuid, p_auto boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  demande         shift_exchanges;
  cedee           assignments;
  rendue          assignments;
  creneau         shifts;
  creneau_rendu   shifts;
  planning        schedules;
  planning_rendu  schedules;
  plannings       uuid[];
  code            text;
  nouvelle        uuid;
  nouvelle_rendue uuid;
  admins          uuid[];
  destinataires   jsonb;
  pl              uuid;
  receveur        uuid;
  detail          text;
begin
  select * into demande from shift_exchanges where id = p_exchange;
  select * into cedee   from assignments where id = demande.assignment_id;
  select * into creneau from shifts where id = demande.shift_id;

  if demande.kind = 'swap' then
    select * into rendue        from assignments where id = demande.return_assignment_id;
    select * into creneau_rendu from shifts where id = demande.return_shift_id;
  end if;

  -- Les plannings, dernier rang de l'ordre des verrous, par identifiant.
  plannings := array(
    select distinct x
      from unnest(array[creneau.schedule_id, creneau_rendu.schedule_id]) as x
     where x is not null
     order by x);

  perform 1 from schedules where id = any(plannings) order by id for update;

  -- Le verrou par pompier du ticket 072 (`apply_auto_proposal`, 0040), sur
  -- chaque pompier qui **reçoit** une garde — B, et A pour un échange —, dans
  -- l'ordre des identifiants, avant toute lecture des règles. Sans lui, une
  -- validation ici et un remplissage automatique dans une autre caserne
  -- liraient chacun « pas pris ailleurs » et poseraient la même personne sur
  -- deux créneaux qui se chevauchent. Il vient en dernier : le remplissage le
  -- prend après le verrou de **son** planning brouillon, qu'aucune fonction de
  -- ce fichier ne touche, et n'attend ensuite aucune ligne que nous tenons —
  -- aucun cycle possible.
  for receveur in
    select distinct u
      from unnest(case when demande.kind = 'swap'
                       then array[demande.taker_id, demande.requester_id]
                       else array[demande.taker_id] end) as u
     order by 1
  loop
    perform pg_advisory_xact_lock(
      hashtextextended('apply_auto_proposal:user:' || receveur::text, 0));
  end loop;

  select * into planning from schedules where id = creneau.schedule_id;
  if demande.kind = 'swap' then
    select * into planning_rendu from schedules where id = creneau_rendu.schedule_id;
  end if;

  -- ------------------------------------------------------------------
  -- Toutes les conditions, avant la moindre écriture.
  -- ------------------------------------------------------------------
  if not station_writable(demande.station_id) then
    code := 'station_suspended';
  elsif cedee.status <> 'accepted' or cedee.user_id <> demande.requester_id then
    code := 'assignment_not_accepted';
  elsif planning.status not in ('published', 'validated') then
    code := 'schedule_not_published';
  elsif demande.kind = 'swap'
        and (rendue.status <> 'accepted' or rendue.user_id <> demande.taker_id) then
    code := 'return_assignment_not_accepted';
  elsif demande.kind = 'swap'
        and planning_rendu.status not in ('published', 'validated') then
    code := 'schedule_not_published';
  elsif not exists (
    select 1 from memberships m
     where m.station_id = demande.station_id
       and m.user_id = demande.requester_id
       and m.status = 'active'
  ) then
    code := 'requester_not_active';
  else
    -- Les codes de `exchange_rule_check`, préfixés par la personne qu'ils
    -- concernent : c'est la liste fermée de `shift_exchanges_reason_code`.
    code := exchange_rule_check(demande.station_id, demande.taker_id,
                                creneau.id, demande.return_assignment_id);
    if code is not null then
      code := 'peer_' || replace(code, 'member_', '');
    elsif demande.kind = 'swap' then
      code := exchange_rule_check(demande.station_id, demande.requester_id,
                                  creneau_rendu.id, demande.assignment_id);
      if code is not null then
        code := 'requester_' || replace(code, 'member_', '');
      end if;
    end if;
  end if;

  -- « Pris ailleurs » ne se dit pas aux pompiers : `reason_code` est lisible
  -- par A et B (`shift_exchanges_select_party`) et part dans leur notification.
  -- Ils lisent le motif neutre « déjà sur ce créneau » ; le motif précis va au
  -- journal, que seuls les administrateurs lisent, et dans la réponse quand
  -- c'est un administrateur qui valide.
  if code is not null then
    detail := case when code like '%taken_elsewhere' then code end;
    code := replace(code, 'taken_elsewhere', 'already_assigned');
    perform exchange_close(p_exchange, 'failed', code, p_actor, null, null, null, detail);
    return jsonb_strip_nulls(jsonb_build_object(
      'ok', false, 'code', 'exchange_failed', 'reason_code', code,
      'detail', case when not p_auto then detail end,
      'exchange_id', p_exchange, 'status', 'failed'));
  end if;

  -- ------------------------------------------------------------------
  -- 1. Les nouvelles attributions, acceptées, horodatées.
  -- ------------------------------------------------------------------
  -- `created_by` et `was_available` sont posés ici : le déclencheur
  -- `assignments_trace_disponibilite` (0018) ne repasse pas derrière une
  -- écriture serveur. `created_by` est celui qui a fait aboutir l'échange :
  -- l'administrateur qui valide, ou le repreneur quand la validation est
  -- automatique.
  insert into assignments (
    station_id, shift_id, user_id, status, was_available,
    proposed_at, responded_at, created_by)
  values (
    demande.station_id, creneau.id, demande.taker_id, 'accepted',
    exchange_declared_available(demande.taker_id, creneau.id),
    now(), now(), p_actor)
  returning id into nouvelle;

  if demande.kind = 'swap' then
    insert into assignments (
      station_id, shift_id, user_id, status, was_available,
      proposed_at, responded_at, created_by)
    values (
      demande.station_id, creneau_rendu.id, demande.requester_id, 'accepted',
      exchange_declared_available(demande.requester_id, creneau_rendu.id),
      now(), now(), p_actor)
    returning id into nouvelle_rendue;
  end if;

  -- ------------------------------------------------------------------
  -- 2. La demande, validée.
  -- ------------------------------------------------------------------
  update shift_exchanges
     set status                   = 'approved',
         auto_approved            = p_auto,
         decided_by               = case when p_auto then null else p_actor end,
         decided_at               = now(),
         closed_at                = now(),
         new_assignment_id        = nouvelle,
         new_return_assignment_id = nouvelle_rendue
   where id = p_exchange
   returning * into demande;

  -- ------------------------------------------------------------------
  -- 3. Les anciennes gardes, remplacées, avec le fil.
  -- ------------------------------------------------------------------
  update assignments set status = 'replaced', replaced_by = nouvelle
   where id = cedee.id;

  if demande.kind = 'swap' then
    update assignments set status = 'replaced', replaced_by = nouvelle_rendue
     where id = rendue.id;
  end if;

  -- ------------------------------------------------------------------
  -- 4. Qui est prévenu : A et B, sauf l'acteur ; et, pour une validation
  -- automatique, les administrateurs actifs, « seulement informés »
  -- (décision 3). Une charge utile par destinataire : `audience` choisit le
  -- lien profond.
  -- ------------------------------------------------------------------
  if p_auto then
    select array_agg(m.user_id order by m.user_id) into admins
      from memberships m
     where m.station_id = demande.station_id
       and m.role = 'admin'
       and m.status = 'active'
       and m.user_id not in (demande.requester_id, demande.taker_id);
  end if;

  select jsonb_agg(jsonb_build_object('user_id', d.u, 'payload',
                   jsonb_build_object('audience', d.audience)))
    into destinataires
    from (
      select u, 'member' as audience
        from unnest(array[demande.requester_id, demande.taker_id]) as u
       where u is distinct from p_actor
      union all
      select u, 'admin'
        from unnest(coalesce(admins, array[]::uuid[])) as u
    ) as d;

  if destinataires is not null and jsonb_array_length(destinataires) > 0 then
    perform notify(
      'exchange_approved',
      p_station    => demande.station_id,
      p_payload    => exchange_payload(demande.id)
                      || jsonb_build_object('auto_approved', p_auto),
      p_recipients => destinataires,
      p_dedupe_key => 'exchange_approved:' || demande.id::text);
  end if;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    demande.station_id, p_actor,
    'exchange.approved', 'shift_exchange', demande.id,
    jsonb_strip_nulls(jsonb_build_object(
      'kind',                     demande.kind,
      'auto_approved',            p_auto,
      'requester_id',             demande.requester_id,
      'taker_id',                 demande.taker_id,
      'assignment_id',            demande.assignment_id,
      'new_assignment_id',        nouvelle,
      'return_assignment_id',     demande.return_assignment_id,
      'new_return_assignment_id', nouvelle_rendue,
      'shift_id',                 creneau.id,
      'date',                     creneau.date,
      'slot',                     creneau.slot)));

  foreach pl in array plannings loop
    perform schedule_reevaluer(pl);
  end loop;

  return jsonb_build_object(
    'ok',                       true,
    'exchange_id',              demande.id,
    'status',                   'approved',
    'auto_approved',            p_auto,
    'new_assignment_id',        nouvelle,
    'new_return_assignment_id', nouvelle_rendue);
end $$;

comment on function exchange_apply(uuid, uuid, boolean) is
  'Exécute une demande d''échange acceptée, en tout ou rien : verrous des plannings, revérification de chaque règle des deux mouvements, puis attributions accepted du repreneur (et du demandeur pour un échange), anciennes replaced avec replaced_by, notifications, audit, réévaluation. Sinon la demande passe failed avec son motif et rien d''autre ne change. Interne. Ticket 073.';

revoke execute on function exchange_shift_start(uuid)                          from public, anon, authenticated;
revoke execute on function exchange_expires_at(uuid)                           from public, anon, authenticated;
revoke execute on function exchange_member_name(uuid, uuid)                    from public, anon, authenticated;
revoke execute on function exchange_rule_check(uuid, uuid, uuid, uuid)         from public, anon, authenticated;
revoke execute on function exchange_declared_available(uuid, uuid)             from public, anon, authenticated;
revoke execute on function exchange_payload(uuid)                              from public, anon, authenticated;
revoke execute on function exchange_close(uuid, exchange_status, text, uuid, text, timestamptz, text[], text)
  from public, anon, authenticated;
revoke execute on function exchange_lock(uuid)                                 from public, anon, authenticated;
revoke execute on function exchange_apply(uuid, uuid, boolean)                 from public, anon, authenticated;

-- ===========================================================================
-- 5. Les fonctions des clients
-- ===========================================================================
-- Ouvertes à `authenticated`, comme `cancel_assignment` (0020) : l'identité
-- vient de `auth.uid()`, jamais d'un paramètre, et chaque fonction vérifie
-- elle-même le droit. Aucune Edge Function : il n'y a ni identité à établir
-- autrement, ni envoi postérieur à composer — les notifications partent par
-- `notify(...)` dans la transaction, comme pour `cancel_assignment`.
--
-- Refus métier en `{"ok": false, "code": …}`, jamais d'exception.

-- ---------------------------------------------------------------------------
-- request_exchange — A propose sa garde
-- ---------------------------------------------------------------------------
-- `p_target` nul : demande « à la caserne ». `p_return_assignment` non nul :
-- échange (exige `p_target`, et désigne une garde **acceptée** de B).
create function request_exchange(
  p_assignment        uuid,
  p_target            uuid default null,
  p_return_assignment uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  moi            uuid := auth.uid();
  cedee          assignments;
  rendue         assignments;
  creneau        shifts;
  creneau_rendu  shifts;
  planning       schedules;
  echeance       timestamptz;
  echeance_rendu timestamptz;
  code           text;
  candidats      uuid[];
  demande        shift_exchanges;
  file           uuid;
begin
  -- ------------------------------------------------------------------
  -- Refus sur lecture sans verrou.
  -- ------------------------------------------------------------------
  select * into cedee from assignments where id = p_assignment;
  -- Une attribution d'un autre est « introuvable » : on ne dit pas à un client
  -- qu'elle existe.
  if cedee.id is null or moi is null or cedee.user_id <> moi then
    return jsonb_build_object('ok', false, 'code', 'assignment_not_found');
  end if;

  if not is_member(cedee.station_id) then
    return jsonb_build_object('ok', false, 'code', 'not_member');
  end if;

  if not station_writable(cedee.station_id) then
    return jsonb_build_object('ok', false, 'code', 'station_suspended');
  end if;

  if p_return_assignment is not null and p_target is null then
    return jsonb_build_object('ok', false, 'code', 'swap_requires_target');
  end if;

  if p_target is not null then
    if p_target = moi then
      return jsonb_build_object('ok', false, 'code', 'target_is_self');
    end if;
    if not exists (
      select 1 from memberships m
       where m.station_id = cedee.station_id
         and m.user_id = p_target
         and m.status = 'active'
    ) then
      return jsonb_build_object('ok', false, 'code', 'target_not_member');
    end if;
  end if;

  if p_return_assignment is not null then
    select * into rendue from assignments where id = p_return_assignment;
    if rendue.id is null
       or rendue.station_id <> cedee.station_id
       or rendue.user_id <> p_target then
      return jsonb_build_object('ok', false, 'code', 'return_assignment_not_found');
    end if;
  end if;

  -- ------------------------------------------------------------------
  -- Les verrous : les attributions, par identifiant.
  -- ------------------------------------------------------------------
  perform 1 from assignments a
   where a.id in (p_assignment, p_return_assignment)
   order by a.id
     for update;

  select * into cedee   from assignments where id = p_assignment;
  select * into creneau from shifts where id = cedee.shift_id;
  select * into planning from schedules where id = creneau.schedule_id;

  if cedee.status <> 'accepted' then
    return jsonb_build_object('ok', false, 'code', 'assignment_not_accepted',
                              'status', cedee.status);
  end if;

  if planning.status not in ('published', 'validated') then
    return jsonb_build_object('ok', false, 'code', 'schedule_not_published',
                              'status', planning.status);
  end if;

  echeance := exchange_expires_at(creneau.id);
  if echeance <= now() then
    return jsonb_build_object('ok', false, 'code', 'too_late', 'expires_at', echeance);
  end if;

  if p_return_assignment is not null then
    select * into rendue        from assignments where id = p_return_assignment;
    select * into creneau_rendu from shifts where id = rendue.shift_id;
    select * into planning      from schedules where id = creneau_rendu.schedule_id;

    if rendue.status <> 'accepted' then
      return jsonb_build_object('ok', false, 'code', 'return_assignment_not_accepted',
                                'status', rendue.status);
    end if;

    if planning.status not in ('published', 'validated') then
      return jsonb_build_object('ok', false, 'code', 'schedule_not_published',
                                'status', planning.status);
    end if;

    echeance_rendu := exchange_expires_at(creneau_rendu.id);
    if echeance_rendu <= now() then
      return jsonb_build_object('ok', false, 'code', 'too_late', 'expires_at', echeance_rendu);
    end if;
    echeance := least(echeance, echeance_rendu);
  end if;

  -- Une seule demande ouverte par attribution, qu'elle y soit la garde cédée
  -- ou la garde rendue. Sous le verrou des deux attributions : deux demandes
  -- simultanées sur la même garde ne passent pas toutes les deux.
  if exists (
    select 1 from shift_exchanges e
     where e.status in ('open', 'accepted_by_peer')
       and (e.assignment_id in (p_assignment, p_return_assignment)
            or e.return_assignment_id in (p_assignment, p_return_assignment))
  ) then
    return jsonb_build_object('ok', false, 'code', 'exchange_already_open');
  end if;

  -- ------------------------------------------------------------------
  -- Les règles du remplaçant, et celles de A pour un échange.
  -- ------------------------------------------------------------------
  if p_target is not null then
    -- `taken_elsewhere` devient `already_assigned` : A n'a pas à apprendre
    -- qu'un collègue est pris dans une autre caserne (même règle partout côté
    -- pompier).
    code := replace(exchange_rule_check(cedee.station_id, p_target, creneau.id, p_return_assignment),
                    'taken_elsewhere', 'already_assigned');
    if code is not null then
      return jsonb_build_object('ok', false, 'code', code, 'who', 'target');
    end if;

    if p_return_assignment is not null then
      code := replace(exchange_rule_check(cedee.station_id, moi, creneau_rendu.id, p_assignment),
                      'taken_elsewhere', 'already_assigned');
      if code is not null then
        return jsonb_build_object('ok', false, 'code', code, 'who', 'requester');
      end if;
    end if;
  else
    -- « À la caserne » : les membres actifs qui ont déclaré une disponibilité
    -- `available` sur ce créneau **et** que les règles laissent reprendre la
    -- garde. Ce sont eux, et eux seuls, qui reçoivent la demande.
    select array_agg(m.user_id order by m.user_id) into candidats
      from memberships m
     where m.station_id = cedee.station_id
       and m.status = 'active'
       and m.user_id <> moi
       and exchange_declared_available(m.user_id, creneau.id)
       and exchange_rule_check(cedee.station_id, m.user_id, creneau.id) is null;
  end if;

  -- ------------------------------------------------------------------
  -- La demande.
  -- ------------------------------------------------------------------
  insert into shift_exchanges (
    station_id, kind, requester_id, assignment_id, shift_id,
    target_id, return_assignment_id, return_shift_id, expires_at)
  values (
    cedee.station_id,
    case when p_return_assignment is null then 'give' else 'swap' end::exchange_kind,
    moi, cedee.id, creneau.id,
    p_target, p_return_assignment, creneau_rendu.id, echeance)
  returning * into demande;

  if p_target is not null then
    candidats := array[p_target];
  end if;

  if candidats is not null and cardinality(candidats) > 0 then
    file := notify(
      'exchange_requested',
      p_user_ids   => candidats,
      p_station    => demande.station_id,
      p_payload    => exchange_payload(demande.id)
                      || jsonb_build_object('expires_at', demande.expires_at),
      p_dedupe_key => 'exchange_requested:' || demande.id::text);
  end if;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    demande.station_id, moi,
    'exchange.requested', 'shift_exchange', demande.id,
    jsonb_strip_nulls(jsonb_build_object(
      'kind',                 demande.kind,
      'assignment_id',        demande.assignment_id,
      'shift_id',             demande.shift_id,
      'date',                 creneau.date,
      'slot',                 creneau.slot,
      'target_id',            demande.target_id,
      'return_assignment_id', demande.return_assignment_id,
      'candidates',           coalesce(cardinality(candidats), 0))));

  return jsonb_build_object(
    'ok',          true,
    'exchange_id', demande.id,
    'status',      demande.status,
    'kind',        demande.kind,
    'broadcast',   demande.target_id is null,
    'expires_at',  demande.expires_at,
    -- Mis en file, pas livré (docs/SCHEMA.md § 5) : le nombre de pompiers à qui
    -- la demande **va** parvenir. Zéro pour une demande à la caserne que
    -- personne n'est libre de reprendre — l'écran doit le dire.
    'notified',    case when file is null then 0 else coalesce(cardinality(candidats), 0) end);
end $$;

comment on function request_exchange(uuid, uuid, uuid) is
  'A propose sa garde acceptée (planning publié ou validé, avant l''échéance) : à un collègue (p_target) ou à la caserne (null), en cession ou en échange contre une garde acceptée du collègue (p_return_assignment). Une seule demande ouverte par attribution. Notifie le destinataire ou les disponibles. Ouverte à authenticated. Ticket 073.';

revoke execute on function request_exchange(uuid, uuid, uuid) from public, anon;
grant  execute on function request_exchange(uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- respond_exchange — B répond
-- ---------------------------------------------------------------------------
-- `p_accept = true` : B reprend la garde. Le premier qui accepte une demande
-- « à la caserne » la prend ; le second trouve `exchange_not_open`.
-- `p_accept = false` : B décline une demande **qui lui est adressée** ; une
-- demande à la caserne ne se décline pas, on la laisse passer.
--
-- Après l'accord : la demande attend un administrateur, **sauf** si la caserne
-- a activé `exchange_auto_approve` **et** que le remplaçant avait déclaré une
-- disponibilité `available` sur ce créneau — pour un échange, chacun sur le
-- créneau qu'il reprend. Elle est alors exécutée dans la même transaction.
create function respond_exchange(p_exchange uuid, p_accept boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  moi     uuid := auth.uid();
  demande shift_exchanges;
  code    text;
  auto    boolean;
  admins  uuid[];
begin
  select * into demande from shift_exchanges where id = p_exchange;

  -- Ce que l'appelant n'a pas le droit de voir, il ne peut pas y répondre — et
  -- on ne lui dit pas que la demande existe.
  if demande.id is null
     or moi is null
     or moi = demande.requester_id
     or (demande.target_id is not null and demande.target_id <> moi)
     or not is_member(demande.station_id) then
    return jsonb_build_object('ok', false, 'code', 'exchange_not_found');
  end if;

  if not p_accept and demande.target_id is null then
    return jsonb_build_object('ok', false, 'code', 'not_target');
  end if;

  -- Accepter change le planning : refusé en lecture seule. Décliner clôt une
  -- demande sans rien changer d'autre : permis.
  if p_accept and not station_writable(demande.station_id) then
    return jsonb_build_object('ok', false, 'code', 'station_suspended');
  end if;

  demande := exchange_lock(p_exchange);

  if demande.status <> 'open' then
    return jsonb_build_object('ok', false, 'code', 'exchange_not_open',
                              'status', demande.status);
  end if;

  if demande.expires_at <= now() then
    perform exchange_close(p_exchange, 'expired', 'deadline_reached');
    return jsonb_build_object('ok', false, 'code', 'exchange_expired');
  end if;

  if not p_accept then
    perform exchange_close(p_exchange, 'rejected', 'peer_declined', moi);
    return jsonb_build_object('ok', true, 'exchange_id', p_exchange, 'status', 'rejected');
  end if;

  -- La garde de A n'est plus à lui : le déclencheur du § 6 a déjà fait échouer
  -- la demande, et on ne passerait pas le test de statut ci-dessus. Le test
  -- reste, au cas où une écriture l'aurait contourné.
  if not exists (
    select 1 from assignments a
     where a.id = demande.assignment_id
       and a.user_id = demande.requester_id
       and a.status = 'accepted'
  ) then
    perform exchange_close(p_exchange, 'failed', 'assignment_not_accepted', moi);
    return jsonb_build_object('ok', false, 'code', 'exchange_failed',
                              'reason_code', 'assignment_not_accepted');
  end if;

  -- À la caserne : seulement les disponibles déclarés (décision 1).
  if demande.target_id is null
     and not exchange_declared_available(moi, demande.shift_id) then
    return jsonb_build_object('ok', false, 'code', 'not_available');
  end if;

  -- Les règles du repreneur : un refus qui le concerne ne clôt pas la demande,
  -- il lui est dit. Il peut décliner, un autre peut la prendre.
  code := replace(exchange_rule_check(demande.station_id, moi, demande.shift_id,
                                      demande.return_assignment_id),
                  'taken_elsewhere', 'already_assigned');
  if code is not null then
    return jsonb_build_object('ok', false, 'code', code);
  end if;

  update shift_exchanges
     set status = 'accepted_by_peer', taker_id = moi, accepted_at = now()
   where id = p_exchange
   returning * into demande;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    demande.station_id, moi,
    'exchange.accepted', 'shift_exchange', demande.id,
    jsonb_build_object('kind', demande.kind,
                       'assignment_id', demande.assignment_id,
                       'requester_id', demande.requester_id));

  auto := station_exchange_auto_approve(demande.station_id)
          and exchange_declared_available(moi, demande.shift_id)
          and (demande.kind = 'give'
               or exchange_declared_available(demande.requester_id, demande.return_shift_id));

  if auto then
    return exchange_apply(p_exchange, moi, true);
  end if;

  -- Validation par l'administrateur : les administrateurs actifs, sauf
  -- l'acteur (docs/WORKFLOWS.md § 8).
  select array_agg(m.user_id order by m.user_id) into admins
    from memberships m
   where m.station_id = demande.station_id
     and m.role = 'admin'
     and m.status = 'active'
     and m.user_id <> moi;

  if admins is not null and cardinality(admins) > 0 then
    perform notify(
      'exchange_accepted',
      p_user_ids   => admins,
      p_station    => demande.station_id,
      p_payload    => exchange_payload(demande.id),
      p_dedupe_key => 'exchange_accepted:' || demande.id::text);
  end if;

  return jsonb_build_object(
    'ok',            true,
    'exchange_id',   demande.id,
    'status',        'accepted_by_peer',
    'auto_approved', false);
end $$;

comment on function respond_exchange(uuid, boolean) is
  'B accepte (p_accept) ou décline une demande d''échange. Le premier repreneur d''une demande à la caserne la prend. Après accord : validation automatique si settings.exchange_auto_approve et disponibilité déclarée, sinon notification des administrateurs. Ouverte à authenticated. Ticket 073.';

revoke execute on function respond_exchange(uuid, boolean) from public, anon;
grant  execute on function respond_exchange(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- decide_exchange — l'administrateur valide ou refuse
-- ---------------------------------------------------------------------------
create function decide_exchange(
  p_exchange uuid,
  p_approve  boolean,
  p_reason   text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  moi     uuid := auth.uid();
  demande shift_exchanges;
begin
  select * into demande from shift_exchanges where id = p_exchange;

  if demande.id is null or moi is null or not is_member(demande.station_id) then
    return jsonb_build_object('ok', false, 'code', 'exchange_not_found');
  end if;

  if not is_admin(demande.station_id) then
    return jsonb_build_object('ok', false, 'code', 'not_admin');
  end if;

  if p_reason is not null and char_length(p_reason) > 500 then
    return jsonb_build_object('ok', false, 'code', 'reason_too_long');
  end if;

  demande := exchange_lock(p_exchange);

  if demande.status <> 'accepted_by_peer' then
    return jsonb_build_object('ok', false, 'code', 'exchange_not_pending',
                              'status', demande.status);
  end if;

  -- Un administrateur qui est A ou B ne tranche pas sa propre demande — ni
  -- pour la valider, ni pour la refuser (B se dédirait par cette porte) —,
  -- **sauf s'il est le seul administrateur actif** : la caserne n'a alors
  -- personne d'autre, et l'accord de B comme la décision restent journalisés.
  if moi in (demande.requester_id, demande.taker_id)
     and exists (
       select 1 from memberships m
        where m.station_id = demande.station_id
          and m.role = 'admin'
          and m.status = 'active'
          and m.user_id <> moi) then
    return jsonb_build_object('ok', false, 'code', 'cannot_decide_own_exchange');
  end if;

  if demande.expires_at <= now() then
    perform exchange_close(p_exchange, 'expired', 'deadline_reached');
    return jsonb_build_object('ok', false, 'code', 'exchange_expired');
  end if;

  if not p_approve then
    perform exchange_close(p_exchange, 'rejected', 'admin_rejected', moi, p_reason);
    return jsonb_build_object('ok', true, 'exchange_id', p_exchange, 'status', 'rejected');
  end if;

  -- La suspension est vérifiée **dans** `exchange_apply` : une validation
  -- refusée pour lecture seule passe `failed` avec ce motif (règle du ticket).
  return exchange_apply(p_exchange, moi, false);
end $$;

comment on function decide_exchange(uuid, boolean, text) is
  'L''administrateur valide (exécution en tout ou rien, exchange_apply) ou refuse (motif facultatif) une demande d''échange acceptée par le repreneur. Ouverte à authenticated, gardée par is_admin. Ticket 073.';

revoke execute on function decide_exchange(uuid, boolean, text) from public, anon;
grant  execute on function decide_exchange(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- cancel_exchange — A retire sa demande
-- ---------------------------------------------------------------------------
-- Tant qu'elle n'est pas validée : `open` ou `accepted_by_peer`. Permis en
-- lecture seule, comme décliner : une clôture ne change aucun planning.
create function cancel_exchange(p_exchange uuid) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  moi     uuid := auth.uid();
  demande shift_exchanges;
begin
  select * into demande from shift_exchanges where id = p_exchange;

  if demande.id is null or moi is null or demande.requester_id <> moi then
    return jsonb_build_object('ok', false, 'code', 'exchange_not_found');
  end if;

  demande := exchange_lock(p_exchange);

  if demande.status not in ('open', 'accepted_by_peer') then
    return jsonb_build_object('ok', false, 'code', 'exchange_not_open',
                              'status', demande.status);
  end if;

  perform exchange_close(p_exchange, 'cancelled', 'requester_cancelled', moi);
  return jsonb_build_object('ok', true, 'exchange_id', p_exchange, 'status', 'cancelled');
end $$;

comment on function cancel_exchange(uuid) is
  'Le demandeur retire sa demande d''échange tant qu''elle n''est pas validée. Prévient le destinataire ou le repreneur. Ouverte à authenticated. Ticket 073.';

revoke execute on function cancel_exchange(uuid) from public, anon;
grant  execute on function cancel_exchange(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- exchangeable_shifts_of — les gardes de B que A peut demander en retour
-- ---------------------------------------------------------------------------
-- Sur un planning seulement **publié**, A ne lit pas les attributions de B
-- (`assignments_select_station_validated` n'ouvre qu'un planning validé) : sans
-- cette fonction, l'écran ne pourrait pas composer un échange (brief de design
-- du ticket, § 9, point bloquant). Elle rend, pour chaque caserne où l'appelant
-- **et** B sont membres actifs, les gardes de B :
--   - `accepted`, et rien d'autre — ni ses propositions en attente, ni ses
--     refus, ni ses annulations ;
--   - d'un planning publié ou validé, dont l'échéance d'échange n'est pas
--     passée ;
--   - qui ne sont **pas déjà engagées** dans une demande ouverte (cédées ou
--     rendues) : une garde engagée n'est pas proposable (décision du brief) ;
--   - sur un créneau que l'appelant ne tient pas déjà.
-- Les colonnes sont exactement ce que `request_exchange` demande, plus de quoi
-- l'afficher. Aucune autre donnée de B, aucune donnée d'une caserne que
-- l'appelant ne partage pas avec lui.
--
-- Vide — jamais une erreur — pour soi-même, pour un inconnu ou pour un membre
-- d'une autre caserne.
create function exchangeable_shifts_of(p_peer uuid)
returns table (
  assignment_id uuid,
  shift_id      uuid,
  station_id    uuid,
  date          date,
  slot          slot_type,
  expires_at    timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select a.id, s.id, a.station_id, s.date, s.slot, exchange_expires_at(s.id)
    from memberships moi
    join memberships pair
      on pair.station_id = moi.station_id
     and pair.user_id = p_peer
     and pair.status = 'active'
    join assignments a
      on a.station_id = moi.station_id
     and a.user_id = p_peer
     and a.status = 'accepted'
    join shifts s on s.id = a.shift_id
    join schedules sc on sc.id = s.schedule_id
   where moi.user_id = auth.uid()
     and moi.status = 'active'
     and p_peer <> auth.uid()
     and sc.status in ('published', 'validated')
     and exchange_expires_at(s.id) > now()
     and not exists (
       select 1 from shift_exchanges e
        where e.status in ('open', 'accepted_by_peer')
          and (e.assignment_id = a.id or e.return_assignment_id = a.id))
     and not exists (
       select 1 from assignments deja
        where deja.shift_id = a.shift_id
          and deja.user_id = auth.uid()
          and deja.status in ('proposed', 'accepted'))
   order by s.date, s.slot;
$$;

comment on function exchangeable_shifts_of(uuid) is
  'Gardes acceptées et à venir du collègue p_peer, dans les casernes partagées avec l''appelant, que celui-ci peut demander en échange : planning publié ou validé, échéance non passée, garde non engagée dans une demande ouverte, créneau que l''appelant ne tient pas. Vide sinon. Ouverte à authenticated. Ticket 073.';

revoke execute on function exchangeable_shifts_of(uuid) from public, anon;
grant  execute on function exchangeable_shifts_of(uuid) to authenticated;

-- ===========================================================================
-- 6. Une garde retirée par l'administrateur fait échouer la demande
-- ===========================================================================
-- `reassign_shift` et `cancel_assignment` (0020) retirent une garde acceptée
-- sans rien savoir des échanges. Sans ce déclencheur, la demande resterait
-- ouverte sur une garde qui n'est plus à A : les disponibles la verraient, l'un
-- d'eux dirait oui, et l'échec n'arriverait qu'à la validation. Elle échoue
-- donc **dans la transaction** de l'administrateur, motif `assignment_changed`,
-- et les intéressés en sont prévenus — sauf l'acteur.
--
-- `exchange_apply` passe sa propre demande en `approved` avant de retirer les
-- gardes : elle n'est pas ouverte, ce déclencheur ne la touche pas.
--
-- Ordre des verrous : la ligne d'attribution est déjà tenue par l'`update` qui
-- nous réveille, la demande vient après. Le sens du fichier.
create function assignments_close_exchanges() returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  ouverte uuid;
begin
  for ouverte in
    select e.id
      from shift_exchanges e
     where e.status in ('open', 'accepted_by_peer')
       and (e.assignment_id = new.id or e.return_assignment_id = new.id)
     order by e.id
       for update
  loop
    perform exchange_close(ouverte, 'failed', 'assignment_changed', auth.uid());
  end loop;
  return null;
end $$;

comment on function assignments_close_exchanges() is
  'Fait échouer (assignment_changed) les demandes d''échange ouvertes sur une garde qui sort de accepted — réattribution ou annulation par l''administrateur —, dans la même transaction, et prévient les intéressés. Ticket 073.';

revoke execute on function assignments_close_exchanges() from public, anon, authenticated;

create trigger assignments_close_exchanges
  after update of status on assignments
  for each row
  when (old.status = 'accepted' and new.status is distinct from 'accepted')
  execute function assignments_close_exchanges();

-- ===========================================================================
-- 7. L'expiration
-- ===========================================================================
-- Une demande expire à son échéance (`expires_at`, posée à la création) : au
-- début du créneau, et au plus tard `exchange_deadline_hours` avant. Les
-- fonctions des clients vérifient déjà l'échéance — une demande échue ne se
-- prend ni ne se valide, même si la tâche est en retard. La tâche, elle, la
-- **clôt** et prévient les intéressés.
--
-- Le prévenir à 03:00 n'est pas une bonne idée : hors de la fenêtre locale de
-- la caserne (`station_notification_window`, 0033), la notification part sur le
-- seul canal `inapp` — elle est dans la Boîte au réveil, sans sonnerie.
--
-- `skip locked` : une demande qu'une fonction cliente tient en ce moment sera
-- reprise au tir suivant, ou close par la fonction elle-même.
create function cron_expire_exchanges(p_reference timestamptz default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant timestamptz := coalesce(p_reference, now());
  echue   record;
  total   integer := 0;
begin
  for echue in
    select e.id, e.station_id
      from shift_exchanges e
     where e.status in ('open', 'accepted_by_peer')
       and e.expires_at <= instant
     order by e.expires_at, e.id
       for update skip locked
  loop
    perform exchange_close(
      echue.id, 'expired', 'deadline_reached', null, null, instant,
      case when station_notification_window(echue.station_id, instant)
           then null
           else array['inapp'] end);
    total := total + 1;
  end loop;

  return total;
end $$;

comment on function cron_expire_exchanges(timestamptz) is
  'Tâche expire_exchanges (docs/SCHEMA.md § 8) : clôt en expired les demandes d''échange ouvertes dont l''échéance est passée et prévient les intéressés (inapp seul hors de la fenêtre horaire locale). Idempotente. Renvoie le nombre de demandes closes. Ticket 073.';

revoke execute on function cron_expire_exchanges(timestamptz) from public, anon, authenticated;

-- Toutes les dix minutes, à la minute 2 : aucune des tâches horaires ne tire à
-- ces minutes-là. `cron.schedule` est un upsert : la migration est rejouable.
do $$
begin
  perform cron.schedule(
    'expire_exchanges',
    '2-59/10 * * * *',
    'select public.cron_expire_exchanges();');
end $$;
