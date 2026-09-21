# Edge Functions — Astreinte SP

Deno / TypeScript, une fonction par dossier, la liste de référence est la section 7 de
[`docs/SCHEMA.md`](../../docs/SCHEMA.md). Le code partagé est dans `_shared/`.

| Fonction            | Ticket | Rôle                                                                                                                                                                             |
| ------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `invite-member`     | 006    | Un admin invite une ou plusieurs adresses dans sa caserne : ligne `invitations`, compte `auth.users` si l'adresse est inconnue, courriel d'invitation, **plafond horaire** (038) |
| `accept-invitation` | 006    | L'invité connecté échange son jeton contre une `memberships` active                                                                                                              |
| `publish-schedule`  | 019    | Publie un planning : statut, `proposed_at` de chaque attribution, puis **une** notification par membre                                                                           |
| `reassign-shift`    | 020    | Réattribue un créneau d'un planning publié : nouvelle attribution proposée, ancienne remplacée, **une** notification au nouveau membre                                           |
| `auto-propose`      | 018    | Applique un remplissage automatique du brouillon : le plan vient de l'application (tri du ticket 017), la base revérifie chaque ligne et écarte celles qui ne passent pas        |
| `send-notification` | 025    | Écrit la ligne interne, envoie le push FCM et le courriel d'une notification, pour un ou plusieurs membres à la fois                                                             |
| `create-checkout`   | 029    | État de l'abonnement d'une caserne, ouverture d'une session de paiement, ouverture du portail de gestion — réservé aux administrateurs de la caserne                             |
| `stripe-webhook`    | 029    | Reçoit les événements du prestataire de paiement, **vérifie leur signature**, met à jour `subscriptions`                                                                         |
| `delete-account`    | 007    | Le membre supprime son compte : profil anonymisé en « Membre supprimé », appartenances désactivées, attributions passées conservées                                              |
| `export-user-data`  | 034    | Le membre récupère en JSON tout ce que l'application sait de lui, et rien de ce qu'elle sait des autres                                                                          |

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
- **La caserne nommée par un événement n'est jamais crue sur parole.** La signature établit que
  l'appel vient du prestataire, pas que `client_reference_id` désigne la bonne caserne — c'est un
  champ que l'on peut poser depuis une URL. `subscription_sync` (migration `0023`) refuse
  (`customer_mismatch`) dès que le client et la caserne ne vont pas déjà ensemble, dans les deux
  sens. Sans ce contrôle, l'administrateur d'une caserne ouvrirait le portail d'une autre.
- **Un événement déjà traité ne se réapplique pas.** `stripe_events` (`docs/SCHEMA.md § 2.17`) en
  porte l'identifiant en clé primaire : un rejeu dans la fenêtre de tolérance rend `duplicate` et
  n'écrit rien. Sans quoi un `invoice.payment_failed` capté puis réémis après une régularisation
  remettrait en impayé une caserne à jour.
- **Un événement de paiement non signé n'est jamais lu.** `stripe-webhook` est publique par nature :
  Stripe l'appelle sans jeton, depuis Internet. La **signature** (`Stripe-Signature`, HMAC-SHA256 du
  **corps brut** avec `STRIPE_WEBHOOK_SECRET`, fenêtre de cinq minutes) est donc tout ce qui
  distingue un vrai événement d'un faux — et un faux vaudrait « cette caserne est active » sans
  qu'un euro ait circulé, ou « cette caserne est suspendue », ce qui mettrait tous ses pompiers en
  lecture seule. Le corps n'est **pas** analysé avant d'être authentifié, et tant qu'aucun secret
  n'est posé **tout est refusé** en 503 : le repli n'est pas « accepter sans vérifier ».
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
| `STRIPE_SECRET_KEY`        | —                                               | Clé secrète du compte Stripe (`sk_live_…`). Ne quitte jamais le serveur (`docs/STRIPE.md § 3`)                                                                                                                        |
| `STRIPE_PRICE_MONTHLY`     | —                                               | Identifiant du tarif mensuel (`price_…`)                                                                                                                                                                              |
| `STRIPE_PRICE_YEARLY`      | —                                               | Identifiant du tarif annuel (`price_…`)                                                                                                                                                                               |
| `STRIPE_WEBHOOK_SECRET`    | —                                               | Secret de signature du point de terminaison (`whsec_…`). **Absent : `stripe-webhook` refuse tout en 503**, et `create-checkout` répond `stripe_not_configured`                                                        |
| `STRIPE_AMOUNT_MONTHLY`    | `1200`                                          | Le montant **affiché** par l'écran, en centimes. Séparé du tarif Stripe : un prix ne se modifie pas chez Stripe, il se remplace                                                                                       |
| `STRIPE_AMOUNT_YEARLY`     | `12000`                                         | Idem pour l'annuel. L'écran en déduit l'économie annoncée                                                                                                                                                             |
| `STRIPE_CURRENCY`          | `eur`                                           | Le symbole affiché à côté des montants                                                                                                                                                                                |
| `APP_SUBSCRIPTION_PATH`    | `/#/admin/abonnement`                           | Chemin de l'écran d'abonnement, base des deux adresses de retour de Stripe (`?paiement=ok`, `?paiement=annule`). Même logique que `APP_INVITE_PATH`                                                                   |

En production :

```sh
supabase secrets set APP_BASE_URL=https://app.astreinte-sp.fr
supabase secrets set APP_INVITE_PATH='/#/invite/{token}'
supabase secrets set MAIL_FROM='Astreinte SP <invitations@astreinte-sp.fr>'
supabase secrets set RESEND_API_KEY=re_…
supabase secrets set APP_LINK_PATH='/#{route}'
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat chemin/vers/le-compte-de-service.json)"
supabase secrets set STRIPE_SECRET_KEY=sk_live_…
supabase secrets set STRIPE_PRICE_MONTHLY=price_…
supabase secrets set STRIPE_PRICE_YEARLY=price_…
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_…
supabase secrets set APP_SUBSCRIPTION_PATH='/#/admin/abonnement'
```

Les quatre secrets Stripe et ce qu'il faut créer dans le tableau de bord pour les obtenir :
**`docs/STRIPE.md`**. Tant qu'un seul manque, l'abonnement est déclaré « pas encore ouvert » et les
casernes restent en essai — l'application, elle, fonctionne entièrement.

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
`account_failed`, `rate_limited`, `internal_error`.

### Le plafond de débit _(ticket 038)_

Vingt adresses par appel bornaient un appel, pas leur nombre : un administrateur — ou un jeton
d'administrateur volé — envoyait autant de courriels qu'il voulait, à des adresses qu'il
choisissait, depuis le domaine d'envoi du produit. `create_invitation` (migration `0032`) compte
désormais les courriels **réellement partis**, création et renvoi confondus, par caserne et par
heure. Le plafond se règle dans `stations.settings.invitation_hourly_limit` (1 à 500, **60** par
défaut) ; le super-administrateur a le sien, **200 par heure et par compte**, toutes casernes
confondues.

Une adresse refusée porte le code `rate_limited`, une **phrase affichable qui dit quand réessayer**,
et les faits :

```jsonc
{
  "email": "recrue@exemple.fr",
  "status": "error",
  "code": "rate_limited",
  "message": "Limite d'invitations atteinte (60 par heure pour cette caserne). Réessaie dans 13 minutes.",
  "rate_limit": {
    "scope": "station", // "station" | "actor" (super-administrateur)
    "limit": 60,
    "used": 60,
    "remaining": 0,
    "window_minutes": 60,
    "retry_at": "2026-09-21T15:12:00+00:00",
    "retry_after_seconds": 730
  }
}
```

Deux comportements de lot à connaître côté client :

- **Vingt adresses comptent pour vingt.** Le compteur est par adresse, pas par appel.
- Dès qu'une adresse est refusée pour cette raison, **les suivantes ne sont pas tentées** : le
  budget est épuisé pour toute la caserne, et vingt allers-retours pour s'entendre dire vingt fois
  la même chose ne servent personne. Elles portent le même code et le même message.

Quand **aucune** adresse n'est passée, la réponse est un refus global `429` plutôt qu'une liste ; un
lot à moitié envoyé garde sa liste, sinon l'administrateur réessaierait des adresses déjà invitées.
Le corps est la forme d'erreur habituelle, enrichie des mêmes faits :

```jsonc
{
  "error": {
    "code": "rate_limited",
    "message": "Limite d'invitations atteinte (60 par heure pour cette caserne). Réessaie dans 13 minutes.",
    "scope": "station",
    "limit": 60,
    "used": 60,
    "remaining": 0,
    "window_minutes": 60,
    "retry_at": "…",
    "retry_after_seconds": 730
  }
}
```

Le message est composé côté serveur (`_shared/invitation_rate_limit.ts`) parce que le délai change à
chaque seconde : **affiche `message` tel quel** plutôt qu'un texte constant associé au code. Le
dépassement est inscrit dans `audit_log` sous `invitation.rate_limited`, une fois par caserne et par
fenêtre.

Erreurs de requête, forme `{"error": {"code", "message"}}` :

| Statut | `code`               | Quand                                                                                 |
| ------ | -------------------- | ------------------------------------------------------------------------------------- |
| 400    | `invalid_body`       | JSON invalide, `station_id` absent, aucune adresse, plus de 20 adresses, rôle inconnu |
| 401    | `unauthenticated`    | Pas de jeton porteur, ou jeton qui n'identifie pas un utilisateur                     |
| 403    | `not_admin`          | L'appelant n'est pas admin **actif** de `station_id`                                  |
| 403    | `station_suspended`  | Abonnement suspendu : la caserne est en lecture seule                                 |
| 429    | `rate_limited`       | Plafond horaire d'invitations atteint, et aucune adresse du lot n'est passée          |
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

## `delete-account`

La sortie définitive d'un membre. Référence : `docs/PRD.md § 8` (RGPD), `docs/SCHEMA.md § 7`,
migration `0026`, `design/007-profil.md § 5.3` et `§ 5.4`, ticket 007.

```
POST /functions/v1/delete-account
apikey: <clé anon>
Authorization: Bearer <access_token du membre>
```

**Aucun corps, et c'est une règle de sécurité, pas une économie.** L'identité vient du JWT, vérifiée
auprès de GoTrue par `caller()`. Un `user_id` accepté dans la requête ferait de cette fonction une
porte pour supprimer le compte d'un autre — `verify_jwt` ne dit rien du _qui_, la clé anon étant
elle-même un JWT valide et publique.

Réponse `200` :

```jsonc
{
  "ok": true,
  "stations": ["uuid"], // les casernes où l'appartenance vient de passer « disabled »
  "memberships": 1
}
```

Deux temps, dans cet ordre :

1. `delete_own_account` (SQL, atomique, migration `0026`) — le profil devient « Membre supprimé »,
   adresse non routable, téléphone effacé, push coupé ; les appartenances passent `disabled` et
   perdent leur surnom ; disponibilités, préférences de charge, appareils, notifications reçues et
   invitations en attente à son adresse sont supprimés. **Les attributions passées restent** : c'est
   l'histoire de la caserne (`docs/PRD.md § 7` règle 6), et elles se lisent désormais sous la
   mention neutre.
2. `auth.admin.deleteUser` — le compte d'authentification est supprimé. Il ne l'était pas avant,
   parce que `profiles.id` ne référence plus `auth.users` (migration `0026`) : c'est exactement ce
   qui permet au profil anonymisé de survivre.

Si le second temps échoue, la réponse est `500 auth_delete_failed` avec `anonymized: true` : rien de
nominatif n'est resté en base, mais l'accès n'est pas fermé et il faut le signaler. L'ordre inverse
produirait la panne symétrique et pire — un compte supprimé, un nom en clair, et plus personne pour
le nettoyer.

Erreurs :

| Statut | `code`               | Détails joints à `error` |
| ------ | -------------------- | ------------------------ |
| 401    | `unauthenticated`    | —                        |
| 405    | `method_not_allowed` | —                        |
| 409    | `last_admin`         | `station`                |
| 409    | `profile_missing`    | —                        |
| 500    | `auth_delete_failed` | `anonymized: true`       |
| 500    | `internal_error`     | —                        |

`last_admin` est la seule erreur métier attendue : une caserne garde au moins un administrateur
actif (même règle que `memberships_guard_admin`, migration `0010`). L'écran nomme la caserne et dit
la sortie — « nomme quelqu'un d'abord ».

**L'export RGPD (`export-user-data`, ci-dessous) reste une étape séparée, et volontairement
facultative.** L'écran le propose juste avant le bouton rouge (`design/034-rgpd-export.md § 5.2`),
mais `delete-account` ne l'appelle pas et ne l'attend pas : forcer un téléchargement avant de
partir, c'est retenir quelqu'un qui a décidé.

---

## `export-user-data`

Le droit d'accès et de portabilité, en un fichier. Référence : `docs/PRD.md § 8` (RGPD),
`docs/SCHEMA.md § 7`, migration `0027`, `docs/RGPD.md`, `design/034-rgpd-export.md`, ticket 034.

```
POST /functions/v1/export-user-data
apikey: <clé anon>
Authorization: Bearer <access_token du membre>
```

**Aucun corps, et un corps envoyé quand même est ignoré.** Même règle que `delete-account`, pour un
enjeu symétrique : celle-ci ne détruit rien, elle **livre** le dossier complet d'une personne —
profil, adresse, téléphone, disponibilités, astreintes. Un `user_id` cru sur parole en ferait un
annuaire. L'identité vient de `caller()`, et `export_own_data` est fermée à `anon` comme à
`authenticated` (`revoke` nommé, migration `0027`) : la RPC directe répond `42501`.

Réponse `200` :

```jsonc
{
  "export": {
    "produit": "Astreinte SP",
    "version_format": 1,
    "genere_le": "2026-09-21T05:45:34.644Z",
    "personne": "uuid",
    "a_lire": "…",
    "inventaire": { "profil": 1, "disponibilites": 72, "attributions": 1, … }
  },
  "donnees": {
    "compte": { … },          // auth.users, ajouté par la fonction
    "profil": { … },          // les douze sections de export_own_data
    "casernes": [ … ],
    "appartenances": [ … ],
    "disponibilites": [ … ],
    "preferences_de_charge": [ … ],
    "attributions": [ … ],
    "notifications": [ … ],
    "appareils": [ … ],
    "invitations_recues": [ … ],
    "invitations_envoyees": [ … ],
    "actes_administratifs_me_concernant": [ … ],
    "mes_actes_administratifs": [ … ],
    "editeur_du_produit": false
  }
}
```

`inventaire` donne le compte de chaque section, y compris quand elle est vide : une section absente
et une section vide ne disent pas la même chose, et c'est ce qui permet de vérifier un export sans
le relire en entier.

**Rien d'une autre personne n'entre dans ce fichier.** C'est la deuxième règle de la fonction SQL,
et elle vaut un export livré : l'administrateur qui a saisi une disponibilité à ma place est un
booléen (`saisie_par_un_administrateur`), l'attribution qui a remplacé la mienne est un booléen
(`remplacee`), l'adresse que j'ai invitée est masquée (`mask_email`), le `data` d'une ligne d'audit
est filtré par liste blanche, et le jeton d'un appareil est tronqué à ses douze derniers caractères.
Les tables écartées et la raison de chacune sont en tête de la migration `0027` et dans
`docs/RGPD.md`.

**La fonction n'ajoute qu'une chose au SQL** : la section `compte` (date de création, dernière
connexion, confirmation de l'adresse), lue par `auth.admin.getUserById`. Le SQL du projet ne touche
pas au schéma `auth` — c'est la règle du `docs/SCHEMA.md § 2.2`, où `profiles.email` est dupliqué
pour cette raison. Si la lecture échoue, `compte` vaut `null` et le reste de l'export part quand
même : un profil anonymisé survit à son compte d'authentification (migration `0026`).

**Le fichier n'est pas fabriqué ici.** La réponse est du JSON, pas une pièce jointe : c'est le
client qui compose le nom et déclenche l'enregistrement (`lib/core/plateforme/telechargement.dart`).
Servir un `Content-Disposition` obligerait le navigateur à visiter l'URL lui-même, donc à porter le
jeton d'accès **dans l'URL**, donc dans l'historique et dans les journaux de la passerelle.

Erreurs :

| Statut | `code`               | Détails joints à `error` |
| ------ | -------------------- | ------------------------ |
| 401    | `unauthenticated`    | —                        |
| 405    | `method_not_allowed` | —                        |
| 409    | `profile_missing`    | —                        |
| 500    | `internal_error`     | —                        |

---

## `ics-feed`

Le flux calendrier d'un membre, pour Google Agenda, Apple Calendar et Outlook. Référence :
`docs/PRD.md § 5.5`, `docs/SCHEMA.md § 7`, migration `0029`, `design/028-export-ics.md`, ticket 028.

```
GET /functions/v1/ics-feed/<jeton>.ics      ← forme canonique
GET /functions/v1/ics-feed?token=<jeton>    ← acceptée aussi
```

**Aucun en-tête d'authentification, et c'est la nature de la fonction.** Ses appelants ne sont pas
l'application : ce sont les serveurs de Google, d'Apple et de Microsoft, qui rechargent l'adresse
toutes les heures. Aucun ne sait porter un jeton d'accès Supabase, aucun ne renouvelle une session.
Le secret est donc dans l'URL, et `verify_jwt = false` — même raisonnement que `stripe-webhook`, où
c'est la signature qui fait office de portier.

`<jeton>` est `profiles.ics_token` (migration `0029`) : 24 octets tirés au sort, rendus en 48
caractères hexadécimaux. Le suffixe `.ics` est optionnel pour le serveur mais recommandé dans le
lien qu'on distribue — plusieurs clients, Outlook en tête, décident du type de contenu d'après l'URL
avant de lire l'en-tête.

Réponse `200` : `text/calendar; charset=utf-8`, `Cache-Control: no-store`,
`Content-Disposition: inline; filename="astreintes.ics"`.

```
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Astreinte SP//Flux calendrier//FR
METHOD:PUBLISH
X-WR-CALNAME:Mes astreintes
REFRESH-INTERVAL;VALUE=DURATION:PT6H
BEGIN:VEVENT
UID:<id de l'attribution>@astreinte-sp
DTSTART:20261114T060000Z
DTEND:20261114T180000Z
SUMMARY:Astreinte jour — CIS Saint-Martin
DESCRIPTION:Créneau de jour\, de 07:00 à 19:00. Astreinte acceptée.
LOCATION:CIS Saint-Martin
STATUS:CONFIRMED
END:VEVENT
END:VCALENDAR
```

**Cette adresse voyage** — elle finit collée dans Google Agenda, donc recopiée sur des serveurs qui
ne sont pas les nôtres. Ce qui la rend sûre n'est pas ici mais en base :

- `ics_feed_events` ne rend que les astreintes **acceptées** de son porteur, sur un planning publié
  ou validé, dans les casernes où il est **encore actif**. Aucune jointure ne mène à une autre
  personne : ni le nom d'un équipier, ni une adresse, ni rien d'une autre caserne.
- Un jeton **régénéré** (`rotate_ics_token`) ne désigne plus personne à la transaction suivante :
  l'ancienne adresse répond `404`, sans délai ni liste de révocation.
- Une appartenance **désactivée** vide le flux des astreintes de cette caserne. Le flux continue de
  répondre `200` avec un calendrier sans événement : un agenda qui reçoit une erreur clignote, ce
  qui n'est pas ce qu'on veut dire à quelqu'un dont la situation est parfaitement normale.
- Une caserne **suspendue** continue, elle, d'alimenter le flux. `docs/PRD.md § 6.6` : « suspendu :
  lecture seule pour tous », et un flux calendrier est une lecture. Le vider ferait croire à des
  gardes annulées.
- La fonction ne pose **aucun en-tête CORS** : un agenda lit depuis son serveur, il n'a pas
  d'origine à faire valoir. (La passerelle ajoute le sien, comme devant toutes les fonctions.)

**Les heures sont résolues en UTC**, dans le fuseau de la caserne, à la date de chaque garde
(`ics-feed/calendrier.ts`) : le changement d'heure est compris sans qu'aucun bloc `VTIMEZONE` ait à
être maintenu, et un `DTSTART` flottant ne glisse pas avec l'appareil qui l'affiche. La nuit est
l'intervalle complémentaire du jour (`day_end → day_start` du lendemain), exactement comme
`HeuresAffichage` côté application.

L'`UID` est celui de l'attribution : le fichier unique téléchargé depuis le détail d'une astreinte
(côté Dart, `lib/features/astreintes/domain/ics_astreinte.dart`) porte le même. Qui a fait les deux
gestes n'a pas deux lignes dans son agenda.

Erreurs — en **texte brut**, parce que personne ne les lira : l'appelant est un robot.

| Statut | Corps                                    | Quand                                           |
| ------ | ---------------------------------------- | ----------------------------------------------- |
| 404    | `Lien d'abonnement invalide.`            | pas de jeton dans l'URL, ou forme invalide      |
| 404    | `Lien d'abonnement invalide ou révoqué.` | jeton inconnu **ou** régénéré — indistinguables |
| 405    | `Méthode non autorisée.`                 | autre chose qu'un `GET` ou un `HEAD`            |
| 500    | `Erreur serveur.`                        | la base n'a pas répondu                         |

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

1. verrou de ligne sur le planning, pour que deux adjoints ne pourvoient pas deux fois la même place
   ;
2. la nouvelle attribution, `proposed` et **déjà horodatée** (`proposed_at`), avec `created_by` et
   `was_available` posés par la fonction — sous le rôle de service, le déclencheur
   `assignments_trace_disponibilite` rend la ligne telle quelle ;
3. l'ancienne, s'il y en a une : `accepted → replaced`, `proposed → replaced`, et **`declined` et
   `cancelled` restent tels quels** — un statut terminal est l'histoire de la caserne, et il a déjà
   été notifié sous ce nom. Dans les quatre cas, `replaced_by` pointe la nouvelle ;
4. les **demandes de notification**, dans la même transaction, par `notify(...)`. Le motif envoyé au
   pompier remplacé est un **code** (`reason_code`), traduit en français par
   `_shared/notification_content.ts` : le texte des notifications vit à un seul endroit ;
5. `audit_log` (`assignment.reassigned`) et `schedule_reevaluer`, qui ramène un planning validé en
   `published` quand une acceptation vient de disparaître.

`previous_assignment_id` est facultatif : laissé vide sur un créneau qui porte un trou non encore
comblé — un refus ou une annulation —, la base rattache la nouvelle attribution au **plus ancien**
d'entre eux. Seule une attribution déjà `replaced` est refusée : elle a trouvé son remplaçant.

### Une réattribution remplace, elle n'ajoute pas

Le créneau ne gagne jamais une place : il en change le titulaire. Deux appels identiques, ou deux
adjoints simultanés, ne produisent donc qu'**une** attribution active et **une** notification — le
verrou sérialise, et le compte des places décide. Renforcer un créneau publié se dit autrement : on
augmente son effectif requis, et le panneau le propose juste au-dessus de la liste des candidats. Le
dire ainsi vaut mieux que de laisser une réattribution faire en douce ce qu'un réglage dit en clair.
Vérifié à deux sessions réelles par `scripts/test_concurrence.sh`.

### Pourquoi elle n'appelle pas `send-notification`, contrairement à `publish-schedule`

Une publication groupe trente pompiers et sept créneaux chacun : le regroupement se fait en SQL,
l'envoi part ensuite de l'Edge Function, **après** la transaction, pour ne pas pouvoir défaire une
publication acquise. Une réattribution vise **une** personne et **un** créneau : il n'y a rien à
grouper, et la file de `notify(...)` — avec son rejeu par `cron_dispatch_notifications` — garantit
l'envoi même si le processus meurt entre la transaction et l'appel HTTP. Un pompier qui ignore qu'il
est d'astreinte est le seul défaut que ce ticket n'a pas le droit de produire.

### Combien de notifications

| Ce que remplace la réattribution | Nouveau membre        | Ancien membre                     |
| -------------------------------- | --------------------- | --------------------------------- |
| un refus (`declined`)            | `assignment_proposed` | **rien** — c'est lui qui a refusé |
| une annulation (`cancelled`)     | `assignment_proposed` | rien — il a déjà été prévenu      |
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

| Statut | `code`                       | Quand                                                             |
| ------ | ---------------------------- | ----------------------------------------------------------------- |
| 400    | `invalid_body`               | JSON invalide, `shift_id` ou `user_id` absent                     |
| 401    | `unauthenticated`            | Pas de jeton porteur, ou jeton qui n'identifie pas un utilisateur |
| 403    | `not_admin`                  | L'appelant n'est pas admin **actif** de la caserne du créneau     |
| 403    | `station_suspended`          | Abonnement suspendu : la caserne est en lecture seule             |
| 404    | `shift_not_found`            | Créneau inconnu                                                   |
| 404    | `assignment_not_found`       | L'attribution à remplacer n'est pas sur ce créneau                |
| 405    | `method_not_allowed`         | Autre verbe que POST                                              |
| 409    | `schedule_not_published`     | Planning en brouillon ou archivé. `status` accompagne l'erreur    |
| 409    | `already_assigned`           | Ce pompier tient déjà ce créneau                                  |
| 409    | `assignment_not_replaceable` | L'ancienne attribution a déjà été remplacée                       |
| 422    | `member_not_active`          | Le pompier visé n'est pas membre actif de la caserne              |
| 500    | `internal_error`             | Incident serveur                                                  |

### Ce qui n'est pas ici, et pourquoi

**L'annulation** est une fonction SQL appelable par un admin
(`cancel_assignment(p_assignment,
p_reason)`), pas une Edge Function : il n'y a ni identité à
établir autrement que par `auth.uid()`, ni regroupement à faire, et `docs/SCHEMA.md § 7` n'en nomme
aucune pour ce geste. Elle notifie le membre **si sa garde était acceptée** ; une proposition
retirée avant réponse ne prévient personne.

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

#### Le mode « trace » d'un envoi abandonné (ticket 040)

Une troisième forme, que **seule la base produit**. Quand une demande de `notification_outbox` a
épuisé ses cinq tentatives, `cron_dispatch_notifications` l'abandonne et `notify_trace_echec`
(migration `0022`) remet la même demande en file avec une clé de plus dans la charge utile commune :

```jsonc
{
  "type": "assignment_proposed",
  "station_id": "uuid",
  "channels": ["inapp"],
  "payload": {
    "period": "2026-10",
    "delivery_failure": {
      "outbox_id": "uuid", // la demande abandonnée
      "attempts": 5,
      "error": "abandon après 5 tentatives sans réponse" // motif technique
    }
  },
  "recipients": [{ "user_id": "uuid", "payload": { "shifts": [/* … */] } }]
}
```

`delivery_failure` **force le canal `inapp` seul** — rien n'est renvoyé, ni push sur un canal qui
vient d'échouer cinq fois, ni courriel de rattrapage — et fait écrire la ligne `notifications` en
échec : `delivered = false`, `sent_at` nul, `error` renseignée. C'est cette colonne, et sa seule
présence, que le centre de notifications traduit en « L'envoi a échoué, tu ne l'as peut-être pas
reçue » (ticket 026).

**Pourquoi la base ne l'écrit pas elle-même** : le titre et le corps sortent de `construireContenu`,
comme pour n'importe quel envoi. Le membre lit « Astreinte proposée le 12 octobre, nuit », pas « une
notification a échoué ». Recopier ces phrases en plpgsql aurait donné deux endroits où le même
français vieillirait séparément.

La réponse porte `"delivery_failure": true` au premier niveau. Une marque présente mais vide laisse
quand même `error` renseignée (`"delivery_failure"`), sans quoi la ligne ressemblerait à un envoi
réussi et la mention disparaîtrait.

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

- **Une demande abandonnée après cinq tentatives laisse une ligne**, et c'est le destinataire qu'on
  prévient, pas les administrateurs (décision du ticket 026). Il est celui qui perd quelque chose ;
  alerter un chef de centre transformerait un incident technique en tâche humaine chez des
  bénévoles. Voir « Le mode trace » plus haut.
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

| Quoi                                                                            | Où                                                                      | En CI ? |
| ------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | ------- |
| Fonctions SQL `create_invitation` / `accept_invitation`                         | `supabase/tests/invitations_test.sql`, joué par `scripts/test_rls.sh`   | oui     |
| Couche HTTP des Edge Functions                                                  | `scripts/test_functions.sh`                                             | non     |
| Export RGPD : sections, cloisonnement, fermeture aux clients (migration `0027`) | `supabase/tests/export_rgpd_test.sql`, joué par `scripts/test_rls.sh`   | oui     |
| Suppression de compte (migration `0026`)                                        | `supabase/tests/suppression_compte_test.sql`, même script               | oui     |
| Publication, gardes de transition, validation automatique, relance              | `supabase/tests/publication_test.sql`, joué par `scripts/test_rls.sh`   | oui     |
| Réattribution, annulation, garde des statuts terminaux                          | `supabase/tests/reattribution_test.sql`, joué par `scripts/test_rls.sh` | oui     |
| File d'attente, `notify(...)` et trace d'un abandon (migrations `0014`, `0022`) | `supabase/tests/notifications_test.sql`, joué par `scripts/test_rls.sh` | oui     |
| Rappels de saisie (migration `0016`)                                            | `supabase/tests/availability_reminders_test.sql`, même script           | oui     |
| Libellés, regroupement, liens profonds, erreurs FCM, enchaînement d'un envoi    | `deno test supabase/functions/tests/`                                   | oui     |

La CI (`.github/workflows/ci.yml`) démarre la pile sans `edge-runtime` ni `kong` : les Edge
Functions n'y sont pas joignables. Toute la logique de décision vit donc en SQL, où elle est testée
à chaque PR ; `scripts/test_functions.sh` couvre l'emballage HTTP et se lance à la main avant de
pousser une modification des fonctions.

---

## `create-checkout`

L'unique porte de l'écran « Abonnement » (ticket 029). Référence : `docs/SCHEMA.md § 7 et 2.13`,
`docs/PRD.md § 6.6`, `docs/STRIPE.md`, `design/029-stripe-abonnement.md`, migration `0023`.

```
POST /functions/v1/create-checkout
apikey: <clé anon>
Authorization: Bearer <access_token de l'admin>
Content-Type: application/json

{ "station_id": "uuid", "action": "state" | "checkout" | "portal", "plan": "monthly" | "yearly" }
```

`action` vaut `state` par défaut. `plan` n'est lu que par `checkout`.

### Trois actions, une seule fonction

`docs/SCHEMA.md § 7` n'en nomme qu'une, et c'est volontairement resté une : les trois gestes
partagent **exactement** le même contrôle de droits — administrateur **actif** de la caserne visée,
établi par une requête sur `memberships`, jamais par le corps de la requête. Trois fonctions
auraient donné trois copies de cette vérification, c'est-à-dire trois endroits où elle peut
diverger. Or l'une d'elles ouvre le **portail**, où l'on résilie.

**`state`** — ce que l'écran affiche. **Elle répond même sans compte Stripe**, et c'est tout son
intérêt : l'écran annonce le tarif au lieu de planter.

```jsonc
{
  "ok": true,
  "station_id": "uuid",
  "configured": false, // les quatre secrets sont-ils posés ?
  "prices": { "monthly": 1200, "yearly": 12000, "currency": "eur" }, // en centimes
  "portal_available": false, // compte configuré **et** client déjà créé
  "subscription": { // null si la caserne n'a pas encore de ligne
    "status": "trialing",
    "plan": null,
    "trial_ends_at": "2026-11-20T09:12:04.118Z",
    "current_period_end": null,
    "has_customer": false
  }
}
```

**`checkout`** — crée le client chez Stripe **s'il n'existe pas**, le retient en base
(`subscription_set_customer`, migration `0023`) **avant** d'ouvrir la session, puis rend l'adresse
de redirection. L'ordre compte : une session ouverte avant que le client soit retenu laisserait, au
premier incident réseau, un client orphelin chez Stripe — et la tentative suivante en créerait un
second, que le portail ne retrouverait pas. La clé d'idempotence est la caserne : deux appuis à une
seconde d'intervalle rendent le **même** client.

```jsonc
{
  "ok": true,
  "action": "checkout",
  "plan": "monthly",
  "session_id": "cs_test_…",
  "url": "https://checkout.stripe.com/c/pay/…"
}
```

La session porte `client_reference_id = station_id` et `metadata.station_id`, recopiées sur
l'abonnement créé : **c'est ce qui permet au webhook de savoir à quelle caserne appartient le
premier événement**, puis aux suivants de la retrouver par `stripe_customer_id`.

**`portal`** — ouvre le portail client (carte, factures, résiliation). Même forme de réponse.

Erreurs, forme `{"error": {"code", "message"}}` :

| Statut | `code`                  | Quand                                                                      |
| ------ | ----------------------- | -------------------------------------------------------------------------- |
| 400    | `invalid_body`          | JSON invalide, `station_id` absent, action inconnue                        |
| 400    | `invalid_plan`          | `checkout` sans formule, ou formule inconnue                               |
| 401    | `unauthenticated`       | Pas de jeton porteur, ou jeton qui n'identifie pas un utilisateur          |
| 403    | `not_admin`             | L'appelant n'est pas admin **actif** de `station_id`                       |
| 405    | `method_not_allowed`    | Autre verbe que POST                                                       |
| 409    | `already_subscribed`    | Un abonnement **vit déjà** : carte et formule se changent dans le portail  |
| 409    | `no_customer`           | `portal` sur une caserne qui n'a jamais souscrit                           |
| 500    | `internal_error`        | Incident serveur                                                           |
| 502    | `stripe_error`          | Stripe a refusé ou n'a pas répondu. Le détail reste au journal             |
| 503    | `stripe_not_configured` | Aucun compte Stripe branché. **Ce n'est pas une panne** (`docs/STRIPE.md`) |

**Une caserne inconnue rend `not_admin`, pas 404.** Dire « caserne inconnue » à qui n'y a pas droit
lui apprendrait qu'elle existe. Et un `station_id` **mal formé** rend 400, pas 500 : il partait dans
une requête PostgREST où il devenait une erreur traduite en incident serveur — un incident annoncé
pour une faute de frappe.

**Tout le contrôle de droits tient dans `create-checkout/acces.ts`**, une fonction pure testée à
chaque PR (`tests/stripe_acces_test.ts`). C'est la règle la plus coûteuse à perdre au premier
refactor — elle décide qui engage une dépense au nom d'une caserne, et qui ouvre le portail où l'on
résilie —, et une règle qui ne casse aucun test quand on la retire n'est pas une règle. La couche
HTTP, elle, est vérifiée par `scripts/test_functions.sh`, qui demande une pile locale et ne tourne
donc pas en CI.

### Le garde-fou du doublon porte sur l'abonnement, pas sur le statut

Le cas qui compte n'est pas la caserne `active` — celle-là ne voit même pas le bouton. C'est la
caserne **en retard de paiement**, cas le plus banal qui soit : une carte qui expire. Son statut
n'est pas `active`, donc une règle posée sur le seul statut `active` la laisse passer — et elle
repart avec un **second** abonnement, prélevé en parallèle du premier, pendant que le premier
continue ses relances. `subscriptions.stripe_subscription_id` ne peut en désigner qu'un : l'autre
devient invisible, et personne ne le résilie.

`checkout` est donc refusé dès qu'un abonnement existe **et vit encore** — `active`, `past_due`,
`trialing` ou `suspended`. Une caserne **résiliée** peut en reprendre un : c'est un client qui
revient, rien ne se dédouble. Une carte qui a expiré se change dans le **portail**, et c'est là que
le message envoie.

---

## `stripe-webhook`

La seule porte par laquelle un paiement change un statut. Référence : `docs/SCHEMA.md § 7 et 2.13`,
`docs/STRIPE.md § 4`, migration `0023`.

```
POST /functions/v1/stripe-webhook
Stripe-Signature: t=1730000000,v1=5257a869e7…
Content-Type: application/json
```

`verify_jwt = false`, et il ne peut pas en être autrement : Stripe appelle sans jeton.

### Avant la signature : un plafond

Le corps est lu par `lireCorpsBorne` (`_shared/http.ts`), qui refuse au-delà d'**un mégaoctet** — un
événement réel dépasse rarement 100 ko. Cette lecture arrive **avant toute authentification**, et il
ne peut pas en être autrement : il faut le corps pour vérifier la signature. Sans plafond, un
anonyme qui connaît l'adresse fait allouer autant de mémoire qu'il veut, puis fait calculer
l'empreinte HMAC de l'ensemble. Deux barrières, parce qu'une seule ne suffit pas : l'en-tête
`Content-Length` n'est pas obligatoire et peut mentir, donc c'est le compte réel des octets lus qui
tranche. Un dépassement rend **413 `payload_too_large`**.

### La signature, et rien d'autre

`HMAC-SHA256(secret, "<t>.<corps brut>")`, en hexadécimal, comparé **à temps constant**, dans une
fenêtre de **cinq minutes**. Trois pièges, tous traités :

- **Le corps brut.** `JSON.parse` puis `JSON.stringify` change l'ordre des clés et les espaces : la
  signature ne correspondrait plus. Le corps est lu en texte, signé en texte, et analysé **après**.
- **La fenêtre.** Sans elle, un événement authentique capté une fois pourrait être réémis des mois
  plus tard. Elle est symétrique : un horodatage dans le futur est refusé aussi. Elle ne fait que
  **borner** le rejeu — à l'intérieur des cinq minutes, c'est le dédoublonnage ci-dessous qui
  l'empêche, jamais la signature.
- **Plusieurs `v1`.** Pendant une rotation de secret, Stripe en envoie deux ; il suffit qu'un
  corresponde. Les `v0` sont l'ancien schéma, ignorés.

Rejets, tous en **4xx** — Stripe marque l'envoi en échec et le montre au propriétaire, ce qui est
exactement ce qu'on veut d'un secret mal recopié :

| Statut | `code`                       | Quand                                                       |
| ------ | ---------------------------- | ----------------------------------------------------------- |
| 400    | `missing_signature`          | En-tête absent                                              |
| 400    | `malformed_signature`        | En-tête illisible, ou sans `v1`                             |
| 400    | `timestamp_out_of_tolerance` | Hors des cinq minutes : horloge décalée, ou rejeu tardif    |
| 400    | `signature_mismatch`         | Signature fausse, ou corps modifié après signature          |
| 400    | `invalid_body`               | Signé mais illisible — anomalie sérieuse, elle doit se voir |
| 405    | `method_not_allowed`         | Autre verbe que POST                                        |
| 413    | `payload_too_large`          | Corps au-delà d'un mégaoctet, refusé avant lecture          |
| 503    | `stripe_not_configured`      | **Aucun secret posé : rien n'est traité**                   |

### Une fois et une seule

La signature dit que l'événement vient de Stripe, **pas qu'il est neuf**. Un même événement
authentique réémis dans la fenêtre de tolérance — rejeu manuel depuis le tableau de bord, double
livraison, requête captée — repasse la vérification. Sur `invoice.payment_failed`, cela remet en
impayé une caserne qui vient de régulariser.

`subscription_sync` s'appuie donc sur la clé primaire de `stripe_events` (`docs/SCHEMA.md § 2.17`) :
c'est l'insertion qui tranche, jamais un test suivi d'une écriture, et deux livraisons simultanées
ne peuvent pas passer toutes les deux. Un rejeu répond **200** avec `"skipped": "duplicate"` — le
prestataire n'a pas à insister.

La même table porte la **trace d'un échec**. Quand `subscription_sync` lève, sa transaction est
annulée et la ligne qu'elle avait posée part avec elle ; l'Edge Function en pose alors une seconde
par `stripe_event_fail`, dans sa propre transaction. Sans elle, un événement valide dont le
traitement échoue disparaîtrait : le prestataire abandonne ses rejeux au bout de trois jours, et il
ne resterait qu'une ligne de journal à rétention courte. `status = 'failed'` est **le seul** état
que le dédoublonnage laisse reprendre, ce qui est précisément ce qui permet aux rejeux d'aboutir.

```sql
select id, type, status, attempts, error from stripe_events where status <> 'processed';
```

### Les cinq événements, et tous les autres

| Événement                       | Effet sur `subscriptions`                                                          |
| ------------------------------- | ---------------------------------------------------------------------------------- |
| `checkout.session.completed`    | `active` (si `payment_status = paid`), client et abonnement retenus, formule posée |
| `invoice.paid`                  | `active`, `current_period_end` repoussée                                           |
| `invoice.payment_failed`        | `past_due`. **Rien n'est coupé** : la caserne écrit encore                         |
| `customer.subscription.updated` | statut et formule suivis ; un état transitoire n'écrase rien                       |
| `customer.subscription.deleted` | `cancelled`, `suspended_at` posée → lecture seule                                  |

Tout autre type est **ignoré avec un 200** : un 4xx ferait rejouer Stripe pendant trois jours un
événement qu'on ne traitera jamais, puis désactiverait le point de terminaison — et les vrais
événements cesseraient d'arriver. Même règle pour les trois refus métier : une caserne introuvable
(un autre projet branché sur le même compte), une formule inconnue, et un **client qui ne correspond
pas à la caserne nommée** (`customer_mismatch`) — la seule protection contre un
`client_reference_id` posé depuis une URL. Ces trois-là **consomment** l'événement : le rejouer n'y
changerait rien, et `stripe_events` en garde la trace en `skipped`.

```jsonc
{ "ok": true, "event_id": "evt_…", "type": "charge.refunded", "skipped": "type_ignore" }
```

Réponse d'un événement appliqué :

```jsonc
{
  "ok": true,
  "event_id": "evt_…",
  "type": "invoice.paid",
  "station_id": "uuid",
  "previous_status": "past_due",
  "status": "active"
}
```

Un **500** est rendu quand la base est indisponible — et c'est voulu : Stripe rejouera, l'événement
reste valable.

### Ce que la fonction n'écrit pas elle-même

Rien. Tout passe par `subscription_sync` (migration `0023`), qui verrouille la ligne, n'applique que
les paramètres **non nuls** — les cinq événements s'appliquent donc dans n'importe quel ordre, et
Stripe ne garantit pas l'ordre de livraison —, tient `suspended_at` et journalise dans `audit_log`.
La suspension d'un impayé, elle, n'est **pas** un événement Stripe : c'est
`cron_suspend_subscriptions`, quatorze jours plus tard (`docs/SCHEMA.md § 8`).
