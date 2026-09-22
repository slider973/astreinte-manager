# 054 — Le déploiement automatique des fonctions ignore la carte d'imports

- **Épopée** : E9 Release
- **Priorité** : P0
- **Dépend de** : 049
- **Branche** : `feat/054-deploiement-fonctions-carte-imports`
- **PR** : —
- **Statut** : terminé le 2026-09-22 (PR créée)

## Contexte

Première exécution du workflow « Déploiement » livré par le ticket 049, sur la fusion `c220fe1`,
le 21 septembre 2026. Le travail `base` réussit, `verification` réussit, mais `fonctions` échoue :
les onze fonctions téléversent leurs fichiers puis sont refusées à l'empaquetage côté serveur,
onze fois le même refus.

```
Failed to bundle the function (reason: Relative import path "@supabase/supabase-js"
not prefixed with / or ./ or ../ … at _shared/supabase.ts:7:51)
```

Le specifier nu est résolu par `supabase/functions/deno.json` (`"@supabase/supabase-js":
"npm:@supabase/supabase-js@2.58.0"`). Le travail `fonctions` passe `--use-api`, qui empaquette à
distance à partir des seuls fichiers téléversés, et **le journal ne montre aucun envoi de
`deno.json`** : la carte d'imports n'atteint jamais le serveur. `supabase/config.toml` ne la
désigne pas non plus (`import_map` absent).

La CI ne pouvait pas l'attraper : `deno check` et `deno test` lisent le `deno.json` local et
passent. Le déploiement manuel du même jour, sans `--use-api`, empaquetait en local avec la carte,
et a réussi. `configuration` et `vercel` ont été sautés par dépendance ; la production n'a rien
perdu, les fonctions en ligne sont celles du déploiement manuel.

## À faire

- Faire arriver la carte d'imports au déploiement. Deux voies : retirer `--use-api` du travail
  `fonctions` pour revenir à l'empaquetage local, ou la désigner explicitement (`--import-map`, ou
  `import_map` dans `supabase/config.toml`, à vérifier dans l'aide du CLI installé). Retenir
  celle qui reproduit exactement ce que le déploiement manuel a fait, et écrire la raison dans le
  workflow.
- Éprouver **avant** la fusion : depuis la branche, lancer le déploiement des fonctions à la main
  avec la commande exacte du workflow, contre la production, et vérifier que les onze passent.
  Le jeton est celui du serveur MCP `supabase-project-b`, jamais écrit.
- Ajouter à `ci.yml` une étape qui aurait attrapé ce défaut : un empaquetage à blanc des fonctions
  tel que le déploiement le fait, ou à défaut une vérification que chaque specifier nu des
  fonctions est résolu par la carte que le déploiement envoie.
- `docs/DEPLOIEMENT.md § 8` : ajouter l'état « fonctions refusées à l'empaquetage » au tableau des
  symptômes, avec sa cause.

## Critères d'acceptation

- Le travail `fonctions` du workflow réussit sur `main` après fusion, les onze fonctions déployées.
- `configuration` et `vercel` ne sont plus sautés ; `vercel` échoue encore pour la seule raison
  du jeton de compte, documentée.
- Une CI de pull request échoue si une fonction importe un specifier que le déploiement ne saurait
  pas résoudre ; démonstration par régression volontaire dans la revue.
- Aucun secret dans le dépôt.
