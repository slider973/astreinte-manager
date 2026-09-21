-- 0024 — Mode suspendu : l'état de la caserne lisible par tout membre, et les
-- deux courriels aux administrateurs (fin d'essai à J-7, suspension). Ticket 030.
-- Référence : docs/PRD.md § 6.6 et § 7.6, docs/SCHEMA.md § 1, 7 et 8,
-- docs/WORKFLOWS.md § 8, design/030-gating-suspension.md.
--
-- Ce qui existait déjà et n'est pas réécrit
-- -----------------------------------------
--   - `station_writable(uuid)` (0007) : **la** définition du droit d'écrire.
--     Cette migration ne la redéfinit pas, elle la donne à lire.
--   - `subscriptions` et sa politique `subscriptions_select_admin` (0006, 0007) :
--     la table reste réservée aux administrateurs. C'est justement le problème
--     que § 1 ci-dessous résout sans y toucher.
--   - `notify(...)` et `notification_outbox` (0014) : la file, la tentative
--     immédiate, la reprise et la clé de dédoublonnage. Les deux courriels de
--     ce ticket passent par là et **par rien d'autre** — aucune seconde voie
--     d'envoi n'est créée.
--   - `cron_suspend_subscriptions(timestamptz)` (0023) : ses deux populations et
--     son idempotence ne bougent pas. Elle gagne une ligne : mettre en file la
--     notification, dans la transaction qui suspend.
--
-- Ce que cette migration ajoute
-- -----------------------------
--   1. `station_access(uuid)` : les quatre faits d'abonnement dont l'interface a
--      besoin, rendus à **tout membre actif** — pas seulement aux admins.
--   2. Deux valeurs à `notification_type` : `subscription_trial_ending` et
--      `subscription_suspended`.
--   3. `cron_subscription_reminders(instant)` : le courriel de fin d'essai à J-7.
--   4. `cron_suspend_subscriptions(instant)` remplacée : même corps, plus la mise
--      en file du courriel de suspension.
--   5. La tâche `pg_cron` quotidienne du rappel, à 03:20 — avant la suspension
--      de 03:30, pour qu'une caserne ne reçoive jamais « il te reste 7 jours »
--      dans la minute où elle est suspendue.
--
-- Aucune colonne, aucune table. Les neuf colonnes de `subscriptions` suffisent,
-- et la clé de dédoublonnage de `notification_outbox` porte l'unicité des envois
-- — pas une colonne « rappel envoyé le », qui serait un second endroit où dire
-- la même chose (même raisonnement qu'en 0021).

-- ===========================================================================
-- 1. `station_access` — ce qu'un membre a le droit de savoir de l'abonnement
-- ===========================================================================
-- Le problème que cette fonction résout tient en une phrase : **un simple membre
-- ne peut pas lire `subscriptions`**, donc il ne peut pas savoir pourquoi sa
-- grille refuse ses cases. C'était le mystère du ticket ; le lever ne demande pas
-- d'ouvrir la table, il demande d'en rendre quatre faits.
--
-- Ce qui sort : `writable`, `status`, `trial_ends_at`, `suspended_at`.
-- Ce qui ne sort pas, et ne sortira pas : `stripe_customer_id`,
-- `stripe_subscription_id`, `plan`, `current_period_end`. Ce sont les affaires de
-- l'administrateur, elles vivent sur `/admin/abonnement` (ticket 029) et la
-- politique `subscriptions_select_admin` les y garde.
--
-- `writable` est **calculé par `station_writable()` elle-même**, jamais réécrit :
-- une seconde liste de statuts ici serait une seconde définition du droit
-- d'écrire, et les deux divergeraient au premier changement.
--
-- Une caserne sans ligne d'abonnement (base restaurée d'un dump antérieur au
-- 0023) rend `writable = true` et `status = null` : même repli que
-- `station_writable`, et l'interface n'annonce alors aucune suspension. Le
-- principe est constant de bout en bout — **on n'invente jamais une
-- suspension**, ni ici ni dans la PWA.
create function station_access(p_station uuid) returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when not is_member(p_station) then null
    else jsonb_build_object(
           'station_id', p_station,
           'writable',   station_writable(p_station))
         || coalesce(
              (select jsonb_build_object(
                        'status',        s.status,
                        'trial_ends_at', s.trial_ends_at,
                        'suspended_at',  s.suspended_at)
                 from subscriptions s
                where s.station_id = p_station),
              '{"status": null, "trial_ends_at": null, "suspended_at": null}'::jsonb)
  end;
$$;

comment on function station_access(uuid) is
  'Les quatre faits d''abonnement que l''interface doit connaître — writable, status, trial_ends_at, suspended_at — rendus à tout membre actif de la caserne (ticket 030). writable vient de station_writable() : une seule définition du droit d''écrire. Rien de ce qui touche au prestataire de paiement n''en sort ; ça reste réservé aux administrateurs (subscriptions_select_admin). Rend null à qui n''est pas membre.';

revoke execute on function station_access(uuid) from public, anon;
grant execute on function station_access(uuid) to authenticated;

-- ===========================================================================
-- 2. Deux types de notification
-- ===========================================================================
-- `alter type … add value` est permis dans une transaction depuis PostgreSQL 12,
-- à la seule condition de ne pas **utiliser** la valeur dans la même
-- transaction. Rien ici ne l'utilise : les corps de fonction sont du texte, et
-- l'appel réel a lieu quand la tâche tourne.
alter type notification_type add value if not exists 'subscription_trial_ending';
alter type notification_type add value if not exists 'subscription_suspended';

-- ===========================================================================
-- 3. `cron_subscription_reminders` — le courriel de fin d'essai
-- ===========================================================================
-- Une seule échéance côté serveur : **J-7**. Les rappels à J-14 et J-3 du ticket
-- sont des bannières, calculées par la PWA sur `trial_ends_at` ; les faire
-- partir en notification ferait trois courriels pour une caserne qui n'a rien
-- décidé, et le troisième arriverait la veille d'une suspension qu'un quatrième
-- message annonce déjà.
--
-- La fenêtre est **[J-7, J-7 + 1 jour[**, pas « à moins de 7 jours » : sans la
-- borne basse, la tâche redeviendrait due chaque jour jusqu'à l'expiration et
-- ne devrait son silence qu'à la clé de dédoublonnage. Une condition qui ne
-- tient que par un filet n'est pas une condition.
--
-- La clé porte `trial_ends_at` et non le jour du tir : un essai prolongé à la
-- main mérite un second rappel, une tâche rejouée après un redémarrage n'en
-- mérite pas.
--
-- `stripe_subscription_id is null` : une caserne qui a déjà souscrit pendant son
-- essai n'a aucune raison d'être relancée. C'est la même condition que la
-- population (a) de `cron_suspend_subscriptions`, et pour la même raison.
create function cron_subscription_reminders(p_reference timestamptz default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant timestamptz := coalesce(p_reference, now());
  ligne   record;
  admins  uuid[];
  cle     text;
  envoyes integer := 0;
begin
  for ligne in
    select s.station_id, s.trial_ends_at
    from subscriptions s
    where s.status = 'trialing'
      and s.trial_ends_at is not null
      and s.stripe_subscription_id is null
      and s.trial_ends_at >= instant + interval '6 days'
      and s.trial_ends_at <  instant + interval '7 days'
    order by s.station_id
  loop
    cle := format('subscription_trial_ending:%s:%s',
                  ligne.station_id, ligne.trial_ends_at::date);

    continue when exists (
      select 1 from notification_outbox
       where type = 'subscription_trial_ending' and dedupe_key = cle);

    select array_agg(m.user_id order by m.user_id)
      into admins
      from memberships m
     where m.station_id = ligne.station_id
       and m.role   = 'admin'
       and m.status = 'active';

    -- Un rappel sans destinataire ferait lever `notify_recipients_invalid` et
    -- arrêterait la tâche pour toutes les autres casernes. Même garde qu'en 0021.
    continue when admins is null or cardinality(admins) = 0;

    perform notify(
      'subscription_trial_ending',
      p_user_ids => admins,
      p_station  => ligne.station_id,
      p_payload  => jsonb_build_object(
                      'trial_ends_at', ligne.trial_ends_at,
                      'days_left',     7),
      -- Canaux explicites, contre l'habitude « push + inapp » des autres types :
      -- un abonnement ne se règle pas depuis l'écran verrouillé d'un téléphone,
      -- et le courriel est le seul canal qui atteigne un chef de centre qui n'a
      -- pas ouvert l'application depuis trois semaines — le cas nominal d'une
      -- fin d'essai.
      p_channels   => array['email', 'inapp'],
      p_dedupe_key => cle);

    envoyes := envoyes + 1;
  end loop;

  return envoyes;
end $$;

comment on function cron_subscription_reminders(timestamptz) is
  'Tâche subscription_reminders (docs/SCHEMA.md § 8) : courriel + notification interne aux administrateurs actifs quand l''essai se termine dans sept jours et qu''aucun abonnement n''a été souscrit. Dédoublonnée sur trial_ends_at, donc idempotente. Renvoie le nombre de casernes prévenues.';

revoke execute on function cron_subscription_reminders(timestamptz) from public, anon, authenticated;

-- ===========================================================================
-- 4. La suspension prévient les administrateurs
-- ===========================================================================
-- Même corps qu'en 0023 — les deux populations, le verrou de ligne, le journal,
-- l'idempotence — plus la mise en file du courriel, **dans la transaction qui
-- suspend**. C'est ce qui garantit que la notification et le fait qu'elle
-- annonce ne peuvent pas diverger : si l'`update` est annulé, la demande de
-- notification l'est avec lui.
--
-- La clé de dédoublonnage porte le jour de la suspension. Une caserne repassée
-- `active` puis re-suspendue plus tard reçoit un second message ; le même tir
-- rejoué après un redémarrage de l'ordonnanceur n'en envoie pas deux — et de
-- toute façon la boucle ne la sélectionne plus.
create or replace function cron_suspend_subscriptions(p_reference timestamptz default now())
returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  ligne     record;
  admins    uuid[];
  cle       text;
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

    -- Prévenir les administrateurs. Une caserne sans administrateur actif
    -- n'existe pas en pratique (`memberships_guard_admin`, 0010) ; si elle
    -- existait, la suspension doit tout de même avoir lieu, donc le défaut de
    -- destinataire saute la notification et **jamais** l'`update`.
    select array_agg(m.user_id order by m.user_id)
      into admins
      from memberships m
     where m.station_id = ligne.station_id
       and m.role   = 'admin'
       and m.status = 'active';

    if admins is not null and cardinality(admins) > 0 then
      cle := format('subscription_suspended:%s:%s',
                    ligne.station_id, p_reference::date);

      if not exists (
        select 1 from notification_outbox
         where type = 'subscription_suspended' and dedupe_key = cle)
      then
        perform notify(
          'subscription_suspended',
          p_user_ids => admins,
          p_station  => ligne.station_id,
          p_payload  => jsonb_build_object(
                          'reason',       ligne.motif,
                          'suspended_at', p_reference),
          p_channels   => array['email', 'inapp'],
          p_dedupe_key => cle);
      end if;
    end if;

    suspendus := suspendus + 1;
  end loop;

  return suspendus;
end $$;

comment on function cron_suspend_subscriptions(timestamptz) is
  'Tâche suspend_subscriptions (docs/SCHEMA.md § 8) : passe en suspended les essais expirés sans abonnement et les past_due dont la dernière période payée remonte à plus de 14 jours, et prévient les administrateurs par courriel (ticket 030). Rien n''est supprimé — la caserne passe en lecture seule via station_writable(). Idempotente. Renvoie le nombre de casernes suspendues.';

revoke execute on function cron_suspend_subscriptions(timestamptz) from public, anon, authenticated;

-- ===========================================================================
-- 5. La tâche planifiée (docs/SCHEMA.md § 8)
-- ===========================================================================
-- 03:20, soit **dix minutes avant** `suspend_subscriptions`. L'ordre compte : à
-- l'envers, une caserne dont l'essai expire aujourd'hui pourrait recevoir
-- « il te reste sept jours » juste après avoir été suspendue. Les deux
-- populations sont disjointes, mais l'ordre rend l'absurdité impossible plutôt
-- qu'improbable.
do $planif$
begin
  perform cron.schedule(
    'subscription_reminders', '20 3 * * *',
    $cmd$select public.cron_subscription_reminders();$cmd$);
exception
  when insufficient_privilege then
    raise notice 'pg_cron : droits insuffisants pour planifier subscription_reminders, à faire à la main.';
end $planif$;
