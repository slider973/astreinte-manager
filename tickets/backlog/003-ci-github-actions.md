# 003 — Mettre en place la CI

- **Épopée** : E0 Fondations
- **Priorité** : P1
- **Dépend de** : 001, 002
- **Branche** : `feat/003-ci-github-actions`

## À faire
- Workflow GitHub Actions sur PR : `flutter analyze`, `flutter test`, `flutter build web`.
- Workflow : `supabase db lint` et rejeu des migrations sur un Postgres éphémère.
- Cache des dépendances Flutter et pub.
- Badge de statut dans le README.

## Critères d'acceptation
- Une PR avec une erreur d'analyse est bloquée.
- Une migration cassée fait échouer la CI.
