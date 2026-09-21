-- Tests de l'export RGPD (migration 0027, ticket 034).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié
-- ------------------
-- 1. **Toutes les sections sont là**, y compris vides : une section absente et une
--    section vide ne disent pas la même chose, et c'est le premier critère
--    d'acceptation du ticket.
-- 2. **Chaque table du § 2 qui porte un `user_id` est représentée.** Le test pose
--    une ligne dans chacune et exige que l'inventaire bouge. C'est la garde
--    contre l'oubli du jour où une table s'ajoutera au schéma.
-- 3. **Rien d'une autre personne.** Le fichier complet est fouillé, en texte, à la
--    recherche du nom, du prénom, de l'adresse et de l'identifiant d'un autre
--    membre et de l'administrateur. Deuxième critère du ticket.
-- 4. Le jeton d'invitation n'en sort jamais ; l'adresse d'un invité est masquée ;
--    le jeton d'un appareil est tronqué.
-- 5. Un identifiant inconnu rend `profile_missing`, jamais une exception.
-- 6. La fonction n'est exécutable ni par `authenticated` ni par `anon` : son
--    paramètre `p_user_id` viserait le dossier complet de n'importe qui.
-- 7. Les actes d'administration **sur mes données** me sont rendus, sans
--    l'identité de leur auteur ni les clés qui désignent des tiers.
--
-- Méthode identique à rls_test.sql : pas de pgTAP, une exception fait sortir psql
-- avec un code non nul. Tout le fichier tourne dans une transaction annulée à la fin.
--
-- Fixtures : le seed (caserne A = aaaaaaaa-…-001, admin …100, membres …101 à …108)
-- plus un planning publié, une attribution, une notification, un appareil et deux
-- invitations, posés ici : le seed n'en crée aucun.

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
-- Fixtures — de quoi remplir toutes les sections de l'export du membre 101
-- ---------------------------------------------------------------------------
do $$
declare
  v_station  uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  v_membre   uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
  v_autre    uuid := 'aaaaaaaa-0000-4000-8000-000000000102';
  v_admin    uuid := 'aaaaaaaa-0000-4000-8000-000000000100';
  v_period   uuid;
  v_schedule uuid;
  v_shift    uuid;
  v_dispo    uuid;
begin
  select id into v_period from periods
   where station_id = v_station order by year, month limit 1;

  insert into schedules (station_id, period_id, status, created_by, published_at)
  values (v_station, v_period, 'published', v_admin, now())
  returning id into v_schedule;

  insert into shifts (station_id, schedule_id, date, slot, required_count)
  values (v_station, v_schedule, current_date, 'day', 1)
  returning id into v_shift;

  -- Une attribution pour moi, une pour quelqu'un d'autre sur le même créneau :
  -- c'est la configuration qui fait fuir un export mal écrit.
  insert into assignments (station_id, shift_id, user_id, status, created_by,
                           proposed_at, responded_at, decline_reason)
  values (v_station, v_shift, v_membre, 'accepted', v_admin, now(), now(), null);
  insert into assignments (station_id, shift_id, user_id, status, created_by, proposed_at)
  values (v_station, v_shift, v_autre, 'proposed', v_admin, now());

  insert into push_tokens (user_id, token, platform, device_label)
  values (v_membre, 'jeton-firebase-tres-long-0123456789ABCDEF', 'web', 'iPhone · Safari');

  insert into notifications (station_id, user_id, type, channel, title, body, data)
  values (v_station, v_membre, 'assignment_proposed', 'inapp',
          'Une astreinte te concerne', 'Corps de la notification',
          '{"route": "/proposals"}'::jsonb);

  -- Une invitation reçue par le membre, une invitation envoyée par l'admin à un
  -- tiers : la première doit sortir sans jeton, la seconde avec une adresse masquée.
  insert into invitations (station_id, email, role, invited_by, token)
  values ('bbbbbbbb-0000-4000-8000-000000000001', 'membre1@caserne-a.test',
          'member', v_admin, 'jeton-invitation-secret-034');
  insert into invitations (station_id, email, role, invited_by, token)
  values (v_station, 'nouvelle.recrue@caserne-a.test', 'member', v_admin,
          'jeton-invitation-secret-034-bis');

  -- Un acte d'administration sur mes données : l'admin saisit une disponibilité
  -- à ma place. Le déclencheur de la migration 0012 écrit la ligne d'audit.
  insert into availabilities (station_id, user_id, date, slot, status, set_by)
  values (v_station, v_membre, current_date + 400, 'night', 'absent', v_admin)
  returning id into v_dispo;
end $$;

\echo ''
\echo '=== 1. Toutes les sections attendues sont présentes, même vides ==='

savepoint s1;

do $$
declare
  v_export   jsonb := export_own_data('aaaaaaaa-0000-4000-8000-000000000105');
  v_attendu  text[] := array[
    'profil', 'casernes', 'appartenances', 'disponibilites',
    'preferences_de_charge', 'attributions', 'notifications', 'appareils',
    'invitations_recues', 'invitations_envoyees',
    'actes_administratifs_me_concernant', 'mes_actes_administratifs',
    'editeur_du_produit'];
  v_section  text;
begin
  perform tests.check(v_export ->> 'ok' = 'true', 'l''export aboutit');

  foreach v_section in array v_attendu loop
    perform tests.check(
      v_export -> 'donnees' ? v_section,
      format('la section « %s » est présente', v_section));
  end loop;

  -- Le membre 105 n'a ni attribution, ni notification, ni appareil : ces
  -- sections doivent être des tableaux **vides**, jamais absentes ni nulles.
  perform tests.check(
    jsonb_typeof(v_export -> 'donnees' -> 'attributions') = 'array'
      and jsonb_array_length(v_export -> 'donnees' -> 'attributions') = 0,
    'une section sans donnée est un tableau vide');

  -- L'inventaire couvre les onze sections de type tableau, plus le profil.
  -- `editeur_du_produit` est un booléen : il n'a rien à compter.
  perform tests.check(
    (select count(*) from jsonb_object_keys(v_export -> 'inventaire')) = 12,
    'l''inventaire compte les douze sections dénombrables');
  perform tests.check(
    (select count(*) from jsonb_object_keys(v_export -> 'donnees')) = 13,
    'l''export porte treize sections en tout');
end $$;

rollback to savepoint s1;

\echo ''
\echo '=== 2. Chaque table du § 2 qui porte un user_id est représentée ==='

savepoint s2;

do $$
declare
  v_membre  uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
  v_inv     jsonb := (export_own_data(v_membre)) -> 'inventaire';
  v_donnees jsonb := (export_own_data(v_membre)) -> 'donnees';
begin
  -- § 2.2 profiles
  perform tests.check(v_donnees -> 'profil' ->> 'email' = 'membre1@caserne-a.test',
    'profiles : le profil est exporté avec son adresse');
  -- § 2.3 memberships (+ § 2.1 stations, réduites à ce qui rend le fichier lisible)
  perform tests.check((v_inv ->> 'appartenances')::int = 1, 'memberships : une appartenance');
  perform tests.check((v_inv ->> 'casernes')::int = 1, 'stations : la caserne est nommée');
  -- § 2.4 invitations (reçues)
  perform tests.check((v_inv ->> 'invitations_recues')::int = 1, 'invitations : celle reçue');
  -- § 2.6 availabilities
  perform tests.check((v_inv ->> 'disponibilites')::int > 0, 'availabilities : les siennes');
  -- § 2.7 availability_preferences (+ § 2.5 periods, réduites à année et mois)
  perform tests.check((v_inv ->> 'preferences_de_charge')::int = 2,
    'availability_preferences : ses deux mois');
  perform tests.check(
    v_donnees -> 'preferences_de_charge' -> 0 ? 'annee'
      and v_donnees -> 'preferences_de_charge' -> 0 ? 'mois',
    'periods : l''année et le mois rendent la préférence lisible seule');
  -- § 2.9 shifts + § 2.8 schedules, recopiés dans l'attribution
  perform tests.check((v_inv ->> 'attributions')::int = 1, 'assignments : la sienne, une seule');
  perform tests.check(
    v_donnees -> 'attributions' -> 0 ? 'date'
      and v_donnees -> 'attributions' -> 0 ? 'creneau'
      and v_donnees -> 'attributions' -> 0 ? 'planning',
    'shifts et schedules : date, créneau et statut du planning sont recopiés');
  -- § 2.11 push_tokens
  perform tests.check((v_inv ->> 'appareils')::int = 1, 'push_tokens : son appareil');
  -- § 2.12 notifications
  perform tests.check((v_inv ->> 'notifications')::int = 1, 'notifications : celle reçue');
  -- § 2.14 audit_log, dans les deux sens
  perform tests.check((v_inv ->> 'actes_administratifs_me_concernant')::int >= 1,
    'audit_log : l''acte posé sur mes données');
  -- § 2.15 super_admins
  perform tests.check(v_donnees ->> 'editeur_du_produit' = 'false',
    'super_admins : le fait est dit, en booléen');
end $$;

rollback to savepoint s2;

\echo ''
\echo '=== 3. L''export ne contient rien d''une autre personne ==='

savepoint s3;

do $$
declare
  v_texte   text := (export_own_data('aaaaaaaa-0000-4000-8000-000000000101'))::text;
  v_interdit text;
  -- L'autre membre attribué sur le même créneau, et l'administrateur qui a agi
  -- sur mes données : ni leur nom, ni leur adresse, ni leur identifiant.
  v_mots    text[] := array[
    'Thomas', 'Moreau', 'membre2@caserne-a.test', 'aaaaaaaa-0000-4000-8000-000000000102',
    'Jean', 'Dupont', 'admin@caserne-a.test', 'aaaaaaaa-0000-4000-8000-000000000100',
    'nouvelle.recrue@caserne-a.test',
    'jeton-invitation-secret-034'];
begin
  foreach v_interdit in array v_mots loop
    perform tests.check(
      position(v_interdit in v_texte) = 0,
      format('« %s » n''apparaît pas dans l''export', v_interdit));
  end loop;

  -- Et pourtant le fait, lui, est bien là : une case cochée par quelqu'un d'autre
  -- reste une information qui me concerne.
  perform tests.check(
    v_texte like '%saisie_par_un_administrateur": true%',
    'la saisie par un administrateur est dite, sans le nommer');
end $$;

rollback to savepoint s3;

\echo ''
\echo '=== 4. Jeton d''invitation absent, adresse invitée masquée, jeton d''appareil tronqué ==='

savepoint s4;

do $$
declare
  v_admin   jsonb := export_own_data('aaaaaaaa-0000-4000-8000-000000000100');
  v_membre  jsonb := export_own_data('aaaaaaaa-0000-4000-8000-000000000101');
  v_envoyee jsonb;
begin
  perform tests.check(
    position('jeton-invitation-secret' in v_admin::text) = 0,
    'aucun jeton d''invitation dans l''export de celui qui a invité');
  perform tests.check(
    position('jeton-invitation-secret' in v_membre::text) = 0,
    'aucun jeton d''invitation dans l''export de l''invité');

  select ligne into v_envoyee
  from jsonb_array_elements(v_admin -> 'donnees' -> 'invitations_envoyees') as t(ligne)
  where ligne ->> 'adresse_masquee' like 'n%@caserne-a.test';

  perform tests.check(v_envoyee is not null, 'l''invitation envoyée est bien exportée');
  perform tests.check(
    v_envoyee ->> 'adresse_masquee' = mask_email('nouvelle.recrue@caserne-a.test'),
    'l''adresse de l''invité est masquée');

  -- Le jeton posé en fixture est « …-0123456789ABCDEF » : ses douze derniers
  -- caractères, et rien de plus.
  perform tests.check(
    v_membre -> 'donnees' -> 'appareils' -> 0 ->> 'jeton_fin' = '456789ABCDEF',
    'le jeton de l''appareil est tronqué à ses douze derniers caractères');
  perform tests.check(
    position('jeton-firebase-tres-long' in v_membre::text) = 0,
    'le jeton complet de l''appareil ne sort pas');
  perform tests.check(
    v_membre -> 'donnees' -> 'appareils' -> 0 ->> 'appareil' = 'iPhone · Safari',
    'l''appareil reste reconnaissable par son libellé');
end $$;

rollback to savepoint s4;

\echo ''
\echo '=== 5. Un identifiant inconnu rend profile_missing ==='

savepoint s5;

do $$
declare
  v_export jsonb := export_own_data('dddddddd-0000-4000-8000-0000000000ff');
begin
  perform tests.check(v_export ->> 'ok' = 'false', 'l''export est refusé');
  perform tests.check(v_export ->> 'code' = 'profile_missing', 'le code dit pourquoi');
  perform tests.check(not v_export ? 'donnees', 'aucune donnée n''accompagne le refus');
end $$;

rollback to savepoint s5;

\echo ''
\echo '=== 6. La fonction est fermée aux clients ==='

savepoint s6;

do $$
begin
  perform tests.check(
    not has_function_privilege('authenticated', 'public.export_own_data(uuid)', 'execute'),
    'authenticated n''exécute pas export_own_data');
  perform tests.check(
    not has_function_privilege('anon', 'public.export_own_data(uuid)', 'execute'),
    'anon n''exécute pas export_own_data');
  perform tests.check(
    has_function_privilege('service_role', 'public.export_own_data(uuid)', 'execute'),
    'le rôle de service, lui, l''exécute');
end $$;

rollback to savepoint s6;

\echo ''
\echo '=== 7. Un membre n''exporte pas le dossier d''un autre ==='

savepoint s7;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  begin
    perform export_own_data('aaaaaaaa-0000-4000-8000-000000000102');
    raise exception 'ECHEC : un membre a pu appeler export_own_data';
  exception
    when insufficient_privilege then null;
    when raise_exception then
      if sqlerrm like 'ECHEC%' then raise; end if;
  end;
  perform tests.check(true, 'l''appel direct d''export_own_data est refusé');

  -- Et le même refus pour son propre identifiant : ce n'est pas une porte
  -- entrouverte, c'est une porte fermée. L'Edge Function est le seul chemin.
  begin
    perform export_own_data('aaaaaaaa-0000-4000-8000-000000000101');
    raise exception 'ECHEC : un membre a pu s''exporter lui-même par RPC';
  exception
    when insufficient_privilege then null;
    when raise_exception then
      if sqlerrm like 'ECHEC%' then raise; end if;
  end;
  perform tests.check(true, 'même pour soi, la RPC directe est refusée');
end $$;

rollback to savepoint s7;

\echo ''
\echo '=== 8. Les actes d''administration sur mes données me sont rendus ==='

savepoint s8;

do $$
declare
  v_export jsonb := export_own_data('aaaaaaaa-0000-4000-8000-000000000101');
  v_acte   jsonb;
begin
  select ligne into v_acte
  from jsonb_array_elements(v_export -> 'donnees' -> 'actes_administratifs_me_concernant')
       as t(ligne)
  where ligne ->> 'acte' = 'availability.set_for_member'
  limit 1;

  perform tests.check(v_acte is not null,
    'la saisie faite à ma place est dans le journal qui m''est rendu');
  perform tests.check(v_acte ->> 'caserne' = 'CIS Saint-Martin',
    'la caserne où l''acte a eu lieu est nommée');
  perform tests.check(v_acte -> 'details' ? 'status' and v_acte -> 'details' ? 'slot',
    'les détails utiles sont gardés');
  perform tests.check(not (v_acte -> 'details' ? 'user_id'),
    'aucun identifiant de personne dans les détails');
  perform tests.check(not (v_acte ? 'acteur'),
    'l''auteur de l''acte n''est pas nommé : c''est sa donnée, pas la mienne');

  -- L'administrateur, lui, retrouve ses propres actes — sans leur contenu, qui
  -- décrit quelqu'un d'autre.
  select ligne into v_acte
  from jsonb_array_elements(
         (export_own_data('aaaaaaaa-0000-4000-8000-000000000100'))
           -> 'donnees' -> 'mes_actes_administratifs') as t(ligne)
  limit 1;
  perform tests.check(v_acte is not null, 'l''administrateur retrouve ses actes');
  perform tests.check(not (v_acte ? 'details'),
    'ses actes n''emportent pas le détail, qui décrit un tiers');
end $$;

rollback to savepoint s8;

\echo ''
\echo '=== Tous les tests de l''export RGPD sont passés ==='
\echo ''

rollback;
