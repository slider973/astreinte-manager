-- La trace de l'envoi sur l'invitation (migration 0035, ticket 048).
-- Lancement : scripts/test_rls.sh (le script joue tous les supabase/tests/*.sql).
--
-- Ce que ces cas protègent :
--
--   1. le grant de colonne — la trace se lit, `token` toujours pas. Une colonne
--      ajoutée n'hérite pas de l'énumération de 0008 : l'oubli se voit ici ;
--   2. l'étanchéité entre casernes — la trace suit la ligne, et la ligne ne sort
--      pas de sa caserne ni de son cercle d'administrateurs ;
--   3. la sémantique des deux colonnes, et surtout la différence entre « on ne
--      sait pas » (les deux nulles) et « personne n'a été prévenu » (un motif sans
--      date). Confondre les deux serait le mensonge que ce ticket corrige.
--
-- Ce que ces cas ne couvrent pas : le rattrapage du § 3 de la migration, qui est
-- une instruction unique jouée au déploiement. Sur une base remise à zéro,
-- `invitations` est vide quand elle passe : il n'y a rien à observer après coup.
--
-- Même méthode que rls_test.sql : pas de pgTAP, une exception fait échouer psql
-- (`ON_ERROR_STOP`). Tout tourne dans une transaction annulée à la fin.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_trace;

create function tests_trace.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

-- Une lecture qui doit être refusée par un grant de colonne : l'absence du droit
-- lève `insufficient_privilege`. Les politiques RLS, elles, ne lèvent rien — elles
-- filtrent ; c'est `check(... count = 0 ...)` qui les couvre plus bas.
create function tests_trace.refuse_lecture(p_sql text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — la lecture a été autorisée', p_label;
exception
  when insufficient_privilege then
    raise notice '  ok   %', p_label;
end $$;

-- Les assertions du § 4 sont jouées sous l'identité d'un administrateur : il doit
-- pouvoir appeler l'outillage, sans quoi c'est le test qui échoue, pas la politique.
grant usage on schema tests_trace to authenticated, anon;

\echo ''
\echo '=== La trace de l''envoi sur l''invitation (0035) ==='

-- ===========================================================================
-- 1. Le grant de colonne
-- ===========================================================================
\echo ''
\echo '--- 1. Grants : la trace oui, le jeton non'
savepoint s1;

select tests_trace.check(
  has_column_privilege('authenticated', 'invitations', 'email_sent_at', 'select')
  and has_column_privilege('authenticated', 'invitations', 'email_error', 'select'),
  'un administrateur lit la trace d''envoi de ses invitations');

select tests_trace.check(
  not has_column_privilege('authenticated', 'invitations', 'token', 'select'),
  'le jeton reste hors du grant, colonnes ajoutées ou pas');

select tests_trace.check(
  not has_column_privilege('anon', 'invitations', 'email_sent_at', 'select')
  and not has_column_privilege('anon', 'invitations', 'email_error', 'select'),
  'le rôle anon ne lit rien de la trace');

rollback to savepoint s1;

-- ===========================================================================
-- 2. À la création, on ne sait pas encore
-- ===========================================================================
-- `create_invitation` ne pose pas la trace : elle s'écrit après, au retour de
-- `sendMail`, depuis `invite-member`. Une invitation toute neuve vaut donc « on
-- ne sait pas », et surtout pas « pas envoyé ».
\echo ''
\echo '--- 2. create_invitation laisse la trace vide'
savepoint s2;

do $$
declare r jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_trace.check(r->>'ok' = 'true', 'invitation créée');
  perform tests_trace.check(
    (select email_sent_at is null and email_error is null
       from invitations where id = (r#>>'{invitation,id}')::uuid),
    'une invitation qui vient de naître ne prétend ni être partie ni avoir échoué');

  -- Et un renvoi ne réinvente pas la trace non plus : il prolonge la ligne, la
  -- trace attend le résultat de l'envoi.
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_trace.check(r->>'resent' = 'true', 'le renvoi réutilise la ligne');
  perform tests_trace.check(
    (select email_sent_at is null and email_error is null
       from invitations where id = (r#>>'{invitation,id}')::uuid),
    'un renvoi ne fabrique pas de trace sans envoi');
end $$;

rollback to savepoint s2;

-- ===========================================================================
-- 3. Les quatre états, relus par l'administrateur de la caserne
-- ===========================================================================
-- Ce que `invite-member` écrit après `sendMail` : un succès pose la date et efface
-- le motif, un échec pose le motif sans toucher à la date.
\echo ''
\echo '--- 3. Ce que les deux colonnes disent'
savepoint s3;

do $$
declare
  r      jsonb;
  v_id   uuid;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  v_id := (r#>>'{invitation,id}')::uuid;

  -- a) L'échec : personne n'a été prévenu, et on sait pourquoi.
  update invitations
     set email_error = 'aucun fournisseur de courriel configuré'
   where id = v_id;
  perform tests_trace.check(
    (select email_sent_at is null and email_error is not null from invitations where id = v_id),
    'un échec se distingue d''une invitation muette : il porte un motif');

  -- b) Le renvoi qui passe : la date arrive, le motif s'efface.
  update invitations
     set email_sent_at = now(), email_error = null
   where id = v_id;
  perform tests_trace.check(
    (select email_sent_at is not null and email_error is null from invitations where id = v_id),
    'un envoi réussi efface le motif d''échec précédent');

  -- c) Un second renvoi qui échoue : le motif revient, la date du dernier envoi
  --    réussi reste. Les deux faits tiennent ensemble et ne se contredisent pas.
  update invitations
     set email_error = 'resend 422 domaine non vérifié'
   where id = v_id;
  perform tests_trace.check(
    (select email_sent_at is not null and email_error is not null from invitations where id = v_id),
    'un échec de renvoi n''efface pas la date du courriel déjà parti');
end $$;

rollback to savepoint s3;

-- ===========================================================================
-- 4. Étanchéité : la trace ne sort pas de sa caserne
-- ===========================================================================
\echo ''
\echo '--- 4. Qui lit la trace'
savepoint s4;

-- Deux invitations, une par caserne, toutes deux en échec d'envoi.
do $$
declare r jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  update invitations set email_error = 'aucun fournisseur de courriel configuré'
   where id = (r#>>'{invitation,id}')::uuid;

  r := create_invitation('bbbbbbbb-0000-4000-8000-000000000001', 'recrue@caserne-b.test',
                         'member', 'bbbbbbbb-0000-4000-8000-000000000100');
  update invitations set email_error = 'aucun fournisseur de courriel configuré'
   where id = (r#>>'{invitation,id}')::uuid;
end $$;

-- a) L'administrateur de la caserne A : sa ligne, et elle seule.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

select tests_trace.check(
  (select count(*) = 1 from invitations
    where email = 'recrue@caserne-a.test' and email_error is not null),
  'l''admin de la caserne A voit que le courriel de son invitation n''est pas parti');

select tests_trace.check(
  (select count(*) = 0 from invitations where email = 'recrue@caserne-b.test'),
  'l''admin de la caserne A ne voit rien de l''invitation de la caserne B');

select tests_trace.refuse_lecture(
  'select token from invitations where email = ''recrue@caserne-a.test''',
  'même administrateur de la caserne, le jeton reste illisible');

rollback to savepoint s4;

savepoint s5;

do $$
declare r jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  update invitations set email_error = 'aucun fournisseur de courriel configuré'
   where id = (r#>>'{invitation,id}')::uuid;
end $$;

-- b) L'administrateur de la caserne B : rien du tout, trace comprise.
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-4000-8000-000000000100","role":"authenticated"}';

select tests_trace.check(
  (select count(*) = 0 from invitations where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
  'l''admin de la caserne B ne lit aucune invitation de la caserne A');

rollback to savepoint s5;

savepoint s6;

do $$
declare r jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  update invitations set email_error = 'aucun fournisseur de courriel configuré'
   where id = (r#>>'{invitation,id}')::uuid;
end $$;

-- c) Un membre simple de la caserne A : l'invitation n'est pas son affaire, la
--    trace non plus.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

select tests_trace.check(
  (select count(*) = 0 from invitations),
  'un membre simple ne lit aucune invitation, ni sa trace d''envoi');

rollback to savepoint s6;

rollback;
