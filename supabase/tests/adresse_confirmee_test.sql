-- L'adresse confirmée, lue à la source (migration 0038, ticket 058).
-- Lancement : scripts/test_rls.sh (le script joue tous les supabase/tests/*.sql).
--
-- Ce que ces cas protègent : `my_pending_invitations()` et
-- `accept_invitation_by_id()` ne croient plus le jeton sur parole. C'est
-- `auth.users.email_confirmed_at` qui tranche, et les métadonnées — que le
-- titulaire écrit lui-même par `auth.updateUser` — n'ont plus voix au chapitre,
-- ni pour fermer, ni pour ouvrir.
--
--   1. métadonnées « non vérifiée », adresse confirmée à la source : il voit ;
--   2. adresse non confirmée à la source : rien à voir, rien à accepter par
--      identifiant, quelles que soient les revendications du jeton ;
--   3. le compte confirmé ordinaire : il voit son invitation et l'accepte.
--
-- Même méthode que rls_test.sql : pas de pgTAP, une exception fait échouer psql
-- (`ON_ERROR_STOP`). Tout tourne dans une transaction annulée à la fin.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_conf;

create function tests_conf.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

-- Pose l'identité d'une session comme GoTrue la signe : `sub`, `email`, et
-- `user_metadata` recopié de `raw_user_meta_data`. `p_extra` ajoute ou
-- remplace des revendications — c'est là qu'un jeton « se déclare » vérifié.
create function tests_conf.session(p_sub uuid, p_extra jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform set_config(
    'request.jwt.claims',
    (coalesce((select jsonb_build_object('email', u.email,
                                         'user_metadata', u.raw_user_meta_data)
                 from auth.users u where u.id = p_sub), '{}'::jsonb)
      || p_extra
      || jsonb_build_object('sub', p_sub, 'role', 'authenticated'))::text,
    true);
end $$;

grant usage on schema tests_conf to authenticated, service_role;
grant execute on all functions in schema tests_conf to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Fixtures : trois comptes hors seed, sans appartenance, chacun invité à la
-- caserne A par Jean Dupont.
--
--   …581  confirmé à la source, `user_metadata.email_verified = false` ;
--   …582  **non confirmé** (`email_confirmed_at` nul),
--         `user_metadata.email_verified = true` ;
--   …583  confirmé, métadonnées vides — le cas ordinaire.
-- ---------------------------------------------------------------------------
insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current
) values
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-0000-4000-8000-000000000581',
   'authenticated', 'authenticated', 'recrue58a@caserne-a.test', now(),
   '{"provider": "email", "providers": ["email"]}'::jsonb,
   '{"email_verified": false}'::jsonb, now(), now(),
   '', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-0000-4000-8000-000000000582',
   'authenticated', 'authenticated', 'recrue58b@caserne-a.test', null,
   '{"provider": "email", "providers": ["email"]}'::jsonb,
   '{"email_verified": true}'::jsonb, now(), now(),
   '', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-0000-4000-8000-000000000583',
   'authenticated', 'authenticated', 'recrue58c@caserne-a.test', now(),
   '{"provider": "email", "providers": ["email"]}'::jsonb,
   '{}'::jsonb, now(), now(),
   '', '', '', '', '');

insert into invitations (id, station_id, email, role, invited_by, expires_at) values
  ('58580000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001',
   'recrue58a@caserne-a.test', 'member', 'aaaaaaaa-0000-4000-8000-000000000100',
   now() + interval '10 days'),
  ('58580000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001',
   'recrue58b@caserne-a.test', 'member', 'aaaaaaaa-0000-4000-8000-000000000100',
   now() + interval '10 days'),
  ('58580000-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001',
   'recrue58c@caserne-a.test', 'member', 'aaaaaaaa-0000-4000-8000-000000000100',
   now() + interval '10 days');

\echo ''
\echo '=== Adresse confirmée à la source (0038) ==='

-- ===========================================================================
-- 0. Ce qui ne bouge pas : signatures, sécurité, droits
-- ===========================================================================
\echo ''
\echo '--- 0. Signatures, security definer, search_path et droits inchangés'

select tests_conf.check(
  (select prosecdef and provolatile = 's' and pronargs = 0
          and proconfig @> array['search_path=public, pg_temp']
     from pg_proc where oid = 'public.my_pending_invitations()'::regprocedure),
  'my_pending_invitations : sans paramètre, stable, security definer, search_path figé');

select tests_conf.check(
  (select prosecdef and proconfig @> array['search_path=public, pg_temp']
          and pg_get_function_result(oid) = 'jsonb'
     from pg_proc where oid = 'public.accept_invitation_by_id(uuid, uuid, text)'::regprocedure),
  'accept_invitation_by_id : même signature, security definer, search_path figé');

select tests_conf.check(
  has_function_privilege('authenticated', 'public.my_pending_invitations()', 'execute')
  and not has_function_privilege('anon', 'public.my_pending_invitations()', 'execute'),
  'my_pending_invitations : authenticated oui, anon non');

select tests_conf.check(
  has_function_privilege('service_role', 'public.accept_invitation_by_id(uuid, uuid, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.accept_invitation_by_id(uuid, uuid, text)', 'execute')
  and not has_function_privilege('anon', 'public.accept_invitation_by_id(uuid, uuid, text)', 'execute'),
  'accept_invitation_by_id : service_role uniquement');

select tests_conf.check(
  not exists (
    select 1 from pg_proc
     where oid in ('public.my_pending_invitations()'::regprocedure,
                   'public.accept_invitation_by_id(uuid, uuid, text)'::regprocedure)
       and (prosrc ~ '''email_verified''' or prosrc ~ 'user_metadata,')),
  'aucune des deux fonctions ne lit plus la revendication email_verified');

-- ===========================================================================
-- 1. Métadonnées « non vérifiée », adresse confirmée à la source : il voit
-- ===========================================================================
\echo ''
\echo '--- 1. user_metadata.email_verified = false, email_confirmed_at posé'
savepoint s1;

set local role authenticated;
select tests_conf.session('cccccccc-0000-4000-8000-000000000581');

select tests_conf.check(
  (select current_setting('request.jwt.claims')::jsonb #>> '{user_metadata,email_verified}') = 'false',
  'le jeton porte bien user_metadata.email_verified = false');

select tests_conf.check(
  (select count(*) from my_pending_invitations()) = 1
  and (select id from my_pending_invitations()) = '58580000-0000-4000-8000-000000000001',
  'il voit son invitation : la métadonnée n''a plus autorité');

-- Et même en ajoutant la revendication au premier niveau.
select tests_conf.session('cccccccc-0000-4000-8000-000000000581', '{"email_verified": false}'::jsonb);
select tests_conf.check(
  (select count(*) from my_pending_invitations()) = 1,
  'email_verified = false au premier niveau du jeton ne ferme rien non plus');

reset role;
select set_config('request.jwt.claims', '', true);
rollback to savepoint s1;

-- ===========================================================================
-- 2. Adresse non confirmée à la source : rien, quelles que soient les métadonnées
-- ===========================================================================
\echo ''
\echo '--- 2. email_confirmed_at nul : rien à voir, rien à accepter'
savepoint s2;

set local role authenticated;

-- Le jeton tel que GoTrue le signerait : user_metadata.email_verified = true.
select tests_conf.session('cccccccc-0000-4000-8000-000000000582');
select tests_conf.check(
  (select count(*) from my_pending_invitations()) = 0,
  'user_metadata.email_verified = true : zéro ligne');

-- Toutes les façons de « se déclarer » vérifié dans le jeton.
select tests_conf.session('cccccccc-0000-4000-8000-000000000582', '{"email_verified": true}'::jsonb);
select tests_conf.check(
  (select count(*) from my_pending_invitations()) = 0,
  'email_verified = true au premier niveau : zéro ligne');

select tests_conf.session('cccccccc-0000-4000-8000-000000000582',
  '{"email_verified": "true", "user_metadata": {"email_verified": true}}'::jsonb);
select tests_conf.check(
  (select count(*) from my_pending_invitations()) = 0,
  'les deux revendications à vrai ensemble : zéro ligne');

select tests_conf.session('cccccccc-0000-4000-8000-000000000582', '{"user_metadata": {}}'::jsonb);
select tests_conf.check(
  (select count(*) from my_pending_invitations()) = 0,
  'sans aucune revendication (l''ancien repli permissif) : zéro ligne');

-- Un `sub` qui ne désigne aucun compte, avec l'adresse invitée dans le jeton :
-- rien non plus. L'adresse du jeton ne suffit jamais seule.
select set_config('request.jwt.claims',
  '{"sub":"cccccccc-0000-4000-8000-0000000005ff","role":"authenticated","email":"recrue58a@caserne-a.test","email_verified":true}',
  true);
select tests_conf.check(
  (select count(*) from my_pending_invitations()) = 0,
  'un sub sans compte, même porteur d''une adresse invitée : zéro ligne');

reset role;
select set_config('request.jwt.claims', '', true);

-- L'acceptation par identifiant, comme l'appelle l'Edge Function : clé de
-- service, `p_user_id` et `p_email` tirés de `auth.getUser(jwt)`.
set local role service_role;

do $$
declare
  r        jsonb;
  r_inconnu jsonb;
begin
  r := accept_invitation_by_id('58580000-0000-4000-8000-000000000002',
                               'cccccccc-0000-4000-8000-000000000582',
                               'recrue58b@caserne-a.test');
  perform tests_conf.check(r->>'ok' = 'false' and r->>'code' = 'email_mismatch',
    'accept_invitation_by_id refuse un compte non confirmé : email_mismatch');

  r_inconnu := accept_invitation_by_id('58580000-0000-4000-8000-0000000000ff',
                                       'cccccccc-0000-4000-8000-000000000582',
                                       'recrue58b@caserne-a.test');
  perform tests_conf.check(r = r_inconnu,
    'le refus est indiscernable de celui d''un identifiant inconnu');
  perform tests_conf.check(
    not (r ? 'station') and not (r ? 'inviter') and not (r ? 'invited_email_masked'),
    'le refus ne nomme ni la caserne, ni l''invitant, ni l''adresse');
end $$;

reset role;

select tests_conf.check(
  not exists (select 1 from memberships
               where user_id = 'cccccccc-0000-4000-8000-000000000582'),
  'aucune appartenance créée');
select tests_conf.check(
  (select accepted_at is null from invitations
    where id = '58580000-0000-4000-8000-000000000002'),
  'l''invitation reste en attente');

-- Et c'est bien la colonne qui décide : confirmée à la source, la même
-- session voit, et la même acceptation passe.
update auth.users set email_confirmed_at = now()
 where id = 'cccccccc-0000-4000-8000-000000000582';

set local role authenticated;
select tests_conf.session('cccccccc-0000-4000-8000-000000000582');
select tests_conf.check(
  (select count(*) from my_pending_invitations()) = 1,
  'une fois email_confirmed_at posé, la même session voit son invitation');
reset role;
select set_config('request.jwt.claims', '', true);

set local role service_role;
select tests_conf.check(
  accept_invitation_by_id('58580000-0000-4000-8000-000000000002',
                          'cccccccc-0000-4000-8000-000000000582',
                          'recrue58b@caserne-a.test')->>'ok' = 'true',
  'et l''acceptation par identifiant passe');
reset role;

rollback to savepoint s2;

-- ===========================================================================
-- 3. Le compte confirmé ordinaire : il voit, il accepte
-- ===========================================================================
\echo ''
\echo '--- 3. Compte confirmé : il voit son invitation et l''accepte'
savepoint s3;

set local role authenticated;
select tests_conf.session('cccccccc-0000-4000-8000-000000000583');

do $$
declare v record;
begin
  perform tests_conf.check(
    (select count(*) from my_pending_invitations()) = 1,
    'une invitation, la sienne');
  select * into v from my_pending_invitations();
  perform tests_conf.check(
    v.id = '58580000-0000-4000-8000-000000000003'
    and v.station_name = 'CIS Saint-Martin'
    and v.invited_by_name = 'Jean Dupont'
    and v.status = 'pending',
    'identifiant, caserne, invitant et statut rendus');
  perform tests_conf.check(
    not exists (select 1 from my_pending_invitations()
                 where id in ('58580000-0000-4000-8000-000000000001',
                              '58580000-0000-4000-8000-000000000002')),
    'rien des invitations des deux autres comptes');
end $$;

reset role;
select set_config('request.jwt.claims', '', true);

set local role service_role;
do $$
declare r jsonb;
begin
  r := accept_invitation_by_id('58580000-0000-4000-8000-000000000003',
                               'cccccccc-0000-4000-8000-000000000583',
                               'recrue58c@caserne-a.test');
  perform tests_conf.check(r->>'ok' = 'true', 'il entre dans la caserne par identifiant');
  perform tests_conf.check(r#>>'{station,name}' = 'CIS Saint-Martin',
    'la réponse nomme la caserne');
end $$;
reset role;

select tests_conf.check(
  (select status = 'active' from memberships
    where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
      and user_id = 'cccccccc-0000-4000-8000-000000000583'),
  'l''appartenance est créée, active');

set local role authenticated;
select tests_conf.session('cccccccc-0000-4000-8000-000000000583');
select tests_conf.check(
  (select count(*) from my_pending_invitations()) = 0,
  'l''invitation acceptée sort de la liste');
reset role;
select set_config('request.jwt.claims', '', true);

rollback to savepoint s3;

\echo ''
\echo '=== Adresse confirmée à la source : tous les cas passent ==='

rollback;
