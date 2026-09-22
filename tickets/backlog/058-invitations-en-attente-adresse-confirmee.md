# 058 — Lire l'adresse confirmée à la source, pas dans les métadonnées

- **Épopée** : E1 Authentification
- **Priorité** : P2
- **Dépend de** : 051
- **Branche** : `feat/058-invitations-en-attente-adresse-confirmee`
- **PR** : —
- **Statut** : à faire

## Contexte

Relevé par la revue du ticket 051, le 22 septembre 2026. `my_pending_invitations()` ne rend les
invitations en attente d'une adresse que si le jeton ne porte pas `email_verified = false`, en
lisant la revendication au premier niveau du jeton ou dans `user_metadata`. Mesuré sur ce projet :
GoTrue ne pose pas la revendication au premier niveau pour un compte créé par `invite-member`, et
c'est `user_metadata.email_verified` qui tranche en pratique.

Deux réserves, aucune exploitable aujourd'hui, toutes deux à fermer avant qu'elles le deviennent :

1. `user_metadata` n'est pas une source d'autorité : l'utilisateur peut l'écrire lui-même
   (`auth.updateUser`). Aujourd'hui ce n'est qu'un auto-blocage, jamais une escalade, mais une
   fonction `security definer` a accès à l'autorité réelle, `auth.users.email_confirmed_at`.
2. Ce qui rend le repli permissif sûr ne vit pas dans la migration mais dans `supabase/config.toml`
   (`enable_signup = false`, `enable_anonymous_sign_ins = false`) : aucun compte ne peut naître
   pour une adresse qu'on ne contrôle pas. Rouvrir l'inscription un jour sans le savoir rouvrirait
   la porte, et rien ne le signalerait.

## À faire

- Remplacer la lecture des revendications par un contrôle sur `auth.users.email_confirmed_at`
  pour l'utilisateur de la session, dans `my_pending_invitations()` et dans
  `accept_invitation_by_id()`, en gardant `search_path` figé et les droits inchangés.
- Écrire dans la migration le lien entre cette fonction et `enable_signup = false`, et ajouter à
  `scripts/verifier_production.sh` un écart si l'inscription libre est activée en production :
  c'est exactement le genre d'écart que le ticket 049 a appris à signaler.
- Couvrir le chemin réel : test SQL avec `user_metadata.email_verified = false`, et test avec un
  compte dont `email_confirmed_at` est nul, qui ne doit rien voir.

## Critères d'acceptation

- Un compte dont l'adresse n'est pas confirmée à la source ne voit aucune invitation et ne peut en
  accepter aucune par identifiant, quelles que soient ses métadonnées.
- La vérification de production signale une inscription libre activée.
- Tests de base et de règles de sécurité verts, sous identité.
