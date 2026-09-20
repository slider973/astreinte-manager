-- Tests des paramètres de caserne (migration 0011, ticket 010).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié
-- ------------------
-- 1. La contrainte `stations_settings_valide` refuse un document mal formé :
--    clé inconnue, clé manquante, type faux, borne dépassée, heure mal écrite,
--    surcharge mal structurée. Et elle accepte les documents légitimes, y
--    compris les surcharges par jour de semaine et par date.
-- 2. Le nom d'une caserne n'est ni vide ni interminable.
-- 3. Un fuseau horaire inconnu est refusé au lieu d'être découvert par le cron.
-- 4. Changer le jour limite — ou le fuseau — recalcule `deadline_at` des
--    périodes **encore ouvertes**, dans le fuseau de la caserne, et ne touche
--    pas les périodes verrouillées.
-- 5. Changer l'effectif requis ne touche **aucun** créneau déjà créé :
--    `shifts.required_count` est une colonne propre à chaque créneau.
-- 6. Seul un admin de la caserne écrit ses paramètres : un membre ordinaire et
--    l'admin d'une autre caserne sont filtrés par la RLS de `stations`.
--
-- Méthode identique à rls_test.sql : pas de pgTAP, une exception fait sortir
-- psql avec un code non nul. Tout le fichier tourne dans une transaction
-- annulée à la fin.
--
-- Fixtures : le seed (caserne A = aaaaaaaa-…-001 « CIS Saint-Martin », admin
-- …100, membres …101+ ; caserne B = bbbbbbbb-…-001, admin …100), plus deux
-- périodes 2099 et un planning de deux créneaux créés ici.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests;

create function tests.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

-- L'écriture doit être refusée par une contrainte ou un déclencheur.
create function tests.echoue(p_sql text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — écriture acceptée alors qu''elle devait être refusée', p_label;
exception
  when others then
    if sqlerrm like 'ECHEC%' then raise; end if;
    raise notice '  ok   % (refusé : %)', p_label, left(sqlerrm, 60);
end $$;

-- L'écriture doit passer et toucher au moins une ligne.
create function tests.allowed(p_sql text, p_label text) returns void
language plpgsql as $$
declare
  n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n < 1 then
    raise exception 'ECHEC : % — écriture autorisée attendue, 0 ligne touchée', p_label;
  end if;
  raise notice '  ok   % (% ligne(s))', p_label, n;
end $$;

-- L'écriture doit être refusée par la RLS : erreur, ou 0 ligne (une politique
-- `using` qui ne matche pas filtre silencieusement).
create function tests.denied(p_sql text, p_label text) returns void
language plpgsql as $$
declare
  n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n > 0 then
    raise exception 'ECHEC : % — % ligne(s) écrite(s) alors que l''écriture devait être refusée', p_label, n;
  end if;
  raise notice '  ok   % (0 ligne, filtré par USING)', p_label;
exception
  when insufficient_privilege then
    raise notice '  ok   % (refusé : %)', p_label, sqlerrm;
  when raise_exception then
    if sqlerrm like 'ECHEC%' then raise; end if;
    raise notice '  ok   % (refusé par trigger : %)', p_label, sqlerrm;
end $$;

-- Un document `settings` complet, avec la ou les clés passées en surcharge.
create function tests.settings(p_surcharge jsonb default '{}'::jsonb) returns jsonb
language sql immutable as $$
  select '{
    "day_start": "07:00",
    "day_end": "19:00",
    "required_day": 1,
    "required_night": 1,
    "availability_deadline_day": 15,
    "response_reminder_hours": 24,
    "response_email_hours": 48,
    "late_report_hours": 72
  }'::jsonb || p_surcharge;
$$;

grant usage on schema tests to authenticated, anon;
grant execute on all functions in schema tests to authenticated, anon;

-- ===========================================================================
-- Fixtures
-- ===========================================================================
-- Deux périodes très loin dans le futur : leur date limite ne dépend pas du
-- jour où le test tourne. 2099-01 est ouverte, 2099-02 est verrouillée.
insert into periods (id, station_id, year, month, status, deadline_at, locked_at)
values
  ('22222222-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001',
   2099, 1, 'open',   make_timestamptz(2098, 12, 15, 23, 59, 59, 'Europe/Paris'), null),
  ('22222222-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001',
   2099, 2, 'locked', make_timestamptz(2099,  1, 15, 23, 59, 59, 'Europe/Paris'),
   make_timestamptz(2099, 1, 15, 23, 59, 59, 'Europe/Paris'));

insert into schedules (id, station_id, period_id, status, created_by)
values ('22222222-0000-4000-8000-000000000003',
        'aaaaaaaa-0000-4000-8000-000000000001',
        '22222222-0000-4000-8000-000000000001',
        'draft',
        'aaaaaaaa-0000-4000-8000-000000000100');

-- Créneaux générés « avec les settings du moment » : 1 le jour, 1 la nuit.
insert into shifts (id, station_id, schedule_id, date, slot, required_count)
values
  ('22222222-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000001',
   '22222222-0000-4000-8000-000000000003', '2099-01-10', 'day', 1),
  ('22222222-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-000000000001',
   '22222222-0000-4000-8000-000000000003', '2099-01-10', 'night', 1);

\echo ''
\echo '== 1. Contrainte stations_settings_valide — documents refusés'

select tests.echoue(
  $$update stations set settings = tests.settings('{"required_days": 2}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'clé inconnue (required_days)');

select tests.echoue(
  $$update stations set settings = tests.settings() - 'required_day'
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'clé obligatoire manquante (required_day)');

select tests.echoue(
  $$update stations set settings = '[]'::jsonb
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'document qui n''est pas un objet');

select tests.echoue(
  $$update stations set settings = tests.settings('{"day_start": "7:00"}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'heure sans zéro initial (7:00)');

select tests.echoue(
  $$update stations set settings = tests.settings('{"day_end": "25:00"}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'heure impossible (25:00)');

select tests.echoue(
  $$update stations set settings = tests.settings('{"day_start": "07:60"}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'minutes impossibles (07:60)');

select tests.echoue(
  $$update stations set settings = tests.settings('{"day_start": "19:00"}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'jour qui commence et finit à la même heure');

select tests.echoue(
  $$update stations set settings = tests.settings('{"required_day": "deux"}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'effectif en toutes lettres');

select tests.echoue(
  $$update stations set settings = tests.settings('{"required_day": 1.5}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'effectif décimal (1.5)');

select tests.echoue(
  $$update stations set settings = tests.settings('{"required_night": -1}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'effectif négatif');

select tests.echoue(
  $$update stations set settings = tests.settings('{"required_night": 51}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'effectif au-delà de 50');

select tests.echoue(
  $$update stations set settings = tests.settings('{"availability_deadline_day": 0}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'jour limite 0');

select tests.echoue(
  $$update stations set settings = tests.settings('{"availability_deadline_day": 31}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'jour limite 31 (absent de février)');

select tests.echoue(
  $$update stations set settings = tests.settings('{"response_reminder_hours": 0}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'délai de relance nul');

select tests.echoue(
  $$update stations set settings = tests.settings('{"late_report_hours": 400}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'délai de relance au-delà de deux semaines');

select tests.echoue(
  $$update stations set settings = tests.settings('{"required_overrides": []}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'surcharges qui ne sont pas un objet');

select tests.echoue(
  $$update stations set settings = tests.settings('{"required_overrides": {"samedi": {"day": 2}}}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'jour de semaine en français (samedi)');

select tests.echoue(
  $$update stations set settings = tests.settings('{"required_overrides": {"2026-02-30": {"day": 2}}}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'date qui n''existe pas (30 février)');

select tests.echoue(
  $$update stations set settings = tests.settings('{"required_overrides": {"31/12/2026": {"day": 2}}}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'date au format français');

select tests.echoue(
  $$update stations set settings = tests.settings('{"required_overrides": {"sat": {}}}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'surcharge vide');

select tests.echoue(
  $$update stations set settings = tests.settings('{"required_overrides": {"sat": {"evening": 2}}}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'créneau inconnu dans une surcharge (evening)');

select tests.echoue(
  $$update stations set settings = tests.settings('{"required_overrides": {"sat": {"day": "2"}}}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'effectif de surcharge en chaîne');

select tests.echoue(
  $$update stations set settings = tests.settings('{"required_overrides": {"sat": 2}}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'surcharge qui n''est pas un objet');

\echo ''
\echo '== 2. Contrainte stations_settings_valide — documents acceptés'

select tests.allowed(
  $$update stations set settings = tests.settings(
      '{"required_overrides": {"sat": {"day": 2}, "sun": {"day": 2, "night": 3}, "2026-12-31": {"night": 3}}}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'surcharges par jour de semaine et par date');

select tests.allowed(
  $$update stations set settings = tests.settings('{"required_overrides": {}}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'surcharges présentes mais vides');

select tests.allowed(
  $$update stations set settings = tests.settings(
      '{"required_day": 0, "availability_deadline_day": 28, "late_report_hours": 336}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'bornes extrêmes légitimes (0, 28, 336)');

select tests.allowed(
  $$update stations set settings = tests.settings()
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'retour au document par défaut');

\echo ''
\echo '== 3. Nom de caserne'

select tests.echoue(
  $$update stations set name = '   ' where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'nom vide');

select tests.echoue(
  $$update stations set name = repeat('x', 81) where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'nom de plus de 80 caractères');

select tests.allowed(
  $$update stations set name = 'CIS Saint-Martin-en-Vercors'
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'nom normal');

\echo ''
\echo '== 4. Fuseau horaire'

select tests.echoue(
  $$update stations set timezone = 'Europe/Pariss'
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'fuseau horaire inconnu');

\echo ''
\echo '== 5. Recalcul des dates limites'

-- L'écriture est faite par l'admin de la caserne, comme dans l'application :
-- le déclencheur doit fonctionner sous la RLS de qui écrit.
savepoint avant_recalcul;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.allowed(
  $$update stations set settings = tests.settings('{"availability_deadline_day": 5}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'un admin change le jour limite de sa caserne');

reset role;

select tests.check(
  (select deadline_at from periods where id = '22222222-0000-4000-8000-000000000001')
    = make_timestamptz(2098, 12, 5, 23, 59, 59, 'Europe/Paris'),
  'la période ouverte ferme désormais le 5 décembre 23:59:59 (heure de Paris)');

select tests.check(
  (select deadline_at from periods where id = '22222222-0000-4000-8000-000000000002')
    = make_timestamptz(2099, 1, 15, 23, 59, 59, 'Europe/Paris'),
  'la période verrouillée garde sa date limite');

select tests.check(
  (select deadline_at from periods p
     join stations s on s.id = p.station_id
    where p.station_id = 'bbbbbbbb-0000-4000-8000-000000000001'
    order by p.year, p.month limit 1)
    = (select period_deadline_at(p.year, p.month,
         (s.settings ->> 'availability_deadline_day')::int, s.timezone)
       from periods p join stations s on s.id = p.station_id
       where p.station_id = 'bbbbbbbb-0000-4000-8000-000000000001'
       order by p.year, p.month limit 1),
  'la caserne B n''a pas bougé');

-- Le fuseau compte : même jour du mois, autre instant.
select tests.allowed(
  $$update stations set timezone = 'Indian/Reunion'
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'changer le fuseau de la caserne');

select tests.check(
  (select deadline_at from periods where id = '22222222-0000-4000-8000-000000000001')
    = make_timestamptz(2098, 12, 5, 23, 59, 59, 'Indian/Reunion'),
  'la date limite suit le nouveau fuseau');

select tests.check(
  (select deadline_at from periods where id = '22222222-0000-4000-8000-000000000001')
    <> make_timestamptz(2098, 12, 5, 23, 59, 59, 'Europe/Paris'),
  'et ce n''est pas le même instant qu''à Paris');

-- La trace du changement existe : un membre qui trouve son mois fermé plus tôt
-- doit pouvoir être renseigné.
select tests.check(
  (select count(*) from audit_log
    where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
      and action = 'station.settings_updated') >= 1,
  'le changement est journalisé dans audit_log');

rollback to savepoint avant_recalcul;

\echo ''
\echo '== 6. Effectif requis : les créneaux déjà créés ne bougent pas'

select tests.check(
  (select count(*) from shifts
    where schedule_id = '22222222-0000-4000-8000-000000000003'
      and required_count = 1) = 2,
  'départ : deux créneaux à 1 pompier requis');

savepoint avant_effectif;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.allowed(
  $$update stations set settings = tests.settings(
      '{"required_day": 3, "required_night": 4,
        "required_overrides": {"sat": {"day": 5}}}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'un admin triple l''effectif requis de sa caserne');

reset role;

select tests.check(
  (select count(*) from shifts
    where schedule_id = '22222222-0000-4000-8000-000000000003'
      and required_count = 1) = 2,
  'les deux créneaux existants gardent leur required_count');

select tests.check(
  (select count(*) from shifts
    where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
      and required_count <> 1) = 0,
  'aucun créneau de la caserne n''a été réécrit');

-- Et la valeur qui servira aux plannings **créés ensuite** est bien la nouvelle.
select tests.check(
  (select (settings ->> 'required_day')::int from stations
    where id = 'aaaaaaaa-0000-4000-8000-000000000001') = 3,
  'le nouvel effectif est celui que lira la prochaine création de planning');

rollback to savepoint avant_effectif;

\echo ''
\echo '== 7. Qui a le droit d''écrire les paramètres'

-- Un membre ordinaire de la caserne A.
savepoint avant_membre;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

select tests.denied(
  $$update stations set settings = tests.settings('{"required_day": 9}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'un membre ne change pas les paramètres de sa caserne');

select tests.denied(
  $$update stations set name = 'Chez moi'
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'un membre ne renomme pas sa caserne');

rollback to savepoint avant_membre;

-- L'admin de la caserne B.
savepoint avant_admin_b;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.denied(
  $$update stations set settings = tests.settings('{"required_day": 9}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'l''admin de la caserne B ne touche pas la caserne A');

select tests.allowed(
  $$update stations set settings = tests.settings('{"required_day": 2}')
      where id = 'bbbbbbbb-0000-4000-8000-000000000001'$$,
  'l''admin de la caserne B règle la sienne');

rollback to savepoint avant_admin_b;

-- Un compte désactivé de la caserne A n'est plus admin de rien.
savepoint avant_desactive;
update memberships set status = 'disabled'
  where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
    and user_id = 'aaaaaaaa-0000-4000-8000-000000000101';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

select tests.denied(
  $$update stations set settings = tests.settings('{"required_day": 9}')
      where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'un membre désactivé non plus');

rollback to savepoint avant_desactive;

\echo ''
\echo 'station_settings_test : OK'

rollback;
