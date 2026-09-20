# 024 — Push web via Firebase Cloud Messaging (PWA)

- **Épopée** : E6 Notifications
- **Priorité** : P0
- **Dépend de** : 001, 005
- **Branche** : `feat/024-fcm-setup`

## À faire
- Projet Firebase, `firebase_messaging` configuré pour le Web : service worker `firebase-messaging-sw.js`, clé VAPID, `firebase_options.dart` limité à la plateforme web. Pas de configuration APNs ni Android à ce ticket (voir 036).
- Demande de permission au bon moment (après onboarding, pas au premier lancement).
- Enregistrement du token dans `push_tokens` avec plateforme et libellé d'appareil, rafraîchissement à chaque lancement.
- Réception : au premier plan (bannière in-app), en arrière-plan, au lancement depuis une notification (deep link via go_router).
- Détection « PWA installée » (`display-mode: standalone`) pour n'afficher l'aide d'installation qu'en navigateur, et message explicite sur iOS Safari non installé : « Ajoute l'app à l'écran d'accueil pour recevoir les notifications ».

## Critères d'acceptation
- Un push de test envoyé depuis la console Firebase arrive sur Chrome Android en PWA installée, Safari iOS 16.4+ en PWA installée, et Chrome desktop.
- L'app compile toujours pour iOS et Android (pas de plugin web-only qui casse le build natif), sans qu'un test natif soit requis.
- Le token est présent dans `push_tokens` pour chaque appareil.
