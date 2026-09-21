-- Tests de la suppression de compte (migration 0026, ticket 007).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié
-- ------------------
-- 1. La chaîne de cascade est bien coupée : supprimer la ligne `auth.users`
--    n'efface plus le profil, donc plus les attributions. C'est **le** critère
--    d'acceptation du ticket, et il tient à une contrainte absente.
-- 2. `delete_own_account` anonymise : « Membre supprimé », adresse non routable,
--    téléphone nul, push coupé, appartenances désactivées et datées, surnom effacé.
-- 3. Les attributions passées restent, et se lisent sous la mention neutre.
-- 4. Ce qui est personnel part : disponibilités, préférences, appareils,
--    notifications, invitations en attente à son adresse.
-- 5. Le dernier administrateur actif d'une caserne est refusé, sans rien écrire.
-- 6. La fonction n'est pas exécutable par `authenticated` ni par `anon` : son
--    paramètre `p_user_id` viserait n'importe qui.
-- 7. Un membre reste incapable d'anonymiser le profil d'un autre par la RLS.
--
-- Méthode identique à rls_test.sql : pas de pgTAP, une exception fait sortir psql
-- avec un code non nul. Tout le fichier tourne dans une transaction annulée à la fin.
--
-- Fixtures : le seed (caserne A = aaaaaaaa-…-001, admin …100, membres …101 à …108)
-- plus un planning publié et une attribution acceptée, posés ici : le seed n'en
-- crée aucun et c'est justement l'historique qu'on protège.

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

grant usage on schema tests to authenticated, anon, service_role;
grant execute on all functions in schema tests to authenticated, anon, service_role;

-- ---------------------------------------------------------------------------
-- Fixtures : un planning publié et une attribution acceptée pour le membre 101
-- ---------------------------------------------------------------------------
create temp table fixture as
select 'aaaaaaaa-0000-4000-8000-000000000001'::uuid as station_id,
       'aaaaaaaa-0000-4000-8000-000000000101'::uuid as membre,
       'aaaaaaaa-0000-4000-8000-000000000100'::uuid as admin;

do $$
declare
  v_station  uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  v_membre   uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
  v_admin    uuid := 'aaaaaaaa-0000-4000-8000-000000000100';
  v_period   uuid;
  v_schedule uuid;
  v_shift    uuid;
begin
  select id into v_period from periods
   where station_id = v_station order by year, month limit 1;

  insert into schedules (station_id, period_id, status, created_by, published_at)
  values (v_station, v_period, 'published', v_admin, now())
  returning id into v_schedule;

  insert into shifts (station_id, schedule_id, date, slot, required_count)
  values (v_station, v_schedule, current_date, 'day', 1)
  returning id into v_shift;

  insert into assignments (station_id, shift_id, user_id, status, created_by, proposed_at, responded_at)
  values (v_station, v_shift, v_membre, 'accepted', v_admin, now(), now());

  insert into push_tokens (user_id, token, platform)
  values (v_membre, 'jeton-de-test-007', 'web');

  insert into notifications (station_id, user_id, type, channel, title, body)
  values (v_station, v_membre, 'schedule_validated', 'inapp', 'Planning validé', 'Corps');

  insert into invitations (station_id, email, role, invited_by)
  values ('bbbbbbbb-0000-4000-8000-000000000001', 'membre1@caserne-a.test', 'member', v_admin);
end $$;

\echo ''
\echo '=== 1. La cascade auth.users → profiles → assignments est coupée ==='

savepoint s1;

do $$
declare
  v_membre uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
begin
  perform tests.check(
    not exists (
      select 1 from pg_constraint
      where conrelid = 'public.profiles'::regclass
        and contype = 'f'
        and confrelid = 'auth.users'::regclass),
    'profiles ne référence plus auth.users');

  delete from auth.users where id = v_membre;

  perform tests.check(
    exists (select 1 from profiles where id = v_membre),
    'le profil survit à la suppression du compte d''authentification');
  perform tests.check(
    exists (select 1 from assignments where user_id = v_membre),
    'l''attribution passée survit à la suppression du compte d''authentification');
end $$;

rollback to savepoint s1;

\echo ''
\echo '=== 2. delete_own_account anonymise et désactive ==='

savepoint s2;

do $$
declare
  v_membre uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
  v_reponse jsonb;
  v_profil profiles%rowtype;
begin
  perform tests.check(
    (select count(*) from availabilities where user_id = v_membre) > 0,
    'le seed a bien donné des disponibilités au membre 101');

  v_reponse := delete_own_account(v_membre);
  perform tests.check(v_reponse ->> 'ok' = 'true', 'la suppression aboutit');
  perform tests.check(
    (v_reponse -> 'memberships')::int = 1, 'une appartenance désactivée');

  select * into v_profil from profiles where id = v_membre;
  perform tests.check(v_profil.first_name = 'Membre', 'le prénom devient « Membre »');
  perform tests.check(v_profil.last_name = 'supprimé', 'le nom devient « supprimé »');
  perform tests.check(
    v_profil.email = 'supprime@astreinte.invalid', 'l''adresse devient non routable');
  perform tests.check(v_profil.phone is null, 'le téléphone est effacé');
  perform tests.check(v_profil.push_enabled is false, 'les notifications sont coupées');

  perform tests.check(
    (select status from memberships where user_id = v_membre) = 'disabled',
    'l''appartenance est désactivée');
  perform tests.check(
    (select disabled_at from memberships where user_id = v_membre) is not null,
    'la date de sortie est posée');
  perform tests.check(
    (select display_name from memberships where user_id = v_membre) is null,
    'le surnom de caserne est effacé');

  perform tests.check(
    exists (select 1 from audit_log
            where entity_id = v_membre and action = 'account.deleted'),
    'la suppression est tracée dans le journal de la caserne');
end $$;

rollback to savepoint s2;

\echo ''
\echo '=== 3. L''attribution passée subsiste sous « Membre supprimé » ==='

savepoint s3;

do $$
declare
  v_membre uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
  v_nom text;
begin
  perform delete_own_account(v_membre);

  perform tests.check(
    (select count(*) from assignments
      where user_id = v_membre and status = 'accepted') = 1,
    'l''attribution acceptée est toujours là');

  select trim(p.first_name || ' ' || p.last_name) into v_nom
  from assignments a join profiles p on p.id = a.user_id
  where a.user_id = v_membre;
  perform tests.check(v_nom = 'Membre supprimé',
    'le planning nomme l''attribution « Membre supprimé »');

  -- Et le compte d'authentification peut maintenant partir sans rien emporter.
  delete from auth.users where id = v_membre;
  perform tests.check(
    (select count(*) from assignments where user_id = v_membre) = 1,
    'l''attribution survit aussi à la suppression du compte auth');
end $$;

rollback to savepoint s3;

\echo ''
\echo '=== 4. Ce qui est personnel part ==='

savepoint s4;

do $$
declare
  v_membre uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
begin
  perform delete_own_account(v_membre);

  perform tests.check(
    not exists (select 1 from availabilities where user_id = v_membre),
    'les disponibilités sont effacées');
  perform tests.check(
    not exists (select 1 from availability_preferences where user_id = v_membre),
    'les préférences de charge sont effacées');
  perform tests.check(
    not exists (select 1 from push_tokens where user_id = v_membre),
    'les appareils sont effacés');
  perform tests.check(
    not exists (select 1 from notifications where user_id = v_membre),
    'les notifications reçues sont effacées');
  perform tests.check(
    not exists (select 1 from invitations
                where accepted_at is null
                  and lower(email) = 'membre1@caserne-a.test'),
    'l''invitation en attente à son adresse est effacée');
end $$;

rollback to savepoint s4;

\echo ''
\echo '=== 5. Le dernier administrateur actif est refusé ==='

savepoint s5;

do $$
declare
  v_admin uuid := 'aaaaaaaa-0000-4000-8000-000000000100';
  v_reponse jsonb;
begin
  v_reponse := delete_own_account(v_admin);
  perform tests.check(v_reponse ->> 'ok' = 'false', 'la suppression est refusée');
  perform tests.check(v_reponse ->> 'code' = 'last_admin', 'le code dit pourquoi');
  perform tests.check(
    v_reponse ->> 'station' = 'CIS Saint-Martin', 'la caserne concernée est nommée');

  -- Rien n'a été écrit : un refus ne laisse pas un profil à moitié anonymisé.
  perform tests.check(
    (select first_name from profiles where id = v_admin) <> 'Membre',
    'le profil de l''administrateur est intact');
  perform tests.check(
    (select status from memberships where user_id = v_admin) = 'active',
    'son appartenance est intacte');
  perform tests.check(
    not exists (select 1 from audit_log
                where entity_id = v_admin and action = 'account.deleted'),
    'aucune trace de suppression n''est écrite');

  -- Avec un second administrateur, le même appel passe.
  update memberships set role = 'admin'
   where user_id = 'aaaaaaaa-0000-4000-8000-000000000102';
  v_reponse := delete_own_account(v_admin);
  perform tests.check(v_reponse ->> 'ok' = 'true',
    'un administrateur qui a un successeur peut partir');
end $$;

rollback to savepoint s5;

\echo ''
\echo '=== 6. La fonction est fermée aux clients ==='

savepoint s6;

do $$
begin
  perform tests.check(
    not has_function_privilege('authenticated', 'public.delete_own_account(uuid)', 'execute'),
    'authenticated n''exécute pas delete_own_account');
  perform tests.check(
    not has_function_privilege('anon', 'public.delete_own_account(uuid)', 'execute'),
    'anon n''exécute pas delete_own_account');
  perform tests.check(
    has_function_privilege('service_role', 'public.delete_own_account(uuid)', 'execute'),
    'le rôle de service, lui, l''exécute');
end $$;

rollback to savepoint s6;

\echo ''
\echo '=== 7. Un membre n''anonymise pas le profil d''un autre ==='

savepoint s7;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
declare
  n integer;
begin
  update profiles set first_name = 'Membre', last_name = 'supprimé'
   where id = 'aaaaaaaa-0000-4000-8000-000000000102';
  get diagnostics n = row_count;
  perform tests.check(n = 0, 'profiles_update_self ne laisse écrire que sa propre ligne');

  begin
    perform delete_own_account('aaaaaaaa-0000-4000-8000-000000000102');
    raise exception 'ECHEC : un membre a pu appeler delete_own_account';
  exception
    when insufficient_privilege then null;
    when raise_exception then
      if sqlerrm like 'ECHEC%' then raise; end if;
  end;
  perform tests.check(true, 'l''appel direct de delete_own_account est refusé');
end $$;

rollback to savepoint s7;

\echo ''
\echo '=== Tous les tests de suppression de compte sont passés ==='
\echo ''

rollback;
