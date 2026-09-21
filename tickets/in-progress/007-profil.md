# 007 — Profil utilisateur

- **Épopée** : E1 Authentification
- **Priorité** : P1
- **Dépend de** : 005
- **Branche** : `feat/007-profil`
- **Statut** : en cours depuis 2026-09-21

## À faire
- Écran profil : prénom, nom, téléphone, préférence push (non critiques), langue (fr uniquement au MVP).
- Sélecteur de caserne si l'utilisateur appartient à plusieurs casernes.
- Suppression de compte : Edge Function qui anonymise le profil et supprime l'utilisateur auth (ticket 034 pour l'export préalable).

## Critères d'acceptation
- Les modifications sont visibles par l'admin dans la liste des membres.
- La suppression conserve les attributions passées sous « Membre supprimé ».
