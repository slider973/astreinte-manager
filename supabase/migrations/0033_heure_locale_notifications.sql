-- 0033 — Envoyer les rappels à une heure décente dans chaque fuseau. Ticket 041,
-- relevé pendant le ticket 015.
-- Référence : docs/SCHEMA.md sections 2.1, 8 et 10.
--
-- Le problème
-- -----------
-- `availability_reminders` (0016) tire **une fois par jour à 09:00, heure du
-- serveur**. Le jour est juste partout — 0016 compte les jours dans le fuseau de
-- chaque caserne —, l'heure ne l'est nulle part ailleurs qu'en métropole :
--
--   | caserne              | fuseau  | heure locale du tir de 09:00 UTC |
--   |----------------------|---------|----------------------------------|
--   | Basse-Terre          | UTC-4   | 05:00                            |
--   | Papeete              | UTC-10  | 23:00 la veille                  |
--   | Mata-Utu (Wallis)    | UTC+12  | 21:00                            |
--
-- Un push à cinq heures du matin chez des pompiers volontaires n'est pas un
-- rappel, c'est un réveil. C'est le genre de détail qui fait désinstaller une
-- application, et qui coûte ensuite la saisie de tout un mois.
--
-- Ce que cette migration pose
-- ---------------------------
--   1. La clé `notification_hour` dans `stations.settings`, **facultative**,
--      bornée 6–20, ajoutée à la liste blanche de `station_settings_valid`
--      (0011, élargie en 0032). Absente : **9**.
--   2. `station_notification_hour(uuid)` : l'heure visée d'une caserne.
--   3. `station_notification_window(uuid, timestamptz)` : **le** mécanisme, un
--      seul pour toutes les tâches qui écrivent aux membres.
--   4. Les trois tâches qui écrivent aux membres passent dessous :
--      `cron_availability_reminders` (0016), `cron_assignment_reminders` et
--      `cron_late_responders_report` (0021).
--   5. La tâche `availability_reminders` devient **horaire**.
--
-- Pourquoi une clé facultative, et pourquoi c'est non négociable
-- --------------------------------------------------------------
-- Exactement la leçon du ticket 038 (0032). La contrainte
-- `stations_settings_valide` n'est pas revalidée par un `create or replace`,
-- mais elle est rejouée à **chaque écriture** d'une ligne `stations` : rendre la
-- clé obligatoire condamnerait toutes les casernes déjà écrites à ne plus jamais
-- pouvoir enregistrer un réglage. La règle vaut pour toute clé ajoutée après
-- coup, et docs/SCHEMA.md § 2.1 la porte désormais noir sur blanc.
--
-- L'écran des paramètres recompose le document entier à chaque enregistrement.
-- Il n'a pas à connaître cette clé — `ParametresCaserne.autresReglages`
-- (lib/features/parametres/domain/parametres_caserne.dart, ticket 038) garde et
-- réécrit **toute** clé qu'il ne montre pas —, mais il n'a surtout pas le droit
-- de l'effacer.
--
-- Une fenêtre, et non une égalité d'heure
-- ---------------------------------------
-- Le ticket dit « ne retenir que les casernes dont l'heure locale correspond à
-- l'heure visée ». Une égalité stricte aurait un trou : l'ordonnanceur qui
-- redémarre pendant l'heure en question fait perdre le rappel pour la journée
-- entière, et le J-3 d'un mois ne revient pas. La condition retenue est donc
--
--     heure visée <= heure locale <= 20
--
-- et c'est la **clé de dédoublonnage** qui fait le reste : la première heure
-- éligible envoie, les suivantes retombent sur la même clé et n'envoient rien.
-- Le comportement nominal est donc « à l'heure visée pile », et le comportement
-- dégradé est « au premier tir qui suit », jamais avant l'heure visée et jamais
-- après 21:00 locales. C'est vérifié tir par tir sur vingt-quatre heures par
-- `supabase/tests/heure_locale_notifications_test.sql § 3`.
--
-- La borne haute est une constante, pas un réglage : elle ne dit pas une
-- préférence de caserne mais une limite de politesse, « on n'écrit pas à
-- quelqu'un après neuf heures du soir ». Une caserne qui veut son rappel tard
-- règle `notification_hour` à 20 ; la fenêtre vaut alors la seule heure 20.
--
-- Les bornes 6–20 : avant 6, on réveille ; après 20, la fenêtre serait vide. Le
-- défaut 9 est celui que 0016 appliquait déjà (à Paris), et c'est l'heure où un
-- volontaire a consulté son téléphone sans avoir été dérangé pour cela.
--
-- Ce qui est unifié, et ce qui ne l'est pas
-- -----------------------------------------
-- **Unifié.** 0021 avait déjà posé une fenêtre horaire locale pour le rapport
-- aux administrateurs, en dur : `extract(hour …) between 8 and 20`. C'était le
-- bon geste au mauvais endroit — une règle de politesse écrite dans le corps
-- d'une tâche, donc vraie pour une tâche et fausse pour les deux autres. Elle
-- disparaît au profit de `station_notification_window`. Conséquence assumée :
-- par défaut le rapport part désormais à 09:00 locales et non à 08:00. Une
-- caserne matinale écrit `"notification_hour": 8` et retrouve exactement
-- l'ancien comportement — ce qu'elle ne pouvait pas faire avant.
--
-- **Étendu à `assignment_reminders`, contre la décision de 0021.** Le test du
-- ticket 022 affirmait : « les relances d'attribution restent horaires et sans
-- fenêtre : un push de rappel suit la proposition de quelques heures et n'a pas
-- d'heure de bureau. » L'argument ne tient pas à l'épreuve du fuseau : le palier
-- est `proposed_at + response_reminder_hours`, c'est-à-dire, par défaut, l'heure
-- de publication du planning **vingt-quatre heures plus tard**. Un planning
-- publié à 23:40 relance à 23:40 le lendemain ; un planning publié par un
-- administrateur métropolitain pour une caserne de Polynésie relance en pleine
-- nuit là-bas. Le retard introduit est au pire de quelques heures sur une
-- réponse attendue sous plusieurs jours ; le push nocturne, lui, est définitif.
-- L'escalier des paliers n'est pas touché : il compare toujours `proposed_at`
-- aux délais de la caserne, la fenêtre ne fait que différer le tir.
--
-- **Pas concerné : les tâches qui ne réveillent personne.** Vérifié une par une
-- sur docs/SCHEMA.md § 8 :
--
--   - `create_periods`, `lock_periods` (0012), `archive_schedules` (0031),
--     `prune_notifications`, `prune_retention` (0030) : aucune n'appelle
--     `notify`. Elles n'écrivent à personne et peuvent continuer de tourner la
--     nuit — c'est même leur meilleure heure, la base est au repos.
--   - `dispatch_notifications` (0014) : elle ne **décide** rien, elle repose ce
--     qui est déjà en file. Lui poser une fenêtre retarderait des messages dont
--     l'heure d'envoi a déjà été arbitrée par la tâche qui les a mis en file, et
--     retarderait aussi les notifications immédiates (une proposition d'astreinte
--     acceptée, une invitation) qui, elles, répondent à un geste humain en cours.
--     Elle reste à la minute.
--   - `subscription_reminders`, `suspend_subscriptions` (0023, 0024) : elles
--     écrivent aux administrateurs en `email` + `inapp`, **jamais en push**
--     (canaux explicites, commentés dans 0024 : « un abonnement ne se règle pas
--     depuis l'écran verrouillé d'un téléphone »). Un courriel n'a pas réveillé
--     son destinataire à 03:20 ; il est lu le matin. Et la notification de
--     suspension est mise en file **dans la transaction qui suspend** : la
--     différer, ce serait accepter qu'une caserne passe en lecture seule avant
--     que son chef de centre n'en soit prévenu.
--
-- Ce qui n'est **pas** fait
-- -------------------------
-- Aucune colonne, aucune table. L'heure visée est un réglage de caserne, elle vit
-- avec les autres dans `settings`. Aucun état « envoyé aujourd'hui » non plus :
-- la clé de dédoublonnage de `notification_outbox` (0014) le porte déjà, et c'est
-- ce que la section 3 du test vérifie sur vingt-quatre tirs consécutifs.

-- ===========================================================================
-- 1. L'heure visée dans les paramètres de la caserne
-- ===========================================================================
-- `station_settings_valid` est la liste blanche de 0011 : une clé absente de la
-- liste est refusée à l'écriture. La fonction est réécrite **à l'identique** sauf
-- trois endroits — la clé dans `connues` (et surtout **pas** dans
-- `obligatoires`), ses bornes, et le commentaire.
create or replace function station_settings_valid(p_settings jsonb) returns boolean
language plpgsql immutable
set search_path = public, pg_temp
as $$
declare
  connues constant text[] := array[
    'day_start', 'day_end',
    'required_day', 'required_night', 'required_overrides',
    'availability_deadline_day',
    'response_reminder_hours', 'response_email_hours', 'late_report_hours',
    'invitation_hourly_limit',
    'notification_hour'
  ];
  -- Ni `invitation_hourly_limit` (0032) ni `notification_hour` ne sont
  -- obligatoires : les casernes écrites avant ces migrations ne les portent pas,
  -- et la contrainte est rejouée à leur première mise à jour. Absentes, ce sont
  -- les défauts de `station_invitation_hourly_limit` et de
  -- `station_notification_hour` qui s'appliquent.
  obligatoires constant text[] := array[
    'day_start', 'day_end',
    'required_day', 'required_night',
    'availability_deadline_day',
    'response_reminder_hours', 'response_email_hours', 'late_report_hours'
  ];
  effectif_max constant integer := 50;
  jour_limite_max constant integer := 28;
  delai_max constant integer := 336;
  invitations_max constant integer := 500;
  -- 6 : avant, on réveille. 20 : au-delà, la fenêtre d'envoi serait vide, sa
  -- borne haute étant 20 (voir station_notification_window).
  heure_min constant integer := 6;
  heure_max constant integer := 20;
  cle text;
  surcharge jsonb;
  sous_cle text;
begin
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    return false;
  end if;

  for cle in select jsonb_object_keys(p_settings) loop
    if not (cle = any (connues)) then return false; end if;
  end loop;

  foreach cle in array obligatoires loop
    if not (p_settings ? cle) then return false; end if;
  end loop;

  if not station_settings_heure_valide(p_settings -> 'day_start')
     or not station_settings_heure_valide(p_settings -> 'day_end') then
    return false;
  end if;

  if (p_settings ->> 'day_start') = (p_settings ->> 'day_end') then
    return false;
  end if;

  if not station_settings_entier_valide(p_settings -> 'required_day', 0, effectif_max)
     or not station_settings_entier_valide(p_settings -> 'required_night', 0, effectif_max) then
    return false;
  end if;

  if not station_settings_entier_valide(
       p_settings -> 'availability_deadline_day', 1, jour_limite_max) then
    return false;
  end if;

  if not station_settings_entier_valide(p_settings -> 'response_reminder_hours', 1, delai_max)
     or not station_settings_entier_valide(p_settings -> 'response_email_hours', 1, delai_max)
     or not station_settings_entier_valide(p_settings -> 'late_report_hours', 1, delai_max) then
    return false;
  end if;

  if p_settings ? 'invitation_hourly_limit'
     and not station_settings_entier_valide(
           p_settings -> 'invitation_hourly_limit', 1, invitations_max) then
    return false;
  end if;

  -- L'heure visée est un **entier d'horloge**, pas une chaîne « HH:MM » : la
  -- fenêtre porte sur l'heure et jamais sur la minute, ce qui couvre sans cas
  -- particulier les fuseaux à la demi-heure (Marquises UTC-09:30) et au quart
  -- d'heure (Chatham UTC+12:45). Écrire « 09:30 » laisserait croire à une
  -- précision que la tâche horaire n'a pas.
  if p_settings ? 'notification_hour'
     and not station_settings_entier_valide(
           p_settings -> 'notification_hour', heure_min, heure_max) then
    return false;
  end if;

  if p_settings ? 'required_overrides' then
    if jsonb_typeof(p_settings -> 'required_overrides') <> 'object' then
      return false;
    end if;

    for cle, surcharge in
      select * from jsonb_each(p_settings -> 'required_overrides')
    loop
      if not station_settings_cle_surcharge_valide(cle) then return false; end if;
      if jsonb_typeof(surcharge) <> 'object' then return false; end if;

      if surcharge = '{}'::jsonb then return false; end if;

      for sous_cle in select jsonb_object_keys(surcharge) loop
        if sous_cle not in ('day', 'night') then return false; end if;
        if not station_settings_entier_valide(
             surcharge -> sous_cle, 0, effectif_max) then
          return false;
        end if;
      end loop;
    end loop;
  end if;

  return true;
end $$;

comment on function station_settings_valid(jsonb) is
  'Valide le document stations.settings (docs/SCHEMA.md § 2.1). Support de la contrainte stations_settings_valide et miroir exact de la validation côté application. invitation_hourly_limit (ticket 038) et notification_hour (ticket 041) sont facultatives : les casernes écrites avant 0032 et 0033 restent valides.';

-- L'heure visée effective. 9 par défaut : c'est l'heure que 0016 appliquait
-- déjà, mais à Paris seulement.
create function station_notification_hour(p_station uuid) returns integer
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select nullif(s.settings ->> 'notification_hour', '')::integer
       from stations s where s.id = p_station),
    9);
$$;

comment on function station_notification_hour(uuid) is
  'Heure locale visée pour les notifications d''une caserne : settings.notification_hour, ou 9 quand la clé est absente (docs/SCHEMA.md § 2.1, ticket 041).';

revoke execute on function station_notification_hour(uuid) from public, anon, authenticated;

-- ===========================================================================
-- 2. La fenêtre d'envoi : un seul mécanisme pour toutes les tâches
-- ===========================================================================
-- Vrai quand il est, chez cette caserne, une heure décente pour lui écrire.
--
-- `extract(hour …)` et non une comparaison de `time` : la fenêtre porte sur
-- l'heure pleine. Un fuseau à la demi-heure tombe donc naturellement dans la
-- bonne heure locale, sans que personne ait à y penser.
--
-- Une caserne dont le fuseau aurait disparu de `pg_timezone_names` ferait lever
-- `invalid_parameter_value` ici et arrêterait la tâche pour toutes les autres.
-- Le cas est fermé en amont par le déclencheur `stations_check_timezone` (0011) ;
-- c'est la raison d'être de ce déclencheur, et elle vaut ici une deuxième fois.
create function station_notification_window(
  p_station uuid,
  p_instant timestamptz default null
) returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select extract(hour from coalesce(p_instant, now()) at time zone s.timezone)::int
           between station_notification_hour(p_station) and 20
    from stations s
   where s.id = p_station;
$$;

comment on function station_notification_window(uuid, timestamptz) is
  'Vrai quand l''heure locale de la caserne est dans sa fenêtre d''envoi : de settings.notification_hour (9 par défaut) à 20 incluse, donc jamais avant l''heure visée et jamais après 21:00 locales. Mécanisme unique des tâches qui écrivent aux membres — availability_reminders, assignment_reminders, late_responders_report (docs/SCHEMA.md § 8, ticket 041). La clé de dédoublonnage de notification_outbox fait qu''un seul tir de la fenêtre envoie réellement.';

revoke execute on function station_notification_window(uuid, timestamptz)
  from public, anon, authenticated;

-- ===========================================================================
-- 3. Les rappels de saisie : horaires, et à l'heure locale visée
-- ===========================================================================
-- Corps de 0016 à l'identique, plus une ligne dans le `where`. Tout le reste —
-- le comptage des jours dans le fuseau de la caserne, « a saisi » = au moins une
-- ligne sur le mois, la période ouverte, la caserne écrivable, la clé de
-- dédoublonnage par caserne / mois / échéance / membre — est déjà juste et
-- n'avait pas à bouger : 0016 s'était trompé d'heure, pas de jour.
create or replace function cron_availability_reminders(p_reference timestamptz default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant timestamptz := coalesce(p_reference, now());
  rappel  record;
  envoyes integer := 0;
begin
  for rappel in
    select
      p.station_id,
      m.user_id,
      e.echeance,
      e.periode,
      e.cle,
      to_char(p.deadline_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as limite_iso
    from periods p
    join stations s on s.id = p.station_id
    cross join lateral (
      select (p.deadline_at at time zone s.timezone)::date
               - (instant at time zone s.timezone)::date as jours
    ) d
    join memberships m
      on m.station_id = p.station_id
     and m.status = 'active'
    cross join lateral (
      select
        case d.jours when 3 then 'j-3' else 'j-1' end     as echeance,
        to_char(make_date(p.year, p.month, 1), 'YYYY-MM') as periode
    ) c
    cross join lateral (
      select c.echeance,
             c.periode,
             format('availability_reminder:%s:%s:%s:%s',
                    p.station_id, c.periode, c.echeance, m.user_id) as cle
    ) e
    where p.status = 'open'
      and d.jours in (1, 3)
      -- Ticket 041 : la tâche tire toutes les heures, chaque caserne n'est
      -- servie que dans sa fenêtre locale. La journée locale est déjà la bonne
      -- unité de `d.jours` : la fenêtre se referme donc forcément avant que
      -- l'échéance ne change.
      and station_notification_window(p.station_id, instant)
      and station_writable(p.station_id)
      and not exists (
        select 1
          from availabilities a
         where a.user_id    = m.user_id
           and a.station_id = p.station_id
           and a.date >= make_date(p.year, p.month, 1)
           and a.date <  (make_date(p.year, p.month, 1) + interval '1 month')::date
      )
      and not exists (
        select 1
          from notification_outbox o
         where o.type = 'availability_reminder'
           and o.dedupe_key = e.cle
      )
    order by p.station_id, p.year, p.month, m.user_id
  loop
    perform notify(
      'availability_reminder',
      p_user_ids   => array[rappel.user_id],
      p_station    => rappel.station_id,
      p_payload    => jsonb_build_object(
                        'period',      rappel.periode,
                        'deadline_at', rappel.limite_iso),
      p_channels   => case rappel.echeance
                        when 'j-3' then array['push', 'inapp']
                        else            array['email', 'inapp']
                      end,
      p_dedupe_key => rappel.cle
    );
    envoyes := envoyes + 1;
  end loop;

  return envoyes;
end $$;

comment on function cron_availability_reminders(timestamptz) is
  'Tâche availability_reminders (docs/SCHEMA.md § 8) : push à J-3, courriel à J-1, aux membres actifs sans aucune ligne availabilities sur le mois d''une période ouverte. Jours comptés dans le fuseau de la caserne, envoi dans sa fenêtre horaire locale (station_notification_window, ticket 041). Un seul envoi par membre et par échéance, garanti par la clé de dédoublonnage de notification_outbox. Renvoie le nombre de rappels mis en file.';

-- La tâche passe de quotidienne à horaire. `cron.schedule` est un upsert depuis
-- pg_cron 1.4 : le même nom de tâche est réécrit, il n'y a rien à dé-planifier.
--
-- Minute 30 : `lock_periods` est à :00, `assignment_reminders` à :15,
-- `late_responders_report` à :45. Quatre tâches horaires qui démarrent à la même
-- seconde verrouilleraient les mêmes lignes de `notification_outbox` pour rien.
do $planif$
begin
  perform cron.schedule(
    'availability_reminders', '30 * * * *',
    $cmd$select public.cron_availability_reminders();$cmd$);
exception
  when insufficient_privilege then
    raise notice 'pg_cron : droits insuffisants pour replanifier availability_reminders, à faire à la main.';
end $planif$;

-- ===========================================================================
-- 4. Les relances d'attribution passent sous la même fenêtre
-- ===========================================================================
-- Corps de 0021 à l'identique, plus une ligne dans le `where` de la boucle des
-- plannings. Volontairement placée là et non dans `assignment_reminder_targets` :
-- cette fonction-là répond à « qui est dû », une question qui ne dépend pas de
-- l'heure qu'il est, et elle est lue par les tests comme la définition du palier.
-- Mélanger « dû » et « envoyable maintenant » rendrait le palier intestable et
-- ferait mentir son nom.
--
-- Rien d'autre ne bouge : ni l'ordre courriel-puis-push, ni la clé de
-- dédoublonnage indexée sur l'heure UTC du tir, ni le constat-avant-la-marque.
create or replace function cron_assignment_reminders(p_reference timestamptz default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant       timestamptz := coalesce(p_reference, now());
  fenetre       text := to_char(instant at time zone 'UTC', 'YYYY-MM-DD"T"HH24');
  palier        text;
  lot           record;
  cibles        uuid[];
  destinataires jsonb;
  cle           text;
  envoyes       integer := 0;
begin
  foreach palier in array array['email', 'push'] loop
    for lot in
      select
        sc.id         as schedule_id,
        sc.station_id as station_id,
        to_char(make_date(pe.year, pe.month, 1), 'YYYY-MM') as periode
      from schedules sc
      join periods pe on pe.id = sc.period_id
      where sc.status = 'published'
        and station_writable(sc.station_id)
        -- Ticket 041. Le palier reste calculé sur `proposed_at` et les délais de
        -- la caserne ; la fenêtre ne fait que différer le tir jusqu'à une heure
        -- où l'on peut écrire à quelqu'un.
        and station_notification_window(sc.station_id, instant)
      order by sc.station_id, sc.id
    loop
      cibles := assignment_reminder_targets(lot.schedule_id, palier, instant);
      continue when cibles is null or cardinality(cibles) = 0;

      cle := format('assignment_reminder:auto:%s:%s:%s', palier, lot.schedule_id, fenetre);

      continue when exists (
        select 1 from notification_outbox
         where type = 'assignment_reminder' and dedupe_key = cle);

      select coalesce(jsonb_agg(g.entree order by g.user_id), '[]'::jsonb)
        into destinataires
        from (
          select
            a.user_id,
            jsonb_build_object(
              'user_id', a.user_id,
              'payload', jsonb_build_object(
                'shifts', jsonb_agg(
                  jsonb_build_object('date', sh.date, 'slot', sh.slot)
                  order by sh.date, sh.slot))
            ) as entree
          from assignments a
          join shifts sh on sh.id = a.shift_id and sh.station_id = a.station_id
          where a.id = any(cibles)
          group by a.user_id
        ) g;

      perform notify(
        'assignment_reminder',
        p_station    => lot.station_id,
        p_payload    => jsonb_build_object('period', lot.periode),
        p_channels   => case palier
                          when 'push' then array['push', 'inapp']
                          else             array['email', 'inapp']
                        end,
        p_recipients => destinataires,
        p_dedupe_key => cle);

      update assignments a
         set reminder_count   = a.reminder_count + 1,
             last_reminder_at = instant
       where a.id = any(cibles);

      envoyes := envoyes + jsonb_array_length(destinataires);
    end loop;
  end loop;

  return envoyes;
end $$;

comment on function cron_assignment_reminders(timestamptz) is
  'Tâche assignment_reminders (docs/SCHEMA.md § 8) : push à response_reminder_hours puis courriel à response_email_hours aux membres actifs dont l''attribution est restée sans réponse. Une notification par membre, groupée. N''envoie que dans la fenêtre horaire locale de la caserne (station_notification_window, ticket 041). reminder_count et last_reminder_at ne sont marqués que lorsqu''un envoi part réellement. Renvoie le nombre de notifications mises en file.';

-- ===========================================================================
-- 5. Le rapport aux administrateurs : même fenêtre, plus de constante en dur
-- ===========================================================================
-- Corps de 0021 à l'identique, sauf `extract(hour from instant at time zone
-- st.timezone) between 8 and 20`, remplacé par l'appel à la fenêtre commune.
-- C'est le point 3 du ticket 041 : deux mécanismes qui disent la même chose de
-- deux façons différentes finissent par diverger, et c'est toujours celui qu'on
-- a oublié qui envoie le push de trois heures du matin.
create or replace function cron_late_responders_report(p_reference timestamptz default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant    timestamptz := coalesce(p_reference, now());
  lot        record;
  en_attente integer;
  noms       jsonb;
  admins     uuid[];
  cle        text;
  envoyes    integer := 0;
begin
  for lot in
    select
      sc.id         as schedule_id,
      sc.station_id as station_id,
      to_char(make_date(pe.year, pe.month, 1), 'YYYY-MM') as periode,
      coalesce((st.settings ->> 'late_report_hours')::int, 72) as heures,
      (instant at time zone st.timezone)::date as jour_local
    from schedules sc
    join periods pe  on pe.id = sc.period_id
    join stations st on st.id = sc.station_id
    where sc.status = 'published'
      and station_writable(sc.station_id)
      -- Jamais au milieu de la nuit locale. La clé de dédoublonnage porte la
      -- date locale : la fenêtre s'ouvre et se referme à l'intérieur d'une même
      -- journée locale, le rapport part donc une fois, au premier tir éligible.
      and station_notification_window(sc.station_id, instant)
    order by sc.station_id, sc.id
  loop
    select
      count(*)::int,
      coalesce(jsonb_agg(distinct q.nom), '[]'::jsonb)
      into en_attente, noms
      from (
        select
          coalesce(
            nullif(btrim(m.display_name), ''),
            nullif(btrim(pr.first_name || ' ' || pr.last_name), ''),
            pr.email,
            'Un membre') as nom
        from assignments a
        join shifts sh on sh.id = a.shift_id and sh.station_id = a.station_id
        left join memberships m
          on m.station_id = a.station_id and m.user_id = a.user_id
        left join profiles pr on pr.id = a.user_id
        where sh.schedule_id = lot.schedule_id
          and a.station_id   = lot.station_id
          and a.status       = 'proposed'
          and a.proposed_at is not null
          and a.proposed_at < instant - make_interval(hours => lot.heures)
      ) q;

    continue when coalesce(en_attente, 0) = 0;

    cle := format('late_responders:%s:%s', lot.schedule_id, lot.jour_local);

    continue when exists (
      select 1 from notification_outbox
       where type = 'late_responders' and dedupe_key = cle);

    select array_agg(m.user_id order by m.user_id)
      into admins
      from memberships m
     where m.station_id = lot.station_id
       and m.role   = 'admin'
       and m.status = 'active';

    continue when admins is null or cardinality(admins) = 0;

    perform notify(
      'late_responders',
      p_user_ids => admins,
      p_station  => lot.station_id,
      p_payload  => jsonb_build_object(
                      'period',        lot.periode,
                      'schedule_id',   lot.schedule_id,
                      'pending_count', en_attente,
                      'hours',         lot.heures,
                      'members',       noms),
      p_dedupe_key => cle);

    envoyes := envoyes + 1;
  end loop;

  return envoyes;
end $$;

comment on function cron_late_responders_report(timestamptz) is
  'Tâche late_responders_report (docs/SCHEMA.md § 8) : prévient les administrateurs des attributions sans réponse depuis late_report_hours, une fois par jour et par planning (clé de dédoublonnage datée dans le fuseau de la caserne), dans la fenêtre horaire locale de la caserne (station_notification_window, ticket 041 : de settings.notification_hour à 20:59). Même définition du retard que v_schedule_progress.assignments_late et remind_schedule. Renvoie le nombre de rapports mis en file.';
