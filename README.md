# Astreinte SP

Application de gestion des astreintes pour les centres de secours (sapeurs-pompiers).
Remplace un intranet web existant en supprimant les frictions de saisie des disponibilités
et de validation du planning.

## Documents

| Document | Contenu |
|---|---|
| [docs/PRD.md](docs/PRD.md) | Product Requirements Document : vision, rôles, fonctionnalités, règles métier, stack |
| [docs/SCHEMA.md](docs/SCHEMA.md) | Schéma Supabase : tables, enums, RLS, fonctions, vues, cron |
| [docs/WORKFLOWS.md](docs/WORKFLOWS.md) | Machines à états et séquences (planning, attribution, notifications) |
| [tickets/](tickets/README.md) | Tickets de développement, un par PR, regroupés par épopée |

## Stack

- Front : Flutter (iOS, Android, Web/PWA), une seule base de code
- Backend : Supabase (Postgres, Auth, Realtime, Edge Functions, pg_cron)
- Push : Firebase Cloud Messaging via `firebase_messaging` (iOS, Android, Web)
- Email : Resend
- Paiement : Stripe (abonnement par caserne)
- Hébergement web : Vercel ou Cloudflare Pages

## Règle de travail

Le code n'est pas encore écrit. Chaque ticket de `tickets/` donne lieu à une branche
`feat/<numéro>-<slug>` et une PR qui référence le ticket. Les tickets précisent leurs
dépendances : respecter l'ordre indiqué dans `tickets/README.md`.
