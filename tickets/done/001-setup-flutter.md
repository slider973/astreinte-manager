# 001 — Initialiser le projet Flutter et l'architecture

- **Épopée** : E0 Fondations
- **Priorité** : P0
- **Dépend de** : aucune
- **Branche** : `feat/001-setup-flutter`
- **PR** : https://github.com/slider973/astreinte-manager/pull/1
- **Statut** : terminé le 2026-09-20 (PR créée)

## Contexte
Point de départ de toute l'app. Une seule base de code pour iOS, Android et Web.

## À faire
- Créer le projet Flutter avec les cibles ios, android, web. Package `fr.astreintesp.app` (à renommer si le nom change).
- Structure par fonctionnalité : `lib/features/<feature>/{data,domain,presentation}`, `lib/core/{router,theme,supabase,notifications,widgets}`.
- Riverpod pour l'état, go_router pour la navigation avec support des deep links.
- Gestion des environnements (dev, prod) via `--dart-define` : URL Supabase, clé anon, projet Firebase.
- Linter strict (`flutter_lints` + règles supplémentaires), `analysis_options.yaml` versionné.
- README de démarrage : commandes de build, variables, comment lancer sur chaque cible.

## Critères d'acceptation
- `flutter run` fonctionne sur simulateur iOS, émulateur Android et Chrome.
- `flutter analyze` sans avertissement.
- Un écran « Hello » lit une variable d'environnement et l'affiche.

## Hors périmètre
- Aucune fonctionnalité métier.
