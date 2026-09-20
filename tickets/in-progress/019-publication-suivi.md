# 019 — Publication et suivi des réponses

- **Épopée** : E4 Planning
- **Priorité** : P0
- **Dépend de** : 017, 025
- **Branche** : `feat/019-publication-suivi`
- **Statut** : en cours depuis 2026-09-20

## Condition d'entrée, relevée en revue du ticket 017
La machine à états des plannings n'est gardée par rien en base. Un admin peut aujourd'hui
ramener un planning publié en brouillon, supprimer une attribution, puis republier : la
restriction posée au ticket 017 se contourne ainsi en deux écritures, et la règle « rien n'est
jamais supprimé » du produit n'est pas tenue. Avant ou pendant ce ticket :
- interdire en base les transitions de statut interdites par `docs/WORKFLOWS.md` section 2,
  en particulier tout retour en brouillon depuis publié ou validé ;
- borner la suppression d'un planning au seul brouillon, la cascade ne consultant pas les
  politiques de sécurité.

## À faire
- Edge Function `publish-schedule` : vérifie qu'on est admin, passe en `published`, renseigne `proposed_at`, appelle `send-notification` groupé par membre.
- Bouton « Publier » avec récapitulatif : créneaux non pourvus, membres au-delà de leur quota, membres attribués hors disponibilité.
- Migration 0008 (partie 2) : vue `v_schedule_progress`.
- Écran de suivi : barre de progression, liste des créneaux par état (en attente, accepté, refusé, non pourvu), liste des retardataires avec bouton « relancer maintenant ».
- Realtime pour mise à jour instantanée.
- Trigger `schedule_auto_validate`.

## Critères d'acceptation
- Chaque membre attribué reçoit une seule notification groupée listant ses créneaux.
- Quand la dernière attribution requise est acceptée, le planning passe en `validated` sans action admin.
