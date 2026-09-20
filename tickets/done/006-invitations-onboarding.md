# 006 — Invitations et onboarding des membres

- **Épopée** : E1 Authentification
- **Priorité** : P0
- **Dépend de** : 005, 008
- **Branche** : `feat/006-invitations-onboarding`
- **PR** : https://github.com/slider973/astreinte-manager/pull/7
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

  **Écart assumé : la relecture remplace le temps réel.** `invitations` est
  volontairement hors de la réplication temps réel (`docs/SCHEMA.md § 9`) : le
  canal Realtime ne sait pas masquer une colonne, et `invitations.token` est un
  porteur de droits qui ne doit jamais sortir. Publier la table donnerait le
  jeton à tout admin connecté, et le premier trou de politique le donnerait à
  tout le monde. L'écran « Membres » relit donc les deux listes à trois
  moments : à son ouverture (`membresControllerProvider` est auto-disposé, son
  état ne survit pas à la navigation), au retour de l'application au premier
  plan, et après chaque action — envoi, renvoi, annulation. Un admin resté sur
  l'écran pendant qu'un invité accepte voit la liste à jour dès qu'il y revient
  ou qu'il rouvre l'application ; le bouton « Relire la liste » reste la sortie
  immédiate. Si un vrai temps réel devient nécessaire, il passera par une vue
  sans jeton, à ouvrir dans un ticket dédié.
