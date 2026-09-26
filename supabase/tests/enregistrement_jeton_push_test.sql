-- Le jeton d'appareil passe au compte qui tient l'appareil (migration 0037, ticket 057).
-- Lancement : scripts/test_rls.sh (le script joue tous les supabase/tests/*.sql).
--
-- Le scénario : un téléphone de caserne prêté. Marie (A) s'y est connectée, puis
-- s'est déconnectée **hors ligne** — la ligne `push_tokens` n'a pas pu partir.
-- Thomas (B) se connecte sur le même téléphone ; FCM lui rend le même jeton T.
--
-- Ce que ces cas protègent :
--
--   1. les droits — `authenticated` seulement, `security definer`, `search_path`
--      figé ; pas de `user_id` en paramètre ;
--   2. la réattribution — T passe à B, A n'a plus de ligne pour T, donc un push
--      destiné à A ne vise plus cet appareil ; les autres jetons de A restent ;
--   3. l'étanchéité — A ne relit pas la ligne de B, et un `upsert` direct sur la
--      ligne d'un autre reste refusé par la RLS : la fonction est le seul chemin ;
--   4. le cas nominal — la déconnexion en ligne supprime la ligne sous RLS.
--
-- Même méthode que rls_test.sql : pas de pgTAP, une exception fait échouer psql
-- (`ON_ERROR_STOP`). Tout tourne dans une transaction annulée à la fin.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_jpt;

create function tests_jpt.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

-- Un refus attendu, avec son code SQLSTATE : `42501` pour un droit (grant
-- d'exécution, politique RLS en écriture), `22023` pour un argument invalide.
create function tests_jpt.refuse(p_sql text, p_state text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — l''appel a été autorisé', p_label;
exception
  when others then
    if sqlstate = p_state then
      raise notice '  ok   % (%)', p_label, sqlstate;
    else
      raise exception 'ECHEC : % — refusé, mais en % (%), pas en %',
        p_label, sqlstate, sqlerrm, p_state;
    end if;
end $$;

-- Pose l'identité d'une session : `auth.uid()` lit `sub`.
create function tests_jpt.session(p_sub uuid) returns void
language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_sub, 'role', 'authenticated')::text,
    true);
end $$;

-- Les jetons que l'envoi viserait pour un membre : exactement la lecture de
-- `send-notification` (`lireJetons` : `select user_id, token, platform from
-- push_tokens where user_id in (…)`, en service role). Security definer pour
-- la lire telle que le serveur la lit, hors RLS, depuis une session de test.
create function tests_jpt.cibles(p_user uuid) returns text[]
language sql security definer set search_path = public, pg_temp as $$
  select coalesce(array_agg(token order by token), '{}') from push_tokens where user_id = p_user;
$$;

grant usage on schema tests_jpt to authenticated, anon;
grant execute on all functions in schema tests_jpt to authenticated, anon;

-- Marie Lefebvre (A) et Thomas Moreau (B), membres de CIS Saint-Martin au seed.
-- Leurs lignes de départ sont retirées : le test ne dépend pas de ce que le seed
-- aurait pu y poser.
delete from push_tokens where user_id in ('aaaaaaaa-0000-4000-8000-000000000101',
                                          'aaaaaaaa-0000-4000-8000-000000000102');

\echo ''
\echo '=== Enregistrement du jeton push (0037) ==='

-- ===========================================================================
-- 1. Les droits
-- ===========================================================================
\echo ''
\echo '--- 1. Qui peut appeler, et comment la fonction est tenue'

select tests_jpt.check(
  has_function_privilege('authenticated',
    'public.register_push_token(text, push_platform, text)', 'execute'),
  'register_push_token : ouverte à authenticated');

select tests_jpt.check(
  not has_function_privilege('anon',
    'public.register_push_token(text, push_platform, text)', 'execute'),
  'register_push_token : fermée à anon — pas de session, pas d''appareil à inscrire');

select tests_jpt.check(
  not has_function_privilege('public',
    'public.register_push_token(text, push_platform, text)', 'execute'),
  'register_push_token : fermée au rôle public');

select tests_jpt.check(
  (select prosecdef and proconfig @> array['search_path=public, pg_temp']
     from pg_proc where proname = 'register_push_token'),
  'security definer, search_path figé avec pg_temp en dernier');

select tests_jpt.check(
  (select pg_get_function_identity_arguments(oid)
     from pg_proc where proname = 'register_push_token')
    = 'p_token text, p_platform push_platform, p_device_label text',
  'trois paramètres, aucun user_id : c''est la session qui dit à qui va la ligne');

-- La RLS de push_tokens n'est pas élargie : quatre politiques « soi-même ».
select tests_jpt.check(
  (select count(*) from pg_policies
    where tablename = 'push_tokens'
      and (coalesce(qual, '') || coalesce(with_check, '')) not like '%auth.uid()%') = 0
  and (select count(*) from pg_policies where tablename = 'push_tokens') = 4,
  'la RLS de push_tokens reste « soi-même », quatre politiques');

-- ===========================================================================
-- 2. Sous identité : A enregistre T
-- ===========================================================================
\echo ''
\echo '--- 2. Marie enregistre le jeton du téléphone de la caserne'

set local role authenticated;
select tests_jpt.session('aaaaaaaa-0000-4000-8000-000000000101');

select register_push_token('jeton-T', 'web', '  Pixel 7 · Chrome  ');
-- Un autre appareil de Marie : il ne doit pas bouger quand T change de main.
select register_push_token('jeton-A2', 'ios', null);
-- Un troisième, pour l'upsert direct du cas 4.
select register_push_token('jeton-A3', 'web', '');

select tests_jpt.check(
  (select count(*) from push_tokens where token = 'jeton-T'
      and user_id = 'aaaaaaaa-0000-4000-8000-000000000101'
      and platform = 'web' and device_label = 'Pixel 7 · Chrome') = 1,
  'A lit sa ligne : web, libellé nettoyé');

select tests_jpt.check(
  (select device_label is null from push_tokens where token = 'jeton-A3'),
  'un libellé vide s''écrit null, comme le faisait l''upsert du client');

-- Rafraîchi sans doublon : last_seen_at repart de l'instant du serveur.
reset role;
update push_tokens set last_seen_at = now() - interval '30 days' where token = 'jeton-T';
set local role authenticated;
select tests_jpt.session('aaaaaaaa-0000-4000-8000-000000000101');
select register_push_token('jeton-T', 'web', 'Pixel 7 · Chrome');

select tests_jpt.check(
  (select count(*) = 1 and max(last_seen_at) = now() from push_tokens where token = 'jeton-T'),
  'rejoué : une seule ligne, last_seen_at rafraîchi par le serveur');

select tests_jpt.check(
  tests_jpt.cibles('aaaaaaaa-0000-4000-8000-000000000101')
    = array['jeton-A2', 'jeton-A3', 'jeton-T'],
  'avant le prêt : un push destiné à A vise ses trois appareils, T compris');

-- ===========================================================================
-- 3. A est sortie hors ligne ; B se connecte sur le même téléphone
-- ===========================================================================
\echo ''
\echo '--- 3. Thomas enregistre le même jeton, sans que Marie se soit déconnectée'

select tests_jpt.session('aaaaaaaa-0000-4000-8000-000000000102');

-- Le défaut d'avant 0037, rejoué : l'upsert direct de B sur T est refusé.
select tests_jpt.refuse(
  $sql$insert into push_tokens (user_id, token, platform, last_seen_at)
       values ('aaaaaaaa-0000-4000-8000-000000000102', 'jeton-T', 'web', now())
       on conflict (token) do update set user_id = excluded.user_id,
                                         last_seen_at = excluded.last_seen_at$sql$,
  '42501',
  'upsert direct de B sur la ligne de A : refusé par la RLS (le défaut de départ)');

select register_push_token('jeton-T', 'web', 'Pixel 7 · Chrome');

select tests_jpt.check(
  (select count(*) from push_tokens where token = 'jeton-T'
      and user_id = 'aaaaaaaa-0000-4000-8000-000000000102') = 1,
  'B lit la ligne de T : elle est à lui');

reset role;
select tests_jpt.check(
  (select count(*) from push_tokens where token = 'jeton-T') = 1
  and (select user_id from push_tokens where token = 'jeton-T')
      = 'aaaaaaaa-0000-4000-8000-000000000102',
  'en base, une seule ligne pour T, au nom de B');

select tests_jpt.check(
  tests_jpt.cibles('aaaaaaaa-0000-4000-8000-000000000101') = array['jeton-A2', 'jeton-A3'],
  'un push destiné à A ne vise plus le téléphone prêté ; ses autres appareils restent');

select tests_jpt.check(
  tests_jpt.cibles('aaaaaaaa-0000-4000-8000-000000000102') = array['jeton-T'],
  'un push destiné à B arrive sur le téléphone qu''il tient');

-- ===========================================================================
-- 4. L'étanchéité : A ne voit rien de B, et la RLS tient toujours
-- ===========================================================================
\echo ''
\echo '--- 4. Ce que A ne peut plus faire'
set local role authenticated;
select tests_jpt.session('aaaaaaaa-0000-4000-8000-000000000101');

select tests_jpt.check(
  (select count(*) from push_tokens where token = 'jeton-T') = 0,
  'A ne relit pas la ligne de B');

select tests_jpt.check(
  (select count(*) from push_tokens) = 2,
  'A ne lit que ses deux lignes restantes');

-- Une suppression ou une mise à jour directe de la ligne de B filtre sans lever.
update push_tokens set user_id = 'aaaaaaaa-0000-4000-8000-000000000101' where token = 'jeton-T';
delete from push_tokens where token = 'jeton-T';

-- B, de son côté, ne peut pas prendre la ligne A3 de A par la table.
select tests_jpt.session('aaaaaaaa-0000-4000-8000-000000000102');
select tests_jpt.refuse(
  $sql$insert into push_tokens (user_id, token, platform, last_seen_at)
       values ('aaaaaaaa-0000-4000-8000-000000000102', 'jeton-A3', 'web', now())
       on conflict (token) do update set user_id = excluded.user_id$sql$,
  '42501',
  'upsert direct de B sur la ligne A3 de A : toujours refusé par la RLS');
select tests_jpt.refuse(
  $sql$insert into push_tokens (user_id, token, platform)
       values ('aaaaaaaa-0000-4000-8000-000000000101', 'jeton-X', 'web')$sql$,
  '42501',
  'insert au nom d''un autre : refusé par la RLS');

reset role;
select tests_jpt.check(
  (select user_id from push_tokens where token = 'jeton-T')
    = 'aaaaaaaa-0000-4000-8000-000000000102'
  and (select user_id from push_tokens where token = 'jeton-A3')
    = 'aaaaaaaa-0000-4000-8000-000000000101',
  'ni A ni B n''ont touché la ligne de l''autre par la table');

-- ===========================================================================
-- 5. Les refus de la fonction
-- ===========================================================================
\echo ''
\echo '--- 5. Refus : anonyme, sans session, jeton vide'

set local role anon;
do $$ begin perform set_config('request.jwt.claims', '{"role": "anon"}', true); end $$;
select tests_jpt.refuse(
  $sql$select register_push_token('jeton-T', 'web', null)$sql$,
  '42501',
  'un appel anonyme est refusé');

set local role authenticated;
do $$ begin perform set_config('request.jwt.claims', '{"role": "authenticated"}', true); end $$;
select tests_jpt.refuse(
  $sql$select register_push_token('jeton-T', 'web', null)$sql$,
  '42501',
  'un JWT sans sub est refusé');

select tests_jpt.session('aaaaaaaa-0000-4000-8000-000000000102');
select tests_jpt.refuse(
  $sql$select register_push_token('   ', 'web', null)$sql$,
  '22023',
  'un jeton vide est refusé');

reset role;
select tests_jpt.check(
  (select user_id from push_tokens where token = 'jeton-T')
    = 'aaaaaaaa-0000-4000-8000-000000000102',
  'aucun refus n''a déplacé T');

-- ===========================================================================
-- 6. Le cas nominal : la déconnexion en ligne supprime la ligne sous RLS
-- ===========================================================================
\echo ''
\echo '--- 6. B se déconnecte en ligne'
set local role authenticated;
select tests_jpt.session('aaaaaaaa-0000-4000-8000-000000000102');
delete from push_tokens where token = 'jeton-T';

reset role;
select tests_jpt.check(
  (select count(*) from push_tokens where token = 'jeton-T') = 0
  and tests_jpt.cibles('aaaaaaaa-0000-4000-8000-000000000102') = '{}',
  'la ligne est partie : plus aucun push ne vise l''appareil');

\echo ''
\echo '=== Enregistrement du jeton push : tous les cas passent ==='

rollback;
