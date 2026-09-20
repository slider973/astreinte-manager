-- Tests du déclencheur `memberships_guard_admin` (migration 0010, ticket 009).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié
-- ------------------
-- 1. Une caserne ne peut pas se retrouver sans administrateur actif : le dernier
--    admin ne peut être ni rétrogradé, ni désactivé, ni supprimé.
-- 2. Un admin ne se retire pas lui-même son accès, même quand un autre admin existe.
-- 3. Tout le reste passe : promouvoir, renommer, désactiver un membre simple,
--    réactiver, et rétrograder un admin tant qu'il en reste un autre.
-- 4. Le rôle de service n'est pas arbitré par le déclencheur — comme pour
--    `assignments_member_transition`, les fonctions serveur doivent pouvoir écrire.
-- 5. `disabled_at` suit le statut sans que l'interface ait à y penser.
--
-- Méthode identique à rls_test.sql : pas de pgTAP, une exception fait sortir psql
-- avec un code non nul. Tout le fichier tourne dans une transaction annulée à la fin.
--
-- Fixtures : le seed seul (caserne A = aaaaaaaa-…-001, un admin …100, huit membres
-- …101 à …108).

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

-- L'écriture doit être refusée par le déclencheur, avec le message attendu.
create function tests.refuse(p_sql text, p_message text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — écriture acceptée alors qu''elle devait être refusée', p_label;
exception
  when raise_exception then
    if sqlerrm like 'ECHEC%' then raise; end if;
    if sqlerrm <> p_message then
      raise exception 'ECHEC : % — refusée, mais avec le message « % » au lieu de « % »',
        p_label, sqlerrm, p_message;
    end if;
    raise notice '  ok   % (refusé : %)', p_label, sqlerrm;
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

grant usage on schema tests to authenticated, anon, service_role;
grant execute on all functions in schema tests to authenticated, anon, service_role;

\echo ''
\echo '=== 1. Le dernier administrateur actif ne peut pas être retiré ==='

savepoint s1;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests.check(
    (select count(*) from memberships
     where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
       and role = 'admin' and status = 'active') = 1,
    'le seed ne donne qu''un seul admin à la caserne A');

  perform tests.refuse(
    $sql$update memberships set role = 'member'
         where user_id = 'aaaaaaaa-0000-4000-8000-000000000100'
           and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'$sql$,
    'membership_last_admin',
    'le dernier admin ne peut pas se rétrograder');

  perform tests.refuse(
    $sql$update memberships set status = 'disabled'
         where user_id = 'aaaaaaaa-0000-4000-8000-000000000100'
           and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'$sql$,
    'membership_last_admin',
    'le dernier admin ne peut pas se désactiver');

  perform tests.refuse(
    $sql$delete from memberships
         where user_id = 'aaaaaaaa-0000-4000-8000-000000000100'
           and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'$sql$,
    'membership_last_admin',
    'le dernier admin ne peut pas être supprimé');
end $$;

rollback to savepoint s1;

\echo ''
\echo '=== 2. Un admin ne se retire pas lui-même, même à plusieurs ==='

savepoint s2;

-- Deuxième admin, posé en tant que postgres : le déclencheur ne s'oppose jamais à
-- une promotion, mais la fixture doit exister avant de passer en `authenticated`.
update memberships set role = 'admin'
where user_id = 'aaaaaaaa-0000-4000-8000-000000000101'
  and station_id = 'aaaaaaaa-0000-4000-8000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests.refuse(
    $sql$update memberships set role = 'member'
         where user_id = 'aaaaaaaa-0000-4000-8000-000000000100'
           and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'$sql$,
    'membership_self_admin_change',
    'un admin ne se rétrograde pas lui-même alors qu''un autre admin existe');

  perform tests.refuse(
    $sql$update memberships set status = 'disabled'
         where user_id = 'aaaaaaaa-0000-4000-8000-000000000100'
           and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'$sql$,
    'membership_self_admin_change',
    'un admin ne se désactive pas lui-même alors qu''un autre admin existe');

  -- Ce qui reste permis sur sa propre ligne : le nom affiché.
  perform tests.allowed(
    $sql$update memberships set display_name = 'Jean D. (chef)'
         where user_id = 'aaaaaaaa-0000-4000-8000-000000000100'
           and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'$sql$,
    'un admin garde le droit de renommer sa propre ligne');

  -- Et l'autre admin, lui, peut être rétrogradé : il en reste un.
  perform tests.allowed(
    $sql$update memberships set role = 'member'
         where user_id = 'aaaaaaaa-0000-4000-8000-000000000101'
           and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'$sql$,
    'rétrograder un admin tant qu''il en reste un autre');
end $$;

rollback to savepoint s2;

\echo ''
\echo '=== 3. Les écritures d''administration ordinaires passent ==='

savepoint s3;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests.allowed(
    $sql$update memberships set role = 'admin'
         where user_id = 'aaaaaaaa-0000-4000-8000-000000000102'
           and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'$sql$,
    'promouvoir un membre en admin');

  perform tests.allowed(
    $sql$update memberships set display_name = 'Marie L.'
         where user_id = 'aaaaaaaa-0000-4000-8000-000000000101'
           and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'$sql$,
    'modifier le nom affiché d''un membre');

  perform tests.allowed(
    $sql$update memberships set status = 'disabled'
         where user_id = 'aaaaaaaa-0000-4000-8000-000000000103'
           and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'$sql$,
    'désactiver un membre simple');

  perform tests.check(
    (select disabled_at is not null from memberships
     where user_id = 'aaaaaaaa-0000-4000-8000-000000000103'
       and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
    'disabled_at est renseigné par le déclencheur');

  perform tests.allowed(
    $sql$update memberships set status = 'active'
         where user_id = 'aaaaaaaa-0000-4000-8000-000000000103'
           and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'$sql$,
    'réactiver un membre désactivé');

  perform tests.check(
    (select disabled_at is null from memberships
     where user_id = 'aaaaaaaa-0000-4000-8000-000000000103'
       and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
    'disabled_at est effacé à la réactivation');
end $$;

rollback to savepoint s3;

\echo ''
\echo '=== 4. Un admin d''une autre caserne reste hors sujet (rappel RLS) ==='

savepoint s4;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  n integer;
begin
  update memberships set role = 'member'
  where user_id = 'aaaaaaaa-0000-4000-8000-000000000100'
    and station_id = 'aaaaaaaa-0000-4000-8000-000000000001';
  get diagnostics n = row_count;
  perform tests.check(n = 0,
    'l''admin de B ne touche pas l''admin de A (filtré par la politique, avant le déclencheur)');
end $$;

rollback to savepoint s4;

\echo ''
\echo '=== 5. Le rôle de service n''est pas arbitré par le déclencheur ==='

savepoint s5;
set local role service_role;

do $$
begin
  -- Le cas exact que le déclencheur refuse à un client : le dernier admin de A.
  perform tests.allowed(
    $sql$update memberships set status = 'disabled'
         where user_id = 'aaaaaaaa-0000-4000-8000-000000000100'
           and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'$sql$,
    'le service role désactive le dernier admin (support, RGPD, réparation)');

  perform tests.check(
    (select disabled_at is not null from memberships
     where user_id = 'aaaaaaaa-0000-4000-8000-000000000100'
       and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
    'disabled_at est tenu à jour même pour le rôle de service');
end $$;

rollback to savepoint s5;

\echo ''
\echo '=== 5b. Un membre désactivé reste visible par son admin ==='

savepoint s5b;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests.allowed(
    $sql$update memberships set status = 'disabled'
         where user_id = 'aaaaaaaa-0000-4000-8000-000000000103'
           and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'$sql$,
    'désactivation du membre à retrouver');

  -- La ligne d'appartenance, évidemment.
  perform tests.check(
    (select count(*) from memberships
     where user_id = 'aaaaaaaa-0000-4000-8000-000000000103'
       and station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 1,
    'l''appartenance désactivée reste lisible par l''admin');

  -- Et son profil : sans lui, la jointure `profiles!inner` de l'écran perd la
  -- ligne, et « Réactiver l'accès » porte sur quelqu'un d'invisible. C'est le
  -- défaut trouvé en essayant l'écran contre la base locale.
  perform tests.check(
    (select count(*) from profiles
     where id = 'aaaaaaaa-0000-4000-8000-000000000103') = 1,
    'le profil d''un membre désactivé reste lisible par son admin');
end $$;

rollback to savepoint s5b;

savepoint s5c;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

update memberships set status = 'disabled'
where user_id = 'aaaaaaaa-0000-4000-8000-000000000103'
  and station_id = 'aaaaaaaa-0000-4000-8000-000000000001';

set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests.check(
    (select count(*) from profiles
     where id = 'aaaaaaaa-0000-4000-8000-000000000103') = 0,
    'un membre simple, lui, ne lit plus le profil d''un désactivé');
end $$;

rollback to savepoint s5c;

\echo ''
\echo '=== 6. La vue v_member_last_availability est lue sous la RLS de availabilities ==='

savepoint s6;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests.check(
    (select count(*) from v_member_last_availability
     where station_id = 'bbbbbbbb-0000-4000-8000-000000000001') = 0,
    'un admin de A ne lit aucune dernière saisie de la caserne B');

  perform tests.check(
    (select count(*) from v_member_last_availability
     where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') > 0,
    'un admin de A lit les dernières saisies de sa caserne');
end $$;

rollback to savepoint s6;

savepoint s6b;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests.check(
    (select coalesce(bool_and(user_id = 'aaaaaaaa-0000-4000-8000-000000000101'), true)
     from v_member_last_availability),
    'un membre simple ne lit que sa propre dernière saisie');
end $$;

rollback to savepoint s6b;

\echo ''
\echo '=== Tous les tests d''administration des membres sont passés ==='
\echo ''

rollback;
