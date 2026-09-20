-- Tests des politiques Row Level Security (docs/SCHEMA.md sections 3 et 4).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f supabase/tests/rls_test.sql).
--
-- Méthode
-- -------
-- Pas de dépendance à pgTAP : le script lève une exception dès qu'une politique fuit,
-- psql s'arrête (`ON_ERROR_STOP`) et rend un code non nul.
--
-- Pour simuler un utilisateur connecté, on reproduit ce que fait PostgREST :
--
--     set local role authenticated;
--     set local request.jwt.claims = '{"sub":"<uuid>","role":"authenticated"}';
--
-- `auth.uid()` lit la claim `sub`, `auth.role()` la claim `role`. Le rôle `authenticated`
-- n'a pas `bypassrls`, donc les politiques s'appliquent réellement (contrairement à
-- `postgres` et `service_role`, qui les contournent).
--
-- Tout le fichier tourne dans une seule transaction terminée par `rollback` : les
-- fixtures (période 2099, planning, attributions, caserne suspendue) disparaissent et la
-- base reste exactement dans l'état du seed. Chaque test est isolé par un savepoint —
-- `rollback to savepoint` annule aussi les `set local`, donc le rôle revient à postgres.
--
-- Fixtures utilisées, en plus du seed (voir supabase/README.md) :
--   - caserne A = aaaaaaaa-…-001, caserne B = bbbbbbbb-…-001 ;
--   - période A 2099-01 `open`, période A 2099-02 `locked` ;
--   - planning A sur 2099-01, deux créneaux, attributions pour membre1 et membre2.

\set ON_ERROR_STOP on
\timing off
\pset pager off
-- Sortie tabulaire réduite : seules les notices des assertions nous intéressent.
\pset tuples_only on
\pset format unaligned

begin;

-- ===========================================================================
-- Outillage d'assertion (schéma tests, annulé par le rollback final)
-- ===========================================================================
create schema tests;

create function tests.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

-- L'écriture doit être refusée : soit erreur RLS / trigger, soit 0 ligne touchée
-- (une politique USING qui ne matche pas filtre silencieusement les lignes).
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

grant usage on schema tests to authenticated, anon;
grant execute on all functions in schema tests to authenticated, anon;

-- ===========================================================================
-- Fixtures
-- ===========================================================================
insert into periods (id, station_id, year, month, status, deadline_at)
values
  ('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001',
   2099, 1, 'open',   '2098-12-15 23:59:59+01'),
  ('11111111-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001',
   2099, 2, 'locked', '2099-01-15 23:59:59+01');

insert into schedules (id, station_id, period_id, status, published_at, created_by)
values ('11111111-0000-4000-8000-000000000003',
        'aaaaaaaa-0000-4000-8000-000000000001',
        '11111111-0000-4000-8000-000000000001',
        'published', now(),
        'aaaaaaaa-0000-4000-8000-000000000100');

insert into shifts (id, station_id, schedule_id, date, slot, required_count)
values
  ('11111111-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-000000000003', '2099-01-10', 'day', 1),
  ('11111111-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-000000000003', '2099-01-10', 'night', 1);

insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by)
values
  -- proposée à membre1 sur le créneau de jour
  ('11111111-0000-4000-8000-000000000006', 'aaaaaaaa-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000101',
   'proposed', now(), 'aaaaaaaa-0000-4000-8000-000000000100'),
  -- proposée à membre2 sur le créneau de nuit
  ('11111111-0000-4000-8000-000000000007', 'aaaaaaaa-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-000000000102',
   'proposed', now(), 'aaaaaaaa-0000-4000-8000-000000000100'),
  -- déjà acceptée par membre1 sur le créneau de nuit (pour tester accepted -> proposed)
  ('11111111-0000-4000-8000-000000000008', 'aaaaaaaa-0000-4000-8000-000000000001',
   '11111111-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-000000000101',
   'accepted', now(), 'aaaaaaaa-0000-4000-8000-000000000100');

-- Caserne B : période, planning `draft` et créneau, pour les tests de cohérence du
-- station_id avec la ligne parente. Le planning reste `draft` : un membre de B ne voit
-- donc toujours rien (section 1b).
insert into periods (id, station_id, year, month, status, deadline_at)
values ('11111111-0000-4000-8000-000000000021', 'bbbbbbbb-0000-4000-8000-000000000001',
        2099, 1, 'open', '2098-12-15 23:59:59+01');

insert into schedules (id, station_id, period_id, status, created_by)
values ('11111111-0000-4000-8000-000000000022',
        'bbbbbbbb-0000-4000-8000-000000000001',
        '11111111-0000-4000-8000-000000000021',
        'draft',
        'bbbbbbbb-0000-4000-8000-000000000100');

insert into shifts (id, station_id, schedule_id, date, slot, required_count)
values ('11111111-0000-4000-8000-000000000023', 'bbbbbbbb-0000-4000-8000-000000000001',
        '11111111-0000-4000-8000-000000000022', '2099-01-10', 'day', 1);

\echo ''
\echo '=== Tests RLS — Astreinte SP ==='

-- ===========================================================================
-- 1. Cloisonnement entre casernes
-- ===========================================================================
\echo ''
\echo '--- 1. Un membre de la caserne A ne lit rien de la caserne B'
savepoint s1;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests.check(auth.uid() = 'aaaaaaaa-0000-4000-8000-000000000101',
    'la claim sub est bien lue par auth.uid()');
  perform tests.check(current_user = 'authenticated',
    'le rôle courant est authenticated (RLS appliquée)');

  perform tests.check(
    (select count(*) from stations where id = 'bbbbbbbb-0000-4000-8000-000000000001') = 0,
    'stations : aucune caserne B visible');
  perform tests.check(
    (select count(*) from stations) = 1,
    'stations : seule la caserne A est visible');

  perform tests.check(
    (select count(*) from memberships where station_id = 'bbbbbbbb-0000-4000-8000-000000000001') = 0,
    'memberships : aucune appartenance de la caserne B visible');
  perform tests.check(
    (select count(*) from memberships) = 9,
    'memberships : les 9 membres de la caserne A sont visibles (pas de récursion)');

  perform tests.check(
    (select count(*) from periods where station_id = 'bbbbbbbb-0000-4000-8000-000000000001') = 0,
    'periods : aucune période de la caserne B visible');

  perform tests.check(
    (select count(*) from availabilities where station_id = 'bbbbbbbb-0000-4000-8000-000000000001') = 0,
    'availabilities : aucune disponibilité de la caserne B visible');
  perform tests.check(
    (select count(*) from availabilities where user_id <> auth.uid()) = 0,
    'availabilities : aucune disponibilité d''un autre membre de la caserne A');

  perform tests.check(
    (select count(*) from availability_preferences where user_id <> auth.uid()) = 0,
    'availability_preferences : seulement les siennes');

  perform tests.check(
    (select count(*) from assignments where station_id = 'bbbbbbbb-0000-4000-8000-000000000001') = 0,
    'assignments : aucune attribution de la caserne B visible');

  perform tests.check(
    (select count(*) from profiles where email like '%caserne-b%') = 0,
    'profiles : aucun profil de la caserne B visible');
  perform tests.check(
    (select count(*) from profiles) = 9,
    'profiles : seuls les 9 profils de la caserne A sont visibles');
end $$;

rollback to savepoint s1;

\echo ''
\echo '--- 1b. Un membre de la caserne B ne lit rien de la caserne A'
savepoint s1b;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests.check(
    (select count(*) from stations where id = 'aaaaaaaa-0000-4000-8000-000000000001') = 0,
    'stations : aucune caserne A visible');
  perform tests.check(
    (select count(*) from memberships where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 0,
    'memberships : aucune appartenance de la caserne A visible');
  perform tests.check(
    (select count(*) from periods where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 0,
    'periods : aucune période de la caserne A visible');
  perform tests.check(
    (select count(*) from availabilities where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 0,
    'availabilities : aucune disponibilité de la caserne A visible');
  perform tests.check(
    (select count(*) from assignments) = 0,
    'assignments : aucune attribution visible (aucun planning en caserne B)');
  perform tests.check(
    (select count(*) from shifts) = 0,
    'shifts : aucun créneau visible');
  perform tests.check(
    (select count(*) from schedules) = 0,
    'schedules : aucun planning visible');
end $$;

rollback to savepoint s1b;

\echo ''
\echo '--- 1c. Un admin de la caserne B ne lit rien de la caserne A'
savepoint s1c;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests.check(
    (select count(*) from availabilities where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 0,
    'availabilities : un admin B ne voit rien de la caserne A');
  perform tests.check(
    (select count(*) from availabilities where station_id = 'bbbbbbbb-0000-4000-8000-000000000001') > 0,
    'availabilities : un admin B voit celles de sa caserne');
  perform tests.check(
    (select count(*) from subscriptions) = 1,
    'subscriptions : un admin ne voit que l''abonnement de sa caserne');
  perform tests.check(
    (select count(*) from invitations) = 0,
    'invitations : aucune invitation (seed vide) et aucune fuite');
  perform tests.check(
    (select count(*) from super_admins) = 0,
    'super_admins : invisible pour un admin de caserne');
end $$;

select tests.denied(
  $q$ update stations set name = 'piraté' where id = 'aaaaaaaa-0000-4000-8000-000000000001' $q$,
  'stations : un admin B ne renomme pas la caserne A');
select tests.denied(
  $q$ insert into memberships (station_id, user_id, role, status)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              'bbbbbbbb-0000-4000-8000-000000000100', 'admin', 'active') $q$,
  'memberships : un admin B ne s''ajoute pas à la caserne A');
select tests.denied(
  $q$ insert into availabilities (station_id, user_id, date, slot, status, set_by)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              'aaaaaaaa-0000-4000-8000-000000000101', '2099-01-10', 'day', 'available',
              'bbbbbbbb-0000-4000-8000-000000000100') $q$,
  'availabilities : un admin B n''écrit pas dans la caserne A');

rollback to savepoint s1c;

-- ===========================================================================
-- 2. Disponibilités : période ouverte / verrouillée
-- ===========================================================================
\echo ''
\echo '--- 2. Disponibilités d''un membre selon le statut de la période'
savepoint s2;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

select tests.allowed(
  $q$ insert into availabilities (station_id, user_id, date, slot, status, set_by)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              'aaaaaaaa-0000-4000-8000-000000000101', '2099-01-10', 'day', 'available',
              'aaaaaaaa-0000-4000-8000-000000000101') $q$,
  'période open : un membre écrit sa disponibilité');

select tests.allowed(
  $q$ update availabilities set status = 'absent'
      where user_id = 'aaaaaaaa-0000-4000-8000-000000000101' and date = '2099-01-10' and slot = 'day' $q$,
  'période open : un membre modifie sa disponibilité');

select tests.allowed(
  $q$ delete from availabilities
      where user_id = 'aaaaaaaa-0000-4000-8000-000000000101' and date = '2099-01-10' and slot = 'day' $q$,
  'période open : un membre supprime sa disponibilité');

select tests.denied(
  $q$ insert into availabilities (station_id, user_id, date, slot, status, set_by)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              'aaaaaaaa-0000-4000-8000-000000000101', '2099-02-10', 'day', 'available',
              'aaaaaaaa-0000-4000-8000-000000000101') $q$,
  'période locked : un membre n''écrit pas sa disponibilité');

select tests.denied(
  $q$ insert into availabilities (station_id, user_id, date, slot, status, set_by)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              'aaaaaaaa-0000-4000-8000-000000000102', '2099-01-10', 'day', 'available',
              'aaaaaaaa-0000-4000-8000-000000000101') $q$,
  'un membre n''écrit pas la disponibilité d''un autre membre');

select tests.denied(
  $q$ insert into availability_preferences (station_id, user_id, period_id, max_shifts)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              'aaaaaaaa-0000-4000-8000-000000000101',
              '11111111-0000-4000-8000-000000000002', 5) $q$,
  'période locked : un membre n''écrit pas ses quotas');

select tests.allowed(
  $q$ insert into availability_preferences (station_id, user_id, period_id, max_shifts)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              'aaaaaaaa-0000-4000-8000-000000000101',
              '11111111-0000-4000-8000-000000000001', 5) $q$,
  'période open : un membre écrit ses quotas');

rollback to savepoint s2;

\echo ''
\echo '--- 2b. Un admin écrit les disponibilités d''un autre membre, période verrouillée comprise'
savepoint s2b;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.allowed(
  $q$ insert into availabilities (station_id, user_id, date, slot, status, set_by)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              'aaaaaaaa-0000-4000-8000-000000000101', '2099-02-10', 'night', 'available',
              'aaaaaaaa-0000-4000-8000-000000000100') $q$,
  'période locked : un admin écrit la disponibilité d''un membre');

select tests.allowed(
  $q$ update availabilities set status = 'absent'
      where user_id = 'aaaaaaaa-0000-4000-8000-000000000101'
        and date = '2099-02-10' and slot = 'night' $q$,
  'période locked : un admin modifie la disponibilité d''un membre');

do $$
begin
  perform tests.check(
    (select count(*) from availabilities
     where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
       and user_id <> auth.uid()) > 0,
    'un admin lit les disponibilités de tous les membres de sa caserne');
  perform tests.check(
    (select count(*) from availability_preferences
     where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 8,
    'un admin lit les quotas de tous les membres de sa caserne (4 membres x 2 périodes)');
end $$;

rollback to savepoint s2b;

-- ===========================================================================
-- 3. Attributions : visibilité selon le statut du planning
-- ===========================================================================
\echo ''
\echo '--- 3. Planning published : un membre ne voit que ses attributions'
savepoint s3;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests.check(
    (select count(*) from assignments) = 2,
    'assignments : membre1 voit ses 2 attributions et pas celle de membre2');
  perform tests.check(
    (select count(*) from assignments where user_id <> auth.uid()) = 0,
    'assignments : aucune attribution d''un autre membre visible');
  perform tests.check(
    (select count(*) from shifts) = 2,
    'shifts : les créneaux du planning publié sont visibles');
  perform tests.check(
    (select count(*) from schedules) = 1,
    'schedules : le planning publié est visible');
end $$;

rollback to savepoint s3;

\echo ''
\echo '--- 3b. Planning draft : rien n''est visible pour un membre'
savepoint s3b;
-- Rembobinage de **fixture**, pas un scénario du produit : depuis la migration
-- 0019, aucun chemin ne ramène un planning publié en brouillon
-- (`schedules_guard_transition`, vérifié par `publication_test.sql § 1`). Le
-- déclencheur est donc écarté le temps de reconstruire l'état initial, et
-- remis aussitôt.
alter table schedules disable trigger schedules_guard_transition;
update schedules set status = 'draft', published_at = null
where id = '11111111-0000-4000-8000-000000000003';
alter table schedules enable trigger schedules_guard_transition;

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests.check((select count(*) from schedules) = 0,
    'schedules : un brouillon est invisible pour un membre');
  perform tests.check((select count(*) from shifts) = 0,
    'shifts : les créneaux d''un brouillon sont invisibles');
  perform tests.check((select count(*) from assignments) = 0,
    'assignments : les attributions d''un brouillon sont invisibles');
end $$;

rollback to savepoint s3b;

\echo ''
\echo '--- 3c. Planning validated : un membre voit les attributions de toute la caserne'
savepoint s3c;
-- `validated_at` n'est plus une colonne libre : le déclencheur de la migration
-- 0019 la pose avec le statut.
update schedules set status = 'validated'
where id = '11111111-0000-4000-8000-000000000003';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests.check(
    (select count(*) from assignments) = 3,
    'assignments : planning validé, les 3 attributions de la caserne sont visibles');
  perform tests.check(
    (select count(*) from assignments where user_id <> auth.uid()) = 1,
    'assignments : celle de membre2 est visible');
end $$;

rollback to savepoint s3c;

\echo ''
\echo '--- 3d. Un admin voit tout, quel que soit le statut du planning'
savepoint s3d;
-- Rembobinage de **fixture**, pas un scénario du produit : depuis la migration
-- 0019, aucun chemin ne ramène un planning publié en brouillon
-- (`schedules_guard_transition`, vérifié par `publication_test.sql § 1`). Le
-- déclencheur est donc écarté le temps de reconstruire l'état initial, et
-- remis aussitôt.
alter table schedules disable trigger schedules_guard_transition;
update schedules set status = 'draft', published_at = null
where id = '11111111-0000-4000-8000-000000000003';
alter table schedules enable trigger schedules_guard_transition;

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests.check((select count(*) from schedules) = 1, 'schedules : un admin voit le brouillon');
  perform tests.check((select count(*) from shifts) = 2, 'shifts : un admin voit les créneaux du brouillon');
  perform tests.check((select count(*) from assignments) = 3, 'assignments : un admin voit toutes les attributions');
end $$;

rollback to savepoint s3d;

-- ===========================================================================
-- 4. Transitions d'attribution par un membre
-- ===========================================================================
\echo ''
\echo '--- 4. Transitions autorisées et interdites'
savepoint s4;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

select tests.denied(
  $q$ update assignments set status = 'proposed'
      where id = '11111111-0000-4000-8000-000000000008' $q$,
  'accepted -> proposed : refusé');

select tests.denied(
  $q$ update assignments set status = 'accepted',
             shift_id = '11111111-0000-4000-8000-000000000005'
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'un membre ne modifie pas shift_id');

select tests.denied(
  $q$ update assignments set status = 'accepted',
             user_id = 'aaaaaaaa-0000-4000-8000-000000000102'
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'un membre ne modifie pas user_id');

select tests.denied(
  $q$ update assignments set status = 'cancelled'
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'proposed -> cancelled : refusé (réservé à l''admin)');

select tests.denied(
  $q$ update assignments set was_available = false
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'un membre ne modifie pas was_available sans changer de statut');

select tests.denied(
  $q$ update assignments set status = 'accepted'
      where id = '11111111-0000-4000-8000-000000000007' $q$,
  'un membre ne répond pas à l''attribution d''un autre');

select tests.denied(
  $q$ insert into assignments (station_id, shift_id, user_id, status, created_by)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              '11111111-0000-4000-8000-000000000004',
              'aaaaaaaa-0000-4000-8000-000000000101', 'accepted',
              'aaaaaaaa-0000-4000-8000-000000000101') $q$,
  'un membre ne crée pas d''attribution');

select tests.denied(
  $q$ delete from assignments where id = '11111111-0000-4000-8000-000000000006' $q$,
  'un membre ne supprime pas une attribution');

select tests.allowed(
  $q$ update assignments set status = 'accepted'
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'proposed -> accepted : autorisé');

do $$
begin
  perform tests.check(
    (select status from assignments where id = '11111111-0000-4000-8000-000000000006') = 'accepted',
    'le statut est bien passé à accepted');
  perform tests.check(
    (select responded_at from assignments where id = '11111111-0000-4000-8000-000000000006') is not null,
    'responded_at est renseigné par le trigger');
end $$;

rollback to savepoint s4;

\echo ''
\echo '--- 4b. proposed -> declined avec motif'
savepoint s4b;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000102","role":"authenticated"}';

select tests.allowed(
  $q$ update assignments set status = 'declined', decline_reason = 'Indisponible ce jour-là'
      where id = '11111111-0000-4000-8000-000000000007' $q$,
  'proposed -> declined avec decline_reason : autorisé');

rollback to savepoint s4b;

\echo ''
\echo '--- 4c. Un admin garde la main sur toutes les transitions'
savepoint s4c;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.allowed(
  $q$ update assignments set status = 'cancelled'
      where id = '11111111-0000-4000-8000-000000000008' $q$,
  'admin : accepted -> cancelled autorisé');

select tests.allowed(
  $q$ update assignments set was_available = false
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'admin : modification libre des colonnes');

rollback to savepoint s4c;

-- ===========================================================================
-- 5. Caserne suspendue : lecture seule
-- ===========================================================================
\echo ''
\echo '--- 5. Caserne suspended : lectures conservées, écritures bloquées'
savepoint s5;
update subscriptions set status = 'suspended', suspended_at = now()
where station_id = 'aaaaaaaa-0000-4000-8000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests.check(station_writable('aaaaaaaa-0000-4000-8000-000000000001') is false,
    'station_writable est faux pour une caserne suspendue');
  perform tests.check((select count(*) from stations) = 1,
    'lecture : la caserne reste visible');
  perform tests.check((select count(*) from periods) = 4,
    'lecture : les périodes restent visibles (2 du seed + 2 fixtures)');
  perform tests.check((select count(*) from availabilities where user_id = auth.uid()) > 0,
    'lecture : les disponibilités restent visibles');
  perform tests.check((select count(*) from assignments) = 2,
    'lecture : les attributions restent visibles');
end $$;

select tests.denied(
  $q$ insert into availabilities (station_id, user_id, date, slot, status, set_by)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              'aaaaaaaa-0000-4000-8000-000000000101', '2099-01-11', 'day', 'available',
              'aaaaaaaa-0000-4000-8000-000000000101') $q$,
  'écriture : disponibilité refusée en caserne suspendue');

select tests.denied(
  $q$ update assignments set status = 'accepted'
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'écriture : réponse à une attribution refusée en caserne suspendue');

rollback to savepoint s5;

\echo ''
\echo '--- 5b. Caserne suspended : un admin non plus n''écrit pas'
savepoint s5b;
update subscriptions set status = 'suspended', suspended_at = now()
where station_id = 'aaaaaaaa-0000-4000-8000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.denied(
  $q$ insert into periods (station_id, year, month, status, deadline_at)
      values ('aaaaaaaa-0000-4000-8000-000000000001', 2099, 3, 'open', '2099-02-15 23:59:59+01') $q$,
  'écriture : création de période refusée en caserne suspendue');

do $$
begin
  perform tests.check((select count(*) from availabilities) > 0,
    'lecture : un admin lit toujours les disponibilités de sa caserne suspendue');
  perform tests.check(
    (select status from subscriptions
     where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 'suspended',
    'lecture : un admin lit l''abonnement suspendu de sa caserne');
end $$;

rollback to savepoint s5b;

-- ===========================================================================
-- 6. Divers : profils, memberships, notifications, tables service role
-- ===========================================================================
\echo ''
\echo '--- 6. Profils, appartenances, notifications et tables réservées'
savepoint s6;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests.check((select count(*) from profiles) = 9,
    'profiles : les 9 profils de la caserne A, aucun de la B');
  perform tests.check(
    (select count(*) from profiles where email like '%caserne-b%') = 0,
    'profiles : aucun email de la caserne B');
end $$;

select tests.allowed(
  $q$ update profiles set phone = '+33600000000' where id = auth.uid() $q$,
  'profiles : un membre modifie son propre profil');

select tests.denied(
  $q$ update profiles set phone = '+33611111111'
      where id = 'aaaaaaaa-0000-4000-8000-000000000102' $q$,
  'profiles : un membre ne modifie pas le profil d''un autre');

select tests.denied(
  $q$ update memberships set role = 'admin' where user_id = auth.uid() $q$,
  'memberships : un membre ne se promeut pas admin');

select tests.denied(
  $q$ insert into audit_log (station_id, actor_id, action, entity)
      values ('aaaaaaaa-0000-4000-8000-000000000001', auth.uid(), 'triche', 'test') $q$,
  'audit_log : écriture refusée au rôle authenticated');

select tests.denied(
  $q$ insert into notifications (station_id, user_id, type, channel, title, body)
      values ('aaaaaaaa-0000-4000-8000-000000000001', auth.uid(),
              'invitation', 'inapp', 'faux', 'faux') $q$,
  'notifications : insertion refusée au rôle authenticated');

select tests.denied(
  $q$ update subscriptions set status = 'active'
      where station_id = 'aaaaaaaa-0000-4000-8000-000000000001' $q$,
  'subscriptions : écriture refusée au rôle authenticated');

select tests.denied(
  $q$ insert into super_admins (user_id) values (auth.uid()) $q$,
  'super_admins : écriture refusée au rôle authenticated');

select tests.denied(
  $q$ insert into stations (name, slug) values ('Caserne pirate', 'pirate') $q$,
  'stations : un membre ne crée pas de caserne');

rollback to savepoint s6;

\echo ''
\echo '--- 6b. Notifications : un membre ne marque comme lue que les siennes'
savepoint s6b;
insert into notifications (id, station_id, user_id, type, channel, title, body)
values
  ('11111111-0000-4000-8000-000000000010', 'aaaaaaaa-0000-4000-8000-000000000001',
   'aaaaaaaa-0000-4000-8000-000000000101', 'assignment_proposed', 'inapp', 'Titre', 'Corps'),
  ('11111111-0000-4000-8000-000000000011', 'aaaaaaaa-0000-4000-8000-000000000001',
   'aaaaaaaa-0000-4000-8000-000000000102', 'assignment_proposed', 'inapp', 'Titre', 'Corps');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests.check((select count(*) from notifications) = 1,
    'notifications : un membre ne voit que les siennes');
end $$;

select tests.allowed(
  $q$ update notifications set read_at = now()
      where id = '11111111-0000-4000-8000-000000000010' $q$,
  'notifications : un membre marque la sienne comme lue');

select tests.denied(
  $q$ update notifications set read_at = now()
      where id = '11111111-0000-4000-8000-000000000011' $q$,
  'notifications : un membre ne marque pas celle d''un autre');

select tests.denied(
  $q$ update notifications set title = 'modifié'
      where id = '11111111-0000-4000-8000-000000000010' $q$,
  'notifications : seule la colonne read_at est modifiable');

rollback to savepoint s6b;

-- ===========================================================================
-- 7. Rôle anon : aucune lecture
-- ===========================================================================
\echo ''
\echo '--- 7. Le rôle anon ne lit rien'
savepoint s7;
set local role anon;

do $$
begin
  perform tests.check((select count(*) from stations) = 0, 'anon : aucune caserne');
  perform tests.check((select count(*) from profiles) = 0, 'anon : aucun profil');
  perform tests.check((select count(*) from memberships) = 0, 'anon : aucune appartenance');
  perform tests.check((select count(*) from availabilities) = 0, 'anon : aucune disponibilité');
  perform tests.check((select count(*) from assignments) = 0, 'anon : aucune attribution');
  perform tests.check((select count(*) from notifications) = 0, 'anon : aucune notification');
end $$;

rollback to savepoint s7;

-- ===========================================================================
-- 8. Les fonctions trigger ne sont pas appelables depuis l'API
-- ===========================================================================
\echo ''
\echo '--- 8. Fonctions trigger non exposées'
savepoint s8;

do $$
declare
  f text;
begin
  foreach f in array array['set_updated_at', 'handle_new_user', 'assignments_member_transition']
  loop
    perform tests.check(
      not has_function_privilege('authenticated', (f || '()')::regprocedure, 'execute'),
      format('%s() n''est pas exécutable par authenticated', f));
    perform tests.check(
      not has_function_privilege('anon', (f || '()')::regprocedure, 'execute'),
      format('%s() n''est pas exécutable par anon', f));
    perform tests.check(
      not has_function_privilege('public', (f || '()')::regprocedure, 'execute'),
      format('%s() n''est pas exécutable par public', f));
  end loop;
end $$;

rollback to savepoint s8;

-- ===========================================================================
-- 9. Aucune table sans RLS ni sans politique dans public
-- ===========================================================================
\echo ''
\echo '--- 9. Couverture RLS du schéma public'
savepoint s9;

do $$
declare
  manquantes text;
begin
  select string_agg(c.relname, ', ' order by c.relname) into manquantes
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  perform tests.check(manquantes is null, coalesce('tables sans RLS : ' || manquantes, 'toutes les tables ont RLS'));

  -- Une table sans politique n'est pas une table sans protection : RLS activée
  -- sans aucune politique refuse *tout* à qui ne contourne pas la RLS. Ce qui
  -- serait un oubli, c'est une table à laquelle `anon` ou `authenticated` a
  -- encore un privilège alors qu'aucune politique ne dit ce qu'il a le droit d'y
  -- voir. C'est donc ça qu'on cherche, et pas l'absence de politique en soi.
  --
  -- Une seule table est dans ce cas et c'est voulu : `notification_outbox`
  -- (migration 0014) porte les charges utiles de toutes les casernes à la fois
  -- et n'est lue que par le rôle de service. Ses privilèges sont retirés à
  -- `anon` et `authenticated`, et le test le vérifie ci-dessous.
  select string_agg(c.relname, ', ' order by c.relname) into manquantes
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and not exists (select 1 from pg_policy p where p.polrelid = c.oid)
    and exists (
      select 1 from unnest(array['anon', 'authenticated']) as r(role)
      where has_table_privilege(r.role, c.oid, 'select')
         or has_table_privilege(r.role, c.oid, 'insert')
         or has_table_privilege(r.role, c.oid, 'update')
         or has_table_privilege(r.role, c.oid, 'delete'));
  perform tests.check(
    manquantes is null,
    coalesce('tables sans politique mais encore ouvertes à un client : ' || manquantes,
             'toute table sans politique est aussi sans privilège client'));

  perform tests.check(
    not exists (select 1 from pg_policy where polrelid = 'public.notification_outbox'::regclass)
    and not has_table_privilege('authenticated', 'public.notification_outbox', 'select')
    and not has_table_privilege('anon', 'public.notification_outbox', 'select'),
    'la file des notifications est fermée à tout client, sans politique à maintenir');
end $$;

rollback to savepoint s9;

-- ===========================================================================
-- 10. Bloquant 1 — pg_temp ne masque pas les tables du schéma public
-- ===========================================================================
\echo ''
\echo '--- 10. pg_temp ne détourne ni les fonctions security definer ni les politiques'
savepoint s10;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-4000-8000-000000000101","role":"authenticated"}';

-- L'exploit : un membre de la caserne B se fabrique une appartenance admin à la
-- caserne A dans son schéma temporaire.
create temp table memberships (station_id uuid, user_id uuid, status text, role text);
insert into memberships
values ('aaaaaaaa-0000-4000-8000-000000000001',
        'bbbbbbbb-0000-4000-8000-000000000101', 'active', 'admin');

do $$
begin
  perform tests.check(
    is_admin('aaaaaaaa-0000-4000-8000-000000000001') is false,
    'is_admin() ignore pg_temp.memberships');
  perform tests.check(
    is_member('aaaaaaaa-0000-4000-8000-000000000001') is false,
    'is_member() ignore pg_temp.memberships');
  perform tests.check(
    (select count(*) from public.availabilities
     where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 0,
    'aucune disponibilité de la caserne A visible malgré pg_temp.memberships');
  perform tests.check(
    (select count(*) from public.stations
     where id = 'aaaaaaaa-0000-4000-8000-000000000001') = 0,
    'la caserne A reste invisible malgré pg_temp.memberships');
end $$;

select tests.denied(
  $q$ insert into public.availabilities (station_id, user_id, date, slot, status, set_by)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              'aaaaaaaa-0000-4000-8000-000000000101', '2099-01-10', 'day', 'available',
              'bbbbbbbb-0000-4000-8000-000000000101') $q$,
  'écriture dans la caserne A refusée malgré pg_temp.memberships');

rollback to savepoint s10;

\echo ''
\echo '--- 10b. pg_temp.periods ne déverrouille pas une période locked'
savepoint s10b;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

-- Les expressions des politiques sont analysées à la création et stockées avec les OID
-- résolus : elles ne sont pas sensibles au search_path de l'appelant. Vérifié ici.
create temp table periods (id uuid, station_id uuid, year int, month int, status text);
insert into periods
values (gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-000000000001', 2099, 2, 'open');

select tests.denied(
  $q$ insert into public.availabilities (station_id, user_id, date, slot, status, set_by)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              'aaaaaaaa-0000-4000-8000-000000000101', '2099-02-10', 'day', 'available',
              'aaaaaaaa-0000-4000-8000-000000000101') $q$,
  'période locked : pg_temp.periods ne déverrouille pas la saisie');

rollback to savepoint s10b;

\echo ''
\echo '--- 10c. Toutes les fonctions du schéma public nomment pg_temp en dernier'
savepoint s10c;

do $$
declare
  fautives text;
begin
  select string_agg(p.proname || ' -> ' || coalesce(array_to_string(p.proconfig, ' '), '(aucun)'),
                    ', ' order by p.proname)
    into fautives
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and (p.proconfig is null
         or not exists (
           select 1 from unnest(p.proconfig) c
           where c = 'search_path=public, pg_temp'));
  perform tests.check(fautives is null,
    coalesce('fonctions au search_path incorrect : ' || fautives,
             'toutes les fonctions ont search_path = public, pg_temp'));
end $$;

rollback to savepoint s10c;

-- ===========================================================================
-- 11. Bloquant 2 — un membre ne déplace pas son attribution d'une caserne à l'autre
-- ===========================================================================
\echo ''
\echo '--- 11. Le station_id d''une attribution est gelé pour un membre'
savepoint s11;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

select tests.denied(
  $q$ update assignments
      set status = 'accepted', station_id = 'bbbbbbbb-0000-4000-8000-000000000001'
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'un membre ne déplace pas son attribution vers la caserne B');

do $$
begin
  perform tests.check(
    (select station_id from public.assignments
     where id = '11111111-0000-4000-8000-000000000006')
      = 'aaaaaaaa-0000-4000-8000-000000000001',
    'l''attribution est restée dans la caserne A');
  perform tests.check(
    (select status from public.assignments
     where id = '11111111-0000-4000-8000-000000000006') = 'proposed',
    'le statut n''a pas changé non plus');
end $$;

rollback to savepoint s11;

-- ===========================================================================
-- 12. Bloquant 3 — liste blanche des colonnes modifiables par un membre
-- ===========================================================================
-- Les tests de la section 4 sur was_available passaient pour une mauvaise raison :
-- c'est la transition proposed -> proposed qui était refusée. Ici, la transition est
-- valide et c'est bien la colonne interdite qui doit provoquer le refus.
\echo ''
\echo '--- 12. Colonnes interdites modifiées pendant une transition valide'
savepoint s12;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

select tests.denied(
  $q$ update assignments set status = 'accepted', was_available = false
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'transition valide + was_available : refusé');

select tests.denied(
  $q$ update assignments set status = 'accepted', reminder_count = 99
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'transition valide + reminder_count : refusé');

select tests.denied(
  $q$ update assignments set status = 'accepted', proposed_at = null
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'transition valide + proposed_at : refusé');

select tests.denied(
  $q$ update assignments set status = 'accepted', last_reminder_at = now()
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'transition valide + last_reminder_at : refusé');

select tests.denied(
  $q$ update assignments set status = 'accepted',
             replaced_by = '11111111-0000-4000-8000-000000000007'
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'transition valide + replaced_by : refusé');

select tests.denied(
  $q$ update assignments set status = 'accepted',
             created_by = 'aaaaaaaa-0000-4000-8000-000000000101'
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'transition valide + created_by : refusé');

do $$
begin
  perform tests.check(
    (select status from public.assignments
     where id = '11111111-0000-4000-8000-000000000006') = 'proposed',
    'aucune de ces tentatives n''a fait passer l''attribution à accepted');
  perform tests.check(
    (select reminder_count from public.assignments
     where id = '11111111-0000-4000-8000-000000000006') = 0,
    'reminder_count est intact');
end $$;

-- La transition seule reste possible, avec le motif de refus.
select tests.allowed(
  $q$ update assignments set status = 'declined', decline_reason = 'En intervention'
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'status + decline_reason seuls : toujours autorisé');

rollback to savepoint s12;

-- ===========================================================================
-- 13. Bloquant 4 — cohérence du station_id avec la ligne parente
-- ===========================================================================
\echo ''
\echo '--- 13. Un admin n''écrit pas via une ligne parente d''une autre caserne'
savepoint s13;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.denied(
  $q$ insert into shifts (station_id, schedule_id, date, slot)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              '11111111-0000-4000-8000-000000000022', '2099-01-11', 'day') $q$,
  'shifts : un admin A n''insère pas de créneau dans un planning de B');

select tests.denied(
  $q$ update shifts set schedule_id = '11111111-0000-4000-8000-000000000022'
      where id = '11111111-0000-4000-8000-000000000004' $q$,
  'shifts : un admin A ne rattache pas son créneau à un planning de B');

select tests.denied(
  $q$ insert into assignments (station_id, shift_id, user_id, status, created_by)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              '11111111-0000-4000-8000-000000000023',
              'aaaaaaaa-0000-4000-8000-000000000101', 'proposed',
              'aaaaaaaa-0000-4000-8000-000000000100') $q$,
  'assignments : un admin A n''attribue pas un créneau de B');

select tests.denied(
  $q$ insert into assignments (station_id, shift_id, user_id, status, created_by)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              '11111111-0000-4000-8000-000000000004',
              'bbbbbbbb-0000-4000-8000-000000000101', 'proposed',
              'aaaaaaaa-0000-4000-8000-000000000100') $q$,
  'assignments : un admin A n''attribue pas un créneau à un membre de B');

select tests.denied(
  $q$ update assignments set user_id = 'bbbbbbbb-0000-4000-8000-000000000101'
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'assignments : un admin A ne réattribue pas vers un membre de B');

select tests.denied(
  $q$ insert into schedules (station_id, period_id, status, created_by)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              '11111111-0000-4000-8000-000000000021', 'draft',
              'aaaaaaaa-0000-4000-8000-000000000100') $q$,
  'schedules : un admin A ne crée pas de planning sur une période de B');

select tests.denied(
  $q$ insert into availabilities (station_id, user_id, date, slot, status, set_by)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              'bbbbbbbb-0000-4000-8000-000000000101', '2099-01-10', 'day', 'available',
              'aaaaaaaa-0000-4000-8000-000000000100') $q$,
  'availabilities : un admin A n''écrit pas pour un membre de B');

select tests.denied(
  $q$ insert into availability_preferences (station_id, user_id, period_id, max_shifts)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              'aaaaaaaa-0000-4000-8000-000000000101',
              '11111111-0000-4000-8000-000000000021', 3) $q$,
  'availability_preferences : un admin A n''écrit pas sur une période de B');

-- Les écritures légitimes de l'admin restent possibles.
select tests.allowed(
  $q$ insert into shifts (station_id, schedule_id, date, slot)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              '11111111-0000-4000-8000-000000000003', '2099-01-12', 'day') $q$,
  'shifts : un admin A insère bien dans son propre planning');

select tests.allowed(
  $q$ insert into assignments (station_id, shift_id, user_id, status, created_by)
      values ('aaaaaaaa-0000-4000-8000-000000000001',
              '11111111-0000-4000-8000-000000000004',
              'aaaaaaaa-0000-4000-8000-000000000103', 'proposed',
              'aaaaaaaa-0000-4000-8000-000000000100') $q$,
  'assignments : un admin A attribue bien un créneau à un membre de A');

rollback to savepoint s13;

-- ===========================================================================
-- 14. Améliorations — planning draft et token d'invitation
-- ===========================================================================
\echo ''
\echo '--- 14. Un membre ne répond pas à l''aveugle à un planning draft'
savepoint s14;
-- Rembobinage de **fixture**, pas un scénario du produit : depuis la migration
-- 0019, aucun chemin ne ramène un planning publié en brouillon
-- (`schedules_guard_transition`, vérifié par `publication_test.sql § 1`). Le
-- déclencheur est donc écarté le temps de reconstruire l'état initial, et
-- remis aussitôt.
alter table schedules disable trigger schedules_guard_transition;
update schedules set status = 'draft', published_at = null
where id = '11111111-0000-4000-8000-000000000003';
alter table schedules enable trigger schedules_guard_transition;

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests.check((select count(*) from public.assignments) = 0,
    'aucune attribution d''un brouillon n''est lisible');
end $$;

-- Sans clause where citant une colonne, un update ne sollicite pas les politiques de
-- select : c'est la politique d'update qui doit porter la condition sur le planning.
select tests.denied(
  $q$ update assignments set status = 'accepted' $q$,
  'update sans where : aucune attribution de brouillon acceptée à l''aveugle');

select tests.denied(
  $q$ update assignments set status = 'accepted'
      where id = '11111111-0000-4000-8000-000000000006' $q$,
  'update ciblé : refusé aussi sur un brouillon');

rollback to savepoint s14;

\echo ''
\echo '--- 14b. Le token d''invitation n''est pas lisible par le rôle authenticated'
savepoint s14b;
insert into invitations (id, station_id, email, invited_by)
values ('11111111-0000-4000-8000-000000000030',
        'aaaaaaaa-0000-4000-8000-000000000001',
        'nouveau@caserne-a.test',
        'aaaaaaaa-0000-4000-8000-000000000100');

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  jete text;
begin
  begin
    select token into jete from public.invitations limit 1;
    raise exception 'ECHEC : le token d''invitation a été lu par un admin';
  exception
    when insufficient_privilege then
      raise notice '  ok   invitations : select token refusé (%)', sqlerrm;
  end;

  begin
    perform 1 from public.invitations i where i.token is not null;
    raise exception 'ECHEC : le token d''invitation a été lu dans un where par un admin';
  exception
    when insufficient_privilege then
      raise notice '  ok   invitations : token refusé aussi dans un where (%)', sqlerrm;
  end;

  perform tests.check(
    (select email from public.invitations
     where id = '11111111-0000-4000-8000-000000000030') = 'nouveau@caserne-a.test',
    'invitations : les autres colonnes restent lisibles par l''admin');
end $$;

rollback to savepoint s14b;

\echo ''
\echo '=== Tous les tests RLS sont passés ==='
\echo ''

rollback;
