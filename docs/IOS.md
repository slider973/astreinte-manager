# L'app iOS native — Foco

Ticket 066. La PWA reste le produit et le seul canal de l'admin ; **Foco** est un second client
du pompier, en SwiftUI, branché sur la même base Supabase avec le même contrat.

| | |
|---|---|
| Code | submodule `foco/` → `slider973/Foco` (fork **privé** de `T4ruxx/Foco`) |
| Cible | iOS 26.4, iPhone et iPad, Xcode 26.4 ou plus récent |
| Base | `supabase-swift` 2.55.2 (Swift Package Manager), clé **publique** seulement |
| Tests | cible `FocoTests` (Swift Testing), `foco/scripts/ci.sh` |
| CI | **dans le fork seulement** : [slider973/Foco → Actions](https://github.com/slider973/Foco/actions) |

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

1. **Tests unitaires** (CI du fork, à chaque PR et poussée sur `main`) contre un faux backend : décodage des
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

**La CI iOS vit dans le fork, et seulement là** :
[slider973/Foco → Actions](https://github.com/slider973/Foco/actions), workflow `iOS`
(`.github/workflows/ios.yml`), sur chaque PR vers `main` et chaque poussée sur `main`.

Pourquoi : `slider973/Foco` est le fork privé d'un dépôt privé (`T4ruxx/Foco`), que GitHub ne
permet pas de rendre public. Le compiler depuis astreinte-manager, qui est public, demanderait une
clé d'accès et rendrait publics les journaux de compilation et les captures d'un code privé. Le
propriétaire a choisi de garder tout cela privé (26 septembre 2026).

Conséquence : **une PR d'astreinte-manager ne peut pas vérifier la compilation de l'app iOS.**
D'où la règle :

> **Toute mise à jour du pointeur `foco/` doit viser un commit du fork dont la course `iOS` est
> verte** — en pratique, un commit de `main` du fork, arrivé par une PR du fork dont la course
> était verte, et dont la course sur `main` l'est aussi.

`foco/scripts/ci.sh` est la recette : Xcode 26.4.1 (`sudo xcode-select`), un `Config.xcconfig`
**factice** (`https://ci.invalid`, aucune vraie clé), l'iPhone 17 Pro sous le runtime iOS 26.4,
`xcodebuild build test`, puis deux captures (mode démo, écran de connexion) gardées en artefact
avec le `Package.resolved` obtenu. Runner `macos-26` : c'est la seule image GitHub qui porte
Xcode 26.4.1 et un simulateur iOS 26.4 ; `macos-15` s'arrête à Xcode 26.3. Le fork étant privé,
ses minutes macOS comptent dans le quota du compte (×10).

La CI Flutter (`ci.yml`) et le déploiement (`deploy.yml`) ne changent pas : leur
`actions/checkout` ne récupère pas les submodules, et `flutter analyze` ne lit que du Dart.

## 8. À reprendre (066d)

- **Accueil** : sur la carte « Astreinte », le titre « D'astreinte maintenant » passe sous
  l'illustration du casque (visible sur la capture du mode démo de la CI).
- **« Aucune caserne »** ne regarde pas les invitations en attente, contrairement à la PWA
  (ticket 051) : il affiche seulement le fait et le conseil de demander une invitation.
- **Libellé « Mon rôle »** dans les réglages (Membre ou Admin de caserne) remplace « Mon grade »
  de Foco, qu'aucune colonne du schéma ne porte : à valider avec le propriétaire.
