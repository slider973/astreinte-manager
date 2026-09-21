-- Tests du mode suspendu (migration 0024, ticket 030).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
-- 1. `station_access` rend les quatre faits à **tout membre actif** — c'est
--    le mystère que le ticket lève : sans elle, un simple pompier ne peut pas
--    savoir pourquoi sa grille refuse ses cases.
-- 2. Ce qu'elle **ne** rend **pas** : rien du prestataire de paiement. La
--    table reste réservée aux administrateurs, et un non-membre n'obtient rien.
-- 3. `writable` suit `station_writable()` et ne s'en écarte jamais.
-- 4. `cron_subscription_reminders` : la fenêtre J-7, la mise en file du
--    courriel aux **administrateurs seuls**, et son idempotence.
-- 5. `cron_suspend_subscriptions` prévient les administrateurs dans la
--    transaction qui suspend, et **rien n'est supprimé**.
-- 6. **La lecture reste entière** pour un membre d'une caserne suspendue :
--    disponibilités, créneaux, attributions, notifications. C'est le critère
--    d'acceptation du ticket, et il se vérifie ici, pas seulement à l'écran.
-- 7. Les tâches sont planifiées, qualifiées, sans argument, et dans le bon
--    ordre — le rappel avant la suspension.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : le seed (caserne A = aaaaaaaa-…-001, admin …100, membres …101 à
-- …108 ; caserne B = bbbbbbbb-…-001).

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_gate;

create function tests_gate.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

create function tests_gate.refuse(p_sql text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — l''appel a réussi alors qu''il devait être refusé', p_label;
exception
  when insufficient_privilege then
    raise notice '  ok   % (refusé : %)', p_label, sqlerrm;
end $$;

grant usage on schema tests_gate to authenticated, anon;
grant execute on all functions in schema tests_gate to authenticated, anon;

\set caserne_a '''aaaaaaaa-0000-4000-8000-000000000001'''
\set caserne_b '''bbbbbbbb-0000-4000-8000-000000000001'''
\set admin_a   '''aaaaaaaa-0000-4000-8000-000000000100'''
\set membre_a  '''aaaaaaaa-0000-4000-8000-000000000101'''

\echo ''
\echo '== 1. station_access : un membre ordinaire sait enfin où il en est'

set local role authenticated;
set local request.jwt.claims to '{"sub": "aaaaaaaa-0000-4000-8000-000000000101", "role": "authenticated"}';

select tests_gate.check(
  (select (station_access(:caserne_a::uuid) ->> 'writable')::boolean is true
      and station_access(:caserne_a::uuid) ->> 'status' = 'trialing'
      and station_access(:caserne_a::uuid) ->> 'trial_ends_at' is not null),
  'un membre lit writable, status et trial_ends_at de sa caserne');

-- Ce qui ne sort pas, et ne doit jamais sortir : les affaires du prestataire
-- de paiement sont celles de l'administrateur (`subscriptions_select_admin`).
select tests_gate.check(
  (select not (station_access(:caserne_a::uuid) ?| array[
                 'stripe_customer_id', 'stripe_subscription_id',
                 'plan', 'current_period_end'])),
  'aucune donnée du prestataire de paiement ne sort de station_access');

select tests_gate.check(
  (select station_access(:caserne_b::uuid) is null),
  'un non-membre n''obtient rien');

-- Et la table, elle, reste fermée : la fonction n'ouvre pas une porte dérobée.
select tests_gate.check(
  (select count(*) = 0 from subscriptions),
  'un membre ordinaire ne lit toujours aucune ligne de subscriptions');

reset role;

\echo ''
\echo '== 2. writable suit station_writable(), et ne s''en écarte jamais'

update subscriptions set status = 'suspended', suspended_at = now()
 where station_id = :caserne_a::uuid;

set local role authenticated;
set local request.jwt.claims to '{"sub": "aaaaaaaa-0000-4000-8000-000000000101", "role": "authenticated"}';

select tests_gate.check(
  (select (station_access(:caserne_a::uuid) ->> 'writable')::boolean is false
      and station_access(:caserne_a::uuid) ->> 'status' = 'suspended'
      and station_access(:caserne_a::uuid) ->> 'suspended_at' is not null),
  'suspendue : writable faux, statut et date rendus');

reset role;

select tests_gate.check(
  (select station_writable(:caserne_a::uuid) is false),
  'station_writable dit la même chose, et c''est elle qui calcule');

\echo ''
\echo '== 3. La lecture reste entière — la suspension n''est jamais une coupure'

set local role authenticated;
set local request.jwt.claims to '{"sub": "aaaaaaaa-0000-4000-8000-000000000101", "role": "authenticated"}';

-- `docs/PRD.md § 6.6` : « Suspendu : lecture seule pour tous. » Quatre lectures
-- que la PWA fait sur ses écrans de consultation ; aucune ne doit se fermer.
select tests_gate.check(
  (select count(*) >= 0 from availabilities where user_id = :membre_a::uuid),
  'un membre suspendu lit ses disponibilités');

select tests_gate.check(
  (select count(*) >= 0 from shifts where station_id = :caserne_a::uuid),
  'un membre suspendu lit les créneaux de la caserne');

select tests_gate.check(
  (select count(*) >= 0 from assignments where user_id = :membre_a::uuid),
  'un membre suspendu lit ses attributions');

select tests_gate.check(
  (select count(*) >= 0 from notifications where user_id = :membre_a::uuid),
  'un membre suspendu ouvre son centre de notifications');

select tests_gate.check(
  (select count(*) >= 0 from periods where station_id = :caserne_a::uuid),
  'un membre suspendu lit les périodes de saisie');

-- Et l'écriture, elle, reste refusée : c'est bien une lecture seule.
select tests_gate.refuse(
  format('insert into availabilities (station_id, user_id, date, slot, status)
          values (%L, %L, current_date + 400, ''day'', ''available'')',
         :caserne_a, :membre_a),
  'une écriture de disponibilité reste refusée');

reset role;

-- Rien n'a été supprimé : la promesse du produit, vérifiée sur la seule
-- transition qui aurait pu la trahir.
-- Le seed pose 648 disponibilités pour la caserne A ; aucune ne bouge.
select tests_gate.check(
  (select count(*) = 648 from availabilities where station_id = :caserne_a::uuid),
  'rien n''a été supprimé par la suspension');

-- On remet la caserne en essai pour les sections suivantes.
update subscriptions set status = 'trialing', suspended_at = null
 where station_id = :caserne_a::uuid;

\echo ''
\echo '== 4. cron_subscription_reminders : la fenêtre J-7'

-- Hors fenêtre : à huit jours, rien ne part.
update subscriptions set trial_ends_at = now() + interval '8 days'
 where station_id = :caserne_a::uuid;
update subscriptions set trial_ends_at = now() + interval '30 days'
 where station_id = :caserne_b::uuid;

select tests_gate.check(
  cron_subscription_reminders() = 0,
  'à huit jours de la fin d''essai, aucun rappel');

-- Dans la fenêtre.
update subscriptions set trial_ends_at = now() + interval '6 days 12 hours'
 where station_id = :caserne_a::uuid;

select tests_gate.check(
  cron_subscription_reminders() = 1,
  'à J-7, un rappel part pour la caserne A et pour elle seule');

select tests_gate.check(
  (select type = 'subscription_trial_ending'
      and station_id = :caserne_a::uuid
      and channels @> array['email', 'inapp']
      and dedupe_key like 'subscription_trial_ending:%'
     from notification_outbox
    where type = 'subscription_trial_ending'),
  'la demande part par courriel et alimente le centre de notifications');

-- Les administrateurs, et personne d'autre.
select tests_gate.check(
  (select (select count(*) from jsonb_array_elements(recipients)) =
          (select count(*) from memberships
            where station_id = :caserne_a::uuid and role = 'admin' and status = 'active')
     from notification_outbox where type = 'subscription_trial_ending'),
  'les destinataires sont exactement les administrateurs actifs');

select tests_gate.check(
  (select bool_and(d ->> 'user_id' in (
            select user_id::text from memberships
             where station_id = :caserne_a::uuid and role = 'admin' and status = 'active'))
     from notification_outbox o,
          lateral jsonb_array_elements(o.recipients) d
    where o.type = 'subscription_trial_ending'),
  'aucun simple pompier ne reçoit un message d''abonnement');

select tests_gate.check(
  cron_subscription_reminders() = 0,
  'rejouée, la tâche n''envoie rien de plus');

-- Une caserne qui a déjà souscrit pendant son essai n'est pas relancée.
update subscriptions
   set stripe_subscription_id = 'sub_test', trial_ends_at = now() + interval '6 days 12 hours'
 where station_id = :caserne_b::uuid;

select tests_gate.check(
  cron_subscription_reminders() = 0,
  'une caserne déjà abonnée pendant son essai n''est pas relancée');

\echo ''
\echo '== 5. La suspension prévient les administrateurs'

update subscriptions set trial_ends_at = now() - interval '1 day'
 where station_id = :caserne_a::uuid;

select tests_gate.check(
  cron_suspend_subscriptions() = 1,
  'l''essai expiré suspend la caserne A');

select tests_gate.check(
  (select type = 'subscription_suspended'
      and station_id = :caserne_a::uuid
      and channels @> array['email', 'inapp']
      and payload ->> 'reason' = 'trial_expired'
     from notification_outbox
    where type = 'subscription_suspended'),
  'le courriel de suspension est mis en file, avec son motif');

select tests_gate.check(
  (select status = 'suspended' and suspended_at is not null
     from subscriptions where station_id = :caserne_a::uuid),
  'et la caserne est bien suspendue — la notification n''a rien remplacé');

select tests_gate.check(
  cron_suspend_subscriptions() = 0
  and (select count(*) = 1 from notification_outbox where type = 'subscription_suspended'),
  'rejouée, la tâche ne suspend ni ne renotifie');

\echo ''
\echo '== 6. Les droits des deux tâches'

set local role authenticated;
set local request.jwt.claims to '{"sub": "aaaaaaaa-0000-4000-8000-000000000100", "role": "authenticated"}';

select tests_gate.refuse(
  'select cron_subscription_reminders()',
  'un administrateur n''appelle pas la tâche de rappel');

select tests_gate.refuse(
  'select cron_suspend_subscriptions()',
  'un administrateur ne suspend pas une caserne à la main');

set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select tests_gate.refuse(
  'select station_access(''aaaaaaaa-0000-4000-8000-000000000001''::uuid)',
  'anon n''appelle pas station_access');

reset role;

\echo ''
\echo '== 7. Les tâches planifiées'

select tests_gate.check(
  (select count(*) = 1 from cron.job
    where jobname = 'subscription_reminders'
      and command = 'select public.cron_subscription_reminders();'
      and schedule = '20 3 * * *'),
  'subscription_reminders est planifiée, qualifiée et sans argument');

-- L'ordre compte : à l'envers, une caserne dont l'essai expire aujourd'hui
-- pourrait recevoir « il te reste sept jours » juste après avoir été suspendue.
select tests_gate.check(
  (select count(*) = 1 from cron.job a, cron.job b
    where a.jobname = 'subscription_reminders'
      and b.jobname = 'suspend_subscriptions'
      and split_part(a.schedule, ' ', 1)::int < split_part(b.schedule, ' ', 1)::int
      and split_part(a.schedule, ' ', 2) = split_part(b.schedule, ' ', 2)),
  'le rappel tourne avant la suspension, le même jour');

\echo ''
\echo 'gating_suspension_test : OK'

rollback;
