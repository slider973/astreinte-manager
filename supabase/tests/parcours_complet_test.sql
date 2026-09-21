-- Le parcours complet d'un mois, côté base (ticket 035).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Pourquoi ce fichier existe
-- --------------------------
-- Les autres fichiers de ce dossier éprouvent **une migration à la fois** :
-- les invitations (0009), les périodes (0012), la matrice (0017), le brouillon
-- (0018), la publication (0019), la réattribution (0020), les relances (0021).
-- Chacun pose ses propres fixtures à l'endroit exact qui l'intéresse, et aucun
-- ne va d'un bout à l'autre.
--
-- Celui-ci ne vérifie **aucune règle nouvelle**. Il vérifie que les huit s'
-- enchaînent : qu'une invitation acceptée donne bien un membre que la matrice
-- voit, que cette matrice nourrit un brouillon, que ce brouillon publié fait
-- apparaître des propositions que le pompier peut refuser, que le refus rouvre
-- un créneau que la réattribution répare, et que la dernière acceptation
-- bascule le planning toute seule. C'est le pendant SQL de
-- `test/parcours/parcours_complet_test.dart`, qui suit le même fil côté
-- écrans.
--
-- Deux tâches planifiées sont jouées **dans le fil**, avec une date de
-- référence : le verrouillage de la période après sa date limite, et la
-- relance des pompiers qui n'ont pas répondu. Elles ne sont pas décoratives —
-- c'est le verrouillage qui ferme la saisie du mois, et c'est la relance qui
-- fait répondre le second pompier. Leur comportement fin est éprouvé par
-- `periods_cron_test.sql` et `assignment_reminders_test.sql` ; ici, on regarde
-- seulement qu'elles tombent au bon moment du parcours.
--
-- Ce qui reste dehors : la couche HTTP. Les Edge Functions `invite-member`,
-- `accept-invitation`, `publish-schedule` et `reassign-shift` emballent les
-- fonctions SQL appelées ici ; elles sont éprouvées par
-- `scripts/test_functions.sh`, qui a besoin de `supabase functions serve` et
-- reste donc local (la CI démarre la pile sans edge-runtime,
-- .github/workflows/ci.yml).
--
-- Méthode identique aux autres fichiers : pas de pgTAP, une exception fait
-- sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : une caserne « CIS Parcours » sur mai 2031, année que ni le seed
-- ni aucun autre fichier ne touche.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_parc;

create function tests_parc.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

create function tests_parc.egal(p_obtenu anyelement, p_attendu anyelement, p_label text) returns void
language plpgsql as $$
begin
  if p_obtenu is distinct from p_attendu then
    raise exception 'ECHEC : % — obtenu [%], attendu [%]', p_label, p_obtenu, p_attendu;
  end if;
  raise notice '  ok   % = %', p_label, coalesce(p_obtenu::text, 'NULL');
end $$;

grant usage on schema tests_parc to authenticated, anon;
grant execute on all functions in schema tests_parc to authenticated, anon;

-- `notify_post` sans réseau — même substitution que `notifications_test.sql` et
-- `publication_test.sql`. L'effet de bord sur la file est conservé, l'appel
-- HTTP est coupé : c'est lui qui n'a rien à faire dans une CI sans Edge
-- Functions.
create or replace function notify_post(p_outbox uuid) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  ligne notification_outbox;
begin
  select * into ligne from notification_outbox where id = p_outbox;
  if not found or ligne.status <> 'pending' then
    return false;
  end if;
  update notification_outbox
     set attempts = attempts + 1, locked_until = now() + interval '2 minutes'
   where id = p_outbox;
  return true;
end $$;

\echo ''
\echo '=== Parcours complet d''un mois, de l''invitation à la validation ==='

-- ===========================================================================
-- Fixtures
-- ===========================================================================
-- Une caserne, un chef de centre (Nadia), un pompier déjà en place (Thomas),
-- et une recrue qui n'existe encore nulle part.
--
-- **La caserne ne demande d'astreinte que le 1er du mois**, de jour et de nuit :
-- `required_day` et `required_night` valent zéro, une surcharge datée les
-- remonte à un. Zéro est une valeur, pas une absence — « pas d'astreinte ce
-- jour-là » est une décision (0018). C'est ce qui rend la **validation**
-- atteignable sans pourvoir soixante-deux créneaux : un planning n'est validé
-- que lorsque *tous* ses créneaux ont leur effectif en attributions acceptées.

insert into stations (id, name, slug, timezone, settings) values
  ('99999999-0000-4000-8000-000000000001', 'CIS Parcours', 'cis-parcours', 'Europe/Paris',
   '{"day_start": "07:00", "day_end": "19:00",
     "required_day": 0, "required_night": 0,
     "required_overrides": {"2031-05-01": {"day": 1, "night": 1}},
     "availability_deadline_day": 15,
     "response_reminder_hours": 24, "response_email_hours": 48,
     "late_report_hours": 72}'::jsonb);

insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current
)
select
  '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
  u.email, now(), '{"provider": "email", "providers": ["email"]}'::jsonb,
  jsonb_build_object('first_name', u.first_name, 'last_name', u.last_name),
  now(), now(), '', '', '', '', ''
from (values
  ('99999999-0000-4000-8000-000000000100'::uuid, 'chef@parcours.test',   'Nadia',  'Aloui'),
  ('99999999-0000-4000-8000-000000000101'::uuid, 'thomas@parcours.test', 'Thomas', 'Moreau')
) as u(id, email, first_name, last_name);

insert into memberships (station_id, user_id, role, status, display_name) values
  ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000100', 'admin',  'active', 'Nadia A.'),
  ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000101', 'member', 'active', 'Thomas M.');

-- Mai 2031, ouvert à la saisie. La date limite est le 15 avril, à la seconde
-- près : c'est elle que la tâche `lock_periods` regarde à l'étape 4.
insert into periods (id, station_id, year, month, status, deadline_at) values
  ('99999999-0000-4000-8000-000000000201', '99999999-0000-4000-8000-000000000001',
   2031, 5, 'open', '2031-04-15 23:59:59+02');

-- Thomas a saisi son mois avant que le parcours commence : disponible le 1er,
-- jour et nuit. C'est ce qui le rendra réattribuable à l'étape 8.
insert into availabilities (station_id, user_id, date, slot, status, set_by) values
  ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000101',
   '2031-05-01', 'day', 'available', '99999999-0000-4000-8000-000000000101'),
  ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000101',
   '2031-05-01', 'night', 'available', '99999999-0000-4000-8000-000000000101');

-- La recrue et son jeton, mémorisés d'une étape à l'autre.
create table tests_parc.fil (cle text primary key, valeur text);
grant select, insert, update on tests_parc.fil to authenticated;

insert into tests_parc.fil (cle, valeur) values
  ('recrue', '99999999-0000-4000-8000-000000000102');

-- ===========================================================================
-- 1. Le chef de centre invite une recrue
-- ===========================================================================
\echo ''
\echo '--- 1. L''administrateur invite'

do $$
declare
  r jsonb;
begin
  r := create_invitation(
         '99999999-0000-4000-8000-000000000001',
         '  Marie.Lefebvre@Exemple.fr ',
         'member',
         '99999999-0000-4000-8000-000000000100');

  perform tests_parc.check(r->>'ok' = 'true', 'l''invitation est créée');
  perform tests_parc.egal(r->'invitation'->>'email', 'marie.lefebvre@exemple.fr',
    'l''adresse est normalisée avant d''entrer en base');
  perform tests_parc.check((r->>'account_exists')::boolean is false,
    'aucun compte n''existe encore : le service devra le créer');

  insert into tests_parc.fil (cle, valeur) values ('jeton', r->>'token');

  -- **L'invitation n'est pas une appartenance.** C'est le point que le parcours
  -- vérifie et qu'aucun écran ne doit jamais contredire.
  perform tests_parc.egal(
    (select count(*)::integer from memberships
      where station_id = '99999999-0000-4000-8000-000000000001'),
    2, 'la caserne a toujours ses deux membres');
end $$;

-- Ce que fait l'Edge Function `invite-member` juste après : créer le compte.
insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current
)
values (
  '00000000-0000-0000-0000-000000000000', '99999999-0000-4000-8000-000000000102',
  'authenticated', 'authenticated', 'marie.lefebvre@exemple.fr', now(),
  '{"provider": "email", "providers": ["email"]}'::jsonb,
  '{"first_name": "Marie", "last_name": "Lefebvre"}'::jsonb,
  now(), now(), '', '', '', '', '');

-- ===========================================================================
-- 2. La recrue ouvre le lien et rejoint la caserne
-- ===========================================================================
\echo ''
\echo '--- 2. La recrue accepte'

do $$
declare
  a jsonb;
begin
  a := accept_invitation(
         (select valeur from tests_parc.fil where cle = 'jeton'),
         '99999999-0000-4000-8000-000000000102',
         'Marie.Lefebvre@Exemple.fr');

  perform tests_parc.check(a->>'ok' = 'true', 'l''acceptation aboutit');
  perform tests_parc.egal(a->'membership'->>'status', 'active',
    'l''appartenance naît active');
  perform tests_parc.egal(a->'station'->>'name', 'CIS Parcours',
    'la caserne est nommée à la recrue');
  perform tests_parc.check(
    (select accepted_at is not null from invitations
      where station_id = '99999999-0000-4000-8000-000000000001'),
    'l''invitation est marquée acceptée : le lien ne servira plus');
end $$;

-- La recrue voit sa caserne, et rien de plus. C'est la RLS, vue du parcours.
set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000102","role":"authenticated"}';

do $$
begin
  perform tests_parc.egal(
    (select count(*)::integer from memberships), 3,
    'la recrue voit les membres de sa caserne, et eux seuls');
  perform tests_parc.egal(
    (select count(*)::integer from periods
      where station_id = '99999999-0000-4000-8000-000000000001'),
    1, 'elle voit le mois ouvert à la saisie');
end $$;

reset role;

-- ===========================================================================
-- 3. Elle saisit ses disponibilités du mois
-- ===========================================================================
\echo ''
\echo '--- 3. La saisie du mois'

set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000102","role":"authenticated"}';

do $$
begin
  -- Le 1er, jour et nuit. `set_by` n'est **pas** envoyé : le déclencheur
  -- `availabilities_trace_auteur` (0012) le pose, et c'est lui qui distingue
  -- plus tard une saisie par procuration.
  insert into availabilities (station_id, user_id, date, slot, status) values
    ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000102',
     '2031-05-01', 'day', 'available'),
    ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000102',
     '2031-05-01', 'night', 'available');

  perform tests_parc.egal(
    (select count(distinct set_by)::integer from availabilities
      where user_id = '99999999-0000-4000-8000-000000000102'),
    1, 'set_by est posé par la base, et c''est la recrue elle-même');
  perform tests_parc.egal(
    (select set_by from availabilities
      where user_id = '99999999-0000-4000-8000-000000000102' and slot = 'day'),
    '99999999-0000-4000-8000-000000000102'::uuid,
    'la saisie n''est pas une procuration');
end $$;

reset role;

-- ===========================================================================
-- 4. La date limite passe : la tâche horaire verrouille le mois
-- ===========================================================================
\echo ''
\echo '--- 4. lock_periods, une heure après la date limite'

do $$
declare
  verrouillees integer;
begin
  -- La tâche tourne toutes les heures. On lui donne l'heure qu'il est,
  -- une heure après la date limite : c'est le pire cas du critère « dans
  -- l'heure » du ticket 014.
  verrouillees := cron_lock_periods('2031-04-16 01:00:00+02'::timestamptz);

  perform tests_parc.check(verrouillees >= 1,
    'la tâche verrouille au moins le mois du parcours');
  perform tests_parc.egal(
    (select status::text from periods
      where id = '99999999-0000-4000-8000-000000000201'),
    'locked', 'mai 2031 est verrouillé');
end $$;

-- Et la saisie se ferme, pour tout le monde. La politique **filtre sans
-- lever** : zéro ligne, et rien en base (docs/SCHEMA.md § 4).
set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000102","role":"authenticated"}';

do $$
declare
  lignes integer;
begin
  update availabilities set status = 'absent'
   where user_id = '99999999-0000-4000-8000-000000000102' and slot = 'day';
  get diagnostics lignes = row_count;

  perform tests_parc.egal(lignes, 0,
    'période verrouillée : la modification ne touche aucune ligne');
  perform tests_parc.egal(
    (select status::text from availabilities
      where user_id = '99999999-0000-4000-8000-000000000102' and slot = 'day'),
    'available', 'et la disponibilité saisie est intacte');
end $$;

reset role;

-- ===========================================================================
-- 5. L'administrateur lit la matrice et construit le brouillon
-- ===========================================================================
\echo ''
\echo '--- 5. La matrice, puis le brouillon'

set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  ligne     record;
  planning  schedules;
  creneau_j uuid;
  creneau_n uuid;
  pose      assignments;
begin
  -- 5a. La matrice : la recrue y est, avec ce qu'elle a saisi.
  select * into ligne
    from availability_matrix(
      '99999999-0000-4000-8000-000000000001',
      '99999999-0000-4000-8000-000000000201')
   where user_id = '99999999-0000-4000-8000-000000000102';

  perform tests_parc.check(ligne.user_id is not null,
    'la recrue a sa ligne dans la matrice du chef de centre');
  perform tests_parc.egal(length(ligne.day_slots), 31,
    'un caractère par jour de mai');
  perform tests_parc.egal(substr(ligne.day_slots, 1, 1), 'D',
    'le 1er de jour est lu « disponible », en majuscule : elle l''a saisi elle-même');
  perform tests_parc.egal(substr(ligne.night_slots, 1, 1), 'D',
    'le 1er de nuit aussi');

  -- 5b. Le planning du mois et ses créneaux.
  planning := create_schedule(
    '99999999-0000-4000-8000-000000000001',
    '99999999-0000-4000-8000-000000000201');

  perform tests_parc.egal(planning.status::text, 'draft',
    'le planning naît en brouillon');
  perform tests_parc.egal(
    (select count(*)::integer from shifts where schedule_id = planning.id),
    62, 'un créneau par jour de mai et par valeur de slot_type');
  perform tests_parc.egal(
    (select count(*)::integer from shifts
      where schedule_id = planning.id and required_count = 1),
    2, 'deux créneaux seulement demandent quelqu''un : la surcharge datée du 1er');

  select id into creneau_j from shifts
   where schedule_id = planning.id and date = '2031-05-01' and slot = 'day';
  select id into creneau_n from shifts
   where schedule_id = planning.id and date = '2031-05-01' and slot = 'night';

  -- 5c. Les deux attributions. Ni `was_available` ni `status` ne sont envoyés :
  -- la base les pose.
  insert into assignments (station_id, shift_id, user_id, created_by)
  values ('99999999-0000-4000-8000-000000000001', creneau_j,
          '99999999-0000-4000-8000-000000000102',
          '99999999-0000-4000-8000-000000000100')
  returning * into pose;

  perform tests_parc.egal(pose.status::text, 'proposed',
    'une attribution de brouillon est « proposed »');
  perform tests_parc.check(pose.proposed_at is null,
    'et son proposed_at est nul : rien n''est parti');
  perform tests_parc.egal(pose.was_available, true,
    'was_available est calculé par la base sur la saisie de la recrue');

  insert into assignments (station_id, shift_id, user_id, created_by)
  values ('99999999-0000-4000-8000-000000000001', creneau_n,
          '99999999-0000-4000-8000-000000000102',
          '99999999-0000-4000-8000-000000000100');

  insert into tests_parc.fil (cle, valeur) values
    ('planning', planning.id::text),
    ('creneau_j', creneau_j::text),
    ('creneau_n', creneau_n::text);
end $$;

reset role;

-- La recrue ne voit **rien** du brouillon : c'est le chef qui écrit son mois,
-- et un pompier qui verrait le brouillon répondrait à un planning en cours
-- d'écriture.
set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000102","role":"authenticated"}';

do $$
begin
  perform tests_parc.egal((select count(*)::integer from schedules), 0,
    'un brouillon est invisible des pompiers');
  perform tests_parc.egal((select count(*)::integer from assignments), 0,
    'et ses attributions avec lui');
end $$;

reset role;

-- ===========================================================================
-- 6. La publication
-- ===========================================================================
\echo ''
\echo '--- 6. publish_schedule'

do $$
declare
  r        jsonb;
  planning uuid := (select valeur::uuid from tests_parc.fil where cle = 'planning');
begin
  r := publish_schedule(planning, '99999999-0000-4000-8000-000000000100');

  perform tests_parc.check(r->>'ok' = 'true', 'la publication aboutit');
  -- Deux attributions, **un seul pompier** : c'est le nombre de téléphones qui
  -- sonnent, et c'est le nombre que l'écran annonce.
  perform tests_parc.egal(jsonb_array_length(r->'recipients'), 1,
    'un destinataire : les créneaux d''un même pompier voyagent groupés');
  perform tests_parc.egal((r->>'assignments')::integer, 2,
    'deux attributions horodatées');

  perform tests_parc.egal(
    (select status::text from schedules where id = planning),
    'published', 'le planning est publié');
  perform tests_parc.egal(
    (select count(*)::integer from assignments a
      join shifts s on s.id = a.shift_id
     where s.schedule_id = planning and a.proposed_at is null),
    0, 'plus aucune attribution sans proposed_at : tout est parti');
  -- **Aucune ligne dans la file d'envoi, et c'est juste** : `publish_schedule`
  -- rend ses destinataires déjà groupés, et c'est l'Edge Function
  -- `publish-schedule` qui appelle `send-notification`. Les téléphones sonnent
  -- par ce chemin-là, éprouvé par `scripts/test_functions.sh`.
  perform tests_parc.egal(
    (select count(*)::integer from notification_outbox
      where station_id = '99999999-0000-4000-8000-000000000001'),
    0, 'la publication ne passe pas par la file : elle rend ses destinataires');
end $$;

-- Et maintenant la recrue voit ses propositions — celles-là et pas d'autres.
set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000102","role":"authenticated"}';

do $$
begin
  perform tests_parc.egal(
    (select count(*)::integer from assignments
      where user_id = '99999999-0000-4000-8000-000000000102'
        and status = 'proposed' and proposed_at is not null),
    2, 'la recrue a deux propositions en attente');
end $$;

reset role;

-- ===========================================================================
-- 7. Elle refuse un créneau, accepte l'autre
-- ===========================================================================
\echo ''
\echo '--- 7. Une réponse, puis l''autre'

set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000102","role":"authenticated"}';

do $$
declare
  creneau_j uuid := (select valeur::uuid from tests_parc.fil where cle = 'creneau_j');
  creneau_n uuid := (select valeur::uuid from tests_parc.fil where cle = 'creneau_n');
  lignes    integer;
begin
  -- Le refus. La charge utile ne porte que `status` et `decline_reason` :
  -- `assignments_member_transition` (0008) refuse toute colonne de plus.
  update assignments set status = 'declined', decline_reason = 'en formation'
   where shift_id = creneau_j and user_id = '99999999-0000-4000-8000-000000000102';
  get diagnostics lignes = row_count;
  perform tests_parc.egal(lignes, 1, 'le refus est enregistré');

  perform tests_parc.check(
    (select responded_at is not null from assignments
      where shift_id = creneau_j and user_id = '99999999-0000-4000-8000-000000000102'),
    'responded_at est posé par la base, jamais par le téléphone');

  -- L'acceptation.
  update assignments set status = 'accepted'
   where shift_id = creneau_n and user_id = '99999999-0000-4000-8000-000000000102';
  get diagnostics lignes = row_count;
  perform tests_parc.egal(lignes, 1, 'l''acceptation est enregistrée');
end $$;

reset role;

do $$
begin
  -- Un créneau requis sur deux est couvert : le planning **reste publié**.
  perform tests_parc.egal(
    (select status::text from schedules
      where id = (select valeur::uuid from tests_parc.fil where cle = 'planning')),
    'published', 'un refus laisse le planning publié : il n''est pas complet');
  perform tests_parc.egal(
    (select count(*)::integer from notification_outbox
      where type = 'schedule_validated'),
    0, 'et personne n''a été prévenu d''une validation qui n''a pas eu lieu');
end $$;

-- ===========================================================================
-- 8. L'administrateur réattribue le créneau refusé
-- ===========================================================================
\echo ''
\echo '--- 8. reassign_shift'

do $$
declare
  r         jsonb;
  creneau_j uuid := (select valeur::uuid from tests_parc.fil where cle = 'creneau_j');
  nouvelle  uuid;
begin
  r := reassign_shift(
         creneau_j,
         '99999999-0000-4000-8000-000000000101',
         '99999999-0000-4000-8000-000000000100');

  perform tests_parc.check(r->>'ok' = 'true', 'la réattribution aboutit');
  perform tests_parc.check((r->>'previous_notified')::boolean is false,
    'celui qui avait refusé n''est pas prévenu : il sait déjà');

  select id into nouvelle from assignments
   where shift_id = creneau_j and user_id = '99999999-0000-4000-8000-000000000101';

  perform tests_parc.egal(
    (select status::text from assignments where id = nouvelle),
    'proposed', 'le remplaçant reçoit une proposition');
  perform tests_parc.check(
    (select proposed_at is not null from assignments where id = nouvelle),
    'elle part tout de suite : le planning est déjà publié');

  -- Le fil de l'historique : le refus dit ce qui l'a couvert.
  perform tests_parc.egal(
    (select replaced_by from assignments
      where shift_id = creneau_j and user_id = '99999999-0000-4000-8000-000000000102'),
    nouvelle, 'le refus porte le lien vers l''attribution qui l''a couvert');

  perform tests_parc.egal(
    (select count(*)::integer from notification_outbox
      where type = 'assignment_proposed'),
    1, 'un téléphone sonne : celui du remplaçant');
end $$;

-- ===========================================================================
-- 9. La relance automatique, vingt-cinq heures plus tard
-- ===========================================================================
\echo ''
\echo '--- 9. cron_assignment_reminders, au-delà de response_reminder_hours'

do $$
declare
  envoyes integer;
begin
  -- Rien avant l'échéance : le seuil de la caserne est 24 heures.
  envoyes := cron_assignment_reminders(now() + interval '2 hours');
  perform tests_parc.egal(
    (select count(*)::integer from notification_outbox
      where type = 'assignment_reminder'),
    0, 'deux heures après : personne n''est en retard, rien ne part');

  -- Vingt-cinq heures après la publication, le palier `push` est franchi.
  envoyes := cron_assignment_reminders(now() + interval '25 hours');
  perform tests_parc.check(envoyes >= 1, 'la tâche relance au moins une caserne');

  perform tests_parc.egal(
    (select count(*)::integer from notification_outbox
      where type = 'assignment_reminder'),
    1, 'une relance, groupée par pompier');
  perform tests_parc.egal(
    (select count(*)::integer from assignments
      where user_id = '99999999-0000-4000-8000-000000000101'
        and reminder_count = 1),
    1, 'la marque suit l''envoi : reminder_count incrémenté sur la garde relancée');
end $$;

-- ===========================================================================
-- 10. Le second pompier accepte : le planning se valide tout seul
-- ===========================================================================
\echo ''
\echo '--- 10. La dernière acceptation, et la bascule'

set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
declare
  creneau_j uuid := (select valeur::uuid from tests_parc.fil where cle = 'creneau_j');
  lignes    integer;
begin
  update assignments set status = 'accepted'
   where shift_id = creneau_j and user_id = '99999999-0000-4000-8000-000000000101';
  get diagnostics lignes = row_count;
  perform tests_parc.egal(lignes, 1, 'l''acceptation du remplaçant est enregistrée');
end $$;

reset role;

do $$
declare
  planning uuid := (select valeur::uuid from tests_parc.fil where cle = 'planning');
begin
  -- `schedule_auto_validate` a vu que chaque créneau requis avait son effectif
  -- en attributions **acceptées**.
  perform tests_parc.egal(
    (select status::text from schedules where id = planning),
    'validated', 'le planning est validé, sans que personne ne l''ait demandé');
  perform tests_parc.check(
    (select validated_at is not null from schedules where id = planning),
    'validated_at est posé par la base');
  perform tests_parc.check(
    (select published_at is not null from schedules where id = planning),
    'et published_at n''a pas bougé : l''histoire du mois est intacte');

  -- Tous les membres actifs l'apprennent, administrateur compris : il n'a pas
  -- déclenché la transition, il a le droit de l'apprendre.
  perform tests_parc.egal(
    (select count(*)::integer from notification_outbox
      where type = 'schedule_validated'),
    1, 'une notification de validation, une seule');
  perform tests_parc.egal(
    (select jsonb_array_length(recipients) from notification_outbox
      where type = 'schedule_validated'),
    3, 'elle va aux trois membres actifs de la caserne');

  -- Et le refus est toujours là : l'historique de la caserne ne s'efface pas
  -- (docs/PRD.md § 7.6).
  perform tests_parc.egal(
    (select count(*)::integer from assignments
      where status = 'declined' and decline_reason = 'en formation'),
    1, 'le refus reste en base, avec son motif');
end $$;

-- ===========================================================================
-- 11. Le mois d'après s'ouvre tout seul
-- ===========================================================================
\echo ''
\echo '--- 11. cron_create_periods, le 1er du mois'

do $$
declare
  crees integer;
begin
  -- La tâche tourne le 1er de chaque mois et ouvre M+1 et M+2. Au 1er juin
  -- 2031, la caserne doit se retrouver avec juillet et août ouverts.
  crees := cron_create_periods('2031-06-01 02:00:00+02'::timestamptz);
  perform tests_parc.check(crees >= 2, 'la tâche a créé au moins deux mois');

  perform tests_parc.check(
    exists (select 1 from periods
             where station_id = '99999999-0000-4000-8000-000000000001'
               and year = 2031 and month = 7 and status = 'open'),
    'juillet 2031 est ouvert à la saisie');
  perform tests_parc.check(
    exists (select 1 from periods
             where station_id = '99999999-0000-4000-8000-000000000001'
               and year = 2031 and month = 8 and status = 'open'),
    'août 2031 aussi');

  -- Idempotente : le cycle recommence sans rien doubler.
  crees := cron_create_periods('2031-06-01 02:00:00+02'::timestamptz);
  perform tests_parc.egal(crees, 0, 'rejouée, la tâche ne crée rien de plus');
end $$;

\echo ''
\echo '=== Parcours complet : OK ==='

rollback;
