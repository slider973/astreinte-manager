# 011 — Grille de saisie des disponibilités

- **Épopée** : E3 Disponibilités
- **Priorité** : P0
- **Dépend de** : 004, 008
- **Branche** : `feat/011-saisie-dispos-grille`

## Contexte
Écran le plus utilisé. Doit être plus rapide que la grille de l'ancien intranet (deux cases par jour, une touche par case).

## À faire
- Écran « Mon mois » : sélecteur de mois (périodes ouvertes en priorité), grille 7 colonnes, chaque jour montre deux zones jour/nuit avec état disponible / absent / non saisi.
- Touche simple : cycle non saisi → disponible → absent → non saisi (ou menu contextuel, à trancher en design).
- Glissement continu : peindre plusieurs jours avec l'état de la première case touchée.
- Sauvegarde automatique par upsert/delete avec debounce 500 ms, indicateur « enregistré » / « erreur, réessayer ».
- Compteurs en bas : jours, nuits, weekends cochés.
- Mois verrouillé : grille en lecture seule avec bandeau explicatif.
- Weekends et fériés français visuellement distingués (table de fériés en dur pour 3 ans, ou calcul).

## Critères d'acceptation
- Saisir un mois complet en glissant prend moins de 30 secondes.
- Une perte de réseau pendant la saisie affiche l'erreur et rejoue à la reconnexion.
- Les états sont lisibles sans la couleur (icône).
