# 047 — Importer les membres d'une caserne depuis un fichier

- **Épopée** : E2 Casernes
- **Priorité** : P0
- **Dépend de** : 006, 009, 038
- **Branche** : `feat/047-import-membres`
- **Statut** : en cours depuis 2026-09-21

## Contexte
Demandé par le propriétaire au moment de créer sa première caserne réelle. Aujourd'hui, l'admin
invite en collant jusqu'à vingt adresses dans un champ, et chaque pompier complète ensuite son
profil lui-même. Pour monter une caserne existante de trente à soixante personnes à partir d'une
liste déjà tenue ailleurs, c'est trop lent et cela perd les noms, qui sont pourtant ce dont l'admin
a besoin pour reconnaître ses pompiers dans la matrice dès le premier mois.

`docs/PRD.md` section 4.2 prévoyait cet import pour une version ultérieure. Il devient nécessaire
tout de suite.

Confirmé par le propriétaire : la liste est un fichier tableur, et tous les pompiers ont une
adresse de courriel qu'ils consultent. Le chemin reste donc l'invitation, pas la création de
comptes sans courriel.

## À faire
- **Lecture d'un fichier** au format tableur, séparé par des virgules ou des points-virgules, avec
  au minimum prénom, nom et adresse. Reconnaître les en-têtes plutôt qu'exiger un ordre de colonnes,
  et accepter les variantes d'intitulés courantes. Prévoir aussi une colonne de rôle facultative.
- **Aperçu avant validation** : l'admin voit ce qui sera fait ligne par ligne avant que rien ne
  parte, avec les lignes en erreur signalées et modifiables ou ignorables. Rien ne s'envoie tant
  qu'il n'a pas confirmé.
- **Rapport après import**, ligne par ligne : invitée, déjà membre, adresse invalide, doublon dans
  le fichier, échec d'envoi. Le ticket 006 a déjà ce vocabulaire de résultats, le réutiliser.
- **Les noms saisis à l'import doivent servir** : aujourd'hui le profil est complété par le pompier
  lui-même à sa première connexion. Décider ce qui prime si l'admin a saisi un nom et que le
  pompier en saisit un autre, et documenter le choix.
- **Le plafond d'envoi du ticket 038 s'applique** : soixante courriels par heure et par caserne.
  Un import de soixante personnes le frôle, un de cent le dépasse. L'import doit donc soit
  s'étaler, soit prévenir clairement l'admin de ce qui partira maintenant et de ce qui suivra,
  plutôt que d'échouer à mi-chemin. C'est le point le plus délicat du ticket.
- **Une limite de taille de fichier** et un refus explicite au-delà, pour ne pas dépendre de la
  bonne volonté de l'appelant.

## Critères d'acceptation
- Importer un fichier de soixante lignes crée soixante invitations, avec les noms, et le rapport
  distingue chaque cas.
- Un fichier contenant des doublons, des adresses invalides et un membre déjà présent produit un
  rapport juste sans rien envoyer d'erroné.
- Un import qui dépasse le plafond horaire le dit avant de commencer, et n'abandonne personne en
  chemin.
- Le fichier d'exemple attendu est documenté, avec ses en-têtes.
