# 041 — Envoyer les rappels à une heure décente dans chaque fuseau

- **Épopée** : E6 Notifications
- **Priorité** : P1
- **Dépend de** : 015
- **Branche** : `feat/041-heure-locale-rappels`
- **Statut** : en cours depuis 2026-09-21

## Contexte
Relevé pendant le ticket 015. La tâche de rappel tourne à neuf heures, heure du serveur. Le jour
est juste dans chaque fuseau, mais pas l'heure : une caserne de Guadeloupe reçoit son rappel à cinq
heures du matin, une de Wallis à vingt et une heures. Pour des bénévoles qu'on réveille ou qu'on
dérange le soir, c'est le genre de détail qui fait désinstaller une application.

Le schéma fixe aujourd'hui « tous les jours neuf heures », et le ticket 015 s'y est tenu.

## À faire
- Passer la tâche en exécution horaire et ne retenir que les casernes dont l'heure locale
  correspond à l'heure visée. La clé de dédoublonnage absorbe déjà les tirs supplémentaires, il n'y
  a donc aucun risque de doublon.
- Rendre l'heure visée configurable dans les paramètres de la caserne, ou la fixer à une valeur
  raisonnable et la documenter.
- Appliquer la même règle aux autres tâches qui écrivent aux membres, en particulier les relances
  du ticket 022.

## Critères d'acceptation
- Un test vérifie qu'une caserne très décalée reçoit son rappel à l'heure locale visée, et une
  seule fois.
