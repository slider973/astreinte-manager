# 050 — L'écran super-admin annonce un envoi sans preuve

- **Épopée** : E9 Release
- **Priorité** : P2
- **Dépend de** : 048
- **Branche** : `feat/050-envoi-annonce-sans-preuve-superadmin`
- **PR** : https://github.com/slider973/astreinte-manager/pull/49
- **Statut** : terminé le 2026-09-22 (PR créée)

## Contexte

Relevé par la contre-revue du ticket 048, le 21 septembre 2026, et laissé hors de son périmètre
pour ne pas l'élargir une quatrième fois.

`lib/features/superadmin/domain/superadmin_providers.dart` annonce « Invitation envoyée à X. »
dès que le rapport ne compte aucun échec, sans regarder si le courriel est réellement sorti. C'est
le mensonge que le ticket 048 a corrigé à trois profondeurs sur les écrans de caserne : dans une
migration, dans un résumé, puis dans un libellé de statut. Le même, au même endroit logique, sur un
écran que le ticket n'avait pas ouvert.

Le contexte qui le rend visible est celui de la production du 21 septembre : aucun fournisseur de
courriel configuré, donc **aucun** courriel ne part, et tous les comptes rendus qui ne regardent
que les échecs annoncent un succès.

## À faire

- Conditionner l'annonce à ce que le courriel soit réellement parti, comme les écrans de caserne le
  font depuis le ticket 048. `ResultatInvitation.courrielEnvoye` porte déjà l'information.
- Réutiliser la règle de vérité du ticket 048 plutôt que d'en réécrire une. C'est sa duplication
  tacite qui a produit le même défaut trois fois : `AppStrings.invitationsResume` et
  `ResultatInvitation.libelle` existent pour ça.
- Brancher le garde-fou de test `test/support/promesse_envoi.dart` sur cet écran. Il refuse le mot
  qui promet un envoi dans tout ce qui est rendu, y compris ce qu'entend un lecteur d'écran.
- Chercher les autres endroits du même genre. Le ticket 048 en a trouvé trois en trois tours de
  revue ; il serait étonnant que celui-ci soit le dernier. Un balayage de ce qui affirme un envoi
  sans regarder son sort vaut mieux qu'un quatrième ticket dans un mois.

## Critères d'acceptation

- L'écran super-admin n'annonce pas un envoi quand aucun courriel n'est parti.
- Le garde-fou de test couvre cet écran, et il échoue si le défaut est réintroduit.
- Aucune règle de vérité n'est recopiée : les écrans partagent la même.
- `flutter analyze` sans avertissement, `flutter test` verts, `flutter build web` qui passe.
