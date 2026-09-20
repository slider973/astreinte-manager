-- Tests des fonctions d'invitation (migration 0009, ticket 006).
-- Lancement : scripts/test_rls.sh (le script joue tous les supabase/tests/*.sql).
--
-- Périmètre : la couche SQL, celle qui décide. Les deux Edge Functions ne font
-- qu'emballer ces fonctions en HTTP ; elles sont éprouvées par
-- scripts/test_functions.sh, qui a besoin de `supabase functions serve` et reste
-- donc local (la CI démarre la pile sans edge-runtime, voir .github/workflows/ci.yml).
--
-- Même méthode que rls_test.sql : pas de pgTAP, une exception fait échouer psql
-- (`ON_ERROR_STOP`). Tout tourne dans une transaction annulée à la fin.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_inv;

create function tests_inv.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

grant usage on schema tests_inv to authenticated;
grant execute on all functions in schema tests_inv to authenticated;

-- ---------------------------------------------------------------------------
-- Fixtures : un compte hors seed, pour jouer l'invité qui vient de recevoir son
-- compte (créé côté Edge Function par la clé de service).
-- ---------------------------------------------------------------------------
insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current
) values (
  '00000000-0000-0000-0000-000000000000',
  'cccccccc-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'recrue@caserne-a.test', now(),
  '{"provider": "email", "providers": ["email"]}'::jsonb, '{}'::jsonb, now(), now(),
  '', '', '', '', ''
);

\echo ''
\echo '=== Fonctions d''invitation (0009) ==='

-- ===========================================================================
-- 1. create_invitation — le droit d'inviter
-- ===========================================================================
\echo ''
\echo '--- 1. create_invitation : qui a le droit d''inviter'
savepoint s1;

do $$
declare r jsonb;
begin
  -- Un membre simple n'invite pas.
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000101');
  perform tests_inv.check(r->>'code' = 'not_admin',
    'create_invitation : un membre simple ne peut pas inviter');

  -- L'admin de la caserne B ne pose rien dans la caserne A, même en visant son id.
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'bbbbbbbb-0000-4000-8000-000000000100');
  perform tests_inv.check(r->>'code' = 'not_admin',
    'create_invitation : l''admin de la caserne B ne peut pas inviter dans la caserne A');

  perform tests_inv.check((select count(*) from invitations) = 0,
    'create_invitation : aucune ligne écrite par les tentatives refusées');

  -- Un admin désactivé perd le droit d'inviter.
  update memberships set status = 'disabled', disabled_at = now()
   where user_id = 'aaaaaaaa-0000-4000-8000-000000000100';
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_inv.check(r->>'code' = 'not_admin',
    'create_invitation : un admin désactivé ne peut plus inviter');
end $$;

rollback to savepoint s1;

-- ===========================================================================
-- 2. create_invitation — cas nominal et renvoi
-- ===========================================================================
\echo ''
\echo '--- 2. create_invitation : création puis renvoi'
savepoint s2;

do $$
declare
  r1 jsonb; r2 jsonb;
begin
  r1 := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', '  Recrue@Caserne-A.test ',
                          'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_inv.check(r1->>'ok' = 'true', 'create_invitation : cas nominal accepté');
  perform tests_inv.check(r1->'invitation'->>'email' = 'recrue@caserne-a.test',
    'create_invitation : adresse normalisée (espaces et casse)');
  perform tests_inv.check(length(r1->>'token') = 48,
    'create_invitation : un token de 24 octets est renvoyé au service');
  perform tests_inv.check((r1->>'resent')::boolean is false,
    'create_invitation : première invitation, resent = false');
  perform tests_inv.check((r1->>'account_exists')::boolean is true,
    'create_invitation : le compte existant est signalé (pas de doublon à créer)');
  perform tests_inv.check(
    (r1->'invitation'->>'expires_at')::timestamptz between now() + interval '13 days'
                                                      and now() + interval '15 days',
    'create_invitation : expiration à 14 jours');

  -- Renvoi : même ligne, même token, expiration repoussée.
  update invitations set expires_at = now() + interval '1 day';
  r2 := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                          'admin', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_inv.check((r2->>'resent')::boolean is true,
    'create_invitation : le renvoi est signalé');
  perform tests_inv.check(r2->'invitation'->>'id' = r1->'invitation'->>'id',
    'create_invitation : le renvoi réutilise la ligne, pas de doublon');
  perform tests_inv.check(r2->>'token' = r1->>'token',
    'create_invitation : le renvoi conserve le token (le lien déjà envoyé reste valable)');
  perform tests_inv.check(
    (r2->'invitation'->>'expires_at')::timestamptz > now() + interval '13 days',
    'create_invitation : le renvoi repousse l''expiration à 14 jours');
  perform tests_inv.check(r2->'invitation'->>'role' = 'admin',
    'create_invitation : le renvoi met le rôle à jour');
  perform tests_inv.check((select count(*) from invitations) = 1,
    'create_invitation : une seule invitation en attente pour la caserne et l''adresse');

  perform tests_inv.check(
    (select count(*) from audit_log where action = 'invitation.created') = 1
    and (select count(*) from audit_log where action = 'invitation.resent') = 1,
    'create_invitation : journal d''audit alimenté (created puis resent)');
end $$;

rollback to savepoint s2;

-- ===========================================================================
-- 3. create_invitation — refus métier
-- ===========================================================================
\echo ''
\echo '--- 3. create_invitation : refus métier'
savepoint s3;

do $$
declare r jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'membre1@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_inv.check(r->>'code' = 'already_member',
    'create_invitation : une adresse déjà membre actif est refusée');

  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'MEMBRE1@CASERNE-A.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_inv.check(r->>'code' = 'already_member',
    'create_invitation : le refus « déjà membre » ignore la casse');

  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'pas une adresse',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_inv.check(r->>'code' = 'invalid_email',
    'create_invitation : adresse invalide refusée');

  r := create_invitation('dddddddd-0000-4000-8000-0000000000ff', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_inv.check(r->>'code' = 'station_not_found',
    'create_invitation : caserne inconnue refusée');

  -- Un membre désactivé, lui, peut être réinvité.
  update memberships set status = 'disabled', disabled_at = now()
   where user_id = 'aaaaaaaa-0000-4000-8000-000000000101';
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'membre1@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_inv.check(r->>'ok' = 'true',
    'create_invitation : un ancien membre désactivé peut être réinvité');
end $$;

rollback to savepoint s3;

\echo ''
\echo '--- 3b. create_invitation : caserne suspendue'
savepoint s3b;

update subscriptions set status = 'suspended'
 where station_id = 'aaaaaaaa-0000-4000-8000-000000000001';

do $$
declare r jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_inv.check(r->>'code' = 'station_suspended',
    'create_invitation : caserne suspendue, pas de nouvelle invitation');
end $$;

rollback to savepoint s3b;

-- ===========================================================================
-- 4. accept_invitation — cas nominal, rejeu et atomicité
-- ===========================================================================
\echo ''
\echo '--- 4. accept_invitation : cas nominal'
savepoint s4;

do $$
declare
  r jsonb; t text; a jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'admin', 'aaaaaaaa-0000-4000-8000-000000000100');
  t := r->>'token';

  a := accept_invitation(t, 'cccccccc-0000-4000-8000-000000000001', 'Recrue@Caserne-A.test');
  perform tests_inv.check(a->>'ok' = 'true',
    'accept_invitation : acceptation acceptée (casse de l''adresse ignorée)');
  perform tests_inv.check(a->'membership'->>'status' = 'active'
                      and a->'membership'->>'role' = 'admin',
    'accept_invitation : membership active avec le rôle prévu par l''invitation');
  perform tests_inv.check(a->'station'->>'name' = 'CIS Saint-Martin',
    'accept_invitation : la caserne est renvoyée à l''app');
  perform tests_inv.check(a->'inviter'->>'email' = 'admin@caserne-a.test',
    'accept_invitation : l''inviteur est renvoyé (pour « contacter ton administrateur »)');
  perform tests_inv.check(a ? 'token' is false,
    'accept_invitation : le token n''est jamais renvoyé');

  perform tests_inv.check(
    (select accepted_at is not null from invitations where token = t),
    'accept_invitation : invitation marquée acceptée');
  perform tests_inv.check(
    (select count(*) from memberships
      where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
        and user_id = 'cccccccc-0000-4000-8000-000000000001'
        and status = 'active') = 1,
    'accept_invitation : une membership, une seule');
  perform tests_inv.check(
    (select count(*) from audit_log where action = 'invitation.accepted') = 1,
    'accept_invitation : journal d''audit alimenté');

  -- Rejeu du même lien : idempotent, pas de seconde membership.
  a := accept_invitation(t, 'cccccccc-0000-4000-8000-000000000001', 'recrue@caserne-a.test');
  perform tests_inv.check(a->>'ok' = 'true' and (a->>'already_accepted')::boolean is true,
    'accept_invitation : rejeu du même lien accepté sans rien recréer');
  perform tests_inv.check(
    (select count(*) from memberships
      where user_id = 'cccccccc-0000-4000-8000-000000000001') = 1,
    'accept_invitation : toujours une seule membership après rejeu');

  -- Une invitation déjà acceptée n'ouvre pas la porte à quelqu'un d'autre.
  a := accept_invitation(t, 'bbbbbbbb-0000-4000-8000-000000000101', 'membre1@caserne-b.test');
  perform tests_inv.check(a->>'code' = 'email_mismatch',
    'accept_invitation : un tiers ne récupère pas une invitation déjà acceptée');
end $$;

rollback to savepoint s4;

-- ===========================================================================
-- 5. accept_invitation — refus
-- ===========================================================================
\echo ''
\echo '--- 5. accept_invitation : refus'
savepoint s5;

do $$
declare
  r jsonb; t text; a jsonb;
begin
  a := accept_invitation('token-inexistant', 'cccccccc-0000-4000-8000-000000000001',
                         'recrue@caserne-a.test');
  perform tests_inv.check(a->>'code' = 'invitation_not_found',
    'accept_invitation : token inconnu refusé');

  a := accept_invitation('', 'cccccccc-0000-4000-8000-000000000001', 'recrue@caserne-a.test');
  perform tests_inv.check(a->>'code' = 'invitation_not_found',
    'accept_invitation : token vide refusé');

  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  t := r->>'token';

  -- Adresse de session différente de l'adresse invitée : le lien se transfère,
  -- l'appartenance non.
  a := accept_invitation(t, 'bbbbbbbb-0000-4000-8000-000000000101', 'membre1@caserne-b.test');
  perform tests_inv.check(a->>'code' = 'email_mismatch',
    'accept_invitation : un porteur de lien qui n''est pas l''invité est refusé');
  perform tests_inv.check(a->>'invited_email_masked' = 'r••••e@caserne-a.test',
    'accept_invitation : l''adresse invitée est renvoyée masquée, pas en clair');
  perform tests_inv.check(
    (select count(*) from memberships
      where user_id = 'bbbbbbbb-0000-4000-8000-000000000101'
        and station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 0,
    'accept_invitation : aucune membership créée par la tentative refusée');
  perform tests_inv.check(
    (select accepted_at is null from invitations where token = t),
    'accept_invitation : l''invitation reste en attente après une tentative refusée');

  -- Expirée.
  update invitations set expires_at = now() - interval '1 second' where token = t;
  a := accept_invitation(t, 'cccccccc-0000-4000-8000-000000000001', 'recrue@caserne-a.test');
  perform tests_inv.check(a->>'code' = 'invitation_expired',
    'accept_invitation : invitation expirée refusée');
  perform tests_inv.check(a->'inviter'->>'email' = 'admin@caserne-a.test',
    'accept_invitation : l''expiration renvoie de quoi contacter l''admin');
  perform tests_inv.check(
    (select count(*) from memberships
      where user_id = 'cccccccc-0000-4000-8000-000000000001') = 0,
    'accept_invitation : rien n''est écrit pour une invitation expirée');

  -- Une invitation acceptée par un autre compte : ni doublon, ni reprise.
  update invitations set expires_at = now() + interval '14 days', accepted_at = now()
   where token = t;
  a := accept_invitation(t, 'cccccccc-0000-4000-8000-000000000001', 'recrue@caserne-a.test');
  perform tests_inv.check(a->>'code' = 'invitation_already_accepted',
    'accept_invitation : invitation déjà acceptée refusée');
end $$;

rollback to savepoint s5;

\echo ''
\echo '--- 5b. accept_invitation : caserne suspendue'
savepoint s5b;

do $$
declare r jsonb; a jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  update subscriptions set status = 'suspended'
   where station_id = 'aaaaaaaa-0000-4000-8000-000000000001';
  a := accept_invitation(r->>'token', 'cccccccc-0000-4000-8000-000000000001',
                         'recrue@caserne-a.test');
  perform tests_inv.check(a->>'code' = 'station_suspended',
    'accept_invitation : on n''entre pas dans une caserne suspendue');
end $$;

rollback to savepoint s5b;

-- ===========================================================================
-- 6. accept_invitation — réactivation d'un ancien membre
-- ===========================================================================
\echo ''
\echo '--- 6. accept_invitation : réactivation d''un membre désactivé'
savepoint s6;

do $$
declare r jsonb; a jsonb;
begin
  update memberships set status = 'disabled', disabled_at = now()
   where user_id = 'aaaaaaaa-0000-4000-8000-000000000101';

  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'membre1@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  a := accept_invitation(r->>'token', 'aaaaaaaa-0000-4000-8000-000000000101',
                         'membre1@caserne-a.test');
  perform tests_inv.check(a->>'ok' = 'true' and a->'membership'->>'status' = 'active',
    'accept_invitation : l''ancien membre est réactivé, pas dupliqué');
  perform tests_inv.check(
    (select disabled_at is null from memberships
      where user_id = 'aaaaaaaa-0000-4000-8000-000000000101'),
    'accept_invitation : disabled_at effacé à la réactivation');
  perform tests_inv.check(
    (select count(*) from memberships
      where user_id = 'aaaaaaaa-0000-4000-8000-000000000101') = 1,
    'accept_invitation : toujours une seule membership');
end $$;

rollback to savepoint s6;

-- ===========================================================================
-- 7. Les deux fonctions sont fermées au rôle authenticated
-- ===========================================================================
-- Sans ce verrou, un admin appellerait create_invitation en RPC PostgREST et
-- lirait le token que 0008 lui a justement retiré.
\echo ''
\echo '--- 7. Exécution réservée au service_role'
savepoint s7;

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  begin
    perform public.create_invitation('aaaaaaaa-0000-4000-8000-000000000001',
      'recrue@caserne-a.test', 'member', 'aaaaaaaa-0000-4000-8000-000000000100');
    raise exception 'ECHEC : create_invitation exécutable par le rôle authenticated';
  exception when insufficient_privilege then
    raise notice '  ok   create_invitation : exécution refusée à authenticated (%)', sqlerrm;
  end;

  begin
    perform public.accept_invitation('peu importe',
      'aaaaaaaa-0000-4000-8000-000000000100', 'admin@caserne-a.test');
    raise exception 'ECHEC : accept_invitation exécutable par le rôle authenticated';
  exception when insufficient_privilege then
    raise notice '  ok   accept_invitation : exécution refusée à authenticated (%)', sqlerrm;
  end;
end $$;

rollback to savepoint s7;

\echo ''
\echo '=== Tous les tests d''invitation sont passés ==='
\echo ''

rollback;
