-- 0022 — Une demande de notification abandonnée laisse une ligne lisible par son
-- destinataire. Ticket 040 (relevé en revue du 025, tranché au 026).
-- Référence : docs/SCHEMA.md sections 2.12, 2.16, 3 et 8 ; docs/WORKFLOWS.md § 8.
--
-- Le trou que cette migration bouche
-- ----------------------------------
-- `cron_dispatch_notifications` (0014) abandonne une demande au bout de cinq
-- tentatives : la ligne de `notification_outbox` passe `failed` avec sa dernière
-- erreur. C'est une trace d'exploitation, lisible par le seul rôle de service.
-- Le pompier à qui on proposait une astreinte, lui, n'a **rien** : ni push, ni
-- courriel, ni ligne dans son centre de notifications. Il peut ne jamais
-- l'apprendre, et personne ne s'en aperçoit — précisément ce que la file
-- d'attente existait pour rendre impossible.
--
-- Décision du ticket 026 : c'est le **destinataire** qu'on prévient, pas les
-- administrateurs. Il est celui qui perd quelque chose ; alerter un chef de
-- centre transformerait un incident technique en tâche humaine chez des
-- bénévoles un samedi soir. Le centre de notifications est déjà le filet du
-- membre sans notification poussée, et l'écran sait déjà montrer la mention :
-- `notifications.error` non nul ⇒ « L'envoi a échoué, tu ne l'as peut-être pas
-- reçue » (`AppStrings.centreEnvoiEchoue`, ticket 026).
--
-- La difficulté, et la voie choisie
-- ---------------------------------
-- La tâche est en SQL ; le français des notifications est construit dans
-- `supabase/functions/_shared/notification_content.ts`, où il est testé et relu
-- d'un seul endroit. Écrire la ligne directement ici obligerait à recopier en
-- plpgsql « Astreinte proposée le 12 octobre, nuit » et ses quinze cousines : le
-- projet a déjà payé ce prix une fois avec les jours fériés, et le critère du
-- ticket est explicite — aucune phrase française à deux endroits.
--
-- On prend donc l'autre voie du ticket : **appeler la fonction d'envoi dans un
-- mode qui n'écrit que la ligne interne**. Et on l'appelle par le seul chemin
-- que la base connaisse déjà, `notify(...)` — c'est-à-dire par la file
-- elle-même :
--
--   1. la demande d'origine est abandonnée, comme avant (`failed`, `last_error`) ;
--   2. une **demande de trace** est mise en file : même type, mêmes
--      destinataires, même charge utile, `channels = {inapp}`, plus une clé
--      `delivery_failure` dans la charge utile commune ;
--   3. `send-notification` la reconnaît à cette clé, n'envoie **rien** (ni push,
--      ni courriel) et écrit la seule ligne `inapp`, avec `delivered = false` et
--      `error` renseignée. Le titre et le corps sortent de `construireContenu`,
--      donc du même endroit que d'habitude : la ligne dit « Astreinte proposée le
--      12 octobre, nuit », pas « une notification a échoué ».
--
-- Ce que ce détour achète, qu'un appel direct n'achèterait pas : la trace hérite
-- de toute la machinerie de la file. Si l'Edge Function est encore en panne au
-- moment de l'abandon — le cas le plus probable, puisque c'est elle qui vient de
-- faire échouer cinq tentatives —, la demande de trace reste en attente et repart
-- à la minute suivante, au lieu d'être perdue à son tour.
--
-- Ce que ce détour ne peut pas promettre : si `send-notification` ne revient
-- jamais, la ligne ne s'écrit jamais. Aucune solution ne peut promettre mieux
-- sans remettre le français en base — et dans ce monde-là, plus aucune
-- notification ne part de toute façon. La demande de trace est alors abandonnée
-- à son tour, visible en exploitation comme les autres.
--
-- Pas de boucle : une demande de trace ne se trace pas elle-même
-- --------------------------------------------------------------
-- La trace passe par la file, donc elle peut être abandonnée, donc elle
-- déclencherait une trace de la trace, à l'infini. Le garde-fou est la clé
-- `delivery_failure` de sa propre charge utile : une demande qui la porte n'en
-- engendre pas d'autre. Un seul endroit, testé.
--
-- L'unicité, elle, est celle de `notification_outbox_dedupe_uniq` (0014) : la clé
-- `delivery_failure:<id de la demande abandonnée>` fait qu'un rejeu de la tâche
-- ne produit pas deux traces.
--
-- Pourquoi `error` ne porte pas de phrase française
-- -------------------------------------------------
-- L'écran ne lit pas le contenu de `notifications.error` : il regarde seulement
-- si la colonne est renseignée, et affiche alors sa propre mention, centralisée
-- dans `AppStrings` (`NotificationInterne.enEchec`, ticket 026). La colonne peut
-- donc porter le motif technique — celui de `notification_outbox.last_error` —
-- qui est ce qu'on veut y lire en exploitation. Aucune phrase destinée au membre
-- n'est écrite ici.

-- ===========================================================================
-- 1. La demande de trace
-- ===========================================================================
-- Rend l'identifiant de la demande de trace mise en file, ou NULL quand il n'y a
-- rien à tracer (demande inconnue, ou demande qui est elle-même une trace).
--
-- `security definer` et sans droit d'exécution pour les clients, comme tout ce
-- qui touche à la file : elle porte les charges utiles de toutes les casernes.
create function notify_trace_echec(p_outbox uuid) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  ligne notification_outbox;
begin
  select * into ligne from notification_outbox where id = p_outbox;
  if not found then
    return null;
  end if;

  -- Le garde-fou de la boucle : une trace abandonnée ne se trace pas.
  if ligne.payload ? 'delivery_failure' then
    return null;
  end if;

  return notify(
    ligne.type,
    p_station    => ligne.station_id,
    -- La charge utile d'origine est conservée telle quelle : c'est elle qui
    -- porte la période et les créneaux, donc le titre que le membre lira. On ne
    -- fait qu'y ajouter le motif.
    p_payload    => coalesce(ligne.payload, '{}'::jsonb) || jsonb_build_object(
                      'delivery_failure', jsonb_build_object(
                        'outbox_id', ligne.id,
                        'attempts',  ligne.attempts,
                        -- Motif technique, jamais montré au membre. `last_error`
                        -- est toujours renseignée par l'abandon ; le repli ne
                        -- sert qu'à garantir une colonne `error` non vide, qui
                        -- est le signal que l'écran regarde.
                        'error',     coalesce(nullif(btrim(ligne.last_error), ''),
                                              'delivery_failed'))),
    -- Le mode : la ligne interne, et rien d'autre. Pas de second push sur un
    -- canal qui vient d'échouer cinq fois, pas de courriel de rattrapage — la
    -- trace dit ce qui s'est passé, elle ne rejoue pas l'envoi.
    p_channels   => array['inapp'],
    p_recipients => ligne.recipients,
    p_dedupe_key => 'delivery_failure:' || ligne.id);
end $$;

comment on function notify_trace_echec(uuid) is
  'Met en file la ligne interne d''une demande de notification abandonnée (ticket 040) : même type, mêmes destinataires, même charge utile, canal inapp seul, motif dans payload.delivery_failure. Rend NULL si la demande est inconnue ou si elle est elle-même une trace — une trace ne se trace pas.';

revoke execute on function notify_trace_echec(uuid) from public, anon, authenticated;

-- ===========================================================================
-- 2. La reprise, qui trace désormais ses abandons
-- ===========================================================================
-- Corps identique à celui de 0014, à une chose près : l'abandon rend les
-- identifiants qu'il vient de clore, et chacun reçoit sa demande de trace. Le
-- reste — retour des prises en charge expirées, délai de grâce de 45 secondes,
-- reposte verrou par verrou — n'est pas touché.
--
-- L'ordre compte : les traces sont mises en file **avant** la boucle de reposte,
-- donc `notify()` a déjà tenté leur envoi immédiat et posé leur verrou quand la
-- boucle les rencontrerait. Elles ne partent pas deux fois dans le même tour.
create or replace function cron_dispatch_notifications(
  p_reference    timestamptz default null,
  p_limit        integer     default 100,
  p_max_attempts integer     default 5
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant  timestamptz := coalesce(p_reference, now());
  ligne    record;
  abandons uuid[];
  abandon  uuid;
  postees  integer := 0;
begin
  -- 0. Les prises en charge abandonnées redeviennent des demandes en attente.
  update notification_outbox
     set status     = 'pending',
         last_error = coalesce(
                        last_error,
                        'prise en charge sans réponse, demande remise en attente')
   where status = 'sending'
     and locked_until <= instant;

  -- 1. L'abandon au bout de `p_max_attempts` tentatives.
  with abandonnees as (
    update notification_outbox
       set status       = 'failed',
           processed_at = instant,
           locked_until = null,
           last_error   = coalesce(
                            last_error,
                            'abandon après ' || p_max_attempts || ' tentatives sans réponse')
     where status = 'pending'
       and attempts >= p_max_attempts
       and (locked_until is null or locked_until <= instant)
    returning id
  )
  select coalesce(array_agg(id), '{}'::uuid[]) into abandons from abandonnees;

  -- 1 bis. Ticket 040 : chaque abandon laisse une ligne lisible par son
  -- destinataire. Sans elle, l'abandon est un silence pour le seul intéressé.
  foreach abandon in array abandons loop
    perform notify_trace_echec(abandon);
  end loop;

  -- 2 et 3. Le reposte.
  for ligne in
    select id
      from notification_outbox
     where status = 'pending'
       and attempts < p_max_attempts
       and (locked_until is null or locked_until <= instant)
       and (attempts > 0 or created_at <= instant - interval '45 seconds')
     order by created_at
     limit p_limit
  loop
    if notify_post(ligne.id) then
      postees := postees + 1;
    end if;
  end loop;

  return postees;
end $$;

comment on function cron_dispatch_notifications(timestamptz, integer, integer) is
  'Tâche dispatch_notifications (docs/SCHEMA.md § 8) : repose les demandes de notification restées en attente, abandonne celles qui ont épuisé leurs tentatives et met en file la ligne interne de chaque abandon (notify_trace_echec, ticket 040). Idempotente. Renvoie le nombre de demandes repostées — les traces ne sont pas comptées, elles sont postées par notify().';

revoke execute on function cron_dispatch_notifications(timestamptz, integer, integer)
  from public, anon, authenticated;
