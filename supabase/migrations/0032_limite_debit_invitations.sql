-- 0032 — Limiter le débit des invitations. Ticket 038, relevé en revue du 006.
-- Référence : docs/SCHEMA.md sections 2.1, 2.4, 2.18, 3, 4 et 10.
--
-- Ce que 0009 et 0025 laissent passer
-- -----------------------------------
-- `create_invitation` contrôle **qui** invite, jamais **combien de fois**. Or la
-- fonction fait deux choses qui coûtent cher quand on les répète : elle fait
-- naître un compte `auth.users` confirmé (les inscriptions libres sont fermées,
-- c'est le seul chemin) et elle déclenche un courriel depuis le domaine d'envoi
-- du produit. L'Edge Function borne un appel à vingt adresses ; elle ne borne
-- pas le nombre d'appels. Un administrateur — ou un jeton d'administrateur volé
-- — envoie donc autant de courriels qu'il veut, à des adresses qu'il choisit,
-- depuis notre réputation d'expéditeur. Le jour où le domaine est signalé, ce
-- sont les invitations de toutes les casernes qui tombent en spam.
--
-- Ce qui est posé ici
-- -------------------
--   1. `invitation_rate_events` : une ligne par courriel d'invitation réellement
--      parti, par caserne et par acteur. Un compteur en base, donc rejouable en
--      intégration continue, contrairement à un compteur en mémoire de Deno qui
--      ne survivrait ni à un redémarrage ni à une seconde instance.
--   2. La clé `invitation_hourly_limit` dans `stations.settings`, **facultative**
--      et ajoutée à la liste blanche de `station_settings_valid` (0011). Elle est
--      facultative pour une raison précise : la contrainte `stations_settings_valide`
--      n'est pas revalidée par `create or replace`, mais la **première mise à jour**
--      d'une caserne existante la rejouerait. Exiger la clé condamnerait toutes
--      les casernes déjà écrites à ne plus jamais pouvoir changer un réglage.
--   3. `invitation_rate_limit()` : la décision, avec la date de réessai.
--   4. La branche de refus dans `create_invitation` : code `rate_limited`, et une
--      ligne `invitation.rate_limited` dans le journal d'audit.
--   5. `prune_invitation_rate_events()`, branchée sur la tâche `prune_retention`
--      de 0030 : un compteur sans purge est une table qui grossit sans fin.
--
-- Portées et plafonds
-- -------------------
-- Le compteur d'un administrateur est **par caserne** : c'est la caserne qui
-- règle son plafond, et deux administrateurs d'une même caserne partagent le même
-- budget — sinon il suffirait de nommer un second administrateur pour doubler.
--
-- Le compteur du super-administrateur est **par acteur**, toutes casernes
-- confondues. Le mesurer par caserne ne le mesurerait pas du tout : il invite le
-- premier administrateur d'une caserne **qu'il vient de créer** (ticket 031),
-- dont le compteur est vierge par construction. Son plafond est plus haut, parce
-- qu'ouvrir vingt casernes dans l'après-midi d'une convention est un usage réel.

-- ===========================================================================
-- 1. Le compteur
-- ===========================================================================
-- Ce que la table ne porte pas est aussi important que ce qu'elle porte : pas
-- d'adresse invitée. `invitations` la garde le temps de l'invitation et
-- `audit_log` la garde trois ans ; la recopier ici serait une troisième
-- conservation de la même donnée personnelle pour compter jusqu'à soixante.
create table invitation_rate_events (
  id          uuid primary key default gen_random_uuid(),
  station_id  uuid not null references stations(id) on delete cascade,
  actor_id    uuid not null references profiles(id) on delete cascade,
  created_at  timestamptz not null default now()
);

-- Les deux portées de comptage, chacune son index : la fenêtre est toujours
-- « la dernière heure », donc toujours la tête de l'index.
create index invitation_rate_events_station_idx
  on invitation_rate_events (station_id, created_at desc);
create index invitation_rate_events_actor_idx
  on invitation_rate_events (actor_id, created_at desc);

comment on table invitation_rate_events is
  'Un courriel d''invitation réellement envoyé (création ou renvoi). Sert au seul plafond horaire de create_invitation (ticket 038). Ne porte aucune adresse : invitations et audit_log les gardent déjà.';
comment on column invitation_rate_events.actor_id is
  'Qui a invité. Compté par acteur pour le super-administrateur, qui invite dans des casernes neuves dont le compteur est vierge.';

alter table invitation_rate_events enable row level security;

-- Lecture : les administrateurs de la caserne, et eux seuls. Ils supportent le
-- refus, ils doivent pouvoir voir ce qui l'a produit. Écriture : personne côté
-- client — la seule main qui écrit est `create_invitation`, en security definer.
create policy "invitation_rate_events_select_admin"
  on invitation_rate_events for select to authenticated
  using (is_admin(station_id));

revoke insert, update, delete, truncate on invitation_rate_events
  from anon, authenticated;
revoke all on invitation_rate_events from anon;

-- ===========================================================================
-- 2. Le plafond dans les paramètres de la caserne
-- ===========================================================================
-- `station_settings_valid` est la liste blanche de 0011 : une clé absente de la
-- liste est refusée. Ajouter le plafond sans toucher à cette fonction rendrait
-- le réglage impossible à poser. La fonction est donc réécrite **à l'identique**
-- sauf trois lignes : la clé dans `connues` (et pas dans `obligatoires`), ses
-- bornes, et le commentaire.
--
-- 500 par heure en borne haute : c'est le point où le réglage cesse de protéger
-- quoi que ce soit. 1 en borne basse : une caserne qui veut fermer le robinet
-- écrit 1, pas 0 — un plafond à zéro n'est pas un débit, c'est une interdiction,
-- et elle se dit en désactivant les administrateurs.
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
    'invitation_hourly_limit'
  ];
  -- `invitation_hourly_limit` n'est **pas** obligatoire : les casernes écrites
  -- avant cette migration ne l'ont pas, et la contrainte les rejouerait à leur
  -- première mise à jour. Absente, c'est INVITATION_HOURLY_LIMIT_DEFAUT qui
  -- s'applique (voir station_invitation_hourly_limit ci-dessous).
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
  'Valide le document stations.settings (docs/SCHEMA.md § 2.1). Support de la contrainte stations_settings_valide et miroir exact de la validation côté application. invitation_hourly_limit (ticket 038) est facultative : les casernes écrites avant 0032 restent valides.';

-- Le plafond effectif d'une caserne. 60 par défaut : une caserne de cinquante
-- pompiers s'invite en une fois — trois lots de vingt, le maximum d'un appel —
-- sans jamais toucher le plafond, tandis qu'une machine à courriels s'arrête au
-- premier quart d'heure.
create function station_invitation_hourly_limit(p_station uuid) returns integer
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select nullif(s.settings ->> 'invitation_hourly_limit', '')::integer
       from stations s where s.id = p_station),
    60);
$$;

comment on function station_invitation_hourly_limit(uuid) is
  'Plafond horaire d''invitations d''une caserne : settings.invitation_hourly_limit, ou 60 quand la clé est absente (docs/SCHEMA.md § 2.1, ticket 038).';

revoke execute on function station_invitation_hourly_limit(uuid) from public, anon;

-- ===========================================================================
-- 3. La décision
-- ===========================================================================
-- Fenêtre glissante d'une heure, pas un compteur remis à zéro à l'heure ronde :
-- un seau qui se vide à 15:00 se remplit deux fois entre 14:59 et 15:01.
--
-- `retry_at` n'est pas « dans une heure » : c'est le moment où le plus ancien des
-- `plafond` derniers envois sort de la fenêtre, donc le moment exact où un envoi
-- redevient possible. C'est ce que l'administrateur lit à l'écran, et une phrase
-- qui dit « réessaie dans une heure » alors que ce sera dans trois minutes est
-- une phrase fausse.
create function invitation_rate_limit(
  p_station uuid,
  p_actor   uuid,
  p_now     timestamptz default null
) returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
-- Volatile, et pas `stable` : une fonction stable réutilise l'instantané de la
-- requête appelante. Appelée deux fois dans la même instruction — un lot rendu
-- par un `select … from unnest(adresses)` — elle ne verrait pas ce que le
-- premier appel vient d'écrire, et compterait deux fois zéro.
declare
  fenetre       constant interval := interval '1 hour';
  -- Le super-administrateur ouvre les casernes : vingt casernes dans une
  -- après-midi de convention, c'est vingt invitations plus les renvois.
  plafond_super constant integer := 200;
  instant       timestamptz := coalesce(p_now, now());
  v_super       boolean;
  v_portee      text;
  v_plafond     integer;
  v_utilise     integer;
  v_plus_ancien timestamptz;
  v_retry       timestamptz;
begin
  -- Reconnu par la table, jamais par `is_super_admin()` : cette fonction lit
  -- `auth.uid()`, qui est nul sous la clé de service (même raison qu'en 0025).
  v_super := exists (select 1 from super_admins where user_id = p_actor);

  if v_super then
    v_portee  := 'actor';
    v_plafond := plafond_super;
    select count(*) into v_utilise
      from invitation_rate_events e
     where e.actor_id = p_actor
       and e.created_at > instant - fenetre;
  else
    v_portee  := 'station';
    v_plafond := station_invitation_hourly_limit(p_station);
    select count(*) into v_utilise
      from invitation_rate_events e
     where e.station_id = p_station
       and e.created_at > instant - fenetre;
  end if;

  if v_utilise < v_plafond then
    return jsonb_build_object(
      'allowed',        true,
      'scope',          v_portee,
      'limit',          v_plafond,
      'used',           v_utilise,
      'remaining',      v_plafond - v_utilise,
      'window_minutes', (extract(epoch from fenetre) / 60)::integer
    );
  end if;

  select min(s.created_at) into v_plus_ancien
  from (
    select e.created_at
      from invitation_rate_events e
     where ((v_portee = 'actor'   and e.actor_id   = p_actor)
         or (v_portee = 'station' and e.station_id = p_station))
       and e.created_at > instant - fenetre
     order by e.created_at desc
     limit greatest(v_plafond, 1)
  ) s;

  v_retry := coalesce(v_plus_ancien, instant) + fenetre;

  return jsonb_build_object(
    'allowed',             false,
    'scope',               v_portee,
    'limit',               v_plafond,
    'used',                v_utilise,
    'remaining',           0,
    'window_minutes',      (extract(epoch from fenetre) / 60)::integer,
    'retry_at',            v_retry,
    'retry_after_seconds', greatest(ceil(extract(epoch from (v_retry - instant)))::integer, 1)
  );
end $$;

comment on function invitation_rate_limit(uuid, uuid, timestamptz) is
  'Plafond horaire d''invitations (ticket 038) : par caserne pour un administrateur, par acteur pour le super-administrateur. Rend allowed, limit, used, remaining, et pour un refus retry_at et retry_after_seconds.';

revoke execute on function invitation_rate_limit(uuid, uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function invitation_rate_limit(uuid, uuid, timestamptz) to service_role;

-- ===========================================================================
-- 4. create_invitation : le refus, la trace, et le compteur
-- ===========================================================================
-- Corps de 0025 à l'identique, plus trois choses :
--
--   a) un verrou consultatif de transaction sur la portée comptée. Sans lui,
--      vingt appels concurrents lisent tous le même `count` et passent tous :
--      un plafond qui se contourne en ouvrant deux onglets n'est pas un plafond.
--      Le verrou porte sur la caserne (ou sur l'acteur pour le super-admin), pas
--      sur une table : deux casernes n'ont aucune raison de s'attendre.
--   b) le contrôle de débit, placé **après** `already_member` et `invalid_email`.
--      Un appel qui n'enverrait aucun courriel ne consomme pas de budget et ne
--      mérite pas un refus de débit : le plafond protège l'envoi, pas la lecture.
--   c) l'écriture de la ligne de compteur **au moment où l'invitation est
--      écrite**, création comme renvoi. Un renvoi envoie un courriel ; il compte.
--      Comme l'écriture est par adresse, un lot de vingt compte pour vingt.
create or replace function create_invitation(
  p_station    uuid,
  p_email      text,
  p_role       membership_role,
  p_invited_by uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email      text := lower(btrim(coalesce(p_email, '')));
  v_station    stations%rowtype;
  v_inviter    profiles%rowtype;
  v_user_id    uuid;
  v_statut     membership_status;
  v_existante  invitations%rowtype;
  v_renvoi     boolean;
  v_super      boolean;
  v_debit      jsonb;
  v_inv        invitations%rowtype;
begin
  if v_email = '' or v_email !~ '^[^@[:space:]]+@[^@[:space:].]+(\.[^@[:space:].]+)+$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_email');
  end if;

  select * into v_station from stations where id = p_station;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'station_not_found');
  end if;

  v_super := exists (select 1 from super_admins where user_id = p_invited_by);

  if not v_super and not exists (
    select 1 from memberships
    where station_id = p_station and user_id = p_invited_by
      and status = 'active' and role = 'admin'
  ) then
    return jsonb_build_object('ok', false, 'code', 'not_admin');
  end if;

  if not station_writable(p_station) then
    return jsonb_build_object('ok', false, 'code', 'station_suspended');
  end if;

  select p.id into v_user_id from profiles p where lower(p.email) = v_email;

  if v_user_id is not null then
    select m.status into v_statut
    from memberships m
    where m.station_id = p_station and m.user_id = v_user_id;

    if v_statut = 'active' then
      return jsonb_build_object('ok', false, 'code', 'already_member');
    end if;
  end if;

  -- (a) Le verrou : compter puis écrire doit être indivisible.
  perform pg_advisory_xact_lock(
    hashtext('invitation_rate_limit'),
    hashtext(case when v_super then p_invited_by::text else p_station::text end));

  -- (b) Le plafond.
  v_debit := invitation_rate_limit(p_station, p_invited_by);
  if not (v_debit ->> 'allowed')::boolean then
    -- Une seule ligne d'audit par caserne et par fenêtre. Un lot de vingt
    -- adresses refusées écrirait sinon vingt fois la même phrase, et c'est
    -- exactement le moment où le journal doit rester lisible.
    if not exists (
      select 1 from audit_log a
       where a.station_id = p_station
         and a.action = 'invitation.rate_limited'
         and a.created_at > now() - interval '1 hour'
    ) then
      insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
      values (
        p_station, p_invited_by, 'invitation.rate_limited', 'invitations', null,
        (v_debit - 'allowed') || jsonb_build_object('email', v_email)
      );
    end if;

    return jsonb_build_object('ok', false, 'code', 'rate_limited')
        || (v_debit - 'allowed');
  end if;

  select * into v_existante
  from invitations
  where station_id = p_station and lower(email) = v_email and accepted_at is null
  for update;
  v_renvoi := found;

  if v_renvoi then
    update invitations
       set role       = p_role,
           invited_by = p_invited_by,
           expires_at = now() + interval '14 days'
     where id = v_existante.id
    returning * into v_inv;
  else
    begin
      insert into invitations (station_id, email, role, invited_by)
      values (p_station, v_email, p_role, p_invited_by)
      returning * into v_inv;
    exception when unique_violation then
      return jsonb_build_object('ok', false, 'code', 'conflict');
    end;
  end if;

  -- (c) Le compteur : une ligne par courriel qui part.
  insert into invitation_rate_events (station_id, actor_id)
  values (p_station, p_invited_by);

  select * into v_inviter from profiles where id = p_invited_by;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    p_station, p_invited_by,
    case when v_renvoi then 'invitation.resent' else 'invitation.created' end,
    'invitations', v_inv.id,
    jsonb_strip_nulls(jsonb_build_object(
      'email', v_email, 'role', p_role, 'expires_at', v_inv.expires_at,
      'by_super_admin', case when v_super then true else null end))
  );

  return jsonb_build_object(
    'ok', true,
    'resent', v_renvoi,
    'token', v_inv.token,
    'account_exists', v_user_id is not null,
    'invitee_id', v_user_id,
    'invitation', jsonb_build_object(
      'id', v_inv.id,
      'station_id', v_inv.station_id,
      'email', v_inv.email,
      'role', v_inv.role,
      'expires_at', v_inv.expires_at,
      'created_at', v_inv.created_at
    ),
    'station', jsonb_build_object(
      'id', v_station.id, 'name', v_station.name, 'slug', v_station.slug
    ),
    'inviter', jsonb_build_object(
      'id', v_inviter.id,
      'first_name', v_inviter.first_name,
      'last_name', v_inviter.last_name,
      'email', v_inviter.email
    )
  );
end;
$$;

comment on function create_invitation(uuid, text, membership_role, uuid) is
  'Crée ou prolonge l''invitation d''une adresse dans une caserne. Invitant autorisé : admin actif de la caserne, ou super-admin (ticket 031). Plafonnée à settings.invitation_hourly_limit envois par heure et par caserne, davantage pour le super-admin (ticket 038) : au-delà, code rate_limited avec retry_at. Renvoie le token : service_role uniquement.';

revoke all on function create_invitation(uuid, text, membership_role, uuid)
  from public, anon, authenticated;
grant execute on function create_invitation(uuid, text, membership_role, uuid) to service_role;

-- ===========================================================================
-- 5. Purge : le compteur n'est pas une archive
-- ===========================================================================
-- Sept jours, alors que la fenêtre fait une heure : ce qui reste après la
-- soixantième minute ne sert plus à compter, il sert à répondre à « qui a envoyé
-- deux cents invitations mardi dernier ». Une semaine suffit à cette question ;
-- au-delà, `audit_log` la garde, avec les adresses en prime.
create function prune_invitation_rate_events(
  p_reference timestamptz default null,
  p_days      integer     default 7
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant    timestamptz := coalesce(p_reference, now());
  supprimees integer;
begin
  delete from invitation_rate_events e
   where e.created_at < instant - make_interval(days => p_days);
  get diagnostics supprimees = row_count;
  return supprimees;
end $$;

comment on function prune_invitation_rate_events(timestamptz, integer) is
  'Supprime les compteurs d''invitation de plus de p_days jours (7). La fenêtre du plafond fait une heure ; le reste n''est qu''une trace courte, doublée par audit_log. Appelée par la tâche prune_retention.';

revoke execute on function prune_invitation_rate_events(timestamptz, integer)
  from public, anon, authenticated;

-- La tâche hebdomadaire de 0030 gagne une table. Le `cron.schedule` n'est pas
-- retouché : la commande planifiée est `select public.cron_prune_retention();`
-- et c'est le corps de la fonction qui change.
create or replace function cron_prune_retention(p_reference timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant timestamptz := coalesce(p_reference, now());
begin
  return jsonb_build_object(
    'audit_log',              prune_audit_log(instant),
    'invitations',            prune_invitations(instant),
    'invitation_rate_events', prune_invitation_rate_events(instant),
    'notification_outbox',    prune_notification_outbox(instant),
    'push_tokens',            prune_push_tokens(instant),
    'stripe_events',          prune_stripe_events(instant));
end $$;

comment on function cron_prune_retention(timestamptz) is
  'Tâche prune_retention (docs/SCHEMA.md § 8) : applique les durées de conservation de docs/RGPD.md qui ne relèvent pas de prune_notifications — journal d''audit (3 ans), invitations (30 jours après expiration, 3 ans après acceptation), compteurs d''invitation (7 jours), file d''attente traitée (30 jours), appareils inactifs (1 an), événements de paiement appliqués (90 jours). Renvoie le nombre de lignes supprimées par table.';

revoke execute on function cron_prune_retention(timestamptz)
  from public, anon, authenticated;
