-- 0016 — Rappels de saisie des disponibilités. Ticket 015.
-- Référence : docs/SCHEMA.md sections 3 et 8 ; docs/WORKFLOWS.md sections 6, 7 et 8.
--
-- Ce qui existait déjà et n'est pas réécrit
-- -----------------------------------------
--   - `notify(...)` et `notification_outbox` (0014, ticket 025) : la file, la
--     tentative immédiate, la reprise, et surtout la **clé de dédoublonnage**
--     (`notification_outbox_dedupe_uniq`), écrite à l'époque pour ce ticket-ci.
--     « Un seul envoi par membre et par échéance » est donc une contrainte
--     d'unicité, pas une colonne d'état à tenir à jour.
--   - `v_period_completion` (0013, revue du ticket 014) : le taux de saisie de
--     l'écran « Périodes », déjà en place et déjà consommé par
--     `lib/features/periodes/data/periodes_repository.dart`. Le second critère
--     d'acceptation du ticket est tenu par cette vue ; rien à refaire ici.
--   - `station_writable(uuid)` (0007) : une caserne suspendue est en lecture
--     seule.
--
-- Ce que cette migration ajoute
-- -----------------------------
--   1. `cron_availability_reminders(instant)`, le corps de la tâche
--      `availability_reminders` de docs/SCHEMA.md § 8, paramétré par une date de
--      référence comme les tâches de 0012 et 0014.
--   2. La tâche `pg_cron` elle-même, tous les jours à 09:00.
--
-- Écart documenté avec docs/SCHEMA.md § 10
-- ----------------------------------------
-- Le plan de migrations annonçait un unique `0016_cron_notifications.sql`
-- portant « les cinq tâches restantes du § 8 ». Elles appartiennent à quatre
-- tickets différents (015, 022, et les deux tâches d'entretien) : les réunir
-- obligerait soit à écrire ici du code sans ticket, soit à modifier plus tard une
-- migration déjà poussée. Le fichier est donc scindé par sujet, conformément à la
-- règle « une migration par sujet », et docs/SCHEMA.md § 10 est mis à jour dans le
-- même commit.

-- ===========================================================================
-- 1. Le corps de la tâche
-- ===========================================================================
-- docs/WORKFLOWS.md § 7 : « J-3 avant deadline : push de rappel aux membres sans
-- saisie ; J-1 : email de rappel ». Une seule fonction pour les deux échéances :
-- c'est la même population, la même charge utile, et la même règle de
-- dédoublonnage. Deux fonctions auraient fait deux fois le même `not exists`.
--
-- Trois choses ne sont pas négociables ici, et chacune a coûté un raisonnement.
--
-- a) Le jour se compte dans le fuseau de la caserne
-- ------------------------------------------------
-- `deadline_at` est un `timestamptz` : « le 15 septembre à 23:59:59 à Paris » et
-- « le 15 septembre à 23:59:59 à Cayenne » sont deux instants différents. Compter
-- les jours restants en UTC relancerait une caserne d'outre-mer un jour trop tôt
-- ou un jour trop tard, selon le signe du décalage. Les deux dates sont donc
-- ramenées dans le fuseau de la caserne avant d'être soustraites — même principe
-- que `cron_create_periods` (0012).
--
-- L'ordonnanceur tire une fois par jour, à 09:00 (heure du serveur). À cet
-- instant, la date locale de chaque caserne est parfaitement définie et avance
-- d'exactement un jour d'un tir à l'autre, quel que soit son décalage : aucune
-- caserne ne saute une échéance, aucune n'en voit deux. C'est ce qui permet de
-- tenir la promesse « J-3 » et « J-1 » avec un seul tir quotidien.
--
-- b) « A saisi » veut dire « a au moins une ligne sur le mois »
-- ------------------------------------------------------------
-- Exactement la définition de `v_period_completion` (0013), et exactement le
-- critère d'acceptation du ticket. Une ligne `absent` compte autant qu'une ligne
-- `available` : le membre a répondu, il n'a rien à se faire rappeler. Le test est
-- un `exists` et non un `count`, l'index `availabilities (user_id, date)` le
-- tranche sans lire les soixante lignes d'un mois plein.
--
-- c) Une période verrouillée ou une caserne suspendue ne relance personne
-- ----------------------------------------------------------------------
-- `status = 'open'` : un admin qui verrouille un mois en avance a décidé que la
-- saisie était close ; le relancer serait lui désobéir. (Le cas n'est pas
-- théorique : `deadline_at` à J-3 avec un statut `locked`, c'est un verrouillage
-- manuel anticipé.)
--
-- `station_writable` : une caserne suspendue est en lecture seule. Lui demander
-- de saisir ce qu'elle ne peut pas écrire, c'est promettre un mur. C'est une
-- différence assumée avec `cron_create_periods`, qui sert les casernes suspendues
-- comme les autres — créer une période ne demande rien à personne, relancer si.
--
-- Le compteur rendu est le nombre de rappels **réellement mis en file**. D'où le
-- filtre sur `notification_outbox` dans la requête : sans lui, un second passage
-- le même jour rendrait le même nombre alors qu'il n'aurait rien fait, et le
-- journal de l'ordonnanceur mentirait. La contrainte d'unicité reste le garde-fou
-- — le filtre est une lecture, deux tirs concurrents pourraient le franchir
-- ensemble ; c'est l'index qui tranche, et `notify` rend alors la ligne déjà en
-- file sans rien reposter.
create function cron_availability_reminders(p_reference timestamptz default null)
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
      -- ISO 8601 en UTC : c'est ce que `new Date(...)` de l'Edge Function lit
      -- sans ambiguïté, et `instantLong()` le reformate ensuite dans le fuseau
      -- de la caserne (supabase/functions/_shared/notification_content.ts).
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
             -- La caserne fait partie de la clé : docs/PRD.md § 6.1 autorise un
             -- pompier à servir dans deux casernes. Sans elle, deux casernes qui
             -- partagent un membre et un mois se voleraient le rappel l'une à
             -- l'autre, et la seconde ne saurait jamais pourquoi.
             format('availability_reminder:%s:%s:%s:%s',
                    p.station_id, c.periode, c.echeance, m.user_id) as cle
    ) e
    where p.status = 'open'
      and d.jours in (1, 3)
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
      -- docs/WORKFLOWS.md § 8 : « push J-3, email J-1 ». `inapp` s'ajoute aux
      -- deux : le centre de notifications (ticket 026) est la trace de ce qui a
      -- été envoyé, et un rappel absent de cette liste serait un rappel qu'on ne
      -- peut plus retrouver quand le push a été balayé de l'écran.
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
  'Tâche availability_reminders (docs/SCHEMA.md § 8) : push à J-3, courriel à J-1, aux membres actifs sans aucune ligne availabilities sur le mois d''une période ouverte. Jours comptés dans le fuseau de la caserne. Un seul envoi par membre et par échéance, garanti par la clé de dédoublonnage de notification_outbox. Renvoie le nombre de rappels mis en file.';

revoke execute on function cron_availability_reminders(timestamptz) from public, anon, authenticated;

-- ===========================================================================
-- 2. La tâche planifiée (docs/SCHEMA.md § 8)
-- ===========================================================================
-- Même forme que 0012 et 0014 : `cron.schedule` est un upsert depuis pg_cron
-- 1.4, la commande est qualifiée et sans argument, et le garde-fou
-- `insufficient_privilege` évite qu'un projet hébergé où le schéma `cron`
-- appartient à `supabase_admin` échoue tout le déploiement pour une tâche de
-- confort.
--
-- Un seul tir par jour suffit parce que la date locale de chaque caserne avance
-- d'exactement un jour entre deux tirs (voir a) ci-dessus). Si l'ordonnanceur
-- redémarre et rejoue la tâche, la clé de dédoublonnage absorbe le rejeu : c'est
-- l'exigence « idempotente » de docs/SCHEMA.md § 8.
do $planif$
begin
  perform cron.schedule(
    'availability_reminders', '0 9 * * *',
    $cmd$select public.cron_availability_reminders();$cmd$);
exception
  when insufficient_privilege then
    raise notice 'pg_cron : droits insuffisants pour planifier availability_reminders, à faire à la main.';
end $planif$;
