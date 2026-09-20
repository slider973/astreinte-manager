# 009 — Gestion des membres par l'admin

- **Épopée** : E2 Casernes
- **Priorité** : P0
- **Dépend de** : 006, 008
- **Branche** : `feat/009-gestion-membres`
- **PR** : https://github.com/slider973/astreinte-manager/pull/8
- **Statut** : terminé le 2026-09-20 (PR créée)

## À faire
- Écran admin « Membres » : liste avec statut, rôle, dernière saisie, recherche.
- Actions : promouvoir/rétrograder admin (pas soi-même), désactiver, réactiver, modifier le nom affiché.
- Un admin ne peut pas se désactiver ni se rétrograder s'il est le dernier admin.

## Critères d'acceptation
- Un membre désactivé ne voit plus la caserne à sa prochaine connexion.
- Le dernier admin ne peut pas être rétrogradé (erreur claire).
