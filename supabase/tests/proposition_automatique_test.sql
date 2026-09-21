-- Tests de la proposition automatique de remplissage (migration 0028, ticket 018).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce que ce fichier vérifie, et ce qu'il ne vérifie pas
-- ----------------------------------------------------
-- Il vérifie **les limites**, celles que la base tient : jamais un absent, jamais
-- un membre qui n'a rien saisi, jamais un plafond dépassé, jamais une place de
-- trop, jamais une attribution déjà posée qui bouge.
--
-- Il ne vérifie **pas le choix** des pompiers : le classement des candidats est
-- celui du ticket 017 (`comparerCandidats`), il vit dans l'application, et c'est
-- `test/features/planning/proposition_automatique_test.dart` qui l'éprouve —
-- l'ordre de choix quand les deux critères s'opposent, le remplissage d'un mois
-- entier, le récapitulatif. Écrire ici un second classement donnerait deux
-- réponses à la même question (design/018 § 3).
--
-- Sections
-- --------
-- 1. Un plan ordinaire s'applique : `proposed`, `proposed_at` nul,
--    `was_available` vrai, `created_by` = l'administrateur qui a appuyé, et un
--    créneau à deux places reçoit **deux pompiers différents**.
-- 2. Les places : un créneau plein refuse, y compris quand c'est une attribution
--    faite **à la main** qui l'a rempli — et celle-ci ne bouge pas d'un octet.
-- 3. L'absent, le non-saisi et le membre désactivé sont écartés, chacun avec son
--    motif.
-- 4. Le plafond d'astreintes : relu à chaque ligne, donc les attributions posées
--    par l'appel lui-même comptent.
-- 5. Le plafond de weekends : samedi et dimanche du même weekend ne coûtent
--    qu'une unité, le weekend suivant est refusé, un jour de semaine passe quand
--    même.
-- 6. Le même membre deux fois sur le même créneau.
-- 7. Les refus globaux : non-administrateur, planning introuvable, planning
--    publié, caserne suspendue, charge utile invalide ou démesurée.
-- 8. Les droits : la fonction est fermée à `authenticated` et à `anon`.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : une caserne « CIS Proposition » et une voisine, sur **mars 2040**
-- qu'aucun autre fichier ne touche. Mars 2040 a ses samedis les 3, 10, 17, 24 et
-- 31 : deux unités de weekend suffisent à éprouver la règle.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_auto;

create function tests_auto.egal(p_obtenu anyelement, p_attendu anyelement, p_label text) returns void
language plpgsql as $$
begin
  if p_obtenu is distinct from p_attendu then
    raise exception 'ECHEC : % — obtenu [%], attendu [%]', p_label, p_obtenu, p_attendu;
  end if;
  raise notice '  ok   % = %', p_label, coalesce(p_obtenu::text, 'NULL');
end $$;

create function tests_auto.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

-- Le code métier d'un refus global. Aucune exception : la fonction répond
-- `{"ok": false, "code": …}`, l'Edge Function traduit.
create function tests_auto.code(p_resultat jsonb, p_code text, p_label text) returns void
language plpgsql as $$
begin
  if (p_resultat ->> 'ok')::boolean is not false then
    raise exception 'ECHEC : % — la fonction a répondu ok, refus [%] attendu', p_label, p_code;
  end if;
  if p_resultat ->> 'code' is distinct from p_code then
    raise exception 'ECHEC : % — code [%] au lieu de [%]',
      p_label, p_resultat ->> 'code', p_code;
  end if;
  raise notice '  ok   % (%)', p_label, p_code;
end $$;

-- Le motif d'une ligne **écartée**, désignée par son créneau et son pompier.
create function tests_auto.ecarte(
  p_resultat jsonb, p_shift uuid, p_user uuid, p_code text, p_label text
) returns void
language plpgsql as $$
declare
  trouve text;
begin
  select e ->> 'code' into trouve
    from jsonb_array_elements(p_resultat -> 'skipped') e
   where (e ->> 'shift_id')::uuid = p_shift
     and (e ->> 'user_id')::uuid  = p_user;

  if trouve is null then
    raise exception 'ECHEC : % — aucune ligne écartée pour ce couple, [%] attendu (skipped = %)',
      p_label, p_code, p_resultat -> 'skipped';
  end if;
  if trouve <> p_code then
    raise exception 'ECHEC : % — écartée pour [%] au lieu de [%]', p_label, trouve, p_code;
  end if;
  raise notice '  ok   % (%)', p_label, p_code;
end $$;

-- Un plan, écrit comme l'écran l'envoie : une liste **ordonnée** de couples.
create function tests_auto.plan(variadic p_couples uuid[]) returns jsonb
language plpgsql as $$
declare
  resultat jsonb := '[]'::jsonb;
  i integer := 1;
begin
  while i < array_length(p_couples, 1) loop
    resultat := resultat || jsonb_build_object(
      'shift_id', p_couples[i], 'user_id', p_couples[i + 1]);
    i := i + 2;
  end loop;
  return resultat;
end $$;

\echo ''
\echo '=== Proposition automatique de remplissage (0028) ==='

-- ===========================================================================
-- Fixtures
-- ===========================================================================
-- P « CIS Proposition » : 1 admin, 4 membres actifs, 1 désactivée.
-- Q « CIS Voisine 5 » : 1 admin et un créneau, pour le cloisonnement.
--
-- Huit créneaux de mars 2040, choisis un par un : un mois entier ne dirait rien
-- de plus et rendrait chaque compte illisible.

insert into stations (id, name, slug, timezone, settings) values
  ('a1a1a1a1-0000-4000-8000-000000000001', 'CIS Proposition', 'cis-proposition', 'Europe/Paris',
   '{"day_start": "07:00", "day_end": "19:00",
     "required_day": 1, "required_night": 1,
     "required_overrides": {},
     "availability_deadline_day": 15,
     "response_reminder_hours": 24, "response_email_hours": 48,
     "late_report_hours": 72}'::jsonb),
  ('b1b1b1b1-0000-4000-8000-000000000001', 'CIS Voisine 5', 'cis-voisine-5', 'Europe/Paris',
   '{"day_start": "07:00", "day_end": "19:00",
     "required_day": 1, "required_night": 1,
     "required_overrides": {},
     "availability_deadline_day": 15,
     "response_reminder_hours": 24, "response_email_hours": 48,
     "late_report_hours": 72}'::jsonb);

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
  ('a1a1a1a1-0000-4000-8000-000000000100'::uuid, 'admin@proposition.test',  'Nadia',  'Aloui'),
  ('a1a1a1a1-0000-4000-8000-000000000101'::uuid, 'bruno@proposition.test',  'Bruno',  'Bertin'),
  ('a1a1a1a1-0000-4000-8000-000000000102'::uuid, 'chloe@proposition.test',  'Chloé',  'Colin'),
  ('a1a1a1a1-0000-4000-8000-000000000103'::uuid, 'damien@proposition.test', 'Damien', 'Denis'),
  ('a1a1a1a1-0000-4000-8000-000000000104'::uuid, 'eve@proposition.test',    'Eve',    'Evrard'),
  ('a1a1a1a1-0000-4000-8000-000000000105'::uuid, 'fabien@proposition.test', 'Fabien', 'Faure'),
  ('b1b1b1b1-0000-4000-8000-000000000100'::uuid, 'admin@voisine5.test',     'Gaël',   'Guyot')
) as u(id, email, first_name, last_name);

insert into memberships (station_id, user_id, role, status, display_name) values
  ('a1a1a1a1-0000-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000100', 'admin',  'active',   'Nadia A.'),
  ('a1a1a1a1-0000-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000101', 'member', 'active',   'Bruno B.'),
  ('a1a1a1a1-0000-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000102', 'member', 'active',   'Chloé C.'),
  ('a1a1a1a1-0000-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000103', 'member', 'active',   'Damien D.'),
  ('a1a1a1a1-0000-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000104', 'member', 'disabled', 'Eve E.'),
  ('a1a1a1a1-0000-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000105', 'member', 'active',   'Fabien F.'),
  ('b1b1b1b1-0000-4000-8000-000000000001', 'b1b1b1b1-0000-4000-8000-000000000100', 'admin',  'active',   'Gaël G.');

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('a1a1a1a1-0000-4000-8000-000000000201', 'a1a1a1a1-0000-4000-8000-000000000001', 2040, 3, 'locked', '2040-02-15 23:59:59+01'),
  ('b1b1b1b1-0000-4000-8000-000000000201', 'b1b1b1b1-0000-4000-8000-000000000001', 2040, 3, 'locked', '2040-02-15 23:59:59+01');

insert into schedules (id, station_id, period_id, created_by) values
  ('a1a1a1a1-0000-4000-8000-000000000301',
   'a1a1a1a1-0000-4000-8000-000000000001',
   'a1a1a1a1-0000-4000-8000-000000000201',
   'a1a1a1a1-0000-4000-8000-000000000100'),
  ('b1b1b1b1-0000-4000-8000-000000000301',
   'b1b1b1b1-0000-4000-8000-000000000001',
   'b1b1b1b1-0000-4000-8000-000000000201',
   'b1b1b1b1-0000-4000-8000-000000000100');

-- Les huit créneaux. Le 401 demande **une** personne, le 402 en demande deux :
-- c'est lui qui éprouve la règle des créneaux à plusieurs.
insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  ('a1a1a1a1-0000-4000-8000-000000000401', 'a1a1a1a1-0000-4000-8000-000000000001',
   'a1a1a1a1-0000-4000-8000-000000000301', '2040-03-01', 'day',   1),  -- jeudi
  ('a1a1a1a1-0000-4000-8000-000000000402', 'a1a1a1a1-0000-4000-8000-000000000001',
   'a1a1a1a1-0000-4000-8000-000000000301', '2040-03-01', 'night', 2),  -- jeudi nuit, 2 places
  ('a1a1a1a1-0000-4000-8000-000000000403', 'a1a1a1a1-0000-4000-8000-000000000001',
   'a1a1a1a1-0000-4000-8000-000000000301', '2040-03-02', 'day',   1),  -- vendredi, pourvu à la main
  ('a1a1a1a1-0000-4000-8000-000000000404', 'a1a1a1a1-0000-4000-8000-000000000001',
   'a1a1a1a1-0000-4000-8000-000000000301', '2040-03-03', 'day',   1),  -- samedi,   unité 03-03
  ('a1a1a1a1-0000-4000-8000-000000000405', 'a1a1a1a1-0000-4000-8000-000000000001',
   'a1a1a1a1-0000-4000-8000-000000000301', '2040-03-04', 'day',   1),  -- dimanche, unité 03-03
  ('a1a1a1a1-0000-4000-8000-000000000406', 'a1a1a1a1-0000-4000-8000-000000000001',
   'a1a1a1a1-0000-4000-8000-000000000301', '2040-03-10', 'day',   1),  -- samedi,   unité 03-10
  ('a1a1a1a1-0000-4000-8000-000000000407', 'a1a1a1a1-0000-4000-8000-000000000001',
   'a1a1a1a1-0000-4000-8000-000000000301', '2040-03-05', 'day',   1),  -- lundi
  ('a1a1a1a1-0000-4000-8000-000000000408', 'a1a1a1a1-0000-4000-8000-000000000001',
   'a1a1a1a1-0000-4000-8000-000000000301', '2040-03-06', 'day',   1),  -- mardi
  ('b1b1b1b1-0000-4000-8000-000000000401', 'b1b1b1b1-0000-4000-8000-000000000001',
   'b1b1b1b1-0000-4000-8000-000000000301', '2040-03-01', 'day',   1);

-- Bruno, Chloé et Damien se sont déclarés disponibles sur les huit créneaux.
-- Eve aussi — désactivée, elle doit être écartée pour **son statut**, et non
-- pour une disponibilité manquante qui masquerait le vrai motif.
insert into availabilities (station_id, user_id, date, slot, status, set_by)
select
  'a1a1a1a1-0000-4000-8000-000000000001',
  m.user_id,
  s.date,
  s.slot,
  'available',
  m.user_id
from shifts s
cross join (values
  ('a1a1a1a1-0000-4000-8000-000000000101'::uuid),
  ('a1a1a1a1-0000-4000-8000-000000000102'::uuid),
  ('a1a1a1a1-0000-4000-8000-000000000103'::uuid),
  ('a1a1a1a1-0000-4000-8000-000000000104'::uuid)
) as m(user_id)
where s.schedule_id = 'a1a1a1a1-0000-4000-8000-000000000301';

-- Fabien, lui, a dit **non** le 1er de jour et **rien du tout** le 1er de nuit.
-- Les deux cas que le ticket sépare, et que la base doit écarter tous les deux.
insert into availabilities (station_id, user_id, date, slot, status, set_by) values
  ('a1a1a1a1-0000-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000105',
   '2040-03-01', 'day', 'absent', 'a1a1a1a1-0000-4000-8000-000000000105');

-- Les plafonds du mois : Bruno deux astreintes, Damien un seul weekend, Chloé
-- rien du tout — un illimité (docs/SCHEMA.md § 2.7, `null` n'est pas zéro).
insert into availability_preferences (station_id, user_id, period_id, max_shifts, max_weekends) values
  ('a1a1a1a1-0000-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000101',
   'a1a1a1a1-0000-4000-8000-000000000201', 2, null),
  ('a1a1a1a1-0000-4000-8000-000000000001', 'a1a1a1a1-0000-4000-8000-000000000103',
   'a1a1a1a1-0000-4000-8000-000000000201', null, 1);

-- **L'attribution faite à la main**, celle qui ne doit jamais bouger. Posée
-- avant tout appel, avec un horodatage reculé pour qu'une réécriture se voie.
insert into assignments (id, station_id, shift_id, user_id, status, created_by, created_at) values
  ('a1a1a1a1-0000-4000-8000-000000000501', 'a1a1a1a1-0000-4000-8000-000000000001',
   'a1a1a1a1-0000-4000-8000-000000000403', 'a1a1a1a1-0000-4000-8000-000000000102',
   'proposed', 'a1a1a1a1-0000-4000-8000-000000000100', '2040-02-20 10:00:00+01');

-- ===========================================================================
-- 1. Un plan ordinaire s'applique
-- ===========================================================================
\echo ''
\echo '--- 1. le plan s''applique, et un créneau à deux places reçoit deux pompiers'
savepoint s1;

do $$
declare
  r jsonb;
  a assignments;
begin
  r := apply_auto_proposal(
    'a1a1a1a1-0000-4000-8000-000000000301',
    'a1a1a1a1-0000-4000-8000-000000000100',
    tests_auto.plan(
      'a1a1a1a1-0000-4000-8000-000000000401', 'a1a1a1a1-0000-4000-8000-000000000101',
      'a1a1a1a1-0000-4000-8000-000000000402', 'a1a1a1a1-0000-4000-8000-000000000102',
      'a1a1a1a1-0000-4000-8000-000000000402', 'a1a1a1a1-0000-4000-8000-000000000103'));

  perform tests_auto.egal((r ->> 'ok')::boolean, true, 'ok');
  perform tests_auto.egal((r ->> 'applied')::int, 3, 'attributions posées');
  perform tests_auto.egal(jsonb_array_length(r -> 'skipped'), 0, 'aucune ligne écartée');

  -- Le créneau à deux places est plein, avec **deux pompiers différents**.
  perform tests_auto.egal(
    (select count(distinct user_id)::int from assignments
      where shift_id = 'a1a1a1a1-0000-4000-8000-000000000402'
        and status in ('proposed', 'accepted')),
    2, 'deux pompiers distincts sur le créneau à deux places');

  select * into a from assignments
   where shift_id = 'a1a1a1a1-0000-4000-8000-000000000401';

  perform tests_auto.egal(a.status::text, 'proposed', 'statut');
  perform tests_auto.check(a.proposed_at is null,
    'proposed_at nul : un brouillon n''a rien envoyé');
  perform tests_auto.egal(a.was_available, true,
    'was_available vrai : le pompier avait dit oui');
  perform tests_auto.egal(a.created_by, 'a1a1a1a1-0000-4000-8000-000000000100'::uuid,
    'created_by : l''administrateur qui a appuyé, pas le rôle de service');

  -- Huit créneaux, dont 401 (1 place), 402 (2 places) et 403 (déjà pourvu à la
  -- main) sont couverts : il en reste cinq à découvert.
  perform tests_auto.egal((r ->> 'shifts_short')::int, 5,
    'créneaux encore à découvert, comptés en base');
end $$;

rollback to s1;

-- ===========================================================================
-- 2. Les places, et l'attribution faite à la main
-- ===========================================================================
\echo ''
\echo '--- 2. un créneau plein refuse, et rien de manuel ne bouge'
savepoint s2;

do $$
declare
  r jsonb;
  avant assignments;
  apres assignments;
begin
  select * into avant from assignments
   where id = 'a1a1a1a1-0000-4000-8000-000000000501';

  r := apply_auto_proposal(
    'a1a1a1a1-0000-4000-8000-000000000301',
    'a1a1a1a1-0000-4000-8000-000000000100',
    tests_auto.plan(
      -- 403 est déjà pourvu à la main par Chloé : Bruno n'y entre pas.
      'a1a1a1a1-0000-4000-8000-000000000403', 'a1a1a1a1-0000-4000-8000-000000000101',
      -- 402 demande deux places : les deux premières passent, la troisième non.
      'a1a1a1a1-0000-4000-8000-000000000402', 'a1a1a1a1-0000-4000-8000-000000000101',
      'a1a1a1a1-0000-4000-8000-000000000402', 'a1a1a1a1-0000-4000-8000-000000000102',
      'a1a1a1a1-0000-4000-8000-000000000402', 'a1a1a1a1-0000-4000-8000-000000000103'));

  perform tests_auto.egal((r ->> 'applied')::int, 2, 'deux places, deux attributions');
  perform tests_auto.ecarte(r,
    'a1a1a1a1-0000-4000-8000-000000000403', 'a1a1a1a1-0000-4000-8000-000000000101',
    'shift_already_filled', 'un créneau pourvu à la main refuse');
  perform tests_auto.ecarte(r,
    'a1a1a1a1-0000-4000-8000-000000000402', 'a1a1a1a1-0000-4000-8000-000000000103',
    'shift_already_filled', 'la troisième place d''un créneau qui en demande deux');

  select * into apres from assignments
   where id = 'a1a1a1a1-0000-4000-8000-000000000501';

  perform tests_auto.check(apres is not distinct from avant,
    'l''attribution faite à la main est intacte, ligne entière comparée');
  perform tests_auto.egal(
    (select count(*)::int from assignments
      where shift_id = 'a1a1a1a1-0000-4000-8000-000000000403'),
    1, 'aucune attribution ajoutée sur le créneau déjà pourvu');
end $$;

rollback to s2;

-- ===========================================================================
-- 3. L'absent, le non-saisi, le désactivé
-- ===========================================================================
\echo ''
\echo '--- 3. ni absent, ni non-saisi, ni désactivé'
savepoint s3;

do $$
declare
  r jsonb;
begin
  r := apply_auto_proposal(
    'a1a1a1a1-0000-4000-8000-000000000301',
    'a1a1a1a1-0000-4000-8000-000000000100',
    tests_auto.plan(
      -- Fabien a dit non le 1er de jour.
      'a1a1a1a1-0000-4000-8000-000000000401', 'a1a1a1a1-0000-4000-8000-000000000105',
      -- Fabien n'a rien dit du 1er de nuit.
      'a1a1a1a1-0000-4000-8000-000000000402', 'a1a1a1a1-0000-4000-8000-000000000105',
      -- Eve est disponible sur le papier, mais elle a quitté la caserne.
      'a1a1a1a1-0000-4000-8000-000000000407', 'a1a1a1a1-0000-4000-8000-000000000104',
      -- Le créneau de la caserne voisine n'appartient pas à ce planning.
      'b1b1b1b1-0000-4000-8000-000000000401', 'a1a1a1a1-0000-4000-8000-000000000101'));

  perform tests_auto.egal((r ->> 'applied')::int, 0, 'aucune attribution posée');
  perform tests_auto.ecarte(r,
    'a1a1a1a1-0000-4000-8000-000000000401', 'a1a1a1a1-0000-4000-8000-000000000105',
    'not_available', 'un absent n''est jamais désigné');
  perform tests_auto.ecarte(r,
    'a1a1a1a1-0000-4000-8000-000000000402', 'a1a1a1a1-0000-4000-8000-000000000105',
    'not_available', 'un membre qui n''a rien saisi non plus');
  perform tests_auto.ecarte(r,
    'a1a1a1a1-0000-4000-8000-000000000407', 'a1a1a1a1-0000-4000-8000-000000000104',
    'member_not_active', 'un membre désactivé non plus');
  perform tests_auto.ecarte(r,
    'b1b1b1b1-0000-4000-8000-000000000401', 'a1a1a1a1-0000-4000-8000-000000000101',
    'shift_not_in_schedule', 'un créneau d''une autre caserne non plus');
end $$;

rollback to s3;

-- ===========================================================================
-- 4. Le plafond d'astreintes
-- ===========================================================================
\echo ''
\echo '--- 4. un quota d''astreintes ne se dépasse jamais, même au sein d''un appel'
savepoint s4;

do $$
declare
  r jsonb;
begin
  -- Bruno a déclaré deux astreintes au plus. Trois lui sont proposées dans le
  -- **même** appel : c'est le compte relu à chaque ligne qui refuse la
  -- troisième, pas une lecture faite au début.
  r := apply_auto_proposal(
    'a1a1a1a1-0000-4000-8000-000000000301',
    'a1a1a1a1-0000-4000-8000-000000000100',
    tests_auto.plan(
      'a1a1a1a1-0000-4000-8000-000000000401', 'a1a1a1a1-0000-4000-8000-000000000101',
      'a1a1a1a1-0000-4000-8000-000000000407', 'a1a1a1a1-0000-4000-8000-000000000101',
      'a1a1a1a1-0000-4000-8000-000000000408', 'a1a1a1a1-0000-4000-8000-000000000101'));

  perform tests_auto.egal((r ->> 'applied')::int, 2, 'deux astreintes posées');
  perform tests_auto.ecarte(r,
    'a1a1a1a1-0000-4000-8000-000000000408', 'a1a1a1a1-0000-4000-8000-000000000101',
    'shift_quota_reached', 'la troisième dépasserait le plafond');

  perform tests_auto.egal(
    (select shifts_left from v_member_load
      where user_id = 'a1a1a1a1-0000-4000-8000-000000000101'
        and period_id = 'a1a1a1a1-0000-4000-8000-000000000201'),
    0, 'le reste de quota vu par v_member_load tombe à zéro, jamais en dessous');

  -- Un illimité, lui, n'est arrêté par rien : c'est ce que `null` veut dire.
  r := apply_auto_proposal(
    'a1a1a1a1-0000-4000-8000-000000000301',
    'a1a1a1a1-0000-4000-8000-000000000100',
    tests_auto.plan(
      'a1a1a1a1-0000-4000-8000-000000000408', 'a1a1a1a1-0000-4000-8000-000000000102',
      'a1a1a1a1-0000-4000-8000-000000000404', 'a1a1a1a1-0000-4000-8000-000000000102',
      'a1a1a1a1-0000-4000-8000-000000000405', 'a1a1a1a1-0000-4000-8000-000000000102',
      'a1a1a1a1-0000-4000-8000-000000000406', 'a1a1a1a1-0000-4000-8000-000000000102'));

  perform tests_auto.egal((r ->> 'applied')::int, 4,
    'un membre sans plafond n''est arrêté par aucun quota');
end $$;

rollback to s4;

-- ===========================================================================
-- 5. Le plafond de weekends
-- ===========================================================================
\echo ''
\echo '--- 5. un weekend est une unité, et le plafond de weekends n''arrête pas la semaine'
savepoint s5;

do $$
declare
  r jsonb;
begin
  -- Damien a déclaré un weekend au plus.
  --   404 samedi 3, 405 dimanche 4 : **la même** unité, deux astreintes ;
  --   406 samedi 10 : une seconde unité, refusée ;
  --   407 lundi 5   : aucune unité, acceptée.
  r := apply_auto_proposal(
    'a1a1a1a1-0000-4000-8000-000000000301',
    'a1a1a1a1-0000-4000-8000-000000000100',
    tests_auto.plan(
      'a1a1a1a1-0000-4000-8000-000000000404', 'a1a1a1a1-0000-4000-8000-000000000103',
      'a1a1a1a1-0000-4000-8000-000000000405', 'a1a1a1a1-0000-4000-8000-000000000103',
      'a1a1a1a1-0000-4000-8000-000000000406', 'a1a1a1a1-0000-4000-8000-000000000103',
      'a1a1a1a1-0000-4000-8000-000000000407', 'a1a1a1a1-0000-4000-8000-000000000103'));

  perform tests_auto.egal((r ->> 'applied')::int, 3, 'trois astreintes posées sur quatre');
  perform tests_auto.ecarte(r,
    'a1a1a1a1-0000-4000-8000-000000000406', 'a1a1a1a1-0000-4000-8000-000000000103',
    'weekend_quota_reached', 'le second weekend dépasserait le plafond');

  perform tests_auto.egal(
    (select weekend_units from v_member_load
      where user_id = 'a1a1a1a1-0000-4000-8000-000000000103'
        and period_id = 'a1a1a1a1-0000-4000-8000-000000000201'),
    1, 'samedi et dimanche du même weekend comptent pour une unité');
  perform tests_auto.egal(
    (select weekends_left from v_member_load
      where user_id = 'a1a1a1a1-0000-4000-8000-000000000103'
        and period_id = 'a1a1a1a1-0000-4000-8000-000000000201'),
    0, 'le reste de weekends tombe à zéro, jamais en dessous');
end $$;

rollback to s5;

-- ===========================================================================
-- 6. Le même membre deux fois sur le même créneau
-- ===========================================================================
\echo ''
\echo '--- 6. un pompier n''est jamais attribué deux fois au même créneau'
savepoint s6;

do $$
declare
  r jsonb;
begin
  r := apply_auto_proposal(
    'a1a1a1a1-0000-4000-8000-000000000301',
    'a1a1a1a1-0000-4000-8000-000000000100',
    tests_auto.plan(
      'a1a1a1a1-0000-4000-8000-000000000402', 'a1a1a1a1-0000-4000-8000-000000000102',
      'a1a1a1a1-0000-4000-8000-000000000402', 'a1a1a1a1-0000-4000-8000-000000000102'));

  perform tests_auto.egal((r ->> 'applied')::int, 1, 'une seule attribution');
  perform tests_auto.ecarte(r,
    'a1a1a1a1-0000-4000-8000-000000000402', 'a1a1a1a1-0000-4000-8000-000000000102',
    'already_assigned', 'le doublon est écarté, pas levé en 23505');
end $$;

rollback to s6;

-- ===========================================================================
-- 7. Les refus globaux
-- ===========================================================================
\echo ''
\echo '--- 7. administrateur, brouillon, abonnement, charge utile'
savepoint s7;

do $$
declare
  r jsonb;
  gros jsonb := '[]'::jsonb;
  i integer;
begin
  -- Un membre ordinaire n'appuie pas sur ce bouton.
  perform tests_auto.code(
    apply_auto_proposal(
      'a1a1a1a1-0000-4000-8000-000000000301',
      'a1a1a1a1-0000-4000-8000-000000000101',
      '[]'::jsonb),
    'not_admin', 'un membre ordinaire');

  -- L'administrateur de la caserne voisine non plus.
  perform tests_auto.code(
    apply_auto_proposal(
      'a1a1a1a1-0000-4000-8000-000000000301',
      'b1b1b1b1-0000-4000-8000-000000000100',
      '[]'::jsonb),
    'not_admin', 'l''administrateur d''une autre caserne');

  perform tests_auto.code(
    apply_auto_proposal(
      '00000000-0000-4000-8000-0000000009ff',
      'a1a1a1a1-0000-4000-8000-000000000100',
      '[]'::jsonb),
    'schedule_not_found', 'un planning qui n''existe pas');

  perform tests_auto.code(
    apply_auto_proposal(
      'a1a1a1a1-0000-4000-8000-000000000301',
      'a1a1a1a1-0000-4000-8000-000000000100',
      '{"picks": []}'::jsonb),
    'invalid_picks', 'une charge utile qui n''est pas un tableau');

  for i in 1..501 loop
    gros := gros || jsonb_build_object(
      'shift_id', 'a1a1a1a1-0000-4000-8000-000000000401',
      'user_id',  'a1a1a1a1-0000-4000-8000-000000000101');
  end loop;
  perform tests_auto.code(
    apply_auto_proposal(
      'a1a1a1a1-0000-4000-8000-000000000301',
      'a1a1a1a1-0000-4000-8000-000000000100',
      gros),
    'too_many_picks', 'une charge utile démesurée');

  -- Une ligne mal formée est écartée, elle ne fait pas tomber le reste du mois.
  r := apply_auto_proposal(
    'a1a1a1a1-0000-4000-8000-000000000301',
    'a1a1a1a1-0000-4000-8000-000000000100',
    '[{"shift_id": "pas-un-uuid", "user_id": "a1a1a1a1-0000-4000-8000-000000000101"},
      {"shift_id": "a1a1a1a1-0000-4000-8000-000000000401",
       "user_id":  "a1a1a1a1-0000-4000-8000-000000000101"}]'::jsonb);
  perform tests_auto.egal((r ->> 'applied')::int, 1,
    'la ligne valide passe malgré la ligne mal formée');
  perform tests_auto.egal(
    (r -> 'skipped' -> 0 ->> 'code'), 'invalid_pick', 'la ligne mal formée est écartée');
end $$;

-- Un planning publié ne se remplit plus automatiquement : chaque geste y fait
-- sonner un téléphone, et cela s'appelle une réattribution (ticket 020). Le
-- point de reprise est à part : `schedules_guard_transition` (0019) interdit le
-- retour de `published` à `draft`, et c'est très bien ainsi.
savepoint s7_publie;

update schedules
   set status = 'published', published_at = now()
 where id = 'a1a1a1a1-0000-4000-8000-000000000301';

do $$
begin
  perform tests_auto.code(
    apply_auto_proposal(
      'a1a1a1a1-0000-4000-8000-000000000301',
      'a1a1a1a1-0000-4000-8000-000000000100',
      '[]'::jsonb),
    'schedule_not_draft', 'un planning publié');
end $$;

rollback to s7_publie;

-- Une caserne suspendue est en lecture seule pour tout le monde.
insert into subscriptions (station_id, status)
values ('a1a1a1a1-0000-4000-8000-000000000001', 'suspended')
on conflict (station_id) do update set status = excluded.status;

do $$
begin
  perform tests_auto.code(
    apply_auto_proposal(
      'a1a1a1a1-0000-4000-8000-000000000301',
      'a1a1a1a1-0000-4000-8000-000000000100',
      '[]'::jsonb),
    'station_suspended', 'une caserne suspendue');
end $$;

rollback to s7;

-- ===========================================================================
-- 8. Les droits
-- ===========================================================================
\echo ''
\echo '--- 8. la fonction est fermée aux clients'
savepoint s8;

do $$
begin
  perform tests_auto.egal(
    has_function_privilege('authenticated',
      'public.apply_auto_proposal(uuid,uuid,jsonb)', 'execute'),
    false, 'authenticated ne l''exécute pas');
  perform tests_auto.egal(
    has_function_privilege('anon',
      'public.apply_auto_proposal(uuid,uuid,jsonb)', 'execute'),
    false, 'anon ne l''exécute pas');
  perform tests_auto.egal(
    has_function_privilege('service_role',
      'public.apply_auto_proposal(uuid,uuid,jsonb)', 'execute'),
    true, 'le rôle de service l''exécute, par l''Edge Function auto-propose');
end $$;

rollback to s8;

\echo ''
\echo '=== Proposition automatique : tous les tests passent ==='

rollback;
