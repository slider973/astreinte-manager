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

## Ce qu'aucun de ces widgets ne fait

- Écrire une couleur (`Color(0xFF…)`) ou une taille de police (`TextStyle(fontSize: …)`).
- Afficher un état sans son icône ni son libellé : `StatusDescriptor` le rend impossible.
- Porter une ombre. La séparation se fait par un filet et un cran de surface.
- Dépendre du survol ou du clic droit.
- Contenir une chaîne visible en dur : tout passe par `AppStrings`.
