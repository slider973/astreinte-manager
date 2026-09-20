# lib/core

Code transverse, sans logique métier. Une fonctionnalité ne doit jamais dépendre d'une
autre fonctionnalité : ce qui est partagé remonte ici.

| Dossier | Contenu | Ticket |
|---|---|---|
| `env.dart` | Lecture des `--dart-define` (`Env`, `envProvider`) | 001 |
| `l10n/` | Textes de l'app centralisés (`AppStrings`) | 001 |
| `router/` | Routes go_router, deep links | 001 |
| `theme/` | Thème Material 3, palette, typographie | 004 |
| `supabase/` | Initialisation du client, providers d'accès | 002 |
| `notifications/` | Firebase Messaging, tokens, deep links | 024 |
| `widgets/` | Composants réutilisables (`SlotChip`, `StatusBadge`, …) | 004 |
| `session/` | Qui est connecté, dans quelle caserne, avec quel rôle | 005 |
| `preferences/` | Les repères locaux vus une fois (guide, aide à l'installation) | 006 |
| `plateforme/` | Navigateur et mode autonome de la PWA, derrière un import conditionnel | 006 |
