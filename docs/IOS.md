# L'app iOS native — Astreinte SP (projet Foco)

Ticket 066. La PWA reste le produit et le seul canal de l'admin ; **Foco** est un second client
du pompier, en SwiftUI, branché sur la même base Supabase avec le même contrat.
Depuis le ticket 067, l'app s'affiche **« Astreinte SP »**, comme la PWA, avec son icône ;
« Foco » ne reste que le nom interne du projet Xcode, du fork et du submodule.

| | |
|---|---|
| Code | submodule `foco/` → `slider973/Foco` (fork **privé** de `T4ruxx/Foco`) |
| Cible | iOS 26.4, iPhone et iPad, Xcode 26.4 ou plus récent |
| Base | `supabase-swift` 2.55.2 (Swift Package Manager), clé **publique** seulement |
| Push | `firebase-ios-sdk` 12.17.0 (Swift Package Manager, `FirebaseCore` et `FirebaseMessaging`), `GoogleService-Info.plist` **non commité** |
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
| `FOCO_REVIEW_EMAIL` | facultatif, défaut `revue-apple@astreinte-sp.fr` (`Config/Foco.xcconfig`, versionné : ce n'est pas un secret) ; la seule adresse connectée par mot de passe (§ 10, ticket 076). Vide : personne |

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
- **Push (066d)** : `foco/Foco/GoogleService-Info.plist`, téléchargé depuis la console Firebase
  (`docs/FIREBASE.md § 9`). **Jamais commité** (`.gitignore` du fork ; exemple dans
  `Config/GoogleService-Info.example.plist`). Sans lui — la CI, un clone neuf —, l'app se
  construit, fonctionne sans push, et ses réglages disent « Notifications : Indisponibles sur
  cette installation ».

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
- **Sur l'iPhone du propriétaire** : identifiant `ch.staticflow.astreintesp` (ticket 067). Le
  projet ne code plus aucune équipe : `DEVELOPMENT_TEAM = $(FOCO_TEAM_ID)` dans
  `Config/Foco.xcconfig`, et `FOCO_TEAM_ID = <équipe>` dans son `Config/Config.xcconfig` local.

## 4. Ce que fait le chantier 066a

| | |
|---|---|
| Connexion | code à six chiffres : `signInWithOTP(email:shouldCreateUser: false)` puis `verifyOTP(type: .email)`, mêmes messages d'erreur que la PWA, renvoi après 60 s |
| Caserne | lue de `memberships` : aucune → « Aucune caserne » (ou « Accès désactivé ») ; une → l'accueil ; plusieurs → choix après connexion, changeable dans les réglages |
| Admin | parcours pompier, plus « Gérer la caserne » qui ouvre la PWA dans Safari |
| Données | protocole `FocoBackend` : `SupabaseBackend` ou `DemoBackend` ; l'`AppStore` ne sait pas lequel |
| Parcours à venir | **aucun depuis 066d**. L'écran « Bientôt dans l'app » reste pour un backend qui dirait un parcours à venir (tests) ; jamais de données de démo mélangées aux vraies |
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
  les écritures du mois fermé, en le disant. Depuis le ticket 068, la cause est relue
  (`station_access`, puis `periods`) et un refus inexpliqué reste neutre (§ 4 sexies).
- File gardée sur l'appareil (`PendingQueueMemory`, `UserDefaults`), comme `file_locale.dart` :
  elle repart au lancement suivant et part à la déconnexion avec le domaine (§ 5).

**CI** : PR [slider973/Foco#3](https://github.com/slider973/Foco/pull/3), course verte sur `main` du fork au commit `ad79bf7` ; revue : PR [slider973/Foco#4](https://github.com/slider973/Foco/pull/4), course verte sur `main` au commit `4963c4d` (pointeur du 066b).

**Vérifié contre le Supabase local** (26 septembre 2026, `membre1@caserne-a.test`, code lu dans
Mailpit) : chaque requête ci-dessus rejouée en `curl`, l'écriture relue par la requête de la PWA
et en base (`set_by` = le membre, posé par `availabilities_trace_auteur`) ; `upsert` sur octobre
verrouillé → `403` `42501` ; `delete` sur octobre → `200 []`, d'où le comptage des lignes.

## 4 ter. Ce que fait le chantier 066c — propositions, mes astreintes, planning, accueil

Les écrans « Propositions », « Mes astreintes », « Planning de la caserne », « Aujourd'hui »,
« Équipe », le détail d'une journée et l'accueil lisent la base. Le contrôleur est
`foco/Foco/Core/Planning/PlanningJourney.swift`, recopie de `PropositionsController`,
`AstreintesController`, du planning de la caserne et de `CalendrierController` ; les valeurs sont
dans `PlanningModels.swift`, le contrat dans `foco/Foco/Core/Backend/PlanningContract.swift`.
L'`AppStore` **recompose** ses créneaux, plannings, attributions et son équipe à partir de ces
lectures (`rebuildPlanning`) : ce que la RLS ne laisse pas lire n'y entre pas. Le mode démo passe
par les mêmes règles (`DemoBackend` imite la RLS : brouillon invisible, publié = ses lignes).

**Contrat** — exactement les requêtes de `lib/features/propositions/data/`,
`lib/features/astreintes/data/` et `lib/features/profil/data/calendrier_repository.dart` ; aucune
colonne hors de `docs/SCHEMA.md`, aucune fonction RPC en dehors de `my_ics_token`.

| Appel Swift | Requête | Côté PWA |
|---|---|---|
| `fetchProposals` | `GET assignments?select=id, status, proposed_at, reminder_count, last_reminder_at, shifts!inner(id, date, slot, schedule_id, schedules!inner(id, status))&user_id=eq&station_id=eq&status=eq.proposed&proposed_at=not.is.null` | `lister` ; un mois archivé est écarté (`repondable`) |
| `respond` | `PATCH assignments?id=eq.<a>&status=eq.proposed&select=id`, corps `{status}` ou `{status, decline_reason}` | `repondre` ; 0 ligne = « plus proposée » |
| `fetchScheduleStatus` | `GET schedules?select=status&id=eq.<p>` | `etatPlanning`, après la dernière acceptation |
| `fetchDuties` | `GET stations?select=id, name, timezone, settings&id=eq` ; `GET assignments?select=id, shift_id, status, shifts!inner(…)&user_id=eq&station_id=eq&status=eq.accepted&shifts.date=gte.<un an>` ; si validé ou archivé : `GET assignments?select=shift_id, user_id, status&station_id=eq&status=eq.accepted&shift_id=in.(…)` puis `GET memberships?select=user_id, display_name, profiles!inner(first_name, last_name)&station_id=eq` | `lire`, `_equipiers` |
| `fetchPlanningMonths` | `GET schedules?select=id, status, periods!inner(year, month)&station_id=eq&status=in.(published,validated,archived)` | `moisLisibles` |
| `fetchPlanningMonth` | `GET shifts?select=id, date, slot, required_count&schedule_id=eq` ; `GET assignments?select=id, user_id, shift_id, shifts!inner(schedule_id)&station_id=eq&status=eq.accepted&shifts.schedule_id=eq` ; les noms si quelqu'un d'autre ; `stations` | `lireMois` |
| `fetchMemberNames` | `GET memberships?select=user_id, display_name, profiles!inner(first_name, last_name)&station_id=eq` | `_noms` (écran « Équipe ») |
| `fetchCalendarToken` | `POST rpc/my_ics_token` (aucun paramètre) | `lireJeton` |

**Temps réel : aucun**, comme la PWA côté membre (`lib/features/propositions/README.md`,
`lib/features/boite/README.md` : seuls la matrice et le suivi de l'admin ouvrent un canal).
L'app relit à l'ouverture de chaque écran et au retour au premier plan (`scenePhase`) ; depuis le
ticket 071, aussi au retour sur l'accueil et à un push reçu au premier plan (§ 4 septies).

**Règles, comme la PWA**

- **Réponse optimiste** : la ligne part tout de suite ; un échec réseau la remet **à sa place
  exacte** avec « Ta réponse n'est pas partie. » et la phrase de la PWA ; un refus de la base
  (`42501`, `station_suspended`) passe l'écran en lecture seule (« Caserne suspendue : les
  réponses sont bloquées… ») ; zéro ligne touchée dit « Ce créneau ne t'est plus proposé. »
  (reprise ou réattribution, `docs/WORKFLOWS.md § 3`). La dernière acceptation d'un planning
  relit `schedules.status` et annonce « Planning d'octobre validé : tout le monde peut le voir
  maintenant. ». Une seconde touche ne renvoie rien.
- **Refus avec motif** : une feuille, deux touches ; titre « Refuser samedi 10 octobre, jour »,
  « Un refus ne se reprend pas… », motif facultatif de 120 caractères, « Refuser le créneau »,
  « Garder le créneau ». Le motif est coupé des blancs ; vide, il n'est pas écrit (pas même `null`).
- **Délai de réponse** : « Sans réponse sous 24 h, un rappel est envoyé. » tire le nombre de
  `response_reminder_hours` ; tant que la caserne n'est pas lue, la phrase se tait.
- **Caserne suspendue** : `station_access`, déjà lu par la saisie (066b), grise les boutons avant
  le premier geste, avec la raison écrite.
- **Mes astreintes** : un an d'historique, à venir par mois, **passées repliées** (« Astreintes
  passées (n) »), frontière au jour ; équipiers nommés seulement sur un planning validé ou
  archivé, sinon « Autres noms à la validation du planning ». Une relecture ratée garde l'écran
  et dit « Ces astreintes n'ont pas pu être actualisées. ».
- **Heures** : celles de la caserne (`day_start`, `day_end`), 07:00 – 19:00 par défaut ; plus
  aucun 06–18 écrit en dur.
- **Lien d'abonnement** : « S'abonner dans Calendrier » ouvre `webcal://<hôte>/functions/v1/
  ics-feed/<jeton>.ics` (le lien `https` de la PWA, schéma changé) ; « Copier le lien » ;
  l'avertissement et le délai de la PWA. Dans « Mes astreintes », les réglages et le menu de
  l'accueil. L'export `.ics` local de Foco est retiré.
- **Planning de la caserne** : le mois d'ouverture de la PWA (courant, sinon le premier à venir,
  sinon le plus récent) ; un mois se lit quand on l'atteint ; **brouillon invisible**, publié =
  ses seuls créneaux avec « Planning publié, pas encore validé » et sa phrase, validé ou archivé =
  toute la caserne. Vues mois, semaine et 3 jours gardées ; chaque état a son glyphe et son mot
  (coche « Toi », point d'interrogation « Proposée », point d'exclamation « Non pourvu »,
  soleil / lune), la couleur vient en plus ; flèches et boutons de 44 pt.
- **Accueil** : la carte « Astreinte » dit « Un instant » tant que les astreintes ne sont pas lues,
  « Ça n'a pas marché » si la lecture échoue, puis la prochaine astreinte réelle ou « Repos » ;
  « À traiter » ne compte les propositions qu'une fois lues ; la carte « Aujourd'hui »
  n'apparaît qu'une fois le jour lu, et dit ce que la base permet d'affirmer (« Aucun planning
  publié ce mois-ci », « Tu n'as pas d'astreinte aujourd'hui », « Aucun créneau aujourd'hui ») ;
  « N d'astreinte maintenant » seulement sur un planning validé ; les tuiles restent vides avant
  lecture et disent « Lecture impossible » après un échec, jamais « Rien en attente ». La
  **cloche** est la Boîte : tant que les notifications n'ont pas d'écran (066d), elle mène aux
  propositions et porte **leur nombre écrit** (plus un point de couleur).

**CI** : PR [slider973/Foco#5](https://github.com/slider973/Foco/pull/5), courses vertes sur la PR ([36214822569](https://github.com/slider973/Foco/actions/runs/36214822569), [36215323242](https://github.com/slider973/Foco/actions/runs/36215323242), 143 tests), fusionnée en squash ; course verte sur `main` du fork ([36215903852](https://github.com/slider973/Foco/actions/runs/36215903852)) au commit `7ec81e5`. Revue : PR [slider973/Foco#6](https://github.com/slider973/Foco/pull/6), course verte ([36217029919](https://github.com/slider973/Foco/actions/runs/36217029919), 146 tests, aucun avertissement Swift), fusionnée en squash ; course verte sur `main` du fork ([36217571649](https://github.com/slider973/Foco/actions/runs/36217571649), 146 tests, 0 avertissement) au commit `573f5e0`, visé par le pointeur `foco/`.

**Vérifié contre le Supabase local** (26 septembre 2026, `membre1@caserne-a.test`, code lu dans
Mailpit ; données posées puis retirées, seed remis dans son état d'origine) :

- planning d'octobre **en brouillon** : `schedules?…status=in.(published,validated,archived)` →
  `[]`, `shifts?…schedule_id=eq.<octobre>` → `[]` ;
- publié (`publish_schedule`) : trois propositions, triées par l'app (10 jour, 10 nuit, 17 jour) ;
  `shifts` du mois → 62 lignes ; attributions acceptées du mois → `[]` (aucune des siennes) ;
- `PATCH …&status=eq.proposed&select=id` `{"status":"accepted"}` → `200 [{"id":…}]` ; refus
  `{"status":"declined","decline_reason":"En formation ce week-end"}` → `200`, relu en base
  (`declined`, motif, `responded_at` posé par la base) ; la même acceptation rejouée → `200 []` ;
  la proposition d'un collègue → `200 []` ; `{"status":"cancelled"}` → `400 P0001
  assignment_transition_reserved` ;
- caserne suspendue (`subscriptions.status = suspended`) : `PATCH` → `200 []` (la politique filtre
  sans lever ; voir les écarts), `rpc/station_access` → `{"writable": false, "status":
  "suspended"}` ;
- publié : « Mes astreintes » → la seule acceptée, sans équipier ; les attributions du mois → la
  sienne seulement ;
- validé : équipiers du 10 octobre → Marie L. et Thomas M. (le lecteur est écarté par l'app),
  noms depuis `memberships` (`display_name` d'abord), attributions du mois → toute la caserne ;
- `rpc/my_ics_token` → `200`, un jeton de 48 caractères hexadécimaux. `ics-feed` n'a pas été
  appelé : l'Edge Runtime local était arrêté.

### Écarts de 066c avec la PWA, et pourquoi

- **« 1/3 pourvus »** : l'effectif pourvu d'un créneau n'est pas lisible par un membre sur un
  planning publié (`assignments_select_own_published`, écart « 1/3 pourvus » du 064a dans
  `DESIGN.md`). L'app ne l'écrit (« 1/2 pourvu »), ni ne marque « Non pourvu » / « Place libre »,
  que sur un planning **validé ou archivé et lu** ; publié, la carte d'un créneau ne porte que ses
  heures et « Les autres noms s'afficheront quand ton chef de centre aura validé le planning. ».
- **« Vos réponses »** (les propositions déjà répondues) de Foco est retiré : la PWA ne lit aucune
  attribution `declined` pour le membre, et ce serait une requête de plus.
- **« Créneau non pourvu » dans « À traiter »** : passé derrière `FOCO_EXTRAS` (reprendre un
  créneau est un échange, v1.1) ; un compte sur les seuls mois lus serait d'ailleurs partiel.
- ~~**La cloche** mène aux propositions et en porte le nombre~~ : depuis 066d, elle mène au centre
  de notifications et porte le compte des rappels non lus, comme la Boîte.
- **Pas de cache local** des astreintes et du planning (la PWA garde `cache_astreintes` et
  `cache_planning_caserne` pour le hors-ligne) : hors ligne à l'ouverture, l'écran dit l'erreur
  avec « Réessayer » ; ce qui a été lu reste en mémoire pendant la session.
- **Pas de blocage « hors ligne » avant le geste** (`enLigneProvider`, « Une réponse a besoin du
  réseau… ») : la réponse part, échoue et la ligne revient à sa place avec la phrase du réseau.
  Toujours vrai après 066d (le moniteur réseau ne sert que la file des disponibilités).
- **Pas de fichier `.ics` par astreinte** (« Ajouter à mon agenda » du détail) ni de
  « Régénérer le lien » : seul l'abonnement, ouvert en `webcal://` ou copié.
- **Écran « Équipe »** : la PWA n'en a pas côté membre ; l'app y liste les noms que rend la
  requête de `_noms` (sans filtre de statut, comme elle), sans rôle pour les collègues (aucune
  colonne lue ne le porte). Seuls les membres actifs y paraissent pour un membre : la politique
  `profiles_select_self_or_same_station` n'ouvre le profil d'un collègue que si son appartenance
  est active, et `profiles!inner` écarte les lignes dont le profil est illisible (vérifié sur la
  politique en base). Un admin, lui, lit aussi les profils des désactivés.
- **Relectures** : une acceptation relit « Mes astreintes », et la dernière d'un planning la
  liste des mois — les mêmes requêtes que la PWA à l'ouverture de ces écrans, jouées tout de suite
  pour que l'accueil ne mente pas.
- **Boutons** : « Accepter » et « Refuser » de même largeur (pilules de Foco) au lieu de
  l'asymétrie trois cinquièmes / deux cinquièmes ; `PillButton` porté à 44 pt de haut.
- **L'accueil compte toutes les propositions répondables**, comme la pastille de la Boîte
  (`propositionsEnAttenteProvider`) ; la section de l'accueil de la PWA écarte en plus celles
  d'un jour passé.
- **Mode démo** : la validation automatique d'un planning y est simplifiée (plus rien de proposé
  dans le mois).
- **Tutoiement** : les badges disent « TOI » (`FocoStrings.you`) depuis la revue du 066c, comme
  la légende et la PWA ; les chaînes de l'accueil et de l'équipe vivent dans `FocoStrings`.

### Écarts relevés dans la PWA au 066c (signalés, non corrigés : `lib/` n'est pas touché)

- **Caserne suspendue et réponse.** Vérifié en `curl` : sur une caserne suspendue, le `PATCH` d'une
  réponse rend `200 []` (la politique `using` filtre la ligne) et non `42501`. Si
  `station_access` n'a pas pu être lu, `repondre` rend donc `disparue`, et la PWA annonce « Ce
  créneau ne t'est plus proposé. » au lieu de la lecture seule. L'app iOS a le même comportement,
  puisqu'elle suit la même règle.

## 4 quater. Ce que fait le chantier 066d — notifications, push, liens profonds, fini

**Centre de notifications** (`foco/Foco/Core/Notifications/NotificationInbox.swift`, écran
`Features/Station/NotificationsView.swift`) : la Boîte de la PWA. Les rappels et infos de la
caserne, la plus récente en premier, les propositions en tête (elles se répondent dans leur écran) ;
marquer lu d'une touche, qui ouvre aussi l'écran lié ; « Tout marquer comme lu » en bas, présent
seulement s'il y a quelque chose à marquer. La **cloche** de l'accueil porte le compte des
**rappels non lus** (`EtatCentre.nonLues`), la tuile « Notifications » de « Ma caserne » aussi
(« 2 non lues », « Tout est lu », rien avant la lecture, « Lecture impossible » après un échec).

**Contrat** (`foco/Foco/Core/Backend/NotificationsContract.swift`) — exactement les requêtes de
`lib/features/notifications/data/`, `lib/features/profil/data/profil_repository.dart` et
`lib/features/invitation/data/invitation_repository.dart`. Aucune colonne hors de
`docs/SCHEMA.md`, aucune fonction en dehors de `my_pending_invitations` et, depuis le ticket 057,
`register_push_token`, aucun canal temps réel.

| Appel Swift | Requête | Côté PWA |
|---|---|---|
| `fetchNotifications` | `GET notifications?select=id, type, title, body, data, read_at, error, created_at&user_id=eq&channel=eq.inapp&order=created_at.desc&limit=200` | `lister` |
| `markNotificationRead` | `PATCH notifications?id=eq.<n>&read_at=is.null&select=read_at`, `{read_at}` | `marquerLue` |
| `markAllNotificationsRead` | `PATCH notifications?user_id=eq&channel=eq.inapp&read_at=is.null&select=id`, `{read_at}` | `toutMarquerLu` |
| `registerPushToken` | `POST rpc/register_push_token`, `{p_token, p_platform: "ios", p_device_label}` *(ticket 057 ; avant : `upsert` direct sur `push_tokens`)* | `enregistrer` |
| `deletePushToken` | `DELETE push_tokens?token=eq.<t>`, `return=minimal` | `oublier` |
| `setPushEnabled` | `PATCH profiles?id=eq.<u>`, `{push_enabled}` ; lu par la lecture du profil du 066a | `definirPushNonCritiques` |
| `fetchPendingInvitations` | `POST rpc/my_pending_invitations` (aucun paramètre) | `mesInvitations` |
| `acceptInvitation` | `POST functions/v1/accept-invitation`, `{invitation_id}` | `accepter` (entrée par identifiant) |

**Règles, comme la PWA**

- **Un rappel est une notification qui n'est pas une proposition** : `assignment_proposed` et
  `assignment_reminder` ne s'affichent pas en rappel et ne comptent pas dans la cloche ;
  `assignment_changed`, si. La règle porte sur le type, jamais sur la route.
- **Marquer lu est optimiste** : la ligne change tout de suite ; un échec la remet non lue et
  l'écran dit « Notification non marquée lue. Réessaie dans un instant. » (annoncé à VoiceOver) ;
  une ligne déjà lue ailleurs (zéro ligne rendue) n'est pas un échec. « Tout marquer comme lu »
  dit « Tout est marqué lu. », ou remet tout en place sur un échec.
- **Une relecture ne vide pas l'écran** : première lecture ratée → « Impossible de lire tes
  notifications. Vérifie ta connexion. » avec « Réessayer » ; relecture ratée → la liste reste,
  avec la même phrase.
- Relu à l'ouverture, au retour au premier plan, au tirage, à un push reçu ou touché.

**Push** (`Core/Notifications/PushCenter.swift`, Firebase isolé dans `App/FirebasePush.swift`) :

- `firebase-ios-sdk` 12.17.0 en version exacte, produits `FirebaseCore` et `FirebaseMessaging`
  seulement ; tout le reste de l'app passe par le protocole `PushMessaging`. **Pourquoi pas plus
  récent** : 12.18.0 déprécie les API du jeton d'enregistrement FCM au profit d'une inscription par
  identifiant d'installation, que ni `push_tokens` ni l'Edge Function d'envoi (`message.token`) ne
  savent viser ; les garder aurait coûté deux avertissements, en changer est un ticket de bout en
  bout, serveur compris.
- **Sans `GoogleService-Info.plist`**, `UnavailablePushMessaging` : aucun appel à Google, état
  « Indisponibles sur cette installation », l'app fonctionne.
- **L'autorisation n'est demandée que sur un geste**, jamais au lancement à froid : la carte
  « Reçois les propositions » de l'accueil (une fois, après l'entrée dans la caserne — la dernière
  étape de l'accueil de la PWA) ou le bloc « Notifications » des réglages. Refusée : la phrase et
  « Ouvrir les réglages de l'iPhone » ; jamais redemandée.
- **Jeton** : publié à chaque lancement quand l'autorisation est accordée (`last_seen_at` à jour,
  posé par le serveur, comme la PWA), `platform = ios` (la valeur existe dans `push_platform` depuis
  la migration `0001`), `device_label` « iPhone · app iOS ». Un jeton rafraîchi par FCM est écrit,
  puis l'ancien supprimé (`JetonPushController.publier`). Depuis le ticket 057, par
  `register_push_token` (voir § 4 quinquies).
- **Déconnexion** : le jeton quitte `push_tokens` **avant** la fermeture de session (la RLS
  `push_tokens_delete_self` le permet encore) et **avant** `LocalWipe` (sa mémoire est encore
  lisible), puis FCM l'oublie (`deleteToken`) : un jeton qui n'a pas pu être supprimé meurt côté
  FCM et l'Edge Function d'envoi le nettoiera.
- **`push_enabled`** : lu avec le profil, basculé par « Rappels et infos » (optimiste, remis en
  place sur un échec avec « Réglage non enregistré… »), inerte tant que les notifications ne sont
  pas activées ; « Les propositions d'astreinte arrivent toujours. » Le serveur applique le
  réglage (`notification_send.ts`).
- **Au premier plan**, la bannière du système s'affiche (`willPresent`) et le centre est relu.
- **Capacités** : `aps-environment` (`Config/Foco.entitlements`), `UIBackgroundModes =
  remote-notification` (`Config/Info.plist`), *swizzling* de Firebase coupé (le jeton APNs passe
  par `FocoAppDelegate`). La CI construit sans signature ni compte Apple.

**Liens profonds** (`Core/Notifications/PushDestination.swift`) : la table de `docs/WORKFLOWS.md
§ 8`, une notification touchée ouvrant l'écran natif **app froide comme chaude** (le lien est gardé
par `PushRelay` puis par le store jusqu'à ce que les appartenances soient lues) ; les deux liens de
l'admin ouvrent la PWA dans Safari ; un lien inconnu, mal formé ou interdit laisse sur l'accueil,
sans message. Une ligne touchée du centre passe par la même fonction.

**Passe de fini** (la section « À reprendre » du 066c) :

| Point | Fait |
|---|---|
| Titre de l'accueil sous le casque | Avec un créneau, l'illustration quitte le fond de la carte « Astreinte » et se place **à côté** du titre (56 pt) ; le titre tient sur deux lignes au plus |
| « Aucune caserne » et les invitations | L'écran pose la question avant de répondre (`my_pending_invitations`, ticket 051) : recherche, invitations valables avec « Rejoindre <caserne> » (`accept-invitation` par identifiant, puis appartenances relues), invitations expirées avec qui les renverra, rien (le texte du 006), échec ou hors ligne (le fait seul) ; relu au retour au premier plan |
| « Mon rôle » | « Ton rôle », comme l'accueil et le profil de la PWA (`accueilRoleLabel`, `profilCaserneRole`) |
| Retour du réseau | `NWPathMonitor` (`Core/Session/NetworkMonitor.swift`) : au passage hors ligne → en ligne, la file des disponibilités repart d'elle-même |
| Grille à 375 pt | Carte de 4 pt de marge, 2 pt entre colonnes : 311 pt pour sept cases, **44,4 pt** par case sur un iPhone SE ou mini |
| Erreurs inconnues | Le classement de `_traduire` : un code PostgREST absent, une réponse sans corps PostgREST ou illisible sont une panne réseau (attente, rejouée) ; seule l'authentification reste « inconnue » |
| VoiceOver | Avatar « Réglages », menu « Plus d'actions », cartes de l'accueil lues d'un trait et ouvrables, flèches des mois nommées, cases du planning lues avec leurs créneaux et leur état en mots, lignes du centre lues comme la PWA (« Non lue. Titre. Corps. Ancienneté. »), annonces des gestes |
| Dynamic Type | Toutes les polices suivent la taille du système (relatives au style de texte le plus proche), plafonnées à **AX3** ; les rangées passent en colonne aux tailles d'accessibilité (créneaux, réponses, compteurs, préférences, légendes), « Ma caserne » passe sur une colonne, le planning défile |

**Vérifié contre le Supabase local** (26 septembre 2026, `membre1@caserne-a.test` et un compte
invité sans caserne, codes lus dans Mailpit ; lignes posées puis retirées, seed remis dans son
état d'origine) :

- liste : quatre lignes `inapp` du membre, la plus récente en premier ; la ligne `push` et celle de
  Thomas M. absentes ; `user_id=eq.<Thomas>` → `[]` (`notifications_select_self`) ;
- marquer lu → `200 [{"read_at": …}]` ; rejoué → `200 []` ; la ligne d'un autre → `200 []` ;
  `{read_at, title}` → `403 42501 permission denied for table notifications` (grant de colonne) ;
- tout marquer lu → `200` et les trois autres identifiants ; en base, la ligne `push` et celle de
  l'autre membre restent non lues ;
- jeton : `upsert` `platform = ios` → `201`, rejoué → `200`, une ligne, `last_seen_at`
  rafraîchi, `device_label` repassé à `null` ; au nom d'un autre → `403 42501` ; `DELETE` → `204`,
  plus aucune ligne ;
- `push_enabled` → `204`, relu `false` par la requête du profil, remis à `true` ;
- `rpc/my_pending_invitations` : membre de caserne → `[]` ; compte invité sans appartenance → les
  deux invitations (valable, « Jean Dupont », et expirée), `invitations` en lecture directe → `[]` ;
- `accept-invitation` `{invitation_id}` : expirée → `410 invitation_expired` ; valable → `200`,
  appartenance active relue par la requête du 066a, l'invitation quitte la liste.

**CI** : PR [slider973/Foco#7](https://github.com/slider973/Foco/pull/7). Première course
rouge ([36221045231](https://github.com/slider973/Foco/actions/runs/36221045231) : un `#expect`
de test qui ne compilait pas, et deux avertissements de dépréciation Firebase — d'où l'épinglage en
12.17.0), puis vertes ([36221277439](https://github.com/slider973/Foco/actions/runs/36221277439),
[36222088597](https://github.com/slider973/Foco/actions/runs/36222088597),
[36222896964](https://github.com/slider973/Foco/actions/runs/36222896964) : 190 tests,
0 avertissement Swift de l'app, 13 captures dont le centre de notifications et six à AX3 (la capture des disponibilités peut sortir blanche : attente fixe de 8 s dans `scripts/ci.sh`, à fiabiliser)),
fusionnée en squash ; course verte sur `main` du fork
([36223546760](https://github.com/slider973/Foco/actions/runs/36223546760), 190 tests,
0 avertissement) au commit `be48a1c`, visé par le pointeur `foco/`.

### Écarts de 066d avec la PWA, et pourquoi

- **Pas d'onglets** : la PWA a une Boîte à trois onglets (Tout, Propositions, Rappels) ; l'app a
  déjà son écran « Propositions ». Le centre montre les rappels, et les propositions en tête par un
  lien vers leur écran. Mêmes lignes, même compte.
- **Au premier plan, la bannière d'iOS** plutôt que le bandeau maison de la PWA
  (`CoucheNotifications`), qui existe parce que le navigateur n'affiche rien au premier plan.
- **L'invitation à activer est une carte de l'accueil**, pas un écran de fin d'accueil : l'app iOS
  n'a pas de parcours d'accueil (profil, guide). Une seule fois, jamais avant l'entrée dans la
  caserne, rien de demandé sans le geste.
- ~~**La déconnexion supprime le jeton de `push_tokens`** ; la PWA ne le fait pas.~~ La PWA le fait
  aussi depuis le ticket 057.
- **Rejoindre une invitation** relit les appartenances et ouvre la caserne ; la PWA passe par son
  écran d'invitation (« Bienvenue », profil, guide).
- **Cases du mois du planning** : la bande d'un créneau dit « J 07:00 – 19:00 » quand elle tient,
  « J » sinon, plutôt qu'un libellé coupé ; les heures restent dans le détail du jour et dans
  l'annonce VoiceOver de la case.
- **Tailles plafonnées** : la pile de cartes de l'accueil, la grille des disponibilités et les
  calendriers du planning ont une géométrie fixe : ils gardent la taille de texte standard ; leurs
  versions dépliées, les listes et les détails suivent Dynamic Type jusqu'à AX3. L'app entière
  s'arrête à AX3.
- **Familles système de la typographie** (SF Pro, SF Rounded, New York, SF Mono, un réglage de
  Foco) : pour grandir avec Dynamic Type, elles perdent leur dessin arrondi ou à empattements par
  appel. La famille par défaut (Helvetica Neue) ne change pas.

### Écarts relevés dans la PWA au 066d

- ~~**Le jeton web n'est pas supprimé à la déconnexion.**~~ Corrigé au ticket 057 : `OubliLocal.tout()`
  supprime la ligne de `push_tokens` avant la fermeture de session, puis oublie la clé
  `notifications.jeton.appareil`, même si la suppression échoue.

## 4 quinquies. Ticket 057 — le jeton d'un téléphone prêté

Un téléphone de caserne est prêté. À la déconnexion, la ligne `push_tokens` de l'appareil part
avant la fermeture de session (066d pour l'app iOS, 057 pour la PWA). Mais **une déconnexion hors
ligne ne supprime rien** : la ligne reste au nom du compte sorti. Le compte suivant se connecte,
FCM lui rend le même jeton, et l'`upsert` direct sur la clé unique `token` était refusé par la RLS :
les push du compte sorti continuaient d'arriver sur l'appareil, et le compte connecté n'en recevait
aucun.

Correction côté base (migration `0037`, `docs/SCHEMA.md § 3`) : `register_push_token(p_token,
p_platform, p_device_label)`, `security definer`, ouverte à `authenticated` seulement, retire le
jeton à tout autre compte et l'inscrit au nom de la session. Un jeton FCM identifie l'appareil : le
présenter prouve qu'on le tient. La décision est écrite dans `docs/WORKFLOWS.md § 8`.

Dans l'app iOS (`foco/`) :

- `NotificationsContract.registerPushTokenFunction = "register_push_token"` et
  `RegisterPushTokenParams` (`p_token`, `p_platform: "ios"`, `p_device_label`, `null` s'il est vide)
  remplacent l'`upsert` et `PushTokenRow`. **Aucun `user_id` ni `last_seen_at` ne part de l'app** :
  la base les pose.
- `FocoBackend.registerPushToken(token:deviceLabel:)` (plus d'identifiant ni d'horloge) ;
  `SupabaseBackend` appelle `rpc/register_push_token` ; `PushCenter` exige toujours une session
  mais n'en envoie pas l'identifiant.
- La suppression à la déconnexion ne change pas (`DELETE push_tokens?token=eq.<t>`, avant la
  fermeture de session et avant `LocalWipe`).
- Tests : contrat figé des trois paramètres, enregistrement au lancement par la fonction,
  téléphone prêté (un jeton resté au nom d'un autre compte passe au compte connecté).

**CI** : PR [slider973/Foco#8](https://github.com/slider973/Foco/pull/8), course verte du premier coup ([36226985794](https://github.com/slider973/Foco/actions/runs/36226985794) : 189 tests, 0 échec,
0 avertissement Swift), fusionnée en squash ; course verte sur `main` du fork
([36227804089](https://github.com/slider973/Foco/actions/runs/36227804089), 189 tests, 0 avertissement)
au commit `ecb7955`, visé par le pointeur `foco/`.

## 4 sexies. Ticket 068 — la saisie refusée en « lecture seule » sur un mois ouvert

**Le bug** (TestFlight 1.0 (102), 28 septembre 2026, iPhone du propriétaire). Caserne en essai,
`station_access.writable` vrai ; septembre et octobre `locked`, novembre `open`. Après une
navigation septembre → octobre → novembre, une touche passe (`201`), un effacement aussi
(`DELETE` du 3 novembre, nuit), puis les deux `upsert` suivants sont refusés en `403` / `42501`
(« new row violates row-level security policy »). L'écran affiche « Ta caserne est passée en
lecture seule… », puis « Caserne suspendue : la saisie est fermée ». Aucune ligne de novembre en
base, alors qu'un `INSERT` du 2 novembre sous l'identité du membre passe.

**La cause** : la grille de `AvailabilityView` gardait ses cibles de pinceau
(`@State frames: [SlotKey: CGRect]`) **d'un mois à l'autre** — la vue n'était pas recréée au
changement de mois et le dictionnaire n'était jamais vidé. Le glissement cherchait la case sous le
doigt par `frames.first { $0.value.contains(point) }` : sur la première ligne de novembre, les
colonnes vides (le 1er novembre 2026 est un dimanche) portaient encore les cases de septembre et
d'octobre, et ailleurs l'ordre du dictionnaire tranchait au hasard. `AvailabilityEntry.set` ne
vérifiait que « le mois affiché est ouvert », pas « la case est du mois affiché » : ces cases
entraient dans la file, et l'`upsert` groupé partait avec des lignes de mois verrouillés — une
seule suffit pour que PostgREST refuse tout le lot. Le refus relisait alors les périodes, trouvait
novembre ouvert, et **en déduisait une suspension** (`knownReadOnly`), gardée jusqu'au redémarrage.
Les dates, elles, étaient justes : chaque case est calculée en date civile par le même calendrier
à l'aller et au retour (vérifié pour chaque case de septembre, octobre et novembre 2026).

**La preuve** : le test `EntryRegressionTests.productionScenario` rejoue le scénario (même
géométrie de grille, même geste, faux backend qui lève `42501` dès qu'un lot porte une ligne d'un
mois fermé). Sur l'ancien code, course
[36410290026](https://github.com/slider973/Foco/actions/runs/36410290026) rouge : message « Ta
caserne est passée en lecture seule… », lots portant `2026-09`, `2026-10` et `2026-11`, base vide
en novembre — exactement la production. Rejoué aussi en `curl` contre le Supabase local
(octobre verrouillé, novembre ouvert, `membre1@caserne-a.test`, code lu dans Mailpit) : un lot
29 octobre + 2 novembre → `403` `42501` ; le 2 novembre seul → accepté.

**La correction** (`foco/`) :

- **Un lot, un seul mois ouvert.** La grille est recréée à chaque mois (`.id(period.key)`) et
  `GridHitMap` ne répond que pour les cases du mois affiché ; `set` et `put` écartent toute case
  d'un autre mois. La file part **un mois à la fois**, le mois affiché d'abord ; une entrée d'un
  mois qui n'est plus ouvert (ou avant toute lecture des périodes, rien ne part) est retirée et
  annoncée (`staleQueueDropped`, « Des disponibilités en attente visaient un mois désormais
  verrouillé… »).
- **Un refus dit sa vraie cause**, dans cet ordre : `station_access` relu → `writable = false` :
  « Ta caserne est passée en lecture seule… » et la grille se ferme ; sinon `periods` relu → le
  mois du lot n'est plus ouvert : « Le mois vient d'être verrouillé… » avec « Recharger » ; sinon
  erreur neutre « Impossible d'enregistrer tes disponibilités. Elles sont conservées sur ton
  téléphone. » avec « Réessayer », **sans jamais parler de suspension**. La lecture seule ne vient
  plus que de `station_access`.
- **Un nouveau mois sans redémarrer.** `AvailabilityEntry.refresh()` relit `station_access`, les
  périodes, le mois affiché et ses préférences, sans jeter la file : au retour au premier plan
  (`AppStore.becameActive()`, depuis l'accueil et l'écran), à l'ouverture de l'accueil et des
  Disponibilités (`prepareAvailability`), et par tirer-pour-actualiser (`.refreshable`). Si l'écran
  montrait le mois par défaut, il suit le nouveau ; un mois choisi à la main reste affiché.
- Tests (`FocoTests/EntryRegressionTests.swift`) : scénario de production, case d'un autre mois
  jamais en file, un lot par mois, mois verrouillé entre-temps jamais envoyé, trois causes de refus
  (suspendue, verrouillé, neutre), nouveau mois au retour au premier plan, à l'ouverture de l'écran
  (mois choisi à la main gardé), date de chaque case.

**Écart relevé dans la PWA** (corrigé au ticket 070 : un refus relit `station_access` avant les
périodes, et un refus inexpliqué reste neutre — `SaisieController._traiterEchec`) : `_traiterEchec` de
`SaisieController` classe un `42501` comme l'ancienne app iOS — mois relu ouvert ⇒ « Ta caserne est
passée en lecture seule », sans lire `station_access`, et `_lectureSeuleConnue` le garde jusqu'au
rechargement de la page ou à un changement de compte. La PWA n'a pas le bug de la grille (ses lots ne portent que le mois affiché), mais
un refus inexpliqué y serait présenté comme une suspension.

**CI** : PR [slider973/Foco#10](https://github.com/slider973/Foco/pull/10). Reproduction seule
(commits `d4e5adc`, `3599e75`) : course [36410290026](https://github.com/slider973/Foco/actions/runs/36410290026)
**rouge** sur les tests (la première, 36409805880, échouait à la compilation : `MonthGrid` existait
déjà, d'où `EntryMonthGrid`). Correction `5579efa` : course [36411249041](https://github.com/slider973/Foco/actions/runs/36411249041)
verte, 10 tests 068, 0 avertissement Swift ; fusionnée en squash ; course verte sur `main` du fork
([36412782083](https://github.com/slider973/Foco/actions/runs/36412782083), 0 avertissement) au
commit `0ab920d`, visé par le pointeur `foco/`. Build TestFlight **1.0 (103)**, course
[36414185633](https://github.com/slider973/Foco/actions/runs/36414185633).

## 4 septies. Ticket 071 — la lecture seule et les données périmées

**Le défaut** (audit du 28 septembre 2026, pointeur `0ab920d`). Les stores sont partagés, et le
retour au premier plan relisait la saisie, le planning et le centre ; restait ce que personne ne
relisait :

- `PlanningJourney.readOnly` n'était posé qu'au `start` : une caserne réactivée après paiement
  gardait « Accepter » grisé jusqu'au redémarrage (et une suspension ne grisait rien) ;
- un push reçu au premier plan ne relisait que le centre ;
- le `.task` de l'accueil était gardé par `isStarted` : revenir d'un écran enfant ne relisait rien ;
- rôle et appartenances n'étaient lus qu'à l'entrée ;
- « Planning de la caserne », « Équipe », « Aujourd'hui » et le détail d'un jour ne relisaient pas
  ce qu'ils avaient déjà lu ;
- le câblage `scenePhase` de l'accueil n'était pas testé.

**La correction** (`foco/`) — **aucune requête, colonne ou fonction nouvelle** : les mêmes lectures,
rejouées à d'autres moments.

| Point | Fait |
|---|---|
| Lecture seule | `AvailabilityEntry.onStationAccess` prévient à **chaque lecture** de `station_access` (ouverture, retour au premier plan, refus d'une écriture) ; l'`AppStore` y branche `PlanningJourney.syncReadOnly`. La saisie et les réponses suivent la même lecture, sans seconde requête ; la lecture seule de la saisie suit `station_access` même si la relecture des périodes échoue ensuite |
| Push reçu au premier plan | `handlePush(.received)` → `refreshContent()` : saisie, propositions, astreintes, mois du planning et centre |
| Retour sur l'accueil | `AppStore.homeAppeared()` au `.task` de l'accueil (qui repart à chaque retour d'un écran poussé), à la fermeture d'une carte dépliée et des réglages ; **au plus une fois toutes les 10 s** (`homeRefreshInterval`), l'entrée et le retour au premier plan comptant comme une relecture. Les arguments de capture n'ouvrent leur écran qu'une fois |
| Rôle et appartenances | `becameActive()` relit d'abord `memberships` (la requête du 066a) : rôle changé → adopté (« Gérer la caserne » et les liens de l'admin suivent) ; caserne ouverte plus active → saisie, planning et centre oubliés **en mémoire vive** (la file des disponibilités gardée sur l'appareil attend `LocalWipe`, à la déconnexion), puis l'écran de l'entrée (« Accès désactivé », une autre caserne, le choix). **Panne réseau** : le rôle lu en base à l'entrée reste ; **tout autre échec** retire le privilège (jamais de repli qui masque un refus). `LocalWipe` inchangé ; un rôle restauré du cache revient toujours simple membre |
| Écrans | « Planning de la caserne » : la liste et les mois déjà lus (`openStationPlanning`) ; « Aujourd'hui » et le détail d'un jour : le mois relu même s'il l'est déjà (`openMonth(containing:)`) ; « Équipe » : les noms relus à chaque ouverture (`openTeam`), un échec garde ceux qu'on avait |
| Lectures dépassées (revue) | la réponse des appartenances est **ignorée si la caserne ouverte ou la session a changé pendant l'attente** (caserne choisie, déconnexion), sur le chemin réussi comme sur l'échec ; une seule lecture des appartenances et une seule relecture du planning ou de la saisie en vol, **une demande arrivée pendant une relecture étant notée et rejouée une fois à sa fin** (second tour de revue ; jamais sous un geste ni pendant un envoi) ; `station_access` : la lecture partie la dernière fait foi (une relecture lente ne défait pas la lecture seule posée par un refus) ; `start` pose la lecture seule comme `refresh`, même si les périodes sont illisibles |
| Rien sous un geste ni une écriture | la saisie ne se relit ni sous le doigt ni pendant un envoi (règle du 068) ; les propositions ne sont pas relues tant qu'une réponse est en vol (`responding`), sinon la ligne répondue reviendrait à l'écran |

**Tests** (`FocoTests/FreshnessTests.swift`) : caserne réactivée puis `becameActive` → lecture seule
levée sur la saisie et les réponses, l'inverse pour une suspension (rien ne part) ; refus d'une
écriture → « Accepter » grisé aussi ; push reçu → nouvelle proposition à l'écran, astreintes,
saisie et centre relus ; retour sur l'accueil → relecture, deux retours en moins de 10 s → une
seule, 10 s après → de nouveau, le retour au premier plan compte ; rôle retiré → plus d'admin, rôle
donné → admin, appartenance désactivée → « Accès désactivé » et mémoire vidée, panne réseau → rôle
gardé, refus → privilège retiré ; « Équipe », « Aujourd'hui » / détail et planning relus à
l'ouverture ; rien sous un geste, rien sous une réponse en vol. **Câblage** : `ScenePhaseWiringTests`
monte la vraie `HomeView` dans une fenêtre de l'app hôte, passe son `scenePhase` de `.background` à
`.inactive` (rien) puis à `.active` (relecture).

**CI** : PR [slider973/Foco#11](https://github.com/slider973/Foco/pull/11). Tests seuls sur
l'ancien code (commit `e9a374b`) : course
[36490736169](https://github.com/slider973/Foco/actions/runs/36490736169) **rouge**, 15 assertions en échec dans 7 tests —
réponses restées en lecture seule ou jamais grisées, push qui ne relit que le centre, rôle
d'admin gardé, appartenance désactivée ignorée ; le câblage `scenePhase` passait déjà. Correction :
(`119d372`) : course [36491914750](https://github.com/slider973/Foco/actions/runs/36491914750) verte avec un
avertissement de test (argument par défaut isolé), puis
[36493314724](https://github.com/slider973/Foco/actions/runs/36493314724) verte, 17 tests 071,
0 avertissement Swift ; fusionnée en squash ; course verte sur `main` du fork
([36494901491](https://github.com/slider973/Foco/actions/runs/36494901491), 0 avertissement) au
commit `5062402`. Build TestFlight **1.0 (104)**, course
[36496276933](https://github.com/slider973/Foco/actions/runs/36496276933).

**Revue** (bloquant : appartenance lue avant l'attente, utilisée après) : PR
[slider973/Foco#12](https://github.com/slider973/Foco/pull/12), 7 tests de plus (caserne choisie
pendant la lecture → reste B avec le rôle de B, et B n'est pas vidée ; déconnexion pendant une
lecture réussie ou refusée → store vide ; lecture ancienne de `station_access` ignorée ; lecture
seule posée par `start` quand les périodes échouent ; retour au premier plan et push simultanés →
une seule lecture). Course [36497739513](https://github.com/slider973/Foco/actions/runs/36497739513)
verte, 0 avertissement Swift ; fusionnée en squash ; course verte sur `main` du fork
([36498778857](https://github.com/slider973/Foco/actions/runs/36498778857), 0 avertissement) au
commit `666916c`. Build TestFlight **1.0 (105)**, course
[36499812274](https://github.com/slider973/Foco/actions/runs/36499812274).

**Second tour de revue** (bloquant : une relecture demandée pendant une autre était jetée — un push
reçu pendant la relecture du retour au premier plan n'apparaissait qu'au déclencheur suivant) : PR
[slider973/Foco#13](https://github.com/slider973/Foco/pull/13). `PlanningJourney.refresh` et
`AvailabilityEntry.refresh` notent la demande (`refreshAgain`) et la rejouent une fois à la fin de
la relecture en cours, sous la même garde de génération ; la saisie ne la rejoue jamais sous un
geste ni pendant un envoi. Tests : push pendant la relecture des propositions → la proposition
apparaît, au plus deux lectures, jamais deux en vol ; push d'ouverture de mois pendant la relecture
des périodes → novembre finit affiché ; relance jamais sous le doigt ; `concurrentRefreshesCoalesce`
attend désormais deux lectures successives. **Preuve rouge volontaire** (tests seuls, `2606997`) :
course [36704881634](https://github.com/slider973/Foco/actions/runs/36704881634), 5 assertions en
échec dans 3 tests. Correction (`69dde83`) : course
[36705708959](https://github.com/slider973/Foco/actions/runs/36705708959) verte, 0 avertissement
Swift ; fusionnée en squash ; course verte sur `main` du fork
([36707326215](https://github.com/slider973/Foco/actions/runs/36707326215), 0 avertissement) au
commit `929f313`, visé par le pointeur `foco/`. Build TestFlight **1.0 (106)**.

## 5. Déconnexion et caches locaux

La règle de `CLAUDE.md` s'applique à l'app iOS. Un seul point : `LocalWipe`
(`foco/Foco/Core/Session/Deconnexion.swift`), appelé par `AppStore.signOut()`. Il efface le
trousseau de l'app (la session Supabase), tout le domaine `UserDefaults`, `Caches`, `tmp`
(l'export `.ics`), `Application Support`, le cache HTTP et les cookies.

- `signOut()` fait quatre choses, dans cet ordre :
  1. **la saisie, le planning et le centre** : `AvailabilityEntry.reset()` arrête minuteurs et
     envois, pour qu'aucune écriture en vol ne réécrive sa file sur l'appareil après
     l'effacement ; `PlanningJourney.reset()` oublie propositions, astreintes, mois lus, noms et
     lien d'abonnement, et fait ignorer toute réponse arrivée après (066c) ;
     `NotificationInbox.reset()` oublie les notifications (066d) ;
  2. **le jeton push** (066d) : `PushCenter.forget()` supprime la ligne de `push_tokens` tant que
     la session le permet et que la mémoire du jeton (`PushTokenMemory`, `UserDefaults`) est encore
     là, puis FCM oublie le jeton de l'appareil. Hors ligne, la ligne reste : c'est
     `register_push_token` qui la fait passer au compte suivant (ticket 057) ;
  3. **la session** : fermée côté serveur tant que le jeton est encore dans le trousseau ;
  4. **l'effacement** (`LocalWipe`), **même si le serveur ne répond pas**.
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
   décodage des réponses relevées sur le seed ; et pour 066c : contrat figé et décodage des
   réponses du seed, réponse acceptée, refusée avec motif, refusée par la base (`42501`), hors
   ligne, plus proposée, dernière acceptation qui valide, double touche, astreintes par mois et
   passées, équipiers seulement une fois validé, relecture ratée, planning non publié invisible,
   publié réduit à ses créneaux, mois d'ouverture, accueil sans fait inventé (avant lecture, après,
   après un échec), cloche, déconnexion qui vide le planning ; et pour 066d : contrat figé et
   réponses relevées en `curl`, liste, non-lues, marquer lu (succès, déjà lue ailleurs, échec),
   tout marquer lu (succès, échec), lectures ratées, cloche et tuile, chaque lien de `WORKFLOWS § 8`
   et les liens mal formés, lancement froid, cycle de vie du jeton (lancement, geste, refus,
   rafraîchissement, `platform = ios`, suppression à la déconnexion avant `LocalWipe` et avant la
   fermeture de session, sans Firebase), `push_enabled`, retour du réseau par un faux
   `NWPathMonitor`, invitations en attente (présentes, absentes, échec, rejointe, refusée,
   expirée), classement des erreurs inconnues.
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
`xcodebuild build test`, puis les captures (mode démo : accueil, saisie des disponibilités
ouverte par `-FocoOpenAvailability`, propositions par `-FocoOpenPropositions`, mes astreintes
par `-FocoOpenDuties`, planning de la caserne par `-FocoOpenPlanning`, centre de notifications
par `-FocoOpenNotifications` ; écran de connexion ; puis les six écrans du mode démo à la taille
de texte **AX3**, `ax3-*.png`) gardées en artefact avec le `Package.resolved` obtenu et
`warnings.txt`, la liste des avertissements Swift **de l'app et de ses tests** (règle : zéro). Runner `macos-26` : c'est la seule image GitHub qui porte
Xcode 26.4.1 et un simulateur iOS 26.4 ; `macos-15` s'arrête à Xcode 26.3. Le fork étant privé,
ses minutes macOS comptent dans le quota du compte (×10).

La CI Flutter (`ci.yml`) et le déploiement (`deploy.yml`) ne changent pas : leur
`actions/checkout` ne récupère pas les submodules, et `flutter analyze` ne lit que du Dart.

## 8. État final (066d)

Tous les points iOS de la section « À reprendre » du 066c sont faits (§ 4 quater). Restent
ouverts, par choix et consignés :

- **Cache local des astreintes et du planning** (066c) : la PWA les garde pour le hors-ligne ;
  l'app iOS ne les garde qu'en mémoire. S'il est ajouté, il part avec `LocalWipe`.
- **Fichier `.ics` par astreinte et « Régénérer le lien »** (066c) : absents de l'app iOS.
- **Pas de blocage « hors ligne » avant une réponse** (`enLigneProvider` côté propositions) : le
  moniteur réseau existe depuis 066d et sert la file des disponibilités ; une réponse hors ligne
  part, échoue et revient à sa place avec la phrase du réseau.
- **Caserne suspendue et réponse, dans la PWA** (066c, confirmé en `curl` et figé par un test du
  fork) : le `PATCH` d'une réponse rend `200 []` et non `42501` ; si `station_access` n'a pas pu
  être lu, `repondre` rend `disparue` et la PWA annonce « Ce créneau ne t'est plus proposé. » au
  lieu de la lecture seule. L'app iOS fait de même. À corriger des deux côtés (ticket
  `supabase-dev` ou relecture de `station_access` sur zéro ligne).
- **Deux écarts de la PWA, confirmés par la revue du 066b** (détail plus bas, `lib/` non touché) :
  `_chargerPreferences` écrit la reprise sur une caserne suspendue ; `EtatSaisie.mois` compte la
  file d'un autre mois. (Celui du 066d, le jeton web non supprimé à la déconnexion, est corrigé au
  ticket 057 : § 4 quinquies.)

### À reprendre (ticket 055)

Le ticket 055 a corrigé dans la PWA trois phrases qui affirmaient un envoi sans preuve.
`foco/` n'a pas été touché : les équivalents iOS sont à aligner, **sans changement de requête**
— le `PATCH` de réponse reste le même, et la base met désormais `assignment_declined` en file
pour lui aussi (migration `0039`, `docs/SCHEMA.md § 5`).

| iOS (`foco/`) | Aujourd'hui | À écrire (PWA, `AppStrings`) |
|---|---|---|
| `FocoStrings.swift:380` (refus) | « \(slot) : refusée. Ton chef de centre est prévenu. » | « … : refusée. Ton chef de centre sera prévenu. » (`propositionsRefusee`) ; pour un administrateur, ou tant que le rôle n'a pas été relu en base, « … : refusée. » sans promesse (`propositionsRefuseeNeutre`) |
| `FocoStrings.swift:24` (`codeResent`) | « Nouveau code envoyé. Regarde tes e-mails. » | « Nouveau code demandé. Regarde tes e-mails d'ici une minute. » (`codeRenvoye`) |
| `FocoTests/PlanningTests.swift:404` | attend l'ancienne phrase du refus | la nouvelle |

La réattribution et l'annulation (« <membre> sera prévenu ») n'ont pas d'équivalent iOS : l'app
n'a pas d'écran d'administration.

### Écarts de 066b avec la PWA, et pourquoi

- ~~**Pas de moniteur réseau.**~~ Repris au 066d : `NWPathMonitor` rejoue la file au retour du
  réseau, comme `enLigneProvider`. Avant cela, l'app relançait à 1 s et 4 s, puis attendait
  « Réessayer ». La file n'est jamais perdue.
- **Interaction de Foco gardée** : un pinceau (Disponible / Absent), une touche qui pose le pinceau
  ou revient à « non saisi », au lieu du cycle de la PWA (non saisi → disponible → absent). Les
  lignes écrites sont les mêmes. Pas d'annulation de geste à deux doigts.
- **Raccourcis dans un menu natif** (portée ▸ créneau) plutôt qu'une feuille : mêmes portées,
  mêmes créneaux, même compte, même confirmation.
- **Cases de 44 pt** (règle binding de `CLAUDE.md`) : la pastille de Foco reste de 32 pt, sa cible
  en fait 44 ; la grille s'allonge d'autant. Depuis 066d, la largeur fait aussi 44 pt au moins,
  même sur 375 pt.
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

## 9. À faire par le propriétaire

Le code est prêt ; ces étapes demandent un compte, une clé ou un téléphone, et ne peuvent pas se
faire dans la CI.

1. ~~**Signature Apple et identifiant de bundle.**~~ Fait au ticket 067 :
   `ch.staticflow.astreintesp`, équipe injectée (`FOCO_TEAM_ID` en local, secret `APPLE_TEAM_ID`
   en CI), plus aucune équipe codée en dur.
2. **`Config/Config.xcconfig` de production** : `FOCO_SUPABASE_URL` et `FOCO_SUPABASE_ANON_KEY`
   de `env/prod.json` (clé **publique** seulement), `FOCO_PWA_URL` si l'adresse de la PWA change.
   Jamais commité.
3. **Firebase iOS** (`docs/FIREBASE.md § 9`) : l'application iOS dans le **même** projet Firebase
   que la PWA, la clé APNs `.p8` (Key ID, Team ID) importée dans *Cloud Messaging*, et
   `GoogleService-Info.plist` déposé en `foco/Foco/GoogleService-Info.plist` (jamais commité).
4. **TestFlight** : par la CI du fork, § 10. `aps-environment` passe en `production`
   automatiquement à l'export.
5. **Vérification sur l'iPhone 17 Pro Max** (dernier critère du ticket), build de développement ou
   TestFlight : connexion par code ; mêmes disponibilités, propositions, astreintes et planning que
   la PWA, une saisie faite d'un côté visible de l'autre ; centre de notifications et cloche ;
   « Activer les notifications », ligne `platform = ios` dans `push_tokens`, envoi de test avec
   `route = /proposals` (§ 9.d de `docs/FIREBASE.md`), app fermée puis ouverte ; déconnexion qui
   retire la ligne et vide l'appareil ; taille de texte AX3 (Réglages → Accessibilité → Affichage et
   taille du texte) et VoiceOver sur l'accueil, les disponibilités, les propositions, mes astreintes,
   le planning et les notifications.

Le bloc `apns` de l'Edge Function d'envoi est fait au chantier 066d (commit `e500717`) : les push iOS portent le son, et `deploy.yml` le met en ligne à la fusion.

## 10. Publier sur TestFlight (ticket 067)

Le Mac du propriétaire (Xcode 16.2) ne peut pas archiver une app iOS 26 : **l'archive, la
signature et l'envoi se font dans la CI du fork**, workflow `TestFlight`
(`foco/.github/workflows/testflight.yml`), lancé à la main.

```sh
gh workflow run testflight.yml -R slider973/Foco
# avec le texte « À tester » montré aux testeurs :
gh workflow run testflight.yml -R slider973/Foco -f changelog="Connexion par code, disponibilités d'octobre"
gh run watch -R slider973/Foco "$(gh run list -R slider973/Foco -w TestFlight -L 1 --json databaseId -q '.[0].databaseId')"
```

Toujours depuis `main` du fork, sur un commit dont la course `iOS` est verte (§ 7).

### Secrets attendus

Déposés par le propriétaire, jamais par un agent : `gh secret set <NOM> -R slider973/Foco`
(la valeur est lue sur l'entrée standard, par exemple `< AuthKey_XXXX.p8`).

| Secret | Contenu | Obligatoire |
|---|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` | identifiant de la clé API App Store Connect | oui |
| `APP_STORE_CONNECT_API_ISSUER_ID` | identifiant de l'émetteur (*Users and Access → Integrations*) | oui |
| `APP_STORE_CONNECT_API_KEY` | contenu du fichier `AuthKey_XXXX.p8` | oui |
| `APPLE_TEAM_ID` | équipe Apple Developer du propriétaire (10 caractères) | oui |
| `FOCO_CONFIG_XCCONFIG` | contenu du `Config/Config.xcconfig` de production : `FOCO_SUPABASE_URL` et `FOCO_SUPABASE_ANON_KEY` de `env/prod.json`, clé **publique** seulement | oui |
| `GOOGLE_SERVICE_INFO_PLIST` | contenu du `GoogleService-Info.plist` Firebase | non : sans lui, l'app est construite sans push |

### Ce que fait le workflow

1. Écrit la clé `.p8` dans `$RUNNER_TEMP` (hors du dépôt, permissions 600), puis
   `Config/Config.xcconfig` et `Foco/GoogleService-Info.plist` (chemins ignorés par git).
2. Numéro de build = numéro de course + 100 : TestFlight refuse un numéro déjà utilisé ; le
   décalage laisse la place d'un envoi manuel et d'un workflow recréé. La version affichée reste
   `MARKETING_VERSION` du projet (1.0) : la changer dans le projet pour une nouvelle version.
3. `xcodebuild archive` en Release, signature automatique : `-allowProvisioningUpdates` et
   `-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID`, avec
   `DEVELOPMENT_TEAM` venu du secret.
4. `xcodebuild -exportArchive` avec `foco/Config/ExportOptions.plist` (`method =
   app-store-connect`, `destination = upload`, `signingStyle = automatic`, `teamID` injecté,
   `manageAppVersionAndBuildNumber = false`) : **l'export envoie lui-même le build** à App Store
   Connect, sans `altool` ni fastlane.
5. Si `changelog` est donné, `foco/scripts/testflight-changelog.py` attend que le build
   apparaisse dans l'API App Store Connect et écrit son « À tester » (`fr-FR`). Un échec ici ne
   fait pas échouer l'envoi.
6. Efface les fichiers secrets dans une étape `if: always()`. Aucun `set -x`, aucun `echo` de
   valeur, aucun journal xcodebuild en artefact.

`Info.plist` déclare `ITSAppUsesNonExemptEncryption = NO` (HTTPS seulement, chiffrement
standard) : TestFlight ne redemande pas la conformité export à chaque build.

### Ce qui reste manuel

- **Une fois** : l'identifiant d'app `ch.staticflow.astreintesp` avec *Push Notifications*, la
  fiche App Store Connect « Astreinte SP », les informations TestFlight (description, contact),
  le groupe de testeurs internes avec *distribution automatique* activée (sans elle, chaque build
  est à ajouter au groupe à la main), la clé API et les secrets ci-dessus, Firebase (§ 9).
- **Rôle de la clé API** : la signature automatique en CI crée un certificat et des profils ; Apple
  réserve les certificats de distribution gérés dans le cloud aux clés **Admin** (ou *App Manager*
  avec l'accès *Certificates, Identifiers & Profiles*). Si l'export échoue sur le certificat, c'est
  la première chose à regarder.
- **Certificats de développement** : l'archive signée fait créer à chaque runner neuf un
  certificat *Apple Development*. Si Apple répond que le nombre maximal de certificats est atteint,
  révoquer les anciens certificats de développement créés par la CI dans developer.apple.com.
- **À chaque version** : lancer le workflow, attendre le traitement d'Apple (5 à 30 minutes), puis
  installer depuis l'app TestFlight de l'iPhone. Écrire « À tester » à la main si le `changelog`
  n'a pas été donné ou n'a pas pu être écrit.
- **Passer en App Store** (hors ticket 067) : fiche publique, captures, confidentialité, revue.

### Testeurs externes (ticket 076)

Un testeur **externe** (hors du compte Apple du propriétaire) reçoit l'app par le groupe
« Testeurs externes », par **lien public** (plafond 100) ou par invitation. Chaque première build
d'une version passe la **revue bêta d'Apple**, qui exige un accès de démonstration : d'où la
caserne de démonstration et la connexion de revue.

**La caserne de démonstration** — `supabase/scripts/caserne_demo.sql`, rejouable, **pas une
migration** (ce sont des données). Elle crée ou remet à zéro « CIS Démonstration » (identifiant
fixe `de300000-0000-4000-8000-000000000001`, slug `demonstration`) et rien d'autre :

- dix membres : le compte de revue `revue-apple@astreinte-sp.fr` (**simple membre**, adresse
  confirmée), une cheffe fictive (admin) et huit membres fictifs. Les fictifs n'ont **qu'un
  profil, sans compte d'authentification**, et une adresse en `.invalid` : personne ne peut s'y
  connecter et aucun courriel n'y arrive ;
- mois courant : planning validé, tout accepté ; M+1 : saisie verrouillée, planning publié,
  **propositions en attente** pour le compte de revue ; M+2 : saisie ouverte ; deux notifications
  dans son centre ;
- abonnement `active` sans date de fin : jamais de lecture seule.

Le script refuse de tourner si le slug appartient à une autre caserne. Pour supprimer un planning
publié, il lève deux gardes (`schedules_guard_suppression`, `shifts_guard_suppression`) et
l'audit de suppression des mois **dans sa transaction** : le DDL est transactionnel, aucune autre
session ne les voit levées, la RLS ne change pas. Vérifié en local (`supabase db reset`, deux
passages, empreinte des autres casernes identique) puis en production le 3 octobre 2026.

```sh
# Avant chaque revue bêta, pour rafraîchir les dates (M, M+1, M+2) :
supabase db query --linked --project-ref axvflcgwsmrjrnjheoly -f supabase/scripts/caserne_demo.sql
# En local (la CLI refuse plusieurs commandes en --local) :
psql "$(supabase status -o json | jq -r .DB_URL)" -v ON_ERROR_STOP=1 -f supabase/scripts/caserne_demo.sql
```

Le compte de revue survit à la remise à zéro, mot de passe compris. Ce mot de passe est dans
**1Password** (coffre Static Flow, « Astreinte SP — compte de revue Apple », champs `username` et
`password`, ID `pw4q4mo6ol6anbl6kwlnamtvby`) et **nulle part ailleurs** : jamais dans le dépôt,
jamais transmis à Apple par un agent. Pour le poser ou le changer, l'API d'administration Auth,
la clé de service lue dans une variable et jamais affichée :

```sh
REF=axvflcgwsmrjrnjheoly
SRK=$(supabase projects api-keys --project-ref $REF -o json | jq -r '.[] | select(.name=="service_role") | .api_key')
UID_=$(supabase db query --linked --project-ref $REF "select id from auth.users where email='revue-apple@astreinte-sp.fr'" | jq -r '.rows[0].id')
op read "op://Static Flow/pw4q4mo6ol6anbl6kwlnamtvby/password" | jq -Rc '{password: .}' \
  | curl -s -o /dev/null -w '%{http_code}\n' -X PUT "https://$REF.supabase.co/auth/v1/admin/users/$UID_" \
      -H "apikey: $SRK" -H "Authorization: Bearer $SRK" -H 'Content-Type: application/json' --data-binary @-
unset SRK
```

**La connexion de revue, dans l'app** — `FOCO_REVIEW_EMAIL` (§ 2) : quand l'adresse saisie lui
est égale (casse et espaces ignorés), l'écran de connexion affiche un champ mot de passe et appelle
`signInWithPassword` au lieu d'envoyer un code. Toute autre adresse garde le code, inchangé ; sans
adresse configurée, personne n'a de mot de passe, et `AppStore.signIn(email:password:)` refuse le
mot de passe à toute autre adresse avant le réseau. La session, le trousseau et la déconnexion
(`LocalWipe`) sont ceux du code.

> **Écart au contrat de la PWA** (le seul de l'app iOS sur l'authentification) : un appel Auth
> `POST /auth/v1/token?grant_type=password`, que la PWA ne fait jamais. Raison : le relecteur
> d'Apple ne peut pas lire un code envoyé par courriel, et la revue bêta exige un accès de
> démonstration. Aucune table, colonne ni fonction nouvelle ; la base accepte déjà le mot de passe
> (fournisseur e-mail de GoTrue) pour tout compte qui en a un ; l'app ne le propose qu'à
> l'adresse de revue. La PWA n'est pas touchée.

**App Store Connect** — `foco/scripts/testflight-externe.py` (clé API **Admin**, 1Password),
idempotent :

1. informations de test `fr-FR` : description, retours à `jonathan.lemaine78@gmail.com`,
   confidentialité `https://astreinte.staticflow.ch/legal/confidentialite` ;
2. détails de la revue bêta : contact Jonathan Lemaine, « connexion requise » cochée, notes en
   anglais pour le relecteur. **Le script n'écrit jamais le nom d'utilisateur ni le mot de
   passe.** Apple refuse toute écriture de ces détails sans **téléphone de contact** (HTTP 409,
   relevé au build 107) : sans `CONTACT_PHONE` ni téléphone déjà saisi dans App Store Connect, le
   script ne les écrit pas, le dit et poursuit ; un téléphone saisi à la main est repris tel quel ;
3. groupe externe « Testeurs externes » : retours activés, lien public avec plafond 100 (si Apple
   le refuse avant la première revue acceptée, le script le dit et le prochain passage l'active) ;
4. le dernier build traité (ou `--build N`) ajouté au groupe ;
5. `--soumettre` : soumission à la revue bêta, **refusée par le script** tant que le téléphone et
   les identifiants de démonstration ne sont pas saisis dans App Store Connect.

```sh
cd foco
I=gjbku4bzm4xghk4ap5xbaz4qce   # « Astreinte SP — App Store Connect API Admin (CI) »
ASC_KEY_ID=$(op read "op://Static Flow/$I/Key ID") ASC_ISSUER_ID=$(op read "op://Static Flow/$I/Issuer ID") \
ASC_KEY="$(op read "op://Static Flow/$I/p8")" python3 scripts/testflight-externe.py [--build N] [--soumettre]
```

Le workflow le fait aussi : `-f externe=true` attend le traitement du build et l'ajoute au groupe ;
`-f soumettre=true` le soumet en plus (même garde). Premier build externe : **1.0 (107)**, course
[TestFlight n° 7](https://github.com/slider973/Foco/actions/runs/37119547344), ajouté au groupe le
3 octobre 2026, état `READY_FOR_BETA_SUBMISSION` (non soumis : identifiants à saisir).

```sh
gh workflow run testflight.yml -R slider973/Foco -f changelog="…" -f externe=true [-f soumettre=true]
```

**Ce qui reste manuel** :

- **Une fois, par le propriétaire** : dans App Store Connect → app Astreinte SP → TestFlight →
  *Informations de test* (*Test Information*), section *Informations sur la revue bêta de l'app* :
  le **téléphone** de contact, puis « Connexion requise » cochée avec le **nom d'utilisateur** et
  le **mot de passe** de l'item 1Password « Astreinte SP — compte de revue Apple ». Enregistrer.
  Ensuite `python3 scripts/testflight-externe.py --build 107 --soumettre` : il écrit le contact,
  les notes et la case, garde téléphone et identifiants, puis soumet.
- **Le lien public** (`https://testflight.apple.com/join/1srwe1VG`, plafond 100) existe depuis le
  3 octobre 2026 ; il n'admet des testeurs qu'une fois la revue bêta acceptée. Le script le
  réimprime à chaque passage.
- **Avant chaque revue** (nouvelle version) : rejouer `caserne_demo.sql` pour des dates fraîches.
- Les courriels automatiques de la caserne de démonstration (rappels, relances) partent vers le
  compte de revue et des adresses `.invalid` : sans effet, aucune vraie personne n'est concernée.
