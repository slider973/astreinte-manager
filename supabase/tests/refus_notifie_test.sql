-- Tests du refus notifié et de la réattribution qui rend `notified` (migration
-- 0039, ticket 055).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié
-- ------------------
-- 1. **La réponse d'un membre, telle que la PWA et l'app iOS l'écrivent** — le
--    `PATCH assignments … status=eq.proposed&select=id`, rejoué ici en
--    `update … where status = 'proposed' returning id` sous le rôle
--    `authenticated` —, quand elle refuse, met en file **une** demande
--    `assignment_declined` dans la même transaction : les deux administrateurs
--    actifs en destinataires, le membre jamais, le nom, le motif, le créneau et
--    le mois dans la charge utile. Un administrateur **désactivé** ne reçoit
--    rien. C'est ce qui rend vraie la phrase « Ton chef
--    de centre sera prévenu » dès qu'une ligne revient.
-- 2. Un administrateur qui refuse sa propre astreinte ne se prévient pas
--    lui-même : seuls les **autres** administrateurs sont destinataires.
-- 2 bis. Un administrateur qui enregistre un refus **à la place** d'un membre
--    (`assignments_update_admin` : le pompier a téléphoné) n'est pas prévenu
--    de son propre geste — l'acteur `auth.uid()` est écarté, comme le titulaire.
-- 3. Un administrateur seul dans sa caserne refuse : rien n'est mis en file, et
--    le refus passe quand même. L'écran ne lui promet rien.
-- 4. Une acceptation ne met rien en file ; un refus sans proposition partie
--    (`proposed_at` nul, écriture serveur) non plus.
-- 5. `reassign_shift` rend `notified = true` pour l'entrant, avec sa ligne de
--    file, à côté de `previous_notified`.
--
-- Fixtures : « CIS Refus » (deux administrateurs actifs, un désactivé, deux membres) et « CIS Seul »
-- (un administrateur, rien d'autre), sur mars 2029.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_refus;

create function tests_refus.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

create function tests_refus.egal(p_obtenu anyelement, p_attendu anyelement, p_label text) returns void
language plpgsql as $$
begin
  if p_obtenu is distinct from p_attendu then
    raise exception 'ECHEC : % — obtenu [%], attendu [%]', p_label, p_obtenu, p_attendu;
  end if;
  raise notice '  ok   % = %', p_label, coalesce(p_obtenu::text, 'NULL');
end $$;

grant usage on schema tests_refus to authenticated, anon;
grant execute on all functions in schema tests_refus to authenticated, anon;

-- `notify_post` sans réseau — même substitution que `reattribution_test.sql` :
-- la file est écrite, l'appel HTTP est coupé.
create or replace function notify_post(p_outbox uuid) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update notification_outbox
     set attempts = attempts + 1, locked_until = now() + interval '2 minutes'
   where id = p_outbox and status = 'pending';
  return found;
end $$;

-- Le rôle `authenticated` ne lit pas la file (RLS fermée) : les comptes se font
-- par cette fonction, qui tourne sous le propriétaire.
create function tests_refus.declines() returns setof notification_outbox
language sql security definer set search_path = public, pg_temp as $$
  select * from notification_outbox where type = 'assignment_declined' order by created_at;
$$;
grant execute on function tests_refus.declines() to authenticated;

\echo ''
\echo '=== Refus notifié et réattribution (0039) ==='

insert into stations (id, name, slug, timezone, settings) values
  ('55555555-0550-4000-8000-000000000001', 'CIS Refus', 'cis-refus-055', 'Europe/Paris',
   '{"day_start": "07:00", "day_end": "19:00", "required_day": 1, "required_night": 1,
     "required_overrides": {}, "availability_deadline_day": 15,
     "response_reminder_hours": 24, "response_email_hours": 48, "late_report_hours": 72}'::jsonb),
  ('55555555-0550-4000-8000-000000000002', 'CIS Seul', 'cis-seul-055', 'Europe/Paris',
   '{"day_start": "07:00", "day_end": "19:00", "required_day": 1, "required_night": 1,
     "required_overrides": {}, "availability_deadline_day": 15,
     "response_reminder_hours": 24, "response_email_hours": 48, "late_report_hours": 72}'::jsonb);

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
  ('55555555-0550-4000-8000-000000000100'::uuid, 'chef@refus.test',    'Nadia',  'Aloui'),
  ('55555555-0550-4000-8000-000000000101'::uuid, 'adjoint@refus.test', 'Paul',   'Adam'),
  ('55555555-0550-4000-8000-000000000102'::uuid, 'bruno@refus.test',   'Bruno',  'Bertin'),
  ('55555555-0550-4000-8000-000000000103'::uuid, 'chloe@refus.test',   'Chloé',  'Colin'),
  ('55555555-0550-4000-8000-000000000104'::uuid, 'ines@refus.test',    'Inès',   'Ancien'),
  ('55555555-0550-4000-8000-000000000200'::uuid, 'seul@refus.test',    'Solène', 'Seul')
) as u(id, email, first_name, last_name);

insert into memberships (station_id, user_id, role, status, display_name) values
  ('55555555-0550-4000-8000-000000000001', '55555555-0550-4000-8000-000000000100', 'admin',  'active', 'Nadia A.'),
  ('55555555-0550-4000-8000-000000000001', '55555555-0550-4000-8000-000000000101', 'admin',  'active', 'Paul A.'),
  ('55555555-0550-4000-8000-000000000001', '55555555-0550-4000-8000-000000000102', 'member', 'active', 'Bruno B.'),
  ('55555555-0550-4000-8000-000000000001', '55555555-0550-4000-8000-000000000103', 'member', 'active', null),
  -- Inès : ancienne administratrice, désactivée. Elle ne doit plus rien recevoir.
  ('55555555-0550-4000-8000-000000000001', '55555555-0550-4000-8000-000000000104', 'admin',  'disabled', 'Inès A.'),
  ('55555555-0550-4000-8000-000000000002', '55555555-0550-4000-8000-000000000200', 'admin',  'active', 'Solène S.');

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('55555555-0550-4000-8000-000000000201', '55555555-0550-4000-8000-000000000001', 2029, 3, 'locked', '2029-02-15 23:59:59+01'),
  ('55555555-0550-4000-8000-000000000202', '55555555-0550-4000-8000-000000000002', 2029, 3, 'locked', '2029-02-15 23:59:59+01');

insert into schedules (id, station_id, period_id, created_by) values
  ('55555555-0550-4000-8000-000000000301', '55555555-0550-4000-8000-000000000001',
   '55555555-0550-4000-8000-000000000201', '55555555-0550-4000-8000-000000000100'),
  ('55555555-0550-4000-8000-000000000302', '55555555-0550-4000-8000-000000000002',
   '55555555-0550-4000-8000-000000000202', '55555555-0550-4000-8000-000000000200');

insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  ('55555555-0550-4000-8000-000000000401', '55555555-0550-4000-8000-000000000001',
   '55555555-0550-4000-8000-000000000301', '2029-03-03', 'night', 1),
  ('55555555-0550-4000-8000-000000000402', '55555555-0550-4000-8000-000000000001',
   '55555555-0550-4000-8000-000000000301', '2029-03-04', 'day',   1),
  ('55555555-0550-4000-8000-000000000403', '55555555-0550-4000-8000-000000000001',
   '55555555-0550-4000-8000-000000000301', '2029-03-05', 'day',   1),
  ('55555555-0550-4000-8000-000000000404', '55555555-0550-4000-8000-000000000001',
   '55555555-0550-4000-8000-000000000301', '2029-03-06', 'day',   1),
  ('55555555-0550-4000-8000-000000000405', '55555555-0550-4000-8000-000000000002',
   '55555555-0550-4000-8000-000000000302', '2029-03-03', 'day',   1),
  ('55555555-0550-4000-8000-000000000406', '55555555-0550-4000-8000-000000000001',
   '55555555-0550-4000-8000-000000000301', '2029-03-07', 'night', 1);

update schedules set status = 'published'
 where id in ('55555555-0550-4000-8000-000000000301', '55555555-0550-4000-8000-000000000302');

insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by) values
  -- Bruno : la proposition qu'il va refuser.
  ('55555555-0550-4000-8000-000000000501', '55555555-0550-4000-8000-000000000001',
   '55555555-0550-4000-8000-000000000401', '55555555-0550-4000-8000-000000000102',
   'proposed', now() - interval '1 hour', '55555555-0550-4000-8000-000000000100'),
  -- Nadia, administratrice, est aussi de garde : elle refusera la sienne.
  ('55555555-0550-4000-8000-000000000502', '55555555-0550-4000-8000-000000000001',
   '55555555-0550-4000-8000-000000000402', '55555555-0550-4000-8000-000000000100',
   'proposed', now() - interval '1 hour', '55555555-0550-4000-8000-000000000100'),
  -- Chloé : elle acceptera.
  ('55555555-0550-4000-8000-000000000503', '55555555-0550-4000-8000-000000000001',
   '55555555-0550-4000-8000-000000000403', '55555555-0550-4000-8000-000000000103',
   'proposed', now() - interval '1 hour', '55555555-0550-4000-8000-000000000100'),
  -- Une attribution jamais partie (`proposed_at` nul).
  ('55555555-0550-4000-8000-000000000504', '55555555-0550-4000-8000-000000000001',
   '55555555-0550-4000-8000-000000000404', '55555555-0550-4000-8000-000000000103',
   'proposed', null, '55555555-0550-4000-8000-000000000100'),
  -- Bruno encore : Paul, administrateur, enregistrera son refus à sa place.
  ('55555555-0550-4000-8000-000000000506', '55555555-0550-4000-8000-000000000001',
   '55555555-0550-4000-8000-000000000406', '55555555-0550-4000-8000-000000000102',
   'proposed', now() - interval '1 hour', '55555555-0550-4000-8000-000000000100'),
  -- Solène, seule administratrice de sa caserne, sur sa propre garde.
  ('55555555-0550-4000-8000-000000000505', '55555555-0550-4000-8000-000000000002',
   '55555555-0550-4000-8000-000000000405', '55555555-0550-4000-8000-000000000200',
   'proposed', now() - interval '1 hour', '55555555-0550-4000-8000-000000000200');

delete from notification_outbox;

-- ===========================================================================
-- 1. Le refus d'un membre, par la requête des clients
-- ===========================================================================
\echo ''
\echo '--- 1. Un refus met en file assignment_declined, dans sa transaction'

set local role authenticated;
set local request.jwt.claims = '{"sub":"55555555-0550-4000-8000-000000000102","role":"authenticated"}';

do $$
declare
  touchees  integer;
  demande   notification_outbox;
  dest      uuid[];
begin
  -- La requête des clients : la condition sur le statut, et l'identifiant rendu.
  with r as (
    update assignments
       set status = 'declined', decline_reason = 'en formation'
     where id = '55555555-0550-4000-8000-000000000501'
       and status = 'proposed'
    returning id
  ) select count(*)::integer into touchees from r;

  perform tests_refus.egal(touchees, 1, 'le PATCH du membre touche sa ligne');
  perform tests_refus.egal((select count(*)::integer from tests_refus.declines()), 1,
    'une et une seule demande assignment_declined est en file');

  select * into demande from tests_refus.declines() limit 1;
  select array_agg((e ->> 'user_id')::uuid order by (e ->> 'user_id'))
    into dest from jsonb_array_elements(demande.recipients) e;

  perform tests_refus.egal(dest,
    array['55555555-0550-4000-8000-000000000100',
          '55555555-0550-4000-8000-000000000101']::uuid[],
    'les deux administrateurs actifs sont destinataires, et eux seuls : ni Bruno, ni Inès (désactivée)');
  perform tests_refus.egal(demande.station_id, '55555555-0550-4000-8000-000000000001'::uuid,
    'la demande porte la caserne');
  perform tests_refus.egal(demande.payload ->> 'member_name', 'Bruno B.',
    'le nom est celui de la caserne');
  perform tests_refus.egal(demande.payload ->> 'decline_reason', 'en formation',
    'le motif part avec la demande');
  perform tests_refus.egal(demande.payload ->> 'period', '2029-03', 'le mois en AAAA-MM');
  perform tests_refus.egal(demande.payload -> 'shifts' -> 0 ->> 'date', '2029-03-03',
    'le créneau : la date');
  perform tests_refus.egal(demande.payload -> 'shifts' -> 0 ->> 'slot', 'night',
    'le créneau : nuit');
  perform tests_refus.egal(demande.dedupe_key, 'declined:55555555-0550-4000-8000-000000000501',
    'la clé de dédoublonnage est l''attribution');
  perform tests_refus.egal(demande.attempts, 1,
    'la tentative immédiate est lancée (notify_post)');

  -- Rejouée, la requête ne touche plus rien et ne met rien de plus en file.
  with r as (
    update assignments set status = 'declined'
     where id = '55555555-0550-4000-8000-000000000501' and status = 'proposed'
    returning id
  ) select count(*)::integer into touchees from r;
  perform tests_refus.egal(touchees, 0, 'le même refus rejoué ne touche aucune ligne');
  perform tests_refus.egal((select count(*)::integer from tests_refus.declines()), 1,
    'et ne met rien de plus en file');
end $$;

-- ===========================================================================
-- 2. Un administrateur qui refuse ne se prévient pas lui-même
-- ===========================================================================
\echo ''
\echo '--- 2. Nadia, administratrice, refuse sa garde : seul Paul est prévenu'

set local request.jwt.claims = '{"sub":"55555555-0550-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  demande notification_outbox;
begin
  update assignments set status = 'declined'
   where id = '55555555-0550-4000-8000-000000000502' and status = 'proposed';

  select * into demande from tests_refus.declines()
   where dedupe_key = 'declined:55555555-0550-4000-8000-000000000502';
  perform tests_refus.check(demande.id is not null, 'le refus de Nadia est en file');
  perform tests_refus.egal(demande.recipients,
    '[{"user_id": "55555555-0550-4000-8000-000000000101"}]'::jsonb,
    'Paul seul : Nadia ne reçoit pas son propre refus');
  perform tests_refus.check(demande.payload ->> 'decline_reason' is null,
    'sans motif, la clé reste nulle');
end $$;

-- ===========================================================================
-- 2 bis. Un administrateur refuse à la place d'un membre
-- ===========================================================================
\echo ''
\echo '--- 2 bis. Paul enregistre le refus de Bruno : seule Nadia est prévenue'

set local request.jwt.claims = '{"sub":"55555555-0550-4000-8000-000000000101","role":"authenticated"}';

do $$
declare
  touchees integer;
  demande  notification_outbox;
begin
  with r as (
    update assignments set status = 'declined', decline_reason = 'appel de Bruno'
     where id = '55555555-0550-4000-8000-000000000506' and status = 'proposed'
    returning id
  ) select count(*)::integer into touchees from r;
  perform tests_refus.egal(touchees, 1,
    'un administrateur peut enregistrer le refus d''un membre (assignments_update_admin)');

  select * into demande from tests_refus.declines()
   where dedupe_key = 'declined:55555555-0550-4000-8000-000000000506';
  perform tests_refus.egal(demande.recipients,
    '[{"user_id": "55555555-0550-4000-8000-000000000100"}]'::jsonb,
    'Nadia seule : Paul, l''acteur, n''est pas prévenu de son propre geste, Bruno non plus');
  perform tests_refus.egal(demande.payload ->> 'member_name', 'Bruno B.',
    'la demande nomme toujours le titulaire, pas l''acteur');
end $$;

-- ===========================================================================
-- 3. Seule administratrice : personne à prévenir, le refus passe
-- ===========================================================================
\echo ''
\echo '--- 3. Solène, seule administratrice, refuse : rien en file, refus accepté'

set local request.jwt.claims = '{"sub":"55555555-0550-4000-8000-000000000200","role":"authenticated"}';

do $$
declare
  touchees integer;
begin
  with r as (
    update assignments set status = 'declined'
     where id = '55555555-0550-4000-8000-000000000505' and status = 'proposed'
    returning id
  ) select count(*)::integer into touchees from r;
  perform tests_refus.egal(touchees, 1, 'le refus passe');
  perform tests_refus.egal(
    (select count(*)::integer from tests_refus.declines()
      where station_id = '55555555-0550-4000-8000-000000000002'),
    0, 'personne d''autre à prévenir : rien en file');
end $$;

-- ===========================================================================
-- 4. Une acceptation, un refus jamais proposé : rien
-- ===========================================================================
\echo ''
\echo '--- 4. Accepter ne prévient personne ; un brouillon refusé non plus'

set local request.jwt.claims = '{"sub":"55555555-0550-4000-8000-000000000103","role":"authenticated"}';

update assignments set status = 'accepted'
 where id = '55555555-0550-4000-8000-000000000503' and status = 'proposed';

reset role;

-- Écriture serveur sur une attribution jamais partie.
update assignments set status = 'declined'
 where id = '55555555-0550-4000-8000-000000000504';

do $$
begin
  perform tests_refus.egal((select count(*)::integer from tests_refus.declines()), 3,
    'toujours trois demandes : ni l''acceptation ni le brouillon n''en ajoutent');
end $$;

-- ===========================================================================
-- 5. reassign_shift rend `notified` pour l'entrant
-- ===========================================================================
\echo ''
\echo '--- 5. La réattribution rend notified (en file) pour l''entrant'

delete from notification_outbox;

do $$
declare
  r        jsonb;
  demande  notification_outbox;
begin
  r := reassign_shift('55555555-0550-4000-8000-000000000401',
                      '55555555-0550-4000-8000-000000000103',
                      '55555555-0550-4000-8000-000000000100',
                      '55555555-0550-4000-8000-000000000501');
  perform tests_refus.check((r ->> 'ok')::boolean, 'la réattribution aboutit');
  perform tests_refus.egal((r ->> 'notified')::boolean, true,
    'notified : la demande de l''entrant est en file');
  perform tests_refus.egal((r ->> 'previous_notified')::boolean, false,
    'previous_notified inchangé : celui qui a refusé ne reçoit rien');

  select * into demande from notification_outbox where type = 'assignment_proposed';
  perform tests_refus.egal(demande.recipients -> 0 ->> 'user_id',
    '55555555-0550-4000-8000-000000000103',
    'la ligne de file est bien celle de Chloé');
  perform tests_refus.egal((select count(*)::integer from notification_outbox), 1,
    'et elle est la seule');
end $$;

\echo ''
\echo 'Refus notifié : tous les tests passent.'

rollback;
