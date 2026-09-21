-- Tests des relances automatiques (migration 0021, ticket 022).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
-- 1. Le palier push : rien avant `response_reminder_hours`, une notification
--    **par membre** à l'échéance (pas une par garde), les canaux de
--    docs/WORKFLOWS.md § 8, et la marque posée sur les attributions envoyées.
-- 2. Le palier courriel : rien avant `response_email_hours`, le courriel à
--    l'échéance — et **rien après**. Deux paliers, pas une sonnerie horaire.
-- 3. Une attribution qui a reçu une réponse ne reçoit plus rien. C'est le
--    critère d'acceptation explicite du ticket.
-- 4. Aucun doublon si la tâche tourne deux fois dans la même heure, et — ce qui
--    compte davantage — **aucune marque** dans ce cas : un palier ne se franchit
--    que lorsqu'un envoi part réellement (revue du ticket 019).
-- 5. Les délais sont ceux de **chaque caserne**. Une caserne réglée à 2 h / 4 h
--    est relancée à 2 h et 4 h pendant que sa voisine à 24 h / 48 h ne bouge pas.
-- 6. Cohabitation avec la relance manuelle de `remind_schedule` (0019) : elle
--    tient lieu de premier palier, et **aucun nombre de clics ne fait sauter le
--    courriel**.
-- 7. Le rapport aux administrateurs : le bon palier, les bons destinataires, la
--    charge utile que lit l'Edge Function, **une fois par jour et par planning**
--    par la seule clé de dédoublonnage — et la même définition du retard que
--    `v_schedule_progress.assignments_late` et `remind_schedule`.
-- 8. Le rapport ne tombe pas au milieu de la nuit locale, y compris pour une
--    caserne d'outre-mer (question soulevée par le ticket 041).
-- 9. Les deux tâches sont planifiées, qualifiées, sans argument, et leurs
--    fonctions ne sont appelables ni par `anon` ni par `authenticated`.
--
-- Rien ici n'appelle l'Edge Function : `notify_post` est remplacée, le temps du
-- test, par une version qui ne fait pas d'appel HTTP — même procédé que
-- `notifications_test.sql`. La CI n'a ni edge-runtime ni Kong.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : deux casernes à soi, sur l'année 2029 que ni le seed ni les autres
-- fichiers ne touchent. La section 6 travaille en revanche autour de `now()` :
-- `remind_schedule` lit l'horloge réelle et n'accepte pas d'instant de
-- référence, la tester à une date fictive ne prouverait rien.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_rel;

create function tests_rel.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

create function tests_rel.egal(p_obtenu anyelement, p_attendu anyelement, p_label text) returns void
language plpgsql as $$
begin
  if p_obtenu is distinct from p_attendu then
    raise exception 'ECHEC : % — obtenu [%], attendu [%]', p_label, p_obtenu, p_attendu;
  end if;
  raise notice '  ok   % = %', p_label, coalesce(p_obtenu::text, 'NULL');
end $$;

create function tests_rel.denied(p_sql text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — aucune erreur levée', p_label;
exception
  when insufficient_privilege then
    raise notice '  ok   % (refusé : %)', p_label, sqlerrm;
end $$;

grant usage on schema tests_rel to authenticated, anon;
grant execute on all functions in schema tests_rel to authenticated, anon;

-- ---------------------------------------------------------------------------
-- `notify_post` sans réseau — même substitution que `notifications_test.sql`.
-- L'effet de bord sur la file est conservé (compteur de tentatives, verrou) :
-- c'est lui qui prouve qu'un rejeu ne repose rien. Seul l'appel HTTP est coupé.
-- ---------------------------------------------------------------------------
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
\echo '=== Relances automatiques (0021) ==='

-- ===========================================================================
-- Fixtures
-- ===========================================================================
-- R « CIS Relance », Europe/Paris, délais par défaut 24 / 48 / 72.
--   R0 admin, R1 R2 R3 membres actifs, R4 membre **désactivé**.
--   Planning de mai 2029, publié, propositions envoyées le 20 avril à 08:00 UTC.
--     T+24 h = 21 avril 08:00 UTC | T+48 h = 22 avril | T+72 h = 23 avril
--   R1 porte **deux** gardes : c'est lui qui prouve le regroupement.
--   R4, désactivé, porte une garde : il ne doit jamais être relancé, mais il
--   doit apparaître dans le rapport aux administrateurs — un trou se voit.
--   Un créneau témoin sans attribution empêche le planning de se valider tout
--   seul quand une garde est acceptée en section 3.
--
-- Q « CIS Relance Gambier », Pacific/Gambier (UTC-9), délais 2 / 4 / 6.
--   Son planning est publié mais vide : les sections 5 et 8 lui posent leur
--   attribution dans leur propre point de reprise, pour que les autres
--   sections n'aient à raisonner que sur une seule caserne.

insert into stations (id, name, slug, timezone, settings) values
  ('99999999-0000-4000-8000-000000000001', 'CIS Relance', 'cis-relance', 'Europe/Paris',
   '{"day_start": "07:00", "day_end": "19:00",
     "required_day": 1, "required_night": 1,
     "required_overrides": {},
     "availability_deadline_day": 15,
     "response_reminder_hours": 24, "response_email_hours": 48,
     "late_report_hours": 72}'::jsonb),
  ('90909090-0000-4000-8000-000000000001', 'CIS Relance Gambier', 'cis-relance-gambier', 'Pacific/Gambier',
   '{"day_start": "07:00", "day_end": "19:00",
     "required_day": 1, "required_night": 1,
     "required_overrides": {},
     "availability_deadline_day": 15,
     "response_reminder_hours": 2, "response_email_hours": 4,
     "late_report_hours": 6}'::jsonb);

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
  ('99999999-0000-4000-8000-000000000100'::uuid, 'admin@relance.test',   'Rachel', 'Rey'),
  ('99999999-0000-4000-8000-000000000101'::uuid, 'membre1@relance.test', 'Bruno',  'Bertin'),
  ('99999999-0000-4000-8000-000000000102'::uuid, 'membre2@relance.test', 'Chloé',  'Colin'),
  ('99999999-0000-4000-8000-000000000103'::uuid, 'membre3@relance.test', 'Damien', 'Denis'),
  ('99999999-0000-4000-8000-000000000104'::uuid, 'ancien@relance.test',  'Eve',    'Evrard'),
  ('90909090-0000-4000-8000-000000000100'::uuid, 'admin@gambier.test',   'Gaël',   'Gauthier'),
  ('90909090-0000-4000-8000-000000000101'::uuid, 'membre1@gambier.test', 'Hina',   'Hart')
) as u(id, email, first_name, last_name);

insert into memberships (station_id, user_id, role, status, display_name) values
  ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000100', 'admin',  'active',   'Rachel R.'),
  ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000101', 'member', 'active',   'Bruno B.'),
  ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000102', 'member', 'active',   'Chloé C.'),
  ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000103', 'member', 'active',   'Damien D.'),
  ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000104', 'member', 'disabled', 'Eve E.'),
  ('90909090-0000-4000-8000-000000000001', '90909090-0000-4000-8000-000000000100', 'admin',  'active',   'Gaël G.'),
  ('90909090-0000-4000-8000-000000000001', '90909090-0000-4000-8000-000000000101', 'member', 'active',   'Hina H.');

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('99999999-0000-4000-8000-000000000205', '99999999-0000-4000-8000-000000000001', 2029, 5, 'locked', '2029-04-15 23:59:59+02'),
  ('99999999-0000-4000-8000-000000000206', '99999999-0000-4000-8000-000000000001', 2029, 6, 'locked', '2029-05-15 23:59:59+02'),
  ('90909090-0000-4000-8000-000000000205', '90909090-0000-4000-8000-000000000001', 2029, 5, 'locked', '2029-04-15 23:59:59-09');

-- Les plannings sont insérés directement en `published` : `schedules_guard_transition`
-- (0019) n'est qu'un déclencheur d'update, et la publication elle-même est déjà
-- couverte par `publication_test.sql`. Ce qui est en test ici commence après.
insert into schedules (id, station_id, period_id, status, created_by, published_at) values
  ('99999999-0000-4000-8000-000000000305', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000205', 'published',
   '99999999-0000-4000-8000-000000000100', '2029-04-20 08:00:00+00'),
  ('90909090-0000-4000-8000-000000000305', '90909090-0000-4000-8000-000000000001',
   '90909090-0000-4000-8000-000000000205', 'published',
   '90909090-0000-4000-8000-000000000100', '2029-04-20 08:00:00+00');

insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  -- Caserne R
  ('99999999-0000-4000-8000-000000000401', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000305', '2029-05-02', 'day',   1),
  ('99999999-0000-4000-8000-000000000402', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000305', '2029-05-03', 'night', 1),
  ('99999999-0000-4000-8000-000000000403', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000305', '2029-05-05', 'day',   1),
  ('99999999-0000-4000-8000-000000000404', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000305', '2029-05-06', 'day',   1),
  ('99999999-0000-4000-8000-000000000405', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000305', '2029-05-07', 'night', 1),
  -- Le créneau témoin : jamais pourvu, donc le planning ne se valide jamais seul.
  ('99999999-0000-4000-8000-000000000409', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000305', '2029-05-10', 'day',   1),
  -- Caserne Q : un témoin, et rien d'autre par défaut.
  ('90909090-0000-4000-8000-000000000409', '90909090-0000-4000-8000-000000000001',
   '90909090-0000-4000-8000-000000000305', '2029-05-10', 'day',   1);

insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by) values
  -- R1 : deux gardes, une seule notification attendue.
  ('99999999-0000-4000-8000-000000000501', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000401', '99999999-0000-4000-8000-000000000101',
   'proposed', '2029-04-20 08:00:00+00', '99999999-0000-4000-8000-000000000100'),
  ('99999999-0000-4000-8000-000000000502', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000402', '99999999-0000-4000-8000-000000000101',
   'proposed', '2029-04-20 08:00:00+00', '99999999-0000-4000-8000-000000000100'),
  ('99999999-0000-4000-8000-000000000503', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000403', '99999999-0000-4000-8000-000000000102',
   'proposed', '2029-04-20 08:00:00+00', '99999999-0000-4000-8000-000000000100'),
  ('99999999-0000-4000-8000-000000000504', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000404', '99999999-0000-4000-8000-000000000103',
   'proposed', '2029-04-20 08:00:00+00', '99999999-0000-4000-8000-000000000100'),
  -- R4 est désactivé : jamais relancé, toujours compté dans le rapport.
  ('99999999-0000-4000-8000-000000000505', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000405', '99999999-0000-4000-8000-000000000104',
   'proposed', '2029-04-20 08:00:00+00', '99999999-0000-4000-8000-000000000100');

select tests_rel.egal(
  (select count(*)::int from assignments
    where station_id = '99999999-0000-4000-8000-000000000001' and status = 'proposed'),
  5, 'décor : cinq propositions sans réponse dans la caserne R');

-- ===========================================================================
-- 1. Le palier push
-- ===========================================================================
\echo ''
\echo '--- 1. Palier push : à response_reminder_hours, une notification par membre'
savepoint s1;

select tests_rel.egal(
  cron_assignment_reminders('2029-04-21 07:59:00+00'), 0,
  'une minute avant l''échéance : rien ne part');

select tests_rel.egal(
  (select count(*)::int from notification_outbox where type = 'assignment_reminder'),
  0, 'et la file est restée vide');

select tests_rel.egal(
  (select count(*)::int from assignments
    where station_id = '99999999-0000-4000-8000-000000000001' and reminder_count > 0),
  0, 'aucune attribution marquée avant l''échéance');

-- À l'échéance : trois membres actifs relancés, R1 une seule fois pour ses deux
-- gardes. Quatre attributions marquées, trois notifications.
select tests_rel.egal(
  cron_assignment_reminders('2029-04-21 08:00:00+00'), 3,
  'à l''échéance : trois notifications, une par membre actif sans réponse');

select tests_rel.egal(
  (select count(*)::int from notification_outbox
    where type = 'assignment_reminder'
      and dedupe_key like 'assignment_reminder:auto:push:99999999-0000-4000-8000-000000000305:%'),
  1, 'un seul envoi pour le planning : les destinataires sont groupés dedans');

do $$
declare
  ligne notification_outbox;
begin
  select * into ligne from notification_outbox
   where dedupe_key like 'assignment_reminder:auto:push:99999999-0000-4000-8000-000000000305:%';

  perform tests_rel.egal(ligne.station_id, '99999999-0000-4000-8000-000000000001'::uuid,
    'la demande porte la caserne');
  perform tests_rel.egal(ligne.channels, array['push', 'inapp'],
    'palier push : canaux push + inapp (docs/WORKFLOWS.md § 8)');
  perform tests_rel.egal(ligne.payload, jsonb_build_object('period', '2029-05'),
    'la charge utile commune porte le mois, comme le lit send-notification');
  perform tests_rel.egal(jsonb_array_length(ligne.recipients), 3,
    'trois destinataires, pas quatre : R1 n''apparaît qu''une fois');
  perform tests_rel.egal(
    ligne.dedupe_key,
    'assignment_reminder:auto:push:99999999-0000-4000-8000-000000000305:2029-04-21T08',
    'la clé porte le palier, le planning et la fenêtre horaire du tir');

  -- Le regroupement : les deux gardes de R1 dans une seule entrée, triées.
  perform tests_rel.egal(
    (select d -> 'payload'
       from jsonb_array_elements(ligne.recipients) d
      where d ->> 'user_id' = '99999999-0000-4000-8000-000000000101'),
    jsonb_build_object('shifts', jsonb_build_array(
      jsonb_build_object('date', '2029-05-02', 'slot', 'day'),
      jsonb_build_object('date', '2029-05-03', 'slot', 'night'))),
    'R1 reçoit une entrée qui liste ses deux gardes, dans l''ordre');

  perform tests_rel.check(
    not exists (
      select 1 from jsonb_array_elements(ligne.recipients) d
       where d ->> 'user_id' = '99999999-0000-4000-8000-000000000104'),
    'le membre désactivé n''est pas relancé : sa proposition n''a plus de destinataire');
end $$;

-- La marque suit l'envoi, sur les quatre attributions parties et sur elles seules.
select tests_rel.egal(
  (select count(*)::int from assignments
    where station_id = '99999999-0000-4000-8000-000000000001'
      and reminder_count = 1
      and last_reminder_at = '2029-04-21 08:00:00+00'),
  4, 'les quatre attributions relancées portent reminder_count = 1 et l''horodatage');

select tests_rel.egal(
  (select reminder_count from assignments
    where id = '99999999-0000-4000-8000-000000000505'),
  0, 'celle du membre désactivé n''est pas marquée');

rollback to savepoint s1;
release savepoint s1;

-- ===========================================================================
-- 2. Le palier courriel
-- ===========================================================================
\echo ''
\echo '--- 2. Palier courriel : à response_email_hours, puis plus rien'
savepoint s2;

select tests_rel.egal(
  cron_assignment_reminders('2029-04-21 08:00:00+00'), 3, 'le push d''abord');

select tests_rel.egal(
  cron_assignment_reminders('2029-04-22 07:59:00+00'), 0,
  'une minute avant l''échéance du courriel : rien');

select tests_rel.egal(
  cron_assignment_reminders('2029-04-22 08:00:00+00'), 3,
  'à T+48 h : le courriel part aux trois mêmes membres');

do $$
declare
  ligne notification_outbox;
begin
  select * into ligne from notification_outbox
   where dedupe_key like 'assignment_reminder:auto:email:%';

  perform tests_rel.egal(ligne.channels, array['email', 'inapp'],
    'palier courriel : canaux email + inapp');
  perform tests_rel.egal(jsonb_array_length(ligne.recipients), 3,
    'toujours groupé par membre');
end $$;

select tests_rel.egal(
  (select count(*)::int from assignments
    where station_id = '99999999-0000-4000-8000-000000000001' and reminder_count = 2),
  4, 'les quatre attributions sont passées au second palier');

-- **Deux paliers, pas une sonnerie horaire.** Une fois le courriel parti, la
-- tâche doit se taire, même trois jours plus tard.
select tests_rel.egal(
  cron_assignment_reminders('2029-04-22 09:00:00+00'), 0,
  'une heure plus tard : rien');
select tests_rel.egal(
  cron_assignment_reminders('2029-04-25 08:00:00+00'), 0,
  'trois jours plus tard : toujours rien — il n''y a que deux paliers');

select tests_rel.egal(
  (select count(*)::int from notification_outbox where type = 'assignment_reminder'),
  2, 'deux demandes en tout : un push, un courriel');

-- Le rattrapage : l'ordonnanceur arrêté trois jours, les deux délais franchis
-- d'un coup. Le courriel passant avant le push dans un même tir, l'escalier
-- reste un escalier — une marche par tir, jamais les deux dans la même minute.
rollback to savepoint s2;

select tests_rel.egal(
  cron_assignment_reminders('2029-04-25 08:00:00+00'), 3,
  'reprise après panne : le premier tir ne fait partir que le push');

select tests_rel.egal(
  (select count(*)::int from notification_outbox
    where dedupe_key like 'assignment_reminder:auto:email:%'),
  0, 'et rien en courriel dans le même tir');

select tests_rel.egal(
  cron_assignment_reminders('2029-04-25 09:00:00+00'), 3,
  'le tir suivant rattrape le courriel');

rollback to savepoint s2;
release savepoint s2;

-- ===========================================================================
-- 3. Qui a répondu ne reçoit plus rien
-- ===========================================================================
\echo ''
\echo '--- 3. Une attribution qui a reçu une réponse ne reçoit plus rien'
savepoint s3;

update assignments
   set status = 'accepted', responded_at = '2029-04-20 12:00:00+00'
 where id = '99999999-0000-4000-8000-000000000503';

update assignments
   set status = 'declined', responded_at = '2029-04-20 13:00:00+00',
       decline_reason = 'Indisponible ce jour-là'
 where id = '99999999-0000-4000-8000-000000000504';

select tests_rel.egal(
  (select status::text from schedules where id = '99999999-0000-4000-8000-000000000305'),
  'published', 'le créneau témoin garde le planning en published : rien ne se valide tout seul');

select tests_rel.egal(
  cron_assignment_reminders('2029-04-21 08:00:00+00'), 1,
  'une seule notification : seul R1 n''a pas répondu');

do $$
declare
  ligne notification_outbox;
begin
  select * into ligne from notification_outbox
   where dedupe_key like 'assignment_reminder:auto:push:%';
  perform tests_rel.egal(
    ligne.recipients -> 0 ->> 'user_id', '99999999-0000-4000-8000-000000000101',
    'et c''est bien R1, celui qui n''a rien dit');
end $$;

select tests_rel.egal(
  (select max(reminder_count) from assignments
    where id in ('99999999-0000-4000-8000-000000000503',
                 '99999999-0000-4000-8000-000000000504')),
  0, 'ni l''acceptation ni le refus ne sont marqués : ils ne reçoivent plus rien');

-- Et cela vaut pour le second palier comme pour le premier : une réponse ferme
-- la porte définitivement, elle ne diffère pas la relance.
select tests_rel.egal(
  cron_assignment_reminders('2029-04-22 08:00:00+00'), 1,
  'à T+48 h aussi : seul R1');

-- Répondre **entre** les deux paliers arrête le courriel.
update assignments
   set status = 'accepted', responded_at = '2029-04-21 20:00:00+00'
 where id = '99999999-0000-4000-8000-000000000501';
update assignments
   set status = 'declined', responded_at = '2029-04-21 20:00:00+00'
 where id = '99999999-0000-4000-8000-000000000502';

select tests_rel.egal(
  cron_assignment_reminders('2029-04-23 08:00:00+00'), 0,
  'une réponse arrivée entre les deux paliers annule le courriel');

rollback to savepoint s3;
release savepoint s3;

-- ===========================================================================
-- 4. Pas de doublon, et surtout pas de marque sans envoi
-- ===========================================================================
\echo ''
\echo '--- 4. Idempotence : le rejeu n''envoie rien et ne marque rien'
savepoint s4;

select tests_rel.egal(
  cron_assignment_reminders('2029-04-21 08:00:00+00'), 3, 'premier tir');

select tests_rel.egal(
  cron_assignment_reminders('2029-04-21 08:00:00+00'), 0,
  'rejeu à la même seconde : rien de plus');

select tests_rel.egal(
  cron_assignment_reminders('2029-04-21 08:47:00+00'), 0,
  'rejeu dans la même heure : rien de plus — même fenêtre, même clé');

select tests_rel.egal(
  (select count(*)::int from notification_outbox where type = 'assignment_reminder'),
  1, 'une seule demande en file');

-- Le rejeu ne repose pas non plus la demande vers l'Edge Function : un
-- `attempts` qui monterait ferait repartir la notification.
select tests_rel.check(
  (select attempts = 1 from notification_outbox where type = 'assignment_reminder'),
  'le rejeu ne repose pas la demande : aucun doublon d''envoi');

-- **Le point de la revue du 019.** Une demande écartée par la clé ne doit
-- toucher ni le compteur ni l'horodatage : sinon, un rejeu de l'ordonnanceur
-- ferait croire à un palier franchi et le courriel partirait sur une base fausse.
select tests_rel.egal(
  (select max(reminder_count) from assignments
    where station_id = '99999999-0000-4000-8000-000000000001'),
  1, 'le compteur reste à 1 malgré les trois tirs');

-- On le vérifie autrement : en forçant une ligne de file sous la clé de l'heure
-- suivante, un tir qui aurait dû envoyer ne marque rien du tout.
insert into notification_outbox (station_id, type, recipients, payload, dedupe_key)
values ('99999999-0000-4000-8000-000000000001', 'assignment_reminder',
        jsonb_build_array(jsonb_build_object('user_id', '99999999-0000-4000-8000-000000000100')),
        '{}'::jsonb,
        'assignment_reminder:auto:email:99999999-0000-4000-8000-000000000305:2029-04-22T08');

select tests_rel.egal(
  cron_assignment_reminders('2029-04-22 08:00:00+00'), 0,
  'la clé déjà prise coupe l''envoi du courriel');

select tests_rel.egal(
  (select max(reminder_count) from assignments
    where station_id = '99999999-0000-4000-8000-000000000001'),
  1, 'et le palier n''est pas franchi : la marque suit l''envoi, jamais l''inverse');

-- La preuve que ce n'était pas un faux positif : à l'heure suivante, le
-- courriel part et le palier se franchit pour de bon.
select tests_rel.egal(
  cron_assignment_reminders('2029-04-22 09:00:00+00'), 3,
  'à la fenêtre suivante, le courriel part');
select tests_rel.egal(
  (select max(reminder_count) from assignments
    where station_id = '99999999-0000-4000-8000-000000000001'),
  2, 'et le palier est franchi');

rollback to savepoint s4;
release savepoint s4;

-- ===========================================================================
-- 5. Les délais sont ceux de chaque caserne
-- ===========================================================================
\echo ''
\echo '--- 5. Chaque caserne a ses délais (settings, ticket 010)'
savepoint s5;

insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  ('90909090-0000-4000-8000-000000000401', '90909090-0000-4000-8000-000000000001',
   '90909090-0000-4000-8000-000000000305', '2029-05-04', 'day', 1);

insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by) values
  ('90909090-0000-4000-8000-000000000501', '90909090-0000-4000-8000-000000000001',
   '90909090-0000-4000-8000-000000000401', '90909090-0000-4000-8000-000000000101',
   'proposed', '2029-04-20 08:00:00+00', '90909090-0000-4000-8000-000000000100');

-- Même instant de proposition, deux mondes : Q est réglée à 2 h, R à 24 h.
select tests_rel.egal(
  cron_assignment_reminders('2029-04-20 10:00:00+00'), 1,
  'T+2 h : Gambier relance, Paris ne bouge pas');

select tests_rel.egal(
  (select ligne.station_id from notification_outbox ligne
    where ligne.type = 'assignment_reminder'),
  '90909090-0000-4000-8000-000000000001'::uuid,
  'et la seule demande en file est celle de Gambier');

select tests_rel.egal(
  (select max(reminder_count) from assignments
    where station_id = '99999999-0000-4000-8000-000000000001'),
  0, 'aucune attribution de Paris n''est marquée');

select tests_rel.egal(
  cron_assignment_reminders('2029-04-20 12:00:00+00'), 1,
  'T+4 h : Gambier passe au courriel, Paris dort toujours');

select tests_rel.check(
  (select channels = array['email', 'inapp'] from notification_outbox
    where dedupe_key like 'assignment_reminder:auto:email:%'),
  'et c''est bien un courriel');

select tests_rel.egal(
  cron_assignment_reminders('2029-04-21 08:00:00+00'), 3,
  'T+24 h : Paris relance enfin, Gambier a fini');

select tests_rel.egal(
  (select count(*)::int from notification_outbox where type = 'assignment_reminder'),
  3, 'trois demandes : push Gambier, courriel Gambier, push Paris');

rollback to savepoint s5;
release savepoint s5;

-- ===========================================================================
-- 6. Cohabitation avec la relance manuelle (remind_schedule, 0019)
-- ===========================================================================
-- `remind_schedule` lit `now()` et n'accepte pas d'instant de référence : cette
-- section travaille donc autour de l'horloge réelle, sur un planning à elle.
-- C'est la seule façon d'éprouver les deux gestes ensemble pour de vrai.
\echo ''
\echo '--- 6. Une relance manuelle ne fait sauter aucun palier automatique'
savepoint s6;

insert into schedules (id, station_id, period_id, status, created_by, published_at) values
  ('99999999-0000-4000-8000-000000000306', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000206', 'published',
   '99999999-0000-4000-8000-000000000100', now());

insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  ('99999999-0000-4000-8000-000000000411', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000306', '2029-06-04', 'day', 1),
  ('99999999-0000-4000-8000-000000000419', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000306', '2029-06-10', 'day', 1);

insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by) values
  ('99999999-0000-4000-8000-000000000511', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000411', '99999999-0000-4000-8000-000000000101',
   'proposed', now(), '99999999-0000-4000-8000-000000000100');

-- Le bouton « Relancer maintenant », pour de vrai, sous l'identité de l'admin.
set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  r jsonb;
begin
  r := remind_schedule('99999999-0000-4000-8000-000000000306', true);
  perform tests_rel.egal(r ->> 'ok', 'true', 'la relance manuelle aboutit');
  perform tests_rel.egal((r ->> 'assignments')::int, 1, 'elle marque l''attribution');
end $$;

reset role;

select tests_rel.egal(
  (select reminder_count from assignments
    where id = '99999999-0000-4000-8000-000000000511'),
  1, 'le compteur partagé est à 1 après la relance manuelle');

-- a) Le palier push est sauté : le pompier vient d'être relancé, deux poussées
--    à quatorze heures d'écart pour la même garde seraient du harcèlement.
select tests_rel.egal(
  cron_assignment_reminders(now() + interval '25 hours'), 0,
  'T+25 h : le push automatique est sauté, la relance manuelle en tenait lieu');

select tests_rel.egal(
  (select count(*)::int from notification_outbox
    where dedupe_key like 'assignment_reminder:auto:push:99999999-0000-4000-8000-000000000306:%'),
  0, 'aucune demande de palier push pour ce planning');

-- b) Le courriel part quand même. C'est la décision documentée en tête de 0021 :
--    le palier courriel se lit « au moins une relance, et aucune depuis
--    l'échéance », pas « exactement une relance ».
select tests_rel.egal(
  cron_assignment_reminders(now() + interval '49 hours'), 1,
  'T+49 h : le courriel part, la relance manuelle ne l''a pas escamoté');

select tests_rel.check(
  (select channels = array['email', 'inapp'] from notification_outbox
    where dedupe_key like 'assignment_reminder:auto:email:99999999-0000-4000-8000-000000000306:%'),
  'et c''est bien le courriel du second palier');

select tests_rel.egal(
  (select reminder_count from assignments
    where id = '99999999-0000-4000-8000-000000000511'),
  2, 'le compteur monte à 2');

-- c) Et il ne repart pas ensuite : `last_reminder_at` est désormais postérieur à
--    l'échéance du courriel, ce qui referme le palier.
select tests_rel.egal(
  cron_assignment_reminders(now() + interval '72 hours'), 0,
  'et le courriel ne se répète pas les heures suivantes');

rollback to savepoint s6;

-- d) **Le cas qui a dicté la condition.** Deux clics de l'administrateur à deux
--    heures différentes : le compteur vaut 2, et un palier écrit
--    `reminder_count = 1` — la lettre du diagramme de docs/WORKFLOWS.md § 6 —
--    aurait privé ce pompier du courriel pour toujours. Le second clic est
--    simulé en retirant la demande de la file : c'est ce que fait le passage à
--    l'heure suivante, et l'idempotence horaire de `remind_schedule` est déjà
--    couverte par `publication_test.sql § 5`.
insert into schedules (id, station_id, period_id, status, created_by, published_at) values
  ('99999999-0000-4000-8000-000000000306', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000206', 'published',
   '99999999-0000-4000-8000-000000000100', now());

insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  ('99999999-0000-4000-8000-000000000411', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000306', '2029-06-04', 'day', 1),
  ('99999999-0000-4000-8000-000000000419', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000306', '2029-06-10', 'day', 1);

insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by) values
  ('99999999-0000-4000-8000-000000000511', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000411', '99999999-0000-4000-8000-000000000101',
   'proposed', now(), '99999999-0000-4000-8000-000000000100');

set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000100","role":"authenticated"}';
select remind_schedule('99999999-0000-4000-8000-000000000306', true) is not null as premier_clic \gset
reset role;

delete from notification_outbox
 where dedupe_key like 'assignment_reminder:99999999-0000-4000-8000-000000000306:%';

set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000100","role":"authenticated"}';
select remind_schedule('99999999-0000-4000-8000-000000000306', true) is not null as second_clic \gset
reset role;

select tests_rel.egal(
  (select reminder_count from assignments
    where id = '99999999-0000-4000-8000-000000000511'),
  2, 'deux clics : le compteur partagé vaut 2');

select tests_rel.egal(
  cron_assignment_reminders(now() + interval '49 hours'), 1,
  'et le courriel part quand même — aucun nombre de clics ne le fait sauter');

rollback to savepoint s6;
release savepoint s6;

-- ===========================================================================
-- 7. Le rapport aux administrateurs
-- ===========================================================================
\echo ''
\echo '--- 7. late_responders : au troisième délai, aux admins, une fois par jour'
savepoint s7;

select tests_rel.egal(
  cron_late_responders_report('2029-04-23 07:59:00+00'), 0,
  'une minute avant T+72 h : aucun rapport');

-- Le seuil est strict, exactement comme `v_schedule_progress.assignments_late` :
-- « depuis **plus de** late_report_hours ». À la seconde pile, rien encore.
select tests_rel.egal(
  cron_late_responders_report('2029-04-23 08:00:00+00'), 0,
  'à la seconde pile : pas encore — le retard se compte en « plus de »');

select tests_rel.egal(
  cron_late_responders_report('2029-04-23 08:01:00+00'), 1,
  'une minute après : un rapport (10:01 heure de Paris, en pleine journée)');

do $$
declare
  ligne notification_outbox;
begin
  select * into ligne from notification_outbox where type = 'late_responders';

  perform tests_rel.egal(ligne.station_id, '99999999-0000-4000-8000-000000000001'::uuid,
    'le rapport porte la caserne');
  perform tests_rel.egal(
    ligne.dedupe_key,
    'late_responders:99999999-0000-4000-8000-000000000305:2029-04-23',
    'la clé est « planning : date locale de la caserne »');
  perform tests_rel.egal(ligne.channels, null::text[],
    'canaux laissés au type : « inapp + push » est déclaré dans CANAUX_PAR_DEFAUT');

  -- Les administrateurs actifs, et eux seuls.
  perform tests_rel.egal(ligne.recipients,
    jsonb_build_array(jsonb_build_object(
      'user_id', '99999999-0000-4000-8000-000000000100')),
    'destinataire : l''administrateur de la caserne, personne d''autre');

  -- Exactement ce que lit `construireContenu` pour `late_responders`.
  perform tests_rel.egal(
    ligne.payload - 'schedule_id',
    jsonb_build_object(
      'period',        '2029-05',
      'pending_count', 5,
      'hours',         72,
      'members',       jsonb_build_array('Bruno B.', 'Chloé C.', 'Damien D.', 'Eve E.')),
    'la charge utile porte le mois, le nombre, le délai et les noms de la caserne');

  perform tests_rel.egal(ligne.payload ->> 'schedule_id',
    '99999999-0000-4000-8000-000000000305',
    'et le planning, pour le lien profond du suivi admin');
end $$;

-- **Une fois par jour et par planning**, par la seule clé de dédoublonnage.
select tests_rel.egal(
  cron_late_responders_report('2029-04-23 09:00:00+00'), 0,
  'une heure plus tard le même jour : rien');
select tests_rel.egal(
  cron_late_responders_report('2029-04-23 20:00:00+00'), 0,
  'le soir du même jour : toujours rien');
select tests_rel.egal(
  (select count(*)::int from notification_outbox where type = 'late_responders'),
  1, 'une seule demande en file pour cette journée');

select tests_rel.egal(
  cron_late_responders_report('2029-04-24 08:00:00+00'), 1,
  'le lendemain : un nouveau rapport, le retard dure toujours');
select tests_rel.egal(
  (select count(*)::int from notification_outbox where type = 'late_responders'),
  2, 'deux demandes, une par journée locale');

-- Les réponses sortent du compte, y compris celle d'un membre désactivé —
-- le rapport dit ce qui reste à faire, pas ce qui a été proposé.
update assignments set status = 'accepted', responded_at = '2029-04-24 09:00:00+00'
 where id = '99999999-0000-4000-8000-000000000503';
update assignments set status = 'declined', responded_at = '2029-04-24 09:00:00+00'
 where id = '99999999-0000-4000-8000-000000000505';

select tests_rel.egal(
  cron_late_responders_report('2029-04-25 08:00:00+00'), 1, 'un rapport le surlendemain');

do $$
declare
  ligne notification_outbox;
begin
  select * into ligne from notification_outbox
   where dedupe_key = 'late_responders:99999999-0000-4000-8000-000000000305:2029-04-25';
  perform tests_rel.egal((ligne.payload ->> 'pending_count')::int, 3,
    'trois propositions restent sans réponse');
  perform tests_rel.egal(ligne.payload -> 'members',
    jsonb_build_array('Bruno B.', 'Damien D.'),
    'et seuls ceux qui n''ont pas répondu sont nommés');
end $$;

-- Plus personne en retard, plus de rapport : la tâche ne réveille pas un
-- administrateur pour lui dire que tout va bien.
update assignments set status = 'accepted', responded_at = '2029-04-25 09:00:00+00'
 where station_id = '99999999-0000-4000-8000-000000000001' and status = 'proposed';

select tests_rel.egal(
  cron_late_responders_report('2029-04-26 08:00:00+00'), 0,
  'tout le monde a répondu : aucun rapport');

rollback to savepoint s7;

-- ---------------------------------------------------------------------------
-- 7 bis. Une seule définition du retard dans tout le produit
-- ---------------------------------------------------------------------------
-- `v_schedule_progress.assignments_late` (0018), `remind_schedule` (0019) et
-- `cron_late_responders_report` (0021) doivent compter la même chose. La vue et
-- la fonction manuelle lisent `now()` : le décor est donc recalé sur l'horloge
-- réelle, avec une heure de référence en pleine journée à Paris.
\echo ''
\echo '--- 7 bis. Le retard : trois lecteurs, une seule règle'

update assignments
   set proposed_at = date_trunc('day', now()) + interval '10 hours' - interval '100 hours'
 where station_id = '99999999-0000-4000-8000-000000000001';

select tests_rel.egal(
  (select assignments_late from v_schedule_progress
    where schedule_id = '99999999-0000-4000-8000-000000000305'),
  5, 'la vue de suivi compte cinq retards');

select cron_late_responders_report(date_trunc('day', now()) + interval '10 hours') as n_rapport \gset

select tests_rel.egal(:'n_rapport'::int, 1, 'la tâche envoie son rapport');

select tests_rel.egal(
  (select (payload ->> 'pending_count')::int from notification_outbox
    where type = 'late_responders'),
  5, 'et elle compte les mêmes cinq retards que la vue');

set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  r jsonb;
begin
  -- Sans `p_tout` : la relance manuelle ne vise que les retardataires.
  r := remind_schedule('99999999-0000-4000-8000-000000000305');
  perform tests_rel.egal((r ->> 'assignments')::int, 5,
    'et la relance manuelle vise exactement les mêmes cinq attributions');
end $$;

reset role;

rollback to savepoint s7;
release savepoint s7;

-- ===========================================================================
-- 8. Le rapport ne tombe pas au milieu de la nuit locale (ticket 041)
-- ===========================================================================
\echo ''
\echo '--- 8. Fenêtre horaire locale : jamais un push à 3 h du matin'
savepoint s8;

insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  ('90909090-0000-4000-8000-000000000401', '90909090-0000-4000-8000-000000000001',
   '90909090-0000-4000-8000-000000000305', '2029-05-04', 'day', 1);

insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by) values
  ('90909090-0000-4000-8000-000000000501', '90909090-0000-4000-8000-000000000001',
   '90909090-0000-4000-8000-000000000401', '90909090-0000-4000-8000-000000000101',
   'proposed', '2029-04-20 08:00:00+00', '90909090-0000-4000-8000-000000000100');

-- Gambier est à UTC-9 : à 14:00 UTC il y est 05:00, et le retard de 6 h est
-- pourtant franchi. Sans fenêtre, le rapport partait en pleine nuit.
select tests_rel.egal(
  (select extract(hour from timestamptz '2029-04-20 14:01:00+00'
                            at time zone 'Pacific/Gambier')::int),
  5, 'décor : 14:01 UTC, il est 5 h du matin à Gambier');

select tests_rel.egal(
  cron_late_responders_report('2029-04-20 14:01:00+00'), 0,
  'le retard est franchi, mais on ne réveille personne à 5 h');

select tests_rel.egal(
  cron_late_responders_report('2029-04-20 16:00:00+00'), 0,
  '7 h du matin : toujours trop tôt');

select tests_rel.egal(
  cron_late_responders_report('2029-04-20 17:00:00+00'), 1,
  '8 h du matin à Gambier : le rapport part');

select tests_rel.egal(
  (select dedupe_key from notification_outbox where type = 'late_responders'),
  'late_responders:90909090-0000-4000-8000-000000000305:2029-04-20',
  'et sa clé porte la date **locale** de la caserne, pas celle du serveur');

-- Le bord haut de la fenêtre : 21 h locale, c'est non ; le rapport attend le
-- lendemain matin. Gambier UTC-9 : 21:00 local = 06:00 UTC le jour suivant.
rollback to savepoint s8;

insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  ('90909090-0000-4000-8000-000000000401', '90909090-0000-4000-8000-000000000001',
   '90909090-0000-4000-8000-000000000305', '2029-05-04', 'day', 1);
insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by) values
  ('90909090-0000-4000-8000-000000000501', '90909090-0000-4000-8000-000000000001',
   '90909090-0000-4000-8000-000000000401', '90909090-0000-4000-8000-000000000101',
   'proposed', '2029-04-20 08:00:00+00', '90909090-0000-4000-8000-000000000100');

select tests_rel.egal(
  cron_late_responders_report('2029-04-21 05:00:00+00'), 1,
  '20 h locale : encore dans la fenêtre');

rollback to savepoint s8;

insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  ('90909090-0000-4000-8000-000000000401', '90909090-0000-4000-8000-000000000001',
   '90909090-0000-4000-8000-000000000305', '2029-05-04', 'day', 1);
insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by) values
  ('90909090-0000-4000-8000-000000000501', '90909090-0000-4000-8000-000000000001',
   '90909090-0000-4000-8000-000000000401', '90909090-0000-4000-8000-000000000101',
   'proposed', '2029-04-20 08:00:00+00', '90909090-0000-4000-8000-000000000100');

select tests_rel.egal(
  cron_late_responders_report('2029-04-21 06:00:00+00'), 0,
  '21 h locale : c''est non, ce sera demain matin');

-- Les relances d'attribution, elles, restent horaires et sans fenêtre : un push
-- de rappel suit la proposition de quelques heures et n'a pas d'heure de bureau.
-- On vérifie seulement qu'elles ne se sont pas mises à dépendre du fuseau.
select tests_rel.egal(
  cron_assignment_reminders('2029-04-20 10:00:00+00'), 1,
  'le palier push de Gambier part à T+2 h, quelle que soit l''heure locale');

rollback to savepoint s8;
release savepoint s8;

-- ===========================================================================
-- 9. Les tâches planifiées et les droits
-- ===========================================================================
\echo ''
\echo '--- 9. pg_cron et exécution réservée'

select tests_rel.check(
  (select command = 'select public.cron_assignment_reminders();'
      and schedule = '15 * * * *'
      and active
     from cron.job where jobname = 'assignment_reminders'),
  'la tâche assignment_reminders est planifiée, horaire, qualifiée et sans argument');

select tests_rel.check(
  (select command = 'select public.cron_late_responders_report();'
      and schedule = '45 * * * *'
      and active
     from cron.job where jobname = 'late_responders_report'),
  'la tâche late_responders_report est planifiée, horaire, qualifiée et sans argument');

-- Les huit tâches de docs/SCHEMA.md § 8 ne sont pas toutes livrées ; celles qui
-- le sont ne doivent pas se marcher dessus sur la minute.
select tests_rel.check(
  (select count(distinct schedule) = count(*)
     from cron.job
    where jobname in ('lock_periods', 'assignment_reminders', 'late_responders_report')),
  'les trois tâches horaires démarrent à des minutes différentes');

do $$
begin
  -- Une tâche qui tourne avec des droits élevés n'est pas un bouton de client.
  set local role authenticated;
  perform tests_rel.denied(
    $sql$select cron_assignment_reminders()$sql$,
    'authenticated n''appelle pas cron_assignment_reminders');
  perform tests_rel.denied(
    $sql$select cron_late_responders_report()$sql$,
    'authenticated n''appelle pas cron_late_responders_report');
  perform tests_rel.denied(
    $sql$select assignment_reminder_targets(
           '99999999-0000-4000-8000-000000000305', 'push')$sql$,
    'authenticated n''interroge pas assignment_reminder_targets');
  reset role;

  set local role anon;
  perform tests_rel.denied(
    $sql$select cron_assignment_reminders()$sql$,
    'anon n''appelle pas cron_assignment_reminders');
  perform tests_rel.denied(
    $sql$select cron_late_responders_report()$sql$,
    'anon n''appelle pas cron_late_responders_report');
  reset role;
end $$;

\echo ''
\echo '=== Relances automatiques : OK ==='

rollback;
