# 039 — Conserver la destination d'un lien profond au démarrage à froid

- **Épopée** : E6 Notifications
- **Priorité** : P0
- **Dépend de** : 005, 011
- **Branche** : `feat/039-deep-links-demarrage-froid`

## Contexte
Relevé pendant le ticket 011 : ouvrir l'application sur une URL portant une destination précise
perd cette destination quand la session doit d'abord être restaurée. L'écran de restauration
réécrit l'URL et la chaîne de requête disparaît. Le retour navigateur en cours de session
fonctionne, seul le démarrage à froid est touché.

C'est bloquant pour les notifications : `docs/WORKFLOWS.md` section 8 prévoit qu'une notification
ouvre l'écran des propositions, un planning ou un mois précis. Un pompier qui touche une
notification alors que l'application est fermée arriverait sur l'accueil, ce qui casse la boucle
de validation du planning, mécanisme central du produit.

## À faire
- Mémoriser la destination initiale complète, chemin et paramètres, avant la redirection vers la
  restauration de session ou la connexion, puis y revenir une fois la session prête.
- Couvrir les quatre destinations de `docs/WORKFLOWS.md` section 8, plus le mois de la grille de
  saisie et le lien d'invitation.
- Traiter le cas où l'utilisateur n'a pas le droit d'accéder à la destination mémorisée.

## Critères d'acceptation
- Ouvrir une URL profonde sur une application fermée mène à la bonne destination après connexion.
- Un test couvre chaque destination listée.
