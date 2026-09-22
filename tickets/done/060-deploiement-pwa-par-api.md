# 060 — Mettre la PWA en ligne par l'API Vercel, avec le jeton de projet

- **Épopée** : E9 Release
- **Priorité** : P0
- **Dépend de** : 054
- **Branche** : `feat/060-deploiement-pwa-par-api`
- **PR** : https://github.com/slider973/astreinte-manager/pull/52
- **Statut** : terminé le 2026-09-22 (PR créée)

## Contexte

Depuis le ticket 032, le travail « PWA, construire et mettre en ligne » du workflow de
déploiement passe par la ligne de commande Vercel (`vercel pull`, `vercel build`,
`vercel deploy --prebuilt`). Il échoue à chaque exécution depuis le 21 septembre 2026 avec
« Not able to load user because of unexpected error: User not found. (404) ».

La cause est la nature du jeton. Le propriétaire a créé deux jetons depuis la page des jetons de
son compte, avec le projet `astreinte-manager` comme portée : Vercel les préfixe `vcp_`, ce sont
des jetons **de projet**. Ils autorisent l'API de déploiement mais n'ont pas de contexte
utilisateur, et la ligne de commande commence par charger l'utilisateur. Le résultat est le même
quel que soit le jeton de ce type, et le demander une troisième fois n'a pas de sens.

Pendant ce temps, les quatre mises en ligne manuelles des 21 et 22 septembre ont toutes réussi par
l'**API** Vercel avec ce même jeton : téléversement des fichiers de `build/web` par leur empreinte
(`POST /v2/files`), puis création d'un déploiement de production (`POST /v13/deployments`) avec
la liste des fichiers, `target: production`, sans construction côté Vercel. Le script vit hors
dépôt, dans le brouillon de session (`deployer.py`) ; il est court, sans dépendance, et il marche.

## À faire

- Remplacer les trois appels à la ligne de commande Vercel du travail `vercel` par un script du
  dépôt, `scripts/deployer_pwa.py` ou équivalent, qui fait exactement ce que le script manuel a
  fait : empreintes SHA-1, téléversement par lot avec reprise sur erreur passagère, création du
  déploiement avec `teamId` et `projectId`, attente de l'état `READY`, échec bruyant sinon.
- Garder la construction sur l'exécuteur avec `--dart-define-from-file`, inchangée, et les
  en-têtes et réécritures de `vercel.json` : vérifier que l'API les applique pour un déploiement
  sans construction (le déploiement manuel les a conservés, le confirmer par une lecture des
  en-têtes servis, comme le fait déjà l'étape « Vérifier les en-têtes servis »).
- Vérifier après coup, dans le workflow : HTTP 200 sur le domaine, et empreinte de
  `main.dart.js` servi égale à celle du build, comme le fait la procédure manuelle.
- `docs/DEPLOIEMENT.md § 2 et 3` : le jeton attendu est un jeton de projet, préfixe `vcp_`, créé
  depuis la page des jetons du compte avec le projet comme portée, et c'est tout. Retirer la
  consigne du jeton de compte, qui a fait perdre une journée.
- Éprouver avant fusion par un `workflow_dispatch` sur la branche, ce que le 049 a restreint à
  `main` : soit lever temporairement la garde sur cette branche avec la raison écrite, soit
  éprouver le script à la main depuis la branche avec les mêmes variables que le workflow.

## Critères d'acceptation

- Le travail `vercel` réussit sur `main` avec le jeton `vcp_` déjà posé, sans intervention.
- La PWA servie après le déploiement automatique est celle du commit fusionné, empreinte à
  l'appui.
- Les en-têtes et réécritures de `vercel.json` sont servis après un déploiement par l'API.
- Aucun secret dans le dépôt ; `docs/DEPLOIEMENT.md` décrit le jeton attendu sans ambiguïté.
