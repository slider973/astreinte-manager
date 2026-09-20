# 028 — Export calendrier ICS

- **Épopée** : E7 Calendrier
- **Priorité** : P1
- **Dépend de** : 027
- **Branche** : `feat/028-export-ics`

## À faire
- Edge Function `ics-feed` : GET public avec token secret par membre (colonne `ics_token` sur `profiles`, régénérable), renvoie un `.ics` des astreintes acceptées avec heures depuis les settings de la caserne.
- Écran profil : bouton « Ajouter à mon calendrier » avec l'URL d'abonnement et instructions Google / Apple / Outlook, bouton « Régénérer le lien ».
- Bouton « Ajouter cette astreinte » sur le détail (fichier ICS unique, via `add_2_calendar` ou partage).

## Critères d'acceptation
- L'abonnement dans Apple Calendar affiche les astreintes et se met à jour après une nouvelle acceptation.
