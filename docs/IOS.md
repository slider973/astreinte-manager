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
| Parcours à venir | propositions, astreintes, planning, accueil (066c), notifications (066d) : écran « Bientôt dans l'app » avec un lien vers la PWA, jamais de données de démo mélangées aux vraies. Les disponibilités sont branchées depuis 066b |
| Extras | échanges, contrôles, discussion : derrière `FOCO_EXTRAS`, désactivé ; aucune table inventée |

**Contrat** (`foco/Foco/Core/Backend/SupabaseRows.swift`) : exactement les requêtes de la PWA.

| Table | Colonnes | Filtre | Côté PWA |
|---|---|---|---|
| `memberships` | `id, station_id, role, status, display_name, stations(name)` | `user_id = eq.<uid>` | `lib/core/session/membership_repository.dart` |
| `profiles` | `first_name, last_name, email, phone, push_enabled, locale` | `id = eq.<uid>`, une ligne | `lib/features/profil/data/profil_repository.dart` |

## 4 bis. Ce que fait le chantier 066b — disponibilités et préférences de charge

L'écran « Disponibilités », la tuile de « Ma caserne », le rappel de l'accueil et la ligne « Date
limite de saisie » des réglages lisent la base. Le contrôleur est
`foco/Foco/Core/Availability/AvailabilityEntry.swift`, recopie de `SaisieController`
(`lib/features/dispos/presentation/controllers/saisie_controller.dart`) ; les règles pures sont
dans `AvailabilityRules.swift`, le contrat dans `foco/Foco/Core/Backend/AvailabilityContract.swift`.

**Contrat** — exactement les requêtes de `lib/features/dispos/data/dispos_repository.dart` et de
`lib/core/caserne/caserne_repository.dart` ; aucune fonction RPC en dehors de `station_access`,
que la PWA appelle aussi sur cet écran.

| Appel Swift | Requête | Preuve |
|---|---|---|
| `fetchPeriods` | `GET periods?select=id,station_id,year,month,status,deadline_at,locked_at&station_id=eq.<s>&order=year.asc,month.asc` | — |
| `fetchAvailability` | `GET availabilities?select=date,slot,status&station_id=eq&user_id=eq&date=gte.<1er>&date=lt.<1er suivant>` | — |
| `upsertAvailability` | `POST availabilities?on_conflict=station_id,user_id,date,slot&select=date,slot,status`, `Prefer: resolution=merge-duplicates,return=representation` | lignes rendues = lignes envoyées, sinon refus |
| `deleteAvailability` | `DELETE availabilities?station_id=eq&user_id=eq&or=(and(date.eq.X,slot.eq.Y),…)&select=date,slot,status` | 0 ligne sans envoi dans le lot → relecture avant d'accuser le verrouillage |
| `fetchPreferences` | `GET availability_preferences?select=period_id,max_shifts,max_weekends,comment&station_id=eq&user_id=eq&period_id=in.(<mois>,<précédent>)` | — |
| `upsertPreferences` | `POST availability_preferences?on_conflict=station_id,user_id,period_id&select=…`, `null` écrits | 0 ligne → refus |
| `fetchStationWritable` | `POST rpc/station_access {p_station}` | illisible → « écrit » ; le refus reste le filet |

**Règles, comme la PWA**

- Le mois par défaut est la première période `open`, à défaut la dernière verrouillée ; l'état et
  la date limite (« Ouvert jusqu'au 15 oct. », « Verrouillé ») viennent de `periods`. Plus aucun
  « 15 » écrit en dur, ni dans l'écran ni dans les réglages.
- Mois verrouillé ou caserne suspendue : la grille ne bouge pas, un appui affiche la phrase de la
  PWA (« Octobre 2026 est verrouillé : la saisie est fermée… »), rien ne part.
- Raccourcis : portée (les weekends, la semaine, tout le mois, copier le mois précédent, tout
  effacer) × créneau (jour, nuit, jour et nuit), seules les cases qui changent partent, copie
  alignée sur les jours de la semaine (décalage dans [-3, 3]), confirmation avant d'écraser des
  saisies, « Annuler » d'un cran.
- Préférences : maximum d'astreintes (0 à 20), de weekends (0 au nombre d'unités du mois, fériés
  français compris), commentaire de 280 caractères, écart affiché sans avertissement, reprise du
  mois précédent **écrite** et annoncée (« Repris de octobre… »).
- Enregistrement : écran optimiste, file coalescée, 500 ms de calme, rien pendant un geste ; état
  visible (« Enregistrement… », « Enregistré », « Non enregistré » + « Réessayer », « Hors
  ligne »). Un échec **ne revient pas en arrière** — la PWA non plus : la case est marquée, la file
  est gardée et rejouée. Un refus de la base (mois verrouillé entre-temps, caserne suspendue)
  affiche la phrase de la PWA avec « Recharger », qui revient à ce que la base contient et abandonne
  les écritures du mois fermé, en le disant.
- File gardée sur l'appareil (`PendingQueueMemory`, `UserDefaults`), comme `file_locale.dart` :
  elle repart au lancement suivant et part à la déconnexion avec le domaine (§ 5).

**CI** : PR [slider973/Foco#3](https://github.com/slider973/Foco/pull/3), course verte sur `main` du fork au commit `ad79bf7` ; revue : PR [slider973/Foco#4](https://github.com/slider973/Foco/pull/4), course verte sur `main` au commit `4963c4d`, visé par le pointeur `foco/`.

**Vérifié contre le Supabase local** (26 septembre 2026, `membre1@caserne-a.test`, code lu dans
Mailpit) : chaque requête ci-dessus rejouée en `curl`, l'écriture relue par la requête de la PWA
et en base (`set_by` = le membre, posé par `availabilities_trace_auteur`) ; `upsert` sur octobre
verrouillé → `403` `42501` ; `delete` sur octobre → `200 []`, d'où le comptage des lignes.

## 5. Déconnexion et caches locaux

La règle de `CLAUDE.md` s'applique à l'app iOS. Un seul point : `LocalWipe`
(`foco/Foco/Core/Session/Deconnexion.swift`), appelé par `AppStore.signOut()`. Il efface le
trousseau de l'app (la session Supabase), tout le domaine `UserDefaults`, `Caches`, `tmp`
(l'export `.ics`), `Application Support`, le cache HTTP et les cookies.

- `signOut()` fait trois choses, dans cet ordre :
  1. **la saisie** : `AvailabilityEntry.reset()` arrête minuteurs et envois, pour qu'aucune
     écriture en vol ne réécrive sa file sur l'appareil après l'effacement ;
  2. **la session** : fermée côté serveur tant que le jeton est encore dans le trousseau ;
  3. **l'effacement** (`LocalWipe`), **même si le serveur ne répond pas**.
- L'effacement porte sur des domaines entiers, pas sur des clés : un nouveau stockage local est
  couvert d'office. C'est le cas de la file des disponibilités (`PendingQueueMemory`, clé
  `foco.dispos.file.<caserne>.<membre>`, 066b).
- Une appartenance relue de l'appareil revient **toujours en simple membre** (le rôle n'est même
  pas gardé) ; le repli sur ce cache ne couvre qu'une panne réseau, jamais un refus de la base.

## 6. Vérifier

Le Mac de développement du 26 septembre 2026 a Xcode 16.2 sous macOS 14.6 : il ne peut ni
installer Xcode 26 ni compiler Foco. **La CI est le compilateur** ; la vérification se fait en
trois niveaux.

1. **Tests unitaires** (CI du fork, à chaque PR et poussée sur `main`) contre un faux backend : décodage des
   lignes Supabase, choix de caserne (zéro, une, plusieurs, choix gardé), repli sur le cache
   limité au réseau et rétrogradé en membre, déconnexion qui vide tout (trousseau,
   `UserDefaults`, fichiers, store, file des disponibilités), traduction des erreurs, configuration
   (clé de service refusée), extras masqués ; et pour 066b : période ouverte, verrouillée, date
   limite, chaque raccourci, copie du mois précédent, préférences et écart, reprise, échec puis
   « Réessayer », refus puis « Recharger », hors ligne, file gardée puis rejouée, contrat figé et
   décodage des réponses relevées sur le seed.
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
`xcodebuild build test`, puis trois captures (mode démo : accueil et saisie des disponibilités,
ouverte par `-FocoOpenAvailability` ; écran de connexion) gardées en artefact
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
- **Retour du réseau (`NWPathMonitor`)** : rejouer la file des disponibilités dès que le réseau
  revient, comme `enLigneProvider` dans la PWA, au lieu d'attendre « Réessayer » ou le lancement
  suivant (revue du 066b).
- **Grille sur un écran de 375 pt** (iPhone SE, mini) : sept colonnes n'y laissent qu'environ
  40 pt de large par case ; la hauteur fait 44 pt, la largeur pas encore (revue du 066b).
- **Classement des erreurs inconnues** : une réponse sans corps PostgREST (`HTTPError`) ou
  illisible est classée « inconnue » et relancée ; la PWA classe un code absent en panne réseau.
  À aligner (revue du 066b).
- **Deux écarts de la PWA, confirmés par la revue du 066b** (détail plus bas, `lib/` non touché) :
  `_chargerPreferences` écrit la reprise sur une caserne suspendue ; `EtatSaisie.mois` compte la
  file d'un autre mois.

### Écarts de 066b avec la PWA, et pourquoi

- **Pas de moniteur réseau.** La PWA rejoue sa file au retour du réseau (`enLigneProvider`) ;
  l'app iOS relance à 1 s et 4 s, puis attend « Réessayer », la réouverture de l'écran ou le
  lancement suivant. La file n'est jamais perdue.
- **Interaction de Foco gardée** : un pinceau (Disponible / Absent), une touche qui pose le pinceau
  ou revient à « non saisi », au lieu du cycle de la PWA (non saisi → disponible → absent). Les
  lignes écrites sont les mêmes. Pas d'annulation de geste à deux doigts.
- **Raccourcis dans un menu natif** (portée ▸ créneau) plutôt qu'une feuille : mêmes portées,
  mêmes créneaux, même compte, même confirmation.
- **Cases de 44 pt** (règle binding de `CLAUDE.md`) : la pastille de Foco reste de 32 pt, sa cible
  en fait 44 ; la grille s'allonge d'autant.
- **Jamais la couleur seule** (revue) : la pastille porte une coche (disponible), une croix et des
  hachures (absent) ou un filet en tirets (non saisi), comme `StatusDescriptor` de la PWA, décrits
  par `SlotAppearance` ; une légende les nomme sous le pinceau. La palette de Foco ne change pas.
- **Compteurs** : la tuile « Absent » de Foco est retirée (la PWA ne compte que les disponibles) ;
  les fériés sont ceux de la PWA (français, Pâques compris) et plus la liste fixe de Foco, qui
  comptait le 1er août suisse.
- **Préférences** : Foco partait de « 4 astreintes, 1 weekend » ; la valeur par défaut est
  désormais celle de la base, *autant que nécessaire*.
- **Envois en série** : l'`upsert`, le `delete` et les préférences d'un lot partent l'un après
  l'autre, là où la PWA les lance ensemble (`Future.wait`). Mêmes requêtes, même nombre.

### Écarts relevés dans la PWA (signalés, non corrigés : `lib/` n'est pas touché ; confirmés par la revue)

- **Reprise des préférences sur une caserne suspendue.** `_chargerPreferences` ne regarde que
  `_lectureSeuleConnue` (un refus déjà essuyé), pas `lectureSeuleCaserneProvider` : sur une caserne
  que `station_access` dit suspendue, la PWA met la reprise en file et récolte un refus « Ta caserne
  est passée en lecture seule ». L'app iOS ne l'écrit pas.
- **Compteurs et file d'un autre mois.** `EtatSaisie.mois` est construit de `{...lues, ..._file}`
  sans filtrer la file par mois : une écriture en attente d'un autre mois entre dans les
  compteurs et dans « Octobre saisi » de l'accueil. L'app iOS ne compte que le mois affiché.
