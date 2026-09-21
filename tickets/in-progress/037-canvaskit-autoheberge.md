# 037 — Supprimer la dépendance à fonts.gstatic.com au démarrage

- **Épopée** : E9 Release
- **Priorité** : P1
- **Dépend de** : 004, 032
- **Branche** : `feat/037-canvaskit-autoheberge`
- **Statut** : en cours depuis 2026-09-21

## Contexte
Découvert pendant le ticket 004 : même avec les polices Atkinson correctement embarquées, le build
web télécharge Roboto depuis `fonts.gstatic.com` (63 Ko) à chaque démarrage. C'est le repli
inconditionnel de CanvasKit, pas un réglage de l'application. Deux problèmes : une requête vers un
CDN Google à chaque ouverture alors que le PRD porte un volet RGPD (section 8, hébergement
européen), et 63 Ko inutiles sur la 4G rurale visée par le brief de design.

## À faire
- Supprimer le téléchargement de Roboto : `fontFallbackBaseUrl` du chargeur Flutter web pointé sur
  un chemin auto-hébergé, ou auto-hébergement complet de CanvasKit (`--web-renderer` et
  `flutter build web --pwa-strategy`), selon ce qui fonctionne avec la version de Flutter du projet.
- Vérifier au journal réseau qu'aucune requête ne sort vers `gstatic.com`, `googleapis.com` ni
  aucun domaine tiers au démarrage ni pendant la navigation.
- Servir `assets/fonts/*.ttf` avec `Content-Encoding: br` : 83 Ko au lieu de 184 Ko. Le WOFF2 est
  exclu, Flutter web ne le décode pas (mesuré au ticket 004, voir `assets/fonts/README.md`).
- Documenter la configuration d'en-têtes attendue de l'hébergeur dans le README de déploiement.

## Critères d'acceptation
- Aucune requête vers un domaine tiers au chargement de la PWA, vérifié au journal réseau.
- Les polices Atkinson s'affichent bien, aucun repli sur Roboto.
- Le poids transféré des polices est inférieur à 100 Ko avec la compression de l'hébergeur.
