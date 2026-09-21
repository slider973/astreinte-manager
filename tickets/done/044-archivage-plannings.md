# 044 — Archiver réellement les plannings des mois passés

- **Épopée** : E9 Release
- **Priorité** : P1
- **Dépend de** : 019
- **Branche** : `feat/044-archivage-plannings`
- **Statut** : terminé le 2026-09-21 (PR créée)

## Contexte
Relevé au ticket 035. `docs/WORKFLOWS.md` section 7 annonce qu'un planning est archivé le premier
du mois suivant, et la transition vers l'état archivé est bien permise par les gardes posées au
ticket 019. Mais aucune tâche planifiée ne l'appelle : les plannings restent indéfiniment publiés
ou validés.

Conséquence côté lecture : la revue du ticket 008 avait déjà noté qu'un planning archivé redevient
invisible pour un membre, ce qui n'a jamais été observé puisque rien n'archive. Il faut trancher ce
point en même temps.

## À faire
- Planifier l'archivage mensuel, en suivant les conventions des tâches existantes, avec un
  paramètre de date de référence pour la testabilité.
- Décider et documenter ce qu'un membre voit d'un planning archivé. Le produit conserve
  l'historique, donc le rendre invisible mérite une décision explicite plutôt qu'un effet de bord.
- Vérifier l'effet sur les écrans qui listent les mois, notamment le sélecteur du planning de la
  caserne, qui exclut aujourd'hui les plannings archivés.

## Critères d'acceptation
- Un planning d'un mois passé est archivé par la tâche, testée avec une date de référence.
- Ce qu'un membre voit d'un planning archivé est décidé, documenté et testé.
