# 017 — Construction du planning en brouillon

- **Épopée** : E4 Planning
- **Priorité** : P0
- **Dépend de** : 016
- **Branche** : `feat/017-brouillon-attribution`
- **PR** : https://github.com/slider973/astreinte-manager/pull/19
- **Statut** : terminé le 2026-09-20 (PR créée)

## À faire
- Création du planning du mois : génère les `shifts` (chaque jour × jour/nuit) avec `required_count` depuis les settings et les surcharges.
- Dans la matrice, une ligne « Créneau » en haut montre pour chaque colonne l'état : à pourvoir (0/1), pourvu (1/1), sur-pourvu.
- Touche sur un créneau : panneau latéral avec les membres disponibles triés par quota restant décroissant puis charge des 3 derniers mois croissante ; membres à quota atteint grisés mais sélectionnables avec avertissement ; option « attribuer quelqu'un de non disponible » avec avertissement et `was_available = false`.
- Retirer une attribution en brouillon la supprime (pas de trace nécessaire avant publication).
- Modifier `required_count` d'un créneau.
- Realtime sur `assignments` pour que deux admins voient les changements de l'autre.

## Critères d'acceptation
- Impossible d'attribuer deux fois le même membre au même créneau (erreur base remontée proprement).
- Les quotas de la ligne membre se mettent à jour à chaque attribution.
