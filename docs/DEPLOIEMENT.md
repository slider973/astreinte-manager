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
      │                   puis scripts/deployer_pwa.py — l'API Vercel, pas sa ligne de commande
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
| **Token** | [vercel.com/account/tokens](https://vercel.com/account/tokens) → « Create Token », **portée = le projet `astreinte-manager`**, expiration au choix |

Le token donne le droit de déployer : il se traite comme un mot de passe et ne va **que** dans les
secrets GitHub.

**Le jeton attendu est un jeton de projet, préfixe `vcp_`.** C'est ce que Vercel crée quand on
choisit le projet pour portée sur la page des jetons du compte, et c'est celui qu'il faut : il ne
donne de droit que sur ce projet.

Un tel jeton **n'a pas de contexte utilisateur**, et la ligne de commande Vercel commence par
charger l'utilisateur : `vercel pull`, `vercel build` et `vercel deploy` répondent tous

```
Not able to load user because of unexpected error: User not found. (404)
```

Ce n'est pas un défaut du jeton — deux jetons créés le 21 septembre 2026 ont donné exactement le
même résultat. C'est pourquoi le déploiement passe par l'**API** Vercel, avec
`scripts/deployer_pwa.py`, qui accepte ce jeton (ticket 060). Rien à demander de plus : ni jeton de
compte, ni portée d'équipe.

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
| `VERCEL_TOKEN` | le jeton de projet `vcp_…` créé au § 2 | le workflow s'arrête et nomme le secret manquant |
| `VERCEL_ORG_ID` | `team_…` (ou l'User ID) | idem |
| `VERCEL_PROJECT_ID` | `prj_…` | idem |

**Il n'y a pas de secret pour le mot de passe de la base.** `supabase db push --project-ref …` avec
le jeton d'accès suffit : le CLI ouvre un rôle de connexion temporaire par l'API de gestion.
Vérifié le 21 septembre 2026 contre le projet de production. Si une version future du CLI le
redemandait, le message nommerait `SUPABASE_DB_PASSWORD` ; il se trouve alors dans
**Project Settings → Database → Database password**, et il se pose comme les autres.

**Le jeton Vercel est un jeton de projet, `vcp_…`**, créé depuis la page des jetons du compte
([vercel.com/account/tokens](https://vercel.com/account/tokens)) avec le projet pour portée — § 2.
C'est le seul type demandé, et il suffit : la mise en ligne passe par l'API Vercel, que ce jeton
autorise. Seul le propriétaire du compte peut le créer.

Il n'y a **pas** de secret `VERCEL_SCOPE` : il ne servait qu'à la ligne de commande, qui n'est plus
utilisée. S'il traîne encore dans les secrets du dépôt, il peut être supprimé.

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

**Le domaine n'est écrit qu'une fois dans le dépôt**, en `site_url` de `[remotes.production.auth]`
(point 1). C'est de là que `scripts/deployer_pwa.py` le lit pour attendre son alias et pour donner
au workflow l'adresse à vérifier (§ 6) : changer de domaine, c'est changer cette ligne, et rien
d'autre côté dépôt.

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

**Depuis un poste, en dépannage.** Les deux commandes sont exactement celles du workflow. La
ligne de commande Vercel n'est pas utilisée : le jeton du dépôt est un jeton de projet et elle le
refuse (§ 2). `scripts/deployer_pwa.py` parle à l'API, n'a aucune dépendance hors bibliothèque
standard, attend l'état `READY`, **puis attend que le domaine de production figure dans les alias
du déploiement** avant de rendre la main (§ 6).

```sh
cp env/prod.json.example env/prod.json   # puis remplir — le fichier n'est pas versionné
scripts/build_web.sh env/prod.json

export VERCEL_TOKEN=vcp_…  VERCEL_ORG_ID=team_…  VERCEL_PROJECT_ID=prj_…
scripts/deployer_pwa.py --dry-run     # ce qui partirait, sans rien envoyer
scripts/deployer_pwa.py               # envoi, déploiement de production, attente de READY
```

Le script envoie `vercel.json` **avec** la construction, à la racine du déploiement, et range
`build/web` sous le chemin que ce fichier déclare en `outputDirectory`. Ce n'est pas un détail :
un déploiement par l'API qui n'envoie pas `vercel.json` ne reçoit **ni les en-têtes, ni la
réécriture vers `index.html`**. C'est ce qui était arrivé aux mises en ligne manuelles des 21 et
22 septembre 2026 — la production rendait 404 sur `/install` comme sur `/admin/planning`, et le
`Cache-Control: public, max-age=0, must-revalidate` qu'on y lisait était celui de Vercel par
défaut, pas le nôtre. La vérification 5 du § 6 le prend désormais en faute.

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

# 5. Les en-têtes de vercel.json sont bien appliqués. Vercel n'en pose aucun
#    de lui-même : s'ils sont là, c'est que la configuration est partie avec
#    la construction (§ 5).
curl -sI https://<domaine>/ | grep -i -e x-content-type-options -e x-frame-options -e referrer-policy
# attendu : nosniff / SAMEORIGIN / strict-origin-when-cross-origin

# 6. C'est bien la construction du commit qui est servie.
#    `--compressed` défait la compression de transport : on compare les octets.
#    `main.dart.js` reste le témoin : c'est le repli, il n'est pas
#    pré-compressé par la construction, donc ses octets sur disque sont ceux
#    qu'on demande à l'hébergeur (§ 6 bis).
curl -s --compressed https://<domaine>/main.dart.js | shasum -a 1
shasum -a 1 build/web/main.dart.js
# attendu : la même empreinte deux fois

# 7. Le moteur Wasm est servi, et la page est isolée — sans quoi la PWA
#    s'ouvre, marche, et saccade comme avant (ticket 065, § 6 bis).
curl -sI https://<domaine>/ | grep -i cross-origin
# attendu : cross-origin-opener-policy: same-origin
#           cross-origin-embedder-policy: require-corp
curl -sI https://<domaine>/main.dart.wasm | grep -i -e content-type -e content-encoding
curl -sI https://<domaine>/canvaskit/skwasm.wasm | grep -i content-type
# attendu : application/wasm, deux fois. `text/html` veut dire que le fichier
# est absent et que la réécriture a servi index.html : il n'y a pas de 404 ici.
```

**L'adresse vérifiée est toujours le domaine de production**, jamais une adresse `*.vercel.app` :
`scripts/deployer_pwa.py` le lit dans `supabase/config.toml`
(`[remotes.production.auth].site_url`, la seule écriture du domaine dans le dépôt), attend après
`READY` qu'il figure dans les alias du déploiement — au plus 120 s, sinon la mise en ligne échoue,
un déploiement prêt sans son alias de production n'en étant pas une — et le rend au workflow, qui
n'a donc aucun alias à choisir. Les alias `*.vercel.app` du projet sont derrière la protection de
déploiement de l'équipe : les interroger rend un 302 vers `vercel.com/sso-api` et fait lire les
en-têtes de vercel.com au lieu de ceux de l'application, ce qui a fait échouer le déploiement du
22 septembre 2026 (ticket 062). Chacune des deux étapes réessaie jusqu'à trois fois, espacées de
cinq secondes, et affiche l'adresse interrogée à chaque tentative.

Le workflow fait lui-même les vérifications 1 à 6 après chaque mise en ligne et **échoue** si elles
ne passent pas — les trois premières à l'étape « Vérifier les en-têtes servis », les trois autres à
l'étape « Vérifier la PWA servie ». La septième est faite par le travail « Vérification d'écart »,
qui joue `scripts/verifier_production.sh` (§ 5 du compte rendu). La raison est dans `assets/fonts/README.md` : une police qui n'est pas décodée
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

## 6 bis. Le moteur de rendu : WebAssembly, son repli, et ses deux en-têtes

Écrit au ticket 065, après un signalement du propriétaire : « le scroll saccade », sur un
iPhone 17 Pro Max avec la PWA installée.

### Ce que la production sert

`scripts/build_web.sh` construit avec `--wasm`. La construction sort **deux applications dans
le même répertoire**, et le chargeur Flutter choisit seul à l'ouverture :

| Le navigateur a WasmGC | Il charge | Rendu par | Rastérisation |
|---|---|---|---|
| oui — Chrome, Edge, Firefox, **Safari depuis 18.2** | `main.dart.wasm` + `main.dart.mjs` | `canvaskit/skwasm.wasm` | sur un **fil séparé** |
| oui, mais la page n'est pas isolée | `main.dart.wasm` + `main.dart.mjs` | `canvaskit/skwasm_heavy.wasm` | sur le fil principal |
| non — Safari d'avant 18.2, vieil Android | `main.dart.js` | `canvaskit/chromium/canvaskit.wasm` | sur le fil principal |

Les trois chemins partent à chaque mise en ligne. Aucun n'est un mode dégradé qu'on découvre :
`scripts/verifier_production.sh` § 5 vérifie que les quatre fichiers sont servis, avec le bon
type, après chaque déploiement.

### Les deux en-têtes, et pourquoi `require-corp`

La deuxième ligne du tableau est celle qu'il faut éviter, et elle ne dépend pas de Flutter :
Skwasm ne rastérise sur un fil séparé que si la page a `SharedArrayBuffer`, que le navigateur
ne donne qu'à un document **isolé**. D'où, sur toutes les routes de `vercel.json` :

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

`require-corp` refuse toute ressource tierce qui ne s'annonce pas partageable. Les deux seules
origines que la PWA joint le sont, vérifié le 23 septembre 2026 :

| Origine | Comment elle est chargée | Pourquoi `require-corp` la laisse passer |
|---|---|---|
| `<ref>.supabase.co` | `fetch` CORS, par `supabase_flutter` | une réponse CORS satisfait la vérification de COEP sans en-tête de plus |
| `www.gstatic.com` (SDK Firebase, `<script>` et `importScripts`) | balise de script et service worker | elle répond `cross-origin-resource-policy: cross-origin` |

Google Fonts n'est plus joint depuis le ticket 037 ; Stripe est une **navigation**, pas une
ressource incorporée, et COEP ne la regarde pas.

**Si un jour une ressource tierce est bloquée**, le symptôme est net dans la console du
navigateur (`net::ERR_BLOCKED_BY_RESPONSE.NotSameOriginAfterDefaultedToSameOriginByCoep`). La
porte de secours est de remplacer `require-corp` par `credentialless` dans `vercel.json` : la
ressource part alors **sans cookie ni identifiant**, ce qui suffit pour un CDN public et ne
suffit pas pour une ressource privée. L'isolation est conservée, donc Skwasm garde son fil.
Ce n'est pas le réglage par défaut parce qu'il élargit ce qui peut entrer dans une page isolée
sans qu'on l'ait demandé — et `test/web/moteur_wasm_test.dart` échoue si on l'y met sans le
décider.

### Ce que ça change, mesuré

Trois tours, Chrome sans interface, processeur bridé ×4 pour approcher un téléphone,
défilement tactile scripté de 3 s. Une image « perdue » est un intervalle de plus d'une
période et demie d'écran : le pompier voit un à-coup.

| Écran | CanvasKit JS | Wasm / Skwasm |
|---|---|---|
| Accueil (390 pt) | 0 à 2 images perdues | 0 |
| Calendrier, mois saisi à moitié (390 pt) | 0 | 0 |
| Matrice admin, 60 membres (1440 pt) | **50 à 54 perdues, 34 à 41 %** | 0 à 2, ≤ 1 % |
| Premier défilement de la matrice | à-coup de 67 à 417 ms | 17 à 33 ms |

Le premier défilement est la compilation des shaders. Elle ne disparaît pas — elle cesse
d'être visible : 417 ms devient 33 ms, soit une image perdue au lieu de vingt-cinq. Aucun
préchauffage n'a été ajouté : il n'y a plus rien à préchauffer.

### Le plafond que ce ticket ne franchit pas

**Sur un iPhone ProMotion, Safari cadence `requestAnimationFrame` à 60 Hz**, là où le reste du
téléphone défile à 120 Hz. C'est une décision d'Apple, pas un réglage. Une PWA Flutter y
paraîtra donc toujours un peu moins fluide qu'une liste native, **même sans aucune image
perdue** — le mouvement est juste, il est simplement cadencé deux fois moins souvent. Ce que le
ticket 065 supprime, ce sont les à-coups ; ce qu'il ne peut pas donner, c'est le 120 Hz.

### Ce que ça pèse

Un navigateur ne télécharge qu'un des deux chemins. Tout est pré-compressé par
`scripts/build_web.sh` et annoncé par `vercel.json` :

| Chemin | Fichiers | Transport |
|---|---|---|
| Wasm | `main.dart.wasm` 1,0 Mo + `skwasm.wasm` 1,1 Mo | ~2,1 Mo |
| Repli JS | `main.dart.js` ~0,9 Mo + `chromium/canvaskit.wasm` 1,5 Mo | ~2,4 Mo |

`main.dart.wasm` est compressé à la construction, comme les moteurs : rien ne garantit qu'un CDN
comprime `application/wasm` à la volée comme il comprime le JavaScript.

## 7. Ce que l'hébergeur fait, et pourquoi (`vercel.json`)

| Règle | Raison |
|---|---|
| `outputDirectory: build/web`, `buildCommand` et `installCommand` réduits à un `echo` | la construction a déjà eu lieu dans Actions. `scripts/deployer_pwa.py` envoie `vercel.json` à la racine du déploiement et `build/web` sous le chemin que ce fichier déclare : Vercel ne fait alors que les deux `echo`, puis sert ce qu'il a reçu, en appliquant les en-têtes et les réécritures ci-dessous |
| Réécriture de tout vers `/index.html` | `go_router` résout les routes côté client, et depuis le ticket 046 elles vivent dans le **chemin** de l'adresse : sans cette règle, un rechargement sur `/admin/planning` — ou l'ouverture d'un lien d'invitation — rendrait 404 avant même que l'application démarre. C'est la contrepartie obligatoire des adresses sans dièse |
| Aucune redirection | `/install` est une route comme les autres depuis le ticket 046. La redirection `/install` → `/#/install` du ticket 032 n'a plus d'objet : elle enverrait sur une adresse que le routeur ne sait plus lire |
| `Cache-Control: max-age=0, must-revalidate` presque partout | c'est le service worker de Flutter qui gère les versions, par empreinte de contenu. Un cache HTTP long figerait l'application sur les téléphones déjà installés. La revalidation coûte une requête conditionnelle, et seulement au premier chargement : ensuite, le service worker sert tout hors ligne |
| `Content-Encoding: br` sur `assets/assets/fonts/*.ttf` | les polices sont **livrées déjà compressées** par `scripts/build_web.sh`. Flutter web ne décode pas le WOFF2 (`assets/fonts/README.md`), le seul levier est la compression de transport : 194 Ko → 88 Ko |
| `Content-Encoding: br` sur `canvaskit/**` | même mécanique, et c'est elle qui rend l'auto-hébergement du moteur viable (ticket 037) : 5,7 Mo de `.wasm` deviennent 1,6 Mo, exactement ce que servait le CDN de Google. Servi sans cet en-tête, le moteur ne démarre pas. Depuis le ticket 065, le répertoire porte aussi Skwasm — 3,4 Mo → 1,1 Mo |
| `Content-Encoding: br` sur `main.dart.wasm` | 3,6 Mo → 1,0 Mo. Rien ne garantit qu'un CDN comprime `application/wasm` à la volée comme il comprime le JavaScript : la compression est faite à la construction et l'en-tête l'annonce. Pas de cache long, même raison que `canvaskit/**` (ticket 065) |
| `Cross-Origin-Opener-Policy: same-origin` et `Cross-Origin-Embedder-Policy: require-corp` sur **toutes** les routes | c'est la condition pour que la page ait `SharedArrayBuffer`, donc pour que Skwasm rastérise sur un fil séparé. Sans eux, la construction Wasm se charge quand même et retombe sur sa variante à un seul fil : rien ne casse, tout ralentit. Le détail et la porte de secours `credentialless` sont au § 6 bis (ticket 065) |
| `canvaskit/**` **sans** cache long | auto-hébergé, le chemin n'a plus la révision du moteur dedans. Un `immutable` d'un an figerait la version d'aujourd'hui et la prochaine montée de Flutter servirait un moteur périmé aux téléphones déjà venus. C'est le service worker qui gère les versions, par empreinte |
| `nosniff`, `Referrer-Policy`, `X-Frame-Options` | le minimum, sans politique de sécurité de contenu : le moteur a besoin de `wasm-unsafe-eval` et une CSP mal posée casse l'application en silence. `nosniff` a une conséquence de plus depuis le ticket 065 : `WebAssembly.compileStreaming` refuse alors tout ce qui n'est pas servi en `application/wasm`, et la page reste blanche sans message |

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
| Les **en-têtes d'isolation** (§ 6 bis) | **rien du tout.** L'application s'ouvre, se parcourt, et le défilement de la matrice repasse de 0 % à 37 % d'images perdues. Le seul témoin est `scripts/verifier_production.sh` § 5 |
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

Il compare cinq choses : les migrations, les Edge Functions (présence, état, `verify_jwt`),
l'adresse Vault du répartiteur de notifications, la configuration d'authentification — **sujet
du courriel de connexion et son corps** — et, depuis le ticket 065, **la PWA servie** : les deux
en-têtes d'isolation, comparés à ce que `vercel.json` déclare, et les quatre fichiers du moteur
(`main.dart.wasm`, `canvaskit/skwasm.wasm`, et leur repli `main.dart.js` +
`canvaskit/chromium/canvaskit.wasm`), reconnus à leur **type servi** et non à leur code HTTP —
la réécriture vers `index.html` rend `200 text/html` sur un fichier absent, jamais 404. Le corps est lu séparément, par
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

# 4. La PWA. La ligne de commande Vercel ne marche pas avec le jeton de projet (§ 2) :
#    c'est l'API, et le script envoie vercel.json avec la construction — sans lui, la
#    production perd ses en-têtes et sa réécriture vers index.html.
export VERCEL_TOKEN=vcp_…  VERCEL_ORG_ID=team_…  VERCEL_PROJECT_ID=prj_…
scripts/build_web.sh env/prod.json
scripts/deployer_pwa.py --dry-run     # à lire avant : ce qui partirait
scripts/deployer_pwa.py               # attend READY, puis l'alias du domaine, et rend l'adresse

# 5. Vérifier.
scripts/verifier_production.sh
```

`scripts/verifier_production.sh` regarde Supabase, et depuis le ticket 065 le moteur de rendu
servi. Pour le reste de la PWA, les sept commandes du § 6 sont la vérification — la cinquième et
la sixième disent en une seconde si la configuration et le code servis sont ceux du dépôt.

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
| `canvasKitBaseUrl` + `--no-web-resources-cdn` | `web/flutter_bootstrap.js`, `scripts/build_web.sh` | 1 620 Ko de CanvasKit depuis `www.gstatic.com` — et, depuis le ticket 065, Skwasm par le même chemin |
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

La compression de `main.dart.js` est faite par Vercel à la volée (3,9 Mo → environ 0,9 Mo en
brotli). Rien à configurer. `main.dart.wasm`, lui, est compressé à la construction : voir § 6 bis.
