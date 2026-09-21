# 038 — Limiter le débit des invitations

- **Épopée** : E2 Casernes
- **Priorité** : P1
- **Dépend de** : 006
- **Branche** : `feat/038-limite-debit-invitations`
- **Statut** : terminé le 2026-09-21 (PR créée)

## Contexte
Relevé en revue du ticket 006 : la fonction d'invitation accepte vingt adresses par appel et un
nombre illimité d'appels. Un admin peut donc créer des comptes confirmés et envoyer des courriels
à des adresses arbitraires depuis l'infrastructure du produit, ce qui expose le domaine d'envoi à
un signalement pour abus et coûte des envois facturés.

## À faire
- Compteur d'invitations par caserne et par heure, tenu en base pour être testable en intégration
  continue, avec un plafond configurable dans les paramètres de la caserne.
- Refus explicite au-delà du plafond, avec un code d'erreur dédié et un message en français
  indiquant quand réessayer.
- Journaliser le dépassement dans le journal d'audit.
- Prévoir un plafond plus élevé pour le super-admin.

## Critères d'acceptation
- Un test SQL vérifie qu'au-delà du plafond, la création d'invitation est refusée.
- Le message affiché à l'admin indique le délai avant de pouvoir réessayer.
