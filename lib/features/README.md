# lib/features

Une fonctionnalité par dossier, découpée en trois couches :

```
features/<feature>/
  data/          repositories Supabase (une classe par table ou RPC), DTO
  domain/        modèles, règles métier, providers Riverpod avec logique
  presentation/  écrans (*_screen.dart) et widgets propres à la fonctionnalité
```

Règles : pas de logique métier dans les widgets ; les types viennent de `docs/SCHEMA.md` ;
une fonctionnalité n'importe jamais une autre fonctionnalité (passer par `lib/core/`).

Ce que les fonctionnalités partagent vit dans `lib/core/` : le système de design
(`core/theme`, `core/widgets`), les textes (`core/l10n`), le routeur (`core/router`), le
client Supabase (`core/supabase`) et la session (`core/session` — qui est connecté, dans
quelle caserne, avec quel rôle).

| Dossier | Ticket | Contenu |
|---|---|---|
| `auth/` | 005 | Les écrans de connexion : adresse e-mail, code à six chiffres, compte sans caserne. L'état de session, lui, est transverse et vit dans `core/session`. |
| `accueil/` | 005 | L'accueil d'après-connexion. Remplacé par les écrans métier aux tickets suivants. |
| `demarrage/` | 005 | Le temps de restaurer la session, et l'écran « application non configurée ». |
| `dev/` | 004 | Le catalogue des composants, absent des builds de production. |
