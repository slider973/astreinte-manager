# 043 — Purger réellement les anciennes notifications

- **Épopée** : E9 Release
- **Priorité** : P0
- **Dépend de** : 034
- **Branche** : `feat/043-purge-notifications`

## Contexte
Relevé en écrivant le registre des traitements du ticket 034. La tâche de purge des notifications
lues est décrite dans `docs/SCHEMA.md` section 8 avec une conservation de quatre-vingt-dix jours,
mais elle n'a jamais été planifiée : aucune ligne dans la table des tâches. Les notifications sont
donc conservées sans limite, ce que le registre annonce pourtant comme borné.

Une durée de conservation affichée mais non appliquée est un manquement, et c'est le genre d'écart
qu'un contrôle relève immédiatement.

## À faire
- Planifier la purge, en suivant les conventions des tâches existantes, notamment le paramètre de
  date de référence qui la rend testable.
- Vérifier les autres durées annoncées dans `docs/RGPD.md` et s'assurer que chacune est réellement
  appliquée, ou corriger le document si la durée retenue est différente.
- Décider du sort du journal d'audit, dont la durée de conservation est aujourd'hui marquée à
  compléter dans le registre.

## Critères d'acceptation
- La purge est planifiée et testée avec une date de référence.
- Chaque durée annoncée dans le registre correspond à un mécanisme qui l'applique.
