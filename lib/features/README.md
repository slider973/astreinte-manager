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

`hello/` est l'exemple minimal du ticket 001 ; il disparaîtra avec le premier écran métier.
