# 016 — Matrice des disponibilités pour l'admin

- **Épopée** : E4 Planning
- **Priorité** : P0
- **Dépend de** : 008, 013, 014
- **Branche** : `feat/016-matrice-admin`
- **Statut** : en cours depuis 2026-09-20

## Contexte
Vue centrale de l'admin. Sur ordinateur en priorité, utilisable sur tablette, consultable sur téléphone.

## À faire
- Migration 0008 : fonction `availability_matrix(station, period)` et vue `v_member_load`.
- Écran admin « Planning du mois » : tableau membres en lignes, jours × (jour, nuit) en colonnes, cellules disponible / absent / non saisi. En-tête de ligne : nom, quotas (restant / max), commentaire du mois (icône avec tooltip).
- Filtres : masquer les non-saisis, trier par quota restant, rechercher un membre.
- Défilement horizontal avec colonne de noms figée.
- Saisie pour un membre par l'admin (touche sur cellule, avec confirmation la première fois), `set_by` renseigné.

## Critères d'acceptation
- 60 membres × 62 colonnes s'affichent en moins de 2 secondes.
- Les quotas affichés correspondent à `v_member_load`.
