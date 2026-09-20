# Edge Functions — Astreinte SP

Deno / TypeScript, une fonction par dossier, la liste de référence est la section 7 de
[`docs/SCHEMA.md`](../../docs/SCHEMA.md). Le code partagé est dans `_shared/`.

| Fonction            | Ticket | Rôle                                                                                                                                                  |
| ------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `invite-member`     | 006    | Un admin invite une ou plusieurs adresses dans sa caserne : ligne `invitations`, compte `auth.users` si l'adresse est inconnue, courriel d'invitation |
| `accept-invitation` | 006    | L'invité connecté échange son jeton contre une `memberships` active                                                                                   |
| `publish-schedule`  | 019    | Publie un planning : statut, `proposed_at` de chaque attribution, puis **une** notification par membre                                                |
| `reassign-shift`    | 020    | Réattribue un créneau d'un planning publié : nouvelle attribution proposée, ancienne remplacée, **une** notification au nouveau membre               |
| `send-notification` | 025    | Écrit la ligne interne, envoie le push FCM et le courriel d'une notification, pour un ou plusieurs membres à la fois                                  |

## Règles qui ne se négocient pas

- **La clé de service ne quitte jamais le serveur.** Elle ouvre le client administrateur
  (`_shared/supabase.ts`) et n'apparaît dans aucune réponse ni aucun journal.
- **Le jeton d'invitation n'est jamais renvoyé à un client.** Il part uniquement dans le lien du
  courriel, vers l'adresse invitée. La colonne `invitations.token` est hors du `grant` de `select`
  du rôle `authenticated` (migration `0008`), et les deux fonctions SQL qui la manipulent sont
  réservées à `service_role` (migration `0009`).
- **`send-notification` n'est jamais appelable par un client.** Elle écrirait une notification à
  n'importe qui, dans n'importe quelle caserne. Elle n'accepte que deux appelants : la clé de
  service en jeton porteur (les autres Edge Functions), ou l'en-tête `x-notify-secret` qui vaut le
  secret engendré dans Vault par la migration `0014` (pg_net). Tout le reste, y compris un
  administrateur connecté, reçoit un 401 — et `scripts/test_functions.sh § 8` le vérifie.
- **`verify_jwt = true` n'est qu'un portier.** La clé anon est un JWT valide et publique : elle
  franchit ce filtre. C'est `caller()` qui établit l'identité réelle auprès de GoTrue, et une
  requête en base qui établit le rôle. Rien du corps de la requête n'est cru sur parole :
  `station_id` sert à choisir la caserne visée, jamais à prouver un droit.

## Lancer en local

```sh
supabase start
supabase functions serve          # dans un second terminal, rechargement à chaud
scripts/test_functions.sh         # assertions de bout en bout des cinq fonctions
```

Sans Docker ni base, la logique pure des fonctions se vérifie seule :

```sh
deno test supabase/functions/tests/ --allow-env
deno check supabase/functions/send-notification/index.ts
deno fmt --check && deno lint            # depuis supabase/functions/
```

Aucun fichier d'environnement n'est nécessaire en local : toutes les variables ci-dessous ont une
valeur par défaut qui vise la pile locale. Pour en changer, passer un fichier :

```sh
supabase functions serve --env-file supabase/functions/.env.local   # non versionné
```

## Variables d'environnement

Fournies par la plateforme, à ne pas déclarer :

| Variable                    | Contenu                                 |
| --------------------------- | --------------------------------------- |
| `SUPABASE_URL`              | URL de l'API du projet                  |
| `SUPABASE_ANON_KEY`         | clé publique                            |
| `SUPABASE_SERVICE_ROLE_KEY` | clé de service, injectée par le runtime |

À régler par le projet :

| Variable                   | Défaut                                          | Rôle                                                                                                                                                                                                                  |
| -------------------------- | ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `APP_BASE_URL`             | `http://127.0.0.1:3000`                         | Origine de la PWA, base du lien d'invitation                                                                                                                                                                          |
| `APP_INVITE_PATH`          | `/#/invite/{token}`                             | Chemin du lien. `{token}` est remplacé. La valeur par défaut suit la stratégie de hash de go_router, en vigueur dans l'application. Passer à `/invite/{token}` seulement si `usePathUrlStrategy()` est activé         |
| `MAIL_FROM`                | `Astreinte SP <invitations@astreinte-sp.local>` | Expéditeur. En production, un domaine vérifié chez Resend                                                                                                                                                             |
| `RESEND_API_KEY`           | —                                               | Présente : les courriels partent par Resend. Absente : repli sur le serveur de courriel local                                                                                                                         |
| `MAILPIT_URL`              | `http://supabase_inbucket_pompier:8025`         | API HTTP de Mailpit, joignable depuis le réseau Docker de la pile locale. Les courriels sont lisibles sur <http://127.0.0.1:54324>                                                                                    |
| `APP_LINK_PATH`            | `/#{route}`                                     | Chemin d'une destination de notification dans la PWA. `{route}` est remplacé par `notifications.data.route` (`/proposals`, `/schedule/2026-10`…). Même logique que `APP_INVITE_PATH`                                  |
| `FIREBASE_SERVICE_ACCOUNT` | —                                               | Le fichier JSON du compte de service Firebase, tel quel (`docs/FIREBASE.md § 5`). Absent : le push est **indisponible** — la ligne interne est écrite, le courriel prend le relais, et **aucun jeton n'est supprimé** |

En production :

```sh
supabase secrets set APP_BASE_URL=https://app.astreinte-sp.fr
supabase secrets set APP_INVITE_PATH='/#/invite/{token}'
supabase secrets set MAIL_FROM='Astreinte SP <invitations@astreinte-sp.fr>'
supabase secrets set RESEND_API_KEY=re_…
supabase secrets set APP_LINK_PATH='/#{route}'
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat chemin/vers/le-compte-de-service.json)"
```

### Deux secrets qui vivent dans la base, pas dans l'environnement

`public.notify(...)` (migration `0014`) doit savoir **où** appeler `send-notification` et **avec
quel secret**. Ces deux valeurs sont dans Supabase Vault, pas dans les variables d'environnement des
fonctions : c'est Postgres qui les lit, au moment de l'appel.

Le secret est engendré au hasard par la migration et n'est recopié nulle part — l'Edge Function va
le lire avec sa clé de service. Il n'y a **rien à faire**.

Il est gardé en mémoire le temps de vie de l'instance, mais **relu en cas de non-correspondance** :
le jour où il tourne, une instance déjà chaude refuserait sinon tous les appels venus de la base
jusqu'à son recyclage, et les notifications s'accumuleraient en file pour une raison invisible.

L'adresse, elle, vise la pile locale par défaut. Sur un projet hébergé, une commande, une fois :

```sql
select vault.update_secret(
  (select id from vault.secrets where name = 'notify_function_url'),
  'https://<ref-du-projet>.supabase.co/functions/v1/send-notification');
```

Tant que ce n'est pas fait, les notifications déclenchées **depuis la base** restent en file :
`select * from notification_outbox where status <> 'sent'` les montre, avec `last_error`. Rien n'est
perdu — c'est tout l'intérêt de la file — mais rien ne part.

Aucun secret dans le dépôt : `supabase/functions/.env*` est ignoré par git (`.gitignore`, règles
`.env` / `.env.*`).

### Choix du transporteur de courriel

`_shared/mailer.ts` essaie, dans l'ordre :

1. **Resend**, dès que `RESEND_API_KEY` est non vide ;
2. **Mailpit**, le serveur de courriel de la pile locale, par son API HTTP `POST /api/v1/send` ;
3. **rien**, et la fonction renvoie `email_sent: false` avec la raison.

Le troisième cas n'annule pas l'invitation : la ligne existe, le renvoi la relance. Un courriel qui
ne part pas est un incident d'envoi, pas une raison de perdre une invitation. L'échec est visible
dans la réponse (`email_sent`) et tracé dans `notifications.error`.

Le gabarit vit dans `_shared/invitation_email.ts` et non dans `supabase/templates/`, qui est réservé
aux gabarits rendus par GoTrue (`magic_link.html`). Le courriel d'invitation est rendu ici, parce
qu'il porte des données de la base — caserne, inviteur, échéance — que GoTrue ne connaît pas. Il
reprend volontairement la mise en forme et le ton de `supabase/templates/magic_link.html`.

---

## `invite-member`

```
POST /functions/v1/invite-member
apikey: <clé anon>
Authorization: Bearer <access_token de l'admin>
Content-Type: application/json
```

Corps — une adresse ou une liste, jusqu'à 20, un seul rôle pour le lot :

```jsonc
{ "station_id": "uuid", "email": "recrue@exemple.fr" }
{ "station_id": "uuid", "emails": ["a@x.fr", "b@x.fr"], "role": "admin" }
```

`role` vaut `member` par défaut. Les adresses sont normalisées (espaces, casse) et dédoublonnées.

Réponse `200` — sémantique de lot : chaque adresse a son sort.

```jsonc
{
  "ok": true, // faux dès qu'une adresse est en erreur
  "invited": 1,
  "failed": 0,
  "results": [
    {
      "email": "recrue@exemple.fr",
      "status": "invited", // "invited" | "resent" | "error"
      "invitation_id": "uuid",
      "role": "member",
      "expires_at": "2026-10-04T13:27:19.268869+00:00",
      "email_sent": true,
      "email_provider": "mailpit" // "resend" | "mailpit" | "none"
    },
    {
      "email": "deja@exemple.fr",
      "status": "error",
      "code": "already_member",
      "message": "Cette personne est déjà membre actif de la caserne."
    }
  ]
}
```

Codes par adresse (`results[].code`) : `already_member`, `invalid_email`, `conflict`,
`account_failed`, `internal_error`.

Erreurs de requête, forme `{"error": {"code", "message"}}` :

| Statut | `code`               | Quand                                                                                 |
| ------ | -------------------- | ------------------------------------------------------------------------------------- |
| 400    | `invalid_body`       | JSON invalide, `station_id` absent, aucune adresse, plus de 20 adresses, rôle inconnu |
| 401    | `unauthenticated`    | Pas de jeton porteur, ou jeton qui n'identifie pas un utilisateur                     |
| 403    | `not_admin`          | L'appelant n'est pas admin **actif** de `station_id`                                  |
| 403    | `station_suspended`  | Abonnement suspendu : la caserne est en lecture seule                                 |
| 404    | `station_not_found`  | Caserne inconnue                                                                      |
| 405    | `method_not_allowed` | Autre verbe que POST                                                                  |
| 500    | `internal_error`     | Incident serveur                                                                      |

Renvoi d'une invitation : l'index partiel `invitations_pending_uniq` n'autorise qu'une invitation en
attente par caserne et par adresse. Un second appel réutilise la ligne, repousse `expires_at` de 14
jours, met le rôle à jour et **conserve le jeton** — le lien déjà envoyé, éventuellement déjà
ouvert, continue de fonctionner.

---

## `accept-invitation`

```
POST /functions/v1/accept-invitation
apikey: <clé anon>
Authorization: Bearer <access_token de l'invité>
Content-Type: application/json

{ "token": "<jeton du lien d'invitation>" }
```

Réponse `200` :

```jsonc
{
  "ok": true,
  "already_accepted": false, // vrai si le même lien est rejoué
  "membership": {
    "id": "uuid",
    "station_id": "uuid",
    "user_id": "uuid",
    "role": "member",
    "status": "active",
    "display_name": null
  },
  "station": {
    "id": "uuid",
    "name": "CIS Saint-Martin",
    "slug": "saint-martin",
    "timezone": "Europe/Paris"
  },
  "inviter": { "first_name": "Jean", "last_name": "Dupont", "email": "admin@caserne-a.test" }
}
```

Erreurs :

| Statut | `code`                        | Détails joints à `error`                           |
| ------ | ----------------------------- | -------------------------------------------------- |
| 400    | `invalid_body`                | —                                                  |
| 401    | `unauthenticated`             | —                                                  |
| 403    | `email_mismatch`              | `invited_email_masked`, `current_email`, `station` |
| 403    | `station_suspended`           | `station`, `inviter`                               |
| 404    | `invitation_not_found`        | —                                                  |
| 409    | `invitation_already_accepted` | `accepted_at`, `station`, `inviter`                |
| 409    | `profile_missing`             | —                                                  |
| 410    | `invitation_expired`          | `expires_at`, `station`, `inviter`                 |
| 500    | `internal_error`              | —                                                  |

`station` et `inviter` accompagnent les erreurs qui méritent une sortie de secours : l'écran peut
nommer la caserne et proposer d'écrire à l'administrateur plutôt que de laisser l'invité dans un
cul-de-sac.

---

## `publish-schedule`

Le geste qui fait sortir le planning du bureau du chef de centre. Référence :
`docs/WORKFLOWS.md § 2, 3 et 4`, `docs/SCHEMA.md § 7`, migration `0019`.

```
POST /functions/v1/publish-schedule
apikey: <clé anon>
Authorization: Bearer <access_token de l'admin>
Content-Type: application/json

{ "schedule_id": "uuid" }
```

### Deux temps, dans cet ordre

1. **`publish_schedule(p_schedule, p_actor)`** — fonction SQL `security definer`, réservée au rôle
   de service. Elle vérifie le droit de l'appelant, passe le planning en `published`, horodate
   `proposed_at` sur chaque attribution du brouillon, journalise `schedule.published` puis **teste
   sa complétude**, **le tout dans une transaction**. Une publication à moitié faite — des
   attributions horodatées sur un planning resté en brouillon — ne se rattrape par aucune reprise.
   Le test de complétude en fin de course n'est pas un luxe : un planning dont tous les créneaux
   demandent zéro personne est complet avant la moindre réponse, et le déclencheur d'acceptation ne
   se réveillerait jamais. La réponse peut donc rendre `"status": "validated"`.
2. **`send-notification`**, forme groupée, avec la clé de service en jeton porteur. La fonction SQL
   rend les destinataires **déjà groupés par membre** : sept créneaux font une entrée, pas sept.
   L'envoi vient après la transaction et **ne peut donc pas la défaire** — une notification perdue
   se rattrape (relance manuelle, crons du ticket 022), une publication à moitié faite, non.

Réponse `200` :

```jsonc
{
  "ok": true,
  "schedule_id": "uuid",
  "station_id": "uuid",
  "status": "published",
  "published_at": "2026-09-18T19:04:11.204Z",
  "period": "2026-10",
  "assignments": 9, // attributions horodatées par cette publication
  "notified": 2, // **membres**, pas attributions
  "notification": { // le compte rendu de send-notification, tel quel
    "ok": true,
    "type": "assignment_proposed",
    "recipients": 2,
    "delivered": 2,
    "failed": 0,
    "results": [/* … */]
  }
}
```

Un planning sans aucune attribution se publie : c'est en ouvrir la lecture aux membres. Il n'y a
alors personne à prévenir, et `notification` porte `"skipped": "no_recipients"`.

Un envoi en échec **n'annule pas** la publication : `ok` reste vrai pour le planning et
`notification` porte `"error": "send_failed"` ou `"unreachable"`. **L'application doit lire
`notification.ok`** : annoncer « 18 pompiers notifiés » quand aucun téléphone n'a sonné retire au
chef de centre la seule raison qu'il aurait d'aller relancer. L'écran de suivi porte donc un bandeau
tant que le rattrapage n'a pas eu lieu.

Erreurs, forme `{"error": {"code", "message"}}` :

| Statut | `code`               | Quand                                                                   |
| ------ | -------------------- | ----------------------------------------------------------------------- |
| 400    | `invalid_body`       | JSON invalide, `schedule_id` absent                                     |
| 401    | `unauthenticated`    | Pas de jeton porteur, ou jeton qui n'identifie pas un utilisateur       |
| 403    | `not_admin`          | L'appelant n'est pas admin **actif** de la caserne du planning          |
| 403    | `station_suspended`  | Abonnement suspendu : la caserne est en lecture seule                   |
| 404    | `schedule_not_found` | Planning inconnu                                                        |
| 405    | `method_not_allowed` | Autre verbe que POST                                                    |
| 409    | `schedule_not_draft` | Déjà publié — l'adjoint a été plus rapide. `status` accompagne l'erreur |
| 500    | `internal_error`     | Incident serveur                                                        |

### Ce qui n'est pas ici, et pourquoi

- **La validation** n'est pas une action : le déclencheur `schedule_auto_validate` (migration
  `0019`) passe le planning en `validated` dès que chaque créneau atteint son effectif requis en
  attributions **acceptées**, et notifie `schedule_validated` à tous les membres actifs. Aucune Edge
  Function n'y participe.
- **La relance** des retardataires est une fonction SQL appelable par un admin
  (`remind_schedule(p_schedule, p_tout)`), pas une Edge Function : elle passe par `notify(...)` et
  sa file, comme les crons du ticket 022 le feront. `p_tout` sert au **rattrapage d'un envoi
  manqué** : quand `notification.ok` vaut faux ci-dessus, les pompiers concernés n'ont rien reçu et
  ne sont pourtant pas « en retard » — leur faire attendre `late_report_hours` serait absurde.

---

## `reassign-shift`

**Un refus ne coûte qu'un créneau.** C'est la promesse centrale du produit, et c'est cette fonction
qui la tient. Référence : `docs/WORKFLOWS.md § 2, 3 et 5`, `docs/SCHEMA.md § 7`, migration `0020`,
`design/020-reattribution.md`.

```
POST /functions/v1/reassign-shift
apikey: <clé anon>
Authorization: Bearer <access_token de l'admin>
Content-Type: application/json

{
  "shift_id": "uuid",
  "user_id": "uuid",
  "previous_assignment_id": "uuid" // facultatif
}
```

### Un seul appel, une seule transaction

`reassign_shift(p_shift, p_user, p_actor, p_previous)` — fonction SQL `security definer`, réservée
au rôle de service — fait tout, en une fois :

1. verrou de ligne sur le planning, pour que deux adjoints ne pourvoient pas deux fois la même
   place ;
2. la nouvelle attribution, `proposed` et **déjà horodatée** (`proposed_at`), avec `created_by` et
   `was_available` posés par la fonction — sous le rôle de service, le déclencheur
   `assignments_trace_disponibilite` rend la ligne telle quelle ;
3. l'ancienne, s'il y en a une : `accepted → replaced`, `proposed → replaced`, et **`declined`
   reste `declined`** — un refus est l'histoire de la caserne. Dans les trois cas, `replaced_by`
   pointe la nouvelle ;
4. les **demandes de notification**, dans la même transaction, par `notify(...)` ;
5. `audit_log` (`assignment.reassigned`) et `schedule_reevaluer`, qui ramène un planning validé en
   `published` quand une acceptation vient de disparaître.

`previous_assignment_id` est facultatif : laissé vide sur un créneau qui porte un refus non encore
couvert, la base rattache la nouvelle attribution au **plus ancien** d'entre eux.

### Pourquoi elle n'appelle pas `send-notification`, contrairement à `publish-schedule`

Une publication groupe trente pompiers et sept créneaux chacun : le regroupement se fait en SQL,
l'envoi part ensuite de l'Edge Function, **après** la transaction, pour ne pas pouvoir défaire une
publication acquise. Une réattribution vise **une** personne et **un** créneau : il n'y a rien à
grouper, et la file de `notify(...)` — avec son rejeu par `cron_dispatch_notifications` — garantit
l'envoi même si le processus meurt entre la transaction et l'appel HTTP. Un pompier qui ignore
qu'il est d'astreinte est le seul défaut que ce ticket n'a pas le droit de produire.

### Combien de notifications

| Ce que remplace la réattribution | Nouveau membre        | Ancien membre                     |
| -------------------------------- | --------------------- | --------------------------------- |
| un refus (`declined`)            | `assignment_proposed` | **rien** — c'est lui qui a refusé |
| une proposition sans réponse     | `assignment_proposed` | rien — il n'avait rien acquis     |
| une garde acceptée               | `assignment_proposed` | `assignment_cancelled`            |
| un créneau vide                  | `assignment_proposed` | —                                 |

Réponse `200` :

```jsonc
{
  "ok": true,
  "assignment_id": "uuid",
  "shift_id": "uuid",
  "user_id": "uuid",
  "was_available": false, // attribué contre sa déclaration : la base l'a journalisé
  "proposed_at": "2026-10-03T08:12:44.019Z",
  "previous": { // null quand rien n'était à remplacer
    "id": "uuid",
    "user_id": "uuid",
    "status": "declined", // son statut **avant** l'appel
    "notified": false
  },
  "schedule": { "id": "uuid", "status": "published" },
  "period": "2026-10"
}
```

Erreurs, forme `{"error": {"code", "message"}}` :

| Statut | `code`                       | Quand                                                              |
| ------ | ---------------------------- | ------------------------------------------------------------------ |
| 400    | `invalid_body`               | JSON invalide, `shift_id` ou `user_id` absent                      |
| 401    | `unauthenticated`            | Pas de jeton porteur, ou jeton qui n'identifie pas un utilisateur  |
| 403    | `not_admin`                  | L'appelant n'est pas admin **actif** de la caserne du créneau      |
| 403    | `station_suspended`          | Abonnement suspendu : la caserne est en lecture seule              |
| 404    | `shift_not_found`            | Créneau inconnu                                                    |
| 404    | `assignment_not_found`       | L'attribution à remplacer n'est pas sur ce créneau                 |
| 405    | `method_not_allowed`         | Autre verbe que POST                                               |
| 409    | `schedule_not_published`     | Planning en brouillon ou archivé. `status` accompagne l'erreur     |
| 409    | `already_assigned`           | Ce pompier tient déjà ce créneau                                   |
| 409    | `assignment_not_replaceable` | L'ancienne attribution a déjà été remplacée                        |
| 422    | `member_not_active`          | Le pompier visé n'est pas membre actif de la caserne               |
| 500    | `internal_error`             | Incident serveur                                                   |

### Ce qui n'est pas ici, et pourquoi

**L'annulation** est une fonction SQL appelable par un admin (`cancel_assignment(p_assignment,
p_reason)`), pas une Edge Function : il n'y a ni identité à établir autrement que par `auth.uid()`,
ni regroupement à faire, et `docs/SCHEMA.md § 7` n'en nomme aucune pour ce geste. Elle notifie le
membre **si sa garde était acceptée** ; une proposition retirée avant réponse ne prévient personne.

---

## `send-notification`

La pièce maîtresse des notifications : toutes les autres fonctions du produit l'appellent. Référence
: `docs/SCHEMA.md § 7`, `docs/WORKFLOWS.md § 6 et 8`, `docs/FIREBASE.md`.

### Deux façons de l'appeler

**Depuis la base** — un déclencheur ou une tâche planifiée :

```sql
select public.notify(
  'assignment_proposed',
  p_station    => '<uuid caserne>',
  p_payload    => jsonb_build_object('period', '2026-10'),
  p_recipients => jsonb_build_array(
    jsonb_build_object(
      'user_id', '<uuid membre>',
      'payload', jsonb_build_object('shifts', jsonb_build_array(
        jsonb_build_object('date', '2026-10-12', 'slot', 'night'))))));
```

La demande est écrite dans `notification_outbox` **dans la transaction métier**, puis postée par
pg_net. Si la fonction ne répond pas, la tâche `dispatch_notifications` reprend chaque minute. C'est
le chemin des tickets 015 et 022.

Le rappel de saisie du ticket 015 (`cron_availability_reminders`, migration `0016`) en est le
premier appelant réel, un appel par membre relancé :

```sql
select public.notify(
  'availability_reminder',
  p_user_ids   => array['<uuid membre>']::uuid[],
  p_station    => '<uuid caserne>',
  p_payload    => jsonb_build_object(
                    'period', '2026-10',
                    'deadline_at', '2026-09-15T21:59:59Z'),
  p_channels   => array['push', 'inapp'],        -- J-1 : array['email', 'inapp']
  p_dedupe_key => 'availability_reminder:<uuid caserne>:2026-10:j-3:<uuid membre>');
```

`p_dedupe_key` est ce qui tient la promesse « un seul envoi par membre et par échéance » : l'index
`notification_outbox_dedupe_uniq` refuse la seconde ligne, et `notify` rend alors l'identifiant de
celle qui est déjà en file, sans rien reposter. La caserne fait partie de la clé — un pompier peut
servir dans deux casernes et doit être relancé par chacune.

**Depuis une autre Edge Function** — `publish-schedule` (019) :

```
POST /functions/v1/send-notification
Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>
Content-Type: application/json
```

Pas de file, pas d'attente : la réponse porte le compte rendu, ce qui permet de le montrer à l'admin
qui vient de cliquer.

**La prise en charge est exclusive.** Une demande venue de la file passe par `notify_claim`, qui la
fait basculer de `pending` à `sending` : deux requêtes qui arrivent ensemble ne l'obtiennent qu'une
fois, la seconde répond `{"ok": true, "skipped": "already_processed"}` sans rien envoyer. Une
fonction qui meurt après la prise en charge laisse la ligne en `sending` ; la tâche
`dispatch_notifications` la ramène à `pending` quand le verrou de deux minutes expire.

### Corps de la requête

Deux formes. La courte, quand tout le monde reçoit la même chose :

```jsonc
{
  "type": "schedule_validated",
  "station_id": "uuid",
  "user_ids": ["uuid", "uuid"],
  "payload": { "period": "2026-10" },
  "channels": ["push", "inapp"] // facultatif
}
```

La groupée, quand chaque membre a sa propre charge utile — c'est celle d'une publication de planning
:

```jsonc
{
  "type": "assignment_proposed",
  "station_id": "uuid",
  "payload": { "period": "2026-10" }, // fusionné sous chaque destinataire
  "recipients": [
    { "user_id": "uuid", "payload": { "shifts": [{ "date": "2026-10-12", "slot": "night" }] } },
    { "user_id": "uuid", "payload": { "shifts": [{ "date": "2026-10-09", "slot": "day" }] } }
  ]
}
```

**Le même membre peut apparaître plusieurs fois** : pour les types regroupés
(`docs/WORKFLOWS.md § 8`), les entrées sont fusionnées et les créneaux dédoublonnés. Sept créneaux
pour un membre font **une** notification qui les résume, pas sept.

`channels` force les canaux ; absent, ce sont ceux du type (§ 8). `inapp` est toujours écrit quand
il figure dans les canaux, **avant tout envoi** : le centre de notifications (ticket 026) ne dépend
pas de la réussite de FCM.

### Charges utiles par type

| Type                    | Clés lues                                             | Exemple de titre                                                                   |
| ----------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `invitation`            | `station_name`, `inviter_name`                        | « Invitation à rejoindre CIS Saint-Martin »                                        |
| `availability_reminder` | `period`, `deadline_at` (ISO)                         | « Dispos d'octobre à saisir »                                                      |
| `assignment_proposed`   | `period`, `shifts[]`                                  | « Astreinte proposée le 12 octobre, nuit » / « 7 astreintes proposées en octobre » |
| `assignment_reminder`   | `period`, `shifts[]`                                  | « Réponse attendue : astreinte du 12 octobre, nuit »                               |
| `assignment_declined`   | `period`, `shifts[]`, `member_name`, `decline_reason` | « Astreinte refusée : 12 octobre, nuit »                                           |
| `assignment_changed`    | `period`, `shifts[]`                                  | « Astreinte modifiée : 12 octobre, nuit »                                          |
| `assignment_cancelled`  | `period`, `shifts[]`, `reason`                        | « Astreinte annulée : 12 octobre, nuit »                                           |
| `schedule_validated`    | `period`, `shifts[]`                                  | « Planning d'octobre validé »                                                      |
| `schedule_all_accepted` | `period`                                              | « Planning d'octobre complet »                                                     |
| `late_responders`       | `period`, `pending_count`, `hours`, `members[]`       | « 3 astreintes sans réponse »                                                      |

`shifts` est un tableau de `{ "date": "AAAA-MM-JJ", "slot": "day" | "night",
"assignment_id"? }`.
`period` est un `AAAA-MM` ; s'il manque, il est déduit du premier créneau. Toute clé absente dégrade
le texte, aucune ne fait échouer l'envoi : une notification pauvre vaut mieux qu'une notification
perdue.

### Liens profonds

`notifications.data.route`, exactement les quatre formes de `docs/WORKFLOWS.md § 8`, traduites côté
client par `lib/features/notifications/domain/destination_push.dart` :

| Type                                                               | `route`                     |
| ------------------------------------------------------------------ | --------------------------- |
| `availability_reminder`                                            | `/availability/<AAAA-MM>`   |
| `assignment_proposed`, `assignment_reminder`, `assignment_changed` | `/proposals`                |
| `assignment_cancelled`, `schedule_validated`                       | `/schedule/<AAAA-MM>`       |
| `assignment_declined`, `schedule_all_accepted`, `late_responders`  | `/admin/schedule/<AAAA-MM>` |
| `invitation`                                                       | `/connexion`                |

`/connexion` est une cinquième forme, que `destination_push.dart` ne connaît pas et rejette : un
push la portant n'ouvrirait rien. C'est sans conséquence parce que `invitation` ne part que par
courriel, où le lien est une adresse complète. Pour que ça le reste, **le canal `push` est refusé
pour ce type** (`invalid_channels`) : un appelant qui le forcerait s'en aperçoit au développement,
pas un pompier sur le terrain.

Le message FCM porte **`notification` et `data`**, et ce n'est pas de la ceinture-bretelles : au
premier plan `messagerie_push.dart` lit `notification.title` ; en arrière-plan le SDK affiche tout
seul et `web/firebase-messaging-sw.js` retrouve la destination dans `FCM_MSG.data.route` ; en repli
« data only », le même service worker lit `data.title`, `data.body` et `data.route`. Retirer l'un
des deux blocs casse l'un des trois chemins.

**`webpush.fcm_options.link` est une adresse complète, pas la route.** L'API v1 valide ce champ
comme une URL et impose `https` : un chemin relatif fait échouer le message entier par un
`400 INVALID_ARGUMENT`, que `classerErreurFcm` range en incident temporaire — donc aucun jeton
perdu, mais aucun push jamais délivré et tout en courriel de secours. Un silence parfait. L'adresse
est construite par `lienApplication()` (`APP_BASE_URL` + `APP_LINK_PATH`), et le champ est **omis**
si l'origine n'est pas en `https` — en développement, le push part donc sans lui, sans conséquence :
le service worker lit `data.route`.

### Réponse `200`

```jsonc
{
  "ok": true, // faux dès qu'un destinataire n'a rien reçu du tout
  "type": "assignment_proposed",
  "recipients": 2, // après regroupement
  "delivered": 2,
  "failed": 0,
  "outbox_id": "uuid", // null pour un appel direct
  "results": [
    {
      "user_id": "uuid",
      "ok": true,
      "title": "Astreinte proposée le 12 octobre, nuit",
      "body": "CIS Saint-Martin te propose une astreinte le lundi 12 octobre, de nuit. …",
      "route": "/proposals",
      "inapp": true,
      "notification_id": "uuid",
      "push": {
        "attempted": 2,
        "delivered": 1,
        "removed_tokens": 1,
        "skipped": null // "channel" | "push_disabled" | "no_token" | "unavailable"
      },
      "email": { "sent": true, "provider": "mailpit", "fallback": true }
    }
  ]
}
```

Erreurs, forme `{"error": {"code", "message"}}` : `method_not_allowed` (405), `unauthenticated`
(401), `invalid_body`, `invalid_type`, `invalid_recipients`, `invalid_channels` (400),
`internal_error` (500). Un destinataire en échec n'est pas une erreur de requête : il porte un
`code` dans son entrée de `results` (`profile_not_found`, `no_channel_delivered`).

### Les règles qui ne se voient pas

- **La ligne `inapp` est écrite en premier**, avant tout envoi. Une notification dont le push et le
  courriel échouent reste lisible dans l'application. Si cette écriture **échoue**, le destinataire
  n'est pas compté comme servi (`inapp: false`, `ok: false`, `code: "no_channel_delivered"`) : la
  demande n'est pas close en `sent` et la file la reprendra. Compter un envoi qu'on n'a pas fait est
  la seule façon de perdre une notification malgré la file.
- **`profiles.push_enabled` est respecté** pour tous les types sauf `assignment_proposed` :
  `docs/PRD.md § 6.5` en fait une notification non désactivable, et l'écran de réglage le dit au
  membre au lieu de le lui cacher. Un push coupé par le réglage **ne bascule pas** sur le courriel :
  « ne me préviens pas » ne veut pas dire « préviens-moi autrement ».
- **Le courriel est le repli** quand le membre n'a aucun appareil enregistré, ou quand aucun
  appareil n'a reçu le push. C'est ce qui fait qu'un pompier sans téléphone compatible apprend quand
  même qu'on lui propose une astreinte.
- **Un jeton définitivement rejeté est supprimé**, un échec passager ne l'est pas. Le 404
  `UNREGISTERED` et le 403 `SENDER_ID_MISMATCH` sont définitifs ; un `400
  INVALID_ARGUMENT` ne
  l'est que s'il désigne le jeton, parce que le même code sort d'un message mal formé — c'est-à-dire
  d'un bogue de notre côté, et supprimer tous les jetons de la caserne à la première régression
  serait une catastrophe.
- **Sans `FIREBASE_SERVICE_ACCOUNT`, le push est « indisponible », pas « en échec »** : rien n'est
  supprimé, l'incident est tracé dans `notifications.error`, le courriel prend le relais. C'est
  l'état du projet tant que `docs/FIREBASE.md § 5` n'a pas été fait.

---

## Tests

| Quoi                                                                         | Où                                                                      | En CI ? |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------------------- | ------- |
| Fonctions SQL `create_invitation` / `accept_invitation`                      | `supabase/tests/invitations_test.sql`, joué par `scripts/test_rls.sh`   | oui     |
| Couche HTTP des cinq Edge Functions                                          | `scripts/test_functions.sh`                                             | non     |
| Publication, gardes de transition, validation automatique, relance           | `supabase/tests/publication_test.sql`, joué par `scripts/test_rls.sh`   | oui     |
| Réattribution, annulation, garde des statuts terminaux                       | `supabase/tests/reattribution_test.sql`, joué par `scripts/test_rls.sh` | oui     |
| File d'attente et `notify(...)` (migration `0014`)                           | `supabase/tests/notifications_test.sql`, joué par `scripts/test_rls.sh` | oui     |
| Rappels de saisie (migration `0016`)                                         | `supabase/tests/availability_reminders_test.sql`, même script           | oui     |
| Libellés, regroupement, liens profonds, erreurs FCM, enchaînement d'un envoi | `deno test supabase/functions/tests/`                                   | oui     |

La CI (`.github/workflows/ci.yml`) démarre la pile sans `edge-runtime` ni `kong` : les Edge
Functions n'y sont pas joignables. Toute la logique de décision vit donc en SQL, où elle est testée
à chaque PR ; `scripts/test_functions.sh` couvre l'emballage HTTP et se lance à la main avant de
pousser une modification des fonctions.
