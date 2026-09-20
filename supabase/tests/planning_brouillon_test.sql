-- Tests de la construction du planning en brouillon (migration 0018, ticket 017).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
-- 1. `station_required_count` : le défaut, la surcharge de jour de semaine, la
--    surcharge datée qui gagne contre elle, le créneau qu'une surcharge laisse
--    de côté, l'effectif zéro qui est une valeur et non une absence.
-- 2. `create_schedule` : un créneau par jour et par créneau, effectif hérité des
--    réglages et de leurs surcharges, idempotence du planning **et** des
--    créneaux, et le critère du ticket 010 — changer l'effectif requis de la
--    caserne ne touche **aucun** créneau déjà créé.
-- 3. Les attributions : `was_available` calculé par la base et non déclaré par
--    le client, `created_by` imposé, l'audit `assignment.force` écrit quand et
--    seulement quand l'attribution est hors disponibilité, et la double
--    attribution refusée par la contrainte d'unicité.
-- 4. Le retrait : une attribution de brouillon se supprime, une attribution de
--    planning publié **non** — elle s'annule et reste pour l'historique.
-- 5. `v_schedule_progress` : créneaux totaux, créneaux couverts, attributions
--    par statut, et les retards qui ignorent le brouillon (`proposed_at` nul).
-- 6. Le temps réel : `assignments` inscrite dans `supabase_realtime`, identité
--    de réplique restée `default` — une suppression ne diffuse qu'une clé.
-- 7. Les droits : un membre ne voit rien d'un brouillon, l'admin voisin non
--    plus, et `anon` n'appelle rien.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : une caserne « CIS Brouillon » et une caserne voisine, sur l'année
-- 2027 que le seed ne touche pas.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_plan;

create function tests_plan.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

create function tests_plan.egal(p_obtenu anyelement, p_attendu anyelement, p_label text) returns void
language plpgsql as $$
begin
  if p_obtenu is distinct from p_attendu then
    raise exception 'ECHEC : % — obtenu [%], attendu [%]', p_label, p_obtenu, p_attendu;
  end if;
  raise notice '  ok   % = %', p_label, coalesce(p_obtenu::text, 'NULL');
end $$;

-- `refuse` : l'instruction doit lever l'erreur nommée, et pas une autre. Une
-- assertion qui se contente de « ça a échoué » passe encore le jour où la
-- fonction échoue pour une faute de frappe.
create function tests_plan.refuse(p_sql text, p_erreur text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — aucune erreur levée, % attendue', p_label, p_erreur;
exception
  when insufficient_privilege then
    raise notice '  ok   % (refusé : %)', p_label, sqlerrm;
  when others then
    if sqlerrm <> p_erreur and sqlstate <> p_erreur then
      raise exception 'ECHEC : % — erreur [% / %] au lieu de [%]',
        p_label, sqlstate, sqlerrm, p_erreur;
    end if;
    raise notice '  ok   % (%)', p_label, sqlerrm;
end $$;

grant usage on schema tests_plan to authenticated, anon;
grant execute on all functions in schema tests_plan to authenticated, anon;

\echo ''
\echo '=== Construction du planning en brouillon (0018) ==='

-- ===========================================================================
-- Fixtures
-- ===========================================================================
-- B « CIS Brouillon » : 1 admin, 3 membres actifs.
-- V « CIS Voisine 2 » : 1 admin, pour les tests de cloisonnement.
--
-- Réglages de B : 1 le jour, 2 la nuit, le samedi 3 le jour, et le 31 mai 2027
-- 5 la nuit. Mai 2027 compte 31 jours et 5 samedis : de quoi voir la règle de
-- priorité à l'œuvre.

insert into stations (id, name, slug, timezone, settings) values
  ('33333333-0000-4000-8000-000000000001', 'CIS Brouillon', 'cis-brouillon', 'Europe/Paris',
   '{"day_start": "07:00", "day_end": "19:00",
     "required_day": 1, "required_night": 2,
     "required_overrides": {"sat": {"day": 3}, "2027-05-31": {"night": 5}},
     "availability_deadline_day": 15,
     "response_reminder_hours": 24, "response_email_hours": 48,
     "late_report_hours": 72}'::jsonb);

-- La voisine garde les réglages par défaut : elle ne sert qu'au cloisonnement.
insert into stations (id, name, slug, timezone) values
  ('44444444-0000-4000-8000-000000000001', 'CIS Voisine 2', 'cis-voisine-2', 'Europe/Paris');

insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current
)
select
  '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
  u.email, now(), '{"provider": "email", "providers": ["email"]}'::jsonb,
  jsonb_build_object('first_name', u.first_name, 'last_name', u.last_name),
  now(), now(), '', '', '', '', ''
from (values
  ('33333333-0000-4000-8000-000000000100'::uuid, 'admin@brouillon.test',   'Irène',  'Aubry'),
  ('33333333-0000-4000-8000-000000000101'::uuid, 'membre1@brouillon.test', 'Louis',  'Bastide'),
  ('33333333-0000-4000-8000-000000000102'::uuid, 'membre2@brouillon.test', 'Awa',    'Camara'),
  ('33333333-0000-4000-8000-000000000103'::uuid, 'membre3@brouillon.test', 'Théo',   'Dumas'),
  ('44444444-0000-4000-8000-000000000100'::uuid, 'admin@voisine2.test',    'Samir',  'Ezzahi')
) as u(id, email, first_name, last_name);

insert into memberships (station_id, user_id, role, status, display_name) values
  ('33333333-0000-4000-8000-000000000001', '33333333-0000-4000-8000-000000000100', 'admin',  'active', 'Irène A.'),
  ('33333333-0000-4000-8000-000000000001', '33333333-0000-4000-8000-000000000101', 'member', 'active', 'Louis B.'),
  ('33333333-0000-4000-8000-000000000001', '33333333-0000-4000-8000-000000000102', 'member', 'active', 'Awa C.'),
  ('33333333-0000-4000-8000-000000000001', '33333333-0000-4000-8000-000000000103', 'member', 'active', 'Théo D.'),
  ('44444444-0000-4000-8000-000000000001', '44444444-0000-4000-8000-000000000100', 'admin',  'active', 'Samir E.');

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('33333333-0000-4000-8000-000000000205', '33333333-0000-4000-8000-000000000001', 2027, 5, 'open',   '2027-04-15 23:59:59+02'),
  ('33333333-0000-4000-8000-000000000206', '33333333-0000-4000-8000-000000000001', 2027, 6, 'open',   '2027-05-15 23:59:59+02'),
  ('33333333-0000-4000-8000-000000000202', '33333333-0000-4000-8000-000000000001', 2027, 2, 'locked', '2027-01-15 23:59:59+01'),
  ('44444444-0000-4000-8000-000000000205', '44444444-0000-4000-8000-000000000001', 2027, 5, 'open',   '2027-04-15 23:59:59+02');

-- Disponibilités de mai 2027. Louis est disponible le 1er (jour), absent le
-- 1er (nuit) ; Awa n'a rien saisi ; Théo est disponible le 1er (jour) aussi.
insert into availabilities (station_id, user_id, date, slot, status, set_by) values
  ('33333333-0000-4000-8000-000000000001', '33333333-0000-4000-8000-000000000101', '2027-05-01', 'day',   'available', '33333333-0000-4000-8000-000000000101'),
  ('33333333-0000-4000-8000-000000000001', '33333333-0000-4000-8000-000000000101', '2027-05-01', 'night', 'absent',    '33333333-0000-4000-8000-000000000101'),
  ('33333333-0000-4000-8000-000000000001', '33333333-0000-4000-8000-000000000103', '2027-05-01', 'day',   'available', '33333333-0000-4000-8000-000000000103');

-- ===========================================================================
-- 1. station_required_count
-- ===========================================================================
\echo ''
\echo '--- 1. L''effectif requis d''un créneau, surcharges comprises'
savepoint s1;

do $$
declare
  reglages constant jsonb := (select settings from stations
                               where id = '33333333-0000-4000-8000-000000000001');
begin
  -- Un mardi ordinaire : les deux valeurs par défaut.
  perform tests_plan.egal(
    station_required_count(reglages, date '2027-05-04', 'day'), 1,
    'mardi, jour : effectif par défaut');
  perform tests_plan.egal(
    station_required_count(reglages, date '2027-05-04', 'night'), 2,
    'mardi, nuit : effectif par défaut');

  -- Un samedi : la surcharge hebdomadaire ne fixe que le jour.
  perform tests_plan.egal(
    station_required_count(reglages, date '2027-05-01', 'day'), 3,
    'samedi, jour : surcharge hebdomadaire');
  perform tests_plan.egal(
    station_required_count(reglages, date '2027-05-01', 'night'), 2,
    'samedi, nuit : le créneau non surchargé garde le défaut');

  -- Le 31 mai 2027 est un lundi : la surcharge datée s'applique à la nuit.
  perform tests_plan.egal(
    station_required_count(reglages, date '2027-05-31', 'night'), 5,
    'date surchargée, nuit : surcharge datée');
  perform tests_plan.egal(
    station_required_count(reglages, date '2027-05-31', 'day'), 1,
    'date surchargée, jour : le défaut, la surcharge ne dit rien du jour');

  -- La priorité : une surcharge datée gagne contre la surcharge du jour de la
  -- semaine. Sans cette règle, une décision prise pour un samedi précis — le
  -- réveillon, une manifestation — ne servirait jamais.
  perform tests_plan.egal(
    station_required_count(
      '{"required_day": 1, "required_night": 1,
        "required_overrides": {"sat": {"day": 3}, "2027-05-08": {"day": 7}}}'::jsonb,
      date '2027-05-08', 'day'),
    7, 'un samedi daté : la date gagne contre le jour de semaine');

  -- Zéro est une valeur : « pas d'astreinte ce jour-là », pas une absence de
  -- réglage. La coalescence ne doit pas le remplacer par 1.
  perform tests_plan.egal(
    station_required_count(
      '{"required_day": 0, "required_night": 0}'::jsonb, date '2027-05-04', 'day'),
    0, 'un effectif de zéro reste zéro');

  -- Réglages amputés : la contrainte `stations_settings_valide` les interdit,
  -- mais une création de mois ne doit pas exploser au milieu pour autant.
  perform tests_plan.egal(
    station_required_count('{}'::jsonb, date '2027-05-04', 'night'), 1,
    'réglages vides : le défaut de la colonne, 1');
end $$;

release savepoint s1;

-- ===========================================================================
-- 2. create_schedule
-- ===========================================================================
\echo ''
\echo '--- 2. La création du planning du mois et de ses créneaux'
savepoint s2;

set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  planning schedules;
  rejoue   schedules;
begin
  planning := create_schedule(
    '33333333-0000-4000-8000-000000000001',
    '33333333-0000-4000-8000-000000000205');

  perform tests_plan.egal(planning.status::text, 'draft',
    'un planning naît en brouillon');
  perform tests_plan.egal(planning.created_by,
    '33333333-0000-4000-8000-000000000100'::uuid,
    'le planning porte son auteur');
  perform tests_plan.check(planning.published_at is null,
    'published_at est nul en brouillon');

  -- Mai 2027 : 31 jours × 2 créneaux.
  perform tests_plan.egal(
    (select count(*)::int from shifts where schedule_id = planning.id),
    62, 'un créneau par jour et par créneau');

  -- Les effectifs viennent des réglages **et** de leurs surcharges.
  perform tests_plan.egal(
    (select required_count from shifts
      where schedule_id = planning.id and date = '2027-05-04' and slot = 'day'),
    1, 'mardi jour : 1');
  perform tests_plan.egal(
    (select required_count from shifts
      where schedule_id = planning.id and date = '2027-05-04' and slot = 'night'),
    2, 'mardi nuit : 2');
  perform tests_plan.egal(
    (select required_count from shifts
      where schedule_id = planning.id and date = '2027-05-01' and slot = 'day'),
    3, 'samedi jour : 3, la surcharge hebdomadaire');
  perform tests_plan.egal(
    (select required_count from shifts
      where schedule_id = planning.id and date = '2027-05-31' and slot = 'night'),
    5, '31 mai nuit : 5, la surcharge datée');

  -- Idempotence : deux adjoints qui cliquent en même temps obtiennent le même
  -- planning, et rien n'est doublé.
  rejoue := create_schedule(
    '33333333-0000-4000-8000-000000000001',
    '33333333-0000-4000-8000-000000000205');

  perform tests_plan.egal(rejoue.id, planning.id,
    'rejouée, la création rend le planning existant');
  perform tests_plan.egal(
    (select count(*)::int from shifts where schedule_id = planning.id),
    62, 'rejouée, elle ne double aucun créneau');
  perform tests_plan.egal(
    (select count(*)::int from schedules
      where station_id = '33333333-0000-4000-8000-000000000001'
        and period_id = '33333333-0000-4000-8000-000000000205'),
    1, 'un seul planning par caserne et par mois');
end $$;

-- Le critère du ticket 010 : `required_count` est une **copie**, pas une
-- référence. Changer l'effectif requis de la caserne ne touche aucun créneau
-- déjà créé ; il ne vaut que pour les plannings créés ensuite.
do $$
declare
  juin schedules;
begin
  update stations
     set settings = jsonb_set(settings, '{required_night}', '4'::jsonb)
   where id = '33333333-0000-4000-8000-000000000001';

  perform tests_plan.egal(
    (select required_count from shifts s
      join schedules sc on sc.id = s.schedule_id
      where sc.period_id = '33333333-0000-4000-8000-000000000205'
        and s.date = '2027-05-04' and s.slot = 'night'),
    2, 'un créneau déjà créé garde son effectif quand les réglages changent');

  juin := create_schedule(
    '33333333-0000-4000-8000-000000000001',
    '33333333-0000-4000-8000-000000000206');

  perform tests_plan.egal(
    (select required_count from shifts
      where schedule_id = juin.id and date = '2027-06-01' and slot = 'night'),
    4, 'le planning créé ensuite prend le nouvel effectif');

  perform tests_plan.egal(
    (select count(*)::int from shifts where schedule_id = juin.id),
    60, 'juin 2027 : 30 jours × 2 créneaux');
end $$;

-- Les refus.
do $$
begin
  perform tests_plan.refuse(
    $sql$select create_schedule(
      '44444444-0000-4000-8000-000000000001',
      '44444444-0000-4000-8000-000000000205')$sql$,
    'forbidden', 'l''admin de B ne construit pas le planning de V');

  perform tests_plan.refuse(
    $sql$select create_schedule(
      '33333333-0000-4000-8000-000000000001',
      '44444444-0000-4000-8000-000000000205')$sql$,
    'period_not_found', 'une période d''une autre caserne est refusée');
end $$;

reset role;

-- Un membre ordinaire n'ouvre pas de planning.
set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests_plan.refuse(
    $sql$select create_schedule(
      '33333333-0000-4000-8000-000000000001',
      '33333333-0000-4000-8000-000000000202')$sql$,
    'forbidden', 'un membre ne crée pas le planning de sa caserne');
end $$;

reset role;

-- Une caserne suspendue est en lecture seule, y compris pour son admin.
insert into subscriptions (station_id, status) values
  ('33333333-0000-4000-8000-000000000001', 'suspended');

set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests_plan.refuse(
    $sql$select create_schedule(
      '33333333-0000-4000-8000-000000000001',
      '33333333-0000-4000-8000-000000000202')$sql$,
    'station_suspended', 'une caserne suspendue ne construit rien');
end $$;

reset role;

delete from subscriptions where station_id = '33333333-0000-4000-8000-000000000001';

release savepoint s2;

-- ===========================================================================
-- 3. Les attributions : was_available, created_by, audit, unicité
-- ===========================================================================
\echo ''
\echo '--- 3. Attribuer : la trace que la base pose, et celle qu''elle refuse'
savepoint s3;

set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  planning     schedules;
  creneau_jour uuid;
  creneau_nuit uuid;
  pose         assignments;
begin
  planning := create_schedule(
    '33333333-0000-4000-8000-000000000001',
    '33333333-0000-4000-8000-000000000205');

  select id into creneau_jour from shifts
    where schedule_id = planning.id and date = '2027-05-01' and slot = 'day';
  select id into creneau_nuit from shifts
    where schedule_id = planning.id and date = '2027-05-01' and slot = 'night';

  -- Louis est disponible le 1er en journée : `was_available` vaut vrai, et le
  -- client n'a rien eu à déclarer.
  insert into assignments (station_id, shift_id, user_id, created_by)
  values ('33333333-0000-4000-8000-000000000001', creneau_jour,
          '33333333-0000-4000-8000-000000000101',
          '33333333-0000-4000-8000-000000000100')
  returning * into pose;

  perform tests_plan.egal(pose.status::text, 'proposed',
    'une attribution de brouillon est « proposed »');
  perform tests_plan.check(pose.proposed_at is null,
    'proposed_at reste nul tant que le planning n''est pas publié');
  perform tests_plan.egal(pose.was_available, true,
    'attribué sur une disponibilité : was_available vrai');

  -- Louis s'est déclaré **absent** la nuit du 1er : la base le sait, même si le
  -- client prétend le contraire. La trace d'une attribution forcée ne se
  -- choisit pas.
  insert into assignments (station_id, shift_id, user_id, created_by, was_available)
  values ('33333333-0000-4000-8000-000000000001', creneau_nuit,
          '33333333-0000-4000-8000-000000000101',
          '33333333-0000-4000-8000-000000000101', true)
  returning * into pose;

  perform tests_plan.egal(pose.was_available, false,
    'attribué contre une absence : was_available faux, malgré le client');
  perform tests_plan.egal(pose.created_by,
    '33333333-0000-4000-8000-000000000100'::uuid,
    'created_by est l''appelant réel, pas celui que le client annonce');

  -- Awa n'a rien saisi : ne pas avoir répondu n'est pas être disponible.
  insert into assignments (station_id, shift_id, user_id, created_by)
  values ('33333333-0000-4000-8000-000000000001', creneau_nuit,
          '33333333-0000-4000-8000-000000000102',
          '33333333-0000-4000-8000-000000000100')
  returning * into pose;

  perform tests_plan.egal(pose.was_available, false,
    'attribué sans saisie : was_available faux');

  -- L'audit : une ligne par attribution forcée, et **seulement** pour elles.
  perform tests_plan.egal(
    (select count(*)::int from audit_log
      where station_id = '33333333-0000-4000-8000-000000000001'
        and action = 'assignment.force'),
    2, 'deux attributions forcées, deux lignes d''audit');

  perform tests_plan.egal(
    (select data ->> 'date' from audit_log
      where action = 'assignment.force'
        and (data ->> 'user_id') = '33333333-0000-4000-8000-000000000102'),
    '2027-05-01', 'la ligne d''audit porte la date du créneau');

  perform tests_plan.egal(
    (select actor_id from audit_log
      where action = 'assignment.force'
        and (data ->> 'user_id') = '33333333-0000-4000-8000-000000000102'),
    '33333333-0000-4000-8000-000000000100'::uuid,
    'la ligne d''audit porte l''administrateur qui a forcé');

  -- La contrainte d'unicité : un membre ne peut pas être attribué deux fois au
  -- même créneau. C'est elle que l'écran traduit en une phrase française.
  perform tests_plan.refuse(
    format($sql$insert into assignments (station_id, shift_id, user_id, created_by)
             values ('33333333-0000-4000-8000-000000000001', %L,
                     '33333333-0000-4000-8000-000000000101',
                     '33333333-0000-4000-8000-000000000100')$sql$, creneau_jour),
    '23505', 'deux fois le même membre sur le même créneau : refusé');

  -- Mais une attribution close ne bloque pas : la contrainte est partielle, et
  -- c'est ce qui rend la réattribution possible au ticket 019.
  update assignments set status = 'cancelled'
   where shift_id = creneau_jour
     and user_id = '33333333-0000-4000-8000-000000000101';

  insert into assignments (station_id, shift_id, user_id, created_by)
  values ('33333333-0000-4000-8000-000000000001', creneau_jour,
          '33333333-0000-4000-8000-000000000101',
          '33333333-0000-4000-8000-000000000100');

  perform tests_plan.egal(
    (select count(*)::int from assignments
      where shift_id = creneau_jour
        and user_id = '33333333-0000-4000-8000-000000000101'),
    2, 'une attribution annulée laisse place à une nouvelle');
end $$;

reset role;

rollback to savepoint s3;
release savepoint s3;

-- ===========================================================================
-- 4. Le retrait : en brouillon, et nulle part ailleurs
-- ===========================================================================
\echo ''
\echo '--- 4. Retirer une attribution : suppression en brouillon, jamais après'
savepoint s4;

set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  planning schedules;
  creneau  uuid;
  pose     uuid;
begin
  planning := create_schedule(
    '33333333-0000-4000-8000-000000000001',
    '33333333-0000-4000-8000-000000000205');

  select id into creneau from shifts
    where schedule_id = planning.id and date = '2027-05-02' and slot = 'day';

  insert into assignments (station_id, shift_id, user_id, created_by)
  values ('33333333-0000-4000-8000-000000000001', creneau,
          '33333333-0000-4000-8000-000000000103',
          '33333333-0000-4000-8000-000000000100')
  returning id into pose;

  delete from assignments where id = pose;
  perform tests_plan.egal(
    (select count(*)::int from assignments where id = pose), 0,
    'en brouillon, retirer supprime');

  -- Une fois le planning publié, la même suppression ne passe plus : la
  -- politique filtre **sans lever**, l'instruction affecte zéro ligne.
  insert into assignments (station_id, shift_id, user_id, created_by, proposed_at)
  values ('33333333-0000-4000-8000-000000000001', creneau,
          '33333333-0000-4000-8000-000000000103',
          '33333333-0000-4000-8000-000000000100', now())
  returning id into pose;

  update schedules set status = 'published', published_at = now()
   where id = planning.id;

  delete from assignments where id = pose;
  perform tests_plan.egal(
    (select count(*)::int from assignments where id = pose), 1,
    'planning publié : la suppression n''emporte rien');

  -- Ce qui reste possible : l'annuler. L'historique n'est jamais supprimé, il
  -- change de statut (docs/PRD.md § 7.6).
  update assignments set status = 'cancelled' where id = pose;
  perform tests_plan.egal(
    (select status::text from assignments where id = pose), 'cancelled',
    'une attribution publiée s''annule');
end $$;

reset role;

rollback to savepoint s4;
release savepoint s4;

-- ===========================================================================
-- 5. v_schedule_progress
-- ===========================================================================
\echo ''
\echo '--- 5. L''avancement d''un planning'
savepoint s5;

set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  planning  schedules;
  jour      uuid;
  nuit      uuid;
  avancement record;
begin
  planning := create_schedule(
    '33333333-0000-4000-8000-000000000001',
    '33333333-0000-4000-8000-000000000205');

  select id into jour from shifts
    where schedule_id = planning.id and date = '2027-05-04' and slot = 'day';
  select id into nuit from shifts
    where schedule_id = planning.id and date = '2027-05-04' and slot = 'night';

  -- Le 4 mai demande 1 le jour et 2 la nuit. On pourvoit le jour, et la moitié
  -- de la nuit.
  insert into assignments (station_id, shift_id, user_id, created_by) values
    ('33333333-0000-4000-8000-000000000001', jour, '33333333-0000-4000-8000-000000000101', '33333333-0000-4000-8000-000000000100'),
    ('33333333-0000-4000-8000-000000000001', nuit, '33333333-0000-4000-8000-000000000102', '33333333-0000-4000-8000-000000000100');

  select * into avancement from v_schedule_progress where schedule_id = planning.id;

  perform tests_plan.egal(avancement.shifts_total, 62,
    'les 62 créneaux du mois sont comptés');
  -- Tous les créneaux à `required_count = 0` seraient couverts d'office ; il n'y
  -- en a aucun ici. Un seul créneau est couvert : celui du jour.
  perform tests_plan.egal(avancement.shifts_filled, 1,
    'un seul créneau couvert : le jour du 4 mai');
  perform tests_plan.egal(avancement.assignments_pending, 2,
    'deux attributions en attente');
  perform tests_plan.egal(avancement.assignments_accepted, 0,
    'aucune acceptation en brouillon');
  perform tests_plan.egal(avancement.assignments_late, 0,
    'le brouillon n''est jamais en retard : proposed_at est nul');

  -- Publié depuis huit jours, sans réponse : c'est un retard, au-delà des 72 h
  -- de `late_report_hours`.
  update schedules set status = 'published', published_at = now() where id = planning.id;
  update assignments set proposed_at = now() - interval '8 days'
   where shift_id in (jour, nuit);

  select * into avancement from v_schedule_progress where schedule_id = planning.id;
  perform tests_plan.egal(avancement.assignments_late, 2,
    'deux propositions sans réponse depuis plus de late_report_hours');

  update assignments set status = 'declined', responded_at = now()
   where shift_id = jour;

  select * into avancement from v_schedule_progress where schedule_id = planning.id;
  perform tests_plan.egal(avancement.assignments_declined, 1,
    'un refus est compté comme tel');
  perform tests_plan.egal(avancement.shifts_filled, 0,
    'un créneau dont l''attribution est refusée n''est plus couvert');
end $$;

reset role;

rollback to savepoint s5;
release savepoint s5;

-- ===========================================================================
-- 6. Le temps réel
-- ===========================================================================
\echo ''
\echo '--- 6. La publication supabase_realtime et l''identité de réplique'
savepoint s6;

do $$
begin
  perform tests_plan.egal(
    (select count(*)::int from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = 'assignments'),
    1, 'assignments est inscrite dans supabase_realtime');

  -- **La décision de sécurité du ticket.** La charge utile d'un `delete` n'est
  -- pas filtrée par les politiques : en `full`, chaque retrait d'attribution
  -- diffuserait toutes les colonnes de la ligne à tous les abonnés. En
  -- `default`, il ne diffuse que la clé primaire.
  perform tests_plan.egal(
    (select relreplident::text from pg_class
      where relname = 'assignments' and relnamespace = 'public'::regnamespace),
    'd', 'l''identité de réplique d''assignments reste « default »');

  -- Et rien d'autre n'est entré dans la publication par inadvertance. En
  -- particulier pas `invitations`, dont le jeton est un porteur de droits.
  perform tests_plan.egal(
    (select count(*)::int from pg_publication_tables
      where pubname = 'supabase_realtime' and tablename = 'invitations'),
    0, 'invitations n''est pas publiée');
end $$;

release savepoint s6;

-- ===========================================================================
-- 7. Les droits : le brouillon est invisible des membres
-- ===========================================================================
\echo ''
\echo '--- 7. Cloisonnement : brouillon invisible, caserne voisine invisible'
savepoint s7;

set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  planning schedules;
  creneau  uuid;
begin
  planning := create_schedule(
    '33333333-0000-4000-8000-000000000001',
    '33333333-0000-4000-8000-000000000205');

  select id into creneau from shifts
    where schedule_id = planning.id and date = '2027-05-03' and slot = 'day';

  insert into assignments (station_id, shift_id, user_id, created_by)
  values ('33333333-0000-4000-8000-000000000001', creneau,
          '33333333-0000-4000-8000-000000000101',
          '33333333-0000-4000-8000-000000000100');
end $$;

reset role;

-- Le membre attribué lui-même ne voit rien : le planning est en brouillon.
-- C'est exactement ce qui fait qu'un abonnement temps réel ne lui diffuse rien.
set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests_plan.egal(
    (select count(*)::int from schedules
      where station_id = '33333333-0000-4000-8000-000000000001'),
    0, 'un membre ne voit aucun planning en brouillon');
  perform tests_plan.egal(
    (select count(*)::int from shifts
      where station_id = '33333333-0000-4000-8000-000000000001'),
    0, 'un membre ne voit aucun créneau d''un brouillon');
  perform tests_plan.egal(
    (select count(*)::int from assignments
      where station_id = '33333333-0000-4000-8000-000000000001'),
    0, 'un membre ne voit pas sa propre attribution en brouillon');
end $$;

reset role;

-- L'admin voisin ne voit rien non plus.
set local role authenticated;
set local request.jwt.claims = '{"sub":"44444444-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests_plan.egal(
    (select count(*)::int from assignments
      where station_id = '33333333-0000-4000-8000-000000000001'),
    0, 'l''admin de V ne voit aucune attribution de B');
  perform tests_plan.egal(
    (select count(*)::int from v_schedule_progress
      where station_id = '33333333-0000-4000-8000-000000000001'),
    0, 'l''admin de V ne lit aucun avancement de B');
end $$;

reset role;

-- `anon` n'appelle rien.
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

do $$
begin
  perform tests_plan.refuse(
    $sql$select create_schedule(
      '33333333-0000-4000-8000-000000000001',
      '33333333-0000-4000-8000-000000000205')$sql$,
    '42501', 'anon n''appelle pas create_schedule');
end $$;

reset role;

release savepoint s7;

\echo ''
\echo '=== Planning en brouillon : tous les tests passent ==='

rollback;
