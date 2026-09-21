-- 0023 — Abonnement par caserne : essai de 60 jours, synchronisation des
-- événements du prestataire de paiement, suspension des impayés. Ticket 029.
-- Référence : docs/PRD.md § 6.6, docs/SCHEMA.md § 2.13, 7 et 8, docs/STRIPE.md.
--
-- Ce qui existait déjà et n'est pas réécrit
-- -----------------------------------------
--   - `subscriptions` (0006) : la table, sa clé primaire qui **est** la caserne,
--     et son déclencheur `set_updated_at`.
--   - Sa politique de lecture `subscriptions_select_admin` et le retrait des
--     droits d'écriture à `anon` et `authenticated` (0007). Rien n'est touché
--     ici : la lecture reste réservée aux administrateurs de la caserne, et
--     l'écriture au rôle de service.
--   - `station_writable(uuid)` (0007) : **la** définition du droit d'écrire dans
--     ce produit — `trialing`, `active` ou `past_due` écrivent ; `suspended` et
--     `cancelled` sont en lecture seule. Cette migration ne la redéfinit pas :
--     elle se contente de faire bouger `status`, et tout le reste suit.
--
-- Ce que cette migration ajoute
-- -----------------------------
--   1. `subscription_bootstrap()` : toute caserne naît avec un essai de
--      **60 jours**, sans carte bancaire. Un déclencheur, plus un rattrapage
--      des casernes déjà en base.
--   2. `subscription_sync(...)` : le seul chemin d'écriture de la table. Appelée
--      par l'Edge Function `stripe-webhook` avec la clé de service, une fois la
--      signature de l'événement vérifiée.
--   3. `stripe_events` : le journal des événements reçus. Il sert deux fois —
--      **dédoublonnage** (un événement réémis dans la fenêtre de tolérance ne
--      s'applique pas deux fois) et **trace durable** d'un traitement en échec,
--      que les rejeux du prestataire abandonnent au bout de trois jours.
--   4. `stripe_event_fail(...)` : pose cette trace depuis l'Edge Function,
--      **hors de la transaction annulée**, sans quoi elle disparaîtrait avec
--      elle.
--   5. `cron_suspend_subscriptions(instant)` : corps de la tâche
--      `suspend_subscriptions` de docs/SCHEMA.md § 8.
--   6. La tâche `pg_cron`, quotidienne.
--
-- Comme 0012, 0014, 0016 et 0021, la tâche est paramétrée par un **instant de
-- référence** : c'est la seule façon de vérifier en quelques millisecondes un
-- comportement dont la période est la journée. L'ordonnanceur appelle toujours
-- sans argument.
--
-- Aucune colonne n'est ajoutée. `docs/SCHEMA.md § 2.13` fait foi, et les neuf
-- colonnes suffisent : la date qui décide de la suspension d'un impayé est
-- `current_period_end`, la fin de la dernière période **payée**. Stripe ne
-- l'avance qu'après un paiement réussi ; elle ne recule donc pas à chaque
-- relance de carte, contrairement à `updated_at`, qui ferait reculer
-- indéfiniment l'échéance des quatorze jours à chaque tentative échouée.

-- ===========================================================================
-- 1. L'essai de 60 jours, posé par la base
-- ===========================================================================
-- Il est **géré côté application, sans carte bancaire** (ticket 029, PRD § 6.6) :
-- aucun essai Stripe, aucun moyen de paiement demandé. La conséquence est qu'il
-- doit naître avec la caserne, sinon `trial_ends_at` reste nul et la caserne
-- n'a **aucune** date de fin — ni côté écran, ni côté tâche de suspension.
--
-- 60 jours est écrit une seule fois, ici. Le jour où ce chiffre change, il
-- change pour les casernes créées ensuite ; les essais en cours gardent leur
-- date, ce qui est le comportement voulu — on ne raccourcit pas un essai déjà
-- promis.
create function subscription_bootstrap() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into subscriptions (station_id, status, trial_ends_at)
  values (new.id, 'trialing', now() + interval '60 days')
  on conflict (station_id) do nothing;
  return new;
end $$;

comment on function subscription_bootstrap() is
  'Déclencheur : toute caserne naît en essai de 60 jours, sans carte bancaire (docs/PRD.md § 6.6). on conflict do nothing : une ligne posée à la main reste telle quelle.';

revoke execute on function subscription_bootstrap() from public, anon, authenticated;

create trigger stations_subscription_bootstrap
  after insert on stations
  for each row execute function subscription_bootstrap();

-- Rattrapage des casernes déjà en base, y compris le seed. `trial_ends_at` est
-- compté depuis leur création et non depuis aujourd'hui : une caserne ouverte il
-- y a trois mois n'a pas droit à un second essai.
insert into subscriptions (station_id, status, trial_ends_at)
select s.id, 'trialing', s.created_at + interval '60 days'
from stations s
where not exists (select 1 from subscriptions a where a.station_id = s.id);

-- ===========================================================================
-- 2. `stripe_events` — ce qu'on a déjà traité, et ce qui a échoué
-- ===========================================================================
-- **La signature ne dit pas qu'un événement est neuf.** Elle dit qu'il vient
-- bien du prestataire. Un même événement authentique réémis dans la fenêtre de
-- cinq minutes — un rejeu manuel depuis le tableau de bord, une double livraison
-- réseau, un attaquant qui a capté la requête — repasserait la vérification et
-- serait appliqué une seconde fois. Sur `invoice.payment_failed`, cela ramène en
-- impayé une caserne qui vient de régulariser.
--
-- Cette table est donc **la** garantie de « une fois et une seule », et
-- l'identifiant du prestataire (`evt_…`) en est la clé primaire : c'est lui qui
-- porte l'unicité, pas nous.
--
-- Elle sert aussi de trace : les rejeux du prestataire s'arrêtent au bout de
-- trois jours, après quoi un événement dont le traitement a échoué ne laissait
-- qu'une ligne dans des journaux à rétention courte. `select * from stripe_events
-- where status = 'failed'` le montre, avec son motif et son compte de tentatives
-- — même rôle que `notification_outbox` pour les notifications.
create table stripe_events (
  id            text primary key,          -- `evt_…`, l'identifiant du prestataire
  type          text not null,             -- `invoice.paid`, …
  station_id    uuid references stations(id) on delete set null,
  status        text not null default 'processing',
  result        jsonb not null default '{}'::jsonb,
  error         text,
  attempts      integer not null default 1,
  received_at   timestamptz not null default now(),
  processed_at  timestamptz,
  constraint stripe_events_status_valide
    check (status in ('processing', 'processed', 'skipped', 'failed'))
);

create index on stripe_events (status, received_at desc) where status <> 'processed';

comment on table stripe_events is
  'Événements du prestataire de paiement déjà reçus. Clé primaire = l''identifiant du prestataire : c''est ce qui rend le traitement « une fois et une seule ». Les lignes status = ''failed'' survivent aux trois jours de rejeu et disent ce qui n''est jamais passé.';

alter table stripe_events enable row level security;

-- Aucune politique, et **aucun privilège client** : ni `anon` ni `authenticated`
-- n'en lisent une ligne. Seuls `service_role` et `postgres` y accèdent, et ils
-- ont `bypassrls`. Même traitement que `notification_outbox` (migration 0014) :
-- une table de plomberie n'a pas de politique à maintenir, elle a une porte
-- fermée. `rls_test.sql § 9` vérifie que les deux vont toujours ensemble.
revoke all on stripe_events from anon, authenticated;

-- Clôt une ligne de `stripe_events` sur un refus, et rend le refus.
--
-- Un refus **consomme** l'événement : une caserne inconnue ne le deviendra pas,
-- une formule inconnue non plus, et un client qui ne correspond pas à sa caserne
-- ne se corrigera pas tout seul. Les rejouer trois jours durant n'aboutirait à
-- rien ; la ligne `skipped` les garde visibles.
create function stripe_event_close(p_event_id text, p_station uuid, p_code text)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_event_id is not null then
    update stripe_events
       set station_id = p_station, status = 'skipped', error = p_code,
           processed_at = now()
     where id = p_event_id;
  end if;
  return jsonb_build_object('ok', false, 'code', p_code);
end $$;

comment on function stripe_event_close(text, uuid, text) is
  'Marque un événement comme écarté (caserne inconnue, formule inconnue, client incohérent) et rend le refus. Un refus consomme l''événement : le rejouer n''y changerait rien.';

revoke execute on function stripe_event_close(text, uuid, text) from public, anon, authenticated;

-- ===========================================================================
-- Trace d'un traitement qui a échoué
-- ===========================================================================
-- Appelée par l'Edge Function **après** que la transaction de `subscription_sync`
-- a été annulée : la ligne posée à l'intérieur est partie avec elle, et c'est
-- justement pour ça qu'il en faut une seconde, dans sa propre transaction.
--
-- Le prestataire rejouera — c'est ce qu'on veut, l'événement reste valable — et
-- la reprise est permise par le statut `failed`, seul cas que le dédoublonnage
-- de `subscription_sync` ne traite pas comme un rejeu. Au bout de trois jours,
-- il abandonne : il reste alors cette ligne, et elle est la seule.
create function stripe_event_fail(p_event_id text, p_type text, p_error text)
returns void
language sql security definer set search_path = public, pg_temp as $$
  insert into stripe_events (id, type, status, error, processed_at)
  values (p_event_id, coalesce(p_type, 'inconnu'), 'failed', left(p_error, 500), now())
  on conflict (id) do update
    set status       = 'failed',
        error        = excluded.error,
        attempts     = stripe_events.attempts + 1,
        processed_at = now();
$$;

comment on function stripe_event_fail(text, text, text) is
  'Trace durable d''un événement reçu et signé dont le traitement a échoué. Posée hors de la transaction annulée. « select * from stripe_events where status = ''failed'' » liste ce qui n''est jamais passé.';

revoke execute on function stripe_event_fail(text, text, text) from public, anon, authenticated;

-- ===========================================================================
-- 3. `subscription_sync` — le seul chemin d'écriture
-- ===========================================================================
-- Appelée par `stripe-webhook` (Edge Function, clé de service) **après**
-- vérification de la signature de l'événement. Elle ne vérifie donc pas la
-- signature : elle vérifie la cohérence des données, ce qui n'est pas la même
-- chose et se fait bien mieux en SQL.
--
-- Deux façons de désigner la caserne, dans cet ordre :
--   1. `p_station` — `checkout.session.completed` le porte en
--      `client_reference_id` : c'est nous qui l'avons mis, au moment d'ouvrir la
--      session de paiement ;
--   2. `p_customer` — les événements suivants (`invoice.*`,
--      `customer.subscription.*`) ne portent que l'identifiant du client chez le
--      prestataire, et c'est la colonne `stripe_customer_id` qui les ramène à
--      une caserne.
--
-- Une caserne introuvable n'est **pas** une erreur serveur : c'est un événement
-- qui ne nous concerne pas (un autre projet branché sur le même compte, un
-- client créé à la main dans le tableau de bord). La fonction rend
-- `station_not_found` et l'Edge Function répond 200 — sans quoi le prestataire
-- rejouerait indéfiniment un événement qui ne sera jamais traitable.
--
-- Les paramètres nuls **ne remplacent rien** : un `invoice.paid` qui ne porte
-- pas de formule ne doit pas effacer `plan`. C'est la raison des `coalesce`
-- ci-dessous, et c'est ce qui permet d'appliquer les quatre événements dans
-- n'importe quel ordre — le prestataire ne garantit pas l'ordre de livraison.
create function subscription_sync(
  p_station     uuid                default null,
  p_customer    text                default null,
  p_subscription text               default null,
  p_status      subscription_status default null,
  p_plan        text                default null,
  p_period_end  timestamptz         default null,
  p_event       text                default null,
  p_event_id    text                default null,
  p_reference   timestamptz         default now()
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_station uuid;
  v_avant   subscriptions%rowtype;
  v_apres   subscriptions%rowtype;
  v_etat    text;
  v_refus   jsonb;
begin
  -- 0. **Une fois et une seule.** L'identifiant du prestataire est la clé
  -- primaire de `stripe_events` : c'est l'insertion qui tranche, pas un test
  -- suivi d'une écriture — deux livraisons simultanées ne peuvent pas passer
  -- toutes les deux.
  if p_event_id is not null then
    insert into stripe_events (id, type, status)
    values (p_event_id, coalesce(p_event, 'inconnu'), 'processing')
    on conflict (id) do nothing;

    if not found then
      -- La ligne existait déjà. `for update` attend que la transaction qui la
      -- tient peut-être encore ait fini : sans cette attente, deux livraisons
      -- parallèles se croiseraient toutes deux en « rien de fait ».
      select status into v_etat from stripe_events where id = p_event_id for update;

      -- Un traitement **en échec** se reprend : c'est tout l'intérêt des rejeux
      -- du prestataire. Tout le reste est un rejeu, et ne s'applique pas.
      if v_etat is distinct from 'failed' then
        return jsonb_build_object(
          'ok', true, 'duplicate', true,
          'code', 'duplicate_event', 'event_id', p_event_id, 'state', v_etat);
      end if;

      update stripe_events
         set attempts = attempts + 1, status = 'processing', error = null
       where id = p_event_id;
    end if;
  end if;

  if p_plan is not null and p_plan not in ('monthly', 'yearly') then
    return stripe_event_close(p_event_id, null, 'invalid_plan');
  end if;

  -- 1. Retrouver la caserne : l'identifiant transmis, sinon le client.
  select s.station_id into v_station
  from subscriptions s
  where (p_station is not null and s.station_id = p_station)
     or (p_station is null and p_customer is not null
         and s.stripe_customer_id = p_customer)
  limit 1;

  -- Une caserne qui n'a pas encore de ligne d'abonnement : elle en reçoit une.
  -- Le cas se produit si le rattrapage ci-dessus n'a pas tourné (base restaurée
  -- d'un dump antérieur), jamais en fonctionnement normal.
  if v_station is null and p_station is not null
     and exists (select 1 from stations where id = p_station) then
    insert into subscriptions (station_id, status, trial_ends_at)
    values (p_station, 'trialing', p_reference + interval '60 days')
    on conflict (station_id) do nothing;
    v_station := p_station;
  end if;

  if v_station is null then
    return stripe_event_close(p_event_id, null, 'station_not_found');
  end if;

  -- 2. **Le client et la caserne doivent déjà aller ensemble.**
  --
  -- La signature dit que l'appel vient du prestataire. Elle ne dit rien de la
  -- caserne nommée : `client_reference_id` est un champ que l'on peut poser
  -- depuis une URL (un lien de paiement public l'accepte en paramètre). Sans ces
  -- deux contrôles, un événement qui nomme la caserne B avec le client de A fait
  -- basculer B en `active` **et lui recolle le client de A** — après quoi
  -- l'administrateur de B ouvre le portail de A : sa carte, ses factures, sa
  -- résiliation.
  --
  -- Les deux contrôles ne font pas double emploi : le premier couvre une caserne
  -- qui a déjà son client, le second un client déjà pris ailleurs.
  if p_customer is not null then
    if exists (select 1 from subscriptions
                where station_id = v_station
                  and stripe_customer_id is not null
                  and stripe_customer_id <> p_customer) then
      return stripe_event_close(p_event_id, v_station, 'customer_mismatch');
    end if;

    if exists (select 1 from subscriptions
                where stripe_customer_id = p_customer
                  and station_id <> v_station) then
      return stripe_event_close(p_event_id, v_station, 'customer_mismatch');
    end if;
  end if;

  -- 3. Verrou de ligne : deux événements livrés en parallèle par le prestataire
  -- ne doivent pas s'écraser à moitié. Le verrou sérialise, et le second lit
  -- l'état écrit par le premier.
  select * into v_avant from subscriptions where station_id = v_station for update;

  update subscriptions set
    stripe_customer_id     = coalesce(p_customer,     stripe_customer_id),
    stripe_subscription_id = coalesce(p_subscription, stripe_subscription_id),
    status                 = coalesce(p_status,       status),
    plan                   = coalesce(p_plan,         plan),
    current_period_end     = coalesce(p_period_end,   current_period_end),
    -- `suspended_at` est la date du passage en lecture seule, et rien d'autre.
    -- Un retour en `active` l'efface : la garder ferait lire « suspendue le
    -- 4 décembre » sur une caserne qui a repayé le 5.
    suspended_at = case
      when coalesce(p_status, v_avant.status) in ('suspended', 'cancelled')
        then coalesce(v_avant.suspended_at, p_reference)
      else null
    end
  where station_id = v_station
  returning * into v_apres;

  -- 4. Journal. `actor_id` reste nul : l'acteur est le prestataire, pas une
  -- personne de la caserne.
  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    v_station, null,
    'subscription.' || coalesce(p_event, 'sync'),
    'subscriptions', v_station,
    jsonb_strip_nulls(jsonb_build_object(
      'from',               v_avant.status,
      'to',                 v_apres.status,
      'plan',               v_apres.plan,
      'current_period_end', v_apres.current_period_end,
      'event_id',           p_event_id,
      -- L'identifiant d'abonnement est utile au diagnostic ; celui du client
      -- l'est aussi, et **aucun des deux n'est un secret** : ce sont des
      -- références opaques, sans pouvoir propre.
      'subscription',       v_apres.stripe_subscription_id))
  );

  v_refus := jsonb_build_object(
    'ok',                 true,
    'station_id',         v_station,
    'previous_status',    v_avant.status,
    'status',             v_apres.status,
    'plan',               v_apres.plan,
    'customer',           v_apres.stripe_customer_id,
    'subscription',       v_apres.stripe_subscription_id,
    'current_period_end', v_apres.current_period_end,
    'trial_ends_at',      v_apres.trial_ends_at,
    'suspended_at',       v_apres.suspended_at);

  if p_event_id is not null then
    update stripe_events
       set station_id = v_station, status = 'processed',
           result = v_refus, processed_at = p_reference, error = null
     where id = p_event_id;
  end if;

  return v_refus;
end $$;

comment on function subscription_sync(uuid, text, text, subscription_status, text, timestamptz, text, text, timestamptz) is
  'Applique un événement du prestataire de paiement à subscriptions (docs/SCHEMA.md § 2.13). Dédoublonné sur p_event_id via stripe_events : un rejeu ne s''applique pas deux fois, un échec se reprend. Caserne désignée par p_station (client_reference_id de la session) ou retrouvée par p_customer, et refusée (customer_mismatch) si les deux ne vont pas déjà ensemble. Les paramètres nuls ne remplacent rien : les cinq événements s''appliquent dans n''importe quel ordre. Journalise dans audit_log. Réservée au rôle de service : appelée par l''Edge Function stripe-webhook, signature déjà vérifiée.';

revoke execute on function subscription_sync(uuid, text, text, subscription_status, text, timestamptz, text, text, timestamptz)
  from public, anon, authenticated;


-- ===========================================================================
-- 4. `subscription_customer` — poser le client sans rien changer d'autre
-- ===========================================================================
-- `create-checkout` crée le client chez le prestataire avant d'ouvrir la
-- session de paiement, et doit le retenir : sans ça, chaque tentative de
-- souscription créerait un client de plus, et le portail de gestion n'en
-- retrouverait aucun. C'est `subscription_sync` avec un seul paramètre utile,
-- mais nommé pour ce qu'il fait — et il n'écrit **aucun** statut, parce qu'à ce
-- moment-là rien n'est payé.
create function subscription_set_customer(p_station uuid, p_customer text)
returns jsonb
language sql security definer set search_path = public, pg_temp as $$
  select subscription_sync(
    p_station  => p_station,
    p_customer => p_customer,
    p_event    => 'customer.created');
$$;

comment on function subscription_set_customer(uuid, text) is
  'Retient l''identifiant client du prestataire pour une caserne, sans toucher au statut : rien n''est encore payé. Réservée au rôle de service (Edge Function create-checkout).';

revoke execute on function subscription_set_customer(uuid, text) from public, anon, authenticated;

-- ===========================================================================
-- 6. `cron_suspend_subscriptions` — la tâche
-- ===========================================================================
-- Deux populations, une seule conséquence : `suspended`, donc lecture seule via
-- `station_writable()`. **Rien n'est supprimé** — c'est une promesse du produit
-- (docs/PRD.md § 6.6) et elle se tient ici, dans la seule fonction qui aurait pu
-- la trahir.
--
--   a. **Essai expiré sans abonnement.** `trialing`, `trial_ends_at` dépassé, et
--      aucun abonnement chez le prestataire. La condition sur
--      `stripe_subscription_id` n'est pas décorative : une caserne qui a payé
--      pendant son essai porte encore `trialing` jusqu'à ce que le webhook
--      arrive, et la suspendre entre-temps serait suspendre un client qui paie.
--
--   b. **Paiement en retard depuis plus de 14 jours.** `past_due`, et la fin de
--      la dernière période payée remonte à plus de quatorze jours. Le repli sur
--      `updated_at` ne sert qu'aux lignes sans `current_period_end` — un
--      `past_due` posé à la main, ou un abonnement dont le prestataire n'a
--      jamais transmis la période.
--
-- Idempotente : une caserne déjà `suspended` ne remplit plus aucune des deux
-- conditions, et un rejeu après redémarrage de l'ordonnanceur ne fait rien.
create function cron_suspend_subscriptions(p_reference timestamptz default now())
returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  ligne     record;
  suspendus integer := 0;
begin
  for ligne in
    select
      station_id,
      status,
      case
        when status = 'trialing' then 'trial_expired'
        else 'past_due_14_days'
      end as motif,
      trial_ends_at,
      current_period_end
    from subscriptions
    where
      -- a. essai expiré, aucun abonnement souscrit
      (status = 'trialing'
       and trial_ends_at is not null
       and trial_ends_at < p_reference
       and stripe_subscription_id is null)
      -- b. impayé depuis plus de quatorze jours
      or (status = 'past_due'
          and coalesce(current_period_end, updated_at) < p_reference - interval '14 days')
    order by station_id
    for update
  loop
    update subscriptions
       set status = 'suspended',
           suspended_at = coalesce(suspended_at, p_reference)
     where station_id = ligne.station_id;

    insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
    values (
      ligne.station_id, null, 'subscription.suspended', 'subscriptions', ligne.station_id,
      jsonb_strip_nulls(jsonb_build_object(
        'reason',             ligne.motif,
        'from',               ligne.status,
        'trial_ends_at',      ligne.trial_ends_at,
        'current_period_end', ligne.current_period_end,
        'reference',          p_reference))
    );

    suspendus := suspendus + 1;
  end loop;

  return suspendus;
end $$;

comment on function cron_suspend_subscriptions(timestamptz) is
  'Tâche suspend_subscriptions (docs/SCHEMA.md § 8) : passe en suspended les essais expirés sans abonnement et les past_due dont la dernière période payée remonte à plus de 14 jours. Rien n''est supprimé — la caserne passe en lecture seule via station_writable(). Idempotente. Renvoie le nombre de casernes suspendues.';

revoke execute on function cron_suspend_subscriptions(timestamptz) from public, anon, authenticated;

-- ===========================================================================
-- 7. La tâche planifiée (docs/SCHEMA.md § 8)
-- ===========================================================================
-- Même forme que 0012, 0014, 0016 et 0021 : `cron.schedule` est un upsert depuis
-- pg_cron 1.4, la commande est qualifiée et sans argument, et le garde-fou
-- `insufficient_privilege` évite qu'un projet hébergé où le schéma `cron`
-- appartient à `supabase_admin` fasse échouer tout le déploiement.
--
-- 03:30 : après `create_periods` (02:00 le 1er du mois) et hors des minutes
-- occupées par les tâches horaires (:00, :15, :45). Une fois par jour suffit —
-- l'écran d'abonnement affiche la date de fin d'essai, et un chef de centre qui
-- ouvre l'application le matin de l'expiration n'est pas encore suspendu. C'est
-- volontaire : quelques heures de grâce ne coûtent rien et évitent de suspendre
-- une caserne pendant la nuit où elle paie.
do $planif$
begin
  perform cron.schedule(
    'suspend_subscriptions', '30 3 * * *',
    $cmd$select public.cron_suspend_subscriptions();$cmd$);
exception
  when insufficient_privilege then
    raise notice 'pg_cron : droits insuffisants pour planifier suspend_subscriptions, à faire à la main.';
end $planif$;
