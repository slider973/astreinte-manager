-- 0018 — La construction du planning en brouillon.
-- Ticket 017. Référence : docs/SCHEMA.md sections 2.8, 2.9, 2.10, 4, 5, 6 et 9 ;
-- docs/WORKFLOWS.md sections 2 et 3 ; docs/PRD.md sections 5.3, 6.4 et 7 ;
-- design/017-brouillon-attribution.md sections 7.1 et 7.2.
--
-- Ce que cette migration ajoute, et pourquoi
-- ------------------------------------------
--   1. `station_required_count(settings, date, slot)` : la règle de l'effectif
--      requis d'un créneau, surcharges comprises, écrite **une fois**.
--   2. `create_schedule(caserne, période)` : crée le planning du mois et ses
--      créneaux, idempotente.
--   3. `assignments_trace_disponibilite` : `was_available` et `created_by`
--      posés par la base, jamais déclarés par le client.
--   4. `assignments_audit_hors_dispo` : le volet `assignments` de
--      `audit_admin_actions` (docs/SCHEMA.md § 5, « viendra avec les
--      plannings »), action `assignment.force`.
--   5. `assignments_delete_admin` restreinte au **brouillon** : après
--      publication, une attribution s'annule, elle ne se supprime pas.
--   6. `v_schedule_progress`, la troisième vue du § 6, que le § 10 rattache à
--      ce ticket.
--   7. L'inscription d'`assignments` dans la publication `supabase_realtime`,
--      la première de la base.
--
-- Ce qui existait déjà et n'est pas réécrit
-- -----------------------------------------
--   - Les trois tables (0004) et leurs contraintes, dont
--     `assignments_active_uniq (shift_id, user_id) where status in
--     ('proposed','accepted')` : c'est **elle** qui interdit d'attribuer deux
--     fois le même membre au même créneau. Rien ne la double ici ; le client
--     traduit son `23505` en une phrase française.
--   - Les politiques de 0007, durcies par 0008 : un admin insère, modifie et
--     supprime déjà les créneaux et les attributions de sa caserne, avec
--     contrôle de cohérence du `station_id`. Seule la suppression change.
--   - `assignments_member_transition` (0008) : la réponse d'un membre. Elle ne
--     concerne pas le brouillon, où aucun membre ne voit rien.

-- ===========================================================================
-- 1. L'effectif requis d'un créneau
-- ===========================================================================
-- `docs/SCHEMA.md § 2.1` : `required_day` et `required_night` donnent l'effectif
-- par défaut, `required_overrides` les exceptions —
-- `{"sat": {"day": 2}, "2026-12-31": {"night": 3}}`. Une surcharge peut ne fixer
-- qu'un seul créneau : celui qu'elle laisse vide garde la valeur par défaut.
--
-- L'ordre de résolution est **date, puis jour de semaine, puis défaut**. Une
-- surcharge datée est une décision prise pour ce jour-là (le réveillon, une
-- manifestation) : elle gagne contre la règle hebdomadaire, sans quoi elle ne
-- servirait à rien les samedis.
--
-- Fonction **pure** : elle ne lit aucune table, ne révèle rien, et son exécution
-- reste ouverte à `authenticated` — comme les quatre fonctions de validation des
-- réglages (0011). Un écran qui voudrait prévisualiser un effectif n'a pas à
-- refaire la règle en Dart.
--
-- `immutable` pour de vrai : la clé ISO est construite par `lpad` et non par
-- `to_char`, dont le résultat dépend de `DateStyle` — la même raison qui a fait
-- écrire `station_settings_cle_surcharge_valide` avec `make_date` (0011).
create function station_required_count(
  p_settings jsonb, p_date date, p_slot slot_type
) returns integer
language plpgsql
immutable
strict
parallel safe
set search_path = public, pg_temp
as $$
declare
  jours      constant text[] := array['mon','tue','wed','thu','fri','sat','sun'];
  sous_cle   constant text := case p_slot when 'day' then 'day' else 'night' end;
  defaut_cle constant text := case p_slot when 'day' then 'required_day' else 'required_night' end;
  surcharges constant jsonb := coalesce(p_settings -> 'required_overrides', '{}'::jsonb);
  cle_date   text;
  valeur     jsonb;
begin
  cle_date := lpad(extract(year  from p_date)::int::text, 4, '0') || '-'
           || lpad(extract(month from p_date)::int::text, 2, '0') || '-'
           || lpad(extract(day   from p_date)::int::text, 2, '0');

  valeur := surcharges -> cle_date -> sous_cle;

  if valeur is null then
    valeur := surcharges -> jours[extract(isodow from p_date)::int] -> sous_cle;
  end if;

  if valeur is null then
    valeur := p_settings -> defaut_cle;
  end if;

  -- Le défaut de dernier recours est 1, celui de la colonne `required_count`
  -- (0004). Il ne sert que pour des réglages amputés que la contrainte
  -- `stations_settings_valide` interdit déjà : mieux vaut un créneau à pourvoir
  -- qu'une erreur au milieu de la création d'un mois.
  return coalesce((valeur #>> '{}')::int, 1);
end $$;

comment on function station_required_count(jsonb, date, slot_type) is
  'Effectif requis d''un créneau : surcharge datée, sinon surcharge de jour de semaine, sinon required_day / required_night. Fonction pure, employée à la création d''un planning.';

grant execute on function station_required_count(jsonb, date, slot_type) to authenticated;

-- ===========================================================================
-- 2. create_schedule — le planning du mois et ses créneaux
-- ===========================================================================
-- `security definer`, comme `create_period` (0012) et pour la même raison : le
-- droit se dit **une fois**, en haut de la fonction, au lieu d'être déduit d'un
-- `is_admin` réévalué sur soixante-deux insertions.
--
-- **`required_count` est une copie, pas une référence** (docs/SCHEMA.md § 2.9).
-- Les réglages de la caserne sont lus **ici, une fois** ; ensuite chaque créneau
-- porte son propre effectif et rien ne le réécrit. C'est le critère du ticket
-- 010 : changer `required_day` n'affecte que les plannings créés après.
--
-- Idempotente à deux niveaux — le planning (`unique (station_id, period_id)`) et
-- les créneaux (`unique (schedule_id, date, slot)`). Deux adjoints qui cliquent
-- en même temps obtiennent le même planning, et rejouer la création ne double
-- aucun créneau. Elle ne **remplace** jamais un effectif existant : un créneau
-- déjà créé n'est pas retouché, même si les réglages ont changé depuis.
create function create_schedule(p_station uuid, p_period uuid)
returns schedules
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caserne  stations;
  periode  periods;
  resultat schedules;
  premier  date;
  suivant  date;
begin
  if not is_admin(p_station) then
    raise exception 'forbidden'
      using hint = 'Seul un administrateur de la caserne construit son planning.';
  end if;

  if not station_writable(p_station) then
    raise exception 'station_suspended'
      using hint = 'L''abonnement de la caserne est suspendu : l''application est en lecture seule.';
  end if;

  select * into periode from periods where id = p_period and station_id = p_station;
  if periode.id is null then
    raise exception 'period_not_found'
      using hint = 'Cette période n''existe pas ou n''appartient pas à cette caserne.';
  end if;

  select * into caserne from stations where id = p_station;

  insert into schedules (station_id, period_id, created_by)
  values (p_station, p_period, auth.uid())
  on conflict (station_id, period_id) do nothing
  returning * into resultat;

  if resultat.id is null then
    select * into resultat from schedules
     where station_id = p_station and period_id = p_period;
  end if;

  premier := make_date(periode.year, periode.month, 1);
  suivant := (premier + interval '1 month')::date;

  -- Un créneau par jour du mois et par valeur de `slot_type` : la longueur du
  -- mois vient du calendrier, jamais d'un 31 supposé, et les créneaux viennent
  -- de l'enum, jamais d'une liste recopiée.
  insert into shifts (station_id, schedule_id, date, slot, required_count)
  select
    p_station,
    resultat.id,
    j::date,
    s.slot,
    station_required_count(caserne.settings, j::date, s.slot)
  from generate_series(premier, suivant - 1, interval '1 day') j
  cross join (select unnest(enum_range(null::slot_type)) as slot) s
  on conflict (schedule_id, date, slot) do nothing;

  return resultat;
end $$;

comment on function create_schedule(uuid, uuid) is
  'Crée le planning d''un mois et ses créneaux (chaque jour × jour/nuit), required_count copié depuis les réglages de la caserne et leurs surcharges. Idempotente : ne double aucun créneau et ne réécrit aucun effectif existant.';

revoke execute on function create_schedule(uuid, uuid) from public, anon;
grant  execute on function create_schedule(uuid, uuid) to authenticated;

-- ===========================================================================
-- 3. was_available et created_by : la base les pose, le client ne les choisit pas
-- ===========================================================================
-- `docs/SCHEMA.md § 2.10` : `was_available` vaut faux quand le membre a été
-- attribué hors de ses disponibilités. C'est la trace qui déclenche l'audit
-- (§ 5) et qui dira, au ticket 019, pourquoi un refus était prévisible.
--
-- Laissée au client, elle ne vaudrait rien : il suffirait d'envoyer `true` pour
-- faire disparaître l'attribution forcée du journal de la caserne. Exactement
-- le raisonnement de `availabilities_trace_auteur` (0012) sur `set_by` — « la
-- trace de l'auteur ne se choisit pas ». Le fait est relu ici, à l'insertion,
-- dans la table des disponibilités.
--
-- **`security invoker`, et c'est un choix, pas un oubli.** La lecture des
-- disponibilités se fait sous les droits de l'appelant, ce qui ne cache rien :
-- le seul rôle que la politique `assignments_insert_admin` laisse insérer est un
-- admin de la caserne, et un admin lit déjà toutes les disponibilités de sa
-- caserne (0007). Surtout, `security definer` ferait de `current_user` le
-- **propriétaire de la fonction** et non le rôle appelant : le test « écriture
-- serveur ? » ci-dessous répondrait « oui » pour tout le monde, et la trace ne
-- serait jamais posée. Même raison, et même forme, que
-- `availabilities_trace_auteur` (0012) et `assignments_member_transition` (0008).
--
-- Il ne s'applique qu'à l'**insertion**. La publication (ticket 019) et les
-- réponses des membres modifient des lignes existantes : recalculer alors une
-- disponibilité saisie entre-temps réécrirait l'histoire.
create function assignments_trace_disponibilite() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  creneau shifts;
begin
  -- Écritures serveur (seed, rôle de service, Edge Functions) : elles savent ce
  -- qu'elles écrivent et n'ont pas d'`auth.uid()`. Même convention que
  -- `memberships_guard_admin` (0010) et `assignments_member_transition` (0008).
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  new.created_by := auth.uid();

  select * into creneau from shifts where id = new.shift_id;
  if creneau.id is null then
    -- La clé étrangère le dira mieux que nous, une ligne plus bas.
    return new;
  end if;

  new.was_available := exists (
    select 1 from availabilities a
    where a.station_id  = new.station_id
      and a.user_id     = new.user_id
      and a.date        = creneau.date
      and a.slot        = creneau.slot
      and a.status      = 'available'
  );

  return new;
end $$;

comment on function assignments_trace_disponibilite() is
  'Impose assignments.created_by = auth.uid() et calcule was_available depuis les disponibilités réelles, pour toute insertion client : la trace d''une attribution forcée ne se choisit pas.';

revoke execute on function assignments_trace_disponibilite() from public, anon, authenticated;

-- Nommé pour passer avant `assignments_audit_hors_dispo` et
-- `assignments_set_updated_at` (ordre alphabétique des déclencheurs).
create trigger assignments_trace_disponibilite
  before insert on assignments
  for each row execute function assignments_trace_disponibilite();

-- ---------------------------------------------------------------------------
-- Le volet `assignments` de l'audit des actions d'administration.
-- docs/SCHEMA.md § 5 : « sur `assignments` quand `was_available = false` ».
-- docs/PRD.md § 7.7 : toute action d'admin sur les données d'un membre —
-- attribution hors disponibilité comprise — est tracée.
--
-- La clause `when` porte le test : la fonction n'est pas appelée pour les
-- attributions ordinaires, qui sont l'immense majorité.
-- ---------------------------------------------------------------------------
create function assignments_audit_hors_dispo() returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  creneau shifts;
begin
  select * into creneau from shifts where id = new.shift_id;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    new.station_id, new.created_by,
    'assignment.force', 'assignment', new.id,
    jsonb_build_object(
      'user_id',  new.user_id,
      'shift_id', new.shift_id,
      'date',     creneau.date,
      'slot',     creneau.slot,
      'status',   new.status)
  );
  return null;
end $$;

comment on function assignments_audit_hors_dispo() is
  'Journalise assignment.force quand un membre est attribué hors de ses disponibilités (docs/SCHEMA.md § 5, docs/PRD.md § 7.7).';

revoke execute on function assignments_audit_hors_dispo() from public, anon, authenticated;

create trigger assignments_audit_hors_dispo
  after insert on assignments
  for each row
  when (new.was_available is false)
  execute function assignments_audit_hors_dispo();

-- ===========================================================================
-- 4. Supprimer une attribution : en brouillon, et nulle part ailleurs
-- ===========================================================================
-- docs/WORKFLOWS.md § 3 : en brouillon, une attribution existe avec
-- `status = 'proposed'` et `proposed_at is null` — rien n'est parti, il n'y a
-- rien à conserver. La retirer, c'est la supprimer.
--
-- Après publication, la même attribution a été notifiée : elle s'annule
-- (`cancelled`) ou se remplace (`replaced`), et elle reste pour l'historique
-- (docs/PRD.md § 7.6 : « l'historique n'est jamais supprimé »). La politique de
-- 0007 laissait pourtant un admin supprimer n'importe quelle attribution, à
-- n'importe quel statut : le principe ne tenait qu'à la discipline des écrans.
-- Ce ticket est celui où la suppression devient une action réelle, c'est donc
-- ici qu'on la borne.
--
-- Les suppressions en cascade (caserne, planning, membre supprimés) ne passent
-- pas par cette politique : les actions d'intégrité référentielle s'exécutent
-- sous l'identité du propriétaire de la table et ne consultent pas la RLS.
drop policy "assignments_delete_admin" on assignments;

create policy "assignments_delete_admin"
  on assignments for delete to authenticated
  using (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1
      from shifts sh
      join schedules sc on sc.id = sh.schedule_id
      where sh.id = assignments.shift_id
        and sh.station_id = assignments.station_id
        and sc.status = 'draft'
    )
  );

-- ===========================================================================
-- 5. v_schedule_progress — avancement d'un planning
-- ===========================================================================
-- docs/SCHEMA.md § 6 et § 10 : la troisième vue du schéma, rattachée à ce
-- ticket. Une ligne par planning.
--
-- `shifts_filled` compte les créneaux **couverts par des attributions actives**
-- (`proposed` ou `accepted`), c'est-à-dire au sens de la construction : en
-- brouillon, rien n'est encore accepté et un planning complet doit se voir
-- complet. La validation, elle, se juge sur les seules acceptations
-- (`schedule_auto_validate`, ticket 019) et ne se lit pas ici.
--
-- `assignments_late` : proposées depuis plus de `late_report_hours` et toujours
-- sans réponse. `proposed_at is null` — tout le brouillon — n'est jamais en
-- retard : c'est la règle de docs/WORKFLOWS.md § 3, celle que suivent aussi les
-- crons de relance.
--
-- `security_invoker`, comme `v_member_load` (0017) : la vue n'accorde aucun
-- droit. Un admin voit les plannings de sa caserne ; un membre ne voit que les
-- plannings publiés ou validés, et n'y compte que les attributions que la RLS
-- lui montre — une vue partielle, pas une fuite.
create view v_schedule_progress
with (security_invoker = true) as
  select
    sc.id                                   as schedule_id,
    sc.station_id                           as station_id,
    sc.period_id                            as period_id,
    sc.status                               as status,
    count(sh.id)::integer                   as shifts_total,
    count(sh.id) filter (
      where coalesce(c.actives, 0) >= sh.required_count
    )::integer                              as shifts_filled,
    coalesce(sum(c.pending),  0)::integer   as assignments_pending,
    coalesce(sum(c.accepted), 0)::integer   as assignments_accepted,
    coalesce(sum(c.declined), 0)::integer   as assignments_declined,
    coalesce(sum(c.late),     0)::integer   as assignments_late
  from schedules sc
  join stations st on st.id = sc.station_id
  left join shifts sh on sh.schedule_id = sc.id and sh.station_id = sc.station_id
  left join lateral (
    select
      count(*) filter (where a.status in ('proposed', 'accepted')) as actives,
      count(*) filter (where a.status = 'proposed')                as pending,
      count(*) filter (where a.status = 'accepted')                as accepted,
      count(*) filter (where a.status = 'declined')                as declined,
      count(*) filter (
        where a.status = 'proposed'
          and a.proposed_at is not null
          and a.proposed_at < now() - make_interval(
                hours => coalesce((st.settings ->> 'late_report_hours')::int, 72))
      )                                                            as late
    from assignments a
    where a.shift_id = sh.id
      and a.station_id = sh.station_id
  ) c on true
  group by sc.id, sc.station_id, sc.period_id, sc.status;

comment on view v_schedule_progress is
  'Par planning : créneaux totaux, créneaux couverts par des attributions actives, attributions en attente, acceptées, refusées, et en retard de réponse au-delà de late_report_hours. security_invoker.';

revoke all on v_schedule_progress from anon;
grant select on v_schedule_progress to authenticated;

-- ===========================================================================
-- 6. Le temps réel sur les attributions
-- ===========================================================================
-- docs/SCHEMA.md § 9 : « Realtime activé sur `assignments`, `schedules`,
-- `notifications` uniquement ». Aucune table n'était encore inscrite ; celle-ci
-- est la première, et c'est ce ticket qui en a besoin — deux adjoints qui
-- construisent le même mois doivent voir le travail de l'autre.
--
-- Ce que la revue du ticket 006 a établi, et qu'il faut vérifier table par
-- table : **une publication diffuse toutes les colonnes, et les politiques RLS
-- filtrent des lignes, pas des colonnes.** C'est ce qui a interdit d'y mettre
-- `invitations`, dont le `token` est un porteur de droits caché au rôle
-- `authenticated` par un `grant` de colonne.
--
-- `assignments` n'est pas dans ce cas :
--   - aucun `grant` de colonne restrictif ne la concerne — ce que
--     `authenticated` peut lire par `select`, il peut le recevoir ici ;
--   - aucune colonne n'est un secret ni un porteur de droits ; la plus sensible
--     humainement, `decline_reason`, ne part qu'avec des lignes que l'abonné a
--     déjà le droit de lire ;
--   - les événements sont filtrés ligne à ligne par les politiques de `select`
--     existantes : un membre ne reçoit **rien** d'un planning en brouillon,
--     puisque aucune politique ne lui en donne la lecture (docs/WORKFLOWS.md
--     § 2, « `draft` est invisible des membres »).
--
-- **L'identité de réplique reste `default`**, et c'est la décision qui compte.
-- La charge utile d'un `delete` n'est pas filtrée par les politiques ; avec
-- `replica identity full`, chaque retrait d'attribution diffuserait toutes les
-- colonnes de la ligne supprimée à tous les abonnés. Avec `default`, il ne
-- diffuse que la clé primaire — un uuid opaque, sans caserne, sans membre et
-- sans date. Le client garde donc ses attributions indexées par identifiant
-- pour savoir quel créneau redessiner. L'instruction est écrite bien qu'elle
-- soit le défaut de PostgreSQL : c'est une décision de sécurité, elle doit se
-- voir dans la migration et échouer bruyamment si quelqu'un la change ailleurs.
alter table assignments replica identity default;

-- `shifts` n'y entre pas : le § 9 ne l'y autorise pas, et un changement
-- d'effectif requis est un événement rare et délibéré, que « Rafraîchir »
-- rattrape. Payer un canal pour une écriture par mois serait un mauvais marché.
do $publication$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'Publication supabase_realtime absente : rien à inscrire.';
    return;
  end if;

  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'assignments'
  ) then
    return;
  end if;

  alter publication supabase_realtime add table assignments;
exception
  -- Sur un projet hébergé, la publication appartient à `supabase_admin`. Une
  -- migration qui échouerait là bloquerait tout le déploiement pour un canal de
  -- confort : même garde-fou que les tâches `pg_cron` de 0012.
  when insufficient_privilege then
    raise notice 'Droits insuffisants pour inscrire assignments dans supabase_realtime.';
end $publication$;
