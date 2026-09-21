# 023 — Vue du planning de la caserne pour les membres

- **Épopée** : E5 Validation
- **Priorité** : P1
- **Dépend de** : 019
- **Branche** : `feat/023-planning-caserne`
- **Statut** : en cours depuis 2026-09-21

## À faire
- Écran « Planning » : calendrier du mois avec, par créneau, les noms des membres acceptés. Visible dès `published` pour ses propres créneaux, complet dès `validated`.
- Indication « en attente de validation » tant que le planning n'est pas validé.
- Sélecteur de mois (mois publiés uniquement).

## Critères d'acceptation
- Un membre ne voit pas les attributions des autres tant que le planning est `published` (RLS).
