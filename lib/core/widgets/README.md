# core/widgets

Composants transverses du système, implémentés au ticket 004 d'après `DESIGN.md` et
`design/004-design-system.md`. Chaque composant a un widget test de rendu ; `/dev/components` les
montre tous, dans tous leurs états, en clair et en sombre.

| Fichier | Widget | Rôle |
|---|---|---|
| `app_scaffold.dart` | `AppScaffold`, `AppDestination` | Ossature d'écran : barre, bannière, contenu, navigation. Barre basse en compact, rail au-delà, panneau latéral en large. |
| `app_banner.dart` | `AppBanner` | **Composant signature.** Les faits qui changent tout ce qui est en dessous. Une seule à la fois, par ordre de priorité. |
| `primary_button.dart` | `PrimaryButton` | Bloc à rayon 8, hauteur 52, libellé 16 sp. Un bouton désactivé **doit** dire pourquoi. |
| `slot_chip.dart` | `SlotChip` | **Composant signature.** La case du registre. Trois densités, trois remplissages. |
| `day_cell.dart` | `DayCell` | Un jour : bloc réglé, numéro, nom, marqueurs, deux cases empilées. |
| `status_badge.dart` | `StatusBadge` | Un état, avec sa marque, son icône et son libellé. Six familles. |
| `empty_state.dart` | `EmptyState` | Vide, erreur, hors ligne. Jamais muet, toujours une sortie. |
| `loading_skeleton.dart` | `LoadingSkeleton`, `SkeletonLigne`, `SkeletonBloc`, `SkeletonGrilleMois` | L'ossature du contenu attendu, jamais une roue. |
| `app_divider.dart` | `AppDivider` | Le filet : le matériau de séparation du système. |
| `count_stat.dart` | `CountStat` | Un compteur en chiffres tabulaires, avec ou sans plafond. |
| `save_indicator.dart` | `SaveIndicator` | Où en est l'enregistrement automatique. |
| `hachures.dart` | `Hachures`, `HachuresPainter` | Primitive de dessin, pas un composant : le motif à 45° partagé par `SlotChip` et `AppBanner`. |
| `champ_texte.dart` | `ChampTexte` | Champ rempli M3 : libellé au-dessus, erreur annoncée sous le champ, une ou plusieurs lignes. |
| `ecran_simple.dart` | `EcranSimple` | L'ossature des écrans sans navigation : connexion, invitation, accueil d'un nouveau membre. |
| `barre_actions_basse.dart` | `BarreActionsBasse` | Le pied de la colonne : les actions du bas s'y bornent à la même largeur que le corps (`largeurMax`, 720 par défaut, `EcranSimple.colonneLecture` sous un écran sans navigation), derrière un filet de niveau 1. |
| `colonne_navigation.dart` | `ColonneNavigation` | La navigation du grand écran (ticket 061b) : libellés à côté des icônes, pastille `primary-container` sur toute la largeur de l'élément, nom du produit en tête. Elle remplace le rail étendu dès `expanded`. |
| `entete_travail.dart` | `EnTeteTravail` | L'en-tête de la zone de travail sur grand écran, **à la place de la barre d'application** : nom de la caserne à gauche, actions de l'écran puis cloche et compte à droite. |
| `avatar_initiales.dart` | `AvatarInitiales` | Un disque d'initiales. Pas de photo : ce serait une donnée personnelle de plus, et les pompiers n'en ont pas dans ce produit. |
| `bouton_retour.dart` | `BoutonRetour` | La sortie d'un écran sans ossature ni parent dans le routeur. Flèche seule quand il y a une pile à dépiler, flèche **suivie du mot « Accueil »** quand il n'y en a pas (ticket 052). |

## La règle qui a produit `BoutonRetour`

Un écran atteint par une navigation depuis un autre écran, déclaré au premier niveau du routeur et
sans barre de navigation, n'a **par construction aucune sortie** : sur iPhone en PWA plein écran il
n'y a pas de barre d'adresse, et la personne est enfermée. À vérifier pour toute nouvelle route :

> *Un écran qui ne porte ni `AppScaffold` ni un parent dans le routeur s'ouvre par `push` et porte
> une flèche à repli.*

## Ce qu'aucun de ces widgets ne fait

- Écrire une couleur (`Color(0xFF…)`) ou une taille de police (`TextStyle(fontSize: …)`).
- Afficher un état sans son icône ni son libellé : `StatusDescriptor` le rend impossible.
- Porter une ombre. La séparation se fait par un filet et un cran de surface.
- Dépendre du survol ou du clic droit.
- Contenir une chaîne visible en dur : tout passe par `AppStrings`.
