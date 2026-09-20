# 042 — Réduire le coût d'une transition de route

- **Épopée** : E9 Release
- **Priorité** : P1
- **Dépend de** : 016
- **Branche** : `feat/042-transition-de-route`

## Contexte
Mesuré au ticket 016, en mode profil dans un vrai navigateur : il s'écoule environ six cents
millisecondes entre le changement de route et le départ de la première requête de l'écran. Ce coût
n'appartient pas à l'écran de la matrice, il a été retrouvé identique sur l'écran des membres.

Sur le budget de deux secondes fixé à la matrice, c'est près d'un tiers dépensé avant que la
moindre donnée ne soit demandée.

## À faire
- Profiler une transition de route et identifier ce qui occupe ces six cents millisecondes :
  reconstruction de l'arbre, providers réévalués, travail de mise en page au premier rendu.
- Lancer la requête de l'écran sans attendre la fin de la transition quand c'est possible.
- Vérifier le gain sur la matrice et sur un écran simple, en mode profil, dans un vrai navigateur.

## Critères d'acceptation
- Le délai entre le changement de route et le départ de la première requête est mesuré avant et
  après, sur les mêmes conditions, et la mesure figure dans le compte rendu.
