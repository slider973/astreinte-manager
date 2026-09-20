# 004 — Thème et composants de base

Brief de design, format `shape` (Impeccable). Écrit avant le code. Mode : **Operate**.
Plateforme : **PWA web mobile-first**, Material 3, une seule apparence sur toutes les cibles.
Monde visuel fondé au même ticket : voir `DESIGN.md` (il gagne sur ce brief pour toute valeur de
token). Ce brief dit **quoi construire** ; `DESIGN.md` dit **avec quoi**.

---

## 1. Job et audience

**Qui arrive.** Personne n'arrive sur ce ticket : il ne produit aucun écran métier. Il produit le
vocabulaire visuel que les 30 tickets suivants vont consommer. Ses « utilisateurs » immédiats sont
`flutter-dev` et `pr-reviewer` ; ses utilisateurs finaux sont ceux des écrans à venir.

**Les deux scènes qui décident de tout.**

1. **Le membre, dehors, 8 secondes.** Sapeur-pompier volontaire, tous âges, aisance numérique très
   variable. Téléphone sorti entre deux activités, souvent en plein soleil, parfois avec des gants.
   Il veut savoir si son mois est saisi, s'il a une proposition en attente, et cocher deux cases.
   Une mauvaise lecture d'état coûte une garde non couverte.
2. **L'admin, assis, 20 minutes.** Chef de centre ou adjoint, sur ordinateur, devant une matrice de
   15 à 60 membres × 31 jours × 2 créneaux. Il a besoin de densité, d'alignement et de repérage
   rapide, pas de confort tactile.

Ces deux scènes exigent des densités opposées. Le système doit les servir **avec les mêmes
composants**, pas avec deux jeux de composants.

**Mode.** Operate. L'expression ne doit jamais masquer la tâche, l'état, ni un repère familier.
La marque vit dans la précision des détails, pas dans un geste graphique.

## 2. Résultat et preuve

**Résultat attendu du ticket.** Un thème Material 3 clair et sombre, sept composants transverses
testés, et un écran de démonstration `/dev/components` qui les montre tous dans tous leurs états.

**Preuve, vérifiable en revue.**

- Chaque état du produit se lit **sans couleur** : une capture en niveaux de gris de
  `/dev/components` reste entièrement interprétable.
- Chaque paire texte/fond documentée dans `DESIGN.md` atteint 4.5:1, prouvé par un test unitaire
  qui calcule le ratio, pas par une inspection à l'œil.
- Toute cible tactile de `/dev/components` mesure ≥ 48 dp sur une fenêtre de 390 × 844.
- `/dev/components` est lisible à `textScaleFactor` 1.0, 1.3 et 2.0 sans texte tronqué.
- `flutter analyze` sans avertissement, `flutter test` vert, `flutter build web` passe.

**La vérité produit que ce système doit porter** (et qu'un template générique ne porterait pas) :
la distinction entre **« absent »** et **« non saisi »**. C'est le mécanisme qui sépare ce produit
de l'intranet remplacé. Si ces deux cases se ressemblent, le ticket a échoué, quelle que soit la
qualité du reste.

## 3. Direction retenue

**« Le registre de garde ».** Le détail complet est dans `DESIGN.md § Overview`. En trois
conséquences pour le développeur :

1. **La structure est imprimée, pas empilée.** On sépare avec un filet 1 dp et un cran de surface
   tonale. `Card` avec `elevation > 0` est interdit pour du contenu. Aucun composant transverse de
   ce ticket ne porte d'ombre — `AppBanner` compris, qui reste au niveau 0. Seuls les menus
   (niveau 2), feuilles et dialogues (niveau 3) et le snackbar (niveau 4) en ont une.
2. **L'accent est l'encre.** `colorScheme.primary` est un noir-encre bleuté `#16212A`. La seule
   couleur saturée à l'écran est donc **toujours** un état. Aucun composant ne colore pour décorer.
3. **La case est la forme signature.** Rayon 4, glyphe centré, trois remplissages :
   plein / hachuré-bordé / vide-tireté. Boutons et champs à rayon 8, jamais en gélule.

**Écarts assumés au Material 3 par défaut**, à ne pas « corriger » :
pas de boutons en gélule (rayon 8), pas de `ColorScheme.fromSeed` (les deux schémas sont écrits à
la main, valeur par valeur, parce que les contrastes sont vérifiés), pas d'ombres sur le contenu,
libellés de navigation toujours visibles, libellé de bouton à 16 sp et non 14.

**Direction et méthode.** Direction issue du tirage `concept-seed --scope direction --mode operate`
(clé `343e7a3d`, index assigné 4 de la liste de candidats ancrés ordonnée par résonance : tableau
synoptique de disponibilité → signalétique normée ISO 7010 → tableau de garde mural → **registre de
main courante et imprimé administratif** → textile rétroréfléchissant → cadrans et manomètres →
carte IGN). Chemin de construction : `code` (`.impeccable/config.json`), donc pas de ronde de
maquettes. Arbitré sans le propriétaire, faute de canal de question : les hypothèses sont en § 7.

## 4. Périmètre et limites

**Dans le périmètre.**

- `lib/core/theme/` complet : couleurs, typographie, espacement, rayons, motion, points de rupture,
  extension de thème des états, `ThemeData` clair et sombre.
- Sept composants du ticket + quatre composants transverses justifiés ci-dessous.
- Deux polices embarquées dans `assets/fonts/`.
- Écran `/dev/components`, **build de développement uniquement** (`kDebugMode` ou
  `--dart-define=DEV_TOOLS=true`), route absente en production.
- Un widget test de rendu par composant + un test de contraste + un test de cibles tactiles.
- `AppStrings` étendu avec les chaînes génériques.
- `lib/app.dart` branché sur les deux thèmes (`theme`, `darkTheme`, `themeMode: ThemeMode.system`).

**Hors périmètre, à ne pas commencer.**

- Tout écran métier : mois, propositions, planning, profil, admin. `AppScaffold` expose les cinq
  destinations mais chacune pointe sur un écran de remplacement neutre jusqu'à son ticket.
- Toute logique de données, Supabase, Riverpod métier, routage authentifié.
- La sélection par glissement de la grille (ticket 011) : `SlotChip` expose les rappels
  (`onTap`, `onDragEnter`) mais ne gère aucun geste multi-cases.
- La matrice admin elle-même (ticket 016) : seule la densité `dense` de `SlotChip` est livrée.
- Le préférence de thème par l'utilisateur (ticket 007) : ici, `ThemeMode.system`.
- Toute icône personnalisée ou logo : l'app n'a pas de logo et n'en invente pas.

**Anti-objectifs explicites.** Pas de bibliothèque de composants tierce, pas de `google_fonts` en
réseau, pas de paquet d'icônes supplémentaire (`Icons` de Flutter suffit), pas de `shimmer` externe.

## 5. États et plages de contenu

Chaque composant se livre avec **tous** ces états visibles dans `/dev/components`.

| Plage | Minimum | Typique | Maximum à tenir |
|---|---|---|---|
| Jours d'un mois | 28 | 30 | 31 (× 2 créneaux = 62 cases) |
| Membres d'une caserne | 15 | 30 | **60** (matrice = 60 × 62 = 3720 cases denses) |
| Propositions en attente | 0 | 3 | 9+ (pastille plafonnée) |
| Nom affiché | « Li » (2 car.) | « Jean Dupont » | « Marie-Christine de Villeneuve-Latour » (40 car., doit tronquer proprement avec info-bulle et semantics complets) |
| Nom de caserne | 3 car. | 25 car. | 60 car. |
| Motif de refus | vide | 40 car. | 280 car. |
| Échelle de texte | 1.0 | 1.0 | 2.0 |

**États transverses à couvrir par les composants :**

- **vide** — `EmptyState` : titre, explication, action. Jamais « Aucune donnée ».
- **chargement** — `LoadingSkeleton` à la forme du contenu attendu (ligne, bloc, grille de cases).
  Jamais de roue au milieu de l'écran. Balayage supprimé si Reduce Motion.
- **erreur** — `EmptyState.erreur` : ce qui a échoué + bouton « Réessayer ». Annoncé
  (`liveRegion`).
- **hors ligne** — `AppBanner.horsLigne` + `EmptyState.horsLigne` pour un écran qui n'a rien en
  cache.
- **lecture seule (caserne suspendue)** — `AppBanner.lectureSeule` + tous les contrôles désactivés
  avec raison affichée.
- **mois verrouillé** — `AppBanner.verrouille` + `SlotChip` en état verrouillé (hachures, non
  focalisable), les valeurs restant parfaitement lisibles.
- **60 membres** — la matrice en densité `dense` doit rester fluide : `SlotChip.dense` est un widget
  sans état, sans animation, `const` autant que possible, et doit tenir dans une liste virtualisée.
- **enregistrement automatique** — `SaveIndicator` : au repos, en cours, enregistré, échec.

## 6. Interaction et layout

### Hiérarchie et topologie

`AppScaffold` = barre d'application (titre + actions) → zone `AppBanner` (au plus une) → contenu →
navigation. Le contenu ne passe jamais sous la navigation ni sous la zone sûre.

### Téléphone (compact, < 600)

`NavigationBar` en bas, 4 ou 5 destinations, libellés toujours visibles, hauteur 72 dp +
`viewPadding.bottom`. Bouton principal en pleine largeur, collé en bas de la feuille ou de l'écran
avec 16 dp de marge. Détail et confirmation en feuille de bas d'écran, jamais en dialogue plein
écran. Les 24 premiers dp du bord gauche restent libres pour le geste retour iOS.

### Tablette (medium 600–839, expanded 840–1199)

`NavigationRail` à gauche, étendu à partir de 840. Deux volets à partir de 840 : liste à gauche,
détail à droite, sans modale. Densité `compacte` (40 dp) pour les cases : une tablette reste
tactile, la densité `dense` lui est interdite.

### Grand écran admin (large, ≥ 1200)

Rail étendu permanent + zone de travail + panneau de détail à droite. C'est la disposition de
référence de la matrice du ticket 016 : colonne « membre » figée à gauche, en-tête de dates collant
en haut, cases 28 px avec 2 px d'écart, densité `dense` autorisée uniquement ici et uniquement au
pointeur. Contenu centré, largeur maximale 1440.

### Rétroaction et transitions

Toute action modifiant une donnée donne une rétroaction en moins de 120 ms : la case change d'état
optimistement, `SaveIndicator` passe en « Enregistrement… », puis « Enregistré ». En cas d'échec, la
case revient à son état précédent **et** un `AppBanner.erreur` propose « Réessayer ».

Un seul moment chorégraphié dans toute l'app : le tampon (voir `DESIGN.md § Motion`). Partout
ailleurs, 120–280 ms, `easeOutCubic`, et zéro si Reduce Motion.

### Accessibilité, non négociable

- Ordre de focus clavier logique, anneau de focus 2 dp visible sur tout fond, jamais supprimé.
- Chaque `SlotChip` et chaque `StatusBadge` porte un `Semantics` avec une **phrase complète**
  française, pas un code : « Samedi 4 octobre, nuit, disponible. Appuie pour marquer absent. »
- Les erreurs sont annoncées (`liveRegion: true`), pas seulement colorées.
- Aucun affichage ne dépend du survol ni du clic droit.
- Contraste ≥ 4.5:1 pour tout texte, ≥ 3:1 pour tout filet porteur d'état.

## 7. Contraintes et décisions ouvertes

### Contraintes fermes

- Flutter 3.x + Material 3, Riverpod, go_router. Aucune dépendance nouvelle sauf les fichiers de
  police (ressources, pas paquets).
- Toutes les chaînes dans `AppStrings`. Tutoiement du membre, phrases courtes, vocabulaire pompier.
- `flutter build web` doit passer ; les polices embarquées doivent être `preload`ées dans
  `web/index.html` pour éviter un FOUT sur la grille.
- `theme-color` du manifeste web aligné sur `surface-container-low` du thème actif.

### Décisions tranchées seul, à confirmer par le propriétaire

1. **Aucun code visuel pompier.** Confirmé libre par le propriétaire ; le rouge est réservé aux
   états « absent / refusé / erreur ». Si une caserne demande plus tard une identité rouge, elle se
   fera par un token de marque distinct, pas en recolorant les états.
2. **Atkinson Hyperlegible Next + Mono** plutôt qu'une grotesque neutre. Raison de brief : basse
   vision, tous âges, lecture au soleil, écrans pleins de chiffres. Coût : ~180 Ko de police
   embarquée. Si ce poids est jugé trop lourd pour la 4G rurale, repli documenté : famille système
   + `FontFeature.tabularFigures()`, et `DESIGN.md` mis à jour.
3. **Thème clair par défaut**, sombre complet suivant le système. Raison : la scène dominante est
   le plein soleil. Le choix manuel du thème arrive au ticket 007.
4. **`ThemeMode.system` au ticket 004**, pas de bascule dans `/dev/components` autre qu'un contrôle
   local de démonstration.
5. **Cinq destinations maximum.** « Mes astreintes » (ticket 027) et « Notifications »
   (ticket 026) n'auront **pas** de destination de premier niveau : elles vivront dans « Mon mois »
   et dans la barre d'application. À trancher au ticket 027 si l'usage dit le contraire.
6. **`SlotChip` dense limité au pointeur.** Sur tablette tactile, la matrice reste en 40 dp et
   défile. Aucune exception.

### Ce qu'un développeur ne doit pas inventer

Les valeurs de couleur, les tailles de police, les rayons, les durées, les icônes d'état, les
libellés d'état et les seuils de rupture sont **tous** dans `DESIGN.md`. Aucun `Color(0xFF…)` ni
`TextStyle(fontSize:)` en dur dans un widget, sans exception.

---

## Widgets Flutter

### `lib/core/theme/`

| Fichier | Contenu |
|---|---|
| `app_colors.dart` | `abstract final class AppColors` : toutes les constantes de `DESIGN.md § Colors`, clair et sombre, rôles M3 **et** encres d'état. Aucun calcul, aucune graine. |
| `app_typography.dart` | Familles (`AppFonts.texte`, `AppFonts.nombre`), construction du `TextTheme` complet, plus `AppTextStyles.nombre`, `.nombrePetit`, `.displayNombre` avec `FontFeature.tabularFigures()`. |
| `app_spacing.dart` | `AppSpacing` (2…48), `AppRadius` (filet 0, case 4, controle 8, feuille 12, pastille 999), `AppStroke` (filet 1, etat 2), `AppTouch` (cible 48, dense 28). |
| `app_motion.dart` | `AppDuration` (instantane 120, courant 180, surface 240, page 280), `AppCurves`, et `AppMotion.scale(context)` qui renvoie `Duration.zero` si `MediaQuery.disableAnimationsOf(context)`. |
| `app_breakpoints.dart` | `enum AppWindowClass { compact, medium, expanded, large }` + `AppWindowClass.of(BuildContext)` (seuils 600 / 840 / 1200) + `bool get estPointeurFin`. |
| `app_elevation.dart` | `AppShadows` : les cinq niveaux de `DESIGN.md § Elevation`, chacun avec décalage **et** flou. |
| `app_status.dart` | Les cinq familles d'états en `enum` de présentation (`DisponibiliteEtat`, `CreneauType`, `AttributionEtat`, `PlanningEtat`, `PeriodeEtat`, `SyncEtat`), la classe immuable `StatusDescriptor { IconData icone; String libelle; Color encre; Color fond; Color? filet; bool hachure; bool barre; }`, et `AppStatusColors extends ThemeExtension<AppStatusColors>` qui résout un `StatusDescriptor` pour chaque valeur d'énumération, en clair et en sombre. **C'est ici que vit la règle « jamais la couleur seule » :** un `StatusDescriptor` sans icône ni libellé est impossible à construire. |
| `app_theme.dart` | `AppTheme.clair` / `AppTheme.sombre` : `ColorScheme` écrits à la main (pas `fromSeed`), `textTheme`, et les thèmes de composants — `FilledButtonTheme`, `OutlinedButtonTheme`, `InputDecorationTheme`, `NavigationBarTheme`, `NavigationRailTheme`, `AppBarTheme`, `DividerTheme`, `BottomSheetTheme`, `DialogTheme`, `SnackBarTheme`, `CardTheme` (élévation 0 + filet), `ChipTheme`, `FocusTheme`. |

### `lib/core/widgets/`

| Fichier | Widget | États à livrer |
|---|---|---|
| `app_scaffold.dart` | `AppScaffold` + `AppDestination` | compact (`NavigationBar`) / medium+ (`NavigationRail`) / large (rail étendu + panneau), avec et sans « Admin », pastille Propositions 0 / 3 / 9+, zones sûres iOS |
| `app_banner.dart` | `AppBanner` | `information`, `attention`, `verrouille`, `horsLigne`, `lectureSeule`, `erreur` (avec action) |
| `primary_button.dart` | `PrimaryButton` + `enum PrimaryButtonVariante { primaire, secondaire, danger }` | normal, pressé, focus, désactivé + raison, chargement (largeur figée), avec et sans icône, pleine largeur et intrinsèque |
| `slot_chip.dart` | `SlotChip` + `enum SlotChipDensite { confortable, compacte, dense }` | 3 états × 2 créneaux × 3 densités, + sélectionné, verrouillé, en enregistrement, erreur |
| `day_cell.dart` | `DayCell` | jour ouvré, weekend, jour férié, aujourd'hui, mois verrouillé, jour hors mois (grisé) |
| `status_badge.dart` | `StatusBadge` | les 15 états de `DESIGN.md § Named Rules`, en taille normale et compacte, libellé tronquable |
| `empty_state.dart` | `EmptyState` + fabriques `.erreur`, `.horsLigne` | vide avec action, vide sans action, erreur avec « Réessayer », hors ligne |
| `loading_skeleton.dart` | `LoadingSkeleton`, `SkeletonLigne`, `SkeletonBloc`, `SkeletonGrilleMois` | balayage actif, balayage supprimé (Reduce Motion) |
| `app_divider.dart` | `AppDivider` | filet horizontal, filet vertical, filet d'en-tête collant |
| `count_stat.dart` | `CountStat` | valeur seule, valeur/plafond (« 2/3 »), plafond illimité (« 2 / ∞ » → libellé « illimité »), valeur à zéro |
| `save_indicator.dart` | `SaveIndicator` | repos, enregistrement, enregistré, échec (avec « Réessayer ») |

`app_divider.dart`, `count_stat.dart` et `save_indicator.dart` ne sont pas listés dans le ticket
mais sont transverses et exigés par le PRD : le filet est le matériau de séparation du système
(§ Elevation), le compteur est requis en 5.2.7 et réutilisé dans la matrice admin (5.3.2), et
l'indicateur de sauvegarde est requis en 5.2.6. `app_banner.dart` porte les états « mois
verrouillé », « caserne suspendue » et « hors ligne » qui traversent tous les écrans. Rien d'autre
n'est ajouté.

### Autres fichiers touchés

| Fichier | Changement |
|---|---|
| `lib/app.dart` | `theme: AppTheme.clair`, `darkTheme: AppTheme.sombre`, `themeMode: ThemeMode.system` |
| `lib/core/router/app_router.dart` | route `/dev/components` nommée `devComponents`, **conditionnée au build de développement** |
| `lib/features/dev/presentation/dev_components_screen.dart` | catalogue : une section par composant, tous les états, un contrôle local clair/sombre et un contrôle d'échelle de texte (1.0 / 1.3 / 2.0) |
| `lib/core/l10n/app_strings.dart` | chaînes ci-dessous |
| `pubspec.yaml` | déclaration `fonts:` pour les deux familles |
| `assets/fonts/` | fichiers `.ttf` Atkinson Hyperlegible Next (400/600/700) et Mono (600/700) |
| `web/index.html` | `<link rel="preload" as="font">` pour les deux familles |

### Tests attendus

| Fichier | Vérifie |
|---|---|
| `test/core/theme/contraste_test.dart` | calcule le ratio WCAG de **chaque** paire documentée dans `DESIGN.md § Colors` et assère ≥ 4.5 (texte) ou ≥ 3.0 (filet porteur d'état), en clair et en sombre |
| `test/core/theme/app_status_test.dart` | chaque valeur d'énumération a un descripteur avec icône **et** libellé non vide ; **deux états d'une même famille n'ont jamais la même icône** |
| `test/core/widgets/<composant>_test.dart` | un par composant : rendu de chaque état, présence du libellé, présence du `Semantics`, taille de cible ≥ 48 pour les densités tactiles |
| `test/core/widgets/reduce_motion_test.dart` | avec `disableAnimations: true`, `LoadingSkeleton` ne s'anime pas et les durées valent zéro |

---

## Textes

À ajouter dans `AppStrings`. Tutoiement du membre. Phrases courtes. Pas de jargon logiciel.

### Navigation

| Clé | Texte |
|---|---|
| `navMonMois` | Mon mois |
| `navPropositions` | Propositions |
| `navPlanning` | Planning |
| `navProfil` | Profil |
| `navAdmin` | Admin |
| `navPropositionsBadge` | {n} propositions en attente |
| `navOuvrirMenu` | Ouvrir le menu |

### États de disponibilité

| Clé | Texte |
|---|---|
| `etatDisponible` | Disponible |
| `etatAbsent` | Absent |
| `etatNonSaisi` | Non saisi |
| `creneauJour` | Jour |
| `creneauNuit` | Nuit |
| `slotSemantique` | {jour} {date}, {créneau}, {état} |
| `slotActionMarquerDisponible` | Appuie pour te marquer disponible |
| `slotActionMarquerAbsent` | Appuie pour te marquer absent |
| `slotActionEffacer` | Appuie pour effacer |
| `slotVerrouille` | Créneau verrouillé |

### États d'attribution

| Clé | Texte |
|---|---|
| `attributionPropose` | En attente |
| `attributionProposeMembre` | En attente de ta réponse |
| `attributionAccepte` | Accepté |
| `attributionRefuse` | Refusé |
| `attributionAnnule` | Annulé |

### États de planning et de période

| Clé | Texte |
|---|---|
| `planningBrouillon` | Brouillon |
| `planningPublie` | Publié |
| `planningValide` | Validé |
| `planningArchive` | Archivé |
| `periodeOuverte` | Saisie ouverte |
| `periodeOuverteJusquAu` | Saisie ouverte jusqu'au {date} |
| `periodeVerrouillee` | Mois verrouillé |
| `periodeVerrouilleeDetail` | Mois verrouillé depuis le {date}. Contacte ton chef de centre pour une modification. |
| `periodeBientotFermee` | Plus que {n} jours pour saisir {mois} |

### Jours et repères de calendrier

| Clé | Texte |
|---|---|
| `jourAujourdhui` | Aujourd'hui |
| `jourWeekend` | Weekend |
| `jourFerie` | Jour férié |
| `jourFerieNomme` | Jour férié : {nom} |
| `jourHorsMois` | Hors du mois |

### Actions génériques

| Clé | Texte |
|---|---|
| `actionEnregistrer` | Enregistrer |
| `actionAnnuler` | Annuler |
| `actionReessayer` | Réessayer |
| `actionFermer` | Fermer |
| `actionContinuer` | Continuer |
| `actionRetour` | Retour |
| `actionChargement` | Chargement… |

### Sauvegarde et réseau

| Clé | Texte |
|---|---|
| `saveEnCours` | Enregistrement… |
| `saveTermine` | Enregistré |
| `saveEchec` | Non enregistré |
| `saveEchecDetail` | Impossible d'enregistrer. Vérifie ta connexion. |
| `horsLigne` | Hors ligne |
| `horsLigneDetail` | Hors ligne. Tes modifications partiront au retour du réseau. |
| `lectureSeule` | Lecture seule |
| `lectureSeuleDetail` | Caserne suspendue : tu peux consulter, pas modifier. |

### États vides et erreurs

| Clé | Texte |
|---|---|
| `videTitreGenerique` | Rien à afficher |
| `videTexteGenerique` | Il n'y a encore rien ici. |
| `videPropositionsTitre` | Aucune proposition |
| `videPropositionsTexte` | Quand ton chef de centre publiera le planning, tes astreintes proposées s'afficheront ici. |
| `erreurTitre` | Ça n'a pas marché |
| `erreurTexteGenerique` | Une erreur est survenue. Réessaie dans un instant. |
| `erreurReseauTitre` | Pas de connexion |
| `erreurReseauTexte` | Impossible de joindre le serveur. Vérifie ta connexion, puis réessaie. |
| `chargementSemantique` | Contenu en cours de chargement |

### Compteurs

| Clé | Texte |
|---|---|
| `compteurJours` | Jours |
| `compteurNuits` | Nuits |
| `compteurWeekends` | Weekends |
| `compteurSurPlafond` | {valeur} sur {plafond} |
| `compteurIllimite` | illimité |

### Écran de démonstration (build de développement)

| Clé | Texte |
|---|---|
| `devComposantsTitre` | Composants |
| `devComposantsSousTitre` | Catalogue du système de design. Build de développement uniquement. |
| `devTheme` | Thème |
| `devThemeClair` | Clair |
| `devThemeSombre` | Sombre |
| `devEchelleTexte` | Taille du texte |

---

## Checklist `craft-floor` (Impeccable)

| Point | Statut |
|---|---|
| **Contraste** — texte ≥ 4.5:1, grand texte ≥ 3:1, texte secondaire teinté depuis la teinte du fond, jamais gris neutre | ✅ Toutes les paires calculées et listées dans `DESIGN.md § Colors`. Le gris est bleu-vert, jamais neutre. Test unitaire exigé. |
| **Profondeur** — ombres avec décalage et flou, pas de halo coloré à décalage zéro | ✅ Cinq niveaux définis, chacun avec décalage et flou ; le contenu n'a aucune ombre (le filet remplace). |
| **Espacement** — groupes serrés, séparations généreuses, plus d'espace au-dessus d'un titre qu'en dessous | ✅ Échelle de 4, règle 24/8 explicite. À vérifier sur valeurs calculées à la revue. |
| **Typographie** — mesure 65–75 ch, échelle et graisses évidentes, vraie copie à chaque rupture | ✅ Échelle fixe ratio 1.2, mesure imposée à la prose seulement, plages de contenu réelles données au § 5 (nom de 40 caractères, motif de 280). |
| **Mouvement** — un moment chorégraphié, sortie exponentielle, pas d'entrée identique partout | ✅ Un seul : le tampon. Reste ≤ 280 ms, `easeOutCubic`. ⚠️ Volontairement pauvre en effets : mode Operate + Reduce Motion obligatoire. Assumé. |
| **États** — survol, désactivé, chargement, erreur, vide + contenu réel, contrôles fonctionnels, composition responsive, focus clavier | ✅ Exigés composant par composant dans le tableau « Widgets Flutter ». ⚠️ **Survol : sans objet**, cible PWA tactile ; remplacé par pressé + focus. |
| **Surfaces du navigateur** — sélection de texte, curseur, barres de défilement, anneau de focus, chiffres tabulaires | ✅ Anneau de focus et chiffres tabulaires spécifiés. ⚠️ Sélection, caret et barres de défilement : Flutter web les gère depuis `ColorScheme` ; à vérifier au rendu et à thématiser dans `app_theme.dart` si le rendu par défaut sort du système. **Point à contrôler explicitement en revue.** |
| **Copie** — la langue du produit, les contrôles nomment leur action, les erreurs nomment le problème et la sortie | ✅ Toutes les chaînes ci-dessus. « Enregistrer le mois » et non « OK » ; chaque erreur a une action. |
| **Couverture** — chaque exigence du brief présente et trouvable en quelques secondes | ✅ `/dev/components` est la preuve de couverture. |
| **Refus** — cartes identiques comme structure, métrique héroïque, sur-titre, numéros de section, modale gratuite, texte en dégradé, verre décoratif, bordure gauche colorée, ombre dure, monospace costume, emoji-icône, clair/sombre choisi par catégorie | ✅ Tous refusés explicitement dans `DESIGN.md § Do's and Don'ts`. Le monospace est justifié (mesure et alignement de chiffres). Le clair par défaut vient de la scène d'usage (plein soleil), pas de la catégorie. |

## Checklist application mobile (ui-ux-pro-max)

| Règle | Sévérité | Statut |
|---|---|---|
| Taille de cible tactile — 44 pt iOS / 48 dp Android, WCAG 24 px web | Haute | ✅ 48 dp partout au tactile ; 28 px en matrice dense **au pointeur uniquement** (> 24 px WCAG). |
| Espacement entre cibles — 8 px minimum | Moyenne | ✅ Écart 8 dp entre contrôles, 4 dp entre cases (les cases sont des cibles contiguës d'une même grille, cas admis, mais la case elle-même fait 48 dp). |
| Contraste du corps de texte — texte sombre sur fond clair, jamais gris sur gris | Haute | ✅ 17.24:1 en clair, 14.76:1 en sombre. |
| Bouton retour prévisible — historique de navigation préservé | Haute | ✅ go_router, routes nommées, geste retour iOS préservé (bande de 24 dp libre au bord gauche). |
| Navigation fixe n'obscurcit pas le contenu | Moyenne | ✅ `AppScaffold` ajoute hauteur de nav + `viewPadding.bottom` au `padding` du contenu défilant. |
| Clavier adapté au type de champ (`inputmode`) | Moyenne | ✅ Imposé dans `DESIGN.md § Inputs` : numérique pour OTP et quotas. |
| Tableaux larges — défilement horizontal ou disposition en cartes | Moyenne | ✅ Matrice admin : défilement horizontal + colonne membre figée sur compact ; grille du membre passe en liste au-delà d'une échelle de texte 1.6. |
| Actions en masse — sélection multiple plutôt qu'une action par ligne | Basse | ⏭️ Hors périmètre du 004. `SlotChip` expose déjà `onDragEnter` pour la sélection par glissement du ticket 011. |
| Récupération d'erreur — étapes suivantes claires | Moyenne | ✅ Chaque état d'erreur porte « Réessayer » et une phrase qui nomme la cause. |
| Messages d'erreur annoncés (`role=alert` / `liveRegion`) | Haute | ✅ Imposé sur `AppBanner.erreur`, `EmptyState.erreur` et les champs. |
| États vides qui guident | Moyenne | ✅ `EmptyState` exige titre + explication + action ; textes fournis. |
| Mode sombre pris en charge | Moyenne | ✅ Schéma sombre complet, vérifié en contraste, `ThemeMode.system`. |
| Thème par le contexte, jamais de couleur en dur | Moyenne | ✅ Interdiction explicite de `Color(0xFF…)` et `TextStyle(fontSize:)` dans un widget. |
