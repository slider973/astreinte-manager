# 048 — Finition de l'écran d'import des membres

- **Épopée** : E2 Casernes
- **Priorité** : P1
- **Dépend de** : 047
- **Branche** : `feat/048-finition-import-membres`
- **PR** : —
- **Statut** : à faire

## Contexte
L'audit Impeccable de l'écran livré au ticket 047 a été passé après coup, le 21 septembre 2026,
détecteur mécanique et inspection visuelle réelle comprises, aux deux largeurs. Score 16 sur 20 :
bon, avec deux dimensions faibles, le responsive et l'intégrité d'implémentation. Le brief de
design `design/047-import-membres.md` reste la référence ; ce ticket ne le rouvre pas, il rattrape
l'écart entre ce brief et ce qui a été construit.

Le détecteur ne rend rien sur les cinq fichiers de la fonctionnalité, et la partie métier tient :
encodages devinés, verdicts justes, plafond annoncé avant l'envoi. Les défauts sont de composition
et de vérité du texte.

## À faire

### La barre d'actions ignore la largeur de colonne (P1)
Le corps des trois temps est borné à `AppSpacing.colonneMax` et centré, la zone de boutons ne l'est
pas. Sur un écran de 1280 points, deux boutons de 1216 points flottent sous une colonne de 720. Le
chef de centre est sur ordinateur à ce moment précis, le brief le dit au paragraphe 1.

C'est systémique et non propre à l'import : `inviter_screen.dart` porte le même motif, et d'autres
écrans à barre d'action basse sont à vérifier. Sortir une barre d'actions partagée, bornée à la
même colonne que le corps, et la brancher partout où le motif se répète.

### Les lignes écartées sont noyées dans la liste (P1)
Le résumé annonce « 63 lignes lues : 60 à inviter, 3 écartées », puis il faut faire défiler soixante
lignes justes pour voir les trois fautives. Rien ne mène à elles. L'aperçu existe pour que personne
ne manque sans qu'on le sache : c'est le risque n° 1 du brief, celui que le ticket 047 avait pour
raison d'être. Remonter les écartées en tête de liste, ou rendre le compte du résumé actionnable.

### Le compteur d'avancement compte les échecs comme des envois (P2)
`AppStrings.importAvancement` dit « X invitations sur Y envoyées… », alors que le nombre vient de
`resultats.length`, c'est-à-dire du total des verdicts reçus, refus compris. Le rapport final
rétablit la vérité, mais le compteur ment pendant l'envoi.

### Le contenu défile sous la barre d'actions sans séparation (P2)
Une ligne est tranchée net au bord du bouton, aux deux largeurs. Il manque un filet, une ombre ou
un dégradé de fin de liste.

### Le rapport perd les noms et aligne soixante coches identiques (P2)
L'aperçu s'interdit explicitement la coche sur chaque ligne, jugée bruit ; le rapport la met
partout. Il affiche des adresses là où l'aperçu affichait des noms, alors que le nom est ce qui
permet de reconnaître les pompiers. La réutilisation du compte rendu du ticket 006 coûte ici :
décider si ce compte rendu accueille les noms, ou si l'import a le sien.

### Trois broutilles (P3)
- `ImporterController._phraseDeLecture` passe `maxOctetsFichier` comme taille réelle à
  `AppStrings.importTropGros` : le message affiche la limite deux fois.
- `_Rapport._motif` renvoie « déjà membre » pour les verdicts `aInviter` et `aInviterSansNom`.
  Branche morte, mais au contenu faux.
- `ImporterController.effacerErreur` n'est appelée de nulle part.

## Critères d'acceptation
- Sur un écran large, les boutons d'action ont la même largeur que le corps de l'écran, aux trois
  temps, et le même motif est appliqué à l'écran d'invitation.
- Après lecture d'un fichier mêlant lignes justes et lignes écartées, les écartées se voient sans
  avoir à parcourir toute la liste.
- Pendant l'envoi, le nombre annoncé ne compte que les invitations réellement parties.
- Le contenu qui défile sous la barre d'actions en est visuellement séparé.
- Le compte rendu d'import nomme les personnes, et n'aligne pas un marqueur identique sur chaque
  ligne quand tout est passé.
- Les trois broutilles P3 sont corrigées ou le code mort est retiré.
- `flutter analyze` sans avertissement, `flutter test` verts, `flutter build web` qui passe.
