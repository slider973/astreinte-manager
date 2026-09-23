# Workflows et machines à états

## 1. Période de saisie (`periods.status`)

```mermaid
stateDiagram-v2
  [*] --> open : création (cron M+1, M+2 ou admin)
  open --> locked : deadline_at atteinte (cron) ou admin
  locked --> open : admin rouvre (audit)
```

Règles :
- Les membres écrivent leurs disponibilités uniquement en `open`.
- L'admin écrit toujours, avec `set_by` renseigné et audit si `set_by <> user_id`.
  `set_by` est **imposé** par le déclencheur `availabilities_trace_auteur` (migration `0012`) :
  ce que le client envoie dans cette colonne est ignoré.
- **Rouvrir, c'est dire jusqu'à quand.** La transition `locked → open` exige une
  `deadline_at` future (`period_reopen_deadline_passed`, migration `0012`) : la tâche
  `lock_periods` passe toutes les heures, et une période rouverte sans nouvelle date limite
  serait reverrouillée dans l'heure. L'écran d'administration demande donc la nouvelle date
  limite dans le même geste que la réouverture.
- `locked_at` n'est jamais écrit par le client : le déclencheur le pose au verrouillage et
  l'efface à la réouverture.

## 2. Planning (`schedules.status`)

```mermaid
stateDiagram-v2
  [*] --> draft : admin crée le planning du mois
  draft --> published : admin publie (publish-schedule)
  published --> validated : toutes les attributions requises acceptées (trigger)
  validated --> published : admin modifie un créneau
  published --> archived : cron, mois passé
  validated --> archived : cron, mois passé
```

Règles :
- `draft` est invisible des membres.
- `published` : chaque membre voit ses propres attributions et peut répondre.
- `validated` : tous les membres voient le planning complet.
- Une modification en `validated` renvoie le planning en `published` et ne touche que les
  attributions modifiées.
- **`archived` : le mois est passé, et il se lit comme le tableau de garde punaisé au mur.**
  Chaque membre voit les créneaux du mois, **toutes ses propres attributions** — y compris ses
  refus et leurs motifs, c'est son historique — et les attributions **acceptées** des autres,
  c'est-à-dire qui a tenu la garde. Il ne voit ni les propositions restées sans réponse ni les
  refus **des autres** : c'était de l'information de construction, le mois révolu elle
  n'appartient plus qu'à l'administration, qui garde tout. Décidé au ticket 044, détaillé dans
  `docs/SCHEMA.md § 4` et dans la migration `0031`.
- **`archived` est terminal, dans les deux sens.** On n'en sort pas
  (`schedules_guard_transition`), et **rien ne s'y écrit plus** : ni un créneau, ni une
  attribution, ni une réponse de membre, ni une réattribution ou une annulation — les deux
  fonctions rendent `schedule_not_published` (migrations `0019`, `0020` et `0031`).
- **Un `draft` n'est jamais archivé.** La transition n'existe pas dans le diagramme, et un
  brouillon oublié est la seule chose du produit qui se supprime encore : l'archiver le rendrait
  indestructible sans avoir jamais été lu.

## 3. Attribution (`assignments.status`)

```mermaid
stateDiagram-v2
  [*] --> proposed : admin attribue (brouillon) puis publie
  proposed --> accepted : membre accepte
  proposed --> declined : membre refuse
  proposed --> cancelled : admin retire avant réponse
  declined --> [*]
  accepted --> cancelled : admin retire (notification)
  proposed --> replaced : admin réattribue à quelqu'un d'autre
  accepted --> replaced : admin réattribue (notification)
```

Règles :
- Un membre passe uniquement de `proposed` à `accepted` ou `declined`.
- `replaced` porte `replaced_by` vers la nouvelle attribution. **Un refus et une annulation
  aussi** : ils gardent leur statut — c'est l'histoire de la caserne, et elle a déjà été notifiée
  sous ce nom — et leur `replaced_by` dit quelle attribution a comblé le trou (migration `0020`).
- **Les états terminaux sont à sens unique, et hors de portée d'un client** (migration `0020`).
  `declined`, `replaced` et `cancelled` ne s'écrivent ni par une insertion ni par une mise à jour
  cliente, et on n'en **sort** pas : l'historique de la caserne ne se réécrit pas. Le motif d'un
  refus est gelé. Ces écritures passent par `reassign_shift` ou `cancel_assignment`, qui préviennent
  le pompier concerné dans la même transaction : un changement d'état qui ne se dit pas laisse
  quelqu'un se croire d'astreinte.
- **Une réattribution remplace, elle n'ajoute pas.** Le nombre d'attributions actives d'un créneau ne
  dépasse jamais son effectif requis : `reassign_shift` compte les places après avoir pris ses
  verrous et refuse en `shift_already_filled` sinon. Renforcer un créneau publié se dit autrement —
  en augmentant son effectif requis.
- **La notification marque les transitions venues d'`accepted`, et elles seules.** Retirer une
  proposition sans réponse ne prévient personne : rien n'était acquis, et l'écran « Propositions »
  du membre sera simplement plus court.
- En brouillon, les attributions existent avec `status = 'proposed'` et `proposed_at = null`.
  La publication renseigne `proposed_at`. Les crons de relance ignorent `proposed_at is null`.
  Une attribution née d'une réattribution est horodatée **dès sa création** : elle est partie.

## 4. Séquence : publication et validation

```mermaid
sequenceDiagram
  participant A as Admin (app)
  participant EF as Edge publish-schedule
  participant DB as Postgres
  participant N as Edge send-notification
  participant M as Membre (app)

  A->>EF: publier schedule_id
  EF->>DB: schedule.status = published, assignments.proposed_at = now()
  EF->>N: pour chaque membre : assignment_proposed (groupé)
  N->>DB: insert notifications (inapp, push)
  N-->>M: push FCM
  M->>DB: update assignment status = accepted (RLS + trigger)
  DB->>DB: trigger schedule_auto_validate
  DB-->>A: Realtime : progression mise à jour
  DB->>N: si tout accepté : schedule_validated à tous
```

## 5. Séquence : refus et réattribution

```mermaid
sequenceDiagram
  participant M1 as Membre initial
  participant DB as Postgres
  participant N as send-notification
  participant A as Admin
  participant EF as Edge reassign-shift
  participant M2 as Nouveau membre

  M1->>DB: status = declined, decline_reason
  DB->>N: assignment_declined à l'admin
  N-->>A: push "X a refusé le 12 nuit"
  A->>EF: réattribuer shift_id à M2
  EF->>DB: reassign_shift — une transaction
  DB->>DB: ancienne reste declined, replaced_by posé ; nouvelle proposed, proposed_at = now()
  DB->>N: assignment_proposed à M2 uniquement
  N-->>M2: push
  DB->>DB: schedule_reevaluer — le planning reste publié
```

**Le compte, c'est un.** Un refus suivi d'une réattribution ne produit qu'une notification, au
nouveau membre. Le refus a déjà produit la sienne — `assignment_declined` aux administrateurs — au
moment où il a été prononcé. Rien n'est renvoyé au reste de la caserne : c'est exactement ce que
l'outil remplacé imposait, et la raison d'être du ticket 020.

Les variantes du même geste :

| Ce que remplace la réattribution | Ancienne attribution | Nouveau membre | Ancien membre |
|---|---|---|---|
| un refus | reste `declined`, `replaced_by` posé | `assignment_proposed` | rien |
| une annulation | reste `cancelled`, `replaced_by` posé | `assignment_proposed` | rien : il a déjà été prévenu |
| une proposition sans réponse | `replaced` | `assignment_proposed` | rien |
| une garde acceptée | `replaced` | `assignment_proposed` | `assignment_cancelled` |
| un créneau vide | — | `assignment_proposed` | — |

**Annuler** (`cancel_assignment`) suit la même règle : `accepted → cancelled` prévient le membre
avec le motif, `proposed → cancelled` ne prévient personne.

Dans les deux cas, une acceptation qui disparaît fait repasser le planning de `validated` à
`published` (§ 2) : seuls les créneaux touchés changent d'état, `published_at` ne se réécrit pas, et
personne n'est notifié de ce recul — la conséquence est déjà partie à qui de droit.

## 6. Séquence : relances

```mermaid
sequenceDiagram
  participant C as pg_cron (horaire)
  participant DB as Postgres
  participant N as send-notification

  C->>DB: select assignments proposed, proposed_at + reminder_hours <= now(), reminder_count = 0
  DB->>N: assignment_reminder (push)
  N->>DB: reminder_count += 1, last_reminder_at
  C->>DB: select proposed, proposed_at + email_hours <= now(), palier courriel dû
  DB->>N: assignment_reminder (email)
  N->>DB: reminder_count += 1, last_reminder_at
  C->>DB: select proposed, proposed_at + late_report_hours < now()
  DB->>N: late_responders aux admins (une fois par jour et par planning)
```

Règles (migration `0021`, ticket 022) :

- **Une réponse ferme la porte.** `status = 'proposed'` est la seule condition de relance :
  accepté, refusé, remplacé, annulé, plus rien ne part.
- **Les délais sont ceux de chaque caserne** (`settings`, § 2.1 de `docs/SCHEMA.md`).
- **Un envoi par membre**, ses gardes groupées dedans, jamais un par garde.
- **La marque suit l'envoi** : `reminder_count` et `last_reminder_at` ne bougent que lorsqu'une
  demande est réellement mise en file. Sinon un palier se franchirait sans que personne ne
  reçoive rien.
- **« Palier courriel dû »** se lit : `reminder_count >= 1` **et** (`reminder_count = 1`
  **ou** aucune relance depuis l'échéance du courriel). Le diagramme disait d'abord
  `reminder_count = 1` tout court ; deux clics de l'administrateur sur « Relancer maintenant »
  (ticket 019, qui incrémente le même compteur) auraient alors privé le pompier du courriel
  pour toujours, et une reprise après panne longue aussi. La seconde branche est le filet.
- **Une relance manuelle tient lieu de premier palier** : le push de `reminder_hours` est sauté
  quand `reminder_count` vaut déjà 1.
- **Le rapport aux administrateurs part entre 08:00 et 20:59 dans le fuseau de la caserne**, et
  sa clé de dédoublonnage porte la date locale : une fois par jour et par planning, jamais au
  milieu de la nuit.

## 7. Cycle de vie d'un mois (vue d'ensemble)

| Moment | Événement |
|---|---|
| 1er de M-2 | La période M est créée, ouverte à la saisie |
| J-3 avant deadline | Push de rappel aux membres sans saisie |
| J-1 | Email de rappel |
| Deadline (ex. 15 de M-1) | Période verrouillée |
| M-1, semaine 3 | L'admin construit le brouillon, publie |
| +24 h | Rappel push aux non-répondants |
| +48 h | Email aux non-répondants |
| +72 h | Rapport des retardataires à l'admin |
| Tout accepté | Planning validé, visible de tous |
| Pendant M | Modifications ponctuelles, notifications ciblées |
| 1er de M+1 | Planning archivé (tâche `archive_schedules`, quotidienne à 02:30 : le 1er du mois **de la caserne**, dans son fuseau, jamais la veille) |

## 8. Notifications par événement

| Type | Destinataire | Canaux | Regroupement |
|---|---|---|---|
| `invitation` | invité | email | non |
| `availability_reminder` | membres sans saisie | push J-3, email J-1 | un par membre |
| `assignment_proposed` | membre attribué | push + inapp | oui, par publication |
| `assignment_reminder` | membre sans réponse | push puis email | par membre |
| `assignment_declined` | admins de la caserne | push + inapp | non |
| `assignment_changed` | membre concerné | push + inapp | non |
| `assignment_cancelled` | membre concerné | push + inapp | non |
| `schedule_validated` | tous les membres | push + inapp | oui |
| `schedule_all_accepted` | admins | push + inapp | non |
| `late_responders` | admins | inapp + push | un par jour et par planning |
| `subscription_trial_ending` | admins | email + inapp | un par fin d'essai (J-7) |
| `subscription_suspended` | admins | email + inapp | un par suspension |

Les deux types d'abonnement sont les seuls, avec `invitation`, à partir par **courriel** : un
abonnement ne se règle pas depuis l'écran verrouillé d'un téléphone, et le courriel est le seul
canal qui atteigne un chef de centre qui n'a pas ouvert l'application depuis trois semaines —
le cas nominal d'une fin d'essai. Aucun membre n'en reçoit : le canal sert à dire « tu es
d'astreinte », pas « paie » *(ticket 030)*.

Deep links (`notifications.data.route`). **Ce sont des liens publics** : ils partent dans des
notifications et survivent aux refontes d'écran. `destinationInterne`
(`features/notifications/domain/destination_push.dart`) les traduit en emplacement interne, et
c'est le seul endroit à changer quand les écrans bougent. La colonne de droite dit où ils mènent
depuis le ticket 064, qui a fait éclater la coquille d'accueil en routes.

| Lien public | Emplacement interne |
|---|---|
| `/proposals` | `/propositions` |
| `/schedule/<period>` | `/astreintes` |
| `/admin/schedule/<period>` | `/admin/suivi?mois=<period>` *(admin seulement)* |
| `/availability/<period>` | `/calendrier?mois=<period>` |
| `/admin/subscription` | `/admin/abonnement` *(admin seulement)* |

Un lien inconnu, mal formé, ou visant un écran que ce compte n'a pas le droit d'ouvrir retombe sur
l'accueil **sans message d'erreur** : le membre n'a rien fait de mal, et le lien peut dater d'avant
une rétrogradation.

Les adresses de la coquille d'avant le ticket 064 — `/?onglet=N`, `/?mois=AAAA-MM`,
`/notifications` — sont redirigées vers les nouvelles routes (`core/router/destinations.dart`,
`ongletHerite`). Elles dorment dans des historiques de navigateur et dans des onglets restaurés :
aucune ne rend un écran vide.
