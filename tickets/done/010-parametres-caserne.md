# 010 — Paramètres de la caserne

- **Épopée** : E2 Casernes
- **Priorité** : P1
- **Dépend de** : 008
- **Branche** : `feat/010-parametres-caserne`
- **PR** : https://github.com/slider973/astreinte-manager/pull/9
- **Statut** : terminé le 2026-09-20 (PR créée)

## À faire
- Écran admin « Paramètres » : nom, fuseau, heures jour/nuit (affichage), effectif requis jour et nuit, surcharges par jour de semaine et par date, jour limite de saisie, délais de relance.
- Validation du JSON `settings` côté app et dans une Edge Function `update-station-settings` (ou contrainte `check` avec fonction SQL).

## Critères d'acceptation
- Changer l'effectif requis n'affecte que les plannings créés ensuite (les shifts existants gardent leur `required_count`).
- Changer le jour limite recalcule `deadline_at` des périodes encore ouvertes.
