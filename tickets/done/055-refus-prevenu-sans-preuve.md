# 055 — Un refus annonce « ton chef de centre est prévenu » sans preuve

- **Épopée** : E5 Validation
- **Priorité** : P2
- **Dépend de** : 050
- **Branche** : `feat/055-refus-prevenu-sans-preuve`
- **PR** : —
- **Statut** : terminé le 2026-09-26 (PR créée)

## Contexte

Relevé par le balayage du ticket 050, le 22 septembre 2026 : le seul reste, dans toute
l'application, d'un texte qui affirme un envoi sans en avoir la preuve.

Quand un pompier refuse une proposition d'astreinte, l'écran des propositions affiche
« <créneau> : refusée. Ton chef de centre est prévenu. » (`AppStrings.propositionsRefusee`). Or
`ResultatReponse` ne vaut que « enregistrée » ou « disparue » : la notification
`assignment_declined` est produite par le chemin d'écriture côté serveur (`docs/WORKFLOWS.md
§ 5`), et **aucun accusé ne remonte au client**. Si la file de notifications est en panne, comme
elle l'a été toute la journée du 21 septembre avec l'adresse Docker dans le coffre, le pompier lit
que son chef est prévenu alors que personne ne l'est.

C'est le même défaut que les tickets 048 et 050 ont corrigé sur les invitations, à ceci près
qu'ici la base ne sait pas encore répondre. Le ticket 050 n'y a pas touché pour cette raison.

## À faire

- Faire remonter au client le sort de la notification de refus. Deux voies à peser dans
  `docs/SCHEMA.md` : la procédure de réponse rend ce qu'elle a mis en file (une notification en
  file n'est pas une notification livrée, le texte doit alors dire « sera prévenu » et non « est
  prévenu ») ; ou l'écran lit ensuite l'état de livraison. La première est plus simple et plus
  honnête tant que la livraison est asynchrone.
- Réécrire la phrase pour qu'elle ne promette que ce que le serveur soutient, et brancher le
  garde-fou `test/support/promesse_envoi.dart` sur l'écran des propositions, en élargissant son
  motif aux verbes utilisés ici (« prévenu », « notifié ») s'il ne les couvre pas.
- Même défaut, même asymétrie, relevé par la revue du 050 : `AppStrings.reattribuerFaite` dit
  « <membre> est prévenu. » pour le nouveau titulaire d'une réattribution, alors que la réponse
  du serveur ne porte le fait que pour l'ancien (`reattribuerFaiteEtAncien` est, lui, gardé par
  `resultat.ancienPrevenu`). La procédure de réattribution doit rendre un `notified` pour l'entrant
  comme elle le fait pour le sortant, et le texte le suivre.
- Au passage, `codeRenvoye` (« Nouveau code envoyé. Regarde tes e-mails. ») a le même angle mort
  côté authentification, mais aucun signal n'existe côté client : décider d'une formulation qui
  n'affirme pas la sortie du courriel, ou documenter pourquoi on garde la phrase.

## Critères d'acceptation

- Après un refus, l'écran ne dit pas que le chef de centre est prévenu si la base ne l'a pas mis
  en file ; le texte distingue « mis en file » de « prévenu ».
- Le garde-fou couvre l'écran des propositions et échoue si l'ancienne phrase revient.
- `docs/SCHEMA.md` décrit ce que la procédure de réponse rend.
- Tests de base et de règles de sécurité verts, `flutter analyze` sans avertissement,
  `flutter test` verts, `flutter build web` qui passe.
