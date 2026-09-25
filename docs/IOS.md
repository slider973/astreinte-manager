# L'app iOS native — Foco

Ticket 066. La PWA reste le produit et le seul canal de l'admin ; **Foco** est un second client
du pompier, en SwiftUI, branché sur la même base Supabase avec le même contrat.

| | |
|---|---|
| Code | submodule `foco/` → `slider973/Foco` (fork **privé** de `T4ruxx/Foco`) |
| Cible | iOS 26.4, iPhone et iPad, Xcode 26.4 ou plus récent |
| Base | `supabase-swift` 2.55.2 (Swift Package Manager), clé **publique** seulement |
| Tests | cible `FocoTests` (Swift Testing), `foco/scripts/ci.sh` |
| CI | `.github/workflows/ios.yml` ici, `.github/workflows/ios.yml` dans le fork |

Pourquoi `foco/` et pas `ios/` : `ios/` est le projet iOS de Flutter (`Runner`), qui reste en
place pour le jour où une caserne demande un build natif de l'app Flutter.

## 1. Cloner

```sh
git clone --recurse-submodules git@github.com:slider973/astreinte-manager.git
# ou, dans un clone existant :
git submodule update --init
```

`slider973/Foco` est privé : il faut un compte GitHub qui y a accès. Sans lui, `foco/` reste
vide et **rien d'autre ne change** — l'app Flutter, ses tests et le déploiement de la PWA
n'ont jamais besoin du submodule.

`scripts/ticket.sh start` resynchronise le submodule après son `checkout main`.

## 2. Configurer

```sh
cd foco
cp Config/Config.example.xcconfig Config/Config.xcconfig
```

`Config/Config.xcconfig` **n'est pas commité** (`.gitignore` du fork). Il porte :

| Clé | Valeur |
|---|---|
| `FOCO_SUPABASE_URL` | l'URL de l'API ; en local `http:/$()/127.0.0.1:54321` |
| `FOCO_SUPABASE_ANON_KEY` | la clé **publique** (anon / publishable) |
| `FOCO_PWA_URL` | facultatif, défaut `https://astreinte.staticflow.ch` (« Gérer la caserne ») |
| `FOCO_EXTRAS_FLAG` | facultatif ; `FOCO_EXTRAS` pour voir les extras hors schéma en local |

- Les valeurs de dev sont celles de `env/dev.json` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`), ou la
  sortie de `supabase status`. Celles de production, celles de `env/prod.json`.
- Dans un `.xcconfig`, `//` ouvre un commentaire : une URL s'écrit `https:/$()/hote`.
- **Jamais la clé de service** : l'app la reconnaît (`sb_secret_…` ou jeton `service_role`) et
  refuse de démarrer.
- Les valeurs passent par `foco/Config/Info.plist` et sont lues au démarrage
  (`Foco/Core/FocoConfig.swift`). Une valeur absente arrête l'app sur « Configuration absente »,
  qui dit laquelle.
- `127.0.0.1` ne marche que dans le simulateur. Sur un iPhone, mettre l'adresse du Mac sur le
  réseau local ou la base de production.

## 3. Ouvrir et lancer

```sh
open foco/Foco.xcodeproj
```

Schéma `Foco`, un simulateur iPhone 17 Pro sous iOS 26.4, ⌘R. Au premier lancement, Xcode
résout `supabase-swift`.

- **Mode démo** : argument de lancement `-FocoDemo` (déjà présent, décoché, dans *Edit Scheme →
  Run → Arguments*). Données en mémoire, aucune requête.
- **Connexion** : l'adresse d'un compte du seed (`membre1@caserne-a.test`), puis le code à six
  chiffres, qui arrive dans Mailpit (`http://127.0.0.1:54324`) avec la pile locale.
- **Sur l'iPhone du propriétaire** : *Signing & Capabilities* avec l'équipe Apple du
  propriétaire (le projet porte `DEVELOPMENT_TEAM = 7LTN3MGW4H`, celle de l'auteur de Foco, et
  l'identifiant `com.mazestudio.foco` : à remplacer par ceux du propriétaire).

## 4. Ce que fait le chantier 066a

| | |
|---|---|
| Connexion | code à six chiffres : `signInWithOTP(email:shouldCreateUser: false)` puis `verifyOTP(type: .email)`, mêmes messages d'erreur que la PWA, renvoi après 60 s |
| Caserne | lue de `memberships` : aucune → « Aucune caserne » (ou « Accès désactivé ») ; une → l'accueil ; plusieurs → choix après connexion, changeable dans les réglages |
| Admin | parcours pompier, plus « Gérer la caserne » qui ouvre la PWA dans Safari |
| Données | protocole `FocoBackend` : `SupabaseBackend` ou `DemoBackend` ; l'`AppStore` ne sait pas lequel |
| Parcours à venir | disponibilités (066b), propositions, astreintes, planning, accueil (066c), notifications (066d) : écran « Bientôt dans l'app » avec un lien vers la PWA, jamais de données de démo mélangées aux vraies |
| Extras | échanges, contrôles, discussion : derrière `FOCO_EXTRAS`, désactivé ; aucune table inventée |

**Contrat** (`foco/Foco/Core/Backend/SupabaseRows.swift`) : exactement les requêtes de la PWA.

| Table | Colonnes | Filtre | Côté PWA |
|---|---|---|---|
| `memberships` | `id, station_id, role, status, display_name, stations(name)` | `user_id = eq.<uid>` | `lib/core/session/membership_repository.dart` |
| `profiles` | `first_name, last_name, email, phone, push_enabled, locale` | `id = eq.<uid>`, une ligne | `lib/features/profil/data/profil_repository.dart` |

## 5. Déconnexion et caches locaux

La règle de `CLAUDE.md` s'applique à l'app iOS. Un seul point : `LocalWipe`
(`foco/Foco/Core/Session/Deconnexion.swift`), appelé par `AppStore.signOut()`. Il efface le
trousseau de l'app (la session Supabase), tout le domaine `UserDefaults`, `Caches`, `tmp`
(l'export `.ics`), `Application Support`, le cache HTTP et les cookies.

- L'effacement porte sur des domaines entiers, pas sur des clés : un nouveau stockage local est
  couvert d'office, et l'ordre n'importe plus. `signOut()` ferme d'abord la session côté serveur
  (le jeton est encore dans le trousseau), puis efface, **même si le serveur ne répond pas**.
- Une appartenance relue de l'appareil revient **toujours en simple membre** (le rôle n'est même
  pas gardé) ; le repli sur ce cache ne couvre qu'une panne réseau, jamais un refus de la base.

## 6. Vérifier

Le Mac de développement du 26 septembre 2026 a Xcode 16.2 sous macOS 14.6 : il ne peut ni
installer Xcode 26 ni compiler Foco. **La CI est le compilateur** ; la vérification se fait en
trois niveaux.

1. **Tests unitaires** (CI, à chaque changement de `foco/`) contre un faux backend : décodage des
   lignes Supabase, choix de caserne (zéro, une, plusieurs, choix gardé), repli sur le cache
   limité au réseau et rétrogradé en membre, déconnexion qui vide tout (trousseau,
   `UserDefaults`, fichiers, store), traduction des erreurs, configuration (clé de service
   refusée), extras masqués.
2. **Test d'intégration facultatif** contre le Supabase local, désactivé en CI :

   ```sh
   cd foco
   TEST_RUNNER_FOCO_IT_SUPABASE_URL=http://127.0.0.1:54321 \
   TEST_RUNNER_FOCO_IT_ANON_KEY="$(supabase status -o json | jq -r .ANON_KEY)" \
   xcodebuild test -project Foco.xcodeproj -scheme Foco \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -only-testing:FocoTests/SupabaseIntegrationTests
   ```

   Il demande un code pour `membre1@caserne-a.test`, le lit dans Mailpit, se connecte, lit les
   appartenances (CIS Saint-Martin) et le profil, puis se déconnecte.
3. **Le propriétaire sur son iPhone** (build de développement ou TestFlight), avant la fin du
   ticket.

## 7. CI

`foco/scripts/ci.sh` est la recette unique : Xcode 26.4.1 (`sudo xcode-select`), un
`Config.xcconfig` **factice** (`https://ci.invalid`, aucune vraie clé), l'iPhone 17 Pro sous le
runtime iOS 26.4, `xcodebuild build test`, puis deux captures (mode démo, écran de connexion)
gardées en artefact avec le `Package.resolved` obtenu.

- **Dans le fork** (`slider973/Foco`, `.github/workflows/ios.yml`) : à chaque poussée sur
  `feat/**` et à chaque PR. C'est là que tourne la vérification tant que la tâche d'ici n'a pas
  sa clé. Le fork étant privé, ses minutes macOS comptent dans le quota du compte (×10).
- **Ici** (`.github/workflows/ios.yml`) : seulement quand `foco` (le pointeur), `.gitmodules`
  ou le workflow changent, ou à la main. Runner `macos-26` : c'est la seule image GitHub qui
  porte Xcode 26.4.1 et un simulateur iOS 26.4 ; `macos-15` s'arrête à Xcode 26.3. Le
  submodule étant privé, la tâche a besoin du secret **`FOCO_DEPLOY_KEY`** :

  ```sh
  ssh-keygen -t ed25519 -N '' -C 'astreinte-manager CI (lecture)' -f foco_deploy_key
  gh repo deploy-key add foco_deploy_key.pub -R slider973/Foco --title 'astreinte-manager CI'
  gh secret set FOCO_DEPLOY_KEY -R slider973/astreinte-manager < foco_deploy_key
  rm foco_deploy_key foco_deploy_key.pub
  ```

  Clé en **lecture seule** (le défaut de `deploy-key add`). **À savoir avant de la poser** :
  astreinte-manager est public, donc les journaux de compilation et les captures de cette tâche
  le seront aussi, alors que le code de Foco vient d'un dépôt privé.

La CI Flutter (`ci.yml`) et le déploiement (`deploy.yml`) ne changent pas : leur
`actions/checkout` ne récupère pas les submodules, et `flutter analyze` ne lit que du Dart.
