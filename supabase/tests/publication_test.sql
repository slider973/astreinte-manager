-- Tests de la publication et du suivi d'un planning (migration 0019, ticket 019).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
-- 1. `schedules_guard_transition` : les cinq transitions de docs/WORKFLOWS.md
--    § 2 et **tout ce qui n'y est pas**, à commencer par le retour en
--    brouillon. La clé gelée, les deux horodatages tenus par la base, et la
--    règle qui vaut aussi pour le rôle de service.
-- 2. La suppression : bornée au brouillon par la politique **et** par un
--    déclencheur, parce que la cascade depuis `periods` ne consulte aucune
--    politique.
-- 3. `publish_schedule` : les quatre refus, la publication atomique,
--    `proposed_at` posé sur chaque attribution, l'audit, et surtout les
--    **destinataires groupés par membre** — un pompier à sept créneaux fait
--    une entrée, pas sept.
-- 4. `schedule_auto_validate` : la validation sans action d'administrateur, sur
--    les **acceptations seules**, une seule fois, avec la notification
--    `schedule_validated` à tous les membres actifs.
-- 5. `remind_schedule` : les refus, le regroupement par membre, l'incrément de
--    `reminder_count`, et l'idempotence à l'heure.
-- 6. Le temps réel et les droits : `schedules` inscrite dans
--    `supabase_realtime` en identité de réplique `default`, et les exécutions
--    refusées à `anon` comme à `authenticated` là où elles doivent l'être.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : une caserne « CIS Publication » et une caserne voisine, sur
-- l'année 2028 que ni le seed ni les autres fichiers ne touchent.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_pub;

create function tests_pub.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

create function tests_pub.egal(p_obtenu anyelement, p_attendu anyelement, p_label text) returns void
language plpgsql as $$
begin
  if p_obtenu is distinct from p_attendu then
    raise exception 'ECHEC : % — obtenu [%], attendu [%]', p_label, p_obtenu, p_attendu;
  end if;
  raise notice '  ok   % = %', p_label, coalesce(p_obtenu::text, 'NULL');
end $$;

-- `refuse` : l'instruction doit lever l'erreur nommée, et pas une autre.
create function tests_pub.refuse(p_sql text, p_erreur text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — aucune erreur levée, % attendue', p_label, p_erreur;
exception
  when insufficient_privilege then
    if p_erreur <> '42501' then
      raise exception 'ECHEC : % — refus de privilège au lieu de [%]', p_label, p_erreur;
    end if;
    raise notice '  ok   % (refusé : %)', p_label, sqlerrm;
  when others then
    if sqlerrm <> p_erreur and sqlstate <> p_erreur then
      raise exception 'ECHEC : % — erreur [% / %] au lieu de [%]',
        p_label, sqlstate, sqlerrm, p_erreur;
    end if;
    raise notice '  ok   % (%)', p_label, sqlerrm;
end $$;

grant usage on schema tests_pub to authenticated, anon;
grant execute on all functions in schema tests_pub to authenticated, anon;

-- ---------------------------------------------------------------------------
-- `notify_post` sans réseau — même substitution que `notifications_test.sql`.
-- L'effet de bord sur la file est conservé, l'appel HTTP est coupé : c'est lui
-- qui n'a rien à faire dans une CI sans Edge Functions.
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
\echo '=== Publication et suivi d''un planning (0019) ==='

-- ===========================================================================
-- Fixtures
-- ===========================================================================
-- P « CIS Publication » : 1 admin, 3 membres actifs, 1 membre désactivé.
-- W « CIS Voisine 3 » : 1 admin, pour le cloisonnement et les refus de droit.
--
-- Effectif requis : 1 le jour, 1 la nuit. Un planning de février 2028 (29 jours,
-- année bissextile) : 58 créneaux, dont on ne pourvoit qu'une poignée.

insert into stations (id, name, slug, timezone, settings) values
  ('55555555-0000-4000-8000-000000000001', 'CIS Publication', 'cis-publication', 'Europe/Paris',
   '{"day_start": "07:00", "day_end": "19:00",
     "required_day": 1, "required_night": 1,
     "required_overrides": {},
     "availability_deadline_day": 15,
     "response_reminder_hours": 24, "response_email_hours": 48,
     "late_report_hours": 72}'::jsonb),
  ('66666666-0000-4000-8000-000000000001', 'CIS Voisine 3', 'cis-voisine-3', 'Europe/Paris',
   '{"day_start": "07:00", "day_end": "19:00",
     "required_day": 1, "required_night": 1,
     "required_overrides": {},
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
  ('55555555-0000-4000-8000-000000000100'::uuid, 'admin@publication.test',   'Nadia',  'Aloui'),
  ('55555555-0000-4000-8000-000000000101'::uuid, 'membre1@publication.test', 'Bruno',  'Bertin'),
  ('55555555-0000-4000-8000-000000000102'::uuid, 'membre2@publication.test', 'Chloé',  'Colin'),
  ('55555555-0000-4000-8000-000000000103'::uuid, 'membre3@publication.test', 'Damien', 'Denis'),
  ('55555555-0000-4000-8000-000000000104'::uuid, 'ancien@publication.test',  'Eve',    'Evrard'),
  ('66666666-0000-4000-8000-000000000100'::uuid, 'admin@voisine3.test',      'Farid',  'Fauré')
) as u(id, email, first_name, last_name);

insert into memberships (station_id, user_id, role, status, display_name) values
  ('55555555-0000-4000-8000-000000000001', '55555555-0000-4000-8000-000000000100', 'admin',  'active',   'Nadia A.'),
  ('55555555-0000-4000-8000-000000000001', '55555555-0000-4000-8000-000000000101', 'member', 'active',   'Bruno B.'),
  ('55555555-0000-4000-8000-000000000001', '55555555-0000-4000-8000-000000000102', 'member', 'active',   'Chloé C.'),
  ('55555555-0000-4000-8000-000000000001', '55555555-0000-4000-8000-000000000103', 'member', 'active',   'Damien D.'),
  ('55555555-0000-4000-8000-000000000001', '55555555-0000-4000-8000-000000000104', 'member', 'disabled', 'Eve E.'),
  ('66666666-0000-4000-8000-000000000001', '66666666-0000-4000-8000-000000000100', 'admin',  'active',   'Farid F.');

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('55555555-0000-4000-8000-000000000202', '55555555-0000-4000-8000-000000000001', 2028, 2, 'locked', '2028-01-15 23:59:59+01'),
  ('55555555-0000-4000-8000-000000000203', '55555555-0000-4000-8000-000000000001', 2028, 3, 'open',   '2028-02-15 23:59:59+01'),
  ('55555555-0000-4000-8000-000000000204', '55555555-0000-4000-8000-000000000001', 2028, 4, 'open',   '2028-03-15 23:59:59+01'),
  ('66666666-0000-4000-8000-000000000202', '66666666-0000-4000-8000-000000000001', 2028, 2, 'locked', '2028-01-15 23:59:59+01');

-- ===========================================================================
-- 1. La machine à états des plannings
-- ===========================================================================
\echo ''
\echo '--- 1. Les transitions de docs/WORKFLOWS.md § 2, imposées en base'
savepoint s1;

insert into schedules (id, station_id, period_id, created_by) values
  ('55555555-0000-4000-8000-000000000302',
   '55555555-0000-4000-8000-000000000001',
   '55555555-0000-4000-8000-000000000202',
   '55555555-0000-4000-8000-000000000100');

do $$
declare
  publie_le  timestamptz;
  valide_le  timestamptz;
begin
  perform tests_pub.check(
    (select published_at is null and validated_at is null from schedules
      where id = '55555555-0000-4000-8000-000000000302'),
    'un brouillon n''a ni date de publication ni date de validation');

  -- draft -> published : autorisée, et la base pose l'horodatage.
  update schedules set status = 'published'
   where id = '55555555-0000-4000-8000-000000000302';
  select published_at into publie_le from schedules
   where id = '55555555-0000-4000-8000-000000000302';
  perform tests_pub.check(publie_le is not null,
    'draft -> published : published_at posé par la base');

  -- published -> draft : **le trou du ticket 017**. Il est fermé, et il l'est
  -- même pour le rôle de service — ce bloc tourne en `postgres`.
  perform tests_pub.refuse(
    $sql$update schedules set status = 'draft'
          where id = '55555555-0000-4000-8000-000000000302'$sql$,
    'schedule_invalid_transition',
    'published -> draft : refusé, y compris pour une écriture serveur');

  -- published -> validated.
  update schedules set status = 'validated'
   where id = '55555555-0000-4000-8000-000000000302';
  select validated_at into valide_le from schedules
   where id = '55555555-0000-4000-8000-000000000302';
  perform tests_pub.check(valide_le is not null,
    'published -> validated : validated_at posé par la base');

  perform tests_pub.refuse(
    $sql$update schedules set status = 'draft'
          where id = '55555555-0000-4000-8000-000000000302'$sql$,
    'schedule_invalid_transition', 'validated -> draft : refusé');

  -- validated -> published : la modification d'un créneau (ticket 020). La date
  -- de validation s'efface, celle de publication **ne bouge pas**.
  update schedules set status = 'published'
   where id = '55555555-0000-4000-8000-000000000302';
  perform tests_pub.check(
    (select validated_at is null from schedules
      where id = '55555555-0000-4000-8000-000000000302'),
    'validated -> published : validated_at effacé');
  perform tests_pub.egal(
    (select published_at from schedules
      where id = '55555555-0000-4000-8000-000000000302'),
    publie_le,
    'validated -> published : published_at reste celui de la première publication');

  -- Un `update` qui n'essaie pas de changer de statut n'efface pas les dates.
  update schedules set published_at = null, validated_at = now()
   where id = '55555555-0000-4000-8000-000000000302';
  perform tests_pub.egal(
    (select published_at from schedules
      where id = '55555555-0000-4000-8000-000000000302'),
    publie_le, 'published_at ne s''efface pas sans changement de statut');
  perform tests_pub.check(
    (select validated_at is null from schedules
      where id = '55555555-0000-4000-8000-000000000302'),
    'validated_at ne s''invente pas sans changement de statut');

  -- La clé est gelée, comme celle d'une période (0012).
  perform tests_pub.refuse(
    $sql$update schedules set period_id = '55555555-0000-4000-8000-000000000203'
          where id = '55555555-0000-4000-8000-000000000302'$sql$,
    'schedule_key_immutable', 'la période d''un planning ne se déplace pas');

  -- published -> archived, puis plus rien.
  update schedules set status = 'archived'
   where id = '55555555-0000-4000-8000-000000000302';
  perform tests_pub.refuse(
    $sql$update schedules set status = 'published'
          where id = '55555555-0000-4000-8000-000000000302'$sql$,
    'schedule_invalid_transition', 'archived -> published : refusé');
  perform tests_pub.refuse(
    $sql$update schedules set status = 'draft'
          where id = '55555555-0000-4000-8000-000000000302'$sql$,
    'schedule_invalid_transition', 'archived -> draft : refusé');
end $$;

rollback to savepoint s1;

-- Les deux transitions qui sautent une étape depuis le brouillon. Elles ont
-- leur propre planning : un `update` qui ne touche aucune ligne ne déclenche
-- rien, et un test qui passerait pour cette raison ne testerait rien.
savepoint s1b;
insert into schedules (id, station_id, period_id, created_by) values
  ('55555555-0000-4000-8000-000000000304',
   '55555555-0000-4000-8000-000000000001',
   '55555555-0000-4000-8000-000000000203',
   '55555555-0000-4000-8000-000000000100');

do $$
begin
  -- Sauter la publication reviendrait à valider un mois que personne n'a reçu.
  perform tests_pub.refuse(
    $sql$update schedules set status = 'validated'
          where id = '55555555-0000-4000-8000-000000000304'$sql$,
    'schedule_invalid_transition', 'draft -> validated : refusé');
  perform tests_pub.refuse(
    $sql$update schedules set status = 'archived'
          where id = '55555555-0000-4000-8000-000000000304'$sql$,
    'schedule_invalid_transition', 'draft -> archived : refusé');
end $$;

rollback to savepoint s1b;
release savepoint s1;

-- ===========================================================================
-- 2. Supprimer un planning : en brouillon, et nulle part ailleurs
-- ===========================================================================
\echo ''
\echo '--- 2. La suppression bornée au brouillon, cascade comprise'
savepoint s2;

insert into schedules (id, station_id, period_id, status, created_by) values
  ('55555555-0000-4000-8000-000000000310',
   '55555555-0000-4000-8000-000000000001',
   '55555555-0000-4000-8000-000000000202', 'draft',
   '55555555-0000-4000-8000-000000000100'),
  ('55555555-0000-4000-8000-000000000311',
   '55555555-0000-4000-8000-000000000001',
   '55555555-0000-4000-8000-000000000203', 'draft',
   '55555555-0000-4000-8000-000000000100');

update schedules set status = 'published'
 where id = '55555555-0000-4000-8000-000000000311';

set local role authenticated;
set local request.jwt.claims = '{"sub":"55555555-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  lignes integer;
begin
  -- La politique filtre **sans lever** : un planning publié ne rend aucune
  -- ligne à supprimer. C'est le refus lisible que le § 4 de docs/SCHEMA.md
  -- décrit table par table.
  delete from schedules where id = '55555555-0000-4000-8000-000000000311';
  get diagnostics lignes = row_count;
  perform tests_pub.egal(lignes, 0,
    'un admin ne supprime pas un planning publié (politique)');

  delete from schedules where id = '55555555-0000-4000-8000-000000000310';
  get diagnostics lignes = row_count;
  perform tests_pub.egal(lignes, 1, 'un admin supprime son brouillon');
end $$;

reset role;

do $$
begin
  -- Le rôle de service contourne la politique : c'est le déclencheur qui
  -- l'arrête, et c'est lui qui compte.
  perform tests_pub.refuse(
    $sql$delete from schedules where id = '55555555-0000-4000-8000-000000000311'$sql$,
    'schedule_delete_published',
    'même le rôle de service ne supprime pas un planning publié');

  -- **La cascade.** Supprimer le mois emporterait le planning publié et toutes
  -- ses attributions sans consulter la moindre politique. Le déclencheur de
  -- ligne, lui, est bien appelé par l'action référentielle.
  perform tests_pub.refuse(
    $sql$delete from periods where id = '55555555-0000-4000-8000-000000000203'$sql$,
    'schedule_delete_published',
    'supprimer le mois d''un planning publié échoue par la cascade');
end $$;

-- Un mois dont le planning est encore en brouillon se supprime, lui : la garde
-- protège l'historique, elle ne gèle pas l'administration d'une caserne.
insert into schedules (id, station_id, period_id, status, created_by) values
  ('55555555-0000-4000-8000-000000000312',
   '55555555-0000-4000-8000-000000000001',
   '55555555-0000-4000-8000-000000000204', 'draft',
   '55555555-0000-4000-8000-000000000100');

do $$
begin
  delete from periods where id = '55555555-0000-4000-8000-000000000204';
  perform tests_pub.egal(
    (select count(*)::int from schedules
      where id = '55555555-0000-4000-8000-000000000312'),
    0, 'supprimer le mois d''un planning en brouillon reste possible');
end $$;

rollback to savepoint s2;
release savepoint s2;

-- ===========================================================================
-- 3. publish_schedule
-- ===========================================================================
\echo ''
\echo '--- 3. La publication : atomique, horodatée, groupée par membre'
savepoint s3;

-- Le planning de février 2028 et ses 58 créneaux.
set local role authenticated;
set local request.jwt.claims = '{"sub":"55555555-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform create_schedule(
    '55555555-0000-4000-8000-000000000001',
    '55555555-0000-4000-8000-000000000202');
end $$;

reset role;

-- Sept créneaux pour Bruno — c'est **le** cas du ticket : sept créneaux, une
-- notification. Deux pour Chloé, aucun pour Damien.
insert into assignments (station_id, shift_id, user_id, created_by)
select
  '55555555-0000-4000-8000-000000000001', sh.id,
  '55555555-0000-4000-8000-000000000101',
  '55555555-0000-4000-8000-000000000100'
from shifts sh
join schedules sc on sc.id = sh.schedule_id
where sc.period_id = '55555555-0000-4000-8000-000000000202'
  and sh.date between '2028-02-01' and '2028-02-04'
  and not (sh.date = '2028-02-04' and sh.slot = 'night');

insert into assignments (station_id, shift_id, user_id, created_by)
select
  '55555555-0000-4000-8000-000000000001', sh.id,
  '55555555-0000-4000-8000-000000000102',
  '55555555-0000-4000-8000-000000000100'
from shifts sh
join schedules sc on sc.id = sh.schedule_id
where sc.period_id = '55555555-0000-4000-8000-000000000202'
  and sh.date = '2028-02-10';

do $$
declare
  planning uuid := (select id from schedules
                     where period_id = '55555555-0000-4000-8000-000000000202');
  resultat jsonb;
  bruno    jsonb;
begin
  perform tests_pub.egal(
    (select count(*)::int from assignments a
      join shifts sh on sh.id = a.shift_id
     where sh.schedule_id = planning),
    9, 'neuf attributions en brouillon');
  perform tests_pub.egal(
    (select count(*)::int from assignments a
      join shifts sh on sh.id = a.shift_id
     where sh.schedule_id = planning and a.proposed_at is not null),
    0, 'aucune n''est horodatée tant que rien n''est parti');

  -- Les refus, avant le succès.
  perform tests_pub.egal(
    publish_schedule('55555555-0000-4000-8000-000000000399',
                     '55555555-0000-4000-8000-000000000100') ->> 'code',
    'schedule_not_found', 'planning inconnu');
  perform tests_pub.egal(
    publish_schedule(planning, '55555555-0000-4000-8000-000000000101') ->> 'code',
    'not_admin', 'un membre ne publie pas');
  perform tests_pub.egal(
    publish_schedule(planning, '66666666-0000-4000-8000-000000000100') ->> 'code',
    'not_admin', 'l''admin de la caserne voisine ne publie pas');

  -- Caserne suspendue : lecture seule, publication comprise.
  insert into subscriptions (station_id, status)
  values ('55555555-0000-4000-8000-000000000001', 'suspended');
  perform tests_pub.egal(
    publish_schedule(planning, '55555555-0000-4000-8000-000000000100') ->> 'code',
    'station_suspended', 'une caserne suspendue ne publie pas');
  update subscriptions set status = 'active'
   where station_id = '55555555-0000-4000-8000-000000000001';

  -- Le succès.
  resultat := publish_schedule(planning, '55555555-0000-4000-8000-000000000100');

  perform tests_pub.egal(resultat ->> 'ok', 'true', 'la publication réussit');
  perform tests_pub.egal(resultat ->> 'status', 'published', 'le planning est publié');
  perform tests_pub.egal(resultat ->> 'period', '2028-02', 'la clé du mois part avec');
  perform tests_pub.egal((resultat ->> 'assignments')::int, 9,
    'les neuf attributions sont horodatées');
  perform tests_pub.check(resultat ->> 'published_at' is not null,
    'la réponse porte la date de publication');

  perform tests_pub.egal(
    (select status::text from schedules where id = planning), 'published',
    'la table dit la même chose que la réponse');
  perform tests_pub.egal(
    (select count(*)::int from assignments a
      join shifts sh on sh.id = a.shift_id
     where sh.schedule_id = planning and a.proposed_at is null),
    0, 'plus aucune attribution sans proposed_at');

  -- **Le critère d'acceptation** : deux destinataires, pas neuf.
  perform tests_pub.egal(
    jsonb_array_length(resultat -> 'recipients'), 2,
    'deux destinataires pour neuf attributions');

  select entree into bruno
    from jsonb_array_elements(resultat -> 'recipients') as entree
   where entree ->> 'user_id' = '55555555-0000-4000-8000-000000000101';

  perform tests_pub.egal(
    jsonb_array_length(bruno -> 'payload' -> 'shifts'), 7,
    'Bruno reçoit une entrée qui liste ses sept créneaux');
  perform tests_pub.egal(
    bruno -> 'payload' -> 'shifts' -> 0 ->> 'date', '2028-02-01',
    'les créneaux sont triés par date');
  perform tests_pub.egal(
    bruno -> 'payload' -> 'shifts' -> 0 ->> 'slot', 'day',
    'le jour passe avant la nuit');
  perform tests_pub.egal(
    bruno -> 'payload' -> 'shifts' -> 6 ->> 'date', '2028-02-04',
    'jusqu''au dernier');
  perform tests_pub.check(
    bruno -> 'payload' -> 'shifts' -> 0 ->> 'assignment_id' is not null,
    'chaque créneau porte l''identifiant de son attribution');

  -- L'audit, parce qu'une publication est une action d'administration.
  perform tests_pub.egal(
    (select data ->> 'recipients' from audit_log
      where action = 'schedule.published' and entity_id = planning),
    '2', 'audit schedule.published, avec le nombre de destinataires');

  -- Rejouée : le second appel ne republie rien.
  perform tests_pub.egal(
    publish_schedule(planning, '55555555-0000-4000-8000-000000000100') ->> 'code',
    'schedule_not_draft', 'un planning publié ne se republie pas');
end $$;

-- Un client n'appelle pas la fonction : elle écrirait pour n'importe qui.
set local role authenticated;
set local request.jwt.claims = '{"sub":"55555555-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests_pub.refuse(
    $sql$select publish_schedule(
      (select id from schedules where period_id = '55555555-0000-4000-8000-000000000202'),
      '55555555-0000-4000-8000-000000000100')$sql$,
    '42501', 'un administrateur connecté n''appelle pas publish_schedule');
end $$;

reset role;

rollback to savepoint s3;
release savepoint s3;

-- ===========================================================================
-- 4. schedule_auto_validate
-- ===========================================================================
\echo ''
\echo '--- 4. La validation automatique, sur les acceptations seules'
savepoint s4;

-- Un planning minuscule pour que « tout accepté » soit atteignable : deux
-- créneaux à 1 requis, le reste à 0.
set local role authenticated;
set local request.jwt.claims = '{"sub":"55555555-0000-4000-8000-000000000100","role":"authenticated"}';
do $$
begin
  perform create_schedule(
    '55555555-0000-4000-8000-000000000001',
    '55555555-0000-4000-8000-000000000202');
end $$;
reset role;

update shifts set required_count = 0
 where schedule_id = (select id from schedules
                       where period_id = '55555555-0000-4000-8000-000000000202')
   and date <> '2028-02-01';

insert into assignments (station_id, shift_id, user_id, created_by)
select
  '55555555-0000-4000-8000-000000000001', sh.id,
  case when sh.slot = 'day'
       then '55555555-0000-4000-8000-000000000101'::uuid
       else '55555555-0000-4000-8000-000000000102'::uuid end,
  '55555555-0000-4000-8000-000000000100'
from shifts sh
where sh.schedule_id = (select id from schedules
                         where period_id = '55555555-0000-4000-8000-000000000202')
  and sh.date = '2028-02-01';

do $$
begin
  perform publish_schedule(
    (select id from schedules where period_id = '55555555-0000-4000-8000-000000000202'),
    '55555555-0000-4000-8000-000000000100');
end $$;

do $$
declare
  planning uuid := (select id from schedules
                     where period_id = '55555555-0000-4000-8000-000000000202');
  file     jsonb;
begin
  perform tests_pub.egal(
    (select status::text from schedules where id = planning), 'published',
    'le planning part publié');

  -- Une acceptation sur deux : pas encore.
  update assignments a set status = 'accepted', responded_at = now()
    from shifts sh
   where sh.id = a.shift_id and sh.schedule_id = planning and sh.slot = 'day';
  perform tests_pub.egal(
    (select status::text from schedules where id = planning), 'published',
    'une acceptation sur deux ne valide pas');

  -- Un refus ne vaut pas une acceptation : le créneau redevient à pourvoir.
  update assignments a set status = 'declined', responded_at = now(),
                           decline_reason = 'en formation'
    from shifts sh
   where sh.id = a.shift_id and sh.schedule_id = planning and sh.slot = 'night';
  perform tests_pub.egal(
    (select status::text from schedules where id = planning), 'published',
    'un refus ne valide pas');

  -- Et `shifts_filled` le dit : une attribution refusée ne couvre plus rien.
  perform tests_pub.egal(
    (select shifts_filled from v_schedule_progress where schedule_id = planning),
    57, 'le créneau refusé n''est plus couvert (57 sur 58)');
  perform tests_pub.egal(
    (select assignments_declined from v_schedule_progress where schedule_id = planning),
    1, 'la vue compte le refus');

  -- On réattribue la nuit et on accepte : c'est la dernière requise.
  insert into assignments (station_id, shift_id, user_id, status, proposed_at, created_by)
  select '55555555-0000-4000-8000-000000000001', sh.id,
         '55555555-0000-4000-8000-000000000103', 'proposed', now(),
         '55555555-0000-4000-8000-000000000100'
    from shifts sh
   where sh.schedule_id = planning and sh.date = '2028-02-01' and sh.slot = 'night';

  update assignments a set status = 'accepted', responded_at = now()
    from shifts sh
   where sh.id = a.shift_id and sh.schedule_id = planning
     and sh.slot = 'night' and a.status = 'proposed';

  perform tests_pub.egal(
    (select status::text from schedules where id = planning), 'validated',
    'la dernière attribution requise acceptée valide le planning');
  perform tests_pub.check(
    (select validated_at is not null from schedules where id = planning),
    'la date de validation est posée');

  -- La notification est en file, pour **tous les membres actifs** — le membre
  -- désactivé n'y est pas.
  select to_jsonb(o) into file
    from notification_outbox o
   where o.type = 'schedule_validated'
     and o.station_id = '55555555-0000-4000-8000-000000000001';

  perform tests_pub.check(file is not null,
    'une demande schedule_validated est en file');
  perform tests_pub.egal(
    jsonb_array_length(file -> 'recipients'), 4,
    'quatre destinataires : les membres actifs, admin compris');
  perform tests_pub.egal(
    file -> 'payload' ->> 'period', '2028-02',
    'la charge utile porte le mois');
  perform tests_pub.check(
    not (file -> 'recipients' @> jsonb_build_array(jsonb_build_object(
          'user_id', '55555555-0000-4000-8000-000000000104'))),
    'le membre désactivé n''est pas notifié');

  -- Une acceptation de plus sur un planning déjà validé ne renotifie pas : la
  -- transition n'a lieu qu'une fois.
  insert into assignments (station_id, shift_id, user_id, status, proposed_at, created_by)
  select '55555555-0000-4000-8000-000000000001', sh.id,
         '55555555-0000-4000-8000-000000000102', 'proposed', now(),
         '55555555-0000-4000-8000-000000000100'
    from shifts sh
   where sh.schedule_id = planning and sh.date = '2028-02-02' and sh.slot = 'day';

  update assignments a set status = 'accepted', responded_at = now()
    from shifts sh
   where sh.id = a.shift_id and sh.schedule_id = planning
     and sh.date = '2028-02-02' and sh.slot = 'day';

  perform tests_pub.egal(
    (select count(*)::int from notification_outbox
      where type = 'schedule_validated'
        and station_id = '55555555-0000-4000-8000-000000000001'),
    1, 'un planning déjà validé ne renotifie pas');
end $$;

rollback to savepoint s4;
release savepoint s4;

-- ===========================================================================
-- 5. remind_schedule
-- ===========================================================================
\echo ''
\echo '--- 5. La relance manuelle des retardataires'
savepoint s5;

-- La relance s'appelle sous l'identité d'un administrateur (`is_admin`), mais
-- la file de notifications ne se lit qu'en dehors : `notification_outbox` est
-- fermée à `authenticated`, et c'est bien ainsi. Les résultats transitent donc
-- par une table de travail.
create table tests_pub.relances (etape text primary key, resultat jsonb);

set local role authenticated;
set local request.jwt.claims = '{"sub":"55555555-0000-4000-8000-000000000100","role":"authenticated"}';
do $$
begin
  perform create_schedule(
    '55555555-0000-4000-8000-000000000001',
    '55555555-0000-4000-8000-000000000202');
end $$;
reset role;

insert into assignments (station_id, shift_id, user_id, created_by)
select
  '55555555-0000-4000-8000-000000000001', sh.id,
  case when sh.slot = 'day'
       then '55555555-0000-4000-8000-000000000101'::uuid
       else '55555555-0000-4000-8000-000000000102'::uuid end,
  '55555555-0000-4000-8000-000000000100'
from shifts sh
where sh.schedule_id = (select id from schedules
                         where period_id = '55555555-0000-4000-8000-000000000202')
  and sh.date between '2028-02-01' and '2028-02-02';

grant all on tests_pub.relances to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"55555555-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  planning uuid := (select id from schedules
                     where period_id = '55555555-0000-4000-8000-000000000202');
begin
  -- Un brouillon n'a relancé personne : il n'y a rien à rappeler.
  perform tests_pub.egal(
    remind_schedule(planning) ->> 'code', 'schedule_not_published',
    'on ne relance pas un brouillon');
end $$;

reset role;

do $$
begin
  perform publish_schedule(
    (select id from schedules where period_id = '55555555-0000-4000-8000-000000000202'),
    '55555555-0000-4000-8000-000000000100');
end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"55555555-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  planning uuid := (select id from schedules
                     where period_id = '55555555-0000-4000-8000-000000000202');
  resultat jsonb;
begin
  -- Rien n'est en retard : la publication vient d'avoir lieu.
  resultat := remind_schedule(planning);
  perform tests_pub.egal((resultat ->> 'members')::int, 0,
    'aucun retardataire juste après la publication');
  perform tests_pub.check(resultat ->> 'outbox_id' is null,
    'et rien n''est mis en file pour personne');

  -- On recule les propositions de quatre jours : `late_report_hours` vaut 72.
  update assignments a set proposed_at = now() - interval '4 days'
    from shifts sh
   where sh.id = a.shift_id and sh.schedule_id = planning;

  perform tests_pub.egal(
    (select assignments_late from v_schedule_progress where schedule_id = planning),
    4, 'la vue compte quatre attributions en retard');

  resultat := remind_schedule(planning);
  insert into tests_pub.relances values ('premiere', resultat);

  perform tests_pub.egal((resultat ->> 'members')::int, 2,
    'deux pompiers relancés pour quatre attributions');
  perform tests_pub.egal((resultat ->> 'assignments')::int, 4,
    'les quatre attributions portent la trace de la relance');
  perform tests_pub.egal(
    (select count(*)::int from assignments a
      join shifts sh on sh.id = a.shift_id
     where sh.schedule_id = planning
       and a.reminder_count = 1 and a.last_reminder_at is not null),
    4, 'reminder_count et last_reminder_at sont à jour');

  -- Double clic, ou deux adjoints : la clé de dédoublonnage rend la même ligne.
  insert into tests_pub.relances values ('rejeu', remind_schedule(planning));
end $$;

reset role;

do $$
declare
  premiere jsonb := (select resultat from tests_pub.relances where etape = 'premiere');
  rejeu    jsonb := (select resultat from tests_pub.relances where etape = 'rejeu');
  file     jsonb;
  bruno    jsonb;
begin
  perform tests_pub.egal(rejeu ->> 'outbox_id', premiere ->> 'outbox_id',
    'relancer deux fois dans l''heure ne met rien de plus en file');
  perform tests_pub.egal(
    (select count(*)::int from notification_outbox
      where type = 'assignment_reminder'
        and station_id = '55555555-0000-4000-8000-000000000001'),
    1, 'une seule demande en file pour les deux appels');

  select to_jsonb(o) into file
    from notification_outbox o where o.id = (premiere ->> 'outbox_id')::uuid;
  perform tests_pub.egal(file ->> 'type', 'assignment_reminder',
    'la demande est un rappel de réponse');
  perform tests_pub.egal(jsonb_array_length(file -> 'recipients'), 2,
    'une entrée par membre, pas une par créneau');
  perform tests_pub.egal(file -> 'payload' ->> 'period', '2028-02',
    'la charge utile porte le mois');

  select entree into bruno
    from jsonb_array_elements(file -> 'recipients') as entree
   where entree ->> 'user_id' = '55555555-0000-4000-8000-000000000101';
  perform tests_pub.egal(
    jsonb_array_length(bruno -> 'payload' -> 'shifts'), 2,
    'Bruno reçoit ses deux créneaux dans la même notification');
end $$;

-- Les droits : un membre ne relance pas, `anon` non plus.
set local role authenticated;
set local request.jwt.claims = '{"sub":"55555555-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests_pub.refuse(
    $sql$select remind_schedule(
      (select id from schedules where period_id = '55555555-0000-4000-8000-000000000202'))$sql$,
    'forbidden', 'un membre ne relance pas');
end $$;

reset role;

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

do $$
begin
  perform tests_pub.refuse(
    $sql$select remind_schedule('55555555-0000-4000-8000-000000000399')$sql$,
    '42501', 'anon n''appelle pas remind_schedule');
end $$;

reset role;

rollback to savepoint s5;
release savepoint s5;

-- ===========================================================================
-- 6. Le temps réel et les droits d'exécution
-- ===========================================================================
\echo ''
\echo '--- 6. schedules en temps réel, et les exécutions révoquées'
savepoint s6;

do $$
begin
  perform tests_pub.check(
    exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'schedules'),
    'schedules est inscrite dans supabase_realtime');

  -- `default` : une suppression ne diffuse que la clé primaire. `full`
  -- diffuserait toutes les colonnes de la ligne supprimée, sans filtre.
  perform tests_pub.egal(
    (select relreplident::text from pg_class
      where oid = 'public.schedules'::regclass),
    'd', 'l''identité de réplique de schedules reste default');

  -- Les fonctions trigger n'apparaissent pas dans le schéma PostgREST.
  perform tests_pub.check(
    not has_function_privilege('authenticated',
      'public.schedules_guard_transition()', 'execute'),
    'schedules_guard_transition n''est pas appelable en RPC');
  perform tests_pub.check(
    not has_function_privilege('authenticated',
      'public.schedule_auto_validate()', 'execute'),
    'schedule_auto_validate n''est pas appelable en RPC');
  perform tests_pub.check(
    not has_function_privilege('anon',
      'public.publish_schedule(uuid, uuid)', 'execute'),
    'publish_schedule est fermée à anon');
  perform tests_pub.check(
    has_function_privilege('authenticated',
      'public.remind_schedule(uuid)', 'execute'),
    'remind_schedule est ouverte à authenticated, qui la garde par is_admin');
end $$;

release savepoint s6;

\echo ''
\echo '=== Publication et suivi : tous les tests passent ==='

rollback;
