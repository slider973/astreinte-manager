# 032 — Build web PWA et déploiement

- **Épopée** : E9 Release
- **Priorité** : P0
- **Dépend de** : 001, 024
- **Branche** : `feat/032-web-pwa-deploy`

## À faire
- `flutter build web` avec CanvasKit, manifeste PWA complété (nom, icônes, couleurs, `display: standalone`), service worker par défaut vérifié.
- Écran de chargement HTML natif (avant Flutter) avec logo, pour masquer le temps de premier chargement.
- Déploiement sur Vercel ou Cloudflare Pages avec domaine, HTTPS, en-têtes de cache corrects pour `flutter_service_worker.js`.
- Workflow CI de déploiement automatique sur `main`.
- Page d'aide `/install` pour l'ajout à l'écran d'accueil.

## Critères d'acceptation
- Lighthouse PWA : installable.
- Temps de premier rendu mesuré sur 4G simulée, consigné dans le ticket.
