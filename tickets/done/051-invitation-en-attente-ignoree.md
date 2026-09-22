# 051 — Une invitation en attente reste invisible pour qui vient de se connecter

- **Épopée** : E1 Authentification
- **Priorité** : P1
- **Dépend de** : 006
- **Branche** : `feat/051-invitation-en-attente-ignoree`
- **PR** : https://github.com/slider973/astreinte-manager/pull/51
- **Statut** : terminé le 2026-09-22 (PR créée)

## Contexte

Vécu par le propriétaire en production le 21 septembre 2026, sur son premier compte de pompier.

Il s'est connecté avec l'adresse à laquelle une invitation venait d'être envoyée, mais **sans passer
par le lien du courriel**. L'écran « Aucune caserne » lui a répondu : « Ton compte existe, mais il
n'est rattaché à aucune caserne. Demande une invitation à ton chef de centre : il t'ajoutera avec
cette adresse e-mail. »

C'est faux et c'est un cul-de-sac. L'invitation existait, en attente, pour cette adresse exactement.
Le produit demande à la personne d'aller réclamer ce qu'elle a déjà.

Le mécanisme : la fonction `invite-member` crée le compte au moment de l'invitation, alors que
l'appartenance ne naît qu'à l'acceptation, par `accept-invitation`. Entre les deux, un compte existe
sans caserne, et quiconque se connecte directement, sans ouvrir le courriel, tombe dans cet état.
Ce n'est pas un cas marginal : la personne qui a déjà l'application ouverte, celle qui la retrouve
sur son téléphone avant d'avoir lu son courriel, celle qui a rangé le message, toutes y arrivent.

## À faire

- Sur l'écran « Aucune caserne », chercher s'il existe une invitation en attente pour l'adresse de
  la session, et la proposer : nom de la caserne, qui invite, échéance, et le geste pour la
  rejoindre sans quitter l'écran.
- Décider comment cette recherche respecte les règles de sécurité. Une personne sans appartenance
  n'a aujourd'hui aucun droit de lecture sur `invitations` ; la route ne peut pas être une simple
  lecture de table, et elle ne doit rien révéler d'autre que ce qui la concerne, jamais l'existence
  d'une caserne ni un jeton. `docs/SCHEMA.md` gagne, et la décision s'y écrit.
- Garder l'écran juste quand il n'y a réellement rien : le texte actuel reste le bon dans ce cas.
- Traiter l'invitation expirée autrement que l'invitation absente. « Ton invitation a expiré,
  demande-en une nouvelle » n'est pas la même phrase, et c'est la seule qui dise quoi faire.

## Critères d'acceptation

- Un compte sans caserne, pour lequel une invitation est en attente, la voit et peut la rejoindre
  depuis cet écran, sans relire son courriel.
- Un compte sans caserne et sans invitation voit le texte actuel, inchangé.
- Une invitation expirée est distinguée d'une invitation absente.
- Aucune information sur une caserne, ni aucun jeton, n'est lisible par un compte qui n'y a pas
  droit ; un test de règles de sécurité le vérifie sous identité.
- `flutter analyze` sans avertissement, `flutter test` verts, `flutter build web` qui passe.
