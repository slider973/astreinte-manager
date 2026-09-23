# 063 — Passer d'une destination à l'autre sans glissement

- **Épopée** : E0 Fondations
- **Priorité** : P1
- **Dépend de** : 004
- **Branche** : `feat/063-transition-entre-destinations`
- **PR** : —
- **Statut** : en cours depuis 2026-09-23

## Contexte

Signalé par le propriétaire le 23 septembre 2026 : « quand tu cliques sur Admin, l'animation de navigation part de droite à gauche, et quand tu recliques sur Profil ça recommence, ce n'est pas naturel ».

Les cinq destinations de la coquille (Mon mois, Propositions, Astreintes, Profil, Admin) sont des `GoRoute` plates dans `lib/core/router/app_router.dart`, avec `builder` et donc la page par défaut. Le thème (`app_theme.dart`, `pageTransitionsTheme`) applique la transition Cupertino sur macOS et iOS : un glissement de droite à gauche, celui d'un écran qu'on pousse par-dessus un autre. Passer d'une destination à sa sœur n'est pas une poussée : il n'y a ni avant ni après, rien à revenir. Le glissement dit le contraire de ce qui se passe.

## À faire

- Les routes des destinations de premier niveau (celles que `AppDestination` sert dans la colonne de navigation et la barre du bas, `/`, propositions, astreintes, profil, `/admin/planning`) changent **sans glissement** : `pageBuilder` avec `NoTransitionPage`, ou un fondu très court si l'inspection à l'écran le juge plus doux ; dans les deux cas la coquille (colonne, en-tête, barre du bas) reste visuellement en place et seul le contenu change.
- Les écrans de détail qu'on pousse et dont on revient (inviter, importer, notifications, paramètres, périodes, guide…) gardent la transition de poussée du thème.
- Vérifier que le geste retour du navigateur et `BoutonRetour` gardent leur comportement, et que `GoRouter.optionURLReflectsImperativeAPIs` n'est pas affecté.
- Un test de routeur : aller de `/` à `/admin/planning` puis à profil ne construit aucune transition de glissement (pas de `CupertinoPageTransition` ni de `SlideTransition` entre les deux), et pousser inviter depuis membres en construit une.

## Critères d'acceptation

- Sur Chrome (macOS et Android émulé), cliquer successivement Admin, Profil, Mon mois ne produit aucun glissement horizontal ; la colonne de navigation ne bouge pas.
- Pousser un écran de détail glisse toujours, revenir aussi.
- `flutter analyze` sans avertissement, `flutter test` verts, `flutter build web` qui passe, détecteur Impeccable à vide.
