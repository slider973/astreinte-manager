-- Tests des purges de conservation (migration 0030, ticket 043).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
-- 1. Notifications : une notification lue il y a plus de 90 jours part, une lue
--    hier reste, une jamais lue part au bout d'un an et pas avant. La frontière
--    est vérifiée **au jour près**, des deux côtés.
-- 2. Journal d'audit : trois ans, à la journée près. Et ce que la purge ne
--    touche pas — l'attribution que l'acte décrivait reste.
-- 3. Invitations : le billet jamais accepté part trente jours après son
--    expiration, l'invitation acceptée trois ans après son acceptation, et
--    l'appartenance qu'elle a créée n'est jamais touchée.
-- 4. File d'attente : une demande traitée part au bout de trente jours ; une
--    demande `pending` ou `sending` **ne part jamais**, même vieille de deux ans.
--    C'est le cas le plus important du fichier : purger une notification pas
--    encore envoyée, c'est perdre l'envoi.
-- 5. Événements de paiement : les fins heureuses partent au bout de
--    quatre-vingt-dix jours, `failed` et `processing` restent sans limite d'âge.
-- 6. Appareils : un jeton non revu depuis plus d'un an part, celui d'hier reste.
-- 7. La tâche `prune_retention` fait les cinq purges d'un coup et rend son compte
--    par table ; rejouée sur le même instant, elle ne supprime plus rien.
-- 8. Les deux tâches sont dans `cron.job`, qualifiées, sans argument, aux
--    horaires de docs/SCHEMA.md § 8 ; aucune des sept fonctions n'est appelable
--    par `anon` ni par `authenticated`.
-- 9. Cloisonnement : une purge n'est pas une porte dérobée. Un administrateur de
--    la caserne A ne peut ni appeler les fonctions, ni supprimer par la main une
--    notification de la caserne B.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Chaque section vide d'abord la table qu'elle éprouve. C'est possible parce que
-- la transaction est annulée à la fin, et c'est ce qui permet de comparer un
-- **compte exact** plutôt qu'un « au moins un » : une purge qui supprimerait une
-- ligne de trop passerait sous un « au moins un ».
--
-- Toutes les dates sont posées relativement à un instant de référence fixe,
-- `2031-06-15 12:00:00+00`, choisi hors des années du seed. Les purges sont
-- appelées avec ce même instant : aucun test ne dépend du jour où il tourne.
--
-- Fixtures : le seed (caserne A = aaaaaaaa-…-001 « CIS Saint-Martin », admin
-- …100, membres …101 à …108 ; caserne B = bbbbbbbb-…-001).

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

create function tests.denied(p_sql text, p_label text) returns void
language plpgsql as $$
declare
  n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n > 0 then
    raise exception 'ECHEC : % — % ligne(s) alors que ça devait être refusé', p_label, n;
  end if;
  raise notice '  ok   % (0 ligne)', p_label;
exception
  when insufficient_privilege then
    raise notice '  ok   % (refusé : %)', p_label, sqlerrm;
end $$;

grant usage on schema tests to authenticated, anon;
grant execute on all functions in schema tests to authenticated, anon;

-- L'instant de référence de tout le fichier.
create function tests.t0() returns timestamptz
language sql immutable as $$ select '2031-06-15 12:00:00+00'::timestamptz $$;

grant execute on function tests.t0() to authenticated, anon;

-- ---------------------------------------------------------------------------
-- 1. Notifications — 90 jours après lecture, 365 jours sans lecture
-- ---------------------------------------------------------------------------
\echo '== 1. notifications'

delete from notifications;

insert into notifications (id, station_id, user_id, type, channel, title, body, created_at, read_at) values
  -- Lue il y a 91 jours : part.
  ('11111111-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001',
   'aaaaaaaa-0000-4000-8000-000000000101', 'assignment_proposed', 'inapp',
   'Lue il y a 91 jours', 'part', tests.t0() - interval '400 days', tests.t0() - interval '91 days'),
  -- Lue il y a 89 jours : reste. La frontière est à 90, pas « autour de 90 ».
  ('11111111-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001',
   'aaaaaaaa-0000-4000-8000-000000000101', 'assignment_proposed', 'inapp',
   'Lue il y a 89 jours', 'reste', tests.t0() - interval '400 days', tests.t0() - interval '89 days'),
  -- Vieille de 400 jours mais lue hier : reste. C'est `read_at` qui compte, et
  -- c'est la lecture prudente des deux.
  ('11111111-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001',
   'aaaaaaaa-0000-4000-8000-000000000102', 'assignment_reminder', 'push',
   'Vieille mais lue hier', 'reste', tests.t0() - interval '400 days', tests.t0() - interval '1 day'),
  -- Jamais lue, créée il y a 366 jours : part.
  ('11111111-0000-4000-8000-000000000004', 'bbbbbbbb-0000-4000-8000-000000000001',
   'bbbbbbbb-0000-4000-8000-000000000101', 'availability_reminder', 'inapp',
   'Jamais lue, 366 jours', 'part', tests.t0() - interval '366 days', null),
  -- Jamais lue, créée il y a 364 jours : reste.
  ('11111111-0000-4000-8000-000000000005', 'bbbbbbbb-0000-4000-8000-000000000001',
   'bbbbbbbb-0000-4000-8000-000000000101', 'availability_reminder', 'inapp',
   'Jamais lue, 364 jours', 'reste', tests.t0() - interval '364 days', null),
  -- Jamais lue, d'hier : reste, évidemment. Le cas nominal du badge non lu.
  ('11111111-0000-4000-8000-000000000006', 'bbbbbbbb-0000-4000-8000-000000000001',
   'bbbbbbbb-0000-4000-8000-000000000102', 'assignment_proposed', 'inapp',
   'Jamais lue, hier', 'reste', tests.t0() - interval '1 day', null);

select tests.check(
  cron_prune_notifications(tests.t0()) = 2,
  'deux notifications supprimées : la lue il y a 91 jours et la jamais lue de 366 jours');

select tests.check(
  (select count(*) from notifications) = 4
  and not exists (select 1 from notifications
                   where id in ('11111111-0000-4000-8000-000000000001',
                                '11111111-0000-4000-8000-000000000004'))
  and (select count(*) from notifications
        where id in ('11111111-0000-4000-8000-000000000002',
                     '11111111-0000-4000-8000-000000000003',
                     '11111111-0000-4000-8000-000000000005',
                     '11111111-0000-4000-8000-000000000006')) = 4,
  'les quatre encore utiles sont là, les deux périmées ne le sont plus');

-- Rejouée sur le même instant : plus rien. L'ordonnanceur rejoue après un
-- redémarrage, et une purge idempotente ne supprime pas deux fois.
select tests.check(
  cron_prune_notifications(tests.t0()) = 0,
  'rejouée sur le même instant, la purge ne supprime plus rien');

-- Les durées sont des paramètres : avec 88 jours, la lue il y a 89 jours part.
-- C'est ce qui rend la frontière vérifiable sans attendre trois mois.
select tests.check(
  cron_prune_notifications(tests.t0(), 88, 363) = 2,
  'durées passées en paramètre : la frontière se déplace à la journée près');

select tests.check(
  not exists (select 1 from notifications
               where id in ('11111111-0000-4000-8000-000000000002',
                            '11111111-0000-4000-8000-000000000005'))
  and (select count(*) from notifications) = 2,
  'et elle emporte exactement les deux lignes que la nouvelle borne désigne');

-- ---------------------------------------------------------------------------
-- 2. Journal d'audit — trois ans
-- ---------------------------------------------------------------------------
\echo '== 2. audit_log'

delete from audit_log;

insert into audit_log (station_id, actor_id, action, entity, entity_id, data, created_at) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000100',
   'availability.set_for_member', 'availability', null, '{}'::jsonb,
   tests.t0() - interval '1096 days'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000100',
   'period.reopen', 'period', null, '{}'::jsonb,
   tests.t0() - interval '1094 days'),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000100',
   'assignment.force', 'assignment', null, '{}'::jsonb,
   tests.t0() - interval '10 days');

select tests.check(
  prune_audit_log(tests.t0()) = 1,
  'un seul acte supprimé : celui de 1096 jours, pas celui de 1094');

select tests.check(
  (select count(*) from audit_log) = 2
  and exists (select 1 from audit_log where action = 'period.reopen')
  and exists (select 1 from audit_log where action = 'assignment.force'),
  'les deux actes de moins de trois ans restent');

-- Deux instructions et non une : une sous-requête placée à côté de l'appel
-- lirait l'instantané du début de l'instruction et verrait encore la ligne que
-- la purge vient de supprimer.
select tests.check(
  prune_audit_log(tests.t0(), 1093) = 1,
  'durée passée en paramètre : la borne se déplace à la journée près');

select tests.check(
  not exists (select 1 from audit_log where action = 'period.reopen'),
  'et l''acte de 1094 jours part avec la nouvelle borne');

-- ---------------------------------------------------------------------------
-- 3. Invitations — le billet mort, puis la trace
-- ---------------------------------------------------------------------------
\echo '== 3. invitations'

delete from invitations;

-- Le nombre d'appartenances avant la purge : c'est lui, et non une constante du
-- seed, que la purge ne doit pas avoir bougé.
create temporary table tests_memberships_avant as select count(*) as n from memberships;

insert into invitations (id, station_id, email, role, invited_by, expires_at, accepted_at, created_at) values
  -- Jamais acceptée, expirée depuis 31 jours : part.
  ('33333333-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001',
   'ancienne@caserne-a.test', 'member', 'aaaaaaaa-0000-4000-8000-000000000100',
   tests.t0() - interval '31 days', null, tests.t0() - interval '45 days'),
  -- Jamais acceptée, expirée depuis 29 jours : reste. L'admin la voit encore et
  -- comprend pourquoi personne n'est entré.
  ('33333333-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001',
   'recente@caserne-a.test', 'member', 'aaaaaaaa-0000-4000-8000-000000000100',
   tests.t0() - interval '29 days', null, tests.t0() - interval '43 days'),
  -- Jamais acceptée, encore valable : reste, évidemment.
  ('33333333-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001',
   'encours@caserne-a.test', 'member', 'aaaaaaaa-0000-4000-8000-000000000100',
   tests.t0() + interval '10 days', null, tests.t0() - interval '4 days'),
  -- Acceptée il y a 1096 jours : part, comme l'acte d'audit qu'elle est devenue.
  ('33333333-0000-4000-8000-000000000004', 'bbbbbbbb-0000-4000-8000-000000000001',
   'entree-2028@caserne-b.test', 'member', 'bbbbbbbb-0000-4000-8000-000000000100',
   tests.t0() - interval '1110 days', tests.t0() - interval '1096 days',
   tests.t0() - interval '1124 days'),
  -- Acceptée le mois dernier : reste.
  ('33333333-0000-4000-8000-000000000005', 'bbbbbbbb-0000-4000-8000-000000000001',
   'entree-recente@caserne-b.test', 'member', 'bbbbbbbb-0000-4000-8000-000000000100',
   tests.t0() - interval '20 days', tests.t0() - interval '30 days',
   tests.t0() - interval '34 days');

select tests.check(
  prune_invitations(tests.t0()) = 2,
  'deux invitations supprimées : l''expirée depuis 31 jours et l''acceptée il y a trois ans');

select tests.check(
  (select count(*) from invitations) = 3
  and not exists (select 1 from invitations
                   where id in ('33333333-0000-4000-8000-000000000001',
                                '33333333-0000-4000-8000-000000000004')),
  'l''invitation en cours, celle qui vient d''expirer et l''entrée récente restent');

-- Ce que la purge ne touche pas : l'appartenance créée par l'invitation
-- acceptée. Le pompier entré en 2028 n'est pas effacé de sa caserne parce que
-- son billet d'entrée a expiré.
select tests.check(
  (select count(*) from memberships) = (select n from tests_memberships_avant),
  'aucune appartenance n''a bougé');

-- ---------------------------------------------------------------------------
-- 4. File d'attente — trente jours après traitement, et jamais avant
-- ---------------------------------------------------------------------------
\echo '== 4. notification_outbox'

delete from notification_outbox;

insert into notification_outbox
  (id, station_id, type, recipients, payload, status, attempts, created_at, processed_at, last_error) values
  -- Envoyée, traitée il y a 31 jours : part.
  ('44444444-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001',
   'assignment_proposed', '[{"user_id": "aaaaaaaa-0000-4000-8000-000000000101"}]'::jsonb,
   '{}'::jsonb, 'sent', 1, tests.t0() - interval '32 days', tests.t0() - interval '31 days', null),
  -- Envoyée, traitée il y a 29 jours : reste.
  ('44444444-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001',
   'assignment_proposed', '[{"user_id": "aaaaaaaa-0000-4000-8000-000000000101"}]'::jsonb,
   '{}'::jsonb, 'sent', 1, tests.t0() - interval '30 days', tests.t0() - interval '29 days', null),
  -- Abandonnée il y a 31 jours : part aussi. L'abandon a laissé sa trace
  -- ailleurs — `notify_trace_echec` (0022) en fait une notification interne, qui
  -- vit, elle, quatre-vingt-dix jours.
  ('44444444-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001',
   'assignment_reminder', '[{"user_id": "aaaaaaaa-0000-4000-8000-000000000102"}]'::jsonb,
   '{}'::jsonb, 'failed', 5, tests.t0() - interval '33 days', tests.t0() - interval '31 days',
   'abandon après 5 tentatives'),
  -- En attente depuis deux ans : **reste**. C'est une notification qui n'est pas
  -- encore partie ; l'âge ne la rend pas facultative.
  ('44444444-0000-4000-8000-000000000004', 'bbbbbbbb-0000-4000-8000-000000000001',
   'schedule_validated', '[{"user_id": "bbbbbbbb-0000-4000-8000-000000000101"}]'::jsonb,
   '{}'::jsonb, 'pending', 2, tests.t0() - interval '730 days', null, null),
  -- Prise en charge il y a deux ans et jamais close : reste elle aussi.
  -- `cron_dispatch_notifications` la remettra en attente, ce n'est pas le travail
  -- d'une purge d'en décider.
  ('44444444-0000-4000-8000-000000000005', 'bbbbbbbb-0000-4000-8000-000000000001',
   'schedule_validated', '[{"user_id": "bbbbbbbb-0000-4000-8000-000000000102"}]'::jsonb,
   '{}'::jsonb, 'sending', 1, tests.t0() - interval '730 days', null, null);

select tests.check(
  prune_notification_outbox(tests.t0()) = 2,
  'deux demandes traitées supprimées, la « sent » et la « failed » de plus de trente jours');

select tests.check(
  (select count(*) from notification_outbox) = 3
  and (select count(*) from notification_outbox where status in ('pending', 'sending')) = 2,
  'la demande en attente et la prise en charge, vieilles de deux ans, sont toujours là');

select tests.check(
  prune_notification_outbox(tests.t0(), 3650) = 0,
  'avec une borne de dix ans, plus rien ne part : aucune ligne terminale ne survit par hasard');

-- ---------------------------------------------------------------------------
-- 5. Événements de paiement — 90 jours, et jamais un échec
-- ---------------------------------------------------------------------------
\echo '== 5. stripe_events'

delete from stripe_events;

insert into stripe_events (id, type, station_id, status, received_at, processed_at, error) values
  ('evt_applique_vieux', 'invoice.paid', 'aaaaaaaa-0000-4000-8000-000000000001',
   'processed', tests.t0() - interval '91 days', tests.t0() - interval '91 days', null),
  ('evt_applique_recent', 'invoice.paid', 'aaaaaaaa-0000-4000-8000-000000000001',
   'processed', tests.t0() - interval '89 days', tests.t0() - interval '89 days', null),
  -- Ignoré et sans date de traitement : `received_at` prend le relais.
  ('evt_ignore_vieux', 'customer.updated', null,
   'skipped', tests.t0() - interval '120 days', null, null),
  -- Échec d'il y a plus d'un an : **reste**. C'est la seule mémoire de ce qui
  -- n'est jamais passé (migration 0023).
  ('evt_echec_ancien', 'invoice.payment_failed', 'bbbbbbbb-0000-4000-8000-000000000001',
   'failed', tests.t0() - interval '400 days', tests.t0() - interval '400 days',
   'station introuvable'),
  -- Traitement interrompu il y a un an : reste aussi, il n'a jamais conclu.
  ('evt_en_cours', 'invoice.paid', 'bbbbbbbb-0000-4000-8000-000000000001',
   'processing', tests.t0() - interval '365 days', null, null);

select tests.check(
  prune_stripe_events(tests.t0()) = 2,
  'deux événements supprimés : l''appliqué de 91 jours et l''ignoré de 120 jours');

select tests.check(
  (select count(*) from stripe_events) = 3
  and exists (select 1 from stripe_events where id = 'evt_echec_ancien')
  and exists (select 1 from stripe_events where id = 'evt_en_cours')
  and exists (select 1 from stripe_events where id = 'evt_applique_recent'),
  'l''échec de 400 jours et le traitement interrompu ne sont jamais purgés');

select tests.check(
  prune_stripe_events(tests.t0(), 1) = 1,
  'avec une borne d''un jour, seul l''appliqué récent part');

select tests.check(
  (select count(*) from stripe_events) = 2
  and exists (select 1 from stripe_events where id = 'evt_echec_ancien')
  and exists (select 1 from stripe_events where id = 'evt_en_cours'),
  'même avec une borne d''un jour, failed et processing survivent');

-- ---------------------------------------------------------------------------
-- 6. Appareils — un an sans usage
-- ---------------------------------------------------------------------------
\echo '== 6. push_tokens'

delete from push_tokens;

insert into push_tokens (user_id, token, platform, device_label, last_seen_at) values
  ('aaaaaaaa-0000-4000-8000-000000000101', 'jeton-abandonne', 'web',
   'iPhone · Safari', tests.t0() - interval '366 days'),
  ('aaaaaaaa-0000-4000-8000-000000000101', 'jeton-limite', 'web',
   'Android · Chrome', tests.t0() - interval '364 days'),
  ('bbbbbbbb-0000-4000-8000-000000000101', 'jeton-vivant', 'web',
   'iPhone · Safari', tests.t0() - interval '1 day');

select tests.check(
  prune_push_tokens(tests.t0()) = 1,
  'un seul jeton supprimé : celui qu''on n''a pas revu depuis 366 jours');

select tests.check(
  (select count(*) from push_tokens) = 2
  and exists (select 1 from push_tokens where token = 'jeton-vivant')
  and exists (select 1 from push_tokens where token = 'jeton-limite'),
  'le jeton d''hier et celui de 364 jours restent');

-- ---------------------------------------------------------------------------
-- 7. La tâche prune_retention — les six purges d'un coup
-- ---------------------------------------------------------------------------
\echo '== 7. cron_prune_retention'

delete from audit_log;
delete from invitations;
delete from invitation_rate_events;
delete from notification_outbox;
delete from push_tokens;
delete from stripe_events;

insert into audit_log (station_id, actor_id, action, entity, data, created_at) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000100',
   'period.reopen', 'period', '{}'::jsonb, tests.t0() - interval '4 years'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000100',
   'period.reopen', 'period', '{}'::jsonb, tests.t0() - interval '1 day');

insert into invitations (station_id, email, invited_by, expires_at, accepted_at, created_at) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'perdue@caserne-a.test',
   'aaaaaaaa-0000-4000-8000-000000000100',
   tests.t0() - interval '200 days', null, tests.t0() - interval '214 days');

-- Le compteur d'invitations (migration 0032) : une semaine de conservation, la
-- plus courte de la tâche — la fenêtre du plafond ne fait qu'une heure.
insert into invitation_rate_events (station_id, actor_id, created_at) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000100',
   tests.t0() - interval '8 days'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000100',
   tests.t0() - interval '6 days');

insert into notification_outbox
  (station_id, type, recipients, payload, status, created_at, processed_at) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'assignment_proposed',
   '[{"user_id": "aaaaaaaa-0000-4000-8000-000000000101"}]'::jsonb, '{}'::jsonb,
   'sent', tests.t0() - interval '100 days', tests.t0() - interval '100 days'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'assignment_proposed',
   '[{"user_id": "aaaaaaaa-0000-4000-8000-000000000101"}]'::jsonb, '{}'::jsonb,
   'sent', tests.t0() - interval '100 days', tests.t0() - interval '2 days');

insert into push_tokens (user_id, token, platform, last_seen_at) values
  ('aaaaaaaa-0000-4000-8000-000000000101', 'jeton-oublie', 'web', tests.t0() - interval '3 years');

insert into stripe_events (id, type, station_id, status, received_at, processed_at) values
  ('evt_retention_1', 'invoice.paid', 'aaaaaaaa-0000-4000-8000-000000000001',
   'processed', tests.t0() - interval '200 days', tests.t0() - interval '200 days'),
  ('evt_retention_2', 'invoice.paid', 'aaaaaaaa-0000-4000-8000-000000000001',
   'processed', tests.t0() - interval '200 days', tests.t0() - interval '200 days');

select tests.check(
  cron_prune_retention(tests.t0()) = jsonb_build_object(
    'audit_log', 1,
    'invitations', 1,
    'invitation_rate_events', 1,
    'notification_outbox', 1,
    'push_tokens', 1,
    'stripe_events', 2),
  'la tâche rend son compte table par table, et non un total indéchiffrable');

select tests.check(
  (select count(*) from audit_log) = 1
  and (select count(*) from invitations) = 0
  and (select count(*) from invitation_rate_events) = 1
  and (select count(*) from notification_outbox) = 1
  and (select count(*) from push_tokens) = 0
  and (select count(*) from stripe_events) = 0,
  'et le travail est fait : il ne reste que ce qui est encore dans sa durée');

select tests.check(
  cron_prune_retention(tests.t0()) = jsonb_build_object(
    'audit_log', 0, 'invitations', 0, 'invitation_rate_events', 0,
    'notification_outbox', 0, 'push_tokens', 0, 'stripe_events', 0),
  'rejouée sur le même instant, elle ne supprime plus rien');

-- Appelée sans argument — la forme exacte de la commande de l'ordonnanceur —
-- elle travaille sur `now()`. Rien du seed n'est assez vieux pour partir :
-- les seules lignes restantes sont celles d'hier.
select tests.check(
  cron_prune_retention() = jsonb_build_object(
    'audit_log', 0, 'invitations', 0, 'invitation_rate_events', 0,
    'notification_outbox', 0, 'push_tokens', 0, 'stripe_events', 0),
  'appelée sans argument, sur now(), elle ne supprime rien de récent');

select tests.check(
  cron_prune_notifications() = 0,
  'et la purge des notifications non plus');

-- ---------------------------------------------------------------------------
-- 8. Les tâches planifiées et les droits
-- ---------------------------------------------------------------------------
\echo '== 8. cron.job et droits'

select tests.check(
  (select count(*) from cron.job
    where jobname = 'prune_notifications'
      and command = 'select public.cron_prune_notifications();') = 1,
  'la tâche prune_notifications est planifiée, qualifiée et sans argument');

select tests.check(
  (select schedule from cron.job where jobname = 'prune_notifications') = '0 4 * * 0',
  'hebdomadaire, dimanche 04:00 (docs/SCHEMA.md § 8)');

select tests.check(
  (select count(*) from cron.job
    where jobname = 'prune_retention'
      and command = 'select public.cron_prune_retention();') = 1,
  'la tâche prune_retention est planifiée, qualifiée et sans argument');

select tests.check(
  (select schedule from cron.job where jobname = 'prune_retention') = '20 4 * * 0',
  'hebdomadaire, dimanche 04:20 (docs/SCHEMA.md § 8)');

-- Huit fonctions, aucune appelable depuis l'application. Une purge appelable par
-- un client serait un « delete » sans politique RLS : la fonction est
-- `security definer`, elle s'exécute avec les droits de son propriétaire.
select tests.check(
  bool_and(not has_function_privilege(r.role, f.signature, 'execute')),
  'aucune fonction de purge n''est appelable par anon ni par authenticated')
from (values
  ('public.cron_prune_notifications(timestamptz, integer, integer)'),
  ('public.cron_prune_retention(timestamptz)'),
  ('public.prune_audit_log(timestamptz, integer)'),
  ('public.prune_invitations(timestamptz, integer, integer)'),
  ('public.prune_invitation_rate_events(timestamptz, integer)'),
  ('public.prune_notification_outbox(timestamptz, integer)'),
  ('public.prune_push_tokens(timestamptz, integer)'),
  ('public.prune_stripe_events(timestamptz, integer)')
) as f(signature)
cross join (values ('anon'), ('authenticated')) as r(role);

-- Les huit sont bien `security definer` avec un `search_path` figé : sans cela,
-- un objet posé dans un schéma temporaire pourrait détourner un `delete`.
select tests.check(
  count(*) = 8,
  'les huit sont security definer avec search_path figé sur public, pg_temp')
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('cron_prune_notifications', 'cron_prune_retention',
                    'prune_audit_log', 'prune_invitations',
                    'prune_invitation_rate_events',
                    'prune_notification_outbox', 'prune_push_tokens',
                    'prune_stripe_events')
  and p.prosecdef
  and 'search_path=public, pg_temp' = any(p.proconfig);

-- ---------------------------------------------------------------------------
-- 9. Cloisonnement — une purge n'est pas une porte dérobée
-- ---------------------------------------------------------------------------
\echo '== 9. cloisonnement'

insert into notifications (id, station_id, user_id, type, channel, title, body, created_at, read_at) values
  ('99999999-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000001',
   'bbbbbbbb-0000-4000-8000-000000000101', 'assignment_proposed', 'inapp',
   'Caserne B', 'ne doit pas bouger', tests.t0() - interval '400 days',
   tests.t0() - interval '400 days');

set local role authenticated;
set local request.jwt.claims to '{"sub": "aaaaaaaa-0000-4000-8000-000000000100", "role": "authenticated"}';

select tests.denied(
  $$select cron_prune_notifications()$$,
  'un administrateur de la caserne A ne peut pas appeler cron_prune_notifications');

select tests.denied(
  $$select cron_prune_retention()$$,
  'ni cron_prune_retention');

select tests.denied(
  $$select prune_audit_log()$$,
  'ni prune_audit_log');

-- Et la vieille notification de la caserne B lui reste hors de portée, purge ou
-- pas purge : c'est la RLS de 0007 qui le dit, on vérifie seulement qu'aucune
-- des fonctions de ce fichier ne l'a affaiblie.
select tests.denied(
  $$delete from notifications where id = '99999999-0000-4000-8000-000000000001'$$,
  'ni supprimer à la main une notification de la caserne B');

reset role;

select tests.check(
  exists (select 1 from notifications where id = '99999999-0000-4000-8000-000000000001'),
  'la notification de la caserne B est toujours là');

\echo ''
\echo 'purges_conservation_test.sql : tout est passé.'

rollback;
