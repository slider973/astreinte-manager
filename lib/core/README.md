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
| `reseau/` | L'état du réseau (`navigator.onLine` et ses événements), derrière un import conditionnel. Sert à distinguer « ça n'a pas pu partir » de « ça a été refusé » | 011 |
| `caserne/` | L'état d'abonnement (`station_access`), relu au retour au premier plan, au retour de Stripe et après un refus `42501` | 030, 070 |
| `fraicheur/` | Le coordinateur unique des relectures : ouverture d'un écran, retour au premier plan, retour du réseau, événement. Délai minimal de 10 s, rien sous une écriture, jamais en vidant l'écran. Aucun stockage | 070 |
