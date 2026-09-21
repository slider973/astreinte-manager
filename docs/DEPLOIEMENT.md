# Déploiement de la PWA

Ce que le propriétaire doit créer chez l'hébergeur pour mettre Astreinte SP en ligne, et comment
vérifier que c'est correct. Écrit au ticket 032.

La PWA **est** le produit (`CLAUDE.md`). Les builds iOS et Android natifs ne sont produits qu'à la
demande d'une caserne et ne sont pas concernés par ce document.

---

## 1. Le principe, en une phrase

**La construction se fait dans GitHub Actions, l'hébergeur ne fait que servir des fichiers.**

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
      ↓
scripts/build_web.sh env/prod.json   flutter build web --release, élagage et compression brotli
                                     du moteur CanvasKit et des polices
      ↓
vercel deploy --prebuilt --prod      téléversement de build/web tel quel
```

Le workflow de déploiement **ne rejoue aucune vérification** : il démarre sur `workflow_run`, après
une exécution réussie de « CI » sur `main`. Une CI rouge ne se déploie pas, et rien n'est dupliqué.

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

### Obligatoires — sans eux, rien ne se déploie

| Secret | Valeur | Conséquence s'il manque |
|---|---|---|
| `VERCEL_TOKEN` | le token créé au § 2 | le workflow s'arrête et nomme le secret manquant |
| `VERCEL_ORG_ID` | `team_…` (ou l'User ID) | idem |
| `VERCEL_PROJECT_ID` | `prj_…` | idem |

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

1. **Supabase** → Authentication → URL Configuration → `Site URL` et `Redirect URLs`, sans quoi le
   lien magique de connexion renvoie sur `localhost`.
2. **Le lien d'invitation** des Edge Functions :
   ```sh
   supabase secrets set APP_BASE_URL='https://<domaine>'
   ```
   Voir `supabase/functions/README.md`. Laisser `APP_INVITE_PATH` sur sa valeur par défaut
   (`/#/invite/{token}`) : l'application utilise la stratégie de hash de `go_router`.

## 5. Mettre en ligne

**Cas nominal.** Fusionner une PR dans `main`. La CI passe, le déploiement part tout seul, l'URL
apparaît dans le résumé de l'exécution (onglet Actions → « Déploiement »).

**Rejouer une mise en ligne sans commit.** Actions → « Déploiement » → « Run workflow ».

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

# 4. L'adresse qu'on dicte au téléphone.
curl -sI https://<domaine>/install | grep -i -e '^HTTP' -e location
# attendu : 307 → /#/install
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
| Réécriture de tout vers `/index.html` | `go_router` résout les routes côté client ; sans elle, un rechargement sur une sous-page rendrait 404 |
| Redirection `/install` → `/#/install` | l'adresse qu'on dicte au téléphone ne peut pas contenir un dièse. Temporaire (307) exprès : elle disparaîtra le jour où `usePathUrlStrategy()` sera activé |
| `Cache-Control: max-age=0, must-revalidate` presque partout | c'est le service worker de Flutter qui gère les versions, par empreinte de contenu. Un cache HTTP long figerait l'application sur les téléphones déjà installés. La revalidation coûte une requête conditionnelle, et seulement au premier chargement : ensuite, le service worker sert tout hors ligne |
| `Content-Encoding: br` sur `assets/assets/fonts/*.ttf` | les polices sont **livrées déjà compressées** par `scripts/build_web.sh`. Flutter web ne décode pas le WOFF2 (`assets/fonts/README.md`), le seul levier est la compression de transport : 194 Ko → 88 Ko |
| `Content-Encoding: br` sur `canvaskit/**` | même mécanique, et c'est elle qui rend l'auto-hébergement du moteur viable (ticket 037) : 5,7 Mo de `.wasm` deviennent 1,6 Mo, exactement ce que servait le CDN de Google. Servi sans cet en-tête, le moteur ne démarre pas |
| `canvaskit/**` **sans** cache long | auto-hébergé, le chemin n'a plus la révision du moteur dedans. Un `immutable` d'un an figerait la version d'aujourd'hui et la prochaine montée de Flutter servirait un moteur périmé aux téléphones déjà venus. C'est le service worker qui gère les versions, par empreinte |
| `nosniff`, `Referrer-Policy`, `X-Frame-Options` | le minimum, sans politique de sécurité de contenu : CanvasKit a besoin de `wasm-unsafe-eval` et une CSP mal posée casse l'application en silence |

## 8. Ce qui n'est pas encore branché, et ce que ça donne

| Absent | Ce que voit l'utilisateur |
|---|---|
| Base Supabase distante | « Application non configurée » ; `/install` reste joignable |
| Firebase | l'application marche, sans notifications, et le dit dans « Profil » |
| Stripe | l'écran « Abonnement » annonce qu'aucun paiement n'est configuré (ticket 029) |

Rien ne plante, rien n'affiche de trace technique. C'est vérifié par
`test/features/onboarding/aide_installation_test.dart` et `test/app_test.dart`.

## 9. Ce qui sort de chez nous, et ce qui n'en sort pas

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
