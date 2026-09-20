# 026 — Centre de notifications in-app

- **Épopée** : E6 Notifications
- **Priorité** : P1
- **Dépend de** : 025
- **Branche** : `feat/026-centre-notifications`
- **PR** : https://github.com/slider973/astreinte-manager/pull/16
- **Statut** : terminé le 2026-09-20 (PR créée)

## À faire
- Écran « Notifications » : liste des lignes `inapp`, non lues en évidence, touche = deep link + `read_at`.
- Badge sur l'icône.
- Bouton « Tout marquer comme lu ».

## À prévoir, remonté par la revue du ticket 025
- **Une notification définitivement en échec ne laisse rien à voir au membre.** Quand
  l'Edge Function `send-notification` reste injoignable, la demande finit `failed` dans
  `notification_outbox` — visible seulement par une requête d'exploitation. Aucune ligne
  `notifications` n'existe, donc le centre n'affiche rien, et personne ne sait que
  quelque chose a été perdu. À traiter ici : soit une ligne `inapp` écrite par
  `cron_dispatch_notifications` au moment de l'abandon, soit un bandeau d'alerte pour
  l'admin de la caserne. Décider à l'ouverture du ticket.

## Critères d'acceptation
- Une notification push reçue apparaît aussi dans la liste sans relancer l'app (Realtime).
