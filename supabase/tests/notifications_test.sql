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
-- 4. `notify_claim` ne rend une demande qu'une fois : un rejeu de la tâche de
--    reprise sur une demande déjà traitée n'envoie rien.
-- 5. `notify_complete` clôt la demande, en réussite comme en échec.
-- 6. `cron_dispatch_notifications` : elle laisse les demandes fraîches à la
--    tentative immédiate, reprend les autres, respecte le verrou et abandonne au
--    bout de cinq tentatives — avec une erreur lisible, pas un silence.
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
  'la première relecture rend la demande');

select tests.check(
  (select (notify_claim(:'id_validation')).locked_until > now() + interval '1 minute'),
  'la relecture pose un verrou : la reprise ne marche pas dessus');

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

select tests.check(
  cron_dispatch_notifications() = 1,
  'la reprise ne repose que la demande vieille et non verrouillée');

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

-- Idempotence : rejouée aussitôt, la tâche ne touche plus rien (tout est verrouillé).
select tests.check(
  cron_dispatch_notifications() = 0,
  'rejouée dans la foulée, la reprise ne repose rien');

-- Trois minutes plus tard, les verrous ont expiré et la demande fraîche a vieilli :
-- les trois demandes encore en attente repartent. C'est ce qui garantit qu'une
-- Edge Function indisponible retarde une notification sans jamais la perdre.
select tests.check(
  cron_dispatch_notifications(now() + interval '3 minutes') = 3,
  'les verrous expirés, la reprise reprend la main sur tout ce qui est en attente');

rollback to savepoint avant_reprise;

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
