# 008 — Row Level Security et fonctions d'accès

- **Épopée** : E2 Casernes
- **Priorité** : P0
- **Dépend de** : 002
- **Branche** : `feat/008-rls-multi-tenant`

## Contexte
Référence : `docs/SCHEMA.md` sections 3 et 4. C'est le socle de sécurité, à faire avant tout écran qui lit des données.

## À faire
- Migration 0007 : fonctions `is_member`, `is_admin`, `is_super_admin`, `station_writable`.
- Politiques RLS pour toutes les tables selon le tableau de la section 4.
- Trigger `assignments_member_transition`.
- Tests SQL (pgTAP ou script) : un membre de la caserne A ne lit rien de la caserne B ; un membre ne modifie pas ses dispos en période verrouillée ; un membre ne passe pas une attribution de `accepted` à `proposed`.

## Critères d'acceptation
- Tous les tests passent en local et en CI.
- `supabase db lint` ne signale aucune table sans RLS.
