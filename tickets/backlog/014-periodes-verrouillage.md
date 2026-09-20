# 014 — Périodes, date limite et verrouillage

- **Épopée** : E3 Disponibilités
- **Priorité** : P0
- **Dépend de** : 008, 010
- **Branche** : `feat/014-periodes-verrouillage`

## À faire
- Migration 0009 (partie 1) : cron `create_periods` et `lock_periods`.
- Écran admin « Périodes » : liste des mois avec statut, date limite, taux de saisie ; actions rouvrir, verrouiller maintenant, créer un mois.
- Réouverture tracée dans `audit_log`.
- Saisie par l'admin pour un membre (depuis la matrice, ticket 016) avec `set_by` et audit.

## Critères d'acceptation
- Une période passe en `locked` dans l'heure suivant sa deadline.
- Après verrouillage, un membre reçoit une erreur claire s'il tente d'écrire (RLS) et la grille est en lecture seule.
