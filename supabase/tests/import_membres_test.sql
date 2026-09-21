-- Le nom porté par l'invitation (migration 0034, ticket 047).
-- Lancement : scripts/test_rls.sh (le script joue tous les supabase/tests/*.sql).
--
-- Ce que ces cas protègent, c'est la décision du § 7 du brief : le nom saisi par
-- l'administrateur à l'import est une **proposition**. Il amorce un profil vide, il
-- n'écrase jamais ce qu'une personne a écrit sur elle-même, et il n'est pas
-- effacé par un renvoi qui ne porte pas de nom.
--
-- Même méthode que invitations_test.sql : pas de pgTAP, une exception fait échouer
-- psql (`ON_ERROR_STOP`). Tout tourne dans une transaction annulée à la fin.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_imp;

create function tests_imp.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

-- Deux comptes hors seed : l'invité au profil vierge, et celui qui a déjà un nom.
insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current
) values
  ('00000000-0000-0000-0000-000000000000', 'dddddddd-0000-4000-8000-000000000001',
   'authenticated', 'authenticated', 'vierge@caserne-a.test', now(),
   '{"provider": "email", "providers": ["email"]}'::jsonb, '{}'::jsonb, now(), now(),
   '', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'dddddddd-0000-4000-8000-000000000002',
   'authenticated', 'authenticated', 'nomme@caserne-a.test', now(),
   '{"provider": "email", "providers": ["email"]}'::jsonb, '{}'::jsonb, now(), now(),
   '', '', '', '', '');

-- `handle_new_user` crée les profils avec des chaînes vides : c'est exactement
-- l'état que l'amorce doit reconnaître comme « place libre ».
update profiles set first_name = '', last_name = ''
 where id = 'dddddddd-0000-4000-8000-000000000001';
update profiles set first_name = 'Camille', last_name = 'Roux'
 where id = 'dddddddd-0000-4000-8000-000000000002';

\echo ''
\echo '=== Le nom porté par l''invitation (0034) ==='

-- ===========================================================================
-- 1. create_invitation écrit les noms, et les normalise
-- ===========================================================================
\echo ''
\echo '--- 1. create_invitation : les noms du fichier'
savepoint s1;

do $$
declare r jsonb; v_inv invitations%rowtype;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'vierge@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100',
                         '  Marie   ', E'Le\tFèbvre');
  perform tests_imp.check(r->>'ok' = 'true', 'invitation avec nom acceptée');

  select * into v_inv from invitations where id = (r#>>'{invitation,id}')::uuid;
  perform tests_imp.check(v_inv.first_name = 'Marie',
    'le prénom est débarrassé de ses espaces');
  perform tests_imp.check(v_inv.last_name = 'Le Fèbvre',
    'le nom garde ses accents et voit ses blancs réduits');
  perform tests_imp.check(r#>>'{invitation,last_name}' = 'Le Fèbvre',
    'les noms reviennent dans la réponse, pour la trace de l''Edge Function');

  -- Un nom vide n'en est pas un : la colonne reste nulle plutôt que de porter ''.
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'sansnom@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100', '   ', null);
  perform tests_imp.check(
    (select first_name is null and last_name is null
       from invitations where email = 'sansnom@caserne-a.test'),
    'une colonne vide du fichier ne pose pas une chaîne vide');

  -- Et une ligne sans nom passe quand même : l'adresse fait entrer, pas le nom.
  perform tests_imp.check(r->>'ok' = 'true',
    'une ligne sans nom est invitée comme les autres');

  -- Le journal ne recopie pas les noms : audit_log garde trois ans.
  perform tests_imp.check(
    (select data ? 'named' and not (data ? 'first_name')
       from audit_log
      where action = 'invitation.created' and data->>'email' = 'vierge@caserne-a.test'),
    'le journal note qu''un nom a été donné, sans le recopier');
end $$;

rollback to savepoint s1;

-- ===========================================================================
-- 2. Le renvoi corrige un nom, il ne l'efface pas
-- ===========================================================================
\echo ''
\echo '--- 2. create_invitation : le renvoi et les noms'
savepoint s2;

do $$
declare r jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'vierge@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100', 'Marie', 'Lefebvre');
  perform tests_imp.check(r->>'ok' = 'true', 'première invitation posée');

  -- Un second import avec un fichier corrigé : le nom suit.
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'vierge@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100', 'Marie', 'Lefèbvre');
  perform tests_imp.check(r->>'resent' = 'true', 'le renvoi réutilise la ligne');
  perform tests_imp.check(
    (select last_name = 'Lefèbvre' from invitations where email = 'vierge@caserne-a.test'),
    'un second import corrige le nom');

  -- Le renvoi depuis l'écran « Membres » ne passe pas de noms : il ne doit pas
  -- faire disparaître ceux qu'un import avait posés.
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'vierge@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_imp.check(
    (select first_name = 'Marie' and last_name = 'Lefèbvre'
       from invitations where email = 'vierge@caserne-a.test'),
    'un renvoi sans nom conserve celui de l''import');
end $$;

rollback to savepoint s2;

-- ===========================================================================
-- 3. accept_invitation amorce un profil vide, jamais un profil rempli
-- ===========================================================================
\echo ''
\echo '--- 3. accept_invitation : à qui appartient le nom'
savepoint s3;

do $$
declare r jsonb; v_token text;
begin
  -- a) Profil vierge : le nom de l'administrateur s'installe.
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'vierge@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100', 'Marie', 'Lefèbvre');
  v_token := r->>'token';
  r := accept_invitation(v_token, 'dddddddd-0000-4000-8000-000000000001', 'vierge@caserne-a.test');
  perform tests_imp.check(r->>'ok' = 'true', 'invitation acceptée');
  perform tests_imp.check(
    (select first_name = 'Marie' and last_name = 'Lefèbvre'
       from profiles where id = 'dddddddd-0000-4000-8000-000000000001'),
    'un profil vide reçoit le nom saisi à l''import');

  -- b) Profil déjà nommé : rien ne bouge. C'est la décision du ticket — la
  --    personne dispose, l'administrateur propose.
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'nomme@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100', 'Kamil', 'Rous');
  v_token := r->>'token';
  r := accept_invitation(v_token, 'dddddddd-0000-4000-8000-000000000002', 'nomme@caserne-a.test');
  perform tests_imp.check(r->>'ok' = 'true', 'invitation acceptée par un compte déjà nommé');
  perform tests_imp.check(
    (select first_name = 'Camille' and last_name = 'Roux'
       from profiles where id = 'dddddddd-0000-4000-8000-000000000002'),
    'un profil déjà rempli n''est pas réécrit par l''administrateur d''une caserne');

  -- c) L'amorce est champ par champ : un prénom déjà là reste, un nom absent
  --    se remplit.
  update profiles set first_name = 'Camille', last_name = ''
   where id = 'dddddddd-0000-4000-8000-000000000002';
  delete from memberships where user_id = 'dddddddd-0000-4000-8000-000000000002';
  delete from invitations where email = 'nomme@caserne-a.test';
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'nomme@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100', 'Kamil', 'Roux');
  v_token := r->>'token';
  perform accept_invitation(v_token, 'dddddddd-0000-4000-8000-000000000002', 'nomme@caserne-a.test');
  perform tests_imp.check(
    (select first_name = 'Camille' and last_name = 'Roux'
       from profiles where id = 'dddddddd-0000-4000-8000-000000000002'),
    'le prénom saisi par la personne tient, le nom manquant est amorcé');

  -- d) `memberships.display_name` n'est pas touché : le surnom de caserne se
  --    décide (ticket 009), il ne se déduit pas d'un tableur.
  perform tests_imp.check(
    (select display_name is null from memberships
      where user_id = 'dddddddd-0000-4000-8000-000000000002'
        and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
    'l''import ne pose pas de nom affiché dans la caserne');
end $$;

rollback to savepoint s3;

-- ===========================================================================
-- 4. Ce que le client a le droit de lire
-- ===========================================================================
\echo ''
\echo '--- 4. Grants : les noms oui, le jeton non'
savepoint s4;

select tests_imp.check(
  has_column_privilege('authenticated', 'invitations', 'first_name', 'select')
  and has_column_privilege('authenticated', 'invitations', 'last_name', 'select'),
  'un administrateur lit les noms de ses invitations en attente');

select tests_imp.check(
  not has_column_privilege('authenticated', 'invitations', 'token', 'select'),
  'le jeton reste hors du grant, colonnes ajoutées ou pas');

select tests_imp.check(
  not has_function_privilege('authenticated',
    'create_invitation(uuid, text, membership_role, uuid, text, text)', 'execute'),
  'create_invitation reste fermée au rôle authenticated');

rollback to savepoint s4;

rollback;
