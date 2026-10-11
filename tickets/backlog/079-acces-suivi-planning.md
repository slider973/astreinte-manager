# 079 — Le suivi de planning est sans retour, et la réattribution avec lui

- **Épopée** : E4 Planning
- **Priorité** : P1
- **Dépend de** : 019, 020
- **Branche** : `feat/079-acces-suivi-planning`
- **Statut** : à faire

## Contexte

Signalé par le propriétaire le 10 octobre 2026, après ses tests, en deux phrases qui
décrivent le même défaut :

> « j'ai une vue suivie de planning, je ne sais pas comment y retourner »

> « quand je dois faire des rétributions, j'ai pas toujours la possibilité »

(« rétributions » = **réattributions** : remplacer un pompier qui a refusé son astreinte.)

Diagnostic (lu dans le code, le 10 octobre) :

1. **Le suivi n'est pas une destination.** `AppDestination.pour`
   (`app_scaffold.dart:62-95`) construit cinq destinations : Accueil, Calendrier, Astreintes,
   Boîte, et Admin pour les administrateurs. `AppRoutes.suivi` n'en fait pas partie — le mot
   « suivi » n'apparaît ni dans `app_scaffold.dart` ni dans `destinations.dart`.

2. **Deux seuls chemins y mènent**, et aucun n'est un retour :
   - un lien de notification (`destination_push.dart:114`),
   - la matrice admin après publication (`matrice_screen.dart:473`).

   Sorti de l'écran, un administrateur n'a aucun moyen d'y revenir : il doit republier un
   planning ou attendre une notification. Ce n'est pas un défaut de recherche de
   l'utilisateur, c'est une impasse de navigation.

3. **La réattribution n'existe que là.** Le geste vit uniquement dans
   `suivi_screen.dart:127-234` (`_reattribuer`, `cibleReattributionProvider`,
   `confirmation_reattribution.dart`). Un écran inatteignable rend donc la réattribution
   inatteignable — d'où le « pas toujours la possibilité ».

   Les quatre blocages de `_raisonReattribution()` (`suivi_screen.dart:212-224`) sont, eux,
   légitimes et restent en place : lecture seule, hors ligne, planning en brouillon, planning
   archivé. Ils expliquent leur refus à l'écran.

## À faire

1. **Un retour depuis l'écran Admin** : sur `planning_admin`, lister les plannings publiés ou
   validés du centre avec, pour chacun, un accès à son suivi. C'est le chemin naturel : un
   administrateur qui veut réattribuer part de son planning.
2. **Le fil d'Ariane fonctionne** : `suivi_screen` doit pouvoir revenir à l'écran Admin même
   lorsqu'on y arrive par une notification (pile de navigation vide). Utiliser le retour de
   go_router vers `planningAdmin` plutôt qu'un `pop` qui n'a rien à dépiler.
3. **Dire où mène le geste** : quand un planning compte au moins une astreinte refusée,
   l'indiquer dans la liste (un compte, pas une couleur seule — contexte d'usage binding :
   gants, extérieur).
4. **Ne pas ajouter de sixième onglet** : la barre en a déjà cinq, et le suivi est un écran
   d'administrateur, pas une destination quotidienne de pompier.

## Critères d'acceptation

- Depuis l'écran Admin, un administrateur atteint le suivi d'un planning publié en un geste.
- Depuis le suivi atteint par une notification, le retour mène à l'écran Admin sans écran
  blanc ni pile vide.
- Un planning avec des astreintes refusées le montre dans la liste, par un compte lisible.
- Un membre non administrateur ne voit aucun de ces accès (vérifié par test).
- `flutter analyze` sans avertissement, `flutter test` verts, `flutter build web` passe.

## Hors périmètre

- Déplacer la réattribution hors du suivi : son contexte (les candidats du créneau) est au
  bon endroit.
- Lever les quatre blocages de `_raisonReattribution()` : ils sont voulus.
