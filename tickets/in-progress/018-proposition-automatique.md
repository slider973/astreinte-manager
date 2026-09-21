# 018 — Proposition automatique de remplissage

- **Épopée** : E4 Planning
- **Priorité** : P1
- **Dépend de** : 017
- **Branche** : `feat/018-proposition-automatique`
- **Statut** : en cours depuis 2026-09-21

## À faire
- Edge Function `auto-propose` : pour chaque créneau non pourvu, dans l'ordre chronologique, choisir le membre disponible avec le plus de quota restant (astreintes et weekends), puis le moins d'astreintes acceptées sur les 3 périodes précédentes, puis aléatoire. Ne jamais dépasser un quota. Ne jamais attribuer un membre absent ou non saisi.
- Bouton « Proposer automatiquement » avec résumé avant application : N créneaux remplis, M non pourvus faute de candidats.
- Ne touche pas aux attributions déjà faites manuellement.

## Critères d'acceptation
- Sur le seed, la fonction remplit tous les créneaux ayant au moins un candidat éligible.
- Un test vérifie qu'aucun quota n'est dépassé.
