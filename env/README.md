# Environnements

Les variables sont injectées à la compilation avec `--dart-define-from-file` et lues
dans `lib/core/env.dart` via `String.fromEnvironment`.

| Fichier | Versionné | Usage |
|---|---|---|
| `dev.json` | oui | Supabase local (`supabase start`), aucune clé sensible. Compléter `SUPABASE_ANON_KEY` avec la clé anon locale affichée par `supabase status` (elle est identique sur toutes les installations locales). |
| `prod.json.example` | oui | Modèle à copier en `prod.json`. |
| `prod.json` | non (`.gitignore`) | Valeurs réelles de production, jamais commitées. |

Variables :

| Clé | Rôle |
|---|---|
| `APP_ENV` | `dev` ou `prod` (défaut : `dev`) |
| `SUPABASE_URL` | URL du projet Supabase |
| `SUPABASE_ANON_KEY` | Clé anon (publique, protégée par RLS). Jamais la clé service. |
| `FIREBASE_PROJECT_ID` | Identifiant du projet Firebase |
| `FIREBASE_API_KEY` | `apiKey` de l'application **web** Firebase |
| `FIREBASE_APP_ID` | `appId` de l'application **web** Firebase |
| `FIREBASE_MESSAGING_SENDER_ID` | `messagingSenderId` du projet |
| `FIREBASE_VAPID_KEY` | Clé publique VAPID (« certificats push web ») |

Les cinq variables `FIREBASE_*` sont toutes nécessaires ensemble : laissées vides, l'application
démarre normalement **sans notifications**, et le dit à l'utilisateur. Aucune n'est un secret ;
la procédure complète pour les obtenir est dans `docs/FIREBASE.md`.

Exemple :

```sh
flutter run -d chrome --dart-define-from-file=env/dev.json
flutter build web --release --dart-define-from-file=env/prod.json
```
