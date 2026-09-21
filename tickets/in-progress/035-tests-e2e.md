# 035 — Tests d'intégration bout en bout

- **Épopée** : E9 Release
- **Priorité** : P1
- **Dépend de** : 021, 020
- **Branche** : `feat/035-tests-e2e`
- **Statut** : en cours depuis 2026-09-21

## À faire
- Tests `integration_test` Flutter sur le parcours complet contre un Supabase local seedé : admin invite → membre accepte → membre saisit un mois → admin construit et publie → membre refuse un créneau → admin réattribue → second membre accepte → planning validé.
- Tests SQL des RLS (ticket 008) et des crons avec délais réduits.
- Exécution en CI sur Chrome headless.

## Critères d'acceptation
- Le parcours complet passe en CI en moins de 10 minutes.
