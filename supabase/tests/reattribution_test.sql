-- Tests de la réattribution et de l'annulation (migration 0020, ticket 020).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
-- 1. `assignments_guard_reattribution` : ni `replaced`, ni `cancelled`, ni
--    `replaced_by` ne s'écrivent depuis un client, **administrateur compris**.
--    Sans cette garde, une requête PostgREST retirait sa garde à un pompier
--    sans que rien ne parte.
-- 2. Les refus métier de `reassign_shift`, les huit.
-- 3. **Le scénario fondateur du produit** : un refus, une réattribution, et
--    *une seule* notification — au nouveau membre. Le refus reste un refus, le
--    lien `replaced_by` est posé, et **le reste du planning n'a pas bougé**.
-- 4. La réattribution d'une garde **acquise** : l'ancienne passe `replaced`,
--    l'ancien est prévenu, et le planning validé repasse en `published` sans
--    que `published_at` ne soit réécrit.
-- 5. Le lien implicite : pourvoir un créneau sans désigner d'ancienne
--    attribution rattache la nouvelle au plus ancien refus non remplacé.
-- 6. `cancel_assignment` : une garde acquise annulée prévient son titulaire,
--    une proposition retirée avant réponse ne prévient personne, et le planning
--    se réévalue dans les deux cas.
-- 7. Les droits : `reassign_shift` fermée aux clients, `cancel_assignment`
--    ouverte à `authenticated` qui la garde par `is_admin`.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : une caserne « CIS Réattribution » et une voisine, sur l'année 2029
-- que ni le seed ni les autres fichiers ne touchent.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_rea;

create function tests_rea.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

create function tests_rea.egal(p_obtenu anyelement, p_attendu anyelement, p_label text) returns void
language plpgsql as $$
begin
  if p_obtenu is distinct from p_attendu then
    raise exception 'ECHEC : % — obtenu [%], attendu [%]', p_label, p_obtenu, p_attendu;
  end if;
  raise notice '  ok   % = %', p_label, coalesce(p_obtenu::text, 'NULL');
end $$;

create function tests_rea.refuse(p_sql text, p_erreur text, p_label text) returns void
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

-- Le code métier d'un refus rendu par une fonction. Aucune exception : ces
-- fonctions répondent `{"ok": false, "code": …}`, l'Edge Function traduit.
create function tests_rea.code(p_resultat jsonb, p_code text, p_label text) returns void
language plpgsql as $$
begin
  if (p_resultat ->> 'ok')::boolean is not false then
    raise exception 'ECHEC : % — la fonction a répondu ok, refus [%] attendu', p_label, p_code;
  end if;
  if p_resultat ->> 'code' is distinct from p_code then
    raise exception 'ECHEC : % — code [%] au lieu de [%]',
      p_label, p_resultat ->> 'code', p_code;
  end if;
  raise notice '  ok   % (%)', p_label, p_code;
end $$;

grant usage on schema tests_rea to authenticated, anon;
grant execute on all functions in schema tests_rea to authenticated, anon;

-- ---------------------------------------------------------------------------
-- `notify_post` sans réseau — même substitution que `publication_test.sql`.
-- L'effet de bord sur la file est conservé, l'appel HTTP est coupé : c'est lui
-- qui n'a rien à faire dans une CI sans Edge Functions. Compter les lignes de
-- `notification_outbox` reste donc la façon exacte de compter les notifications
-- qui partiront.
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
\echo '=== Réattribution et annulation (0020) ==='

-- ===========================================================================
-- Fixtures
-- ===========================================================================
-- R « CIS Réattribution » : 1 admin, 3 membres actifs, 1 désactivé.
-- V « CIS Voisine 4 » : 1 admin, pour le cloisonnement.
--
-- Un planning de février 2029 réduit à **quatre créneaux** : la réattribution
-- se juge sur un créneau à la fois, et un planning de 56 créneaux ne dirait
-- rien de plus tout en rendant « le planning est-il complet ? » illisible.

insert into stations (id, name, slug, timezone, settings) values
  ('77777777-0000-4000-8000-000000000001', 'CIS Réattribution', 'cis-reattribution', 'Europe/Paris',
   '{"day_start": "07:00", "day_end": "19:00",
     "required_day": 1, "required_night": 1,
     "required_overrides": {},
     "availability_deadline_day": 15,
     "response_reminder_hours": 24, "response_email_hours": 48,
     "late_report_hours": 72}'::jsonb),
  ('88888888-0000-4000-8000-000000000001', 'CIS Voisine 4', 'cis-voisine-4', 'Europe/Paris',
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
  ('77777777-0000-4000-8000-000000000100'::uuid, 'admin@reattribution.test',  'Nadia',  'Aloui'),
  ('77777777-0000-4000-8000-000000000101'::uuid, 'bruno@reattribution.test',  'Bruno',  'Bertin'),
  ('77777777-0000-4000-8000-000000000102'::uuid, 'chloe@reattribution.test',  'Chloé',  'Colin'),
  ('77777777-0000-4000-8000-000000000103'::uuid, 'damien@reattribution.test', 'Damien', 'Denis'),
  ('77777777-0000-4000-8000-000000000104'::uuid, 'eve@reattribution.test',    'Eve',    'Evrard'),
  ('88888888-0000-4000-8000-000000000100'::uuid, 'admin@voisine4.test',       'Farid',  'Fauré')
) as u(id, email, first_name, last_name);

insert into memberships (station_id, user_id, role, status, display_name) values
  ('77777777-0000-4000-8000-000000000001', '77777777-0000-4000-8000-000000000100', 'admin',  'active',   'Nadia A.'),
  ('77777777-0000-4000-8000-000000000001', '77777777-0000-4000-8000-000000000101', 'member', 'active',   'Bruno B.'),
  ('77777777-0000-4000-8000-000000000001', '77777777-0000-4000-8000-000000000102', 'member', 'active',   'Chloé C.'),
  ('77777777-0000-4000-8000-000000000001', '77777777-0000-4000-8000-000000000103', 'member', 'active',   'Damien D.'),
  ('77777777-0000-4000-8000-000000000001', '77777777-0000-4000-8000-000000000104', 'member', 'disabled', 'Eve E.'),
  ('88888888-0000-4000-8000-000000000001', '88888888-0000-4000-8000-000000000100', 'admin',  'active',   'Farid F.');

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('77777777-0000-4000-8000-000000000202', '77777777-0000-4000-8000-000000000001', 2029, 2, 'locked', '2029-01-15 23:59:59+01');

insert into schedules (id, station_id, period_id, created_by) values
  ('77777777-0000-4000-8000-000000000302',
   '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000202',
   '77777777-0000-4000-8000-000000000100');

insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  ('77777777-0000-4000-8000-000000000401', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000302', '2029-02-01', 'day',   1),
  ('77777777-0000-4000-8000-000000000402', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000302', '2029-02-01', 'night', 1),
  ('77777777-0000-4000-8000-000000000403', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000302', '2029-02-02', 'day',   1),
  ('77777777-0000-4000-8000-000000000404', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000302', '2029-02-02', 'night', 0);

-- Damien s'est déclaré disponible le 1er février de jour ; Bruno n'a rien dit
-- du 1er février de nuit. La trace `was_available` se juge là-dessus.
insert into availabilities (station_id, user_id, date, slot, status, set_by) values
  ('77777777-0000-4000-8000-000000000001', '77777777-0000-4000-8000-000000000103',
   '2029-02-01', 'day', 'available', '77777777-0000-4000-8000-000000000103'),
  ('77777777-0000-4000-8000-000000000001', '77777777-0000-4000-8000-000000000102',
   '2029-02-02', 'day', 'available', '77777777-0000-4000-8000-000000000102');

-- ===========================================================================
-- 1. Les trois colonnes que personne n'écrit à la main
-- ===========================================================================
\echo ''
\echo '--- 1. replaced, cancelled et replaced_by sont réservés aux fonctions'
savepoint s1;

update schedules set status = 'published'
 where id = '77777777-0000-4000-8000-000000000302';

insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by) values
  ('77777777-0000-4000-8000-000000000501', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000401', '77777777-0000-4000-8000-000000000101',
   'proposed', now(), '77777777-0000-4000-8000-000000000100'),
  ('77777777-0000-4000-8000-000000000502', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000402', '77777777-0000-4000-8000-000000000102',
   'accepted', now(), '77777777-0000-4000-8000-000000000100');

set local role authenticated;
set local request.jwt.claims = '{"sub":"77777777-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  -- C'est **un administrateur** qui essaie, et c'est tout l'intérêt du test :
  -- `assignments_update_admin` (0008) le laisse écrire n'importe quel statut, et
  -- `assignments_member_transition` (0008) le laisse passer dès sa première
  -- ligne. Seul le déclencheur de ce ticket l'arrête.
  perform tests_rea.refuse(
    $sql$update assignments set status = 'cancelled'
          where id = '77777777-0000-4000-8000-000000000502'$sql$,
    'assignment_transition_reserved',
    'un admin ne passe pas une attribution en cancelled depuis un client');

  perform tests_rea.refuse(
    $sql$update assignments set status = 'replaced'
          where id = '77777777-0000-4000-8000-000000000502'$sql$,
    'assignment_transition_reserved',
    'un admin ne passe pas une attribution en replaced depuis un client');

  perform tests_rea.refuse(
    $sql$update assignments
            set replaced_by = '77777777-0000-4000-8000-000000000502'
          where id = '77777777-0000-4000-8000-000000000501'$sql$,
    'assignment_link_reserved',
    'un admin ne pose pas replaced_by depuis un client');

  -- Ce que l'admin garde le droit de faire, et qui ne doit pas être cassé :
  -- écrire une attribution ordinaire.
  update assignments set reminder_count = 1
   where id = '77777777-0000-4000-8000-000000000501';
  perform tests_rea.egal(
    (select reminder_count from assignments
      where id = '77777777-0000-4000-8000-000000000501'),
    1, 'un admin écrit toujours les colonnes ordinaires');
end $$;

reset role;

rollback to savepoint s1;
release savepoint s1;

-- ===========================================================================
-- 2. Les refus métier de reassign_shift
-- ===========================================================================
\echo ''
\echo '--- 2. Les huit refus de reassign_shift'
savepoint s2;

insert into assignments (id, station_id, shift_id, user_id, status, created_by) values
  ('77777777-0000-4000-8000-000000000511', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000401', '77777777-0000-4000-8000-000000000101',
   'proposed', '77777777-0000-4000-8000-000000000100');

do $$
declare
  r jsonb;
begin
  -- Un créneau inconnu.
  perform tests_rea.code(
    reassign_shift('77777777-0000-4000-8000-0000000004ff',
                   '77777777-0000-4000-8000-000000000103',
                   '77777777-0000-4000-8000-000000000100'),
    'shift_not_found', 'créneau inconnu');

  -- Le planning est encore en brouillon : on y attribue et on y retire, on n'y
  -- réattribue pas — rien n'est parti.
  perform tests_rea.code(
    reassign_shift('77777777-0000-4000-8000-000000000401',
                   '77777777-0000-4000-8000-000000000103',
                   '77777777-0000-4000-8000-000000000100'),
    'schedule_not_published', 'un brouillon ne se réattribue pas');

  update schedules set status = 'published'
   where id = '77777777-0000-4000-8000-000000000302';

  -- L'acteur n'administre pas cette caserne.
  perform tests_rea.code(
    reassign_shift('77777777-0000-4000-8000-000000000401',
                   '77777777-0000-4000-8000-000000000103',
                   '88888888-0000-4000-8000-000000000100'),
    'not_admin', 'l''admin de la caserne voisine est refusé');

  -- L'acteur est membre, pas administrateur.
  perform tests_rea.code(
    reassign_shift('77777777-0000-4000-8000-000000000401',
                   '77777777-0000-4000-8000-000000000103',
                   '77777777-0000-4000-8000-000000000101'),
    'not_admin', 'un membre simple est refusé');

  -- Le nouveau n'est pas un membre actif.
  perform tests_rea.code(
    reassign_shift('77777777-0000-4000-8000-000000000401',
                   '77777777-0000-4000-8000-000000000104',
                   '77777777-0000-4000-8000-000000000100'),
    'member_not_active', 'un membre désactivé ne reçoit pas de créneau');

  -- Déjà en place sur ce créneau : l'autre administrateur a été plus rapide.
  perform tests_rea.code(
    reassign_shift('77777777-0000-4000-8000-000000000401',
                   '77777777-0000-4000-8000-000000000101',
                   '77777777-0000-4000-8000-000000000100'),
    'already_assigned', 'un membre déjà attribué n''est pas attribué deux fois');

  -- L'ancienne attribution désignée n'est pas sur ce créneau.
  perform tests_rea.code(
    reassign_shift('77777777-0000-4000-8000-000000000402',
                   '77777777-0000-4000-8000-000000000103',
                   '77777777-0000-4000-8000-000000000100',
                   '77777777-0000-4000-8000-000000000511'),
    'assignment_not_found', 'une ancienne attribution d''un autre créneau est refusée');

  -- Une attribution déjà remplacée ne se remplace pas deux fois : son lien
  -- pointerait ailleurs et l'historique se contredirait.
  r := reassign_shift('77777777-0000-4000-8000-000000000401',
                      '77777777-0000-4000-8000-000000000103',
                      '77777777-0000-4000-8000-000000000100',
                      '77777777-0000-4000-8000-000000000511');
  perform tests_rea.check((r ->> 'ok')::boolean, 'la première réattribution passe');

  perform tests_rea.code(
    reassign_shift('77777777-0000-4000-8000-000000000401',
                   '77777777-0000-4000-8000-000000000102',
                   '77777777-0000-4000-8000-000000000100',
                   '77777777-0000-4000-8000-000000000511'),
    'assignment_not_replaceable', 'une attribution déjà remplacée ne se remplace pas deux fois');

  -- Caserne suspendue : l'application entière est en lecture seule.
  insert into subscriptions (station_id, status, plan)
  values ('77777777-0000-4000-8000-000000000001', 'suspended', 'starter');

  perform tests_rea.code(
    reassign_shift('77777777-0000-4000-8000-000000000402',
                   '77777777-0000-4000-8000-000000000103',
                   '77777777-0000-4000-8000-000000000100'),
    'station_suspended', 'une caserne suspendue ne réattribue rien');
end $$;

rollback to savepoint s2;
release savepoint s2;

-- ===========================================================================
-- 3. Le scénario fondateur : un refus, une réattribution, UNE notification
-- ===========================================================================
\echo ''
\echo '--- 3. Un refus réattribué : une seule notification, au nouveau membre'
savepoint s3;

update schedules set status = 'published'
 where id = '77777777-0000-4000-8000-000000000302';

-- Le mois publié : Bruno sur le 1er jour, Chloé sur le 1er nuit, Damien sur le
-- 2 jour. Bruno refuse ; les deux autres ne doivent pas bouger d'un octet.
insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by) values
  ('77777777-0000-4000-8000-000000000521', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000401', '77777777-0000-4000-8000-000000000101',
   'proposed', now() - interval '2 hours', '77777777-0000-4000-8000-000000000100'),
  ('77777777-0000-4000-8000-000000000522', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000402', '77777777-0000-4000-8000-000000000102',
   'accepted', now() - interval '2 hours', '77777777-0000-4000-8000-000000000100'),
  ('77777777-0000-4000-8000-000000000523', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000403', '77777777-0000-4000-8000-000000000103',
   'proposed', now() - interval '2 hours', '77777777-0000-4000-8000-000000000100');

-- Le refus de Bruno, tel qu'il l'écrit depuis son écran.
update assignments
   set status = 'declined', responded_at = now(), decline_reason = 'en formation ce week-end'
 where id = '77777777-0000-4000-8000-000000000521';

delete from notification_outbox;

do $$
declare
  r          jsonb;
  nouvelle   assignments;
  ancienne   assignments;
  avant_522  assignments;
  avant_523  assignments;
  demandes   integer;
  demande    notification_outbox;
begin
  select * into avant_522 from assignments where id = '77777777-0000-4000-8000-000000000522';
  select * into avant_523 from assignments where id = '77777777-0000-4000-8000-000000000523';

  r := reassign_shift('77777777-0000-4000-8000-000000000401',
                      '77777777-0000-4000-8000-000000000103',
                      '77777777-0000-4000-8000-000000000100',
                      '77777777-0000-4000-8000-000000000521');

  perform tests_rea.check((r ->> 'ok')::boolean, 'la réattribution aboutit');
  perform tests_rea.egal(r ->> 'previous_status', 'declined',
    'la fonction rend le statut de l''ancienne attribution');
  perform tests_rea.egal((r ->> 'previous_notified')::boolean, false,
    'l''ancien n''est pas notifié : c''est lui qui a refusé');
  perform tests_rea.egal(r ->> 'period', '2029-02', 'la période est rendue en AAAA-MM');

  select * into nouvelle from assignments where id = (r ->> 'assignment_id')::uuid;
  select * into ancienne from assignments where id = '77777777-0000-4000-8000-000000000521';

  -- La nouvelle : proposée, **horodatée**, tracée.
  perform tests_rea.egal(nouvelle.status, 'proposed'::assignment_status,
    'la nouvelle attribution est proposée');
  perform tests_rea.check(nouvelle.proposed_at is not null,
    'la nouvelle attribution est horodatée : les crons de relance la verront');
  perform tests_rea.egal(nouvelle.user_id, '77777777-0000-4000-8000-000000000103'::uuid,
    'la nouvelle attribution est celle de Damien');
  perform tests_rea.egal(nouvelle.created_by, '77777777-0000-4000-8000-000000000100'::uuid,
    'created_by porte l''acteur, posé par la fonction et non par le déclencheur client');
  perform tests_rea.egal(nouvelle.was_available, true,
    'was_available est relu dans availabilities : Damien s''était déclaré disponible');

  -- L'ancienne : le refus **reste un refus**, et il porte le fil.
  perform tests_rea.egal(ancienne.status, 'declined'::assignment_status,
    'le refus reste un refus : il est l''histoire de la caserne');
  perform tests_rea.egal(ancienne.replaced_by, nouvelle.id,
    'replaced_by relie le refus à l''attribution qui l''a couvert');
  perform tests_rea.egal(ancienne.decline_reason, 'en formation ce week-end',
    'le motif du refus est intact');

  -- **Une seule demande de notification, et elle est pour Damien.**
  select count(*)::integer into demandes from notification_outbox;
  perform tests_rea.egal(demandes, 1,
    'un refus réattribué ne produit qu''UNE notification');

  select * into demande from notification_outbox limit 1;
  perform tests_rea.egal(demande.type, 'assignment_proposed'::notification_type,
    'la notification est une proposition d''astreinte');
  perform tests_rea.egal(jsonb_array_length(demande.recipients), 1,
    'elle a un seul destinataire');
  perform tests_rea.egal(demande.recipients -> 0 ->> 'user_id',
    '77777777-0000-4000-8000-000000000103',
    'le destinataire est le nouveau membre');
  perform tests_rea.egal(
    demande.recipients -> 0 -> 'payload' -> 'shifts' -> 0 ->> 'date', '2029-02-01',
    'la charge utile porte la date du créneau');
  perform tests_rea.egal(
    demande.recipients -> 0 -> 'payload' -> 'shifts' -> 0 ->> 'assignment_id',
    nouvelle.id::text,
    'la charge utile porte l''identifiant de la nouvelle attribution');

  -- **Le reste du planning n'a pas bougé.** C'est la promesse du produit, et
  -- c'est la comparaison ligne à ligne qui la vérifie, pas un compteur.
  perform tests_rea.check(
    (select a from assignments a where a.id = '77777777-0000-4000-8000-000000000522') = avant_522,
    'l''acceptation de Chloé est intacte, au champ près');
  perform tests_rea.check(
    (select a from assignments a where a.id = '77777777-0000-4000-8000-000000000523') = avant_523,
    'la proposition en attente de Damien sur un autre créneau est intacte');

  -- Le planning reste publié : une proposition n'est pas une acceptation.
  perform tests_rea.egal(
    (select status from schedules where id = '77777777-0000-4000-8000-000000000302'),
    'published'::schedule_status, 'le planning reste publié');

  -- Le journal de la caserne.
  perform tests_rea.egal(
    (select count(*)::integer from audit_log
      where action = 'assignment.reassigned'
        and station_id = '77777777-0000-4000-8000-000000000001'),
    1, 'la réattribution est journalisée une fois');
  perform tests_rea.egal(
    (select data ->> 'previous_status' from audit_log
      where action = 'assignment.reassigned'
        and station_id = '77777777-0000-4000-8000-000000000001'),
    'declined', 'le journal dit ce que remplaçait la nouvelle attribution');
end $$;

rollback to savepoint s3;
release savepoint s3;

-- ===========================================================================
-- 4. Réattribuer une garde acquise : l'ancien est prévenu, le planning recule
-- ===========================================================================
\echo ''
\echo '--- 4. Une acceptation remplacée : deux notifications, et validated -> published'
savepoint s4;

update schedules set status = 'published'
 where id = '77777777-0000-4000-8000-000000000302';

-- Trois créneaux à pourvoir (le quatrième demande zéro personne), tous
-- acceptés : le planning est complet, donc validé.
insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by) values
  ('77777777-0000-4000-8000-000000000531', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000401', '77777777-0000-4000-8000-000000000101',
   'proposed', now(), '77777777-0000-4000-8000-000000000100'),
  ('77777777-0000-4000-8000-000000000532', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000402', '77777777-0000-4000-8000-000000000102',
   'proposed', now(), '77777777-0000-4000-8000-000000000100'),
  ('77777777-0000-4000-8000-000000000533', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000403', '77777777-0000-4000-8000-000000000103',
   'proposed', now(), '77777777-0000-4000-8000-000000000100');

update assignments set status = 'accepted', responded_at = now()
 where id in ('77777777-0000-4000-8000-000000000531',
              '77777777-0000-4000-8000-000000000532',
              '77777777-0000-4000-8000-000000000533');

delete from notification_outbox;

do $$
declare
  r         jsonb;
  planning  schedules;
  publie_le timestamptz;
  ancienne  assignments;
  demandes  integer;
begin
  select * into planning from schedules where id = '77777777-0000-4000-8000-000000000302';
  publie_le := planning.published_at;
  perform tests_rea.egal(planning.status, 'validated'::schedule_status,
    'trois acceptations sur trois créneaux requis : le planning est validé');

  -- Bruno tenait le 1er février de jour, accepté. On le remplace par Damien,
  -- qui n'a rien déclaré ce jour-là : la trace `was_available` doit le dire.
  r := reassign_shift('77777777-0000-4000-8000-000000000401',
                      '77777777-0000-4000-8000-000000000102',
                      '77777777-0000-4000-8000-000000000100',
                      '77777777-0000-4000-8000-000000000531');

  perform tests_rea.check((r ->> 'ok')::boolean, 'la réattribution d''une garde acquise aboutit');
  perform tests_rea.egal(r ->> 'previous_status', 'accepted',
    'la fonction rend l''état acquis de l''ancienne attribution');
  perform tests_rea.egal((r ->> 'previous_notified')::boolean, true,
    'l''ancien est prévenu : il croyait tenir cette garde');
  perform tests_rea.egal((r ->> 'was_available')::boolean, false,
    'Chloé n''avait rien déclaré ce jour-là : l''attribution est tracée hors disponibilité');

  select * into ancienne from assignments where id = '77777777-0000-4000-8000-000000000531';
  perform tests_rea.egal(ancienne.status, 'replaced'::assignment_status,
    'une acceptation remplacée passe en replaced');
  perform tests_rea.egal(ancienne.replaced_by, (r ->> 'assignment_id')::uuid,
    'replaced_by pointe la nouvelle attribution');

  -- Deux demandes : la proposition au nouveau, l'annulation à l'ancien.
  select count(*)::integer into demandes from notification_outbox;
  perform tests_rea.egal(demandes, 2,
    'une garde acquise remplacée notifie deux personnes, et deux seulement');
  perform tests_rea.egal(
    (select recipients -> 0 ->> 'user_id' from notification_outbox
      where type = 'assignment_proposed'),
    '77777777-0000-4000-8000-000000000102', 'la proposition part au nouveau membre');
  perform tests_rea.egal(
    (select recipients -> 0 ->> 'user_id' from notification_outbox
      where type = 'assignment_cancelled'),
    '77777777-0000-4000-8000-000000000101', 'l''annulation part à l''ancien titulaire');
  perform tests_rea.egal(
    (select payload -> 'shifts' -> 0 ->> 'slot' from notification_outbox
      where type = 'assignment_cancelled'),
    'day', 'l''annulation dit de quel créneau il s''agit');
  perform tests_rea.check(
    (select payload ->> 'reason' is not null from notification_outbox
      where type = 'assignment_cancelled'),
    'l''annulation dit pourquoi : « annulée » sans raison produit un coup de téléphone');

  -- **Le planning recule, et son histoire ne se réécrit pas.**
  select * into planning from schedules where id = '77777777-0000-4000-8000-000000000302';
  perform tests_rea.egal(planning.status, 'published'::schedule_status,
    'une acceptation qui disparaît ramène le planning validé en publié');
  perform tests_rea.check(planning.validated_at is null,
    'un planning qui n''est plus validé n''a plus de date de validation');
  perform tests_rea.egal(planning.published_at, publie_le,
    'published_at reste celui de la première publication');

  -- Les deux autres créneaux n'ont pas bougé.
  perform tests_rea.egal(
    (select count(*)::integer from assignments
      where id in ('77777777-0000-4000-8000-000000000532',
                   '77777777-0000-4000-8000-000000000533')
        and status = 'accepted'),
    2, 'les deux autres acceptations tiennent toujours');

  -- Et quand le nouveau accepte, le planning se revalide tout seul.
  update assignments set status = 'accepted', responded_at = now()
   where id = (r ->> 'assignment_id')::uuid;
  perform tests_rea.egal(
    (select status from schedules where id = '77777777-0000-4000-8000-000000000302'),
    'validated'::schedule_status,
    'le remplaçant accepte : le planning se revalide sans rien republier');
end $$;

rollback to savepoint s4;
release savepoint s4;

-- ===========================================================================
-- 5. Le lien implicite
-- ===========================================================================
\echo ''
\echo '--- 5. Pourvoir un créneau refusé sans désigner l''ancienne attribution'
savepoint s5;

update schedules set status = 'published'
 where id = '77777777-0000-4000-8000-000000000302';

insert into assignments (id, station_id, shift_id, user_id, status, proposed_at,
                         responded_at, decline_reason, created_by) values
  ('77777777-0000-4000-8000-000000000541', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000401', '77777777-0000-4000-8000-000000000101',
   'declined', now() - interval '3 hours', now() - interval '2 hours', 'en formation',
   '77777777-0000-4000-8000-000000000100'),
  ('77777777-0000-4000-8000-000000000542', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000401', '77777777-0000-4000-8000-000000000102',
   'declined', now() - interval '3 hours', now() - interval '1 hours', 'indisponible',
   '77777777-0000-4000-8000-000000000100');

do $$
declare
  r jsonb;
begin
  r := reassign_shift('77777777-0000-4000-8000-000000000401',
                      '77777777-0000-4000-8000-000000000103',
                      '77777777-0000-4000-8000-000000000100');

  perform tests_rea.check((r ->> 'ok')::boolean, 'pourvoir un créneau refusé aboutit');
  perform tests_rea.egal(r ->> 'previous_id', '77777777-0000-4000-8000-000000000541',
    'le lien se pose sur le PLUS ANCIEN refus non encore remplacé');
  perform tests_rea.egal(
    (select replaced_by::text from assignments
      where id = '77777777-0000-4000-8000-000000000541'),
    r ->> 'assignment_id', 'le premier refus porte le fil');
  perform tests_rea.check(
    (select replaced_by is null from assignments
      where id = '77777777-0000-4000-8000-000000000542'),
    'le second refus reste sans lien : une attribution ne couvre qu''un trou');
  perform tests_rea.egal(
    (select count(*)::integer from assignments
      where shift_id = '77777777-0000-4000-8000-000000000401' and status = 'declined'),
    2, 'les deux refus restent des refus');
end $$;

-- **Une annulation se repourvoit comme un refus.** C'est le cas que l'écran de
-- suivi produit le plus souvent après le ticket 020 : une garde retirée par la
-- caserne laisse exactement le même trou qu'un refus, et le geste est le même.
do $$
declare
  r jsonb;
begin
  insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by)
  values ('77777777-0000-4000-8000-000000000543', '77777777-0000-4000-8000-000000000001',
          '77777777-0000-4000-8000-000000000402', '77777777-0000-4000-8000-000000000101',
          'proposed', now(), '77777777-0000-4000-8000-000000000100');
  -- L'annulation est posée directement : ce bloc tourne sous le rôle
  -- propriétaire, sans `auth.uid()`, et `cancel_assignment` y répondrait
  -- `not_admin`. Elle est testée pour elle-même au § 6.
  update assignments
     set status = 'cancelled', decline_reason = 'manœuvre annulée'
   where id = '77777777-0000-4000-8000-000000000543';

  r := reassign_shift('77777777-0000-4000-8000-000000000402',
                      '77777777-0000-4000-8000-000000000103',
                      '77777777-0000-4000-8000-000000000100',
                      '77777777-0000-4000-8000-000000000543');

  perform tests_rea.check((r ->> 'ok')::boolean,
    'une astreinte annulée se repourvoit');
  perform tests_rea.egal(r ->> 'previous_status', 'cancelled',
    'la fonction rend l''état annulé de l''ancienne attribution');
  perform tests_rea.egal((r ->> 'previous_notified')::boolean, false,
    'son titulaire a déjà été prévenu par l''annulation : rien de plus ne part');
  perform tests_rea.egal(
    (select status from assignments
      where id = '77777777-0000-4000-8000-000000000543'),
    'cancelled'::assignment_status,
    'l''annulation reste une annulation : un statut terminal ne se réécrit pas');
  perform tests_rea.egal(
    (select replaced_by::text from assignments
      where id = '77777777-0000-4000-8000-000000000543'),
    r ->> 'assignment_id', 'et elle porte le fil vers ce qui l''a comblée');
end $$;

-- Sur un créneau simplement vide, il n'y a rien à relier.
do $$
declare
  r jsonb;
begin
  r := reassign_shift('77777777-0000-4000-8000-000000000403',
                      '77777777-0000-4000-8000-000000000102',
                      '77777777-0000-4000-8000-000000000100');
  perform tests_rea.check((r ->> 'ok')::boolean, 'pourvoir un créneau vide aboutit');
  perform tests_rea.check(r ->> 'previous_id' is null,
    'un créneau sans refus ne relie rien');
end $$;

rollback to savepoint s5;
release savepoint s5;

-- ===========================================================================
-- 6. cancel_assignment
-- ===========================================================================
\echo ''
\echo '--- 6. Annuler une astreinte, et le dire'
savepoint s6;

update schedules set status = 'published'
 where id = '77777777-0000-4000-8000-000000000302';

insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by) values
  ('77777777-0000-4000-8000-000000000551', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000401', '77777777-0000-4000-8000-000000000101',
   'proposed', now(), '77777777-0000-4000-8000-000000000100'),
  ('77777777-0000-4000-8000-000000000552', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000402', '77777777-0000-4000-8000-000000000102',
   'proposed', now(), '77777777-0000-4000-8000-000000000100'),
  ('77777777-0000-4000-8000-000000000553', '77777777-0000-4000-8000-000000000001',
   '77777777-0000-4000-8000-000000000403', '77777777-0000-4000-8000-000000000103',
   'proposed', now(), '77777777-0000-4000-8000-000000000100');

update assignments set status = 'accepted', responded_at = now()
 where id in ('77777777-0000-4000-8000-000000000551',
              '77777777-0000-4000-8000-000000000552',
              '77777777-0000-4000-8000-000000000553');

delete from notification_outbox;

-- La file se compte sous le rôle propriétaire : `notification_outbox` est hors
-- du `grant` de `select` d'`authenticated` (migration 0014), et c'est très bien
-- ainsi — un administrateur n'a pas à lire la file d'envoi de sa caserne. Le
-- geste se fait donc sous `authenticated`, comme en vrai, et le constat juste
-- après, sous le rôle qui a le droit de regarder.
create table tests_rea.resultat (cle text primary key, valeur jsonb);
grant insert, select on tests_rea.resultat to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub":"77777777-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  r jsonb;
begin
  r := cancel_assignment('77777777-0000-4000-8000-000000000551', 'manœuvre annulée');
  insert into tests_rea.resultat values ('annulation', r);
  perform tests_rea.check((r ->> 'ok')::boolean, 'l''annulation aboutit');
  perform tests_rea.egal((r ->> 'notified')::boolean, true,
    'le titulaire d''une garde acquise est prévenu');

  -- Deux fois la même annulation : la seconde est un refus lisible, pas une
  -- seconde notification.
  perform tests_rea.code(
    cancel_assignment('77777777-0000-4000-8000-000000000551'),
    'assignment_not_active', 'une attribution déjà annulée ne s''annule pas deux fois');
end $$;

reset role;

do $$
declare
  ligne assignments;
begin
  select * into ligne from assignments where id = '77777777-0000-4000-8000-000000000551';
  perform tests_rea.egal(ligne.status, 'cancelled'::assignment_status,
    'l''attribution passe en cancelled');
  perform tests_rea.egal(ligne.decline_reason, 'manœuvre annulée',
    'le motif de l''annulation reste lisible dans le suivi');

  perform tests_rea.egal(
    (select count(*)::integer from notification_outbox), 1,
    'une annulation notifie une personne, une fois — et un second appel n''ajoute rien');
  perform tests_rea.egal(
    (select type from notification_outbox limit 1),
    'assignment_cancelled'::notification_type, 'et c''est une annulation');
  perform tests_rea.egal(
    (select recipients -> 0 ->> 'user_id' from notification_outbox limit 1),
    '77777777-0000-4000-8000-000000000101', 'elle part au titulaire de la garde');
  perform tests_rea.egal(
    (select payload ->> 'reason' from notification_outbox limit 1),
    'manœuvre annulée', 'le motif voyage jusqu''au téléphone');

  perform tests_rea.egal(
    (select status from schedules where id = '77777777-0000-4000-8000-000000000302'),
    'published'::schedule_status,
    'une acceptation annulée ramène le planning validé en publié');
end $$;

-- Une proposition retirée **avant réponse** ne prévient personne : le membre
-- n'avait rien acquis, et son écran « Propositions » sera simplement plus court.
update assignments set status = 'proposed', responded_at = null
 where id = '77777777-0000-4000-8000-000000000552';

set local role authenticated;
set local request.jwt.claims = '{"sub":"77777777-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  r jsonb;
begin
  r := cancel_assignment('77777777-0000-4000-8000-000000000552');
  perform tests_rea.check((r ->> 'ok')::boolean, 'retirer une proposition aboutit');
  perform tests_rea.egal((r ->> 'notified')::boolean, false,
    'une proposition retirée avant réponse ne notifie personne');
end $$;

reset role;

do $$
begin
  perform tests_rea.egal(
    (select count(*)::integer from notification_outbox), 1,
    'la file n''a pas bougé');
end $$;

-- Les refus de droit : la caserne voisine, et le membre simple.
set local role authenticated;

do $$
begin
  set local request.jwt.claims = '{"sub":"88888888-0000-4000-8000-000000000100","role":"authenticated"}';
  perform tests_rea.code(
    cancel_assignment('77777777-0000-4000-8000-000000000553'),
    'not_admin', 'l''admin de la caserne voisine n''annule rien ici');

  set local request.jwt.claims = '{"sub":"77777777-0000-4000-8000-000000000101","role":"authenticated"}';
  perform tests_rea.code(
    cancel_assignment('77777777-0000-4000-8000-000000000553'),
    'not_admin', 'un membre simple n''annule rien');

  set local request.jwt.claims = '{"sub":"77777777-0000-4000-8000-000000000100","role":"authenticated"}';
  perform tests_rea.code(
    cancel_assignment('77777777-0000-4000-8000-0000000005ff'),
    'assignment_not_found', 'une attribution inconnue est refusée');
end $$;

reset role;

rollback to savepoint s6;
release savepoint s6;

-- ===========================================================================
-- 7. Les droits
-- ===========================================================================
\echo ''
\echo '--- 7. Qui peut appeler quoi'
savepoint s7;

do $$
begin
  perform tests_rea.check(
    not has_function_privilege('authenticated',
      'public.reassign_shift(uuid, uuid, uuid, uuid)', 'execute'),
    'reassign_shift est fermée à authenticated : elle passe par l''Edge Function');
  perform tests_rea.check(
    not has_function_privilege('anon',
      'public.reassign_shift(uuid, uuid, uuid, uuid)', 'execute'),
    'reassign_shift est fermée à anon');
  perform tests_rea.check(
    has_function_privilege('authenticated',
      'public.cancel_assignment(uuid, text)', 'execute'),
    'cancel_assignment est ouverte à authenticated, qui la garde par is_admin');
  perform tests_rea.check(
    not has_function_privilege('anon',
      'public.cancel_assignment(uuid, text)', 'execute'),
    'cancel_assignment est fermée à anon');
  perform tests_rea.check(
    not has_function_privilege('authenticated',
      'public.assignments_guard_reattribution()', 'execute'),
    'le déclencheur n''est pas appelable en RPC');

  -- Le déclencheur est bien posé, et **avant** celui de la réponse des membres :
  -- un refus doit se lire sur la règle la plus précise.
  perform tests_rea.check(
    exists (select 1 from pg_trigger
             where tgrelid = 'public.assignments'::regclass
               and tgname = 'assignments_guard_reattribution'),
    'assignments_guard_reattribution est posé sur assignments');
  perform tests_rea.check(
    'assignments_guard_reattribution' < 'assignments_member_transition',
    'il passe avant assignments_member_transition (ordre alphabétique)');
end $$;

release savepoint s7;

\echo ''
\echo '=== Réattribution et annulation : tous les tests passent ==='

rollback;
