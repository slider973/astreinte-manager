# 021 — Écran des propositions pour le membre

- **Épopée** : E5 Validation
- **Priorité** : P0
- **Dépend de** : 008, 024
- **Branche** : `feat/021-ecran-propositions`
- **Statut** : en cours depuis 2026-09-21

## Contexte
Deuxième écran le plus important. Il doit permettre de répondre en deux touches depuis la notification.

## À faire
- Écran « Propositions » : liste des attributions `proposed` avec `proposed_at` non nul, groupées par mois, chaque ligne : date, créneau, boutons Accepter / Refuser. Refus : motif facultatif en une ligne.
- Badge sur l'onglet avec le nombre en attente.
- Deep link `/proposals` depuis la notification.
- Mise à jour du statut via update RLS (trigger vérifie la transition).
- État vide : « Aucune proposition en attente ».

## Critères d'acceptation
- Accepter puis rafraîchir : la ligne disparaît et l'astreinte apparaît dans « Mes astreintes ».
- Une attribution annulée par l'admin entre-temps affiche un message et disparaît.
