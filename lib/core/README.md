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
