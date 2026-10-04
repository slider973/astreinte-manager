-- Un pompier dans deux casernes (migration 0040, ticket 072).
-- Lancement : scripts/test_rls.sh (le script joue tous les supabase/tests/*.sql).
--
-- Le fil, dans l'ordre où il se vit
-- ---------------------------------
-- Pauline est pompière à **Bravo**. L'administrateur d'**Alpha** l'invite.
--
-- 1. Elle voit l'invitation d'Alpha alors qu'elle est déjà rattachée à Bravo,
--    l'accepte par son identifiant, et a **deux appartenances actives**.
-- 2. La grille d'Alpha dit qu'elle est prise ailleurs, cellule par cellule, et
--    **seulement** cela : `X`, ni caserne, ni heure, ni statut. Les heures de
--    Bravo ne sont pas celles d'Alpha (jour 08:00–20:00 contre 07:00–19:00) :
--    c'est le chevauchement **réel** qui compte, pas la date et le créneau. La
--    grille et `member_taken_elsewhere` disent la même chose sur tout le mois.
-- 3. La proposition automatique d'Alpha l'écarte (`taken_elsewhere`) là où elle
--    est prise à Bravo, la pose partout ailleurs, et met un collègue à sa place.
--    Un refus à Bravo ne bloque rien. Et dans l'autre sens : le brouillon
--    d'Alpha la rend prise ailleurs pour Bravo.
-- 4. Aucune donnée de Bravo n'est lisible depuis Alpha, et réciproquement — ni
--    par la table, ni par la matrice, ni par la réponse de la proposition.
-- 5. Les droits : les deux fonctions nouvelles sont fermées aux clients, la
--    matrice leur reste ouverte, `apply_auto_proposal` reste au rôle de service.
-- 6. La RLS n'a pas bougé : aucune politique ne s'appuie sur 0040, et toutes les
--    tables métier restent sous RLS.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
-- Avril 2041, qu'aucun autre fichier ne touche.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_multi;

create function tests_multi.egal(p_obtenu anyelement, p_attendu anyelement, p_label text) returns void
language plpgsql as $$
begin
  if p_obtenu is distinct from p_attendu then
    raise exception 'ECHEC : % — obtenu [%], attendu [%]', p_label, p_obtenu, p_attendu;
  end if;
  raise notice '  ok   % = %', p_label, coalesce(p_obtenu::text, 'NULL');
end $$;

create function tests_multi.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

-- Le motif d'une ligne écartée par `apply_auto_proposal`.
create function tests_multi.ecarte(
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
  if trouve is distinct from p_code then
    raise exception 'ECHEC : % — écartée pour [%] au lieu de [%] (skipped = %)',
      p_label, trouve, p_code, p_resultat -> 'skipped';
  end if;
  raise notice '  ok   % (%)', p_label, p_code;
end $$;

-- Une ligne posée (et non écartée) par `apply_auto_proposal`.
create function tests_multi.pose(p_shift uuid, p_user uuid, p_label text) returns void
language plpgsql as $$
begin
  if not exists (
    select 1 from assignments
     where shift_id = p_shift and user_id = p_user and status = 'proposed'
  ) then
    raise exception 'ECHEC : % — aucune attribution posée', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

grant usage on schema tests_multi to authenticated, anon;
grant execute on all functions in schema tests_multi to authenticated, anon;

\echo ''
\echo '=== Un pompier dans deux casernes (0040) ==='

-- ===========================================================================
-- Fixtures
-- ===========================================================================
-- Alpha : jour 07:00–19:00. Bravo : jour 08:00–20:00. Même fuseau.
--
--   72a0…0100  Arnaud, administrateur d'Alpha
--   72a0…0101  Quentin, pompier d'Alpha seulement — le témoin
--   72b0…0100  Bérénice, administratrice de Bravo
--   72b0…0101  Pauline, pompière de Bravo, bientôt aussi d'Alpha

insert into stations (id, name, slug, timezone, settings) values
  ('72a00000-0000-4000-8000-000000000001', 'CIS Alpha 72', 'cis-alpha-72', 'Europe/Paris',
   '{"day_start": "07:00", "day_end": "19:00",
     "required_day": 1, "required_night": 1,
     "availability_deadline_day": 15,
     "response_reminder_hours": 24, "response_email_hours": 48,
     "late_report_hours": 72}'::jsonb),
  ('72b00000-0000-4000-8000-000000000001', 'CIS Bravo 72', 'cis-bravo-72', 'Europe/Paris',
   '{"day_start": "08:00", "day_end": "20:00",
     "required_day": 1, "required_night": 1,
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
  ('72a00000-0000-4000-8000-000000000100'::uuid, 'arnaud@alpha72.test',   'Arnaud',   'Aubert'),
  ('72a00000-0000-4000-8000-000000000101'::uuid, 'quentin@alpha72.test',  'Quentin',  'Quéré'),
  ('72b00000-0000-4000-8000-000000000100'::uuid, 'berenice@bravo72.test', 'Bérénice', 'Blanc'),
  ('72b00000-0000-4000-8000-000000000101'::uuid, 'pauline@bravo72.test',  'Pauline',  'Perrin')
) as u(id, email, first_name, last_name);

insert into memberships (station_id, user_id, role, status, display_name) values
  ('72a00000-0000-4000-8000-000000000001', '72a00000-0000-4000-8000-000000000100', 'admin',  'active', 'Arnaud A.'),
  ('72a00000-0000-4000-8000-000000000001', '72a00000-0000-4000-8000-000000000101', 'member', 'active', 'Quentin Q.'),
  ('72b00000-0000-4000-8000-000000000001', '72b00000-0000-4000-8000-000000000100', 'admin',  'active', 'Bérénice B.'),
  ('72b00000-0000-4000-8000-000000000001', '72b00000-0000-4000-8000-000000000101', 'member', 'active', 'Pauline P.');

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('72a00000-0000-4000-8000-000000000201', '72a00000-0000-4000-8000-000000000001', 2041, 4, 'locked', '2041-03-15 23:59:59+01'),
  ('72b00000-0000-4000-8000-000000000201', '72b00000-0000-4000-8000-000000000001', 2041, 4, 'locked', '2041-03-15 23:59:59+01');

-- Alpha construit son brouillon ; Bravo a déjà publié le sien.
insert into schedules (id, station_id, period_id, created_by) values
  ('72a00000-0000-4000-8000-000000000301', '72a00000-0000-4000-8000-000000000001',
   '72a00000-0000-4000-8000-000000000201', '72a00000-0000-4000-8000-000000000100'),
  ('72b00000-0000-4000-8000-000000000301', '72b00000-0000-4000-8000-000000000001',
   '72b00000-0000-4000-8000-000000000201', '72b00000-0000-4000-8000-000000000100');

-- Les créneaux d'Alpha (brouillon), un par cas :
--   401  10 nuit   19:00 → 07:00  chevauche la nuit de Bravo du 10 (20:00 → 08:00)
--   402  11 jour   07:00 → 19:00  chevauche la fin de cette nuit, de 07:00 à 08:00 —
--                                  autre date, autre créneau : pris quand même
--   403  12 jour                  libre à Bravo
--   404  13 nuit                  Bravo l'avait proposée ce soir-là, elle a refusé
--   405  14 jour                  libre
--   406  10 jour   07:00 → 19:00  finit **avant** la nuit de Bravo (20:00) : libre
--   407  20 jour                  Bravo l'a acceptée ce jour-là (08:00 → 20:00)
insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  ('72a00000-0000-4000-8000-000000000401', '72a00000-0000-4000-8000-000000000001',
   '72a00000-0000-4000-8000-000000000301', '2041-04-10', 'night', 1),
  ('72a00000-0000-4000-8000-000000000402', '72a00000-0000-4000-8000-000000000001',
   '72a00000-0000-4000-8000-000000000301', '2041-04-11', 'day',   1),
  ('72a00000-0000-4000-8000-000000000403', '72a00000-0000-4000-8000-000000000001',
   '72a00000-0000-4000-8000-000000000301', '2041-04-12', 'day',   1),
  ('72a00000-0000-4000-8000-000000000404', '72a00000-0000-4000-8000-000000000001',
   '72a00000-0000-4000-8000-000000000301', '2041-04-13', 'night', 1),
  ('72a00000-0000-4000-8000-000000000405', '72a00000-0000-4000-8000-000000000001',
   '72a00000-0000-4000-8000-000000000301', '2041-04-14', 'day',   1),
  ('72a00000-0000-4000-8000-000000000406', '72a00000-0000-4000-8000-000000000001',
   '72a00000-0000-4000-8000-000000000301', '2041-04-10', 'day',   1),
  ('72a00000-0000-4000-8000-000000000407', '72a00000-0000-4000-8000-000000000001',
   '72a00000-0000-4000-8000-000000000301', '2041-04-20', 'day',   1);

-- Les créneaux de Bravo.
insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  ('72b00000-0000-4000-8000-000000000401', '72b00000-0000-4000-8000-000000000001',
   '72b00000-0000-4000-8000-000000000301', '2041-04-10', 'night', 1),
  ('72b00000-0000-4000-8000-000000000402', '72b00000-0000-4000-8000-000000000001',
   '72b00000-0000-4000-8000-000000000301', '2041-04-13', 'night', 1),
  ('72b00000-0000-4000-8000-000000000403', '72b00000-0000-4000-8000-000000000001',
   '72b00000-0000-4000-8000-000000000301', '2041-04-20', 'day',   1),
  ('72b00000-0000-4000-8000-000000000404', '72b00000-0000-4000-8000-000000000001',
   '72b00000-0000-4000-8000-000000000301', '2041-04-12', 'day',   1);

-- Bravo publie : Pauline est proposée le 10 de nuit, a refusé le 13 de nuit et
-- a accepté le 20 de jour. Écritures serveur, comme `publish_schedule` et la
-- réponse du membre les auraient laissées.
update schedules set status = 'published', published_at = '2041-03-20 10:00:00+01'
 where id = '72b00000-0000-4000-8000-000000000301';

insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, responded_at, created_by) values
  ('72b00000-0000-4000-8000-000000000501', '72b00000-0000-4000-8000-000000000001',
   '72b00000-0000-4000-8000-000000000401', '72b00000-0000-4000-8000-000000000101',
   'proposed', '2041-03-20 10:00:00+01', null, '72b00000-0000-4000-8000-000000000100'),
  ('72b00000-0000-4000-8000-000000000502', '72b00000-0000-4000-8000-000000000001',
   '72b00000-0000-4000-8000-000000000402', '72b00000-0000-4000-8000-000000000101',
   'declined', '2041-03-20 10:00:00+01', '2041-03-21 09:00:00+01', '72b00000-0000-4000-8000-000000000100'),
  ('72b00000-0000-4000-8000-000000000503', '72b00000-0000-4000-8000-000000000001',
   '72b00000-0000-4000-8000-000000000403', '72b00000-0000-4000-8000-000000000101',
   'accepted', '2041-03-20 10:00:00+01', '2041-03-21 09:00:00+01', '72b00000-0000-4000-8000-000000000100');

-- Une notification de Bravo pour Pauline : elle ne doit apparaître qu'à elle.
insert into notifications (station_id, user_id, type, channel, title, body, data) values
  ('72b00000-0000-4000-8000-000000000001', '72b00000-0000-4000-8000-000000000101',
   'assignment_proposed', 'inapp', 'Astreinte proposée le 10 avril, nuit', 'CIS Bravo 72',
   '{"route": "/proposals", "station_id": "72b00000-0000-4000-8000-000000000001"}'::jsonb);

-- L'invitation d'Alpha, à l'adresse de Pauline.
insert into invitations (id, station_id, email, role, invited_by, expires_at) values
  ('72a00000-0000-4000-8000-000000000601', '72a00000-0000-4000-8000-000000000001',
   'pauline@bravo72.test', 'member', '72a00000-0000-4000-8000-000000000100',
   now() + interval '7 days');

-- ===========================================================================
-- 1. Deux appartenances actives
-- ===========================================================================
\echo ''
\echo '--- 1. une pompière de Bravo accepte l''invitation d''Alpha'

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"72b00000-0000-4000-8000-000000000101","role":"authenticated","email":"pauline@bravo72.test"}';

select tests_multi.check(
  exists (select 1 from my_pending_invitations()
           where id = '72a00000-0000-4000-8000-000000000601'
             and station_name = 'CIS Alpha 72' and status = 'pending'),
  'déjà rattachée à Bravo, elle voit l''invitation d''Alpha en attente');

reset role;

do $$
declare r jsonb;
begin
  r := accept_invitation_by_id('72a00000-0000-4000-8000-000000000601',
                               '72b00000-0000-4000-8000-000000000101',
                               'pauline@bravo72.test');
  perform tests_multi.check((r ->> 'ok')::boolean, 'l''acceptation par identifiant réussit');
  perform tests_multi.egal(r #>> '{membership,station_id}',
    '72a00000-0000-4000-8000-000000000001', 'la réponse désigne la caserne d''Alpha');
  perform tests_multi.egal(r #>> '{station,name}', 'CIS Alpha 72',
    'la réponse nomme Alpha, pour que l''app y bascule');
end $$;

-- Sous sa propre session : deux appartenances actives, deux casernes.
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"72b00000-0000-4000-8000-000000000101","role":"authenticated","email":"pauline@bravo72.test"}';

select tests_multi.egal(
  (select count(*)::int from memberships
    where user_id = '72b00000-0000-4000-8000-000000000101' and status = 'active'),
  2, 'deux appartenances actives, lues sous sa session');

select tests_multi.check(
  is_member('72a00000-0000-4000-8000-000000000001')
  and is_member('72b00000-0000-4000-8000-000000000001'),
  'membre d''Alpha et de Bravo à la fois');

select tests_multi.check(
  not is_admin('72a00000-0000-4000-8000-000000000001')
  and not is_admin('72b00000-0000-4000-8000-000000000001'),
  'simple membre dans les deux : une seconde caserne n''apporte aucun droit');

select tests_multi.egal(
  (select count(*)::int from stations
    where id in ('72a00000-0000-4000-8000-000000000001', '72b00000-0000-4000-8000-000000000001')),
  2, 'elle lit les deux casernes — c''est ce que le sélecteur affiche');

reset role;

-- Ses disponibilités à Alpha, et celles du témoin : toutes « disponible ».
insert into availabilities (station_id, user_id, date, slot, status, set_by)
select s.station_id, m.user_id, s.date, s.slot, 'available', m.user_id
  from shifts s
 cross join (values
   ('72b00000-0000-4000-8000-000000000101'::uuid),
   ('72a00000-0000-4000-8000-000000000101'::uuid)) as m(user_id)
 where s.schedule_id = '72a00000-0000-4000-8000-000000000301';

-- ===========================================================================
-- 2. La grille d'Alpha : prise ailleurs, et rien d'autre
-- ===========================================================================
\echo ''
\echo '--- 2. availability_matrix : « X » là où le créneau chevauche, et seulement cela'

set local role authenticated;
set local request.jwt.claims = '{"sub":"72a00000-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  ligne record;
  temoin record;
begin
  select * into ligne
    from availability_matrix('72a00000-0000-4000-8000-000000000001',
                             '72a00000-0000-4000-8000-000000000201')
   where user_id = '72b00000-0000-4000-8000-000000000101';

  perform tests_multi.check(ligne.user_id is not null,
    'Pauline a sa ligne dans la grille d''Alpha');
  perform tests_multi.egal(length(ligne.day_taken_elsewhere), 30,
    'day_taken_elsewhere : un caractère par jour d''avril');
  perform tests_multi.egal(length(ligne.night_taken_elsewhere), 30,
    'night_taken_elsewhere : un caractère par jour d''avril');

  -- Jour : le 11 (07:00–08:00 sous la nuit de Bravo du 10) et le 20 (garde
  -- acceptée). **Pas** le 10 : 19:00 précède 20:00.
  perform tests_multi.egal(ligne.day_taken_elsewhere,
    repeat('.', 10) || 'X' || repeat('.', 8) || 'X' || repeat('.', 10),
    'jours pris ailleurs : le 11 et le 20');
  -- Nuit : le 10 (proposée à Bravo) et le 20 (19:00–20:00 sous le jour de
  -- Bravo). **Pas** le 13 : elle a refusé, un refus ne l'occupe pas.
  perform tests_multi.egal(ligne.night_taken_elsewhere,
    repeat('.', 9) || 'X' || repeat('.', 9) || 'X' || repeat('.', 10),
    'nuits prises ailleurs : le 10 et le 20, pas le 13 refusé');

  -- Les colonnes d'avant n'ont pas bougé.
  perform tests_multi.egal(ligne.day_slots,
    repeat('.', 9) || 'DDD.D' || repeat('.', 5) || 'D' || repeat('.', 10),
    'day_slots inchangé (jours 10, 11, 12, 14 et 20 saisis)');

  -- Le témoin, qui n'est que d'Alpha : jamais pris ailleurs.
  select * into temoin
    from availability_matrix('72a00000-0000-4000-8000-000000000001',
                             '72a00000-0000-4000-8000-000000000201')
   where user_id = '72a00000-0000-4000-8000-000000000101';
  perform tests_multi.egal(temoin.day_taken_elsewhere || temoin.night_taken_elsewhere,
    repeat('.', 60), 'un membre d''une seule caserne n''est jamais pris ailleurs');

  -- **Rien de Bravo dans la ligne** : ni son identifiant, ni son nom, ni ceux
  -- de ses créneaux, plannings ou attributions. Ce que l'administrateur d'Alpha
  -- apprend tient dans les « X ».
  perform tests_multi.check(
    position('72b00000-0000-4000-8000-000000000001' in row_to_json(ligne)::text) = 0
    and position('Bravo' in row_to_json(ligne)::text) = 0
    and position('72b00000-0000-4000-8000-0000000004' in row_to_json(ligne)::text) = 0
    and position('72b00000-0000-4000-8000-0000000005' in row_to_json(ligne)::text) = 0
    and position('72b00000-0000-4000-8000-0000000003' in row_to_json(ligne)::text) = 0,
    'la ligne de la grille ne porte aucune donnée de Bravo');
end $$;

reset role;

-- La grille et la fonction disent la même chose, sur **tout** le mois et pour
-- les deux membres : deux écritures de la même règle, une seule réponse.
do $$
declare
  ligne record;
  jour  integer;
  ecarts integer := 0;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"72a00000-0000-4000-8000-000000000100","role":"authenticated"}', true);
  for ligne in
    select * from availability_matrix('72a00000-0000-4000-8000-000000000001',
                                      '72a00000-0000-4000-8000-000000000201')
  loop
    for jour in 1 .. 30 loop
      if (substr(ligne.day_taken_elsewhere, jour, 1) = 'X')
         is distinct from member_taken_elsewhere('72a00000-0000-4000-8000-000000000001',
           ligne.user_id, make_date(2041, 4, jour), 'day') then
        ecarts := ecarts + 1;
      end if;
      if (substr(ligne.night_taken_elsewhere, jour, 1) = 'X')
         is distinct from member_taken_elsewhere('72a00000-0000-4000-8000-000000000001',
           ligne.user_id, make_date(2041, 4, jour), 'night') then
        ecarts := ecarts + 1;
      end if;
    end loop;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  perform tests_multi.egal(ecarts, 0,
    'parité grille / member_taken_elsewhere sur 30 jours × 2 créneaux × 2 membres');
end $$;

-- La relève n'est pas un chevauchement : dans une même caserne, le jour finit
-- quand la nuit commence, et la nuit quand le jour suivant commence.
select tests_multi.check(
  not (shift_window('2041-04-10', 'day', 'Europe/Paris', s.settings)
       && shift_window('2041-04-10', 'night', 'Europe/Paris', s.settings))
  and not (shift_window('2041-04-10', 'night', 'Europe/Paris', s.settings)
       && shift_window('2041-04-11', 'day', 'Europe/Paris', s.settings)),
  'shift_window : la relève (19:00 / 19:00) ne chevauche pas')
from stations s where s.id = '72a00000-0000-4000-8000-000000000001';

-- Le passage à l'heure d'hiver : la nuit du 25 octobre 2026 dure treize heures.
select tests_multi.egal(
  upper(shift_window('2026-10-24', 'night', 'Europe/Paris', s.settings))
    - lower(shift_window('2026-10-24', 'night', 'Europe/Paris', s.settings)),
  interval '13 hours', 'shift_window : la nuit du changement d''heure, en heures réelles')
from stations s where s.id = '72a00000-0000-4000-8000-000000000001';

-- ===========================================================================
-- 3. La proposition automatique ne la double pas
-- ===========================================================================
\echo ''
\echo '--- 3. apply_auto_proposal : taken_elsewhere'

do $$
declare
  r jsonb;
  p constant uuid := '72b00000-0000-4000-8000-000000000101';
  q constant uuid := '72a00000-0000-4000-8000-000000000101';
begin
  r := apply_auto_proposal(
    '72a00000-0000-4000-8000-000000000301',
    '72a00000-0000-4000-8000-000000000100',
    jsonb_build_array(
      jsonb_build_object('shift_id', '72a00000-0000-4000-8000-000000000401', 'user_id', p),
      jsonb_build_object('shift_id', '72a00000-0000-4000-8000-000000000402', 'user_id', p),
      jsonb_build_object('shift_id', '72a00000-0000-4000-8000-000000000403', 'user_id', p),
      jsonb_build_object('shift_id', '72a00000-0000-4000-8000-000000000404', 'user_id', p),
      jsonb_build_object('shift_id', '72a00000-0000-4000-8000-000000000405', 'user_id', p),
      jsonb_build_object('shift_id', '72a00000-0000-4000-8000-000000000406', 'user_id', p),
      jsonb_build_object('shift_id', '72a00000-0000-4000-8000-000000000407', 'user_id', p),
      -- Le témoin prend la nuit du 10, que Pauline ne peut pas tenir.
      jsonb_build_object('shift_id', '72a00000-0000-4000-8000-000000000401', 'user_id', q)));

  perform tests_multi.check((r ->> 'ok')::boolean, 'le plan s''applique');
  perform tests_multi.egal((r ->> 'applied')::int, 5, 'attributions posées');
  perform tests_multi.egal(jsonb_array_length(r -> 'skipped'), 3, 'lignes écartées');
  perform tests_multi.egal((r ->> 'taken_elsewhere')::int, 3,
    'la réponse compte les lignes écartées pour taken_elsewhere');

  perform tests_multi.ecarte(r, '72a00000-0000-4000-8000-000000000401', p, 'taken_elsewhere',
    'nuit du 10 : proposée à Bravo le même soir');
  perform tests_multi.ecarte(r, '72a00000-0000-4000-8000-000000000402', p, 'taken_elsewhere',
    'jour du 11 : la nuit de Bravo finit à 08:00, le jour d''Alpha commence à 07:00');
  perform tests_multi.ecarte(r, '72a00000-0000-4000-8000-000000000407', p, 'taken_elsewhere',
    'jour du 20 : acceptée à Bravo');

  perform tests_multi.pose('72a00000-0000-4000-8000-000000000403', p, 'jour du 12 : libre, posée');
  perform tests_multi.pose('72a00000-0000-4000-8000-000000000404', p,
    'nuit du 13 : un refus à Bravo ne l''occupe pas, posée');
  perform tests_multi.pose('72a00000-0000-4000-8000-000000000405', p, 'jour du 14 : libre, posée');
  perform tests_multi.pose('72a00000-0000-4000-8000-000000000406', p,
    'jour du 10 : finit à 19:00, avant la nuit de Bravo, posée');
  perform tests_multi.pose('72a00000-0000-4000-8000-000000000401', q,
    'nuit du 10 : le témoin prend la place');

  -- La réponse ne nomme que des objets d'Alpha (et Pauline, qui est d'Alpha
  -- aussi) : aucun créneau, aucune attribution de Bravo.
  perform tests_multi.check(
    position('72b00000-0000-4000-8000-0000000004' in r::text) = 0
    and position('72b00000-0000-4000-8000-0000000005' in r::text) = 0,
    'la réponse ne porte aucun créneau ni aucune attribution de Bravo');
  perform tests_multi.check(
    position('72b00000-0000-4000-8000-000000000001' in r::text) = 0,
    'la réponse ne porte pas l''identifiant de Bravo');

  -- Bravo n'a pas bougé d'une ligne.
  perform tests_multi.egal(
    (select count(*)::int from assignments
      where station_id = '72b00000-0000-4000-8000-000000000001'),
    3, 'les attributions de Bravo sont intactes');
end $$;

-- Dans l'autre sens : le **brouillon** d'Alpha la rend prise pour Bravo.
-- Proposée compte, brouillon compris.
select tests_multi.check(
  member_taken_elsewhere('72b00000-0000-4000-8000-000000000001',
    '72b00000-0000-4000-8000-000000000101', '2041-04-12', 'day'),
  'le brouillon d''Alpha (jour du 12) la rend prise ailleurs pour Bravo');

select tests_multi.check(
  not member_taken_elsewhere('72b00000-0000-4000-8000-000000000001',
    '72b00000-0000-4000-8000-000000000101', '2041-04-12', 'night'),
  'la nuit du 12 de Bravo (20:00) suit le jour d''Alpha (19:00) : libre');

-- Ses propres gardes de Bravo ne la rendent pas « prise ailleurs » pour Bravo.
select tests_multi.check(
  not member_taken_elsewhere('72b00000-0000-4000-8000-000000000001',
    '72b00000-0000-4000-8000-000000000101', '2041-04-20', 'day'),
  'une garde de la caserne elle-même n''est pas « ailleurs »');

set local role authenticated;
set local request.jwt.claims = '{"sub":"72b00000-0000-4000-8000-000000000100","role":"authenticated"}';

select tests_multi.egal(
  (select substr(day_taken_elsewhere, 12, 1)
     from availability_matrix('72b00000-0000-4000-8000-000000000001',
                              '72b00000-0000-4000-8000-000000000201')
    where user_id = '72b00000-0000-4000-8000-000000000101'),
  'X', 'la grille de Bravo montre le 12 de jour pris ailleurs');

reset role;

-- ===========================================================================
-- 4. Aucune donnée de Bravo lisible depuis Alpha
-- ===========================================================================
\echo ''
\echo '--- 4. cloisonnement : Pauline relie deux casernes, leurs données restent séparées'

set local role authenticated;
set local request.jwt.claims = '{"sub":"72a00000-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  b constant uuid := '72b00000-0000-4000-8000-000000000001';
  n integer;
begin
  select count(*) into n from stations where id = b;
  perform tests_multi.egal(n, 0, 'stations de Bravo, vues par l''admin d''Alpha');
  select count(*) into n from memberships where station_id = b;
  perform tests_multi.egal(n, 0, 'memberships de Bravo');
  select count(*) into n from memberships where user_id = '72b00000-0000-4000-8000-000000000101';
  perform tests_multi.egal(n, 1, 'de Pauline, l''admin d''Alpha ne voit que l''appartenance à Alpha');
  select count(*) into n from periods where station_id = b;
  perform tests_multi.egal(n, 0, 'periods de Bravo');
  select count(*) into n from schedules where station_id = b;
  perform tests_multi.egal(n, 0, 'schedules de Bravo');
  select count(*) into n from shifts where station_id = b;
  perform tests_multi.egal(n, 0, 'shifts de Bravo');
  select count(*) into n from assignments where station_id = b;
  perform tests_multi.egal(n, 0, 'assignments de Bravo');
  select count(*) into n from availabilities where station_id = b;
  perform tests_multi.egal(n, 0, 'availabilities de Bravo');
  select count(*) into n from availability_preferences where station_id = b;
  perform tests_multi.egal(n, 0, 'availability_preferences de Bravo');
  select count(*) into n from notifications where station_id = b;
  perform tests_multi.egal(n, 0, 'notifications de Bravo (celle de Pauline comprise)');
  select count(*) into n from invitations where station_id = b;
  perform tests_multi.egal(n, 0, 'invitations de Bravo');
  select count(*) into n from audit_log where station_id = b;
  perform tests_multi.egal(n, 0, 'audit_log de Bravo');
  select count(*) into n from v_schedule_progress where station_id = b;
  perform tests_multi.egal(n, 0, 'v_schedule_progress de Bravo');
  select count(*) into n from v_member_load where station_id = b;
  perform tests_multi.egal(n, 0, 'v_member_load de Bravo');

  begin
    perform * from availability_matrix(b, '72b00000-0000-4000-8000-000000000201');
    raise exception 'ECHEC : la matrice de Bravo s''est ouverte à l''admin d''Alpha';
  exception when others then
    if sqlerrm <> 'forbidden' then raise; end if;
    raise notice '  ok   la matrice de Bravo reste fermée à l''admin d''Alpha (forbidden)';
  end;
end $$;

-- Et dans l'autre sens : le brouillon d'Alpha, vu par l'admin de Bravo.
set local request.jwt.claims = '{"sub":"72b00000-0000-4000-8000-000000000100","role":"authenticated"}';

select tests_multi.egal(
  (select count(*)::int from assignments where station_id = '72a00000-0000-4000-8000-000000000001')
  + (select count(*)::int from shifts where station_id = '72a00000-0000-4000-8000-000000000001')
  + (select count(*)::int from schedules where station_id = '72a00000-0000-4000-8000-000000000001'),
  0, 'rien du planning d''Alpha n''est lisible par l''admin de Bravo');

-- Pauline, elle, ne voit toujours pas le brouillon d'Alpha qui la concerne : un
-- brouillon est invisible des membres (docs/WORKFLOWS.md § 2), seconde caserne
-- ou pas.
set local request.jwt.claims = '{"sub":"72b00000-0000-4000-8000-000000000101","role":"authenticated"}';

select tests_multi.egal(
  (select count(*)::int from assignments where station_id = '72a00000-0000-4000-8000-000000000001'),
  0, 'le brouillon d''Alpha reste invisible de Pauline');

select tests_multi.egal(
  (select count(*)::int from assignments where station_id = '72b00000-0000-4000-8000-000000000001'
      and user_id = '72b00000-0000-4000-8000-000000000101'),
  3, 'ses gardes publiées de Bravo lui restent lisibles');

-- Son centre de notifications rend celles de **ses deux** casernes, chacune avec
-- son `station_id` : c'est l'app qui filtre ou étiquette (ticket 072, À faire 2).
reset role;
insert into notifications (station_id, user_id, type, channel, title, body, data) values
  ('72a00000-0000-4000-8000-000000000001', '72b00000-0000-4000-8000-000000000101',
   'availability_reminder', 'inapp', 'Saisis tes disponibilités', 'CIS Alpha 72',
   '{"route": "/availability/2041-05", "station_id": "72a00000-0000-4000-8000-000000000001"}'::jsonb);
set local role authenticated;
set local request.jwt.claims = '{"sub":"72b00000-0000-4000-8000-000000000101","role":"authenticated"}';

select tests_multi.egal(
  (select string_agg(distinct station_id::text, ',' order by station_id::text) from notifications
    where user_id = '72b00000-0000-4000-8000-000000000101'),
  '72a00000-0000-4000-8000-000000000001,72b00000-0000-4000-8000-000000000001',
  'le centre de notifications rend les deux casernes, station_id renseigné');

-- Et l'admin d'Alpha ne lit pas plus celle d'Alpha que celle de Bravo : une
-- notification est à son destinataire seul.
set local request.jwt.claims = '{"sub":"72a00000-0000-4000-8000-000000000100","role":"authenticated"}';
select tests_multi.egal(
  (select count(*)::int from notifications where user_id = '72b00000-0000-4000-8000-000000000101'),
  0, 'les notifications de Pauline restent à Pauline');

reset role;

-- ===========================================================================
-- 5. Les droits
-- ===========================================================================
\echo ''
\echo '--- 5. qui peut appeler quoi'

select tests_multi.check(
  not has_function_privilege('authenticated',
    'public.member_taken_elsewhere(uuid, uuid, date, slot_type)', 'execute')
  and not has_function_privilege('anon',
    'public.member_taken_elsewhere(uuid, uuid, date, slot_type)', 'execute'),
  'member_taken_elsewhere : fermée aux clients — sinon un oracle de l''agenda d''autrui');

select tests_multi.check(
  has_function_privilege('service_role',
    'public.member_taken_elsewhere(uuid, uuid, date, slot_type)', 'execute'),
  'member_taken_elsewhere : ouverte au rôle de service');

select tests_multi.check(
  not has_function_privilege('authenticated',
    'public.shift_window(date, slot_type, text, jsonb)', 'execute')
  and not has_function_privilege('anon',
    'public.shift_window(date, slot_type, text, jsonb)', 'execute'),
  'shift_window : fermée aux clients');

select tests_multi.check(
  has_function_privilege('authenticated', 'public.availability_matrix(uuid, uuid)', 'execute')
  and not has_function_privilege('anon', 'public.availability_matrix(uuid, uuid)', 'execute'),
  'availability_matrix : recréée avec ses droits de 0017');

select tests_multi.check(
  not has_function_privilege('authenticated', 'public.apply_auto_proposal(uuid, uuid, jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.apply_auto_proposal(uuid, uuid, jsonb)', 'execute'),
  'apply_auto_proposal : toujours réservée au rôle de service');

select tests_multi.check(
  (select prosecdef from pg_proc where oid = 'public.member_taken_elsewhere(uuid, uuid, date, slot_type)'::regprocedure)
  and (select 'search_path=public, pg_temp' = any(proconfig) from pg_proc
        where oid = 'public.member_taken_elsewhere(uuid, uuid, date, slot_type)'::regprocedure),
  'member_taken_elsewhere : security definer, search_path fixé');

-- ===========================================================================
-- 6. La RLS n'a pas bougé
-- ===========================================================================
\echo ''
\echo '--- 6. aucune politique ne dépend de 0040, toutes les tables restent sous RLS'

select tests_multi.check(
  not exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and (coalesce(qual, '') ~ '(taken_elsewhere|shift_window)'
            or coalesce(with_check, '') ~ '(taken_elsewhere|shift_window)')),
  'aucune politique ne s''appuie sur les fonctions de 0040');

select tests_multi.check(
  not exists (
    select 1 from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  'toutes les tables de public restent sous RLS');

rollback;
