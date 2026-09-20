# 024 — Configuration Firebase Cloud Messaging sur les trois plateformes

- **Épopée** : E6 Notifications
- **Priorité** : P0
- **Dépend de** : 001, 005
- **Branche** : `feat/024-fcm-setup`

## À faire
- Projet Firebase, `firebase_messaging` configuré pour iOS (APNs key, capabilities), Android, Web (service worker `firebase-messaging-sw.js`, clé VAPID).
- Demande de permission au bon moment (après onboarding, pas au premier lancement).
- Enregistrement du token dans `push_tokens` avec plateforme et libellé d'appareil, rafraîchissement à chaque lancement.
- Réception : au premier plan (bannière in-app), en arrière-plan, au lancement depuis une notification (deep link via go_router).
- Sur web, détection « PWA installée » pour n'afficher l'aide d'installation qu'en navigateur.

## Critères d'acceptation
- Un push de test envoyé depuis la console Firebase arrive sur iOS natif, Android natif, Chrome Android en PWA, Safari iOS en PWA installée.
- Le token est présent dans `push_tokens` pour chaque appareil.
