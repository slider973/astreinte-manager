# Supabase — base de données locale

Référence du schéma : [`docs/SCHEMA.md`](../docs/SCHEMA.md). Les migrations l'implémentent
telles quelles ; tout écart est expliqué dans le commit et reporté dans le document.

## Prérequis

- CLI Supabase 2.117+ (`supabase --version`).
- Docker (Rancher Desktop ou Docker Desktop) en marche.

## Commandes

```sh
supabase start        # démarre Postgres, Auth, Studio, Inbucket… (première fois : long)
supabase status       # URL de l'API, clé anon, Studio (http://127.0.0.1:54323), Inbucket
supabase db reset     # rejoue toutes les migrations puis supabase/seed.sql
supabase db lint      # vérifie les fonctions et les tables sans RLS
supabase stop         # arrête les conteneurs (les données locales sont perdues au reset)
```

Studio : <http://127.0.0.1:54323>. Emails de test (OTP, liens magiques) :
<http://127.0.0.1:54324>.

`env/dev.json` contient l'URL locale et la clé anon locale, identiques sur toutes les
installations (voir `env/README.md`). La clé `service_role` n'est jamais versionnée.

## Migrations

Une migration par sujet, nommée `NNNN_sujet.sql` dans l'ordre de `docs/SCHEMA.md` section 10.
Une migration poussée sur `main` n'est jamais modifiée : on en crée une nouvelle.

| Fichier | Contenu |
|---|---|
| `0001_enums_and_stations.sql` | extensions (`pgcrypto`, `pg_net`, `pg_cron`), enums, `set_updated_at()`, `stations` |
| `0002_profiles_memberships_invitations.sql` | `profiles`, trigger `handle_new_user` sur `auth.users`, `memberships`, `invitations` |
| `0003_periods_availabilities_preferences.sql` | `periods`, `availabilities`, `availability_preferences` |
| `0004_schedules_shifts_assignments.sql` | `schedules`, `shifts`, `assignments` |
| `0005_notifications_push_tokens.sql` | `push_tokens`, `notifications` |
| `0006_subscriptions_audit_super_admins.sql` | `subscriptions`, `audit_log`, `super_admins` |
| `0007_functions_rls.sql` | `is_member`, `is_admin`, `is_super_admin`, `station_writable`, toutes les politiques RLS, trigger `assignments_member_transition` |

RLS est activé sur chaque table dès sa création et toutes les tables ont au moins une
politique depuis `0007`. Les politiques sont posées `to authenticated` : `anon` ne lit rien,
`service_role` et `postgres` ont `bypassrls`. Les vues arrivent au ticket 016
(`0008_views.sql`), le cron au ticket 022 (`0009_cron.sql`).

## Tests RLS

```sh
scripts/test_rls.sh        # joue supabase/tests/*.sql contre la base locale
DB_URL=postgresql://… scripts/test_rls.sh
```

`supabase/tests/rls_test.sql` simule un utilisateur connecté comme le fait PostgREST
(`set local role authenticated` + `set local request.jwt.claims`), vérifie le cloisonnement
entre les deux casernes du seed, les périodes verrouillées, la visibilité des attributions
selon le statut du planning, les transitions d'attribution et le passage en lecture seule
d'une caserne suspendue. Tout tourne dans une transaction annulée à la fin : la base reste
dans l'état du seed. Le script rend un code non nul au premier test rouge.

## Seed (`seed.sql`)

Données de développement, rejouées par `supabase db reset` et réutilisées par les tests
Flutter. Identifiants fixes.

| Élément | Caserne A | Caserne B |
|---|---|---|
| `stations.id` | `aaaaaaaa-0000-4000-8000-000000000001` | `bbbbbbbb-0000-4000-8000-000000000001` |
| Nom / slug | CIS Saint-Martin / `saint-martin` | CIS Val-de-Loue / `val-de-loue` |
| Admin | `admin@caserne-a.test` (`aaaaaaaa-…-000000000100`) | `admin@caserne-b.test` (`bbbbbbbb-…-000000000100`) |
| Membres | `membre1@caserne-a.test` … `membre8@caserne-a.test` (`aaaaaaaa-…-000000000101` … `…108`) | idem en `caserne-b.test` (`bbbbbbbb-…-000000000101` … `…108`) |
| Périodes | M+1 `aaaaaaaa-…-000000000201`, M+2 `aaaaaaaa-…-000000000202` | M+1 `bbbbbbbb-…-000000000201`, M+2 `bbbbbbbb-…-000000000202` |
| Abonnement | `trialing`, fin d'essai à J+30 | idem |

- Mot de passe de tous les comptes : `astreinte-dev`. La connexion par code OTP (ticket 005)
  fonctionne aussi : le code arrive dans Inbucket.
- Les comptes sont créés directement dans `auth.users` ; le trigger `handle_new_user` crée les
  profils avec `first_name` / `last_name` depuis `raw_user_meta_data`.
- Périodes M+1 et M+2 calculées depuis `now()`. `deadline_at` = jour
  `settings.availability_deadline_day` (15) du mois précédent à 23:59:59 (fuseau de la
  caserne). M+1 est `locked` si sa deadline est déjà passée (après le 15 du mois courant),
  M+2 est toujours `open`.
- Disponibilités : pour chaque membre (admins compris), chaque jour des deux périodes et
  chaque créneau, environ 50 % `available`, 10 % `absent`, 40 % non saisi. Tirage
  reproductible (`setseed(0.42)`, boucle à ordre fixe).
- Préférences (`availability_preferences`) pour `membre1` à `membre4` de chaque caserne, sur
  les deux périodes.
- Aucun planning, créneau ni attribution : ticket 017. Aucun super-admin : ticket 031.

## Types

La CLI ne génère que du TypeScript. `scripts/gen_types.sh` écrit
`supabase/types/database.types.ts` depuis la base locale (`supabase gen types typescript
--local --schema public`). Ce fichier sert :

- de source pour les Edge Functions (TypeScript, tickets 025 et suivants) ;
- de référence lisible pour écrire les modèles Dart.

Côté Flutter, les modèles sont écrits à la main dans `lib/features/<feature>/data/`
(un fichier par table, `fromJson` / `toJson` avec les noms de colonnes en `snake_case`
exactement comme dans `docs/SCHEMA.md`) et les enums Postgres de la section 1 dans
`lib/core/supabase/enums.dart`. Raisons de ne pas utiliser `supadart` :

- package communautaire jeune, sans garantie de suivi des versions de `supabase_flutter` ;
- classes générées difficiles à adapter (immutabilité, `copyWith`, valeurs par défaut,
  enums Dart) alors que le schéma ne compte que 15 tables ;
- la lecture des données passe par des RPC et des vues filtrées (tickets 016, 023) dont
  la forme ne correspond pas aux tables.

Régénérer les types TypeScript après chaque migration et relire le diff : c'est le moyen
le plus simple de repérer une colonne oubliée dans un modèle Dart.

## Projet distant

Non encore créé (voir ticket 002). Une fois le projet créé dans le dashboard (région
`eu-west-3` ou `eu-central-1`) :

```sh
supabase login
supabase link --project-ref <ref>
supabase db push          # applique les migrations
supabase secrets set …    # secrets des Edge Functions, jamais dans le dépôt
```
