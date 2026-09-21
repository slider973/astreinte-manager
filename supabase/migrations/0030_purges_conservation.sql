-- 0030 — Appliquer les durées de conservation annoncées. Ticket 043.
-- Référence : docs/SCHEMA.md § 8 (tâches planifiées), docs/RGPD.md § 2 (registre
-- des traitements).
--
-- Pourquoi cette migration existe
-- --------------------------------
-- Le registre des traitements du ticket 034 annonce des durées de conservation.
-- L'une d'elles — « les notifications lues sont supprimées au bout de quatre-
-- vingt-dix jours » — était décrite dans docs/SCHEMA.md § 8 depuis le premier
-- jour et **n'avait jamais été planifiée** : aucune ligne dans `cron.job`, aucune
-- fonction. Une durée affichée mais non appliquée n'est pas un retard de
-- développement, c'est une affirmation fausse dans un document opposable.
--
-- Le ticket demandait donc deux choses : mettre cette tâche en service, et
-- relire le registre ligne à ligne pour vérifier que chaque durée annoncée
-- correspond à un mécanisme qui l'applique. La relecture a trouvé quatre autres
-- tables sans borne, dont trois portent une donnée personnelle.
--
-- L'inventaire, table par table
-- ------------------------------
-- Ce que la relecture a établi, et qui est reporté dans docs/RGPD.md :
--
--   | Table                  | Annoncé avant          | Mécanisme avant          | Ici |
--   |------------------------|------------------------|--------------------------|-----|
--   | profiles, memberships  | anonymisé à la suppression | `delete_own_account` (0026) | rien à faire |
--   | availabilities, prefs  | effacées à la suppression  | `delete_own_account` (0026) | rien à faire |
--   | assignments, shifts    | sans limite, assumé    | —                        | rien à faire |
--   | subscriptions          | durée de l'abonnement  | cascade avec la caserne  | document corrigé |
--   | **notifications**      | 90 jours (§ 8)         | **aucun**                | tâche `prune_notifications` |
--   | **push_tokens**        | sans limite            | rejet Firebase seulement | 365 jours sans usage |
--   | **notification_outbox**| sans limite            | **aucun**                | 30 jours après traitement |
--   | **invitations**        | « tant que l'appartenance existe » | suppression de compte, invitations en attente | 30 jours après expiration |
--   | **audit_log**          | `[À COMPLÉTER]`        | **aucun**                | 3 ans |
--   | **stripe_events**      | durée légale comptable | **aucun**                | 90 jours, sauf les échecs |
--
-- Les durées, et pourquoi celles-là
-- ----------------------------------
-- **Notifications lues : 90 jours après la lecture.** C'est la durée déjà
-- écrite au § 8, reprise sans discussion. Le point de départ est `read_at` et
-- non `created_at` : « les notifications lues de plus de 90 jours » se lit
-- « lues il y a plus de 90 jours », et c'est aussi le choix le plus prudent des
-- deux — une notification lue le jour de sa réception part au même moment dans
-- les deux lectures, une notification lue tardivement reste trois mois de plus
-- sous celle-ci.
--
-- **Notifications jamais lues : 365 jours après leur création.** Ajout au § 8,
-- et il fallait le faire pour que la ligne du registre soit vraie. Purger les
-- seules notifications lues laissait l'autre moitié de la table sans borne : le
-- produit aurait annoncé une conservation limitée en conservant sans limite tout
-- ce que personne n'a ouvert. Un an est le point où le contenu a cessé d'avoir
-- un sens — la garde annoncée est passée depuis longtemps, le lien profond
-- pointe vers une période archivée — tout en laissant très largement le temps
-- à un pompier absent une saison de retrouver ce qu'il a manqué.
--
-- **Journal d'audit : 3 ans.** Le registre laissait la durée `[À COMPLÉTER]`
-- avec « trois ans est l'ordre de grandeur usuel » ; le ticket demandait de
-- trancher et de dire pourquoi plutôt que de recopier le chiffre. Le
-- raisonnement :
--
--   1. **À quoi sert cette trace.** À expliquer *a posteriori* une décision
--      d'administration sur les données d'un membre : qui a coché cette
--      disponibilité à ma place, qui m'a attribué cette garde hors
--      disponibilité, qui a réouvert ce mois (docs/PRD.md § 7 règle 7). C'est un
--      journal métier, pas un journal technique de sécurité — la recommandation
--      CNIL de six mois à un an sur les journaux de connexion ne s'y applique
--      pas.
--   2. **Sur quelle durée la question se pose.** Un désaccord sur une garde naît
--      dans les jours qui suivent. Mais l'acte tracé sous-tend une indemnité de
--      vacation horaire, et une réclamation sur une somme due se prescrit par
--      trois ans (art. L3245-1 du code du travail, durée usuelle des créances
--      salariales). Trois ans couvre donc la fenêtre pendant laquelle la trace
--      peut encore servir à quelque chose.
--   3. **Pourquoi pas plus.** Au-delà, personne ne conteste plus rien, et le
--      journal ne serait plus qu'un historique nominatif des gestes d'un chef de
--      centre sur toute une carrière — conservé sans finalité, donc conservé
--      sans base.
--   4. **Ce qu'on ne perd pas.** Le fait, lui, reste : l'attribution, le créneau
--      et la mention « attribué hors disponibilité » vivent dans `assignments`,
--      conservés sans limite (docs/RGPD.md § 2.2). Ce qui expire au bout de trois
--      ans, c'est le nom de celui qui a posé le geste, pas la garde.
--
--   Une caserne publique dont le SDIS applique la déchéance quadriennale
--   (loi du 31 décembre 1968) voudra quatre ans : c'est un seul chiffre à changer,
--   le paramètre `p_days` de `prune_audit_log`, et c'est pour cela qu'il est un
--   paramètre et non une constante en dur.
--
-- **File d'attente des notifications : 30 jours après traitement.** Elle ne
-- contient que des lignes de plomberie, mais ces lignes portent la charge utile
-- complète — identifiants des destinataires, dates de garde — et grossissent
-- d'une ligne par envoi, pour toujours. Trente jours est très au-delà de ce dont
-- la table a besoin pour son travail : **la clé de dédoublonnage la plus longue
-- vit une journée** (`late_responders:<planning>:<date locale>`,
-- `subscription_suspended:<caserne>:<date>`) ou une heure
-- (`assignment_reminder:…:<fenêtre horaire>`) ; la seule qui vise plus loin,
-- `availability_reminder:<caserne>:<mois>:<j-3|j-1>:<membre>`, ne protège en
-- pratique que le jour où l'échéance tombe, la tâche ne visant ce palier qu'un
-- jour par mois. Une ligne non traitée — `pending` ou `sending` — n'est **jamais**
-- supprimée, quel que soit son âge : c'est une notification qui n'est pas encore
-- partie.
--
-- **Appareils : 365 jours sans usage.** `last_seen_at` est réécrit à chaque
-- inscription du jeton, c'est-à-dire à chaque ouverture de l'application
-- (`lib/features/notifications/data/push_tokens_repository.dart`). Un jeton que
-- l'on n'a pas revu depuis un an appartient à un téléphone changé ou à un
-- navigateur désinstallé — Firebase invalide d'ailleurs de lui-même les jetons
-- restés inactifs environ neuf mois. Et l'erreur est sans conséquence durable :
-- si le jeton était encore vivant, la prochaine ouverture de l'application le
-- réinscrit.
--
-- **Invitations : 30 jours après l'expiration, 3 ans après l'acceptation.**
-- Une invitation est un billet d'entrée à usage unique, valable quatorze jours.
-- Jamais acceptée et expirée depuis un mois, elle ne porte plus qu'une adresse
-- électronique — celle de quelqu'un qui n'est jamais entré dans la caserne,
-- donc la donnée la moins justifiable du produit — et un jeton mort. Acceptée,
-- elle devient la trace de qui a fait entrer qui : même nature et même horizon
-- que le journal d'audit, donc même durée. L'appartenance, elle, reste.
--
-- **Événements de paiement : 90 jours, et jamais un échec.** Le registre
-- annonçait « la durée légale de conservation des pièces comptables » pour
-- `subscriptions` **et** `stripe_events` ; c'était une erreur de rédaction et
-- docs/RGPD.md est corrigé. `stripe_events` n'est pas une pièce comptable : les
-- factures sont chez le prestataire de paiement, cette table est un journal
-- d'idempotence dont le rôle — « une fois et une seule » — cesse quand le
-- prestataire cesse de rejouer, c'est-à-dire au bout de **trois jours**
-- (migration 0023). Quatre-vingt-dix jours laissent quatre-vingt-sept jours de
-- marge pour lire un historique. Les lignes `failed` et `processing` sont
-- épargnées sans limite d'âge : ce sont exactement celles que
-- `select * from stripe_events where status = 'failed'` doit encore montrer, et
-- ce qu'elles disent, c'est ce qui n'est jamais passé.
--
-- Ce qui n'est **pas** fait ici, et pourquoi
-- ------------------------------------------
-- **Aucun index n'est ajouté.** Chaque purge parcourt une table entière une fois
-- par semaine, la nuit. L'index qui l'éviterait serait tenu à jour à chaque
-- insertion — c'est-à-dire à chaque notification et à chaque acte
-- d'administration — pour économiser un balayage hebdomadaire sur une table dont
-- la taille est précisément ce que ces tâches bornent. Le jour où un de ces
-- balayages se voit dans les journaux, l'index se pose en une ligne ; le poser
-- d'avance, c'est payer tous les jours pour une nuit par semaine.
--
-- **Aucune ligne n'est archivée ailleurs.** Une purge qui recopie n'est pas une
-- purge. La durée annoncée doit être la durée réelle, sans table de l'ombre.
--
-- **`archive_schedules` reste à faire** (docs/SCHEMA.md § 8, rang 30 du § 10) :
-- c'est un changement de statut de planning, pas une conservation de donnée
-- personnelle, et il n'est annoncé dans aucune ligne du registre. Il garde son
-- ticket.
--
-- Deux tâches, et pas six
-- -----------------------
-- `prune_notifications` garde le nom que docs/SCHEMA.md § 8 lui donne depuis le
-- début : c'est la tâche que le registre cite, elle doit se lire dans `cron.job`
-- sous ce nom-là. Les cinq autres purges tiennent dans une seule tâche
-- hebdomadaire `prune_retention`, parce qu'une ligne d'ordonnanceur par table
-- serait six fois le même réveil à six minutes d'écart, et six fois la même
-- panne à diagnostiquer. Chacune reste une fonction à part, appelable et
-- vérifiable seule — c'est ce que font les tests.
--
-- Toutes prennent un instant de référence `p_reference` (docs/SCHEMA.md § 8) :
-- c'est la seule façon de vérifier en quelques millisecondes une règle dont
-- l'unité est le trimestre. Elles prennent en plus leurs durées en paramètre,
-- pour que le test puisse poser une frontière à la journée près sans fabriquer
-- des lignes vieilles de trois ans, et pour qu'une caserne qui doit changer un
-- chiffre change un chiffre. L'ordonnanceur appelle toujours sans argument.

-- ===========================================================================
-- 1. La tâche prune_notifications (docs/SCHEMA.md § 8)
-- ===========================================================================
-- Un seul `delete` pour les deux règles : un balayage au lieu de deux, et une
-- borne qu'on lit d'un coup d'œil.
--
-- `read_at is not null` / `read_at is null` partitionnent la table : aucune
-- ligne n'est examinée deux fois, aucune n'échappe aux deux branches.
--
-- Renvoie le nombre de lignes supprimées, comme toutes les tâches de ce fichier :
-- c'est ce que le journal de l'ordonnanceur retient, et c'est ce que le test
-- compare.
create function cron_prune_notifications(
  p_reference    timestamptz default null,
  p_read_days    integer     default 90,
  p_unread_days  integer     default 365
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant    timestamptz := coalesce(p_reference, now());
  supprimees integer;
begin
  delete from notifications n
   where (n.read_at is not null
          and n.read_at < instant - make_interval(days => p_read_days))
      or (n.read_at is null
          and n.created_at < instant - make_interval(days => p_unread_days));

  get diagnostics supprimees = row_count;
  return supprimees;
end $$;

comment on function cron_prune_notifications(timestamptz, integer, integer) is
  'Tâche prune_notifications (docs/SCHEMA.md § 8) : supprime les notifications lues il y a plus de p_read_days jours (90) et celles jamais lues créées il y a plus de p_unread_days jours (365). Renvoie le nombre de lignes supprimées.';

revoke execute on function cron_prune_notifications(timestamptz, integer, integer)
  from public, anon, authenticated;

-- ===========================================================================
-- 2. Le journal d'audit — trois ans
-- ===========================================================================
-- Voir le raisonnement en tête de migration. `created_at` est la seule date de
-- la ligne : un acte n'est pas modifié après coup.
create function prune_audit_log(
  p_reference timestamptz default null,
  p_days      integer     default 1095
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant    timestamptz := coalesce(p_reference, now());
  supprimees integer;
begin
  delete from audit_log a
   where a.created_at < instant - make_interval(days => p_days);

  get diagnostics supprimees = row_count;
  return supprimees;
end $$;

comment on function prune_audit_log(timestamptz, integer) is
  'Supprime les actes d''administration de plus de p_days jours (1095, soit trois ans : horizon d''une réclamation sur une garde, voir la migration 0030 et docs/RGPD.md § 2.4). Le fait attribué reste dans assignments. Appelée par la tâche prune_retention.';

revoke execute on function prune_audit_log(timestamptz, integer)
  from public, anon, authenticated;

-- ===========================================================================
-- 3. Les invitations — le billet mort, puis la trace
-- ===========================================================================
-- Deux branches disjointes (`accepted_at` nul ou non), une pour chaque vie
-- d'une invitation. La non acceptée part trente jours après son expiration, pas
-- le jour même : une invitation qui vient d'expirer se renvoie, et l'admin qui
-- la retrouve dans sa liste comprend pourquoi personne n'est entré.
create function prune_invitations(
  p_reference      timestamptz default null,
  p_expired_days   integer     default 30,
  p_accepted_days  integer     default 1095
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant    timestamptz := coalesce(p_reference, now());
  supprimees integer;
begin
  delete from invitations i
   where (i.accepted_at is null
          and i.expires_at < instant - make_interval(days => p_expired_days))
      or (i.accepted_at is not null
          and i.accepted_at < instant - make_interval(days => p_accepted_days));

  get diagnostics supprimees = row_count;
  return supprimees;
end $$;

comment on function prune_invitations(timestamptz, integer, integer) is
  'Supprime les invitations jamais acceptées expirées depuis plus de p_expired_days jours (30) et les invitations acceptées depuis plus de p_accepted_days jours (1095, même horizon que le journal d''audit). L''appartenance créée par l''invitation n''est pas touchée. Appelée par la tâche prune_retention.';

revoke execute on function prune_invitations(timestamptz, integer, integer)
  from public, anon, authenticated;

-- ===========================================================================
-- 4. La file d'attente des notifications — trente jours après traitement
-- ===========================================================================
-- **Seuls les états terminaux.** `pending` est une notification qui n'est pas
-- encore partie ; `sending` est une prise en charge en cours, que
-- `cron_dispatch_notifications` remettra en attente si elle n'aboutit pas. Ni
-- l'une ni l'autre ne se purge par l'âge : ce serait perdre un envoi, et une
-- purge n'a pas à décider qu'une notification n'était pas si importante.
--
-- `processed_at is not null` est redondant avec les deux statuts — `notify_complete`
-- et l'abandon de 0022 le posent tous les deux — et c'est voulu : la date de
-- départ de la conservation doit exister, pas être supposée.
create function prune_notification_outbox(
  p_reference timestamptz default null,
  p_days      integer     default 30
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant    timestamptz := coalesce(p_reference, now());
  supprimees integer;
begin
  delete from notification_outbox o
   where o.status in ('sent', 'failed')
     and o.processed_at is not null
     and o.processed_at < instant - make_interval(days => p_days);

  get diagnostics supprimees = row_count;
  return supprimees;
end $$;

comment on function prune_notification_outbox(timestamptz, integer) is
  'Supprime les demandes de notification traitées (sent, failed) depuis plus de p_days jours (30). Une demande pending ou sending n''est jamais supprimée, quel que soit son âge. Appelée par la tâche prune_retention.';

revoke execute on function prune_notification_outbox(timestamptz, integer)
  from public, anon, authenticated;

-- ===========================================================================
-- 5. Les événements de paiement — quatre-vingt-dix jours, jamais un échec
-- ===========================================================================
-- `processed` et `skipped` sont les deux fins heureuses : l'événement a été
-- appliqué, ou il n'avait rien à appliquer. `failed` et `processing` restent,
-- sans limite d'âge — voir le commentaire de la table en 0023, elles sont la
-- seule mémoire de ce qui n'est jamais passé, et elles sont rares par
-- construction.
--
-- `coalesce(processed_at, received_at)` : un `skipped` posé par l'Edge Function
-- sans date de traitement n'échappe pas à la purge pour autant.
create function prune_stripe_events(
  p_reference timestamptz default null,
  p_days      integer     default 90
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant    timestamptz := coalesce(p_reference, now());
  supprimees integer;
begin
  delete from stripe_events e
   where e.status in ('processed', 'skipped')
     and coalesce(e.processed_at, e.received_at) < instant - make_interval(days => p_days);

  get diagnostics supprimees = row_count;
  return supprimees;
end $$;

comment on function prune_stripe_events(timestamptz, integer) is
  'Supprime les événements du prestataire de paiement appliqués ou ignorés depuis plus de p_days jours (90, contre trois jours de rejeu côté prestataire). Les lignes failed et processing ne sont jamais supprimées. Appelée par la tâche prune_retention.';

revoke execute on function prune_stripe_events(timestamptz, integer)
  from public, anon, authenticated;

-- ===========================================================================
-- 6. Les appareils — un an sans usage
-- ===========================================================================
-- `last_seen_at` est réécrit à chaque inscription du jeton, donc à chaque
-- ouverture de l'application. Voir le raisonnement en tête de migration : la
-- suppression d'un jeton encore vivant est rattrapée par la prochaine ouverture.
create function prune_push_tokens(
  p_reference timestamptz default null,
  p_days      integer     default 365
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant    timestamptz := coalesce(p_reference, now());
  supprimees integer;
begin
  delete from push_tokens t
   where t.last_seen_at < instant - make_interval(days => p_days);

  get diagnostics supprimees = row_count;
  return supprimees;
end $$;

comment on function prune_push_tokens(timestamptz, integer) is
  'Supprime les jetons d''appareil non revus depuis plus de p_days jours (365). last_seen_at est réécrit à chaque ouverture de l''application ; un jeton encore vivant serait réinscrit à la suivante. Appelée par la tâche prune_retention.';

revoke execute on function prune_push_tokens(timestamptz, integer)
  from public, anon, authenticated;

-- ===========================================================================
-- 7. La tâche prune_retention
-- ===========================================================================
-- Un réveil hebdomadaire pour les cinq purges qui ne portent pas le nom d'une
-- tâche du § 8. Renvoie le compte par table plutôt qu'un total : un total de
-- 12 400 ne dit pas laquelle des cinq tables vient de maigrir, et c'est
-- justement ce qu'on veut savoir en lisant le journal de l'ordonnanceur.
--
-- Aucun garde-fou d'erreur : si une purge échoue, la tâche échoue et se voit.
-- Rattraper l'exception pour « ne pas bloquer les autres » ferait passer une
-- durée de conservation non appliquée pour une nuit ordinaire, ce qui est
-- exactement l'écart que ce ticket vient corriger.
create function cron_prune_retention(p_reference timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant timestamptz := coalesce(p_reference, now());
begin
  return jsonb_build_object(
    'audit_log',           prune_audit_log(instant),
    'invitations',         prune_invitations(instant),
    'notification_outbox', prune_notification_outbox(instant),
    'push_tokens',         prune_push_tokens(instant),
    'stripe_events',       prune_stripe_events(instant));
end $$;

comment on function cron_prune_retention(timestamptz) is
  'Tâche prune_retention (docs/SCHEMA.md § 8) : applique les durées de conservation de docs/RGPD.md qui ne relèvent pas de prune_notifications — journal d''audit (3 ans), invitations (30 jours après expiration, 3 ans après acceptation), file d''attente traitée (30 jours), appareils inactifs (1 an), événements de paiement appliqués (90 jours). Renvoie le nombre de lignes supprimées par table.';

revoke execute on function cron_prune_retention(timestamptz)
  from public, anon, authenticated;

-- ===========================================================================
-- 8. Les deux tâches planifiées (docs/SCHEMA.md § 8)
-- ===========================================================================
-- Même forme que 0012, 0014, 0016, 0021, 0023 et 0024 : `cron.schedule` est un
-- upsert depuis pg_cron 1.4, la commande est qualifiée et sans argument, et le
-- garde-fou `insufficient_privilege` évite qu'un projet hébergé où le schéma
-- `cron` appartient à `supabase_admin` fasse échouer tout le déploiement.
--
-- Dimanche 04:00 et 04:20 : la nuit la plus creuse de la semaine, après la
-- fenêtre des tâches d'abonnement (03:20 et 03:30) et avant celle des rappels
-- de saisie (09:00). Vingt minutes séparent les deux purges — elles ne se
-- disputent aucune ligne, mais deux balayages complets simultanés se disputent
-- des entrées-sorties.
do $planif$
begin
  perform cron.schedule(
    'prune_notifications', '0 4 * * 0',
    $cmd$select public.cron_prune_notifications();$cmd$);
exception
  when insufficient_privilege then
    raise notice 'pg_cron : droits insuffisants pour planifier prune_notifications, à faire à la main.';
end $planif$;

do $planif$
begin
  perform cron.schedule(
    'prune_retention', '20 4 * * 0',
    $cmd$select public.cron_prune_retention();$cmd$);
exception
  when insufficient_privilege then
    raise notice 'pg_cron : droits insuffisants pour planifier prune_retention, à faire à la main.';
end $planif$;
