# 064 — Un monde visuel pour le pompier, à partir d'un tableau de bord

- **Épopée** : E0 Fondations
- **Priorité** : P1
- **Dépend de** : 061, 063
- **Branche** : `feat/064-monde-visuel-pompier`
- **PR** : —
- **Statut** : à faire

## Contexte

Demandé par le propriétaire le 23 septembre 2026, avec une image de référence conservée dans
`design/assets/064-reference-pompier.png` : « pour la partie pompier, il doit être différent de
l'admin, il doit ressembler à ça ». Trois écrans de téléphone d'une application de vacations :
un accueil avec une salutation et un avatar, une rangée de cartes « Your shifts » (carte indigo
de la vacation du jour avec heure, rôle et lieu ; carte grise « Free day » ; carte jaune),
une section « Available shifts » avec une bande de semaine à points et une liste de créneaux
(lettre en avatar, heure, lieu, « 1/3 filled ») ; une boîte de réception à onglets ; quatre
icônes en bas.

Le propriétaire a tranché trois questions le même jour :

1. **Le premier écran devient un tableau de bord**, « Accueil » : salutation, prochaine
   astreinte, propositions à répondre, appel à saisir ses disponibilités. Le calendrier de
   saisie (aujourd'hui « Mon mois ») devient le deuxième onglet, « Calendrier ».
2. **« Available shifts », ce sont les propositions reçues** : les créneaux que l'admin propose
   et auxquels le pompier doit répondre. Pas de créneaux à pourvoir en libre-service, ce n'est
   pas dans le PRD.
3. **La barre du bas passe à quatre entrées** : Accueil, Calendrier, Astreintes, Boîte. Le profil
   passe derrière l'avatar de l'en-tête. La Boîte réunit notifications et propositions avec des
   onglets. L'admin garde sa cinquième entrée « Admin », visible pour lui seul.

Les tokens du ticket 061 (indigo, vert, orange et rose de remplissage, Archivo pour les titres,
Atkinson pour le corps) ne changent pas : c'est la **structure** et la **matière** des écrans du
pompier qui changent, pas la palette. Ce ticket remplace le chantier 061d, qui n'était qu'une
passe de fini : la passe de fini devient le dernier chantier de celui-ci.

## À faire

- Brief `design/064-monde-visuel-pompier.md` (écrit, joint à ce ticket), puis les chantiers
  dans l'ordre qu'il fixe : 064a navigation et Accueil, 064b Boîte, 064c Calendrier et
  Astreintes, 064d passe de fini Impeccable sur tous les écrans du pompier.
- `docs/PRD.md § 5.5` et `PRODUCT.md` : l'accueil du pompier est un tableau de bord, le
  calendrier de saisie est un onglet ; les deep links de `docs/WORKFLOWS.md` qui visaient
  « Mon mois », « Propositions » ou « Notifications » sont relus et mis à jour.
- Les écrans changent de route sans casser les liens des notifications déjà envoyées :
  les anciennes routes redirigent.

## Critères d'acceptation

- L'accueil du pompier est un tableau de bord conforme au brief : salutation, cartes
  d'astreinte, propositions avec bande de semaine, appel à saisir les disponibilités quand une
  période est ouverte.
- La barre du bas a quatre entrées pour un membre, cinq pour un admin ; le profil s'ouvre
  depuis l'avatar et revient avec `BoutonRetour`.
- La Boîte a des onglets Tout / Propositions / Rappels ; répondre à une proposition depuis la
  Boîte ou l'Accueil produit le même résultat qu'aujourd'hui.
- Aucune régression fonctionnelle : saisie des disponibilités, réponse aux propositions,
  export ICS, notifications ; les tests existants de ces parcours restent verts (adaptés aux
  nouvelles routes, jamais affaiblis).
- Contraste 4,5:1 pour tout texte, aucun état porté par la couleur seule, cibles 44 pt,
  Operate : lisible dehors, avec des gants.
- `flutter analyze` sans avertissement, `flutter test` verts, `flutter build web` qui passe,
  détecteur Impeccable à vide, inspection à l'écran à 390 et sur un téléphone avec la PWA
  installée.
