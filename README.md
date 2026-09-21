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
| [docs/FIREBASE.md](docs/FIREBASE.md) | Ce que le propriétaire doit créer chez Firebase pour activer les notifications, et comment le vérifier |
| [docs/DEPLOIEMENT.md](docs/DEPLOIEMENT.md) | Mise en ligne de la PWA : projet Vercel, secrets GitHub, domaine, vérifications |
| [tickets/](tickets/README.md) | Tickets de développement, un par PR, regroupés par épopée |

## Stack

- Front : Flutter (iOS, Android, Web/PWA), une seule base de code
- Backend : Supabase (Postgres, Auth, Realtime, Edge Functions, pg_cron)
- Push : Firebase Cloud Messaging via `firebase_messaging` (iOS, Android, Web)
- Email : Resend
- Paiement : Stripe (abonnement par caserne)
- Hébergement web : Vercel ou Cloudflare Pages

## Démarrage

[![CI](https://github.com/slider973/astreinte-manager/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/slider973/astreinte-manager/actions/workflows/ci.yml)

Chaque PR vers `main` déclenche [la CI](.github/workflows/ci.yml) : analyse, tests et build web
d'un côté, rejeu des migrations, tests RLS et lint du schéma de l'autre.

Prérequis : Flutter 3.38+ (Dart 3.10+), Xcode 16 pour iOS, Android Studio ou SDK Android pour
Android, Chrome pour le web. Vérifier avec `flutter doctor -v`.

```sh
flutter pub get
flutter analyze          # doit être vierge
flutter test             # doit être vert
```

### Variables d'environnement

L'app lit sa configuration à la compilation via `--dart-define` (voir `lib/core/env.dart` et
[env/README.md](env/README.md)) : `APP_ENV`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
et les cinq variables `FIREBASE_*`. Le fichier `env/dev.json` est versionné (Supabase local, aucune
clé sensible) ; `env/prod.json` se crée à partir de `env/prod.json.example` et n'est jamais commité.

Les variables `FIREBASE_*` sont **facultatives** : laissées vides, l'application démarre et
fonctionne normalement, sans notifications, et le dit dans l'écran « Profil ». La marche à suivre
pour les obtenir est dans [docs/FIREBASE.md](docs/FIREBASE.md).

### Lancer sur chaque cible

```sh
flutter devices                                  # lister les cibles
flutter run -d chrome     --dart-define-from-file=env/dev.json
flutter run -d "iPhone 16 Pro" --dart-define-from-file=env/dev.json   # simulateur iOS (open -a Simulator)
flutter emulators --launch Pixel_3_API_32        # puis :
flutter run -d emulator-5554 --dart-define-from-file=env/dev.json     # émulateur Android
```

### Construire

```sh
scripts/build_web.sh env/prod.json                                  # la PWA, prête à servir
flutter build web --release --dart-define-from-file=env/prod.json   # la même, sans la compression des polices
flutter build ipa           --dart-define-from-file=env/prod.json
flutter build appbundle     --dart-define-from-file=env/prod.json
```

`scripts/build_web.sh` ajoute au build web la compression brotli des polices embarquées (184 Ko →
83 Ko). Elle n'est lisible qu'avec l'en-tête `Content-Encoding: br` que pose `vercel.json` : servir
`build/web` avec un serveur statique ordinaire donne des polices illisibles et un repli silencieux
sur Roboto. Pour regarder le résultat avec les en-têtes réels : `scripts/servir_web.py`, puis
<http://127.0.0.1:8099>.

### Mettre en ligne

Tout commit fusionné dans `main` part en production après une CI verte
([.github/workflows/deploy.yml](.github/workflows/deploy.yml)). Les secrets à poser et les
vérifications à faire sont dans [docs/DEPLOIEMENT.md](docs/DEPLOIEMENT.md).

### Architecture

```
lib/
  main.dart                 ProviderScope + AstreinteApp
  app.dart                  MaterialApp.router (thème, go_router)
  core/                     transverse : env, l10n, router, theme, supabase, notifications, widgets
  features/<feature>/       data / domain / presentation
```

Identifiant d'app : `fr.astreintesp.app` (Android `applicationId`, iOS bundle id). État avec
Riverpod 3 sans génération de code pour l'instant (`riverpod_generator` sera ajouté quand un
ticket en aura besoin, à partir du 004). Navigation avec go_router, deep links activés côté
plateformes (`flutter_deeplinking_enabled`, `FlutterDeepLinkingEnabled`) ; les domaines
associés seront déclarés avec les notifications (tickets 024 et 026).

## Règle de travail

Chaque ticket de `tickets/` donne lieu à une branche
`feat/<numéro>-<slug>` et une PR qui référence le ticket. Les tickets précisent leurs
dépendances : respecter l'ordre indiqué dans `tickets/README.md`.
