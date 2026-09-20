# 012 — Raccourcis de sélection

- **Épopée** : E3 Disponibilités
- **Priorité** : P0
- **Dépend de** : 011
- **Branche** : `feat/012-raccourcis-selection`
- **PR** : https://github.com/slider973/astreinte-manager/pull/11
- **Statut** : terminé le 2026-09-20 (PR créée)

## À faire
- Barre de raccourcis au-dessus de la grille : « Tous les weekends », « Toutes les nuits en semaine », « Tous les jours en semaine », « Tout le mois », « Copier le mois précédent », « Tout effacer ».
- Chaque raccourci propose jour, nuit ou les deux.
- Confirmation avant « Tout effacer » et « Copier le mois précédent » si des saisies existent.
- Opérations groupées en une seule requête (RPC `bulk_set_availabilities`) pour éviter 62 upserts.

## Critères d'acceptation
- « Tous les weekends, nuit » coche exactement les samedis et dimanches nuit.
- « Copier le mois précédent » aligne sur les jours de semaine (pas sur les numéros de jour).
