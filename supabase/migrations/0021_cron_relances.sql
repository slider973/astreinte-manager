-- 0021 — Relances automatiques des attributions sans réponse et rapport des
-- retardataires aux administrateurs. Ticket 022.
-- Référence : docs/WORKFLOWS.md sections 3, 6 et 8 ; docs/SCHEMA.md sections 3 et 8.
--
-- Ce qui existait déjà et n'est pas réécrit
-- -----------------------------------------
--   - `notify(...)` et `notification_outbox` (0014, ticket 025) : la file, la
--     tentative immédiate, la reprise, et la **clé de dédoublonnage**
--     (`notification_outbox_dedupe_uniq`). Le commentaire de la colonne
--     `dedupe_key` annonçait déjà « un rapport par jour et par planning (022) » :
--     c'est cette migration qui vient le tenir, et elle le tient avec la clé,
--     pas avec une colonne d'état de plus.
--   - `v_schedule_progress.assignments_late` (0018) : **la** définition du retard
--     dans ce produit — `proposed`, `proposed_at` non nul, plus vieux que
--     `settings.late_report_hours`. `remind_schedule` (0019) la reprend mot pour
--     mot pour la relance manuelle, `cron_late_responders_report` la reprend ici.
--     Trois lecteurs, une seule règle ; l'égalité des trois est vérifiée par
--     `supabase/tests/assignment_reminders_test.sql § 7`.
--   - `remind_schedule` (0019) : le bouton « Relancer maintenant ». Elle
--     incrémente `reminder_count` et pose `last_reminder_at` **seulement quand un
--     envoi part réellement** ; les deux tâches ci-dessous font pareil, et c'est
--     ce qui permet aux deux gestes de cohabiter (voir « Cohabitation » plus bas).
--   - `station_writable(uuid)` (0007) : une caserne suspendue est en lecture
--     seule, on ne relance personne chez elle.
--
-- Ce que cette migration ajoute
-- -----------------------------
--   1. `assignment_reminder_targets(planning, palier, instant)` : qui est dû, à
--      quel palier, à quel instant. Une fonction, une règle, deux appelants
--      (la tâche et les tests).
--   2. `cron_assignment_reminders(instant)`, corps de la tâche
--      `assignment_reminders` de docs/SCHEMA.md § 8 : push au premier délai,
--      courriel au second.
--   3. `cron_late_responders_report(instant)`, corps de la tâche
--      `late_responders_report` : le rapport aux administrateurs au troisième
--      délai, **une fois par jour et par planning**.
--   4. Les deux tâches `pg_cron`, horaires.
--
-- Tout est paramétré par un instant de référence, comme 0012, 0014 et 0016 :
-- c'est la seule façon de vérifier en quelques millisecondes un comportement
-- dont la période est la journée. L'ordonnanceur appelle toujours sans argument.
--
-- Les trois délais viennent des `settings` de **chaque caserne**
-- (`response_reminder_hours`, `response_email_hours`, `late_report_hours`,
-- posés au ticket 010) : aucune constante d'heures n'est écrite ici. Les
-- `coalesce` sur les valeurs par défaut de docs/SCHEMA.md § 2.1 (24, 48, 72) ne
-- servent que pour un document amputé, que la contrainte
-- `stations_settings_valide` interdit déjà.
--
-- Cohabitation avec la relance manuelle (question posée par la revue du 019)
-- --------------------------------------------------------------------------
-- `remind_schedule` incrémente le **même** compteur que ces tâches. Le
-- comportement voulu, décidé ici et documenté dans docs/SCHEMA.md § 3 :
--
--   - **Une relance manuelle tient lieu de premier palier.** Le palier push est
--     conditionné à `reminder_count = 0` : un pompier relancé à la main à T+10 h
--     ne reçoit pas un second push à T+24 h. C'est exactement ce que le
--     commentaire de `remind_schedule` annonçait (« les crons du ticket 022
--     sautent le push de 24 h quand `reminder_count` vaut déjà 1 »), et c'est le
--     bon geste : deux poussées à quatorze heures d'écart pour la même garde,
--     c'est du harcèlement, pas une relance.
--
--   - **Aucune relance manuelle ne fait sauter le palier courriel.** Il aurait
--     été tentant de l'écrire `reminder_count = 1` tout court, en miroir du
--     diagramme de docs/WORKFLOWS.md § 6. Deux clics de l'administrateur à deux
--     heures différentes amènent le compteur à 2, et le pompier n'aurait alors
--     **jamais** reçu le courriel — celui-là même qui atteint qui a coupé ses
--     push (`TYPES_CRITIQUES`,
--     `supabase/functions/_shared/notification_content.ts` : le rappel de
--     réponse est désactivable *parce qu'*il repart en courriel). La condition
--     s'écrit donc en deux branches :
--
--         reminder_count >= 1
--         and proposed_at + response_email_hours <= instant
--         and (reminder_count = 1
--              or last_reminder_at < proposed_at + response_email_hours)
--
--     La première branche est l'escalier nominal : une relance est partie —
--     palier push ou clic d'administrateur, peu importe —, le courriel suit.
--     La seconde est le filet : plusieurs relances sont parties, mais **aucune
--     depuis l'échéance du courriel**, donc il reste dû. Ensemble, elles
--     arrêtent la boucle — une fois le courriel parti, le compteur vaut au moins
--     2 et `last_reminder_at` est postérieur à l'échéance — sans jamais priver
--     du courriel un pompier dont l'administrateur a cliqué deux fois.
--
--     Écrire seulement la seconde branche ne suffisait pas, et c'est le test de
--     reprise après panne qui l'a montré : ordonnanceur arrêté trois jours, le
--     push part à T+120 h, `last_reminder_at` dépasse alors l'échéance du
--     courriel et celui-ci n'aurait plus jamais eu lieu. C'est précisément le
--     cas où il compte le plus.
--
--   - **Le palier courriel passe avant le palier push dans un même tir.** Les
--     deux ensembles sont disjoints à l'instant de la lecture (`= 0` contre
--     `>= 1`), mais le push marque les lignes qu'il traite : le faire d'abord
--     ferait entrer ses propres lignes dans le palier courriel du même tir
--     lorsqu'une reprise après panne franchit les deux délais d'un coup, et le
--     pompier recevrait push et courriel dans la même minute. Courriel d'abord,
--     et l'escalier reste un escalier — une marche par heure.
--
-- Ce qui n'est **pas** fait, volontairement
-- -----------------------------------------
-- Aucune colonne n'est ajoutée à `assignments`. `reminder_count` et
-- `last_reminder_at` (0004) suffisent à porter les paliers, et la clé de
-- dédoublonnage porte l'unicité des envois. Une colonne « rapport envoyé le » sur
-- `schedules` aurait été un troisième endroit où dire la même chose, avec la
-- dérive que cela suppose.

-- ===========================================================================
-- 1. Qui est dû, et à quel palier
-- ===========================================================================
-- Une attribution est relançable quand **elle n'a pas reçu de réponse** :
-- `status = 'proposed'`. C'est le critère d'acceptation du ticket — « un membre
-- qui a répondu ne reçoit plus rien » — et il est porté par cette seule clause,
-- pas par une liste de cas. Accepté, refusé, remplacé, annulé : quatre statuts
-- terminaux, aucun ne franchit ce filtre.
--
-- `proposed_at is not null` écarte le brouillon : docs/WORKFLOWS.md § 3 dit que
-- rien n'est en retard tant que rien n'a été proposé, et un planning repassé de
-- `validated` à `published` ne réveille pas des attributions jamais envoyées.
--
-- Le planning doit être `published`. Un brouillon n'a rien annoncé à personne ;
-- un planning `validated` a l'effectif qu'il lui faut, et relancer sur un
-- surnombre déjà couvert ferait courir un pompier pour rien. C'est aussi ce que
-- répond `remind_schedule` (`schedule_not_published`) : le bouton et la tâche
-- voient le même monde.
--
-- L'appartenance doit être **active**. Une proposition laissée à un membre
-- désactivé n'a plus de destinataire ; elle reste comptée dans le rapport aux
-- administrateurs (§ 3), qui est justement l'endroit où ce trou doit se voir.
create function assignment_reminder_targets(
  p_schedule uuid,
  p_palier   text,
  p_instant  timestamptz default null
) returns uuid[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with cadre as (
    select
      sc.id         as schedule_id,
      sc.station_id as station_id,
      st.settings   as settings,
      coalesce(p_instant, now()) as instant
    from schedules sc
    join stations st on st.id = sc.station_id
    where sc.id = p_schedule
      and sc.status = 'published'
      and station_writable(sc.station_id)
  ),
  delais as (
    select
      c.*,
      make_interval(hours => coalesce((c.settings ->> 'response_reminder_hours')::int, 24)) as push,
      make_interval(hours => coalesce((c.settings ->> 'response_email_hours')::int, 48))    as email
    from cadre c
  )
  select array_agg(a.id order by a.id)
  from delais d
  join shifts sh
    on sh.schedule_id = d.schedule_id
   and sh.station_id  = d.station_id
  join assignments a
    on a.shift_id   = sh.id
   and a.station_id = sh.station_id
  join memberships m
    on m.station_id = a.station_id
   and m.user_id    = a.user_id
   and m.status     = 'active'
  where a.status = 'proposed'
    and a.proposed_at is not null
    and case p_palier
          when 'push' then
            a.reminder_count = 0
            and a.proposed_at + d.push <= d.instant
          when 'email' then
            a.reminder_count >= 1
            and a.proposed_at + d.email <= d.instant
            and (
              -- L'escalier nominal : une relance est partie, le courriel suit.
              a.reminder_count = 1
              -- Le filet : plusieurs relances, aucune depuis l'échéance.
              or coalesce(a.last_reminder_at, '-infinity'::timestamptz)
                   < a.proposed_at + d.email
            )
          else false
        end;
$$;

comment on function assignment_reminder_targets(uuid, text, timestamptz) is
  'Attributions d''un planning publié dues au palier « push » (response_reminder_hours, jamais relancées) ou « email » (response_email_hours, relancées une fois, ou plusieurs mais pas depuis cette échéance). Délais lus dans les settings de la caserne. NULL quand personne n''est dû.';

revoke execute on function assignment_reminder_targets(uuid, text, timestamptz)
  from public, anon, authenticated;

-- ===========================================================================
-- 2. La tâche assignment_reminders
-- ===========================================================================
-- docs/WORKFLOWS.md § 6 : push au premier délai, courriel au second.
-- docs/WORKFLOWS.md § 8 : regroupement « par membre » — un pompier qui traîne
-- sur quatre gardes reçoit une notification qui les liste, pas quatre.
--
-- Un envoi par planning et par palier, avec ses destinataires déjà groupés :
-- même forme que `publish_schedule` et `remind_schedule`, et même raison — le
-- groupement se fait en SQL parce qu'il est alors vérifiable par
-- `scripts/test_rls.sh`, qui tourne en CI là où les Edge Functions ne sont pas
-- joignables.
--
-- **La clé de dédoublonnage porte l'heure du tir.** La tâche est horaire : une
-- fenêtre d'une heure vaut exactement un tir, et un rejeu de l'ordonnanceur après
-- redémarrage retombe dans la même fenêtre, donc sur la même clé, donc ne
-- réexpédie rien. La fenêtre est indexée sur l'heure UTC, pas sur une heure
-- locale : la clé n'a pas à être lisible par un humain, elle a à être stable.
--
-- **Le constat avant la marque**, comme dans `remind_schedule` : si une demande
-- existe déjà sous cette clé, personne ne recevra rien de plus et l'on ne touche
-- **ni `reminder_count` ni `last_reminder_at`**. Marquer sans envoyer, c'est
-- faire franchir un palier à un pompier qui n'a rien reçu : à T+48 h il serait
-- réputé avoir eu son push et le courriel partirait sur une base fausse. La
-- revue du 019 l'avait déjà dit pour le bouton ; c'est la même règle ici.
--
-- Renvoie le nombre de **notifications** mises en file — une par membre relancé,
-- pas une par garde. C'est ce que compte le journal de l'ordonnanceur, et c'est
-- le même nombre que celui qu'on annoncerait à un administrateur.
create function cron_assignment_reminders(p_reference timestamptz default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant       timestamptz := coalesce(p_reference, now());
  -- La fenêtre horaire du tir. Voir plus haut : stabilité, pas lisibilité.
  fenetre       text := to_char(instant at time zone 'UTC', 'YYYY-MM-DD"T"HH24');
  palier        text;
  lot           record;
  cibles        uuid[];
  destinataires jsonb;
  cle           text;
  envoyes       integer := 0;
begin
  -- Le courriel d'abord : voir « Cohabitation » en tête de migration.
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
      order by sc.station_id, sc.id
    loop
      cibles := assignment_reminder_targets(lot.schedule_id, palier, instant);
      continue when cibles is null or cardinality(cibles) = 0;

      cle := format('assignment_reminder:auto:%s:%s:%s', palier, lot.schedule_id, fenetre);

      -- Déjà parti dans cette fenêtre : ni envoi, ni marque.
      continue when exists (
        select 1 from notification_outbox
         where type = 'assignment_reminder' and dedupe_key = cle);

      -- Une entrée par pompier, ses gardes triées. La charge utile commune
      -- (`period`) reste sur la demande : `send-notification` la fusionne dans
      -- celle de chaque destinataire (`notification_send.ts`).
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
        -- docs/WORKFLOWS.md § 8 : « push puis email ». `inapp` s'ajoute aux
        -- deux : le centre de notifications est la trace de ce qui est parti, et
        -- un rappel absent de cette liste serait un rappel introuvable une fois
        -- le push balayé de l'écran. Même choix qu'au ticket 015.
        p_channels   => case palier
                          when 'push' then array['push', 'inapp']
                          else             array['email', 'inapp']
                        end,
        p_recipients => destinataires,
        p_dedupe_key => cle);

      -- La marque suit l'envoi. `instant` et non `now()` : le palier suivant se
      -- calcule contre la même horloge que celle qui vient de décider.
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
  'Tâche assignment_reminders (docs/SCHEMA.md § 8) : push à response_reminder_hours puis courriel à response_email_hours aux membres actifs dont l''attribution est restée sans réponse. Une notification par membre, groupée. reminder_count et last_reminder_at ne sont marqués que lorsqu''un envoi part réellement. Renvoie le nombre de notifications mises en file.';

revoke execute on function cron_assignment_reminders(timestamptz)
  from public, anon, authenticated;

-- ===========================================================================
-- 3. La tâche late_responders_report
-- ===========================================================================
-- docs/WORKFLOWS.md § 8 : destinataires « admins », regroupement « un par jour
-- et par planning ». Le regroupement est la **clé de dédoublonnage** —
-- `late_responders:<planning>:<date locale de la caserne>` — et rien d'autre.
-- Aucun état supplémentaire à tenir, aucun risque de le voir diverger du réel.
--
-- Le retard est celui de `v_schedule_progress.assignments_late` : `proposed`,
-- `proposed_at` non nul, plus vieux que `late_report_hours`. **Sans filtre
-- d'appartenance**, contrairement aux relances du § 2, et la différence est
-- voulue : une proposition laissée à un pompier désactivé ne sera jamais
-- honorée, c'est un trou dans le planning, et le rapport aux administrateurs est
-- précisément l'endroit où un trou doit apparaître. Relancer ce pompier n'aurait
-- pas de sens ; le taire à son chef de centre non plus.
--
-- L'heure locale, et la question du ticket 041
-- --------------------------------------------
-- La tâche est horaire, et la clé de dédoublonnage porte la **date locale de la
-- caserne**. Sans autre précaution, la première exécution après minuit local
-- partirait — un push à 00:15 pour dire que trois propositions traînent depuis
-- trois jours. La fenêtre `8 <= heure locale <= 20` écarte ce cas : chaque
-- caserne reçoit son rapport au premier tir de sa journée locale à partir de
-- 08:00, et jamais après 21:00.
--
-- C'est aussi la réponse locale au ticket 041 (« l'heure d'envoi n'est pas
-- adaptée au fuseau des casernes d'outre-mer ») pour cette tâche-ci : elle est
-- déjà dans le fuseau de chaque caserne et n'a rien à attendre de ce ticket. Le
-- 041 reste entier pour `availability_reminders` (0016), dont le tir quotidien
-- unique à 09:00 est une heure de serveur. Les décalages à la demi-heure
-- (Marquises UTC-09:30) sont couverts sans cas particulier : la fenêtre porte sur
-- l'heure, pas sur la minute.
--
-- `pending_count`, `hours` et `members` sont exactement ce que lit
-- `construireContenu` pour `late_responders`
-- (`supabase/functions/_shared/notification_content.ts`) : « 3 astreintes sans
-- réponse — Marie L., Thomas M. n'ont pas répondu. » Les noms sont ceux de la
-- caserne (`memberships.display_name`), avec le nom du profil en repli : c'est
-- ainsi que l'administrateur les reconnaît dans ses listes.
--
-- Renvoie le nombre de rapports mis en file, un par planning.
create function cron_late_responders_report(p_reference timestamptz default null)
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
      -- Jamais au milieu de la nuit locale. Voir plus haut.
      and extract(hour from instant at time zone st.timezone) between 8 and 20
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

    -- Une caserne sans administrateur actif n'existe pas en pratique
    -- (`memberships_guard_admin`, 0010), mais un rapport sans destinataire
    -- ferait lever `notify_recipients_invalid` et arrêterait la tâche pour
    -- toutes les autres casernes.
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
      -- Canaux laissés à NULL : ceux du type, « inapp + push »
      -- (docs/WORKFLOWS.md § 8), déclarés une seule fois dans
      -- `CANAUX_PAR_DEFAUT`. Les recopier ici en ferait un second endroit à
      -- tenir à jour.
      p_dedupe_key => cle);

    envoyes := envoyes + 1;
  end loop;

  return envoyes;
end $$;

comment on function cron_late_responders_report(timestamptz) is
  'Tâche late_responders_report (docs/SCHEMA.md § 8) : prévient les administrateurs des attributions sans réponse depuis late_report_hours, une fois par jour et par planning (clé de dédoublonnage datée dans le fuseau de la caserne), entre 08:00 et 20:59 heure locale. Même définition du retard que v_schedule_progress.assignments_late et remind_schedule. Renvoie le nombre de rapports mis en file.';

revoke execute on function cron_late_responders_report(timestamptz)
  from public, anon, authenticated;

-- ===========================================================================
-- 4. Les deux tâches planifiées (docs/SCHEMA.md § 8)
-- ===========================================================================
-- Même forme que 0012, 0014 et 0016 : `cron.schedule` est un upsert depuis
-- pg_cron 1.4, la commande est qualifiée et sans argument, et le garde-fou
-- `insufficient_privilege` évite qu'un projet hébergé où le schéma `cron`
-- appartient à `supabase_admin` fasse échouer tout le déploiement pour une tâche
-- de confort.
--
-- Les minutes sont décalées les unes des autres et de `lock_periods`
-- (`0 * * * *`) : trois tâches horaires qui démarrent à la même seconde
-- verrouillent les mêmes lignes de `notification_outbox` pour rien.
do $planif$
begin
  perform cron.schedule(
    'assignment_reminders', '15 * * * *',
    $cmd$select public.cron_assignment_reminders();$cmd$);
exception
  when insufficient_privilege then
    raise notice 'pg_cron : droits insuffisants pour planifier assignment_reminders, à faire à la main.';
end $planif$;

do $planif$
begin
  perform cron.schedule(
    'late_responders_report', '45 * * * *',
    $cmd$select public.cron_late_responders_report();$cmd$);
exception
  when insufficient_privilege then
    raise notice 'pg_cron : droits insuffisants pour planifier late_responders_report, à faire à la main.';
end $planif$;
