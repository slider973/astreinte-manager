# 034 — RGPD : export et suppression des données

- **Épopée** : E9 Release
- **Priorité** : P1
- **Dépend de** : 007
- **Branche** : `feat/034-rgpd-export`
- **Statut** : terminé le 2026-09-21 (PR créée)

## À faire
- Edge Function `export-user-data` : JSON de tout ce qui concerne l'utilisateur (profil, memberships, disponibilités, attributions, notifications).
- Bouton dans le profil, fichier téléchargé ou envoyé par email.
- Suppression de compte (ticket 007) : anonymisation puis suppression auth.
- Page de politique de confidentialité et mentions légales.
- Registre des traitements minimal dans `docs/RGPD.md`.

## Critères d'acceptation
- L'export contient toutes les tables listées.
- Après suppression, aucune donnée nominative ne subsiste hors « Membre supprimé » dans les attributions.
