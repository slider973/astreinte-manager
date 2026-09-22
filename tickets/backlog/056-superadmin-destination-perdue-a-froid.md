# 056 — L'éditeur sans caserne perd sa destination au démarrage à froid

- **Épopée** : E9 Release
- **Priorité** : P2
- **Dépend de** : 045, 053
- **Branche** : `feat/056-superadmin-destination-perdue-a-froid`
- **PR** : —
- **Statut** : à faire

## Contexte

Relevé en écrivant les tests du ticket 053, le 22 septembre 2026. Un éditeur qui n'est membre
d'aucune caserne, le cas nominal du brief `design/031-super-admin.md`, ouvre `/superadmin`
application fermée et finit sur « Aucune caserne ».

La cause est structurelle. Dans `lib/core/router/app_router.dart`, la reprise de la destination
mémorisée (tickets 024, 031, 039, 045) est gardée par `if (etat == EtatAuth.connecte)`. Un
éditeur sans caserne est en `EtatAuth.sansCaserne`. Sa destination de lancement n'est donc jamais
rejouée, `garde('/demarrage')` l'envoie sur « Aucune caserne », et la destination reste mémorisée
sans jamais être consommée.

Le ticket 045 avait traité la course entre la garde de rôle et le chargement des appartenances
pour les écrans d'administration de caserne. Il n'a pas couvert l'état sans caserne, parce qu'à
l'époque personne n'y avait de destination légitime. Depuis le 031, l'éditeur en a une.

## À faire

- Rejouer la destination mémorisée aussi en `EtatAuth.sansCaserne`, mais uniquement vers les
  routes que cet état a le droit d'atteindre : `/superadmin` pour un éditeur, et rien d'autre. Un
  compte sans caserne qui aurait mémorisé `/admin/membres` ne doit pas y être rejoué, ni voir sa
  destination survivre.
- Consommer la destination dans tous les cas, y compris quand elle est refusée : une destination
  jamais consommée est une destination qui ressort à la session suivante, ce que le 053 a dû
  vérifier à la main.
- Couvrir par un test qui échoue sans le correctif : éditeur sans caserne, démarrage à froid sur
  `/superadmin`, danse de la porte et du rafraîchissement du 045, arrivée sur `/superadmin`.

## Critères d'acceptation

- Un éditeur sans caserne qui ouvre `/superadmin` à froid y arrive.
- Un compte sans caserne qui n'est pas éditeur et qui a mémorisé une route d'administration
  arrive sur « Aucune caserne », et la destination est oubliée.
- Le test ci-dessus échoue sans le correctif, démonstration en revue.
- `flutter analyze` sans avertissement, `flutter test` verts, `flutter build web` qui passe.
