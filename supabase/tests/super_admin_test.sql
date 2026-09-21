-- Tests de l'interface super-admin (migration 0025, ticket 031).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
-- 1. Ce que le super-admin **a perdu** : plus aucune politique RLS ne le nomme,
--    sauf celle de `super_admins`. C'est la propriété centrale du ticket, et
--    elle se lit sur `pg_policies` — pas à l'œil sur 0007.
-- 2. Ce qu'il ne lit toujours pas, table par table : rien d'une caserne dont il
--    n'est pas membre, ni les plannings, ni les disponibilités, ni les membres.
-- 3. `super_admin_stations` : les faits d'exploitation, et rien qui nomme
--    quelqu'un. Zéro ligne pour un admin ordinaire et pour un membre.
-- 4. Créer une caserne : le slug dérivé, l'essai posé par le trigger du 0023,
--    la trace d'audit, et le refus pour qui n'est pas super-admin.
-- 5. Nommer le premier administrateur : **le chemin du ticket 006**,
--    `create_invitation`, avec la branche super-admin — et sans que cela ouvre
--    quoi que ce soit à un admin de caserne voisine.
-- 6. Suspendre et réactiver à la main : le statut change, `station_writable()`
--    suit, **rien n'est supprimé**, la réactivation ne se fait pas re-suspendre
--    par la tâche de 03:30, et la raison est obligatoire.
-- 7. Le point de sécurité central : un super-admin **ne lit pas** les plannings
--    sans action de support explicite et tracée, et la trace atterrit dans
--    l'audit de la caserne, donc sous les yeux de ses administrateurs.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : le seed (caserne A = aaaaaaaa-…-001, admin …100, membres …101 à
-- …108 ; caserne B = bbbbbbbb-…-001), plus un compte **hors seed** qui joue
-- l'éditeur : membre d'aucune caserne, c'est le cas nominal.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_sa;

create function tests_sa.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

-- L'écriture doit être refusée : soit erreur RLS, soit 0 ligne touchée (une
-- politique USING qui ne matche pas filtre silencieusement).
create function tests_sa.denied(p_sql text, p_label text) returns void
language plpgsql as $$
declare n integer;
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
end $$;

-- L'écriture doit passer et toucher au moins une ligne.
create function tests_sa.allowed(p_sql text, p_label text) returns void
language plpgsql as $$
declare n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n < 1 then
    raise exception 'ECHEC : % — 0 ligne écrite alors que l''écriture devait passer', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

grant usage on schema tests_sa to authenticated, anon;
grant execute on all functions in schema tests_sa to authenticated, anon;

\set caserne_a '''aaaaaaaa-0000-4000-8000-000000000001'''
\set caserne_b '''bbbbbbbb-0000-4000-8000-000000000001'''
\set admin_a   '''aaaaaaaa-0000-4000-8000-000000000100'''
\set membre_a  '''aaaaaaaa-0000-4000-8000-000000000101'''
\set editeur   '''eeeeeeee-0000-4000-8000-0000000000e1'''

-- ---------------------------------------------------------------------------
-- L'éditeur : un compte sans aucune appartenance. C'est le cas nominal — la
-- personne qui édite le produit n'est membre d'aucune caserne — et c'est aussi
-- le cas le plus sévère pour les politiques.
-- ---------------------------------------------------------------------------
insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current
) values (
  '00000000-0000-0000-0000-000000000000',
  :editeur::uuid,
  'authenticated', 'authenticated', 'editeur@astreinte.test', now(),
  '{"provider": "email", "providers": ["email"]}'::jsonb, '{}'::jsonb, now(), now(),
  '', '', '', '', ''
);
insert into super_admins (user_id) values (:editeur::uuid);

-- Un planning publié sur la caserne A : sans lui, « le super-admin ne lit pas
-- les plannings » serait vrai pour la seule raison qu'il n'y en a aucun.
insert into periods (id, station_id, year, month, status, deadline_at)
values ('11111111-0000-4000-8000-000000000031', :caserne_a::uuid, 2099, 3, 'locked',
        '2099-02-15 23:59:59+01');
insert into schedules (id, station_id, period_id, status, published_at, created_by)
values ('22222222-0000-4000-8000-000000000031', :caserne_a::uuid,
        '11111111-0000-4000-8000-000000000031', 'published', now(), :admin_a::uuid);
insert into shifts (id, station_id, schedule_id, date, slot)
values ('33333333-0000-4000-8000-000000000031', :caserne_a::uuid,
        '22222222-0000-4000-8000-000000000031', '2099-03-04', 'night');
insert into assignments (station_id, shift_id, user_id, status, created_by)
values (:caserne_a::uuid, '33333333-0000-4000-8000-000000000031', :membre_a::uuid,
        'accepted', :admin_a::uuid);

\echo ''
\echo '=== Interface super-admin (0025) ==='

-- ===========================================================================
-- 1. Plus aucune politique RLS ne nomme le super-admin
-- ===========================================================================
\echo ''
\echo '--- 1. Les politiques : is_super_admin() ne subsiste que sur super_admins'
savepoint s1;

select tests_sa.check(
  (select count(*) = 0
     from pg_policies
    where schemaname = 'public'
      and tablename <> 'super_admins'
      and coalesce(qual, '') || coalesce(with_check, '') like '%is_super_admin%'),
  'aucune politique hors super_admins ne cite is_super_admin()');

select tests_sa.check(
  (select count(*) = 1
     from pg_policies
    where schemaname = 'public' and tablename = 'super_admins'),
  'super_admins garde sa politique de lecture, et elle seule');

-- Les trois politiques de `stations` sont revenues au membre et à l'admin.
select tests_sa.check(
  (select count(*) = 0 from pg_policies
    where schemaname = 'public' and tablename = 'stations' and cmd = 'INSERT'),
  'stations : plus de politique d''insertion — la création passe par la fonction tracée');

rollback to savepoint s1;

-- ===========================================================================
-- 2. Ce que l'éditeur ne lit pas, et ne doit jamais lire
-- ===========================================================================
\echo ''
\echo '--- 2. Les tables restent fermées à l''éditeur'
savepoint s2;

set local role authenticated;
set local request.jwt.claims to '{"sub": "eeeeeeee-0000-4000-8000-0000000000e1", "role": "authenticated"}';

select tests_sa.check(
  (select count(*) = 0 from stations),
  'stations : l''éditeur ne lit plus la table (il lisait les deux casernes, settings compris)');

select tests_sa.check(
  (select count(*) = 0 from periods)
  and (select count(*) = 0 from schedules)
  and (select count(*) = 0 from shifts)
  and (select count(*) = 0 from assignments),
  'aucune donnée de planning n''est lisible — pourtant il y en a une, posée plus haut');

select tests_sa.check(
  (select count(*) = 0 from availabilities)
  and (select count(*) = 0 from availability_preferences),
  'aucune disponibilité n''est lisible');

select tests_sa.check(
  (select count(*) = 0 from memberships)
  and (select count(*) = 0 from invitations)
  and (select count(*) = 0 from subscriptions)
  and (select count(*) = 0 from audit_log),
  'ni membres, ni invitations, ni abonnements, ni journal d''audit');

-- Et l'écriture, qui passait : `update stations` acceptait nom, slug, fuseau et
-- réglages métier d'une caserne dont l'éditeur n'est pas membre, sans trace.
select tests_sa.denied(
  $q$ update stations set name = 'PIRATÉ' where id = 'aaaaaaaa-0000-4000-8000-000000000001' $q$,
  'l''éditeur ne renomme plus une caserne dont il n''est pas membre');

select tests_sa.denied(
  $q$ update stations set settings = jsonb_set(settings, '{required_day}', '9')
       where id = 'aaaaaaaa-0000-4000-8000-000000000001' $q$,
  'l''éditeur ne règle plus l''effectif requis d''une caserne');

select tests_sa.denied(
  $q$ insert into stations (name, slug) values ('Directe', 'directe-031') $q$,
  'l''éditeur ne crée plus une caserne par insertion directe');

rollback to savepoint s2;

-- ===========================================================================
-- 3. super_admin_stations — la liste, et ses limites
-- ===========================================================================
\echo ''
\echo '--- 3. super_admin_stations : les faits, et rien qui nomme quelqu''un'
savepoint s3;

set local role authenticated;
set local request.jwt.claims to '{"sub": "eeeeeeee-0000-4000-8000-0000000000e1", "role": "authenticated"}';

select tests_sa.check(
  (select count(*) = 2 from super_admin_stations()),
  'l''éditeur voit les deux casernes');

select tests_sa.check(
  (select active_members = 9 and active_admins = 1 and status = 'trialing' and writable
     from super_admin_stations() where station_id = :caserne_a::uuid),
  'effectifs et abonnement de la caserne A');

select tests_sa.check(
  (select last_published_year = 2099 and last_published_month = 3
      and last_published_at is not null
     from super_admin_stations() where station_id = :caserne_a::uuid),
  'le dernier planning publié est celui de mars 2099');

select tests_sa.check(
  (select last_published_at is null and last_published_year is null
     from super_admin_stations() where station_id = :caserne_b::uuid),
  'une caserne sans planning publié rend null, pas une erreur');

rollback to savepoint s3;

\echo '--- 3b. ni un admin de caserne ni un membre n''en tirent quoi que ce soit'
savepoint s3b;

set local role authenticated;
set local request.jwt.claims to '{"sub": "aaaaaaaa-0000-4000-8000-000000000100", "role": "authenticated"}';
select tests_sa.check(
  (select count(*) = 0 from super_admin_stations()),
  'un administrateur de caserne n''obtient aucune ligne');

rollback to savepoint s3b;
savepoint s3c;

set local role authenticated;
set local request.jwt.claims to '{"sub": "aaaaaaaa-0000-4000-8000-000000000101", "role": "authenticated"}';
select tests_sa.check(
  (select count(*) = 0 from super_admin_stations()),
  'un simple membre n''obtient aucune ligne');

-- Et les trois autres fonctions lui répondent « forbidden », pas un résultat.
do $$
declare r jsonb;
begin
  r := super_admin_create_station('Tentative', 'Europe/Paris');
  perform tests_sa.check(r->>'code' = 'forbidden',
    'un membre ne crée pas de caserne');
  r := super_admin_set_station_suspended('aaaaaaaa-0000-4000-8000-000000000001', true,
                                         'tentative depuis un compte membre');
  perform tests_sa.check(r->>'code' = 'forbidden',
    'un membre ne suspend pas sa caserne');
  r := super_admin_support_schedules('aaaaaaaa-0000-4000-8000-000000000001',
                                     'tentative depuis un compte membre');
  perform tests_sa.check(r->>'code' = 'forbidden',
    'un membre n''ouvre pas la consultation de support');
end $$;

rollback to savepoint s3c;

-- ===========================================================================
-- 4. Créer une caserne
-- ===========================================================================
\echo ''
\echo '--- 4. super_admin_create_station'
savepoint s4;

-- Les **appels** se font sous le rôle `authenticated`, comme depuis la PWA. Les
-- **vérifications**, elles, repassent sous `postgres` : l'éditeur ne lit ni
-- `subscriptions` ni `audit_log`, et c'est précisément ce que la section 2
-- vient d'exiger. Un test qui assert sous le rôle testé n'assert rien.
set local role authenticated;
set local request.jwt.claims to '{"sub": "eeeeeeee-0000-4000-8000-0000000000e1", "role": "authenticated"}';

do $$
declare r jsonb;
begin
  r := super_admin_create_station('CIS Forêt-sur-Sèvre', 'Europe/Paris');
  perform tests_sa.check(r->>'ok' = 'true', 'la caserne est créée');
  perform tests_sa.check(r->'station'->>'slug' = 'cis-foret-sur-sevre',
    'le slug est dérivé du nom, accents repliés');

  -- Deux casernes de même nom : le slug se suffixe, personne ne voit l'erreur.
  r := super_admin_create_station('CIS Forêt-sur-Sèvre', 'Europe/Paris');
  perform tests_sa.check(r->'station'->>'slug' = 'cis-foret-sur-sevre-2',
    'un homonyme prend un slug suffixé plutôt qu''une violation d''unicité');

  r := super_admin_create_station('   ', 'Europe/Paris');
  perform tests_sa.check(r->>'code' = 'invalid_name', 'un nom vide est refusé');

  r := super_admin_create_station('CIS Ailleurs', 'Mars/Olympus');
  perform tests_sa.check(r->>'code' = 'invalid_timezone',
    'un fuseau inconnu est refusé à la création, pas trois semaines plus tard par un cron');
end $$;

reset role;

-- L'essai vient du trigger du 0023, pas de la fonction : une seule décision.
select tests_sa.check(
  exists (select 1 from subscriptions s join stations st on st.id = s.station_id
           where st.slug = 'cis-foret-sur-sevre' and s.status = 'trialing'
             and s.trial_ends_at > now() + interval '55 days'),
  'la caserne naît en essai de 60 jours (subscription_bootstrap)');

select tests_sa.check(
  exists (select 1 from audit_log a join stations st on st.id = a.station_id
           where st.slug = 'cis-foret-sur-sevre' and a.action = 'station.created'
             and a.actor_id = :editeur::uuid
             and (a.data->>'by_super_admin')::boolean),
  'la création est inscrite au journal d''audit de la caserne');

rollback to savepoint s4;

-- ===========================================================================
-- 5. Nommer le premier administrateur — par le chemin du ticket 006
-- ===========================================================================
\echo ''
\echo '--- 5. create_invitation : la branche super-admin, et elle seule'
savepoint s5;

-- `create_invitation` est fermée à `authenticated` (0009) : elle s'appelle sous
-- la clé de service. On garde donc le rôle `postgres` et on ne pose que la
-- claim, pour que `is_super_admin()` reconnaisse l'éditeur.
set local request.jwt.claims to '{"sub": "eeeeeeee-0000-4000-8000-0000000000e1", "role": "authenticated"}';

do $$
declare r jsonb; v_id uuid;
begin
  -- Une caserne neuve n'a aucun membre : c'est exactement le cas que
  -- `create_invitation` refusait avec not_admin.
  r := super_admin_create_station('CIS Neuve', 'Europe/Paris');
  v_id := (r->'station'->>'id')::uuid;

  r := create_invitation(v_id, 'chef@cis-neuve.test', 'admin',
                         'eeeeeeee-0000-4000-8000-0000000000e1');
  perform tests_sa.check(r->>'ok' = 'true',
    'l''éditeur invite le premier administrateur d''une caserne sans membre');
  perform tests_sa.check(r->'invitation'->>'role' = 'admin',
    'l''invitation porte bien le rôle admin');

  perform tests_sa.check(
    exists (select 1 from audit_log
             where station_id = v_id and action = 'invitation.created'
               and (data->>'by_super_admin')::boolean),
    'l''invitation posée par l''éditeur est marquée comme telle dans l''audit');

  -- Ce que la branche n'ouvre pas : un admin de caserne reste borné à la sienne.
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'x@caserne-a.test',
                         'admin', 'bbbbbbbb-0000-4000-8000-000000000100');
  perform tests_sa.check(r->>'code' = 'not_admin',
    'l''admin de la caserne B n''invite toujours pas dans la caserne A');

  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'x@caserne-a.test',
                         'admin', 'aaaaaaaa-0000-4000-8000-000000000101');
  perform tests_sa.check(r->>'code' = 'not_admin',
    'un simple membre n''invite toujours pas');

  -- Une caserne suspendue ne reçoit pas de nouveaux membres, même de l'éditeur :
  -- s'il veut inviter, il réactive d'abord — et ça se voit dans l'audit.
  update subscriptions set status = 'suspended', suspended_at = now() where station_id = v_id;
  r := create_invitation(v_id, 'autre@cis-neuve.test', 'admin',
                         'eeeeeeee-0000-4000-8000-0000000000e1');
  perform tests_sa.check(r->>'code' = 'station_suspended',
    'une caserne suspendue reste fermée aux invitations, éditeur compris');
end $$;

-- Et le token ne devient pas lisible en RPC pour autant.
select tests_sa.check(
  not has_function_privilege('authenticated',
    'create_invitation(uuid, text, membership_role, uuid)', 'execute'),
  'create_invitation reste fermée au rôle authenticated');

rollback to savepoint s5;

-- ===========================================================================
-- 6. Suspendre et réactiver à la main
-- ===========================================================================
\echo ''
\echo '--- 6. super_admin_set_station_suspended'
savepoint s6;

-- Même raison qu'en 4 : les constats portent sur des tables que l'éditeur ne
-- lit pas. Le rôle reste `postgres`, seule la claim change — et le droit
-- d'appel depuis un client est vérifié à part, juste en dessous.
set local request.jwt.claims to '{"sub": "eeeeeeee-0000-4000-8000-0000000000e1", "role": "authenticated"}';

select tests_sa.check(
  has_function_privilege('authenticated',
    'super_admin_set_station_suspended(uuid, boolean, text)', 'execute')
  and has_function_privilege('authenticated',
    'super_admin_support_schedules(uuid, text)', 'execute')
  and has_function_privilege('authenticated',
    'super_admin_create_station(text, text)', 'execute')
  and not has_function_privilege('anon',
    'super_admin_stations()', 'execute'),
  'les quatre fonctions sont appelables par un client connecté, jamais par anon');

do $$
declare r jsonb; v_dispos bigint; v_assign bigint;
begin
  select count(*) into v_dispos from availabilities where station_id = 'aaaaaaaa-0000-4000-8000-000000000001';
  select count(*) into v_assign from assignments   where station_id = 'aaaaaaaa-0000-4000-8000-000000000001';

  -- Le cas réel : un essai déjà expiré. C'est celui qui piège une réactivation
  -- naïve — sans report de `trial_ends_at`, la tâche de 03:30 reprendrait la
  -- caserne dans la nuit qui suit.
  update subscriptions set trial_ends_at = now() - interval '2 days'
   where station_id = 'aaaaaaaa-0000-4000-8000-000000000001';

  r := super_admin_set_station_suspended('aaaaaaaa-0000-4000-8000-000000000001', true, 'court');
  perform tests_sa.check(r->>'code' = 'reason_required',
    'une raison de moins de dix caractères est refusée par le serveur, pas seulement par le formulaire');

  r := super_admin_set_station_suspended('aaaaaaaa-0000-4000-8000-000000000001', true,
                                         'impayé constaté hors Stripe, demande du trésorier');
  perform tests_sa.check(r->>'ok' = 'true' and r->>'status' = 'suspended'
                     and (r->>'writable')::boolean is false,
    'la caserne passe en lecture seule');

  perform tests_sa.check(
    station_writable('aaaaaaaa-0000-4000-8000-000000000001') is false,
    'station_writable() suit, donc toutes les politiques d''écriture suivent');

  -- La promesse du produit : rien n'est supprimé (`PRD § 6.6`, § 7.6).
  perform tests_sa.check(
    (select count(*) from availabilities where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = v_dispos
    and (select count(*) from assignments where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = v_assign,
    'rien n''est supprimé : les disponibilités et les attributions sont intactes');

  perform tests_sa.check(
    exists (select 1 from audit_log
             where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
               and action = 'subscription.suspended'
               and actor_id = 'eeeeeeee-0000-4000-8000-0000000000e1'
               and data->>'note' like 'impayé constaté%'),
    'la suspension et sa raison sont au journal d''audit de la caserne');

  -- Réactivation : et surtout, elle doit tenir la nuit.
  r := super_admin_set_station_suspended('aaaaaaaa-0000-4000-8000-000000000001', false,
                                         'régularisation reçue par virement');
  perform tests_sa.check(r->>'status' = 'trialing' and (r->>'writable')::boolean
                     and r->>'suspended_at' is null,
    'la caserne redevient écrivable');

  perform tests_sa.check(
    cron_suspend_subscriptions(now() + interval '1 day') = 0,
    'la tâche de 03:30 ne re-suspend pas une caserne qu''on vient de réactiver');

  perform tests_sa.check(
    exists (select 1 from audit_log
             where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
               and action = 'subscription.reactivated'),
    'la réactivation est tracée elle aussi');

  r := super_admin_set_station_suspended('dddddddd-0000-4000-8000-0000000000ff', true,
                                         'caserne qui n''existe pas du tout');
  perform tests_sa.check(r->>'code' = 'station_not_found',
    'une caserne inconnue est dite inconnue, sans exception');
end $$;

rollback to savepoint s6;

-- ===========================================================================
-- 7. Le point de sécurité central : pas de planning sans support tracé
-- ===========================================================================
\echo ''
\echo '--- 7. super_admin_support_schedules : une lecture, une ligne d''audit'
savepoint s7;

-- Le rappel, dans la même section que l'action : hors support, il n'y a rien.
-- Celui-là **doit** tourner sous `authenticated`, c'est une politique qu'on teste.
set local role authenticated;
set local request.jwt.claims to '{"sub": "eeeeeeee-0000-4000-8000-0000000000e1", "role": "authenticated"}';

select tests_sa.check(
  (select count(*) = 0 from schedules where station_id = :caserne_a::uuid),
  'hors support, l''éditeur ne voit aucun planning de la caserne A');

reset role;

do $$
declare r jsonb; v_avant bigint; v_planning jsonb;
begin
  select count(*) into v_avant from audit_log
   where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
     and action = 'support.schedules_read';

  r := super_admin_support_schedules('aaaaaaaa-0000-4000-8000-000000000001', 'pourquoi');
  perform tests_sa.check(r->>'code' = 'reason_required',
    'sans raison écrite, la consultation de support est refusée');

  perform tests_sa.check(
    (select count(*) from audit_log
      where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
        and action = 'support.schedules_read') = v_avant,
    'un refus ne laisse pas de trace de consultation : rien n''a été lu');

  r := super_admin_support_schedules('aaaaaaaa-0000-4000-8000-000000000001',
        'ticket support 42 : le planning de mars ne se valide pas');
  perform tests_sa.check(r->>'ok' = 'true', 'avec une raison, la consultation aboutit');

  v_planning := r->'schedules'->0;
  perform tests_sa.check(
    (v_planning->>'year')::int = 2099 and (v_planning->>'month')::int = 3
    and v_planning->>'status' = 'published'
    and (v_planning->>'shifts')::int = 1
    and (v_planning->'assignments'->>'accepted')::int = 1,
    'le support rend le statut, les dates et les compteurs du mois');

  -- Ce que le support ne rend pas, et ne rendra pas : qui est de garde.
  perform tests_sa.check(
    r::text not like '%' || 'aaaaaaaa-0000-4000-8000-000000000101' || '%'
    and not (v_planning ?| array['user_id', 'users', 'members', 'assignees']),
    'aucun user_id, aucun nom : « où en est le planning », jamais « qui est de garde »');

  perform tests_sa.check(
    (select count(*) from audit_log
      where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
        and action = 'support.schedules_read'
        and actor_id = 'eeeeeeee-0000-4000-8000-0000000000e1'
        and data->>'note' like 'ticket support 42%') = v_avant + 1,
    'la consultation laisse exactement une ligne, avec sa raison');

  -- Deux consultations, deux lignes : pas de session ouverte qu'on oublierait
  -- de fermer.
  r := super_admin_support_schedules('aaaaaaaa-0000-4000-8000-000000000001',
        'ticket support 42 : seconde vérification après correctif');
  perform tests_sa.check(
    (select count(*) from audit_log
      where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
        and action = 'support.schedules_read') = v_avant + 2,
    'une lecture = une ligne d''audit, à chaque fois');
end $$;

-- La garantie qui compte : c'est la **caserne** qui voit qu'on l'a regardée.
-- Sous le rôle `authenticated`, donc à travers `audit_log_select_admin`.
set local role authenticated;
set local request.jwt.claims to '{"sub": "aaaaaaaa-0000-4000-8000-000000000100", "role": "authenticated"}';
select tests_sa.check(
  (select count(*) = 2 from audit_log
    where station_id = :caserne_a::uuid and action = 'support.schedules_read'),
  'l''administrateur de la caserne lit les deux consultations de support dans son journal');

-- Et il n'obtient pas la fonction pour autant.
do $$
declare r jsonb;
begin
  r := super_admin_support_schedules('aaaaaaaa-0000-4000-8000-000000000001',
                                     'je suis admin de cette caserne, pas éditeur');
  perform tests_sa.check(r->>'code' = 'forbidden',
    'un administrateur de caserne n''appelle pas la fonction de support');
end $$;

rollback to savepoint s7;

-- ===========================================================================
-- 8. Ce que les autres ne perdent pas
-- ===========================================================================
-- Retirer `is_super_admin()` des politiques de `stations` ne doit rien casser
-- pour les casernes elles-mêmes : c'est le seul risque de régression du ticket.
\echo ''
\echo '--- 8. Les casernes gardent leurs droits sur leur propre caserne'
savepoint s8;

set local role authenticated;
set local request.jwt.claims to '{"sub": "aaaaaaaa-0000-4000-8000-000000000100", "role": "authenticated"}';

select tests_sa.check(
  (select count(*) = 1 from stations),
  'un admin voit sa caserne, et elle seule');

select tests_sa.allowed(
  $q$ update stations set timezone = 'Europe/Paris'
       where id = 'aaaaaaaa-0000-4000-8000-000000000001' $q$,
  'un admin règle toujours sa caserne');

rollback to savepoint s8;
savepoint s8b;

set local role authenticated;
set local request.jwt.claims to '{"sub": "aaaaaaaa-0000-4000-8000-000000000101", "role": "authenticated"}';
select tests_sa.check(
  (select count(*) = 1 from stations where id = :caserne_a::uuid),
  'un membre lit toujours sa caserne');
select tests_sa.denied(
  $q$ update stations set name = 'Renommée' where id = 'aaaaaaaa-0000-4000-8000-000000000001' $q$,
  'un membre ne renomme toujours pas sa caserne');

rollback to savepoint s8b;

\echo ''
\echo 'Tests super-admin : OK'

rollback;
