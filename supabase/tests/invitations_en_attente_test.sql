-- Les invitations en attente vues par l'invité (migration 0036, ticket 051).
-- Lancement : scripts/test_rls.sh (le script joue tous les supabase/tests/*.sql).
--
-- Ce que ces cas protègent :
--
--   1. l'étanchéité — la fonction n'a pas de paramètre, donc pas de vecteur
--      d'énumération ; le test le dit quand même, sous identité, parce qu'un
--      paramètre ajouté plus tard doit casser ici ;
--   2. le jeton — hors de portée d'`authenticated` par tous les chemins : le
--      `grant` de colonne de 0008, la fonction de lecture, et l'acceptation par
--      identifiant ;
--   3. la frontière d'expiration — tranchée par le serveur, et une invitation
--      expirée est **rendue** (sinon « expirée » redeviendrait « aucune », qui est
--      exactement le mensonge que le ticket corrige) ;
--   4. l'acceptation par identifiant — mêmes fins de parcours que par jeton, et
--      un identifiant qui n'est pas le sien est refusé sans rien apprendre.
--
-- Même méthode que rls_test.sql : pas de pgTAP, une exception fait échouer psql
-- (`ON_ERROR_STOP`). Tout tourne dans une transaction annulée à la fin.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_att;

create function tests_att.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

-- Un refus de privilège (grant de colonne, grant d'exécution) lève
-- `insufficient_privilege`. Les politiques RLS, elles, ne lèvent rien : elles
-- filtrent, et c'est `check(count = 0)` qui les couvre.
create function tests_att.refuse(p_sql text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — l''appel a été autorisé', p_label;
exception
  when insufficient_privilege then
    raise notice '  ok   %', p_label;
end $$;

-- Pose l'identité d'une session : `auth.uid()` lit `sub`, `auth.jwt() ->> 'email'`
-- lit `email`. C'est tout ce dont `my_pending_invitations()` a besoin — et c'est
-- tout ce qu'elle peut savoir de l'appelant.
create function tests_att.session(p_sub uuid, p_email text, p_extra jsonb default '{}'::jsonb)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    (jsonb_build_object('sub', p_sub, 'role', 'authenticated', 'email', p_email) || p_extra)::text,
    true);
end $$;

grant usage on schema tests_att to authenticated, anon;
grant execute on all functions in schema tests_att to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Fixtures : deux comptes hors seed, sans la moindre appartenance. C'est
-- exactement l'état du compte du 21 septembre 2026 — né de `invite-member`,
-- connecté sans passer par le lien du courriel.
-- ---------------------------------------------------------------------------
insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current
) values
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-0000-4000-8000-000000000051',
   'authenticated', 'authenticated', 'recrue51a@caserne-a.test', now(),
   '{"provider": "email", "providers": ["email"]}'::jsonb, '{}'::jsonb, now(), now(),
   '', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-0000-4000-8000-000000000052',
   'authenticated', 'authenticated', 'recrue51b@caserne-b.test', now(),
   '{"provider": "email", "providers": ["email"]}'::jsonb, '{}'::jsonb, now(), now(),
   '', '', '', '', '');

-- inv1 : caserne A, en attente, invitée par Jean Dupont — le cas nominal.
-- inv2 : caserne B, expirée depuis deux jours — « expirée » n'est pas « aucune ».
-- inv3 : caserne A, en attente, pour l'autre adresse — l'invitation du voisin.
-- inv4 : caserne B, déjà acceptée — ce qui ne doit plus apparaître.
insert into invitations (id, station_id, email, role, invited_by, expires_at, accepted_at) values
  ('51510000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001',
   'recrue51a@caserne-a.test', 'member', 'aaaaaaaa-0000-4000-8000-000000000100',
   now() + interval '10 days', null),
  ('51510000-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000001',
   'recrue51a@caserne-a.test', 'admin',  'bbbbbbbb-0000-4000-8000-000000000100',
   now() - interval '2 days', null),
  ('51510000-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001',
   'recrue51b@caserne-b.test', 'member', 'aaaaaaaa-0000-4000-8000-000000000100',
   now() + interval '5 days', null),
  ('51510000-0000-4000-8000-000000000004', 'bbbbbbbb-0000-4000-8000-000000000001',
   'recrue51b@caserne-b.test', 'member', 'bbbbbbbb-0000-4000-8000-000000000100',
   now() + interval '5 days', now());

\echo ''
\echo '=== Invitations en attente, vues par l''invité (0036) ==='

-- ===========================================================================
-- 1. Les droits d'exécution et le grant de colonne
-- ===========================================================================
\echo ''
\echo '--- 1. Qui peut appeler quoi, et ce que personne ne lit'
savepoint s1;

select tests_att.check(
  has_function_privilege('authenticated', 'public.my_pending_invitations()', 'execute'),
  'my_pending_invitations : ouverte à authenticated');

select tests_att.check(
  not has_function_privilege('anon', 'public.my_pending_invitations()', 'execute'),
  'my_pending_invitations : fermée à anon — pas de session, pas d''adresse');

select tests_att.check(
  not has_function_privilege('public', 'public.my_pending_invitations()', 'execute'),
  'my_pending_invitations : fermée au rôle public');

select tests_att.check(
  not has_function_privilege('authenticated',
    'public.accept_invitation_by_id(uuid, uuid, text)', 'execute')
  and not has_function_privilege('anon',
    'public.accept_invitation_by_id(uuid, uuid, text)', 'execute'),
  'accept_invitation_by_id : service_role uniquement, comme accept_invitation');

-- Le jeton reste hors du grant de colonne de 0008 : une fonction security definer
-- ne doit pas rouvrir par la fenêtre la porte que la migration a fermée.
select tests_att.check(
  not has_column_privilege('authenticated', 'invitations', 'token', 'select'),
  'le jeton reste hors de portée d''authenticated');

-- Et il n'est pas non plus dans la signature de la fonction de lecture : cinq
-- colonnes, celles du brief, pas une de plus.
select tests_att.check(
  pg_get_function_result(oid) =
    'TABLE(id uuid, station_name text, invited_by_name text, expires_at timestamp with time zone, status text)',
  'my_pending_invitations rend exactement les cinq champs du brief')
from pg_proc where proname = 'my_pending_invitations';

select tests_att.check(
  (select provolatile = 's' and prosecdef
     from pg_proc where proname = 'my_pending_invitations'),
  'my_pending_invitations : stable et security definer');

select tests_att.check(
  (select proconfig @> array['search_path=public, pg_temp']
     from pg_proc where proname = 'my_pending_invitations'),
  'search_path figé : pg_temp nommé, et en dernier');

select tests_att.check(
  (select pronargs = 0 from pg_proc where proname = 'my_pending_invitations'),
  'aucun paramètre : pas d''oracle d''énumération par adresse');

rollback to savepoint s1;

-- ===========================================================================
-- 2. Sous identité : chacun ne voit que ce qui le concerne
-- ===========================================================================
\echo ''
\echo '--- 2. Ce que voit l''invité, et ce qu''il ne voit pas'
savepoint s2;

set local role authenticated;
select tests_att.session('cccccccc-0000-4000-8000-000000000051', 'recrue51a@caserne-a.test');

do $$
declare
  v record;
begin
  perform tests_att.check(
    (select count(*) from my_pending_invitations()) = 2,
    'deux invitations pour cette adresse : une en attente, une expirée');

  -- Tri décroissant : ce qui est encore valable d'abord, l'expirée en dernier.
  select * into v from my_pending_invitations() limit 1;
  perform tests_att.check(v.id = '51510000-0000-4000-8000-000000000001',
    'l''invitation en attente vient en tête');
  perform tests_att.check(v.station_name = 'CIS Saint-Martin',
    'le nom de la caserne est rendu : on ne rejoint pas « une caserne »');
  perform tests_att.check(v.invited_by_name = 'Jean Dupont',
    'l''invitant est nommé, prénom et nom recomposés côté serveur');
  perform tests_att.check(v.status = 'pending',
    'le serveur tranche : en attente');

  -- L'expirée est **rendue**. Zéro ligne ferait dire « aucune invitation » à
  -- l'écran, c'est-à-dire le mensonge que ce ticket corrige.
  select * into v from my_pending_invitations() offset 1 limit 1;
  perform tests_att.check(v.id = '51510000-0000-4000-8000-000000000002',
    'l''expirée est rendue, et elle vient en dernier');
  perform tests_att.check(v.status = 'expired',
    'le serveur tranche : expirée — pas une soustraction de dates sur le téléphone');
  perform tests_att.check(v.station_name = 'CIS Val-de-Loue' and v.invited_by_name = 'Claire Martin',
    'l''expirée dit à qui demander un renvoi');

  -- Rien de l'invitation du voisin, ni de celle qui est déjà acceptée.
  perform tests_att.check(
    not exists (select 1 from my_pending_invitations()
                where id in ('51510000-0000-4000-8000-000000000003',
                             '51510000-0000-4000-8000-000000000004')),
    'ni l''invitation d''un autre, ni une invitation déjà acceptée');

  -- Et la table elle-même reste fermée : la fonction est la seule porte.
  perform tests_att.check(
    (select count(*) from invitations) = 0,
    'un select direct sur invitations rend zéro ligne à un compte sans caserne');
end $$;

select tests_att.refuse(
  $$select token from invitations where id = '51510000-0000-4000-8000-000000000001'$$,
  'le jeton reste refusé, même à qui l''invitation est adressée');

reset role;
select set_config('request.jwt.claims', '', true);
rollback to savepoint s2;

-- ===========================================================================
-- 3. Le compte A ne voit rien du compte B, même en connaissant son adresse
-- ===========================================================================
\echo ''
\echo '--- 3. Étanchéité entre deux comptes'
savepoint s3;

set local role authenticated;
select tests_att.session('cccccccc-0000-4000-8000-000000000052', 'recrue51b@caserne-b.test');

do $$
begin
  perform tests_att.check(
    (select count(*) from my_pending_invitations()) = 1,
    'le second compte ne voit que la sienne');
  perform tests_att.check(
    (select id from my_pending_invitations()) = '51510000-0000-4000-8000-000000000003',
    'et c''est bien la sienne');
  -- La fonction n'a pas de paramètre : connaître l'adresse du voisin ne donne
  -- aucune prise. Le cas est écrit pour qu'un paramètre ajouté plus tard casse ici.
  perform tests_att.check(
    not exists (select 1 from my_pending_invitations()
                where station_name = 'CIS Val-de-Loue'),
    'connaître l''adresse d''un autre ne rend pas ses invitations');
end $$;

reset role;
select set_config('request.jwt.claims', '', true);

-- Un membre installé de la caserne A n'obtient rien non plus : la fonction
-- répond à l'adresse de la session, pas au rôle.
set local role authenticated;
select tests_att.session('aaaaaaaa-0000-4000-8000-000000000100', 'admin@caserne-a.test');

select tests_att.check(
  (select count(*) from my_pending_invitations()) = 0,
  'l''administrateur qui a envoyé les invitations ne les relit pas par cette porte');

reset role;
select set_config('request.jwt.claims', '', true);

-- Sans session, rien du tout : zéro ligne, jamais une exception. « Pas
-- d'invitation » et « pas le droit » doivent être indiscernables.
select tests_att.check(
  (select count(*) from my_pending_invitations()) = 0,
  'sans adresse dans le jeton : zéro ligne, pas une exception');

set local role anon;
select tests_att.refuse(
  $$select * from my_pending_invitations()$$,
  'le rôle anon ne peut pas appeler la fonction');
reset role;

rollback to savepoint s3;

-- ===========================================================================
-- 4. Les détails de la réponse
-- ===========================================================================
\echo ''
\echo '--- 4. Casse de l''adresse, nom absent, plafond de dix lignes'
savepoint s4;

-- L'adresse se compare en minuscules, comme l'index partiel
-- `invitations_pending_uniq` : c'est la même notion d'« adresse déjà invitée ».
set local role authenticated;
select tests_att.session('cccccccc-0000-4000-8000-000000000051', 'Recrue51A@Caserne-A.TEST');
select tests_att.check(
  (select count(*) from my_pending_invitations()) = 2,
  'la comparaison d''adresse ignore la casse, des deux côtés');
reset role;
select set_config('request.jwt.claims', '', true);

-- Un JWT qui dit explicitement « adresse non vérifiée » n'ouvre pas de caserne.
set local role authenticated;
select tests_att.session('cccccccc-0000-4000-8000-000000000051', 'recrue51a@caserne-a.test',
                         '{"email_verified": false}'::jsonb);
select tests_att.check(
  (select count(*) from my_pending_invitations()) = 0,
  'une adresse déclarée non vérifiée ne rend rien');
reset role;
select set_config('request.jwt.claims', '', true);

set local role authenticated;
select tests_att.session('cccccccc-0000-4000-8000-000000000051', 'recrue51a@caserne-a.test',
                         '{"user_metadata": {"email_verified": true}}'::jsonb);
select tests_att.check(
  (select count(*) from my_pending_invitations()) = 2,
  'la claim posée par GoTrue à vrai ne change rien');
reset role;
select set_config('request.jwt.claims', '', true);

-- Nom absent : `null`, jamais un repli sur l'adresse de l'invitant. Les deux
-- colonnes sont `not null default ''` : « sans nom » se dit avec des chaînes
-- vides, et c'est bien `null` que la fonction doit rendre.
update profiles set first_name = '', last_name = ''
 where id = 'aaaaaaaa-0000-4000-8000-000000000100';

set local role authenticated;
select tests_att.session('cccccccc-0000-4000-8000-000000000051', 'recrue51a@caserne-a.test');
select tests_att.check(
  (select invited_by_name is null from my_pending_invitations()
    where id = '51510000-0000-4000-8000-000000000001'),
  'un invitant sans nom rend null — l''écran omet la ligne, il n''affiche pas une adresse');
reset role;
select set_config('request.jwt.claims', '', true);

rollback to savepoint s4;

savepoint s4b;

-- Le plafond : une réponse dont la taille dépend de l'appelant est une réponse
-- à borner. Douze casernes, douze invitations, dix lignes rendues — les dix dont
-- l'échéance est la plus lointaine, l'ordre étant décroissant.
insert into stations (id, name, slug, timezone)
select ('51510000-0000-4000-9000-' || lpad(n::text, 12, '0'))::uuid,
       'Caserne d''essai ' || n, 'essai-51-' || n, 'Europe/Paris'
from generate_series(1, 12) n;

insert into invitations (station_id, email, role, invited_by, expires_at)
select ('51510000-0000-4000-9000-' || lpad(n::text, 12, '0'))::uuid,
       'recrue51a@caserne-a.test', 'member', 'aaaaaaaa-0000-4000-8000-000000000100',
       now() + (n || ' days')::interval
from generate_series(1, 12) n;

set local role authenticated;
select tests_att.session('cccccccc-0000-4000-8000-000000000051', 'recrue51a@caserne-a.test');

do $$
begin
  perform tests_att.check(
    (select count(*) from my_pending_invitations()) = 10,
    'au plus dix lignes, quel que soit le nombre d''invitations');
  perform tests_att.check(
    (select station_name from my_pending_invitations() limit 1) = 'Caserne d''essai 12',
    'tri par échéance décroissante : l''échéance la plus lointaine en tête');
  perform tests_att.check(
    (select bool_and(e1 >= e2) from (
       select expires_at e1, lead(expires_at) over () e2 from my_pending_invitations()
     ) t where e2 is not null),
    'l''ordre est monotone : les expirées ne remontent jamais');
end $$;

reset role;
select set_config('request.jwt.claims', '', true);
rollback to savepoint s4b;

-- ===========================================================================
-- 5. L'acceptation par identifiant
-- ===========================================================================
\echo ''
\echo '--- 5. accept_invitation_by_id : le même parcours, sans jeton'
savepoint s5;

do $$
declare r jsonb;
begin
  r := accept_invitation_by_id('51510000-0000-4000-8000-000000000001',
                               'cccccccc-0000-4000-8000-000000000051',
                               'recrue51a@caserne-a.test');
  perform tests_att.check(r->>'ok' = 'true', 'l''invité entre dans la caserne par identifiant');
  perform tests_att.check(r#>>'{station,name}' = 'CIS Saint-Martin',
    'la réponse nomme la caserne, comme par le chemin du jeton');
  perform tests_att.check(
    (select status = 'active' from memberships
      where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
        and user_id = 'cccccccc-0000-4000-8000-000000000051'),
    'l''appartenance est créée, active');
  perform tests_att.check(
    (select accepted_at is not null from invitations
      where id = '51510000-0000-4000-8000-000000000001'),
    'l''invitation est marquée acceptée dans la même transaction');

  -- Le jeton n'apparaît nulle part dans la réponse, à aucune profondeur.
  perform tests_att.check(r::text not like '%token%',
    'aucun jeton dans la réponse de l''acceptation par identifiant');

  -- Et l'invitation, une fois acceptée, disparaît de la liste.
  perform set_config('request.jwt.claims',
    '{"sub":"cccccccc-0000-4000-8000-000000000051","role":"authenticated","email":"recrue51a@caserne-a.test"}',
    true);
  perform tests_att.check(
    not exists (select 1 from my_pending_invitations()
                where id = '51510000-0000-4000-8000-000000000001'),
    'une invitation acceptée sort de la liste');
  perform set_config('request.jwt.claims', '', true);
end $$;

rollback to savepoint s5;

savepoint s6;

do $$
declare
  r_autre    jsonb;
  r_inconnue jsonb;
  r_jeton    jsonb;
  v_token    text;
begin
  -- L'identifiant de l'invitation du voisin : refusé, et rien n'est appris.
  r_autre := accept_invitation_by_id('51510000-0000-4000-8000-000000000003',
                                     'cccccccc-0000-4000-8000-000000000051',
                                     'recrue51a@caserne-a.test');
  perform tests_att.check(r_autre->>'code' = 'email_mismatch',
    'l''identifiant d''un autre est refusé sur l''adresse, comme un jeton transféré');
  perform tests_att.check(
    not (r_autre ? 'station') and not (r_autre ? 'invited_email_masked')
    and not (r_autre ? 'inviter'),
    'le refus ne nomme ni la caserne, ni l''adresse invitée');

  -- Un identifiant qui n'existe pas rend **exactement la même chose** : sinon la
  -- fonction devient un oracle d'existence.
  r_inconnue := accept_invitation_by_id('51510000-0000-4000-8000-0000000000ff',
                                        'cccccccc-0000-4000-8000-000000000051',
                                        'recrue51a@caserne-a.test');
  perform tests_att.check(r_inconnue = r_autre,
    'identifiant inconnu et identifiant d''un autre sont indiscernables');

  perform tests_att.check(
    accept_invitation_by_id(null, 'cccccccc-0000-4000-8000-000000000051',
                            'recrue51a@caserne-a.test') = r_autre,
    'un identifiant absent ne se distingue pas davantage');

  -- Expirée : la même fin de parcours que par le jeton, au mot près.
  select token into v_token from invitations where id = '51510000-0000-4000-8000-000000000002';
  r_jeton := accept_invitation(v_token, 'cccccccc-0000-4000-8000-000000000051',
                               'recrue51a@caserne-a.test');
  perform tests_att.check(
    accept_invitation_by_id('51510000-0000-4000-8000-000000000002',
                            'cccccccc-0000-4000-8000-000000000051',
                            'recrue51a@caserne-a.test') = r_jeton,
    'invitation expirée : identifiant et jeton rendent la même réponse');
  perform tests_att.check(r_jeton->>'code' = 'invitation_expired',
    'et c''est bien « invitation expirée », une des six fins de parcours du 006');

  -- Déjà acceptée : idem, sans avoir eu besoin du jeton.
  select token into v_token from invitations where id = '51510000-0000-4000-8000-000000000004';
  perform tests_att.check(
    accept_invitation_by_id('51510000-0000-4000-8000-000000000004',
                            'cccccccc-0000-4000-8000-000000000052',
                            'recrue51b@caserne-b.test')->>'code'
      = accept_invitation(v_token, 'cccccccc-0000-4000-8000-000000000052',
                          'recrue51b@caserne-b.test')->>'code',
    'invitation déjà acceptée : même code des deux côtés');
end $$;

rollback to savepoint s6;

\echo ''
\echo '=== Invitations en attente : tous les cas passent ==='

rollback;
