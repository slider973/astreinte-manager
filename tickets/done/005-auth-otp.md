# 005 — Connexion par email et code OTP

- **Épopée** : E1 Authentification
- **Priorité** : P0
- **Dépend de** : 001, 002
- **Branche** : `feat/005-auth-otp`
- **Statut** : terminé le 2026-09-20 (PR créée)

## À faire
- Écran de connexion : email, envoi du code à 6 chiffres via Supabase Auth (`signInWithOtp`), écran de saisie du code, renvoi du code avec compte à rebours.
- Support du lien magique en alternative (deep link vers l'app, redirection web).
- Persistance de session, rafraîchissement automatique, écran de déconnexion.
- Gestion des erreurs : email invalide, code expiré, trop de tentatives.
- Templates email Supabase personnalisés en français (code et lien magique).

## Critères d'acceptation
- Un utilisateur se connecte sur les trois plateformes avec un code reçu par email.
- La session survit à un redémarrage de l'app.
- Un utilisateur sans membership voit un écran « Aucune caserne, demandez une invitation ».
