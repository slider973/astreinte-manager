# 046 — Servir les routes sans dièse, pour que la connexion par lien fonctionne

- **Épopée** : E1 Authentification
- **Priorité** : P0 — bloquant en production
- **Dépend de** : 032
- **Branche** : `feat/046-strategie-url-sans-diese`
- **Statut** : en cours depuis 2026-09-21

## Contexte
Découvert à la première connexion réelle sur le site déployé. L'application sert ses routes après
un dièse, et le fournisseur d'authentification renvoie ses jetons dans le fragment de l'adresse,
c'est-à-dire exactement au même endroit. Le routeur lit alors les jetons comme une route et rend
une page introuvable. Vérifié : le fournisseur écrase le fragment quelle que soit l'adresse de
retour demandée, il n'existe donc aucun contournement par la configuration.

Conséquence : **toute connexion par lien échoue en production**, pour tout le monde. C'est le seul
mode disponible tant que le service d'envoi de courriels n'affiche pas le code à six chiffres, et
c'est aussi le mode qu'utilise le lien d'invitation.

## À faire
- Passer l'application en adresses sans dièse.
- Reprendre tout ce qui construit une adresse en supposant le dièse : le chemin du lien
  d'invitation dans les fonctions serveur, la construction de la cible dans le service worker des
  notifications, la redirection de la page d'aide à l'installation dans la configuration
  d'hébergement, et tout ce que les tickets 024, 026 et 032 ont écrit sur ce modèle.
- Vérifier que la réécriture vers la page d'accueil couvre bien toutes les routes profondes chez
  l'hébergeur, sans quoi un rechargement sur une route donnerait une page introuvable.
- Vérifier la connexion par lien de bout en bout sur le site déployé, et le lien d'invitation.

## Critères d'acceptation
- Un lien de connexion ouvre l'application authentifiée sur le site en ligne.
- Un rechargement sur une route profonde fonctionne.
- Le lien d'invitation mène à l'écran d'invitation.
