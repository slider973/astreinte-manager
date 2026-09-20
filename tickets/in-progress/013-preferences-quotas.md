# 013 — Préférences de charge par mois

- **Épopée** : E3 Disponibilités
- **Priorité** : P0
- **Dépend de** : 011
- **Branche** : `feat/013-preferences-quotas`
- **Statut** : en cours depuis 2026-09-20

## Contexte
C'est la fonctionnalité qui règle la friction principale : distinguer « disponible » de « veut être planifié ».

## À faire
- Section sous la grille : « Ce mois, je veux faire au maximum » : astreintes (nombre ou illimité), weekends (nombre ou illimité), commentaire libre.
- Valeurs par défaut reprises du mois précédent, sinon illimité.
- Texte pédagogique : « Cocher tous vos weekends ne vous engage pas à tous les faire. Indiquez ici combien vous en voulez réellement. »
- Écriture dans `availability_preferences` par upsert.

## Critères d'acceptation
- Un membre qui coche 4 weekends et met « 1 weekend max » voit son quota affiché « 1 weekend » côté admin.
- Le commentaire est visible par l'admin dans la matrice.
