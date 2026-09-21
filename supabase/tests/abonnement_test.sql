-- Tests de l'abonnement par caserne (migration 0023, ticket 029).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
-- 1. Toute caserne naît en essai de **60 jours**, sans carte bancaire, par le
--    déclencheur `stations_subscription_bootstrap`. Le seed aussi.
-- 2. Les **quatre événements** du prestataire de paiement, appliqués par
--    `subscription_sync` : `checkout.session.completed`, `invoice.paid`,
--    `invoice.payment_failed`, `customer.subscription.updated/deleted`.
-- 3. Ce que `subscription_sync` refuse ou ignore : caserne introuvable, formule
--    inconnue, paramètres nuls qui n'effacent rien, désignation par le seul
--    identifiant client, ordre d'arrivée quelconque.
-- 4. `cron_suspend_subscriptions` dans ses **deux cas** — essai expiré sans
--    abonnement, impayé de plus de quatorze jours — et tout ce qu'elle ne doit
--    pas toucher. Idempotence comprise.
-- 5. La conséquence réelle : `station_writable()` bascule, donc la caserne passe
--    en lecture seule, et **rien n'est supprimé**.
-- 6. Les droits : un admin lit son abonnement, un membre ordinaire non, et
--    aucune des trois fonctions n'est appelable par un client.
-- 7. La tâche est planifiée, qualifiée, sans argument.
--
-- Rien ici n'appelle le prestataire : `subscription_sync` reçoit les valeurs
-- qu'une Edge Function en aurait extraites, une fois la signature vérifiée.
-- La vérification de signature, elle, est testée en Deno
-- (supabase/functions/tests/stripe_signature_test.ts).
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : le seed (caserne A = aaaaaaaa-…-001 « CIS Saint-Martin », admin
-- …100, membres …101 à …108 ; caserne B = bbbbbbbb-…-001), plus une caserne
-- créée ici pour observer le déclencheur.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_abo;

create function tests_abo.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

create function tests_abo.denied(p_sql text, p_label text) returns void
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

-- Un appel qui doit échouer sur un manque de droits, quel que soit son résultat.
create function tests_abo.refuse(p_sql text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — l''appel a réussi alors qu''il devait être refusé', p_label;
exception
  when insufficient_privilege then
    raise notice '  ok   % (refusé : %)', p_label, sqlerrm;
end $$;

-- Les assertions tournent aussi sous les rôles « authenticated » et « anon »
-- (section 6) : sans ces deux droits, elles échoueraient sur le schéma, pas sur
-- ce qu'elles vérifient.
grant usage on schema tests_abo to authenticated, anon;
grant execute on all functions in schema tests_abo to authenticated, anon;

\set caserne_a '''aaaaaaaa-0000-4000-8000-000000000001'''
\set caserne_b '''bbbbbbbb-0000-4000-8000-000000000001'''
\set admin_a   '''aaaaaaaa-0000-4000-8000-000000000100'''
\set membre_a  '''aaaaaaaa-0000-4000-8000-000000000101'''
\set caserne_c '''cccccccc-0000-4000-8000-0000000000c1'''

\echo ''
\echo '== 1. Toute caserne naît en essai de 60 jours, sans carte'

insert into stations (id, name, slug, timezone)
values (:caserne_c, 'CIS Bois-Joli', 'bois-joli', 'Europe/Paris');

select tests_abo.check(
  (select status = 'trialing'
      and stripe_customer_id is null
      and stripe_subscription_id is null
      and plan is null
      and trial_ends_at between now() + interval '59 days' and now() + interval '61 days'
     from subscriptions where station_id = :caserne_c::uuid),
  'une caserne créée a un essai de 60 jours, sans client ni formule');

select tests_abo.check(
  (select count(*) = 3 from subscriptions),
  'les deux casernes du seed et la nouvelle ont chacune leur ligne');

select tests_abo.check(
  (select status = 'trialing' and trial_ends_at > now()
     from subscriptions where station_id = :caserne_a::uuid),
  'la caserne du seed est en essai en cours');

-- Le déclencheur ne piétine pas une ligne posée à la main (`do nothing`).
select tests_abo.check(
  (select trial_ends_at > now() + interval '30 days'
     from subscriptions where station_id = :caserne_b::uuid),
  'le seed a confirmé la date de fin d''essai sans que le déclencheur la double');

\echo ''
\echo '== 2. Les quatre événements du prestataire'

\echo '-- 2.a checkout.session.completed : la caserne devient abonnée'

select tests_abo.check(
  (subscription_sync(
     p_station     => :caserne_a::uuid,
     p_customer    => 'cus_A',
     p_subscription=> 'sub_A',
     p_status      => 'active',
     p_plan        => 'monthly',
     p_period_end  => '2027-01-15T00:00:00Z',
     p_event       => 'checkout.session.completed') ->> 'ok')::boolean,
  'checkout.session.completed est appliqué');

select tests_abo.check(
  (select status = 'active'
      and stripe_customer_id = 'cus_A'
      and stripe_subscription_id = 'sub_A'
      and plan = 'monthly'
      and current_period_end = '2027-01-15T00:00:00Z'
      and suspended_at is null
     from subscriptions where station_id = :caserne_a::uuid),
  'la caserne A est active, mensuelle, avec son client et son abonnement');

select tests_abo.check(
  (select count(*) = 1 from audit_log
    where station_id = :caserne_a::uuid
      and action = 'subscription.checkout.session.completed'
      and data ->> 'from' = 'trialing' and data ->> 'to' = 'active'),
  'le passage trialing → active est journalisé');

-- **L'essai n'est pas effacé.** `trial_ends_at` reste : c'est l'histoire de la
-- caserne, et l'écran peut encore dire « essai commencé le … ».
select tests_abo.check(
  (select trial_ends_at is not null from subscriptions where station_id = :caserne_a::uuid),
  'souscrire n''efface pas la date de fin d''essai');

\echo '-- 2.b invoice.paid : la période est repoussée, le client seul suffit à désigner la caserne'

select tests_abo.check(
  (subscription_sync(
     p_customer   => 'cus_A',            -- pas de p_station : c'est le cas réel
     p_status     => 'active',
     p_period_end => '2027-02-15T00:00:00Z',
     p_event      => 'invoice.paid') ->> 'ok')::boolean,
  'invoice.paid est appliqué sans identifiant de caserne');

select tests_abo.check(
  (select status = 'active'
      and current_period_end = '2027-02-15T00:00:00Z'
      -- Les paramètres nuls n'effacent rien : la formule et l'abonnement tiennent.
      and plan = 'monthly'
      and stripe_subscription_id = 'sub_A'
     from subscriptions where station_id = :caserne_a::uuid),
  'invoice.paid repousse la période sans effacer la formule ni l''abonnement');

\echo '-- 2.c invoice.payment_failed : past_due, et la caserne écrit encore'

select tests_abo.check(
  (subscription_sync(
     p_customer => 'cus_A',
     p_status   => 'past_due',
     p_event    => 'invoice.payment_failed') ->> 'ok')::boolean,
  'invoice.payment_failed est appliqué');

select tests_abo.check(
  (select status = 'past_due' and suspended_at is null
     from subscriptions where station_id = :caserne_a::uuid),
  'la caserne est en retard de paiement, pas encore suspendue');

select tests_abo.check(
  station_writable(:caserne_a::uuid),
  'un retard de paiement ne coupe pas l''écriture : on laisse quatorze jours');

\echo '-- 2.d customer.subscription.updated : changement de formule'

select tests_abo.check(
  (subscription_sync(
     p_customer   => 'cus_A',
     p_status     => 'active',
     p_plan       => 'yearly',
     p_period_end => '2028-02-15T00:00:00Z',
     p_event      => 'customer.subscription.updated') ->> 'ok')::boolean,
  'customer.subscription.updated est appliqué');

select tests_abo.check(
  (select status = 'active' and plan = 'yearly'
     from subscriptions where station_id = :caserne_a::uuid),
  'la caserne est passée à la formule annuelle');

\echo '-- 2.e customer.subscription.deleted : résilié, lecture seule, rien de supprimé'

-- De quoi vérifier que la résiliation ne supprime aucune donnée métier.

create temporary table tests_abo_compte as
  select (select count(*) from availabilities where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') as dispos,
         (select count(*) from memberships   where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') as membres;

select tests_abo.check(
  (subscription_sync(
     p_customer  => 'cus_A',
     p_status    => 'cancelled',
     p_event     => 'customer.subscription.deleted',
     p_reference => '2027-03-01T10:00:00Z') ->> 'ok')::boolean,
  'customer.subscription.deleted est appliqué');

select tests_abo.check(
  (select status = 'cancelled' and suspended_at = '2027-03-01T10:00:00Z'
     from subscriptions where station_id = :caserne_a::uuid),
  'la caserne est résiliée et la date de bascule est posée');

select tests_abo.check(
  not station_writable(:caserne_a::uuid),
  'une caserne résiliée passe en lecture seule');

select tests_abo.check(
  (select dispos = (select count(*) from availabilities where station_id = 'aaaaaaaa-0000-4000-8000-000000000001')
      and membres = (select count(*) from memberships where station_id = 'aaaaaaaa-0000-4000-8000-000000000001')
     from tests_abo_compte),
  'rien n''est supprimé : ni disponibilités, ni membres (docs/PRD.md § 6.6)');

\echo '-- 2.f le retour d''un paiement efface la date de bascule'

select tests_abo.check(
  (subscription_sync(
     p_customer   => 'cus_A',
     p_status     => 'active',
     p_period_end => '2027-04-15T00:00:00Z',
     p_event      => 'invoice.paid') ->> 'ok')::boolean,
  'un paiement qui revient est appliqué');

select tests_abo.check(
  (select status = 'active' and suspended_at is null
     from subscriptions where station_id = :caserne_a::uuid),
  'suspended_at est effacée : la caserne n''est plus suspendue');

select tests_abo.check(
  station_writable(:caserne_a::uuid),
  'l''écriture est rouverte');

\echo ''
\echo '== 3. Ce que subscription_sync refuse ou ignore'

select tests_abo.check(
  subscription_sync(
    p_customer => 'cus_inconnu',
    p_status   => 'active',
    p_event    => 'invoice.paid') ->> 'code' = 'station_not_found',
  'un client inconnu ne concerne pas ce projet : station_not_found, pas d''erreur');

select tests_abo.check(
  subscription_sync(
    p_station => 'dddddddd-0000-4000-8000-0000000000ff'::uuid,
    p_status  => 'active',
    p_event   => 'checkout.session.completed') ->> 'code' = 'station_not_found',
  'une caserne inexistante est refusée');

select tests_abo.check(
  subscription_sync(
    p_customer => 'cus_A',
    p_plan     => 'weekly',
    p_event    => 'customer.subscription.updated') ->> 'code' = 'invalid_plan',
  'une formule inconnue est refusée avant toute écriture');

select tests_abo.check(
  (select plan = 'yearly' from subscriptions where station_id = :caserne_a::uuid),
  'et la formule en base n''a pas bougé');

-- `subscription_set_customer` : le client est retenu, le statut ne bouge pas.
select tests_abo.check(
  (subscription_set_customer(:caserne_b::uuid, 'cus_B') ->> 'ok')::boolean,
  'subscription_set_customer retient le client');

select tests_abo.check(
  (select stripe_customer_id = 'cus_B' and status = 'trialing'
      and stripe_subscription_id is null
     from subscriptions where station_id = :caserne_b::uuid),
  'poser le client ne fait pas croire que c''est payé');

\echo ''
\echo '== 4. cron_suspend_subscriptions, dans ses deux cas'

-- Les instants de référence ci-dessous sont en 2027, alors que les essais du
-- seed expirent dans soixante jours. On repousse leur échéance hors de portée
-- pour que chaque assertion ne porte que sur le cas qu'elle nomme.
update subscriptions set trial_ends_at = '2030-01-01T00:00:00Z' where status = 'trialing';

-- Décor : quatre casernes de plus, une par situation. Elles sont créées ici, et
-- leur essai est posé par le déclencheur puis réécrit à la main.
insert into stations (id, name, slug) values
  ('cccccccc-0000-4000-8000-0000000000c2', 'Essai expiré',        'essai-expire'),
  ('cccccccc-0000-4000-8000-0000000000c3', 'Essai expiré payé',   'essai-expire-paye'),
  ('cccccccc-0000-4000-8000-0000000000c4', 'Impayé récent',       'impaye-recent'),
  ('cccccccc-0000-4000-8000-0000000000c5', 'Impayé ancien',       'impaye-ancien');

update subscriptions set status = 'trialing', trial_ends_at = '2027-05-01T00:00:00Z'
 where station_id = 'cccccccc-0000-4000-8000-0000000000c2';

-- Elle a payé pendant son essai : le webhook a posé l'abonnement, le statut
-- n'est pas encore passé à `active`. La suspendre serait suspendre un client.
update subscriptions set status = 'trialing', trial_ends_at = '2027-05-01T00:00:00Z',
       stripe_subscription_id = 'sub_C3', stripe_customer_id = 'cus_C3'
 where station_id = 'cccccccc-0000-4000-8000-0000000000c3';

update subscriptions set status = 'past_due', current_period_end = '2027-05-20T00:00:00Z',
       stripe_subscription_id = 'sub_C4', stripe_customer_id = 'cus_C4'
 where station_id = 'cccccccc-0000-4000-8000-0000000000c4';

update subscriptions set status = 'past_due', current_period_end = '2027-05-01T00:00:00Z',
       stripe_subscription_id = 'sub_C5', stripe_customer_id = 'cus_C5'
 where station_id = 'cccccccc-0000-4000-8000-0000000000c5';

-- La veille de l'expiration : personne n'est suspendu.
select tests_abo.check(
  cron_suspend_subscriptions('2027-04-30T03:30:00Z') = 0,
  'la veille de l''expiration, aucune caserne n''est suspendue');

-- Le 21 mai : l'essai du c2 a expiré (1er mai), et l'impayé du c5 remonte au
-- 1er mai, soit vingt jours. Celui du c4 remonte au 20 mai : un jour.
select tests_abo.check(
  cron_suspend_subscriptions('2027-05-21T03:30:00Z') = 2,
  'deux casernes suspendues : l''essai expiré et l''impayé de plus de 14 jours');

select tests_abo.check(
  (select status = 'suspended' and suspended_at = '2027-05-21T03:30:00Z'
     from subscriptions where station_id = 'cccccccc-0000-4000-8000-0000000000c2'),
  'cas a : essai expiré sans abonnement → suspendue');

select tests_abo.check(
  (select status = 'trialing'
     from subscriptions where station_id = 'cccccccc-0000-4000-8000-0000000000c3'),
  'un essai expiré mais **déjà payé** n''est pas suspendu');

select tests_abo.check(
  (select status = 'past_due'
     from subscriptions where station_id = 'cccccccc-0000-4000-8000-0000000000c4'),
  'un impayé d''un jour n''est pas suspendu');

select tests_abo.check(
  (select status = 'suspended' and suspended_at = '2027-05-21T03:30:00Z'
     from subscriptions where station_id = 'cccccccc-0000-4000-8000-0000000000c5'),
  'cas b : impayé depuis vingt jours → suspendue');

select tests_abo.check(
  (select count(*) = 2 from audit_log
    where action = 'subscription.suspended'
      and data ->> 'reason' in ('trial_expired', 'past_due_14_days')),
  'les deux suspensions sont journalisées avec leur motif');

-- Bornes exactes : quatorze jours pile ne suspend pas, quatorze jours et une
-- seconde suspendent. La limite du ticket est « **plus de** quatorze jours ».
select tests_abo.check(
  cron_suspend_subscriptions('2027-06-03T00:00:00Z') = 0,
  'quatorze jours pile après le 20 mai : l''impayé récent tient encore');

select tests_abo.check(
  cron_suspend_subscriptions('2027-06-03T00:00:01Z') = 1,
  'une seconde plus tard, il est suspendu');

-- Idempotence : l'ordonnanceur rejoue après un redémarrage.
select tests_abo.check(
  cron_suspend_subscriptions('2027-06-03T00:00:02Z') = 0,
  'rejouée, la tâche ne suspend rien de plus (idempotente)');

select tests_abo.check(
  (select suspended_at = '2027-06-03T00:00:01Z'
     from subscriptions where station_id = 'cccccccc-0000-4000-8000-0000000000c4'),
  'et la date de bascule n''est pas repoussée par le rejeu');

-- Un `past_due` sans période payée connue retombe sur `updated_at`.
update subscriptions set status = 'past_due', current_period_end = null
 where station_id = :caserne_b::uuid;

select tests_abo.check(
  cron_suspend_subscriptions(now() + interval '13 days') = 0,
  'sans période payée connue, le repli sur updated_at tient treize jours');

select tests_abo.check(
  cron_suspend_subscriptions(now() + interval '15 days') = 1,
  'et suspend au quinzième');

\echo ''
\echo '== 5. La conséquence : lecture seule, et rien de plus'

select tests_abo.check(
  not station_writable('cccccccc-0000-4000-8000-0000000000c2'::uuid),
  'une caserne suspendue ne peut plus écrire');

select tests_abo.check(
  station_writable('cccccccc-0000-4000-8000-0000000000c3'::uuid),
  'celle qui a payé pendant son essai écrit toujours');

-- Une caserne sans **aucune** ligne d'abonnement écrit : c'est le repli de
-- `station_writable` (0007), et c'est ce qui garantit qu'un projet sans
-- prestataire de paiement configuré reste utilisable.
delete from subscriptions where station_id = 'cccccccc-0000-4000-8000-0000000000c2';

select tests_abo.check(
  station_writable('cccccccc-0000-4000-8000-0000000000c2'::uuid),
  'sans ligne d''abonnement du tout, la caserne reste pleinement utilisable');

\echo ''
\echo '== 6. Les droits'

set local role authenticated;
set local request.jwt.claims to '{"sub": "aaaaaaaa-0000-4000-8000-000000000100", "role": "authenticated"}';

select tests_abo.check(
  (select count(*) = 1 from subscriptions where station_id = :caserne_a::uuid),
  'un admin lit l''abonnement de sa caserne');

select tests_abo.check(
  (select count(*) = 0 from subscriptions where station_id = :caserne_b::uuid),
  'et pas celui d''une autre caserne');

select tests_abo.refuse(
  $$select subscription_sync(p_customer => 'cus_A', p_status => 'active', p_event => 'forge')$$,
  'un admin ne peut pas appliquer un événement de paiement');

select tests_abo.refuse(
  $$select subscription_set_customer('aaaaaaaa-0000-4000-8000-000000000001'::uuid, 'cus_pirate')$$,
  'un admin ne peut pas poser un identifiant client');

select tests_abo.refuse(
  $$select cron_suspend_subscriptions()$$,
  'un admin ne peut pas déclencher la tâche de suspension');

select tests_abo.denied(
  $$update subscriptions set status = 'active' where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'un admin n''écrit pas directement dans subscriptions');

set local request.jwt.claims to '{"sub": "aaaaaaaa-0000-4000-8000-000000000101", "role": "authenticated"}';

select tests_abo.check(
  (select count(*) = 0 from subscriptions),
  'un membre ordinaire ne lit aucun abonnement');

set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select tests_abo.check(
  (select count(*) = 0 from subscriptions),
  'anon ne lit rien');

reset role;

\echo ''
\echo '== 7. La tâche planifiée'

select tests_abo.check(
  (select count(*) = 1 from cron.job
    where jobname = 'suspend_subscriptions'
      and command = 'select public.cron_suspend_subscriptions();'
      and schedule = '30 3 * * *'),
  'la tâche suspend_subscriptions est planifiée, qualifiée et sans argument');

\echo ''
\echo 'abonnement_test : OK'

rollback;
