# 015 — Rappels de saisie des disponibilités

- **Épopée** : E3 Disponibilités
- **Priorité** : P1
- **Dépend de** : 014, 025
- **Branche** : `feat/015-rappels-saisie`
- **PR** : https://github.com/slider973/astreinte-manager/pull/17
- **Statut** : terminé le 2026-09-20 (PR créée)

## À faire
- Cron `availability_reminders` : J-3 push, J-1 email, aux membres actifs sans aucune ligne `availabilities` pour la période.
- Un seul envoi par membre et par échéance (tracer dans `notifications`).

## Critères d'acceptation
- Un membre ayant saisi au moins un créneau ne reçoit pas de rappel.
- L'admin voit le taux de saisie sur l'écran Périodes.
