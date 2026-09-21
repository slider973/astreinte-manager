# 042 — Réduire le coût d'une transition de route

- **Épopée** : E9 Release
- **Priorité** : P1
- **Dépend de** : 016
- **Branche** : `feat/042-transition-de-route`
- **PR** : https://github.com/slider973/astreinte-manager/pull/41
- **Statut** : terminé le 2026-09-21 (PR créée)

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

## Mesures

Construction `flutter build web --profile --no-web-resources-cdn` servie en local, base de
développement Supabase avec son seed, portée à **60 membres** pour la caserne A comme le veut le
critère du ticket 016. Chrome 153 sans interface, fenêtre 1440 × 900, session déjà ouverte,
médiane de cinq tours, un tour = un chargement neuf puis deux transitions.
Protocole rejouable : `scripts/mesurer_transition.mjs`.

Le bridage processeur ×4 et ×6 de Chrome tient lieu de téléphone : sans lui, cette machine ne
ressemble à rien de ce qu'un chef de centre a dans la poche.

### Les six cents millisecondes n'existent pas là où le ticket les plaçait

**Entre le changement de route et le départ de la première requête, il s'écoule 0 à 1 ms**, dans
les trois conditions, avant comme après ce ticket. La requête de l'écran part dans la même tâche
que le changement d'URL. Vérifié deux fois, au `fetch` intercepté dans la page et au journal
réseau de Chrome, sur la matrice comme sur l'écran des membres, et aussi sur une construction de
débogage (53 ms du clic à la requête, rien de plus).

Ce qui est vrai, en revanche, c'est que **la requête attendait toute l'image de la transition**.
Le profil processeur de la fenêtre clic → requête ne contient rien d'autre qu'une image Flutter :
`performRebuild` 22 %, `build` 11 %, mise en page, `drawPicture`, `submitFrame`. La raison est
structurelle et n'appartient à aucun écran, exactement comme le disait le ticket : sur le web, la
file de micro-tâches ne se vide qu'à la fin de la tâche du navigateur, et cette tâche contient la
construction, la mise en page et la peinture du nouvel écran. Un provider lu pendant cette
construction ne peut pas émettre avant qu'elle soit finie.

Sur cette machine, cette image coûte 28 ms sans bridage. Sur un téléphone d'astreinte, les 600 ms
mesurées au ticket 016 sont le même phénomène : l'image de la matrice, la plus lourde du produit,
peinte en entier pour ne montrer qu'un squelette.

### Avant / après

Du relâchement du clic au départ de la première requête de l'écran :

| Transition | Bridage | Avant | Après |
|---|---|---|---|
| accueil → matrice (`availability_matrix`) | aucun | 28 ms | **3 ms** |
| accueil → matrice | ×4 | 75 ms | **10 ms** |
| accueil → matrice | ×6 | 117 ms | **15 ms** |
| matrice → membres (`memberships`) | aucun | 27 ms | **2 ms** |
| matrice → membres | ×4 | 85 ms | **6 ms** |
| matrice → membres | ×6 | 128 ms | **9 ms** |

La requête part désormais **avant** le changement d'URL : −25 ms sans bridage, −83 ms bridé ×4,
−110 ms bridé ×6 pour la matrice. Le réseau travaille pendant que l'image se peint.

Le nombre de requêtes par transition est identique avant et après — deux pour la matrice, trois
pour les membres, comptées à chaque tour. C'est le contrôle qui compte ici : un préchargement mal
retenu fait partir chaque requête deux fois et se lit comme un gain.

### Ce qui reste, et qui ne se réduit pas ici

- **Le chargement à froid sur `/admin/planning`** (lien de notification, PWA rouverte) est
  inchangé : 1 990 ms → `periods`, réponse à 2 091, `availability_matrix` à 2 130, bridé ×4.
  La matrice ne peut pas demander un mois avant de savoir lequel ; le tour de réseau est
  incompressible côté application. Restent ~40 ms entre la réponse des mois et le départ de la
  requête : c'est Riverpod qui publie la valeur d'un provider asynchrone à la fin de l'image.
  Les supprimer demanderait de sortir la liste des mois de `FutureProvider` — hors de ce ticket.
- **La peinture de la matrice elle-même** : 0,74 s bridé ×4 et 1,1 s bridé ×6 de tâche continue
  après l'arrivée des données, pour 60 membres × 62 colonnes. C'est le vrai poste du budget de
  deux secondes, et il appartient à l'écran, pas à la transition.
- **Observé au passage, sans rapport avec ce ticket** : un chargement à froid sur
  `/#/admin/planning` a atterri deux fois sur l'accueil au lieu de la matrice, sur trois essais
  d'une même construction, avant comme après. La destination mémorisée se perd par moments. À
  ouvrir comme ticket à part.
