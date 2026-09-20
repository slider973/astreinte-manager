# 006 — Invitations et onboarding des membres

- **Épopée** : E1 Authentification
- **Priorité** : P0
- **Dépend de** : 005, 008
- **Branche** : `feat/006-invitations-onboarding`
- **Statut** : terminé le 2026-09-20 (PR créée)

## À faire
- Edge Function `invite-member` : crée l'invitation, envoie l'email via Resend avec le lien `https://app/…/invite/<token>`.
- Edge Function `accept-invitation` : vérifie token et expiration, crée la membership, marque `accepted_at`.
- Écran admin : inviter par email (un ou plusieurs), liste des invitations en attente, renvoyer, annuler.
- Parcours invité : lien → connexion OTP avec l'email pré-rempli → acceptation → profil → guide 3 écrans → mois en cours.
- Écran d'aide « Ajouter à l'écran d'accueil » sur iOS Safari et Android Chrome, affiché une fois, avec captures pas à pas. Sur iOS, insister : sans installation, pas de notifications.

## Critères d'acceptation
- Une invitation expirée affiche un message clair et propose de contacter l'admin.
- Un email déjà membre ne peut pas être réinvité (index unique).
- L'invitation acceptée apparaît en temps réel côté admin.
