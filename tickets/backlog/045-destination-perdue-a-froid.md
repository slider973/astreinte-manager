# 045 — Destination perdue au chargement à froid d'un écran d'administration

- **Épopée** : E6 Notifications
- **Priorité** : P1
- **Dépend de** : 024, 031
- **Branche** : `feat/045-destination-perdue-a-froid`

## Contexte
Observé pendant le ticket 042, de façon reproductible mais intermittente : ouvrir l'application
directement sur un écran d'administration, application fermée, atterrit parfois sur l'accueil.
Deux fois sur trois essais, avant comme après les corrections de ce ticket, donc sans rapport avec
elles.

Le mécanisme de mémorisation de la destination a été posé au ticket 024 puis durci au ticket 031,
où la reprise demande désormais son avis à la garde de rôle avant de rejouer la destination. Le
défaut est vraisemblablement une course entre cette garde, qui a besoin du rôle, et le chargement
des appartenances qui le fournit : la garde tranche avant de savoir.

C'est le même chemin que celui d'une notification touchée application fermée, donc le défaut touche
aussi les liens des notifications d'administration, comme le rapport des retardataires.

## À faire
- Reproduire de façon fiable, en bridant le réseau si nécessaire pour élargir la fenêtre de course.
- Faire attendre la reprise que le rôle soit réellement connu, plutôt que de trancher sur un état
  intermédiaire.
- Couvrir par un test qui échoue sans le correctif.

## Critères d'acceptation
- Ouvrir une adresse d'administration application fermée mène à cet écran, en dix essais sur dix.
- Le même contrôle pour une destination de membre.
