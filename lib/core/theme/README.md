# core/theme

Socle visuel de l'application. Structure posée au ticket 004 ; **teintes et police de titre
remplacées au ticket 061** (`design/061-monde-visuel-admin.md`), qui échange le monde du registre
noir-encre contre la charte du propriétaire : indigo d'accent, vert, orange, rose, violet
décoratif, et Archivo sur les trois styles de titre. Ce que le 004 a posé et que le 061 ne touche
pas : la structure imprimée (filets, colonnes, cases) plutôt qu'empilée, l'échelle d'espacement,
les formes, le mouvement, et la règle « jamais la couleur seule ».

| Fichier | Contenu |
|---|---|
| `app_colors.dart` | Toutes les couleurs, écrites valeur par valeur. Rôles Material 3 clair et sombre, encres d'état. Aucun calcul, aucune graine. |
| `app_typography.dart` | `AppFonts` (les trois familles embarquées : Atkinson texte, Atkinson Mono nombres, Archivo titres), `AppTextStyles` (échelle fixe ratio 1.2, chiffres tabulaires) et la construction du `TextTheme`. |
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

## Les deux indigos, et les trois teintes qui ne sont pas du texte

Le ticket 061 sépare ce que le 004 confondait. `primary` (`#7655FA`) est un **remplissage** :
bouton, sélection, jour courant, bloc de grille. `accentTexte` (`#5840BC`) est la même couleur
assombrie pour tenir en ligne, sur le blanc comme sur le papier. Écrire du texte en `primary` est
un défaut : 4.72:1 suffit pour un bouton à texte blanc, pas pour de l'indigo sur blanc lu dehors.

Trois teintes de la charte n'ont **jamais** le droit d'être du texte en thème clair :
`orangeVif` (`#F59638`), `roseVif` (`#F9357C`) et `accentDecoratif` (`#B142E8`). Elles remplissent
un bloc, un segment de barre, une pastille ; le texte posé dessus est l'encre du registre.
`accentDecoratif` va plus loin : il ne porte **aucun état**, jamais — marque et illustration
d'état vide seulement. Le test de contraste garde ces trois-là en vérifiant qu'elles restent
**sous** 4.5:1, ce qui rend l'erreur impossible à commettre en silence.

De nuit, l'orange et le rose vifs deviennent du texte (`darkTertiary`, `darkError`), parce que le
fond a changé de côté. C'est mesuré, pas supposé.

## Ce que dit l'indigo, ce que dit le vert

Deux teintes, deux sens, et aucun recouvrement.

- **Indigo** — ce qui est **choisi** et ce qui est **disponible**. `primary-container` est la
  pastille de la sélection : segment choisi, puce choisie, mois choisi, jour choisi, destination
  de navigation courante. `onPrimaryContainer` est son encre, 6.74:1 en clair, 9.07:1 de nuit.
- **Vert** — ce qui est **acquis** : accepté, couvert, validé, publié, saisie ouverte,
  enregistré. C'est la famille `etatAccepte*`, mêmes valeurs que `etatInfo*`.

Material 3 sélectionne en `secondary-container`, c'est-à-dire, depuis le 061, en vert. **Tout
composant qui exprime une sélection doit donc être réglé dans `app_theme.dart`** —
`segmentedButtonTheme`, `chipTheme`, `navigationBarTheme`, `navigationRailTheme`,
`navigationDrawerTheme` le sont. Un composant Material ajouté sans ce réglage repartira en vert
et fera dire à la couleur deux choses à la fois.

Les deux pastilles ont presque la même valeur (1.01:1 l'une contre l'autre) : en niveaux de gris
elles sont le même gris. Rien de ce qui sépare « choisi » de « accepté » ne repose donc sur la
teinte — l'icône et le libellé le font, et `StatusDescriptor` les rend obligatoires.

## Valeurs dérivées ici

Les accents sombres viennent du brief ; **les conteneurs sombres ont été dérivés dans
`app_colors.dart`**, avec deux cibles : texte du conteneur à 4.5:1 au moins sur le conteneur, et
conteneur détaché de la surface de nuit d'au moins 1.3:1. Chaque valeur porte son ratio en
commentaire, et le test le recalcule.

Les familles « planning », « période » et « synchronisation » n'ont pas de teinte propre : elles
réemploient les tokens des quatre familles de tête (indigo, vert, orange, rose).

## Vérification

`test/core/theme/contraste_test.dart` recalcule le ratio WCAG de chaque paire du système à chaque
exécution : un changement de couleur qui casse 4.5:1 (texte) ou 3:1 (filet porteur d'état) fait
échouer la suite. `test/core/theme/app_status_test.dart` interdit deux icônes identiques dans une
même famille d'états. `test/core/theme/selection_et_accepte_test.dart` monte un bouton segmenté,
une puce et les badges « Accepté » et « Validé » en clair et en sombre, et vérifie sur la couleur
**peinte** que la sélection est indigo et que l'acquis est vert.
