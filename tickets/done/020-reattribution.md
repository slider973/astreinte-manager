# 020 — Réattribution d'un créneau refusé ou modifié

- **Épopée** : E4 Planning
- **Priorité** : P0
- **Dépend de** : 019
- **Branche** : `feat/020-reattribution`
- **Statut** : terminé le 2026-09-21 (PR créée)

## À faire
- Edge Function `reassign-shift` : marque l'ancienne attribution `replaced` (si accepted) ou laisse `declined`, crée la nouvelle en `proposed` avec `proposed_at = now()`, notifie le nouveau membre, notifie l'ancien si son attribution était acceptée.
- Depuis le suivi ou la matrice : sur un créneau refusé, le panneau latéral des candidats s'ouvre directement.
- Annuler une attribution acceptée (`cancelled`) avec notification.
- Modifier un planning validé le repasse en `published` ; seuls les créneaux touchés changent d'état.

## Critères d'acceptation
- Un refus puis une réattribution ne génère qu'une notification, au nouveau membre.
- L'historique (`declined`, `replaced`) reste consultable dans le suivi.
