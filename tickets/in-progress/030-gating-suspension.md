# 030 — Mode suspendu et bannières

- **Épopée** : E8 Abonnement
- **Priorité** : P1
- **Dépend de** : 029
- **Branche** : `feat/030-gating-suspension`
- **Statut** : en cours depuis 2026-09-21

## À faire
- `station_writable` bloque les écritures (déjà dans RLS, ticket 008) ; l'app affiche un bandeau explicatif et désactive les actions.
- Bannière d'essai : « Essai jusqu'au … » pour les admins, rappels in-app à J-14 et J-3.
- Email aux admins à J-7 et à la suspension.

## Critères d'acceptation
- En `suspended`, un membre peut lire son planning mais pas modifier ses disponibilités, avec message clair.
