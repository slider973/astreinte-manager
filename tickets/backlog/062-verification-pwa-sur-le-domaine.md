# 062 — La vérification de la PWA vise un alias protégé au lieu du domaine

- **Épopée** : E9 Release
- **Priorité** : P0
- **Dépend de** : 060
- **Branche** : `feat/062-verification-pwa-sur-le-domaine`
- **PR** : —
- **Statut** : à faire

## Contexte

Signalé par le propriétaire le 22 septembre 2026 : « ça a encore failed la CI/CD ». Run
« Déploiement » 35768686568 sur `7253360`. Quatre travaux verts, base, fonctions, configuration,
vérification d'écart. Le travail « PWA, construire et mettre en ligne » a bien construit et mis en
ligne, `READY` obtenu, puis a échoué à l'étape « Vérifier les en-têtes servis ».

La cause n'est pas la PWA, c'est l'adresse vérifiée. L'étape a interrogé
`https://astreinte-manager-slider973s-projects.vercel.app`, l'alias d'équipe de Vercel, qui est
derrière la protection de déploiement : il répond 302 vers `vercel.com/sso-api`, puis 307 vers une
page de connexion Vercel. Les en-têtes lus sont ceux de vercel.com, pas ceux de l'application. Le
run précédent, sur `4e7fb77`, avait vérifié `https://astreinte.staticflow.ch` et était passé : le
choix de l'adresse par `scripts/deployer_pwa.py` (`adresse_publique`, qui écarte les alias
`*.vercel.app`) n'est pas déterministe selon l'ordre des alias que l'API rend, et la revue du 060
avait noté ce hasard sans le bloquer.

La production, elle, est saine : le domaine sert la version déployée, avec les en-têtes de
sécurité et les réécritures.

## À faire

- La vérification après mise en ligne vise **toujours** le domaine de production,
  `https://astreinte.staticflow.ch`, jamais un alias `vercel.app`. Le domaine est une constante
  de configuration lue par le workflow (variable d'environnement du workflow ou `vercel.json`),
  pas un choix fait à l'exécution parmi les alias.
- `adresse_publique` du script rend cette adresse quand elle figure dans les alias du déploiement,
  et échoue bruyamment si elle n'y figure pas : un déploiement `READY` dont l'alias de production
  n'est pas posé n'est pas une mise en ligne réussie.
- Entre `READY` et la bascule de l'alias, quelques secondes peuvent s'écouler : les deux étapes de
  vérification réessaient jusqu'à trois fois, espacées de cinq secondes, avant de conclure.
- Éprouver avant fusion, à la main depuis la branche, comme au 060.

## Critères d'acceptation

- Le run « Déploiement » sur `main` après fusion est vert sur les cinq travaux.
- Les deux étapes de vérification interrogent le domaine de production, visible dans leur journal.
- Un déploiement dont l'alias de production manque fait échouer le travail avec un message clair.
- Aucun secret dans le dépôt.
