# Edge Functions — Astreinte SP

Deno / TypeScript, une fonction par dossier, la liste de référence est la section 7 de
[`docs/SCHEMA.md`](../../docs/SCHEMA.md). Le code partagé est dans `_shared/`.

| Fonction            | Ticket | Rôle                                                                                                                                                  |
| ------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `invite-member`     | 006    | Un admin invite une ou plusieurs adresses dans sa caserne : ligne `invitations`, compte `auth.users` si l'adresse est inconnue, courriel d'invitation |
| `accept-invitation` | 006    | L'invité connecté échange son jeton contre une `memberships` active                                                                                   |

## Règles qui ne se négocient pas

- **La clé de service ne quitte jamais le serveur.** Elle ouvre le client administrateur
  (`_shared/supabase.ts`) et n'apparaît dans aucune réponse ni aucun journal.
- **Le jeton d'invitation n'est jamais renvoyé à un client.** Il part uniquement dans le lien du
  courriel, vers l'adresse invitée. La colonne `invitations.token` est hors du `grant` de `select`
  du rôle `authenticated` (migration `0008`), et les deux fonctions SQL qui la manipulent sont
  réservées à `service_role` (migration `0009`).
- **`verify_jwt = true` n'est qu'un portier.** La clé anon est un JWT valide et publique : elle
  franchit ce filtre. C'est `caller()` qui établit l'identité réelle auprès de GoTrue, et une
  requête en base qui établit le rôle. Rien du corps de la requête n'est cru sur parole :
  `station_id` sert à choisir la caserne visée, jamais à prouver un droit.

## Lancer en local

```sh
supabase start
supabase functions serve          # dans un second terminal, rechargement à chaud
scripts/test_functions.sh         # 69 assertions de bout en bout
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

| Variable          | Défaut                                          | Rôle                                                                                                                               |
| ----------------- | ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `APP_BASE_URL`    | `http://127.0.0.1:3000`                         | Origine de la PWA, base du lien d'invitation                                                                                       |
| `APP_INVITE_PATH` | `/#/invite/{token}`                             | Chemin du lien. `{token}` est remplacé. La valeur par défaut suit la stratégie de hash de go_router, en vigueur dans l'application. Passer à `/invite/{token}` seulement si `usePathUrlStrategy()` est activé |
| `MAIL_FROM`       | `Astreinte SP <invitations@astreinte-sp.local>` | Expéditeur. En production, un domaine vérifié chez Resend                                                                          |
| `RESEND_API_KEY`  | —                                               | Présente : les courriels partent par Resend. Absente : repli sur le serveur de courriel local                                      |
| `MAILPIT_URL`     | `http://supabase_inbucket_pompier:8025`         | API HTTP de Mailpit, joignable depuis le réseau Docker de la pile locale. Les courriels sont lisibles sur <http://127.0.0.1:54324> |

En production :

```sh
supabase secrets set APP_BASE_URL=https://app.astreinte-sp.fr
supabase secrets set APP_INVITE_PATH='/#/invite/{token}'
supabase secrets set MAIL_FROM='Astreinte SP <invitations@astreinte-sp.fr>'
supabase secrets set RESEND_API_KEY=re_…
```

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

## Tests

| Quoi                                                    | Où                                                                    | En CI ? |
| ------------------------------------------------------- | --------------------------------------------------------------------- | ------- |
| Fonctions SQL `create_invitation` / `accept_invitation` | `supabase/tests/invitations_test.sql`, joué par `scripts/test_rls.sh` | oui     |
| Couche HTTP des deux Edge Functions                     | `scripts/test_functions.sh`                                           | non     |

La CI (`.github/workflows/ci.yml`) démarre la pile sans `edge-runtime` ni `kong` : les Edge
Functions n'y sont pas joignables. Toute la logique de décision vit donc en SQL, où elle est testée
à chaque PR ; `scripts/test_functions.sh` couvre l'emballage HTTP et se lance à la main avant de
pousser une modification des fonctions.
