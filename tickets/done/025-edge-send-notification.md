# 025 — Edge Function send-notification

- **Épopée** : E6 Notifications
- **Priorité** : P0
- **Dépend de** : 002, 024
- **Branche** : `feat/025-edge-send-notification`
- **PR** : https://github.com/slider973/astreinte-manager/pull/15
- **Statut** : terminé le 2026-09-20 (PR créée)

## À faire
- Function `send-notification` : entrée `{type, user_ids, station_id, payload, channels?}`. Construit titre et corps en français par type, insère la ligne `inapp`, envoie via FCM (HTTP v1, service account) à tous les tokens du membre, envoie via Resend si canal email demandé ou si aucun token push. Trace chaque envoi dans `notifications` avec `delivered` et `error`.
- Supprime les tokens rejetés par FCM (`UNREGISTERED`).
- Respecte `profiles.push_enabled` pour les types non critiques.
- Templates email HTML simples en français.
- Appel depuis SQL via `pg_net` (fonction `notify(...)`) pour les triggers et crons.

## Critères d'acceptation
- Test d'intégration : un appel avec un membre sans token produit un email.
- Un token invalide est supprimé après un envoi.
