-- 0014 — Chemin d'appel des notifications depuis la base. Ticket 025.
-- Référence : docs/SCHEMA.md sections 2.11, 2.12, 3, 7 et 8 ; docs/WORKFLOWS.md 6 et 8.
--
-- Ce que cette migration ne fait PAS
-- ----------------------------------
-- Elle n'écrit aucune notification et n'envoie rien. Le contenu français, le
-- regroupement, l'envoi FCM, le courriel et la suppression des jetons rejetés
-- vivent dans l'Edge Function `send-notification` (Deno), parce que signer un
-- jeton OAuth Google en plpgsql n'a pas de sens. Cette migration ne pose que le
-- **chemin d'appel** : comment un déclencheur ou une tâche planifiée demande un
-- envoi, et comment cette demande survit à une panne du destinataire.
--
-- Écart assumé avec docs/SCHEMA.md et le ticket : une file d'attente
-- ---------------------------------------------------------------
-- Le ticket demandait « appel depuis SQL via pg_net (fonction notify(...)) ».
-- L'appel pg_net est là, mais il n'est plus le dépositaire de la demande.
--
-- `net.http_post` est asynchrone et **sans mémoire** : il pousse une requête
-- dans `net.http_request_queue`, un worker la tire, et si l'Edge Function ne
-- répond pas (déploiement en cours, 500, quota), la requête est perdue. Aucune
-- reprise, aucune trace — et comme c'est l'Edge Function qui écrit la ligne
-- `notifications`, une perte ne laisse **rien** derrière elle. Un pompier à qui
-- on a attribué une astreinte ne l'apprendrait jamais, et personne ne le saurait.
--
-- `notification_outbox` corrige exactement ça : la demande est écrite dans la
-- transaction métier (publication d'un planning, verrouillage d'une période), donc
-- elle existe ou l'événement n'a pas eu lieu — jamais entre les deux. La tentative
-- pg_net immédiate garde la latence à quelques centaines de millisecondes ; la
-- tâche `dispatch_notifications` (chaque minute) est le filet : elle reprend ce qui
-- n'a pas abouti, cinq fois, puis marque la ligne `failed` avec sa dernière erreur.
-- Une notification perdue devient donc une ligne visible, pas un silence.
--
-- Conséquence pour les tickets 015, 019, 020, 022 et 026 : ils appellent
-- `public.notify(...)` et n'ont rien d'autre à savoir. Les deux Edge Functions
-- `publish-schedule` (019) et `reassign-shift` (020), elles, peuvent appeler
-- `send-notification` directement en HTTP (elles ont déjà la clé de service) :
-- c'est le chemin synchrone, celui qui rend un compte rendu à l'admin qui vient
-- de cliquer. La file sert le chemin asynchrone, celui des déclencheurs et des crons.
--
-- Livraison **au moins une fois**, jamais zéro : un doublon de notification est
-- un désagrément, une proposition d'astreinte jamais reçue est une faute.

-- ===========================================================================
-- 1. La file d'attente
-- ===========================================================================
-- `recipients` porte un destinataire par entrée, avec sa propre charge utile :
-- c'est ce qui permet à une publication de planning d'envoyer **une** notification
-- par membre listant **ses** créneaux (docs/WORKFLOWS.md § 8, colonne
-- « Regroupement »). La forme est fixée par `notification_outbox_recipients_valides`
-- ci-dessous et documentée dans supabase/functions/README.md.
create table notification_outbox (
  id            uuid primary key default gen_random_uuid(),
  station_id    uuid references stations(id) on delete cascade,
  type          notification_type not null,
  recipients    jsonb not null,
  payload       jsonb not null default '{}'::jsonb,
  channels      text[],
  dedupe_key    text,
  status        text not null default 'pending'
                  check (status in ('pending', 'sending', 'sent', 'failed')),
  attempts      int not null default 0,
  locked_until  timestamptz,
  last_error    text,
  result        jsonb,
  created_at    timestamptz not null default now(),
  processed_at  timestamptz
);

comment on table notification_outbox is
  'File d''attente des envois de notification (ticket 025). Écrite dans la transaction métier par public.notify(), consommée par l''Edge Function send-notification, reprise par la tâche dispatch_notifications.';
comment on column notification_outbox.recipients is
  'Tableau JSON [{"user_id": uuid, "payload": {…}}]. Une entrée par destinataire, avec sa charge utile propre : c''est le support du regroupement.';
comment on column notification_outbox.channels is
  'Canaux forcés par l''appelant (push, email, inapp). NULL = canaux par défaut du type (docs/WORKFLOWS.md § 8).';
comment on column notification_outbox.status is
  'pending : en attente. sending : une Edge Function l''a prise en charge (verrou locked_until). sent / failed : close. Une prise en charge abandonnée revient à pending quand son verrou expire (cron_dispatch_notifications).';
comment on column notification_outbox.dedupe_key is
  'Clé d''unicité métier. Deux appels de même type et même clé ne produisent qu''une ligne : « un rappel par membre et par échéance » (015), « un rapport par jour et par planning » (022).';

-- La forme de `recipients` est vérifiée ici et pas seulement dans notify() :
-- une Edge Function ou un test qui insère directement doit se heurter à la même
-- règle, sinon la garantie n'en est pas une.
create function notification_outbox_recipients_valides(p_recipients jsonb)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select jsonb_typeof(p_recipients) = 'array'
     and jsonb_array_length(p_recipients) > 0
     and not exists (
       select 1
         from jsonb_array_elements(p_recipients) as e(entree)
        where jsonb_typeof(e.entree) is distinct from 'object'
           or e.entree ->> 'user_id' is null
           or (e.entree ->> 'user_id') !~
              '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
           or (e.entree ? 'payload'
               and jsonb_typeof(e.entree -> 'payload') is distinct from 'object')
     );
$$;

comment on function notification_outbox_recipients_valides(jsonb) is
  'Support de la contrainte notification_outbox_recipients_valide : tableau non vide d''objets {user_id: uuid, payload?: object}.';

alter table notification_outbox
  add constraint notification_outbox_recipients_valide
  check (notification_outbox_recipients_valides(recipients));

-- La file de travail de la tâche de reprise. Index partiel : seules les lignes
-- en attente sont lues, et elles sont rares au regard de l'historique.
create index notification_outbox_pending_idx
  on notification_outbox (created_at)
  where status in ('pending', 'sending');

-- « Un seul envoi par membre et par échéance » (ticket 015), « une fois par jour
-- et par planning » (docs/WORKFLOWS.md § 8, late_responders) : la règle est ici,
-- pas dans cinq appelants qui la réécriront chacun à leur façon.
create unique index notification_outbox_dedupe_uniq
  on notification_outbox (type, dedupe_key)
  where dedupe_key is not null;

-- Personne ne lit cette table depuis l'application : elle porte les charges utiles
-- de toutes les casernes à la fois. RLS activée sans aucune politique — donc
-- fermée — et les privilèges par défaut d'`auto_expose_new_tables` retirés.
alter table notification_outbox enable row level security;
revoke all on notification_outbox from anon, authenticated;

-- ===========================================================================
-- 2. Où appeler, et avec quel secret
-- ===========================================================================
-- L'adresse de l'Edge Function et le secret d'appel vivent dans Supabase Vault,
-- chiffrés, pas dans une colonne en clair ni dans une migration.
--
-- Le secret est **engendré ici**, au hasard, et lu par l'Edge Function avec sa
-- clé de service. Personne n'a à le recopier nulle part : c'est la seule forme
-- d'authentification interne qui n'introduit ni étape manuelle ni secret dans le
-- dépôt. La base ne peut pas porter la clé de service (ce serait la mettre en
-- clair dans le seed), et l'Edge Function ne peut pas deviner un mot de passe
-- qu'on ne lui a pas donné : elle va donc le chercher là où il est.
--
-- L'URL par défaut vise la pile locale (le conteneur Kong du réseau Docker), sur
-- le modèle de `MAILPIT_URL` dans _shared/mailer.ts. Sur un projet hébergé, elle
-- se remplace en une commande, documentée dans supabase/functions/README.md.
do $vault$
declare
  id_secret uuid;
begin
  if not exists (select 1 from vault.secrets where name = 'notify_internal_secret') then
    id_secret := vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'notify_internal_secret',
      'Secret partagé entre public.notify_post() et l''Edge Function send-notification (ticket 025). Engendré à la migration, jamais recopié.');
  end if;

  if not exists (select 1 from vault.secrets where name = 'notify_function_url') then
    id_secret := vault.create_secret(
      'http://supabase_kong_pompier:8000/functions/v1/send-notification',
      'notify_function_url',
      'Adresse de l''Edge Function send-notification. Valeur par défaut : la pile locale. À remplacer sur un projet hébergé (supabase/functions/README.md).');
  end if;
exception
  when others then
    raise notice 'Vault indisponible : notify_post() signalera l''absence de configuration (%).', sqlerrm;
end $vault$;

-- Adresse et secret d'appel, lus au moment de l'envoi. Deux lectures de Vault par
-- envoi : c'est négligeable devant un appel HTTP, et ça évite un cache à invalider
-- le jour où le secret tourne.
create function notify_endpoint(out o_url text, out o_secret text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  select decrypted_secret into o_url
    from vault.decrypted_secrets where name = 'notify_function_url';
  select decrypted_secret into o_secret
    from vault.decrypted_secrets where name = 'notify_internal_secret';
exception
  when others then
    o_url := null;
    o_secret := null;
end $$;

comment on function notify_endpoint() is
  'Adresse et secret d''appel de l''Edge Function send-notification, lus dans Supabase Vault.';

revoke execute on function notify_endpoint() from public, anon, authenticated;

-- Le secret, pour l'Edge Function qui doit vérifier l'appel entrant. Réservé à
-- `service_role` : la fonction le lit avec sa clé de service, qui donne déjà accès
-- à tout. Rien de neuf n'est exposé.
create function notify_internal_secret() returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select o_secret from notify_endpoint();
$$;

comment on function notify_internal_secret() is
  'Secret d''appel interne, lu par l''Edge Function send-notification pour authentifier les requêtes venues de pg_net. Réservé à service_role.';

revoke execute on function notify_internal_secret() from public, anon, authenticated;
grant execute on function notify_internal_secret() to service_role;

-- ===========================================================================
-- 3. Poster une ligne de la file vers l'Edge Function
-- ===========================================================================
-- Le corps HTTP ne porte que l'identifiant de la ligne : l'Edge Function relit la
-- demande complète par `notify_claim`. Une charge utile de publication de planning
-- peut faire plusieurs dizaines de kilo-octets ; elle n'a rien à faire dans une
-- file HTTP, et la relire en base garantit que les deux bouts parlent de la même
-- version de la demande.
--
-- `attempts` et `locked_until` sont posés **ici**, au moment où la requête part,
-- et pas au moment où l'Edge Function la ramasse : une fonction injoignable ne
-- ramasse rien, et le compteur doit quand même avancer, sinon la reprise tourne
-- en rond pour l'éternité.
--
-- Aucune exception ne remonte : `notify_post` est appelée depuis la transaction
-- métier. Un incident pg_net ne doit jamais annuler une publication de planning —
-- la ligne reste `pending` et la tâche de reprise s'en occupera.
create function notify_post(p_outbox uuid) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  cible    record;
  ligne    notification_outbox;
begin
  select * into ligne from notification_outbox where id = p_outbox;
  if not found or ligne.status <> 'pending' then
    return false;
  end if;

  select * into cible from notify_endpoint();

  if cible.o_url is null or cible.o_secret is null then
    update notification_outbox
       set last_error = 'notify_function_url ou notify_internal_secret absent de Vault'
     where id = p_outbox;
    return false;
  end if;

  update notification_outbox
     set attempts      = attempts + 1,
         locked_until  = now() + interval '2 minutes'
   where id = p_outbox;

  perform net.http_post(
    url                  => cible.o_url,
    body                 => jsonb_build_object('outbox_id', p_outbox),
    headers              => jsonb_build_object(
                              'Content-Type', 'application/json',
                              'x-notify-secret', cible.o_secret),
    timeout_milliseconds => 20000);

  return true;
exception
  when others then
    update notification_outbox
       set last_error = left('notify_post : ' || sqlerrm, 500)
     where id = p_outbox;
    return false;
end $$;

comment on function notify_post(uuid) is
  'Poste une ligne de notification_outbox vers l''Edge Function send-notification via pg_net. Ne lève jamais : un incident d''envoi laisse la ligne en attente pour la tâche de reprise.';

revoke execute on function notify_post(uuid) from public, anon, authenticated;

-- ===========================================================================
-- 4. `notify(...)` — le point d'entrée des déclencheurs et des crons
-- ===========================================================================
-- Deux façons de décrire les destinataires :
--
--   - `p_user_ids` + `p_payload` : tout le monde reçoit la même chose
--     (« le planning d'octobre est validé ») ;
--   - `p_recipients` : un objet par destinataire, avec sa charge utile
--     (« tes créneaux », qui ne sont pas ceux du voisin). C'est la forme du
--     regroupement, celle de la publication d'un planning.
--
-- `p_dedupe_key` rend l'appel idempotent : rejoué, il renvoie l'identifiant de la
-- ligne déjà en file et n'envoie rien de plus. Une tâche planifiée est rejouée
-- après un redémarrage de l'ordonnanceur ; sans cette clé, chaque redémarrage
-- coûterait une salve de doublons.
create function notify(
  p_type       notification_type,
  p_user_ids   uuid[]   default null,
  p_station    uuid     default null,
  p_payload    jsonb    default '{}'::jsonb,
  p_channels   text[]   default null,
  p_recipients jsonb    default null,
  p_dedupe_key text     default null
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  destinataires jsonb;
  id_ligne      uuid;
begin
  if p_recipients is not null then
    destinataires := p_recipients;
  elsif p_user_ids is not null and array_length(p_user_ids, 1) > 0 then
    select jsonb_agg(distinct jsonb_build_object('user_id', u))
      into destinataires
      from unnest(p_user_ids) as u
     where u is not null;
  end if;

  if destinataires is null or not notification_outbox_recipients_valides(destinataires) then
    raise exception 'notify_recipients_invalid'
      using hint = 'Donner p_user_ids (uuid[]) ou p_recipients ([{"user_id": uuid, "payload": {…}}]).';
  end if;

  insert into notification_outbox (station_id, type, recipients, payload, channels, dedupe_key)
  values (p_station, p_type, destinataires, coalesce(p_payload, '{}'::jsonb),
          p_channels, nullif(btrim(coalesce(p_dedupe_key, '')), ''))
  on conflict (type, dedupe_key) where dedupe_key is not null do nothing
  returning id into id_ligne;

  -- Doublon écarté par la clé : on rend la ligne déjà en file plutôt qu'une
  -- erreur. L'appelant n'a pas à distinguer « j'ai créé » de « c'était déjà fait ».
  if id_ligne is null then
    select id into id_ligne
      from notification_outbox
     where type = p_type and dedupe_key = nullif(btrim(coalesce(p_dedupe_key, '')), '');
    return id_ligne;
  end if;

  -- Tentative immédiate : la latence perçue reste celle d'un appel HTTP, pas
  -- celle de la tâche de reprise. pg_net ne dépile qu'après le COMMIT, donc
  -- l'Edge Function ne peut pas lire une demande qui n'existerait pas encore.
  perform notify_post(id_ligne);

  return id_ligne;
end $$;

comment on function notify(notification_type, uuid[], uuid, jsonb, text[], jsonb, text) is
  'Point d''entrée des notifications depuis la base (déclencheurs, tâches planifiées). Écrit la demande dans notification_outbox — dans la transaction métier — puis tente un appel immédiat. Renvoie l''identifiant de la ligne de file.';

revoke execute on function notify(notification_type, uuid[], uuid, jsonb, text[], jsonb, text)
  from public, anon, authenticated;

-- ===========================================================================
-- 5. Les deux fonctions que l'Edge Function appelle
-- ===========================================================================
-- `notify_claim` : prend la demande en charge, une fois et une seule.
--
-- La prise en charge **change le statut** (`pending` → `sending`) au lieu de se
-- contenter de repousser le verrou : c'est ce qui rend l'appel exclusif. Deux
-- requêtes qui arrivent ensemble — la tentative immédiate de `notify()` et la
-- reprise qui n'a pas vu le verrou — n'obtiennent la demande qu'une fois, la
-- seconde reçoit NULL et repart sans rien envoyer. Avec un simple verrou repoussé,
-- les deux l'obtenaient, et le membre recevait la notification en double.
--
-- `update … returning` prend un verrou de ligne : la course est arbitrée par
-- PostgreSQL, pas par la chronologie des appels.
--
-- Une Edge Function qui meurt après avoir pris la demande en charge la laisse en
-- `sending` : `cron_dispatch_notifications` la ramène à `pending` quand son verrou
-- expire. Une panne coûte deux minutes de retard, pas une notification.
create function notify_claim(p_outbox uuid)
returns notification_outbox
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  ligne notification_outbox;
begin
  update notification_outbox
     set status       = 'sending',
         locked_until = now() + interval '2 minutes'
   where id = p_outbox
     and status = 'pending'
  returning * into ligne;

  return ligne;
end $$;

comment on function notify_claim(uuid) is
  'Prend une demande de notification en charge (pending -> sending) et pose un verrou. Renvoie NULL si elle est déjà prise ou close : un rejeu n''envoie rien deux fois.';

revoke execute on function notify_claim(uuid) from public, anon, authenticated;
grant execute on function notify_claim(uuid) to service_role;

-- `notify_complete` : la demande est traitée. `p_ok` vaut faux quand l'Edge
-- Function n'a pas pu faire son travail du tout (base injoignable, type inconnu) ;
-- un envoi push qui échoue pour un destinataire n'est pas un échec de la demande —
-- il est tracé dans `notifications.error`, ligne par ligne, canal par canal.
create function notify_complete(
  p_outbox uuid,
  p_ok     boolean,
  p_error  text  default null,
  p_result jsonb default null
) returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update notification_outbox
     set status       = case when p_ok then 'sent' else 'failed' end,
         processed_at = now(),
         locked_until = null,
         last_error   = left(p_error, 500),
         result       = p_result
   where id = p_outbox;
$$;

comment on function notify_complete(uuid, boolean, text, jsonb) is
  'Clôt une demande de notification : sent ou failed, avec son compte rendu. Appelée par l''Edge Function send-notification.';

revoke execute on function notify_complete(uuid, boolean, text, jsonb) from public, anon, authenticated;
grant execute on function notify_complete(uuid, boolean, text, jsonb) to service_role;

-- ===========================================================================
-- 6. La reprise
-- ===========================================================================
-- Trois règles, dans cet ordre :
--
--   0. une prise en charge dont le verrou a expiré revient à `pending` : l'Edge
--      Function qui l'avait prise n'a jamais rendu sa réponse (redémarrage,
--      dépassement de délai). Sans ce retour en arrière, une demande restée en
--      `sending` ne serait jamais reprise — la file aurait un trou noir ;
--   1. au-delà de `p_max_attempts` tentatives, la ligne passe `failed` avec sa
--      dernière erreur : on arrête de marteler une Edge Function en panne, et
--      l'incident devient visible en base plutôt que d'être un silence ;
--   2. une ligne fraîche (moins de 45 secondes) qui n'a pas encore été postée est
--      laissée à la tentative immédiate de `notify()` — sinon la reprise doublerait
--      chaque envoi ;
--   3. tout le reste est reposté, verrou par verrou.
--
-- Idempotente et paramétrée par un instant de référence, comme les tâches de la
-- migration 0012 : les tests n'attendent pas l'ordonnanceur.
create function cron_dispatch_notifications(
  p_reference    timestamptz default null,
  p_limit        integer     default 100,
  p_max_attempts integer     default 5
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant timestamptz := coalesce(p_reference, now());
  ligne   record;
  postees integer := 0;
begin
  -- 0. Les prises en charge abandonnées redeviennent des demandes en attente.
  update notification_outbox
     set status     = 'pending',
         last_error = coalesce(
                        last_error,
                        'prise en charge sans réponse, demande remise en attente')
   where status = 'sending'
     and locked_until <= instant;

  update notification_outbox
     set status       = 'failed',
         processed_at = instant,
         locked_until = null,
         last_error   = coalesce(
                          last_error,
                          'abandon après ' || p_max_attempts || ' tentatives sans réponse')
   where status = 'pending'
     and attempts >= p_max_attempts
     and (locked_until is null or locked_until <= instant);

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
  'Tâche dispatch_notifications (docs/SCHEMA.md § 8) : repose les demandes de notification restées en attente, abandonne celles qui ont épuisé leurs tentatives. Idempotente. Renvoie le nombre de demandes repostées.';

revoke execute on function cron_dispatch_notifications(timestamptz, integer, integer)
  from public, anon, authenticated;

-- ===========================================================================
-- 7. La tâche planifiée
-- ===========================================================================
-- Chaque minute : c'est le pas le plus fin de pg_cron, et il borne le retard
-- d'une notification dont la tentative immédiate a échoué. Commande qualifiée et
-- sans argument, comme les tâches de 0012 — rien n'y est interpolé.
do $planif$
begin
  perform cron.schedule(
    'dispatch_notifications', '* * * * *',
    $cmd$select public.cron_dispatch_notifications();$cmd$);
exception
  when insufficient_privilege then
    raise notice 'pg_cron : droits insuffisants pour planifier dispatch_notifications, à faire à la main.';
end $planif$;
