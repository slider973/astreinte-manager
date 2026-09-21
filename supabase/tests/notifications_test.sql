-- Tests du chemin d'appel des notifications depuis la base (migration 0014, ticket 025).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
-- 1. `notify` écrit la demande dans `notification_outbox` : forme des
--    destinataires, charge utile, canaux, caserne.
-- 2. La forme de `recipients` est une contrainte, pas une convention : une
--    insertion directe mal formée est refusée comme un appel mal formé.
-- 3. `p_dedupe_key` rend l'appel idempotent : « un rappel par membre et par
--    échéance » (ticket 015), « un rapport par jour et par planning » (ticket 022).
-- 4. `notify_claim` ne rend une demande qu'une fois : deux prises en charge
--    concurrentes ne produisent pas deux notifications, et un rejeu de la tâche
--    de reprise sur une demande déjà close n'envoie rien.
-- 5. `notify_complete` clôt la demande, en réussite comme en échec.
-- 6. `cron_dispatch_notifications` : elle laisse les demandes fraîches à la
--    tentative immédiate, reprend les autres, respecte le verrou et abandonne au
--    bout de cinq tentatives — avec une erreur lisible, pas un silence.
-- 6 bis. Une demande abandonnée ne reste pas un silence pour son destinataire
--    (ticket 040) : elle met en file sa propre ligne interne, canal `inapp` seul,
--    fidèle à l'original, unique, et qui ne se trace pas elle-même.
-- 7. La file n'est lisible par personne côté application : ni `anon`, ni
--    `authenticated`, ni un admin de caserne. Elle porte les charges utiles de
--    toutes les casernes à la fois.
-- 8. Aucune des fonctions de la migration n'est appelable par un client, et la
--    tâche `dispatch_notifications` est planifiée.
--
-- Rien ici n'appelle l'Edge Function : `notify_post` est remplacée, le temps du
-- test, par une version qui ne fait pas d'appel HTTP. La CI n'a ni edge-runtime
-- ni Kong (.github/workflows/ci.yml), et la logique testée est celle de la file,
-- pas celle du réseau.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : le seed (caserne A = aaaaaaaa-…-001, admin …100, membres …101+ ;
-- caserne B = bbbbbbbb-…-001, admin …100).

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

create function tests.echoue_avec(p_sql text, p_motif text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — accepté alors que ça devait être refusé', p_label;
exception
  when others then
    if sqlerrm like 'ECHEC%' then raise; end if;
    if position(p_motif in sqlerrm) = 0 then
      raise exception 'ECHEC : % — refusé, mais pour « % » au lieu de « % »',
        p_label, left(sqlerrm, 80), p_motif;
    end if;
    raise notice '  ok   % (refusé : %)', p_label, p_motif;
end $$;

-- L'écriture doit être refusée par la RLS ou par les privilèges.
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
  when raise_exception then
    if sqlerrm like 'ECHEC%' then raise; end if;
    raise notice '  ok   % (refusé : %)', p_label, sqlerrm;
end $$;

grant usage on schema tests to authenticated, anon;
grant execute on all functions in schema tests to authenticated, anon;

-- ---------------------------------------------------------------------------
-- `notify_post` sans réseau.
--
-- La vraie fonction lit Vault et appelle `net.http_post`. On garde exactement son
-- effet de bord sur la file — compteur de tentatives et verrou — et on coupe
-- l'appel HTTP : c'est lui qui n'a rien à faire dans une CI sans Edge Functions.
-- Le remplacement est annulé avec la transaction.
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
     set attempts     = attempts + 1,
         locked_until = now() + interval '2 minutes'
   where id = p_outbox;

  return true;
end $$;

\echo ''
\echo '-- 1. notify écrit la demande dans la file'

select notify(
  'assignment_proposed',
  p_recipients => jsonb_build_array(
    jsonb_build_object(
      'user_id', 'aaaaaaaa-0000-4000-8000-000000000101',
      'payload', jsonb_build_object(
        'shifts', jsonb_build_array(jsonb_build_object('date', '2026-10-12', 'slot', 'night')))),
    jsonb_build_object(
      'user_id', 'aaaaaaaa-0000-4000-8000-000000000102',
      'payload', jsonb_build_object(
        'shifts', jsonb_build_array(jsonb_build_object('date', '2026-10-13', 'slot', 'day'))))),
  p_station    => 'aaaaaaaa-0000-4000-8000-000000000001',
  p_payload    => jsonb_build_object('period', '2026-10'),
  p_channels   => array['push', 'inapp']
) as id_publication \gset

select tests.check(
  (select count(*) from notification_outbox where id = :'id_publication') = 1,
  'notify rend l''identifiant d''une ligne réellement écrite');

select tests.check(
  (select type = 'assignment_proposed'
      and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
      and jsonb_array_length(recipients) = 2
      and payload ->> 'period' = '2026-10'
      and channels = array['push', 'inapp']
      and status = 'pending'
     from notification_outbox where id = :'id_publication'),
  'la demande porte son type, sa caserne, ses deux destinataires et ses canaux');

-- La tentative immédiate a eu lieu : compteur à 1 et verrou posé. Sans cela, la
-- tâche de reprise doublerait l'envoi à la minute suivante.
select tests.check(
  (select attempts = 1 and locked_until > now()
     from notification_outbox where id = :'id_publication'),
  'notify a tenté l''appel immédiat et posé le verrou de deux minutes');

-- La forme courte, celle du ticket : une liste d'identifiants et une charge utile
-- commune.
select notify(
  'schedule_validated',
  p_user_ids => array['aaaaaaaa-0000-4000-8000-000000000101',
                      'aaaaaaaa-0000-4000-8000-000000000102']::uuid[],
  p_station  => 'aaaaaaaa-0000-4000-8000-000000000001',
  p_payload  => jsonb_build_object('period', '2026-10')
) as id_validation \gset

select tests.check(
  (select jsonb_array_length(recipients) = 2 and channels is null
     from notification_outbox where id = :'id_validation'),
  'la forme courte (user_ids) donne un destinataire par identifiant, canaux par défaut');

\echo ''
\echo '-- 2. La forme des destinataires est une contrainte, pas une convention'

select tests.echoue_avec(
  $$select notify('schedule_validated', p_user_ids => array[]::uuid[])$$,
  'notify_recipients_invalid',
  'notify sans destinataire est refusée');

select tests.echoue_avec(
  $$select notify('schedule_validated', p_recipients => '[{"payload":{}}]'::jsonb)$$,
  'notify_recipients_invalid',
  'un destinataire sans user_id est refusé');

select tests.echoue_avec(
  $$select notify('schedule_validated', p_recipients => '[{"user_id":"pas-un-uuid"}]'::jsonb)$$,
  'notify_recipients_invalid',
  'un user_id qui n''est pas un uuid est refusé');

-- Et la même règle vaut pour une insertion directe : une Edge Function ou un
-- test qui contournerait `notify` se heurte à la contrainte de la table.
select tests.echoue_avec(
  $$insert into notification_outbox (type, recipients)
    values ('schedule_validated', '{"user_id":"aaaaaaaa-0000-4000-8000-000000000101"}'::jsonb)$$,
  'notification_outbox_recipients_valide',
  'une insertion directe avec un objet au lieu d''un tableau est refusée');

\echo ''
\echo '-- 3. La clé de dédoublonnage rend l''appel idempotent'

select notify(
  'availability_reminder',
  p_user_ids   => array['aaaaaaaa-0000-4000-8000-000000000101']::uuid[],
  p_station    => 'aaaaaaaa-0000-4000-8000-000000000001',
  p_payload    => jsonb_build_object('period', '2026-11'),
  p_dedupe_key => 'availability_reminder:2026-11:j-3:aaaaaaaa-0000-4000-8000-000000000101'
) as id_rappel \gset

select notify(
  'availability_reminder',
  p_user_ids   => array['aaaaaaaa-0000-4000-8000-000000000101']::uuid[],
  p_station    => 'aaaaaaaa-0000-4000-8000-000000000001',
  p_payload    => jsonb_build_object('period', '2026-11'),
  p_dedupe_key => 'availability_reminder:2026-11:j-3:aaaaaaaa-0000-4000-8000-000000000101'
) as id_rappel_bis \gset

select tests.check(
  :'id_rappel' = :'id_rappel_bis',
  'le second appel rend la demande déjà en file, il n''en crée pas une deuxième');

select tests.check(
  (select count(*) from notification_outbox
    where dedupe_key = 'availability_reminder:2026-11:j-3:aaaaaaaa-0000-4000-8000-000000000101') = 1,
  'une seule ligne en file pour ce membre et cette échéance');

select tests.check(
  (select attempts = 1 from notification_outbox where id = :'id_rappel'),
  'le rejeu ne repose pas la demande : pas de doublon de notification');

-- La clé ne collisionne pas entre types : deux rapports du même planning, l'un de
-- retardataires, l'autre de validation, cohabitent.
select notify(
  'late_responders',
  p_user_ids   => array['aaaaaaaa-0000-4000-8000-000000000100']::uuid[],
  p_station    => 'aaaaaaaa-0000-4000-8000-000000000001',
  p_dedupe_key => 'availability_reminder:2026-11:j-3:aaaaaaaa-0000-4000-8000-000000000101'
) as id_autre_type \gset

select tests.check(
  :'id_autre_type' <> :'id_rappel',
  'la clé de dédoublonnage est propre à chaque type');

\echo ''
\echo '-- 4. notify_claim ne rend une demande qu''une fois'

select tests.check(
  (select (notify_claim(:'id_validation')).id is not null),
  'la première prise en charge rend la demande');

select tests.check(
  (select status = 'sending' and locked_until > now() + interval '1 minute'
     from notification_outbox where id = :'id_validation'),
  'elle passe la demande en « sending » et pose le verrou');

-- Le point que la revue a relevé : sans changement de statut, une seconde prise
-- en charge — la reprise qui n'a pas vu le verrou, ou deux requêtes arrivées
-- ensemble — rendait la demande une deuxième fois, et le membre recevait la
-- notification en double.
select tests.check(
  (select (notify_claim(:'id_validation')).id is null),
  'une seconde prise en charge ne rend rien : la première l''a bien prise');

select notify_complete(:'id_validation', true, null,
  jsonb_build_object('recipients', 2, 'delivered', 2, 'failed', 0));

select tests.check(
  (select (notify_claim(:'id_validation')).id is null),
  'une demande close n''est plus relue : le rejeu n''envoie rien deux fois');

select tests.check(
  (select status = 'sent' and processed_at is not null and locked_until is null
      and result ->> 'delivered' = '2'
     from notification_outbox where id = :'id_validation'),
  'notify_complete clôt la demande avec son compte rendu');

\echo ''
\echo '-- 5. notify_complete trace aussi un échec'

select notify_complete(:'id_autre_type', false, 'invalid_type : essai');

select tests.check(
  (select status = 'failed' and last_error = 'invalid_type : essai'
     from notification_outbox where id = :'id_autre_type'),
  'une demande que l''Edge Function n''a pas su traiter passe en échec, avec son motif');

\echo ''
\echo '-- 6. La reprise'

savepoint avant_reprise;

-- Table nette : seules les lignes créées ici comptent.
delete from notification_outbox;

insert into notification_outbox (id, station_id, type, recipients, created_at, attempts, locked_until)
values
  -- fraîche et jamais postée : laissée à la tentative immédiate de notify()
  ('cccccccc-0000-4000-8000-000000000001',
   'aaaaaaaa-0000-4000-8000-000000000001', 'schedule_validated',
   '[{"user_id":"aaaaaaaa-0000-4000-8000-000000000101"}]'::jsonb,
   now() - interval '5 seconds', 0, null),
  -- vieille et jamais postée : la tentative immédiate a échoué, à reprendre
  ('cccccccc-0000-4000-8000-000000000002',
   'aaaaaaaa-0000-4000-8000-000000000001', 'schedule_validated',
   '[{"user_id":"aaaaaaaa-0000-4000-8000-000000000101"}]'::jsonb,
   now() - interval '5 minutes', 0, null),
  -- verrouillée : une Edge Function est en train de la traiter
  ('cccccccc-0000-4000-8000-000000000003',
   'aaaaaaaa-0000-4000-8000-000000000001', 'schedule_validated',
   '[{"user_id":"aaaaaaaa-0000-4000-8000-000000000101"}]'::jsonb,
   now() - interval '5 minutes', 1, now() + interval '1 minute'),
  -- cinq tentatives sans réponse : à abandonner
  ('cccccccc-0000-4000-8000-000000000004',
   'aaaaaaaa-0000-4000-8000-000000000001', 'schedule_validated',
   '[{"user_id":"aaaaaaaa-0000-4000-8000-000000000101"}]'::jsonb,
   now() - interval '1 hour', 5, now() - interval '1 minute');

-- Prise en charge par une Edge Function qui n'a jamais rendu sa réponse
-- (redémarrage, dépassement de délai) : son verrou a expiré.
insert into notification_outbox (id, station_id, type, recipients, created_at, attempts, status, locked_until)
values
  ('cccccccc-0000-4000-8000-000000000005',
   'aaaaaaaa-0000-4000-8000-000000000001', 'schedule_validated',
   '[{"user_id":"aaaaaaaa-0000-4000-8000-000000000101"}]'::jsonb,
   now() - interval '10 minutes', 1, 'sending', now() - interval '3 minutes'),
  -- prise en charge en cours, verrou encore valide : on n'y touche pas
  ('cccccccc-0000-4000-8000-000000000006',
   'aaaaaaaa-0000-4000-8000-000000000001', 'schedule_validated',
   '[{"user_id":"aaaaaaaa-0000-4000-8000-000000000101"}]'::jsonb,
   now() - interval '10 seconds', 1, 'sending', now() + interval '2 minutes');

-- Deux demandes reposées : celle restée en plan, et celle dont la prise en charge
-- a été abandonnée et qui vient de revenir en attente.
select tests.check(
  cron_dispatch_notifications() = 2,
  'la reprise repose la demande restée en plan et celle dont la prise en charge a expiré');

select tests.check(
  (select attempts = 0 and status = 'pending'
     from notification_outbox where id = 'cccccccc-0000-4000-8000-000000000001'),
  'une demande de moins de 45 secondes est laissée à la tentative immédiate');

select tests.check(
  (select attempts = 1 and locked_until > now()
     from notification_outbox where id = 'cccccccc-0000-4000-8000-000000000002'),
  'la demande restée en plan est repostée, compteur incrémenté et verrou posé');

select tests.check(
  (select attempts = 1 from notification_outbox where id = 'cccccccc-0000-4000-8000-000000000003'),
  'une demande verrouillée n''est pas repostée : pas de doublon');

select tests.check(
  (select status = 'failed' and last_error like 'abandon après 5 tentatives%'
     from notification_outbox where id = 'cccccccc-0000-4000-8000-000000000004'),
  'au bout de cinq tentatives la demande est abandonnée, avec une erreur lisible');

-- Sans ce retour en arrière, une demande restée en `sending` ne serait jamais
-- reprise : la file aurait un trou noir, et la notification disparaîtrait.
select tests.check(
  (select status = 'pending' and attempts = 2 and locked_until > now()
     from notification_outbox where id = 'cccccccc-0000-4000-8000-000000000005'),
  'une prise en charge sans réponse revient en attente, puis repart');

select tests.check(
  (select status = 'sending' and attempts = 1
     from notification_outbox where id = 'cccccccc-0000-4000-8000-000000000006'),
  'une prise en charge en cours n''est pas dérangée');

-- Idempotence : rejouée aussitôt, la tâche ne touche plus rien (tout est verrouillé).
select tests.check(
  cron_dispatch_notifications() = 0,
  'rejouée dans la foulée, la reprise ne repose rien');

-- Trois minutes plus tard, tous les verrous ont expiré, la demande fraîche a
-- vieilli et la prise en charge encore valide est devenue caduque : les cinq
-- demandes non closes repartent. C'est ce qui garantit qu'une Edge Function
-- indisponible retarde une notification sans jamais la perdre.
--
-- Six et non cinq depuis le ticket 040 : l'abandon de la demande …004 a mis en
-- file la ligne interne de son destinataire, et cette demande-là est une demande
-- comme les autres — elle attend, elle est reprise, elle finit par aboutir.
select tests.check(
  cron_dispatch_notifications(now() + interval '3 minutes') = 6,
  'les verrous expirés, la reprise reprend la main sur tout ce qui n''est pas clos');

select tests.check(
  (select count(*) from notification_outbox
    where payload ? 'delivery_failure'
      and dedupe_key = 'delivery_failure:cccccccc-0000-4000-8000-000000000004') = 1,
  'la sixième est la ligne interne que l''abandon devait au pompier (ticket 040)');

rollback to savepoint avant_reprise;

\echo ''
\echo '-- 6 bis. Un abandon laisse une ligne pour son destinataire (ticket 040)'

savepoint avant_trace;

-- Ce que l'abandon valait avant ce ticket : une ligne `failed` dans la file, que
-- seul le rôle de service voit. Le pompier à qui on proposait l'astreinte du
-- 12 octobre n'avait rien — ni push, ni courriel, ni ligne dans son centre de
-- notifications. Le ticket 026 a tranché : c'est **lui** qu'on prévient.
--
-- Le français ne peut pas s'écrire ici : il vit dans
-- `supabase/functions/_shared/notification_content.ts`, et le recopier en
-- plpgsql en ferait un second endroit à tenir à jour. L'abandon remet donc la
-- même demande en file, canal `inapp` seul et marque `delivery_failure` : c'est
-- `send-notification` qui écrira la ligne, avec les mots habituels. Ce que ce
-- fichier vérifie, c'est tout ce qui se décide en SQL — la trace existe, elle est
-- fidèle, elle est unique, et elle ne boucle pas.
delete from notification_outbox;

insert into notification_outbox
  (id, station_id, type, recipients, payload, channels, created_at, attempts, locked_until)
values
  ('cccccccc-0000-4000-8000-000000000010',
   'aaaaaaaa-0000-4000-8000-000000000001', 'assignment_proposed',
   '[{"user_id":"aaaaaaaa-0000-4000-8000-000000000101",
      "payload":{"shifts":[{"date":"2026-10-12","slot":"night"}]}}]'::jsonb,
   '{"period":"2026-10"}'::jsonb,
   array['push', 'inapp'],
   now() - interval '1 hour', 5, now() - interval '1 minute');

-- Aucune demande *repostée* : celle-ci est abandonnée, et la trace qu'elle
-- engendre est postée par `notify()`, pas par la boucle de reprise.
select tests.check(
  cron_dispatch_notifications() = 0,
  'la reprise ne repose rien : la demande a épuisé ses tentatives');

select tests.check(
  (select status = 'failed' and last_error like 'abandon après 5 tentatives%'
     from notification_outbox where id = 'cccccccc-0000-4000-8000-000000000010'),
  'la demande est abandonnée, avec son motif, comme avant');

select tests.check(
  (select count(*) from notification_outbox
    where dedupe_key = 'delivery_failure:cccccccc-0000-4000-8000-000000000010') = 1,
  'et elle laisse une demande de trace pour son destinataire');

-- Fidélité : la trace doit produire **la** notification qu'on a failli perdre,
-- pas un succédané. Même type, même caserne, mêmes destinataires, même charge
-- utile — c'est ce qui donne « Astreinte proposée le 12 octobre, nuit » à
-- l'arrivée, et non « une notification a échoué ».
select tests.check(
  (select t.type = 'assignment_proposed'
      and t.station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
      and t.channels = array['inapp']
      and t.recipients = o.recipients
      and t.payload ->> 'period' = '2026-10'
     from notification_outbox t, notification_outbox o
    where t.dedupe_key = 'delivery_failure:cccccccc-0000-4000-8000-000000000010'
      and o.id = 'cccccccc-0000-4000-8000-000000000010'),
  'la trace reprend le type, la caserne, les destinataires et la charge utile, sur le seul canal inapp');

-- Le motif technique voyage avec la trace : c'est lui qui remplira
-- `notifications.error`, la colonne que l'écran regarde pour afficher sa mention.
-- Son contenu n'est jamais montré au membre, donc aucune phrase française n'a à
-- être écrite ici.
select tests.check(
  (select payload -> 'delivery_failure' ->> 'outbox_id'
            = 'cccccccc-0000-4000-8000-000000000010'
      and (payload -> 'delivery_failure' ->> 'attempts')::int = 5
      and payload -> 'delivery_failure' ->> 'error' like 'abandon après 5 tentatives%'
     from notification_outbox
    where dedupe_key = 'delivery_failure:cccccccc-0000-4000-8000-000000000010'),
  'elle porte le motif de l''abandon, pour la colonne error de la ligne interne');

select tests.check(
  (select status = 'pending' and attempts = 1 and locked_until > now()
     from notification_outbox
    where dedupe_key = 'delivery_failure:cccccccc-0000-4000-8000-000000000010'),
  'elle est postée aussitôt, et reprise comme n''importe quelle demande si ça échoue');

-- Rejeu de la tâche : l'abandon est déjà clos, il ne repasse pas, et la clé de
-- dédoublonnage empêcherait de toute façon une seconde trace.
select cron_dispatch_notifications(now() + interval '5 minutes');

select tests.check(
  (select count(*) from notification_outbox where payload ? 'delivery_failure') = 1,
  'rejouée, la tâche ne produit pas une seconde trace');

-- Et si la trace elle-même n'aboutit pas ? Elle passe par la file, donc elle peut
-- être abandonnée à son tour. Sans garde-fou, elle engendrerait une trace de la
-- trace, indéfiniment. La marque `delivery_failure` de sa propre charge utile est
-- ce garde-fou.
update notification_outbox
   set status = 'pending', attempts = 5, locked_until = now() - interval '1 minute'
 where dedupe_key = 'delivery_failure:cccccccc-0000-4000-8000-000000000010';

select cron_dispatch_notifications(now() + interval '10 minutes');

select tests.check(
  (select status = 'failed' from notification_outbox
    where dedupe_key = 'delivery_failure:cccccccc-0000-4000-8000-000000000010'),
  'une trace qui n''aboutit pas est abandonnée comme le reste');

select tests.check(
  (select count(*) from notification_outbox where payload ? 'delivery_failure') = 1,
  'mais une trace ne se trace pas elle-même : pas de boucle');

select tests.check(
  notify_trace_echec('cccccccc-0000-4000-8000-0000000000ff') is null,
  'une demande inconnue ne produit pas de trace');

rollback to savepoint avant_trace;

\echo ''
\echo '-- 7. La file n''est lisible par personne côté application'

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.denied(
  $$select * from notification_outbox$$,
  'un admin de caserne ne lit pas la file des notifications');

select tests.denied(
  $$insert into notification_outbox (type, recipients)
    values ('schedule_validated', '[{"user_id":"aaaaaaaa-0000-4000-8000-000000000100"}]'::jsonb)$$,
  'un admin n''écrit pas dans la file');

reset role;
set local role anon;

select tests.denied(
  $$select * from notification_outbox$$,
  'anon ne lit pas la file des notifications');

reset role;

\echo ''
\echo '-- 8. Les fonctions ne sont pas des boutons pour les clients'

select tests.check(
  not has_function_privilege('authenticated',
    'public.notify(notification_type, uuid[], uuid, jsonb, text[], jsonb, text)', 'execute'),
  'notify n''est pas appelable par authenticated');

select tests.check(
  not has_function_privilege('anon',
    'public.notify(notification_type, uuid[], uuid, jsonb, text[], jsonb, text)', 'execute'),
  'notify n''est pas appelable par anon');

select tests.check(
  not has_function_privilege('authenticated', 'public.notify_post(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.notify_post(uuid)', 'execute'),
  'notify_post n''est pas appelable par un client');

select tests.check(
  not has_function_privilege('authenticated',
    'public.cron_dispatch_notifications(timestamptz, integer, integer)', 'execute'),
  'la tâche de reprise n''est pas appelable par un client');

select tests.check(
  not has_function_privilege('authenticated', 'public.notify_trace_echec(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.notify_trace_echec(uuid)', 'execute'),
  'la trace d''un envoi abandonné n''est pas un bouton pour les clients');

-- Le secret d'appel interne : lisible par la clé de service (l'Edge Function en a
-- besoin pour authentifier ce qui vient de pg_net), par personne d'autre.
select tests.check(
  not has_function_privilege('authenticated', 'public.notify_internal_secret()', 'execute')
  and not has_function_privilege('anon', 'public.notify_internal_secret()', 'execute'),
  'le secret d''appel interne n''est pas lisible par un client');

select tests.check(
  has_function_privilege('service_role', 'public.notify_internal_secret()', 'execute')
  and has_function_privilege('service_role', 'public.notify_claim(uuid)', 'execute')
  and has_function_privilege('service_role',
        'public.notify_complete(uuid, boolean, text, jsonb)', 'execute'),
  'l''Edge Function, elle, a ce qu''il lui faut');

select tests.check(
  (select length(coalesce(notify_internal_secret(), '')) >= 32),
  'le secret d''appel a été engendré par la migration, et il est long');

select tests.check(
  (select count(*) from cron.job where jobname = 'dispatch_notifications'
     and command = 'select public.cron_dispatch_notifications();') = 1,
  'la tâche dispatch_notifications est planifiée, qualifiée et sans argument');

select tests.check(
  (select schedule from cron.job where jobname = 'dispatch_notifications') = '* * * * *',
  'elle tourne chaque minute : c''est le retard maximum d''une notification');

\echo ''
\echo 'notifications_test : OK'

rollback;
