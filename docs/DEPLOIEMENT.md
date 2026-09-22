# Déploiement

Ce que le propriétaire doit créer chez l'hébergeur pour mettre Astreinte SP en ligne, et comment
vérifier que c'est correct. Écrit au ticket 032, étendu à la base et aux Edge Functions au
ticket 049.

La PWA **est** le produit (`CLAUDE.md`). Les builds iOS et Android natifs ne sont produits qu'à la
demande d'une caserne et ne sont pas concernés par ce document.

---

## 1. Le principe, en une phrase

**La construction se fait dans GitHub Actions, les hébergeurs ne font que recevoir.**

C'est une contrainte, pas un goût : l'application lit sa configuration avec
`String.fromEnvironment` (`lib/core/env.dart`), donc **à la compilation**. Une variable posée dans
le tableau de bord Vercel arriverait après coup et n'atteindrait jamais le binaire. Toutes les
valeurs de production sont donc des **secrets GitHub**, et Vercel n'en connaît aucune.

```
commit sur main
      ↓
CI (.github/workflows/ci.yml)        analyse, tests, build web, parcours, migrations, RLS, Edge Functions
      ↓  (uniquement si tout est vert)
Déploiement (.github/workflows/deploy.yml)
      │
      ├─ 1. base          supabase db push --dry-run   puis  --include-all
      │                   migrations en attente + secrets Vault de config.toml
      ├─ 2. fonctions     supabase functions deploy --use-api --import-map …/deno.json
      │                   les onze, avec le verify_jwt de supabase/config.toml
      ├─ 3. configuration supabase config diff  puis  config push
      │                   gabarits de courriel, serveur d'envoi, plafonds, redirections
      ├─ 4. PWA           scripts/build_web.sh env/prod.json
      │                   puis vercel deploy --prebuilt --prod
      └─ 5. vérification  scripts/verifier_production.sh — le dépôt contre la production
```

**L'ordre n'est pas décoratif.** Une Edge Function qui appelle une procédure que la base n'a pas
encore ne rend pas un message clair, elle rend une erreur de serveur ; une PWA qui appelle une
fonction pas encore déployée rend un 404 que l'utilisateur lit « Impossible de joindre le serveur ».
La base d'abord, les fonctions ensuite, la PWA en dernier.

Le workflow de déploiement **ne rejoue aucune vérification** : il démarre sur `workflow_run`, après
une exécution réussie de « CI » sur `main`. Une CI rouge ne se déploie pas, et rien n'est dupliqué.

**Le garde-fou de la base est une exécution à blanc, pas une approbation humaine.** `db push
--dry-run --skip-vault` nomme les migrations qu'il appliquerait, juste avant de les appliquer pour
de bon, dans le même travail et sur le même commit ; le résultat est écrit dans le résumé de
l'exécution. L'approbation a été écartée parce que le ticket 049 demande qu'une migration parte
**sans intervention manuelle** : un relecteur requis ferait attendre un clic à chaque fusion, y
compris pour les neuf PR sur dix qui ne touchent pas la base. Le choix reste réversible sans
toucher au workflow — le travail « base » déclare `environment: production-base`, **un environnement
à lui**, quand les trois autres déclarent `production`. Il suffit d'ajouter un relecteur requis à
`production-base` dans **Settings → Environments** pour que les migrations attendent un humain. La
séparation est là pour ça : un relecteur posé sur `production` demanderait quatre approbations par
mise en ligne, PWA comprise, pour protéger la seule base.

## 2. Une fois pour toutes — créer le projet chez Vercel

1. Créer un compte sur [vercel.com](https://vercel.com) et une équipe (ou rester en compte
   personnel).
2. Créer un projet **vide**, sans importer le dépôt Git.
   - Si le dépôt est importé quand même, ce n'est pas grave : `vercel.json` porte
     `"git": { "deploymentEnabled": { "main": false } }`, ce qui empêche Vercel de lancer ses
     propres constructions. Vercel n'a pas Flutter et échouerait.
3. Relever trois valeurs :

| Valeur | Où la trouver |
|---|---|
| **Project ID** | Projet → Settings → General, champ « Project ID » (`prj_…`) |
| **Team ID / Org ID** | Équipe → Settings → General, champ « Team ID » (`team_…`). En compte personnel, c'est l'« User ID » |
| **Token** | [vercel.com/account/tokens](https://vercel.com/account/tokens) → « Create Token », portée = l'équipe du projet, expiration au choix |

Le token donne le droit de déployer : il se traite comme un mot de passe et ne va **que** dans les
secrets GitHub.

## 3. Les secrets GitHub

Dépôt → **Settings → Secrets and variables → Actions → New repository secret**.

**Des secrets de dépôt, jamais des secrets d'environnement.** Le bouton voisin, « Manage
environment secrets », rangerait la valeur dans `production` ou `production-base` — et le travail
« vérification » ne la verrait pas : il appelle `.github/workflows/verifier-production.yml`, un
workflow réutilisable qui ne déclare aucun `environment:`, et un secret d'environnement n'est
visible que d'un travail qui déclare cet environnement. `secrets: inherit` ne transmet que ce que
l'appelant voit lui-même. Le symptôme serait trompeur : la mise en ligne réussit, puis la
vérification s'arrête en disant « Secrets absents : SUPABASE_ACCESS_TOKEN SUPABASE_PROJECT_REF »
alors qu'ils sont bien posés. Cela vaut pour les deux `SUPABASE_*` obligatoires ci-dessous.

### Obligatoires — sans eux, rien ne se déploie

| Secret | Valeur | Conséquence s'il manque |
|---|---|---|
| `SUPABASE_ACCESS_TOKEN` | un jeton personnel, [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens) | la base et les fonctions ne partent pas ; le workflow s'arrête et nomme le secret |
| `SUPABASE_PROJECT_REF` | la référence du projet, 20 lettres (`https://<ref>.supabase.co`) | idem |
| `VERCEL_TOKEN` | le token créé au § 2 | le workflow s'arrête et nomme le secret manquant |
| `VERCEL_ORG_ID` | `team_…` (ou l'User ID) | idem |
| `VERCEL_PROJECT_ID` | `prj_…` | idem |

**Il n'y a pas de secret pour le mot de passe de la base.** `supabase db push --project-ref …` avec
le jeton d'accès suffit : le CLI ouvre un rôle de connexion temporaire par l'API de gestion.
Vérifié le 21 septembre 2026 contre le projet de production. Si une version future du CLI le
redemandait, le message nommerait `SUPABASE_DB_PASSWORD` ; il se trouve alors dans
**Project Settings → Database → Database password**, et il se pose comme les autres.

**Le jeton Vercel doit être un jeton de compte**, créé depuis les réglages personnels
([vercel.com/account/tokens](https://vercel.com/account/tokens)), et non un jeton lié au projet :
ce dernier fait répondre « User not found » à la ligne de commande, et la mise en ligne de la PWA
échoue à l'étape « Mettre en ligne sur Vercel ». Seul le propriétaire du compte peut le créer.

### Le serveur d'envoi de courriels

| Secret | Valeur | Conséquence s'il manque |
|---|---|---|
| `SUPABASE_AUTH_SMTP_PASSWORD` | la clé d'API Resend (`re_…`), qui sert de mot de passe SMTP | le travail « configuration » s'arrête **avant** de pousser quoi que ce soit, et nomme le secret |

C'est le seul morceau de la configuration d'authentification qui ne peut pas vivre dans le dépôt.
`supabase/config.toml` déclare `pass = "env(SUPABASE_AUTH_SMTP_PASSWORD)"` : sans la variable, la
poussée écrirait un mot de passe **vide** sur un serveur d'envoi déclaré actif, et plus aucun
courriel de connexion ne partirait — donc plus personne ne se connecterait. Le workflow refuse
plutôt que d'écrire.

### Facultatifs — l'application se déploie et s'ouvre sans eux

| Secret | Valeur | Conséquence s'il manque |
|---|---|---|
| `SUPABASE_URL` | `https://<ref>.supabase.co` | l'application s'ouvre sur **« Application non configurée »**. `/install` reste joignable |
| `SUPABASE_ANON_KEY` | la clé **anon / publishable** du projet. **Jamais** la clé `service_role` | idem |
| `FIREBASE_PROJECT_ID` | identifiant du projet Firebase | |
| `FIREBASE_API_KEY` | `apiKey` de l'application **web** | l'application s'ouvre **sans notifications**, et le dit dans « Profil ». Aucune requête ne part vers Google |
| `FIREBASE_APP_ID` | `appId` de l'application web (`1:…:web:…`) | |
| `FIREBASE_MESSAGING_SENDER_ID` | `messagingSenderId` | |
| `FIREBASE_VAPID_KEY` | clé publique VAPID, onglet Cloud Messaging | |

Les cinq `FIREBASE_*` vont **ensemble** : une configuration à moitié remplie est traitée comme
absente (`lib/core/env.dart`). La marche à suivre pour les obtenir est dans
[docs/FIREBASE.md](FIREBASE.md).

Aucune de ces valeurs n'est un secret au sens strict — la clé anon est publique par conception et
protégée par RLS, les cinq valeurs Firebase sont publiées dans le HTML de n'importe quelle
application web. Elles passent par des secrets GitHub parce que c'est le seul endroit où une valeur
peut être changée sans commit, pas parce qu'elles sont sensibles.

### Ce qui ne se met **pas** ici

- La clé `service_role` de Supabase, la clé secrète Stripe, la clé de service Firebase : elles
  vivent dans les secrets **Supabase** (`supabase secrets set`), côté Edge Functions, et jamais
  dans l'application. Un test le vérifie (`test/core/supabase/aucune_cle_service_test.dart`).
- Des variables d'environnement **Vercel** : elles n'auraient aucun effet (§ 1).

## 4. Le domaine

Projet Vercel → Settings → Domains → « Add ». Vercel demande un `CNAME` (sous-domaine) ou des
enregistrements `A` (apex) chez le registrar. Le certificat HTTPS est émis automatiquement et
renouvelé ; il n'y a rien à faire de plus.

Une fois le domaine connu, deux choses le suivent :

1. **Les adresses d'authentification**, dans `supabase/config.toml`, section
   `[remotes.production.auth]` : `site_url` vaut l'origine nue, `https://<domaine>`, et
   `additional_redirect_urls` doit contenir `https://<domaine>/**` — le lien d'invitation ramène
   sur `/invite/<jeton>`, pas sur la racine. **Un commit, pas un clic** : c'est le déploiement qui
   les pose (`config push`). Les modifier dans Authentication → URL Configuration marche jusqu'au
   prochain déploiement, qui remettra ce que dit le dépôt.
2. **Le lien d'invitation** des Edge Functions :
   ```sh
   supabase secrets set APP_BASE_URL='https://<domaine>'
   ```
   Voir `supabase/functions/README.md`. Les trois chemins — `APP_INVITE_PATH`, `APP_LINK_PATH`,
   `APP_SUBSCRIPTION_PATH` — restent sur leur valeur par défaut, **sans dièse** (ticket 046). S'ils
   ont été posés avant, les retirer : ils fabriqueraient des liens morts.

## 5. Mettre en ligne

**Cas nominal.** Fusionner une PR dans `main`. La CI passe, le déploiement part tout seul — base,
fonctions, configuration, PWA, dans cet ordre — et le résumé de l'exécution porte les migrations
appliquées, les fonctions déployées, les écarts de configuration poussés et l'URL (onglet Actions →
« Déploiement »).

**Rejouer une mise en ligne sans commit.** Actions → « Déploiement » → « Run workflow ».

**Demander si la production est à jour.** Actions → « Vérification de la production » → « Run
workflow ». Réponse en moins d'une minute, dans le résumé de l'exécution : migrations, Edge
Functions, secret Vault du répartiteur de notifications, configuration d'authentification. Le même
compte rendu s'obtient depuis un poste :

```sh
export SUPABASE_ACCESS_TOKEN=sbp_…   # supabase.com/dashboard/account/tokens
export SUPABASE_PROJECT_REF=…        # facultatif si le projet est lié
scripts/verifier_production.sh
```

**Depuis un poste, en dépannage.** Les trois commandes `vercel` sont exactement celles du
workflow ; `vercel build` ne reconstruit rien, il empaquette `build/web` avec les en-têtes et les
réécritures de `vercel.json`. Le répertoire `.vercel/` qu'elles créent n'est pas versionné.

```sh
cp env/prod.json.example env/prod.json   # puis remplir — le fichier n'est pas versionné
scripts/build_web.sh env/prod.json

export VERCEL_ORG_ID=team_…  VERCEL_PROJECT_ID=prj_…
npx vercel pull --yes --environment=production --token=<token>
npx vercel build --prod --token=<token>
npx vercel deploy --prebuilt --prod --token=<token>
```

**Regarder la construction avant de l'envoyer.** Un serveur statique ordinaire ne convient pas :
il ne pose pas `Content-Encoding: br` sur les polices et le moteur pré-compressés. Les polices
échouent alors au décodage **en silence**, le moteur refuse de démarrer et la page reste blanche.
`scripts/servir_web.py` rejoue `vercel.json` — redirections, en-têtes, réécriture vers
`index.html` — et comprime les types texte comme le fait le CDN.

```sh
scripts/build_web.sh env/prod.json
scripts/servir_web.py            # puis http://127.0.0.1:8099
```

## 6. Vérifier, dans cet ordre

```sh
# 1. Les polices sont bien servies pré-compressées : 88 Ko au lieu de 194.
curl -sI -H 'Accept-Encoding: br' \
  https://<domaine>/assets/assets/fonts/AtkinsonHyperlegibleNext-Regular.ttf \
  | grep -i -e content-encoding -e content-length
# attendu : content-encoding: br   /   content-length: ~17600

# 2. Le moteur de rendu aussi, sans quoi l'application ne démarre pas du tout.
curl -sI -H 'Accept-Encoding: br' https://<domaine>/canvaskit/chromium/canvaskit.wasm \
  | grep -i -e content-encoding -e content-length
# attendu : content-encoding: br   /   content-length: ~1616000

# 3. Le service worker n'est pas figé par le CDN.
curl -sI https://<domaine>/flutter_service_worker.js | grep -i cache-control
# attendu : public, max-age=0, must-revalidate

# 4. Une route profonde rechargée ne rend pas une page introuvable.
#    C'est la réécriture vers index.html : sans elle, plus rien ne marche
#    depuis que les routes vivent dans le chemin (ticket 046).
curl -so /dev/null -w '%{http_code}\n' https://<domaine>/install
curl -so /dev/null -w '%{http_code}\n' https://<domaine>/admin/planning
# attendu : 200, deux fois
```

Le workflow fait lui-même les vérifications 1 à 3 après chaque mise en ligne et **échoue** si elles
ne passent pas. La raison est dans `assets/fonts/README.md` : une police qui n'est pas décodée
échoue **en silence**, et l'application retombe alors sur un Roboto téléchargé chez Google. Le
moteur, lui, échoue bruyamment — `WebAssembly.compileStreaming(): expected magic word` — et la page
reste blanche. Mieux vaut une mise en ligne rouge qu'une PWA muette ou qui appelle gstatic.

Puis, sur un téléphone :

1. Ouvrir `https://<domaine>/install`, suivre les trois gestes, vérifier que l'icône posée sur
   l'écran d'accueil est bien **la case cochée sur fond encre**, pas le logo bleu de Flutter.
2. Ouvrir depuis l'icône : l'application doit démarrer **sans barre d'adresse**
   (`display: standalone`).
3. Chrome de bureau → DevTools → Lighthouse → catégorie « Progressive Web App » : « Installable »
   doit être vert.

## 7. Ce que l'hébergeur fait, et pourquoi (`vercel.json`)

| Règle | Raison |
|---|---|
| `outputDirectory: build/web`, `buildCommand` réduit à un `echo` | la construction a déjà eu lieu dans Actions ; `vercel build` ne fait qu'empaqueter |
| Réécriture de tout vers `/index.html` | `go_router` résout les routes côté client, et depuis le ticket 046 elles vivent dans le **chemin** de l'adresse : sans cette règle, un rechargement sur `/admin/planning` — ou l'ouverture d'un lien d'invitation — rendrait 404 avant même que l'application démarre. C'est la contrepartie obligatoire des adresses sans dièse |
| Aucune redirection | `/install` est une route comme les autres depuis le ticket 046. La redirection `/install` → `/#/install` du ticket 032 n'a plus d'objet : elle enverrait sur une adresse que le routeur ne sait plus lire |
| `Cache-Control: max-age=0, must-revalidate` presque partout | c'est le service worker de Flutter qui gère les versions, par empreinte de contenu. Un cache HTTP long figerait l'application sur les téléphones déjà installés. La revalidation coûte une requête conditionnelle, et seulement au premier chargement : ensuite, le service worker sert tout hors ligne |
| `Content-Encoding: br` sur `assets/assets/fonts/*.ttf` | les polices sont **livrées déjà compressées** par `scripts/build_web.sh`. Flutter web ne décode pas le WOFF2 (`assets/fonts/README.md`), le seul levier est la compression de transport : 194 Ko → 88 Ko |
| `Content-Encoding: br` sur `canvaskit/**` | même mécanique, et c'est elle qui rend l'auto-hébergement du moteur viable (ticket 037) : 5,7 Mo de `.wasm` deviennent 1,6 Mo, exactement ce que servait le CDN de Google. Servi sans cet en-tête, le moteur ne démarre pas |
| `canvaskit/**` **sans** cache long | auto-hébergé, le chemin n'a plus la révision du moteur dedans. Un `immutable` d'un an figerait la version d'aujourd'hui et la prochaine montée de Flutter servirait un moteur périmé aux téléphones déjà venus. C'est le service worker qui gère les versions, par empreinte |
| `nosniff`, `Referrer-Policy`, `X-Frame-Options` | le minimum, sans politique de sécurité de contenu : CanvasKit a besoin de `wasm-unsafe-eval` et une CSP mal posée casse l'application en silence |

## 8. Les trois états de la base, et ce que chacun donne

Ce document n'en connaissait que deux — absente, présente — jusqu'au 21 septembre 2026. Il en
manquait un, et c'est celui qu'on a eu.

| État | Ce que voit l'utilisateur |
|---|---|
| **Base absente** — `SUPABASE_URL` ou `SUPABASE_ANON_KEY` non posé | « Application non configurée » dès l'ouverture ; `/install` reste joignable |
| **Base présente et à jour** | tout marche |
| **Base présente mais en retard** — des migrations ou des Edge Functions manquent | l'application s'ouvre, la connexion marche, et **c'est précisément ce qui trompe** : le défaut n'apparaît qu'à l'action qui touche la pièce manquante |

### Ce que « en retard » donne à l'écran

Aucun de ces messages ne parle de déploiement. C'est pour cela qu'un retard a pu vivre des
semaines.

| Ce qui manque | Ce que l'écran dit |
|---|---|
| Une **Edge Function** (la passerelle rend 404) | « Impossible de joindre le serveur. Vérifie ta connexion, puis réessaie. » — sur l'invitation, la publication du planning, la réattribution, l'abonnement, l'export RGPD |
| Une **migration** (colonne ou table absente) | l'écran concerné reste vide ou refuse l'enregistrement, sans explication ; la trace technique n'est visible que dans les journaux du projet |
| Le secret Vault **`notify_function_url`** mal posé | rien. `cron_dispatch_notifications` réussit toutes les minutes, pousse vers un hôte inexistant, et la file grossit : `select * from notification_outbox where status <> 'sent'` |
| La **configuration d'authentification** non poussée | le courriel de connexion arrive en anglais, avec un lien au lieu du code à six chiffres. Ouvrir le lien change de page, le jeton d'invitation ne vit qu'en mémoire : l'invitation ne peut plus être acceptée et l'écran dit « Aucune caserne » |
| Le **plafond d'envoi** resté à celui du plan gratuit | la troisième invitation de l'heure ne part pas, et l'écran annonce un envoi réussi |
| Les **fonctions refusées à l'empaquetage** — le travail `fonctions` est rouge, rien n'est parti | rien de neuf : la production garde les fonctions de la mise en ligne précédente et l'écart ne se lit que dans le workflow. À la **première** mise en ligne, c'est le 404 de la première ligne de ce tableau |

### Fonctions refusées à l'empaquetage

Le travail `fonctions` téléverse ses fichiers, puis échoue autant de fois qu'il y a de fonctions :

```
unexpected deploy status 400: {"message":"Failed to bundle the function (reason: Relative
import path \"@supabase/supabase-js\" not prefixed with / or ./ or ../
  at …/supabase/functions/_shared/supabase.ts:7:51)."}
```

**La cause** : `--use-api` empaquette **côté serveur**, avec les seuls fichiers téléversés. Le CLI
téléverse le graphe des imports relatifs et la carte d'imports — mais la carte **seulement si on la
lui nomme**. La nôtre est unique pour les onze fonctions, `supabase/functions/deno.json` : Deno la
trouve en remontant les dossiers, le téléverseur non. C'est arrivé à la première exécution du
workflow, le 21 septembre 2026 (ticket 054) ; `configuration` et `vercel` ont été sautés par
dépendance, et la production n'a rien perdu puisqu'elle en était déjà à la mise en ligne manuelle
du même jour.

**Le rattrapage** : désigner la carte, `--import-map supabase/functions/deno.json`, à la ligne de
commande comme dans le workflow. La preuve que la carte est partie se lit dans le journal, une fois
par fonction, **avant** les autres fichiers :

```
Uploading asset (invite-member): supabase/functions/deno.json
```

Une carte oubliée ne peut plus atteindre la production sans être vue : `scripts/verifier_carte_imports.py`,
joué par la CI, lit la commande de `deploy.yml` et refuse la pull request si un specifier nu d'une
fonction n'est pas résolu par la carte qu'elle désigne.

### Savoir dans quel état on est

```sh
export SUPABASE_ACCESS_TOKEN=sbp_…
scripts/verifier_production.sh
```

Rend `0` quand le dépôt et la production disent la même chose, `1` en nommant chaque écart et la
commande qui le rattrape, `2` s'il n'a pas pu conclure. Il tourne aussi à chaque mise en ligne et à
la demande (§ 5).

Il compare quatre choses : les migrations, les Edge Functions (présence, état, `verify_jwt`),
l'adresse Vault du répartiteur de notifications, et la configuration d'authentification — **sujet
du courriel de connexion et son corps**. Le corps est lu séparément, par
`GET /v1/projects/{ref}/config/auth`, champ `mailer_templates_magic_link_content` : `config diff`
ne le voit pas, `content_path` étant un fichier que `config push` téléverse et non une valeur qu'il
compare. C'est pourtant le corps qui était en anglais le 21 septembre 2026. Avant de comparer, trois
choses sont normalisées de part et d'autre et **elles seules** : les retours chariot des fins de
ligne Windows, les espaces en fin de ligne, les lignes vides. Une ligne ajoutée, un mot changé, une
balise déplacée font un écart.

### Rattraper — la procédure manuelle de secours

C'est elle qui a sauvé la journée du 21 septembre 2026, avant que le workflow existe. Elle reste
la bonne réponse quand GitHub Actions est indisponible, ou pour rattraper une production sans
attendre une fusion. Elle ne fait rien de plus que le workflow, dans le même ordre.

```sh
export SUPABASE_ACCESS_TOKEN=sbp_…                 # jamais dans un fichier du dépôt
export SUPABASE_PROJECT_REF=…                      # 20 lettres, https://<ref>.supabase.co

# 1. La base. L'exécution à blanc d'abord : elle nomme ce qui partira.
supabase db push --project-ref "$SUPABASE_PROJECT_REF" --include-all --dry-run --skip-vault
supabase db push --project-ref "$SUPABASE_PROJECT_REF" --include-all
#    Depuis un poste lié (`supabase link`), `--linked` remplace `--project-ref`.

# 2. Les fonctions. Sans nom de fonction : les onze, avec le verify_jwt de config.toml.
#    `--import-map` n'est pas facultatif : avec `--use-api`, l'empaquetage a lieu côté
#    serveur et ne voit que les fichiers téléversés (voir « refusées à l'empaquetage »).
supabase functions deploy --project-ref "$SUPABASE_PROJECT_REF" \
  --import-map supabase/functions/deno.json --use-api

# 3. La configuration d'authentification : gabarits, serveur d'envoi, plafonds, redirections.
export SUPABASE_AUTH_SMTP_PASSWORD=re_…            # clé d'API Resend, sinon le mot de passe part vide
supabase config diff --project-ref "$SUPABASE_PROJECT_REF"   # à lire avant
supabase config push --project-ref "$SUPABASE_PROJECT_REF"

# 4. Vérifier.
scripts/verifier_production.sh
```

**L'adresse du répartiteur de notifications** est posée par l'étape 1 :
`[remotes.production.db.vault]` de `supabase/config.toml` la déclare, et `db push` met à jour les
secrets Vault déclarés **avant** de jouer les migrations. Si jamais elle est à reprendre à la main,
la commande est dans `supabase/functions/README.md` :

```sql
select vault.update_secret(
  (select id from vault.secrets where name = 'notify_function_url'),
  'https://<ref>.supabase.co/functions/v1/send-notification');
```

Les notifications restées en file repartent d'elles-mêmes à la minute suivante : rien n'est perdu,
c'est tout l'intérêt de la file.

### Ce que `config push` pose, et ce qui reste manuel

`supabase config push` ne pousse que ce que `supabase/config.toml` **déclare**, et laisse le reste
intact. La section `[remotes.production]` y remplace les valeurs de la pile locale : sans elle, la
poussée ramènerait la production sur `http://127.0.0.1:3000`.

| Réglage | Par où |
|---|---|
| Gabarit et sujet du courriel de connexion | `config push` — `[auth.email.template.magic_link]`, fichier `supabase/templates/magic_link.html` |
| Adresses du site et de redirection | `config push` — `[remotes.production.auth]` |
| Plafond d'envoi de courriels | `config push` — `[remotes.production.auth.rate_limit]` |
| Serveur d'envoi (hôte, port, compte, expéditeur) | `config push` — `[remotes.production.auth.email.smtp]` |
| **Mot de passe SMTP** (clé d'API Resend) | **manuel** : secret GitHub `SUPABASE_AUTH_SMTP_PASSWORD`, lu par `env(…)`. Un secret ne va pas dans le dépôt |
| **Secrets des Edge Functions** (`RESEND_API_KEY`, `STRIPE_*`, `FIREBASE_SERVICE_ACCOUNT`, `APP_BASE_URL`) | **manuel** : `supabase secrets set`, une fois. Voir `supabase/functions/README.md` |
| **Domaine et certificat** chez Vercel | **manuel** : § 4 |
| **Jetons** (accès Supabase, Vercel) | **manuel** : secrets GitHub, § 3 |
| `auth.sms.twilio.enabled` | **ni l'un ni l'autre** : non poussée, non surveillée — voir ci-dessous |

**Une propriété ne converge pas, et elle est traitée comme telle.** `config diff` rend
`auth.sms.twilio.enabled` en écart — dépôt `false`, production `true` — sans qu'aucune décision
produit soit derrière. L'API hébergée rend toujours un `sms_provider` et le sien vaut « twilio » par
défaut ; `external_phone_enabled` est à faux, aucun compte Twilio n'est renseigné, aucun SMS ne part
et aucun ne partira, le MVP n'authentifiant que par courriel. La déclarer vraie dans
`[remotes.production]` est refusé par le CLI, qui réclame alors un `account_sid` et un
`message_service_sid` inexistants ; la pousser à `false` ne tient pas, l'API la redonne `true` au
passage suivant. Elle est donc **non poussée et non comparée** : `scripts/verifier_production.sh`
la range dans une liste nommée, la signale en information, et ne compte pas d'écart. Une alarme qui
sonne à chaque déploiement ne dit plus rien.

Ce qui reste manuel l'est pour une seule raison : ce sont des secrets, ou des actions que seul le
propriétaire du compte peut faire. Tout le reste est dans le dépôt et se rejoue.

## 9. Ce qui n'est pas encore branché, et ce que ça donne

| Absent | Ce que voit l'utilisateur |
|---|---|
| Base Supabase distante | « Application non configurée » ; `/install` reste joignable |
| Firebase | l'application marche, sans notifications, et le dit dans « Profil » |
| Stripe | l'écran « Abonnement » annonce qu'aucun paiement n'est configuré (ticket 029) |

Rien ne plante, rien n'affiche de trace technique. C'est vérifié par
`test/features/onboarding/aide_installation_test.dart` et `test/app_test.dart`.

## 10. Ce qui sort de chez nous, et ce qui n'en sort pas

Depuis le ticket 037, **une PWA qui s'ouvre et qu'on parcourt ne contacte aucun domaine tiers.**
Vérifié au journal réseau, au démarrage comme pendant la navigation, y compris en saisissant des
caractères absents du sous-ensemble embarqué. Trois réglages tiennent ce résultat, et les trois
sont couverts par `test/web/aucun_tiers_test.dart` :

| Réglage | Où | Ce qu'il supprime |
|---|---|---|
| `canvasKitBaseUrl` + `--no-web-resources-cdn` | `web/flutter_bootstrap.js`, `scripts/build_web.sh` | 1 620 Ko de CanvasKit depuis `www.gstatic.com` |
| famille `Roboto` déclarée | `pubspec.yaml` | 63 Ko de Roboto depuis `fonts.gstatic.com`, à chaque ouverture |
| `fontFallbackBaseUrl` | `web/flutter_bootstrap.js` | les polices Noto depuis `fonts.gstatic.com`, déclenchées par le texte saisi (`web/polices-de-repli/README.md`) |

Ce qui part encore, et pourquoi :

- **Supabase** (`<ref>.supabase.co`) : c'est la base du produit, hébergée en Europe. Ce n'est pas un
  tiers au sens du registre des données personnelles, c'est le sous-traitant déclaré.
- **Firebase**, le jour où les cinq secrets `FIREBASE_*` seront posés : `firebase_core_web` injecte
  le SDK depuis `www.gstatic.com`, et `web/firebase-messaging-sw.js` fait un `importScripts` vers la
  même adresse. Tant que la configuration est absente — c'est le cas aujourd'hui —, **aucune de ces
  requêtes ne part**. Le jour où elle sera posée, ce sera une dépendance tierce assumée, à déclarer
  dans la politique de confidentialité ; elle sort du périmètre du ticket 037.

La compression de `main.dart.js` est faite par Vercel à la volée (3,7 Mo → environ 1,1 Mo en gzip,
moins en brotli). Rien à configurer.
