# 002 — Créer le projet Supabase et les migrations initiales

- **Épopée** : E0 Fondations
- **Priorité** : P0
- **Dépend de** : aucune
- **Branche** : `feat/002-supabase-migrations`
- **Statut** : en cours depuis 2026-09-20

## Contexte
Référence : `docs/SCHEMA.md`. Un projet Supabase unique, région Europe.

## À faire
- Créer le projet Supabase (région eu-central-1 ou eu-west), activer `pg_cron`, `pg_net`.
- Initialiser `supabase/` dans le dépôt (`supabase init`), config locale.
- Écrire les migrations 0001 à 0006 (enums, tables, index, triggers `updated_at`, `handle_new_user`).
- Script de seed pour le dev : 2 casernes, 1 admin et 8 membres chacune, périodes M+1 et M+2, disponibilités aléatoires.
- Génération des types Dart depuis le schéma (script documenté).

## Critères d'acceptation
- `supabase db reset` rejoue toutes les migrations sans erreur en local.
- Le seed produit des données cohérentes visibles dans Studio.
- Les migrations sont appliquées sur le projet distant dev. **Reporté** : le compte Supabase de
  l'organisation « Perso Jonathan » a des factures impayées, ce qui bloque la création de tout
  projet sur le compte. À reprendre sur un autre compte avec `supabase login`, `supabase link
  --project-ref <ref>` puis `supabase db push` (marche à suivre dans `supabase/README.md`).

## Hors périmètre
- RLS, vues et cron : tickets 008, 016, 022.
