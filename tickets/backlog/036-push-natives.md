# 036 — Push natives iOS et Android (à la demande d'une caserne)

- **Épopée** : E6 Notifications
- **Priorité** : P2 — ne pas démarrer sans demande explicite d'une caserne
- **Dépend de** : 024, 025
- **Branche** : `feat/036-push-natives`

## Contexte
La PWA est le canal principal et le ticket 024 couvre le push web. Ce ticket ajoute les canaux natifs
uniquement si une caserne réclame l'app sur les stores (ticket 033).

## À faire
- iOS : clé APNs dans Firebase, capabilities Push Notifications et Background Modes, `firebase_options.dart` étendu à iOS.
- Android : `google-services.json`, canal de notification par défaut, icône monochrome.
- Enregistrement des tokens natifs dans `push_tokens` avec `platform` ios ou android (colonne déjà prévue).
- Réception au premier plan, en arrière-plan et au lancement depuis une notification, deep link via go_router.
- L'Edge Function `send-notification` n'a rien à changer : FCM route par token.

## Critères d'acceptation
- Un push de test arrive sur un iPhone réel et sur un Android réel avec l'app native.
- Le build web n'est pas affecté (aucune régression sur le ticket 024).
