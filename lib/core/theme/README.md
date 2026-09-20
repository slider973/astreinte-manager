# core/theme

Socle visuel de l'application, implémenté au ticket 004 à partir de `DESIGN.md` (normatif) et de
`design/004-design-system.md`. Le monde visuel est **le registre de garde** : structure imprimée
(filets, colonnes, cases), pas empilée (cartes, ombres, pastilles).

| Fichier | Contenu |
|---|---|
| `app_colors.dart` | Toutes les couleurs, écrites valeur par valeur. Rôles Material 3 clair et sombre, encres d'état. Aucun calcul, aucune graine. |
| `app_typography.dart` | `AppFonts` (les deux familles embarquées), `AppTextStyles` (échelle fixe ratio 1.2, chiffres tabulaires) et la construction du `TextTheme`. |
| `app_spacing.dart` | `AppSpacing` (échelle de 4), `AppRadius`, `AppStroke`, `AppTouch`. |
| `app_motion.dart` | `AppDuration`, `AppCurves`, et `AppMotion` qui met toute durée à zéro sous Reduce Motion. |
| `app_breakpoints.dart` | `AppWindowClass` (600 / 840 / 1200) et `context.estPointeurFin`. |
| `app_elevation.dart` | `AppShadows`, les cinq niveaux. Les niveaux 0 et 1 n'ont **aucune** ombre : le filet remplace. |
| `app_status.dart` | `StatusDescriptor` et `AppStatusColors`. **La règle « jamais la couleur seule » vit ici.** |
| `app_theme.dart` | `AppTheme.clair` et `AppTheme.sombre`. `ColorScheme` écrits à la main, jamais `fromSeed`. |

## Les trois règles qui ne se négocient pas

1. **Aucun `Color(0xFF…)` ni `TextStyle(fontSize: …)` dans un widget.** Un widget lit
   `Theme.of(context).colorScheme`, `Theme.of(context).textTheme` ou `context.statuts`.
2. **Un état s'écrit `marque + icône + libellé`, la couleur en quatrième.** `StatusDescriptor`
   rend impossible la construction d'un état sans icône ni libellé ; un état rendu par une teinte
   seule est un défaut bloquant en revue.
3. **Pas d'ombre sur du contenu.** La séparation se fait par un filet 1 dp et un cran de surface
   tonale. Seuls menus, feuilles, dialogues et snackbars flottent.

## Valeurs de `DESIGN.md` complétées ici

`DESIGN.md` ne donne les encres sombres que pour les familles « disponibilité » et
« attribution ». Les familles « planning », « période » et « synchronisation » réemploient en
sombre des tokens **déjà présents** dans `DESIGN.md` (aucune valeur inventée) ; le détail est dans
`DESIGN.md § Named Rules`, colonne « Encre sombre ».

## Vérification

`test/core/theme/contraste_test.dart` recalcule le ratio WCAG de chaque paire du système à chaque
exécution : un changement de couleur qui casse 4.5:1 (texte) ou 3:1 (filet porteur d'état) fait
échouer la suite. `test/core/theme/app_status_test.dart` interdit deux icônes identiques dans une
même famille d'états.
