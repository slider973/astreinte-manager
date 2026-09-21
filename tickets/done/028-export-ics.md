# 028 — Export calendrier ICS

- **Épopée** : E7 Calendrier
- **Priorité** : P1
- **Dépend de** : 027
- **Branche** : `feat/028-export-ics`
- **PR** : https://github.com/slider973/astreinte-manager/pull/34
- **Statut** : terminé le 2026-09-21 (PR créée)

## À faire
- Edge Function `ics-feed` : GET public avec token secret par membre (colonne `ics_token` sur `profiles`, régénérable), renvoie un `.ics` des astreintes acceptées avec heures depuis les settings de la caserne.
- Écran profil : bouton « Ajouter à mon calendrier » avec l'URL d'abonnement et instructions Google / Apple / Outlook, bouton « Régénérer le lien ».
- Bouton « Ajouter cette astreinte » sur le détail : téléchargement d'un fichier ICS unique (web) ; pas de plugin natif à ce stade.

## Critères d'acceptation
- L'abonnement dans Apple Calendar affiche les astreintes et se met à jour après une nouvelle acceptation.
