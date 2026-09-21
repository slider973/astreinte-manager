# 032 — Build web PWA et déploiement

- **Épopée** : E9 Release
- **Priorité** : P0
- **Dépend de** : 001
- **Branche** : `feat/032-web-pwa-deploy`
- **PR** : https://github.com/slider973/astreinte-manager/pull/35
- **Statut** : terminé le 2026-09-21 (PR créée)

## Contexte
La PWA est le canal principal : ce ticket se fait dès le jalon 2, juste après la connexion, pour
tester chaque écran suivant sur téléphone avec la PWA installée.

## À faire
- `flutter build web` avec CanvasKit, manifeste PWA complété (nom, icônes, couleurs, `display: standalone`), service worker par défaut vérifié.
- Écran de chargement HTML natif (avant Flutter) avec logo, pour masquer le temps de premier chargement.
- Déploiement sur Vercel ou Cloudflare Pages avec domaine, HTTPS, en-têtes de cache corrects pour `flutter_service_worker.js`.
- Workflow CI de déploiement automatique sur `main`.
- Page d'aide `/install` pour l'ajout à l'écran d'accueil.

## Critères d'acceptation
- Lighthouse PWA : installable.
- Temps de premier rendu mesuré sur 4G simulée, consigné dans le ticket.

## Mesures

Construction de production (`scripts/build_web.sh`), servie en local avec les en-têtes de
`vercel.json` et la compression à la volée des types texte, comme le fait le CDN. Chrome 153
sans interface, fenêtre 390 × 844, cache vidé à chaque tour, médiane de trois tours.

| Condition | Premier rendu (écran HTML) | Première image Flutter |
|---|---|---|
| Sans bridage (local) | **40 ms** | 382 ms |
| 4G rapide — 9 Mb/s, 85 ms de latence | **36 ms** | 1 721 ms |
| 4G lente — 1,6 Mb/s, 300 ms de latence | **28 ms** | 8 695 ms |

C'est la raison d'être de l'écran d'attente HTML : sur la 4G lente visée par le brief de design,
il y a **8,7 secondes** entre l'ouverture de la page et la première image de l'application. Ce
temps était jusqu'ici une page blanche ; il est désormais occupé par le squelette du premier
écran, dès la 28ᵉ milliseconde.

### Ce qui occupe ces 8,7 secondes

Ventilation d'un chargement à froid, en octets réellement transférés :

| Origine | Poids | Quoi |
|---|---|---|
| `www.gstatic.com` | **1 620 Ko** | CanvasKit (`canvaskit.wasm` + `canvaskit.js`) |
| `fonts.gstatic.com` | 62 Ko | Roboto, repli inconditionnel du moteur |
| l'hébergeur | 1 124 Ko | `main.dart.js`, compressé à la volée (3 638 Ko en clair) |
| l'hébergeur | 82 Ko | les cinq polices Atkinson, pré-compressées en brotli (184 Ko en clair) |

**Les deux premières lignes appartiennent au ticket 037** : 1,68 Mo sur 2,9 Mo viennent de chez
Google, pas de l'hébergeur, et c'est le premier poste du temps de chargement. Ce ticket a fait sa
part — les polices embarquées passent de 184 Ko à 82 Ko, exactement la cible annoncée par le 037.

### Ce qui n'a pas été mesuré ici

Lighthouse et le test d'installabilité demandent une URL en HTTPS : ils se font après la première
mise en ligne, avec la procédure du § 6 de `docs/DEPLOIEMENT.md`.
