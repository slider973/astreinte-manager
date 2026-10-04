# 073 — Échanger ou céder une astreinte entre pompiers

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web**,
Material 3, une seule apparence. Chantier **073b** (PWA) ; le chantier base (073a) livre en
parallèle `shift_exchanges` et les fonctions `request_exchange`, `respond_exchange`,
`decide_exchange`, `cancel_exchange`. Ce brief reste **au niveau des états et des actions** : il
ne nomme aucune colonne que le contrat n'aura pas confirmée, et il liste au § 9 ce que l'écran
attend du contrat.

`DESIGN.md` gagne sur ce brief pour toute valeur de token. Aucune couleur nouvelle n'est demandée :
les états d'échange **réemploient** les familles existantes (même réponse qu'au ticket 029).

Sources : `tickets/in-progress/073-echange-astreintes.md` (décisions du 29 septembre 2026, règles
métier) ; `PRODUCT.md` ; `DESIGN.md` (§ Attribution, § Écarts 020, 027, 064a à 064d) ;
`docs/WORKFLOWS.md § 3, § 5, § 8` ; `design/020-reattribution.md`, `design/021-ecran-propositions.md`,
`design/027-mes-astreintes.md`, `design/064-monde-visuel-pompier.md` ; le code des écrans
Astreintes (`feuille_astreinte.dart`, `ligne_astreinte.dart`), Boîte (`boite_screen.dart`,
`panneau_reponse.dart`), Suivi (`suivi_screen.dart`, `confirmation_reattribution.dart`) et
Paramètres (`formulaire_parametres.dart`).

Recherche ui-ux-pro-max (`--stack flutter`, `--domain ux`, `--domain web`) : la base n'a **aucune
entrée** sur l'échange de gardes ni sur les files d'approbation (« shift swap », « shift trade
approval queue » : zéro résultat en `flutter`, résultats hors sujet en `ux`). Ce qui a servi :
confirmation avant action irréversible, message de succès bref, erreur avec sortie, état vide avec
action, 8 px entre cibles, annonce contextuelle d'un compte qui change (« 2 échanges à valider »
et non « 2 »), `ListView.builder` pour les listes longues, `Semantics` partout. Le reste vient du
système en place.

> **Hypothèses.** Ce brief est écrit par un agent sans canal de question vers le propriétaire.
> Chaque choix que ni le ticket ni le PRD ne tranchent est marqué **[H]** et repris au § 11.

---

## 1. Job et audience

Trois personnes, trois moments.

**Antoine, le demandeur (A).** Mercredi soir, il apprend qu'il est convoqué à une formation le
samedi 12. Il est d'astreinte cette nuit-là, il l'a acceptée il y a trois semaines. Aujourd'hui il
appelle son chef, qui appelle des collègues, qui rappellent. Ce qu'il veut : **trouver quelqu'un
sans passer six coups de fil**, et savoir à tout moment où en est sa demande. Il est sur son
téléphone, assis, il a deux minutes — c'est le seul des trois parcours qui n'est pas pressé.

**Chloé, la remplaçante (B).** Son téléphone vibre : « Antoine C. te propose sa nuit du samedi
12 octobre ». Elle est au travail, une main libre. Elle sait en trois secondes si elle peut. Ce
qu'elle veut : **dire oui ou non sans réfléchir à ce que ça déclenche** — et, si c'est un
échange, voir d'un coup d'œil ce qu'elle prend **et ce qu'elle donne**. C'est le geste de la
proposition du ticket 021, avec une conséquence de plus à lire.

**Marie, la cheffe de centre (admin).** Elle reçoit « Chloé C. accepte de reprendre la nuit du
12 octobre d'Antoine C. ». Sur son portable au bureau ou sur son téléphone. Ce qu'elle veut :
**vérifier que ça ne casse rien** — Chloé n'est pas déjà trop chargée, elle avait dit être libre —
puis valider ou refuser en deux gestes. Elle ne refait pas le planning : deux pompiers se sont
arrangés, elle contresigne.

## 2. Résultat et preuve

**Résultat.** Une garde change de main sans coup de téléphone, avec l'accord des deux pompiers et
le contreseing du chef, et **le reste du planning ne bouge pas** (principe produit 3).

**Preuve, dans l'ordre :**

1. Demander coûte **quatre touches** depuis la feuille de l'astreinte pour une cession à la
   caserne (« Proposer un échange », « Toute la caserne », « Continuer », « Envoyer la demande »),
   six pour une cession à un collègue, huit pour un échange (collègue, forme, garde en retour, deux
   « Continuer », envoi). C'est le seul parcours du produit qui dépasse deux touches, et il le peut :
   A n'est pas pressé (§ 1), et chaque touche est une décision qu'il doit prendre.
2. Répondre coûte **trois touches depuis la notification** pour B, comme une proposition
   (`DESIGN.md § Écarts 064b`, « La promesse deux touches ») : la notification, la ligne, la
   réponse.
3. Valider coûte **deux touches** pour l'admin depuis la file : la ligne, puis « Valider » dans la
   confirmation. Sur grand écran, la ligne suivante n'en coûte qu'une de plus.
4. À chaque instant, A et B lisent l'état de la demande **en toutes lettres**, avec une icône et
   une marque, à un seul endroit : la carte de suivi de l'échange.
5. Un échange qui échoue à la validation ne produit jamais une erreur muette : il produit **une
   phrase qui nomme la cause** (« Chloé C. a atteint son maximum de weekends »), et rien d'autre
   n'a changé.
6. Après validation, les écrans existants racontent le changement sans écran nouveau : A voit sa
   garde disparaître de ses astreintes, B la voit apparaître, le suivi de l'admin montre l'ancienne
   attribution « Remplacé · remplacé par Chloé C. ».

## 3. Direction retenue

**Monde visuel : celui qui existe.** Le pompier est dans le monde des cartes douces (ticket 064),
l'admin dans le registre blanc à blocs réglés (ticket 061). Ce ticket n'ajoute **aucune famille de
couleur, aucune forme, aucun mouvement** ; il ajoute un objet métier, la demande d'échange, et lui
donne la grammaire des objets voisins.

**Thèse structurelle : la demande est un objet suivi, pas un message.** Une proposition (021) se
répond et disparaît. Une demande d'échange, elle, **vit plusieurs jours et passe par trois mains** :
il faut pouvoir la retrouver. D'où un seul objet visuel, la **carte d'échange**, qui se montre
identique à A, à B et à l'admin, et dont seul l'appel à l'action change selon qui regarde :

```
┌───────────────────────────────────────────────┐
│ [N]  Samedi 12 octobre · Nuit                 │  ← la garde cédée (CarreCreneau)
│      19:00 – 07:00                            │
│      Antoine C. · Chloé C.                    │  ← de qui, à qui (ou « Toute la caserne »)
│  ┌──────────────────────────────┐             │
│  │ ⏳ En attente de Chloé C.    │             │  ← StatusBadge : marque + icône + libellé
│  └──────────────────────────────┘             │
└───────────────────────────────────────────────┘
```

Pour un **échange**, la carte porte deux rangées réglées au lieu d'une, toujours dans le même
ordre et **toujours écrites du point de vue du lecteur** :

```
  Tu donnes   [N] sam. 12 oct. · Nuit · 19:00 – 07:00
  Tu prends   [J] mar. 15 oct. · Jour · 07:00 – 19:00
```

Pour l'admin, qui n'est ni l'un ni l'autre, les deux rangées disent les noms :
« Antoine C. cède » / « Chloé C. cède ». Le verbe est sur chaque ligne parce que c'est la ligne
qu'on lit de loin, pas l'en-tête.

**Le moment focal** est la **paire de gardes** dans le panneau de réponse de B. C'est là que l'erreur
coûte cher (accepter un échange en croyant accepter une cession), et c'est là que le design dépense
sa clarté : deux rangées pleine largeur, chacune avec son carré de créneau, son verbe en gras et
une icône de sens (`Icons.remove_circle_outline` pour ce qu'on donne, `Icons.add_circle_outline`
pour ce qu'on prend). Ni flèche typographique ni couleur ne portent le sens : le glyphe « → »
n'existe pas dans les coupes Atkinson (`DESIGN.md § Écarts 064a`).

**Le seul mouvement** est le tampon déjà existant (`DESIGN.md § Motion`) : il se pose une fois
quand une carte d'échange passe à « Validé » sous les yeux du pompier. Rien d'autre ne bouge.

## 4. Périmètre et limites

**Livré (PWA) :**

- Pompier A : depuis une astreinte acceptée à venir, « Proposer un échange » ; choix « Un collègue »
  ou « Toute la caserne » ; pour un collègue, « Céder » ou « Échanger » avec choix de sa garde en
  retour ; récapitulatif ; envoi ; suivi ; annulation.
- Pompier B : demandes reçues et « à reprendre » dans la Boîte (onglets « Propositions » et
  « Tout ») et sur l'accueil ; panneau de réponse ; suivi de ce qu'il a accepté.
- Admin : file « Échanges » avec charge et plafonds de chacun ; valider ; refuser avec motif ;
  réglage de validation automatique et d'échéance dans les Paramètres ; entrée depuis le Suivi.
- Les sept états de la demande, avec leurs textes exacts (§ 5.3 et § 10).
- Hors ligne et caserne suspendue : lecture seule, raison écrite à côté de chaque bouton inerte.

**Pas livré, et à ne pas esquisser :**

- L'app iOS (`foco/`) : chantier 073c. Les chaînes du § 10 servent de référence pour la parité,
  rien de plus.
- Un échange entre casernes, une garde contre plusieurs, une chaîne à trois (hors périmètre du
  ticket).
- Une bourse aux gardes ouverte à tous : « Toute la caserne » ne montre la demande **qu'aux
  membres ayant déclaré une disponibilité** sur ce créneau (décision 1). L'écran de A ne promet
  jamais plus que ça.
- Un message libre de A à B. Le ticket ne le prévoit pas et le schéma n'aura pas la colonne. Le
  pompier qui veut s'expliquer a un téléphone.
- Une modification de demande. Une demande se crée ou s'annule ; pour changer de collègue, on
  annule et on recommence.
- Une modification de la matrice admin : aucune case nouvelle, aucune légende nouvelle. L'échange
  validé passe par `replaced` et `replaced_by`, que la matrice et le suivi savent déjà dire.

**Anti-objectifs :**

- **Pas de messagerie.** Pas de fil de discussion, pas de « commentaire ». La demande est un
  formulaire à trois champs, pas une conversation.
- **Pas de liste des collègues « disponibles » pour A.** A ne voit pas les disponibilités des
  autres (RLS) ; l'écran ne fait pas semblant de les connaître. C'est la base qui filtre « Toute la
  caserne », et c'est la base qui refuse un collègue inéligible.
- **Pas de glissement pour répondre**, pas de « tout accepter » : mêmes raisons qu'au 021.
- **Pas de confirmation côté B à l'acceptation.** Le panneau **est** la confirmation : il s'ouvre
  par un appui et dit les deux gardes. Un dialogue de plus ferait quatre touches. La validation
  admin est le filet.
- **Pas de nouvel onglet dans la Boîte ni de nouvelle destination** : cinq destinations au plus
  (`DESIGN.md § Navigation`), et la barre d'onglets de la Boîte est déjà pleine à 390 points
  (`§ Écarts 064b`, « La largeur des trois onglets »).

## 5. États et plages de contenu

### 5.1 Plages réelles

| Grandeur | Minimum | Typique | Maximum retenu |
|---|---|---|---|
| Membres actifs proposés à A comme collègue | 0 (caserne de un) | 25 | **59** (60 moins A) |
| Gardes à venir de B, proposables en retour | 0 | 3 | 15 (trois mois publiés) |
| Demandes reçues par B en même temps | 0 | 0 | 6 |
| Demandes « à reprendre » visibles par un disponible | 0 | 1 | 10 |
| Demandes suivies par A en même temps | 0 | 1 | 1 par astreinte (une seule ouverte par attribution) |
| File admin « À valider » | **0** (le cas courant) | 1 | 20 |
| Motif de refus admin | 0 | 25 caractères | **120**, coupés à la saisie |
| Nom d'un membre (`display_name`) | 2 | 10 | libre en base : `ellipsis` sur une ligne, nom entier en sémantique |

Zéro est le cas nominal partout. Cinquante-neuf collègues est légal : la liste est virtualisée,
précédée d'un champ de recherche dès **plus de 12 membres**.

### 5.2 Ce qui rend une astreinte « proposable »

Le bouton « Proposer un échange » n'apparaît **que** sur une astreinte **acceptée**, d'un planning
**publié ou validé**, sur un créneau **futur**. Sur les autres, il est **absent**, pas grisé : une
astreinte passée n'a rien à proposer. Grisé avec sa raison, en revanche, dans quatre cas où le
pompier peut s'attendre à le trouver :

| Cas | Bouton | Raison écrite sous le bouton |
|---|---|---|
| Une demande est déjà ouverte sur cette garde | remplacé par la carte de suivi (§ 6.4) | — |
| L'échéance est passée (24 h avant par défaut) | grisé | « Trop tard pour proposer un échange : la demande devait partir avant le {date} à {heure}. » |
| Hors ligne | grisé | « Une demande d'échange a besoin du réseau. » |
| Caserne suspendue | grisé | « Caserne suspendue : les échanges sont bloqués. Contacte ton chef de centre. » |

### 5.3 Les sept états de la demande — la grammaire

Aucune encre nouvelle : chaque état prend un descripteur existant de `app_status.dart`
(`StatusBadge.descripteur`, comme au 029). Trois signaux par état — **marque, icône, libellé** — et
la couleur en quatrième. Vérifier en niveaux de gris : deux états qui partagent une famille
diffèrent toujours par l'icône **et** le libellé.

| Statut base | Libellé court (badge) | Icône | Famille réemployée | Marque |
|---|---|---|---|---|
| `open`, demande à un collègue | « En attente de {prénom N.} » | `Icons.hourglass_top` | attente (ocre) | contour 2 dp, fond ocre pâle |
| `open`, demande à la caserne | « Cherche un remplaçant » | `Icons.person_search` | attente (ocre) | idem |
| `accepted_by_peer` | « À valider par le chef » | `Icons.how_to_reg` | attente (ocre) | idem |
| `approved` | « Validé » | `Icons.verified` | accepté / validé (vert) | plein, tampon |
| `rejected` (par B ou par l'admin) | « Refusé » | `Icons.cancel` | refusé (rose) | barré |
| `cancelled` | « Annulé » | `Icons.block` | annulé (gris) | barré, atténué |
| `expired` | « Expiré » | `Icons.timer_off` | archivé (gris atténué) | atténué |
| `failed` | « N'a pas pu se faire » | `Icons.error_outline` | conflit (rose) | contour 2 dp `error` |

- « En attente de… » et « À valider par le chef » partagent l'ocre : c'est voulu, les deux disent
  « pas encore ». L'icône (`hourglass_top` / `how_to_reg`) et le libellé les séparent.
- « Refusé » et « N'a pas pu se faire » partagent le rose : l'icône (`cancel` / `error_outline`) et
  le libellé les séparent, et la ligne de détail dit qui ou quoi.
- **Un statut terminal n'est jamais une alarme pour A** sauf `failed` et `rejected` : `cancelled`
  et `expired` sont des faits gris (`DESIGN.md § Do's`).
- Le badge d'état mesure 28 dp de haut, rayon 4 (`badge-etat`), texte `libelle-champ` 14.

Sous le badge, **une ligne de détail** en `corps-secondaire` dit le qui et le quand, et pour les
états terminaux le pourquoi :

| Statut | Ligne de détail, vue par A | vue par B | vue par l'admin |
|---|---|---|---|
| `open` (collègue) | « Envoyée {il y a 2 h}. Expire le {sam. 11 oct.} à {07:00}. » | (la demande est dans sa Boîte, pas dans son suivi) | « Envoyée {il y a 2 h} à Chloé C. » |
| `open` (caserne) | « Visible des collègues disponibles ce créneau. Expire le … » | « Antoine C. cherche un remplaçant. » | « Envoyée {il y a 2 h} aux disponibles. » |
| `accepted_by_peer` | « Chloé C. a accepté {il y a 10 min}. Ton chef de centre doit valider. » | « Tu as accepté {il y a 10 min}. Ton chef de centre doit valider. » | « Accepté par Chloé C. {il y a 10 min}. » |
| `approved` | « Validé par Marie D. le {12 oct.}. Chloé C. assure cette garde. » | « Validé par Marie D. le … C'est ta garde. » | « Validé par {toi / Marie D.} le … » ; automatique : « Validé automatiquement le … » |
| `rejected` par B | « Chloé C. a refusé. » | « Tu as refusé. » | « Refusé par Chloé C. » |
| `rejected` par l'admin | « Refusé par Marie D. : « {motif} » » (ou sans motif : « Refusé par Marie D. ») | idem | « Refusé par {toi / Marie D.} : « {motif} » » |
| `cancelled` | « Tu as annulé ta demande. » | « Antoine C. a annulé sa demande. » | « Annulé par Antoine C. » |
| `expired` | « Personne n'a répondu à temps. Ta garde reste la tienne. » | « Cette demande a expiré. » | « Expiré sans réponse. » |
| `failed` | « L'échange n'a pas pu se faire : {cause}. Ta garde reste la tienne. » | « L'échange n'a pas pu se faire : {cause}. » | « Échec : {cause}. » |

**Les causes d'échec** (`failed`) et des refus de la base à la demande ou à la réponse, en
français, sans code. Le mot exact dépend du contrat (§ 9) ; l'écran a une phrase par motif et une
phrase de repli :

| Motif (contrat à confirmer) | Phrase |
|---|---|
| la garde de A n'est plus acceptée | « la garde a changé entre-temps » |
| B est déjà sur ce créneau, ou sur un créneau qui chevauche dans une autre caserne (072) | « {Chloé C.} est déjà prise sur ce créneau » |
| plafond d'astreintes de B atteint | « {Chloé C.} a atteint son maximum d'astreintes du mois » |
| plafond de weekends de B atteint | « {Chloé C.} a atteint son maximum de weekends du mois » |
| (échange) idem côté A sur la garde de B | mêmes phrases avec le nom de A |
| B n'est plus membre actif | « {Chloé C.} n'est plus membre de la caserne » |
| caserne suspendue | « la caserne est en lecture seule » |
| créneau commencé ou planning archivé | « le créneau a commencé » |
| autre | « la situation a changé entre-temps » |

### 5.4 Les états des écrans

| État | Astreintes (A) / suivi | Boîte (B) | File admin |
|---|---|---|---|
| Chargement | cartes fantômes de la section « Échanges » (forme de `SqueletteAstreintes`) | squelette de la Boîte inchangé | squelette de liste réglée (forme de `SqueletteSuivi`) |
| Vide | section absente (pas d'en-tête vide) | l'état vide existant de « Propositions », inchangé | « Aucun échange à valider » + texte (§ 10) |
| Erreur de lecture | état d'erreur **dans la section**, « Réessayer » (`§ Écarts 064a`) | idem | `EmptyState` d'erreur avec « Réessayer » |
| Hors ligne | bannière `hors-ligne` de consultation (« Hors ligne. » + « Dernière mise à jour : … »), boutons grisés avec raison | idem | idem |
| Caserne suspendue | bannière `lecture-seule`, boutons grisés avec raison | idem | idem |
| Demande disparue pendant la lecture (annulée, expirée, prise par un autre) | — | bannière d'information dans le panneau, ligne retirée (patron « proposition disparue » du 021) | ligne qui passe dans « Terminés » à la relecture |
| Planning archivé | plus aucun bouton ; les cartes terminées restent lisibles jusqu'au créneau | — | « Terminés » seulement |
| 60 membres | recherche + liste virtualisée | — | — |

Le « mois verrouillé » de la saisie **ne concerne pas** l'échange : il verrouille les
disponibilités, pas le planning. Un mois verrouillé ne grise rien ici.

## 6. Parcours du pompier A — proposer, suivre, annuler

### 6.1 Le point d'entrée

**Dans la feuille de l'astreinte** (`DetailAstreinte`, `feuille_astreinte.dart`), dans chaque bloc
de créneau, **sous** « Ajouter à mon calendrier » : un `PrimaryButton` **secondaire**, pleine
largeur, icône `Icons.swap_horiz`, libellé **« Proposer un échange »**. Un bouton par créneau, pas
par feuille : la feuille porte une journée, et un pompier peut être de jour et de nuit le même jour
(même raison que l'export ICS, `design/028 § 6`).

Pas de bouton sur la ligne de la liste ni sur la case du calendrier : la ligne s'ouvre déjà par un
appui (027), et deux cibles dans une ligne de 72 se touchent par accident avec des gants.

**[H]** Pas de raccourci depuis l'accueil. L'accueil dit la prochaine astreinte ; l'échanger est
rare, et la feuille est à un appui de la carte.

### 6.2 La demande — un écran poussé, trois étapes au plus

Route poussée **`/astreintes/echange?attribution=<id>&etape=<qui|quoi|verifier>`**, avec
`BoutonRetour` et `SafeArea(top: false)` (règle des écrans poussés, `§ Écarts 064a`). L'étape est
**dans l'adresse** : le retour du navigateur et le geste retour iOS reculent d'une étape, jamais
de tout le parcours. Une adresse dont l'attribution n'est plus proposable rouvre la feuille
d'astreinte avec la raison, sans erreur.

Fond doux (`AppScaffold.fondDoux`), contenu en `CarteDouce`. En tête, **toujours visible**, la
garde concernée dans une carte : `CarreCreneau` + « Samedi 12 octobre · Nuit » (`titleMedium`) +
« 19:00 – 07:00 ». Sous elle, l'étape en cours en texte : « Étape 1 sur 3 » (`mention`), pas de
barre de progression ni de pastilles numérotées.

Barre d'application : titre **« Proposer un échange »**. Le bouton d'avancée est dans
`filActions`, épinglé en bas, 52 dp, pleine largeur : il ne défile pas avec la liste des collègues.

**Étape 1 — « À qui ? »**

Deux grands choix exclusifs (`ChoixExclusif`, § 8), 64 dp au moins, icône à gauche, titre,
ligne d'explication, coche quand choisi :

- `Icons.person_outline` · **« Un collègue »** — « Tu choisis la personne. Tu peux céder ta garde ou
  l'échanger contre une des siennes. »
- `Icons.groups_outlined` · **« Toute la caserne »** — « Les collègues qui se sont dits disponibles
  ce créneau la verront. Le premier qui accepte la prend. »

Quand « Un collègue » est choisi, la liste des membres actifs de la caserne s'ouvre **sous** les
deux choix, dans la même page :

- Champ « Chercher un collègue » (`ChampTexte`, libellé au-dessus) dès plus de 12 membres.
- Une ligne par membre, 56 dp : `AvatarInitiales` 32 (décoratif), nom en `corps`, coche
  `Icons.check_circle` et fond `primary-container` quand choisi. `Semantics(selected:,
  inMutuallyExclusiveGroup: true)`.
- A n'y figure pas. Tri alphabétique. Aucune mention de disponibilité : A ne la connaît pas.
- Liste vide (caserne de un) : « Tu es seul dans ta caserne pour l'instant. » et « Un collègue »
  grisé avec cette raison.

Bouton : **« Continuer »**. Grisé tant que rien n'est choisi, raison « Choisis un collègue ou
toute la caserne. » sous le bouton. Avec « Toute la caserne », l'étape 2 est **sautée** (une
demande à la caserne est toujours une cession, décision 2) et le bouton mène à « Vérifier » ;
l'étape affichée devient alors « Étape 1 sur 2 ».

**Étape 2 — « Céder ou échanger ? »** (collègue seulement)

Deux choix exclusifs :

- `Icons.redo` · **« Céder »** — « {Chloé C.} prend ta garde. Tu ne prends rien en retour. »
- `Icons.swap_horiz` · **« Échanger »** — « {Chloé C.} prend ta garde, et tu prends une des
  siennes. »

Quand « Échanger » est choisi, la liste des **gardes à venir de B** s'ouvre dessous : une ligne
par garde, 56 dp, `CarreCreneau` + « mar. 15 oct. · Jour · 07:00 – 19:00 », choix exclusif.
Groupées par mois avec `EnteteSection.discret` si elles s'étendent sur plus d'un mois.

- Chargement : trois lignes fantômes.
- B n'a aucune garde à venir : « Échanger » reste visible, **grisé**, raison « {Chloé C.} n'a pas
  de garde à venir à échanger. »
- Une garde de B qui tombe **sur le même créneau** que celle de A n'est pas listée.
- **[H]** Une garde de B déjà engagée dans une autre demande ouverte est listée grisée, mention
  « Déjà dans une demande en cours ». À confirmer avec le contrat (§ 9).

Bouton : **« Continuer »**, grisé avec raison « Choisis la garde que tu prends en retour. » tant
que « Échanger » est choisi sans garde.

**Étape 3 — « Vérifie ta demande »**

Un récapitulatif en une carte, puis l'envoi. Rien n'est éditable ici : on revient en arrière pour
changer (le bouton retour le fait).

```
Vérifie ta demande

  Tu donnes   [N] Samedi 12 octobre · Nuit · 19:00 – 07:00
  Tu prends   [J] Mardi 15 octobre · Jour · 07:00 – 19:00     ← échange seulement

  À           Chloé C.          (ou « Les collègues disponibles ce créneau »)

  ⓘ Ton chef de centre devra valider après l'accord de Chloé C.
     La demande expire le vendredi 11 octobre à 19:00.

  [ Envoyer la demande ]
```

La phrase d'information prend le patron « bloc dans le contenu » du 023 (fond `etat-info-fond`,
icône `Icons.info_outline`, sans filet coloré à gauche). Quand la caserne a activé la validation
automatique, la phrase devient « Si {Chloé C.} s'était dite disponible ce créneau, l'échange sera
validé dès son accord. Sinon, ton chef de centre validera. » **[H]** : A peut lire ce réglage
(à confirmer, § 9) ; sinon la phrase par défaut reste juste dans les deux cas, puisque le chef est
« informé ».

Bouton principal : **« Envoyer la demande »** (`PrimaryButton`, chargement intégré : le libellé
reste, l'indicateur de 20 dp le précède). Pas de dialogue de confirmation : cet écran **est** la
confirmation, et l'envoi est annulable.

**Après l'envoi** : retour à `/astreintes` (la pile du parcours est remplacée, pas empilée), la
feuille de l'astreinte n'est pas rouverte, et un message passager (8 s, `§ Écarts 024`) dit
« Demande envoyée à Chloé C. » ou « Demande envoyée aux collègues disponibles. ». La ligne de
l'astreinte porte désormais sa mention d'échange (§ 6.3).

**Refus de la base à l'envoi** : le récapitulatif reste à l'écran, une `AppBanner` d'erreur au-dessus
dit la phrase du motif (§ 5.3) et « Le récapitulatif est resté là : change de collègue ou de garde
et réessaie. », et le bouton se réactive. Une erreur de réseau dit « Ta demande n'est pas partie.
Vérifie le réseau et réessaie. »

### 6.3 Ce que la liste des astreintes montre

**Une section « Échanges » en tête de l'écran Astreintes** (portée « Moi », vue « Liste »), au-dessus
des mois, présente **seulement** quand le pompier a au moins une demande à suivre — comme
demandeur ou comme repreneur. `EnteteSection.discret` « Échanges · {n} », puis une carte d'échange
par demande (§ 3), triées : `accepted_by_peer`, puis `open`, puis terminées par date de décision
décroissante.

Ce qui y reste :

- toutes les demandes `open` et `accepted_by_peer` du pompier ;
- les demandes terminées **tant que le créneau concerné est à venir**, puis elles disparaissent
  **[H]** (l'historique complet reste côté admin et dans le suivi). Cela garde la trace d'un refus
  ou d'un échec le temps qu'elle sert.

Au-delà de trois cartes, la section se replie sur les trois plus récentes et un bouton texte
« Voir les {n} échanges » (48 dp) la déplie en place.

En plus, **la ligne d'astreinte** concernée (`LigneAstreinte`) gagne une seconde ligne de mention
quand une demande est ouverte : `Icons.swap_horiz` 16 + « Échange en cours » en `corps-secondaire`
`on-surface-variant`, et la sémantique de la ligne finit par « échange en cours ». Pas de badge
de couleur sur la ligne : l'état vit dans la carte.

Dans la **vue « Mois »** (calendrier), rien ne change visuellement **[H]** : une case de 45 dp n'a
pas la place d'une troisième marque ; la sémantique de la case ajoute « échange en cours ».

### 6.4 Le détail d'une demande et l'annulation

Un appui sur une carte d'échange ouvre **le détail de l'échange** : feuille de bas d'écran en
compact, medium et expanded ; dialogue de 480 en large — la mécanique de `ouvrirDetailAstreinte`.
Dans la feuille d'astreinte elle-même, la garde qui a une demande ouverte montre **la même carte**
à la place du bouton « Proposer un échange ».

Contenu du détail :

1. Titre : « Échange de la nuit du samedi 12 octobre » (ou « Cession de… » pour une cession).
2. Badge d'état et ligne de détail (§ 5.3).
3. La ou les gardes, en rangées « Tu donnes / Tu prends ».
4. Le fil : trois lignes au plus, en `mention`, horodatées — « Demandée le 8 oct. à 21:14 »,
   « Acceptée par Chloé C. le 9 oct. à 07:02 », « Validée par Marie D. le 9 oct. à 12:30 ». C'est
   l'exigence « l'historique reste lisible » du ticket, à l'échelle d'une demande.
5. Les actions, selon l'état et le lecteur :

| Lecteur | `open` | `accepted_by_peer` | terminal |
|---|---|---|---|
| A | « Annuler la demande » (secondaire) | « Annuler la demande » (secondaire) | — |
| B (a accepté) | — | — | — |
| tous | « Fermer » | « Fermer » | « Fermer » |

**[H]** B ne peut pas se rétracter après avoir accepté : le contrat ne prévoit pas de transition
`accepted_by_peer → open`. Si Chloé change d'avis, elle le dit au chef, qui refuse. Le détail le
dit à B : « Pour revenir sur ton accord, contacte ton chef de centre. »

**Annuler** ouvre une confirmation (feuille en compact, dialogue en large), parce que la demande
est déjà partie sur d'autres téléphones :

- Titre : « Annuler ta demande ? »
- Texte (collègue) : « Chloé C. sera prévenue. Ta garde du samedi 12 octobre, de nuit, reste la
  tienne. » ; (caserne) : « Les collègues qui la voyaient ne la verront plus. Ta garde reste la
  tienne. » ; (déjà acceptée) : « Chloé C. avait accepté. Elle et ton chef de centre seront
  prévenus. Ta garde reste la tienne. »
- Boutons : **« Annuler la demande »** (danger) et **« Garder la demande »** (secondaire).

Après annulation : message passager « Demande annulée. », la carte passe à « Annulé ».
Si la demande a été validée entre-temps, la base refuse : bannière dans la feuille « Trop tard :
l'échange vient d'être validé. » et la carte se relit.

## 7. Parcours du pompier B — recevoir, reprendre, répondre

### 7.1 Où les demandes arrivent

**Dans la Boîte, onglet « Propositions » et onglet « Tout »**, comme des propositions : ce sont des
questions qui attendent un geste. L'onglet ne change pas de nom **[H]** — une demande d'un collègue
est une proposition de garde ; un quatrième onglet ne tiendrait pas à 390.

Dans l'onglet « Propositions », un groupe **« Demandes de collègues · {n} »** (`EnteteSection.discret`)
**au-dessus** des groupes par mois : une demande humaine expire plus vite qu'une proposition de
planning, elle passe devant. Dans « Tout », elle est classée par date d'arrivée, comme le reste
(`§ Écarts 064b`, « Le tri de Tout »).

**Sur l'accueil**, la section « Propositions · {n} » compte aussi les demandes reçues et « à
reprendre » **[H]** : le chiffre dit « ce qu'on te demande », et le pompier ne doit pas apprendre
deux endroits. La bande de semaine pose le point orange de proposition sur le jour de la garde
proposée.

**La carte de demande reçue** reprend `CarteProposition` (carte douce, `CarreCreneau`, titre,
ligne, mention d'ancienneté à droite) :

| Forme | Titre | Ligne | Mention |
|---|---|---|---|
| Cession, à toi | « Samedi 12 octobre · Nuit » | « Antoine C. te propose sa garde » | « il y a 2 h » |
| Échange, à toi | « Samedi 12 octobre · Nuit » | « Antoine C. te propose un échange contre ton jour du mar. 15 oct. » | « il y a 2 h » |
| À reprendre | « Samedi 12 octobre · Nuit » | « À reprendre · Antoine C. cherche un remplaçant » | « il y a 2 h » |

Une icône de 20 dp précède la ligne : `Icons.swap_horiz` pour un échange ou une cession à toi,
`Icons.person_search` pour « à reprendre ». C'est ce qui sépare d'un coup d'œil une demande d'un
collègue d'une proposition du planning, avec le texte ; la carte garde la même forme.

**Notifications.** La notification de demande reçue (et celle de demande « à reprendre ») pose la
même question que la carte : comme `assignment_proposed`, elle est **exclue de « Rappels » et du
compte de non-lues** (`docs/WORKFLOWS.md § 8`). Les issues — validée, refusée, annulée, expirée,
échouée, et pour l'admin « validé automatiquement » — sont des **faits** : elles vont dans
« Rappels » et comptent comme non lues.

### 7.2 Le panneau de réponse

Un appui sur la carte ouvre **`PanneauEchange`**, frère de `PanneauReponse` : volet latéral en
large (`AppScaffold.panneauLateral`, `etendu: true`), feuille de bas d'écran en dessous.

```
Échange proposé par Antoine C.                      ← titleLarge
il y a 2 h · expire le ven. 11 oct. à 19:00          ← mention

 ⊖  Tu donnes   [J] Mardi 15 octobre · Jour          ← échange seulement
                    07:00 – 19:00
 ⊕  Tu prends   [N] Samedi 12 octobre · Nuit
                    19:00 – 07:00

 ⓘ  Ton chef de centre validera après ton accord.

 [  Accepter l'échange  ][ Refuser ]
```

- **Ordre des rangées : « Tu prends » d'abord pour une cession** (il n'y en a qu'une), **« Tu
  donnes » d'abord pour un échange** : ce qu'on perd se lit avant ce qu'on gagne, c'est la
  question qu'on se pose en premier.
- Chaque rangée : icône de sens 24 (`remove_circle_outline` / `add_circle_outline`), verbe en
  `libelle-action` 16 gras, `CarreCreneau`, date en `titre-bloc`, heures en `corps`. Séparées par
  un filet `outline-variant`. Sémantique : « Tu donnes : mardi 15 octobre, jour, de 07:00 à
  19:00 ».
- Boutons, mêmes règles que `PanneauReponse` (asymétrie 3/5 – 2/5, empilés sous 350 points de
  rangée) :

| Forme | Bouton principal | Bouton secondaire |
|---|---|---|
| Cession à toi | « Accepter la garde » | « Refuser » |
| Échange à toi | « Accepter l'échange » | « Refuser » |
| À reprendre | « Je la prends » | **[H]** aucun : on l'ignore, elle disparaît quand quelqu'un la prend ou qu'elle expire |

- **Pas de motif au refus de B** **[H]** : un collègue qui dit non n'a pas à se justifier, et le
  contrat ne prévoit qu'un motif (celui de l'admin et de l'échec).
- **Pas de confirmation** (§ 4). Le refus non plus : il ne coûte rien, A peut redemander.
- Pour « à reprendre », la phrase d'information devient « Le premier qui accepte la prend. Ton chef
  de centre validera ensuite. »

**Après la réponse** : la carte quitte la liste, message passager — « Accord envoyé. Ton chef de
centre doit valider. » ; validation automatique acquise : « C'est fait : la garde du samedi
12 octobre est à toi. » ; refus : « Refus envoyé à Antoine C. ». L'accord rejoint le suivi de B dans
la section « Échanges » des Astreintes (§ 6.3).

**Courses** (deux repreneurs, demande annulée pendant la lecture) : la base répond que la demande
n'est plus ouverte. Bannière d'information dans le panneau, jamais de rouge — patron « proposition
disparue » du 021 :

- « Cette garde a déjà été reprise par un collègue. » (à reprendre, quelqu'un a été plus rapide)
- « Antoine C. a annulé sa demande. »
- « Cette demande a expiré. »
- repli : « Cette demande n'est plus ouverte. »

Puis la carte quitte la liste. **Refus de règle** (B dépasserait son plafond, déjà prise) : bannière
d'erreur dans le panneau avec la phrase du § 5.3 tournée vers B — « Tu as atteint ton maximum de
weekends du mois : tu ne peux pas accepter. » —, boutons inertes, la carte reste (A peut annuler).

## 8. Parcours de l'admin — la file des échanges

### 8.1 L'écran et ses entrées

Nouvel écran admin **« Échanges »**, route **`/admin/echanges`**, à côté de Membres, Réglages et
Mois de saisie. Entrées :

- les liens admin de la barre de la matrice et du suivi (`_liensAdmin`, icône `Icons.swap_horiz`,
  info-bulle « Échanges d'astreintes ») et leur menu nommé en compact (`_MenuAdmin`, libellé
  « Échanges d'astreintes ») ;
- dans le **Suivi du planning**, un bloc réglé en tête de contenu quand la file n'est pas vide :
  `Icons.how_to_reg` · « {n} échange(s) à valider » + bouton « Voir les échanges ». Famille
  attente (ocre), patron du « fait qui décrit le contenu » (`§ Écarts 023`), pas une bannière ;
- la notification « accord du collègue » de l'admin (lien public à créer, § 9).

L'écran n'est pas filtré par mois : un échange se juge à la garde, pas au mois affiché.

### 8.2 La composition

Papier blanc de l'admin, blocs réglés. Trois filtres en tête, dans la forme des filtres du suivi
(`filtres_suivi.dart`), chacun avec son compte en `nombre-petit` :
**« À valider · {n} »** (par défaut), **« En attente d'un collègue · {n} »**, **« Terminés »**.
Le filtre est dans l'adresse (`?filtre=a-valider|en-attente|termines`).

**Large (≥ 1200, conçu d'abord pour 1280)** : liste à gauche, **panneau de décision à droite**
(`panneauLateral`, 360, jamais de modale), comme le panneau du créneau de la matrice. La première
ligne « À valider » est ouverte d'office. Valider ou refuser ouvre la ligne suivante.

**Expanded (840–1199)** : même composition, panneau 360.

**Compact et medium** : liste seule ; un appui sur une ligne ouvre le panneau en feuille de bas
d'écran.

**La ligne de la file** (bloc réglé, 72 dp, rayon 8, filet 1 dp) :

```
[N] sam. 12 oct. · Nuit          Antoine C.  cède à  Chloé C.        ⏳ À valider par le chef
    Cession · accepté il y a 10 min · expire ven. 11 oct. 19:00
```

Pour un échange, la seconde ligne dit « Échange contre le jour du mar. 15 oct. ». En compact, la
ligne s'empile : date et créneau, noms, puis badge et mention ; elle s'allonge plutôt que de
tronquer. La ligne entière est la cible (56 dp au moins) : elle ne porte qu'une action, ouvrir.

### 8.3 Le panneau de décision — la charge de chacun

```
Cession · samedi 12 octobre, nuit                  ← titleLarge
Accepté par Chloé C. il y a 10 min                  ← mention

 Antoine C. cède    [N] sam. 12 oct. · Nuit
 Chloé C. cède      [J] mar. 15 oct. · Jour         ← échange seulement

 ── Charge après l'échange ─────────────────────
 Chloé C.     octobre   7/8 astr. · 3/2 w-e  ⚠    ← chiffres en Atkinson Mono
              ⚠ Dépasserait son maximum de weekends (2).
              Disponibilité déclarée : ✓ Disponible
 Antoine C.   octobre   5/8 astr. · 1/2 w-e       ← échange : sa charge change aussi

 [ Valider l'échange ]  [ Refuser ]
```

- **Charge** : pour chaque personne qui **reçoit** une garde, la charge du mois de cette garde
  **après** l'échange, au format des candidats (« 7/8 astr. · 3/2 w-e », `AppStrings` existant),
  calculée comme `v_member_load`. Pour une cession, A est listé aussi, sa charge baisse (mention
  « libère cette garde ») — c'est ce que le chef voudra voir pour un pompier qui cède souvent.
- **Plafond dépassé** : `Icons.warning_amber` + phrase en `error` (« Dépasserait son maximum de
  weekends (2). »). Le ticket fait du plafond une **règle bloquante** à la validation (contrairement
  au principe produit 4, qui vaut pour la construction) : le bouton « Valider » est alors **grisé**
  avec cette raison dessous, pour ne pas laisser l'admin provoquer un `failed` qu'on lui annonce
  déjà. Seul « Refuser » reste.
- **Disponibilité déclarée** de celui qui reprend, sur ce créneau : la marque de la case du
  registre en petit (`SlotChip` compacte, inerte) + « Disponible », « Absent » ou « Non saisi ».
  C'est l'information qui décide de la validation automatique, et la seule que le chef cherche.
- **Prise ailleurs** (072) : si la base signale que le repreneur est pris sur un créneau qui
  chevauche dans une autre caserne, ligne `Icons.event_busy` « Déjà de garde ailleurs sur ce
  créneau. », sans détail de l'autre caserne, et « Valider » grisé avec cette raison.

**Valider** ouvre une confirmation (patron 020 : un téléphone sonne, et ça ne se défait pas) :

- Titre : « Valider l'échange ? » / « Valider la cession ? »
- Texte (cession) : « La nuit du samedi 12 octobre passe d'Antoine C. à Chloé C. Les deux seront
  prévenus. » ; (échange) : « La nuit du samedi 12 octobre passe à Chloé C., et le jour du mardi
  15 octobre à Antoine C. Les deux seront prévenus. »
- Boutons : **« Valider et prévenir »** (primaire), **« Revenir »** (secondaire).

**Refuser** ouvre la même feuille avec un champ :

- Titre : « Refuser l'échange ? »
- Texte : « Antoine C. garde sa nuit du samedi 12 octobre. Antoine C. et Chloé C. seront
  prévenus. »
- Champ « Motif (facultatif) », 120 caractères, compteur, aide « Il sera envoyé aux deux
  pompiers. » **[H]** facultatif, comme l'annulation du 020 ; à rendre obligatoire si le
  propriétaire le veut.
- Boutons : **« Refuser et prévenir »** (danger), **« Revenir »**.

**Après** : message passager « Échange validé. Antoine C. et Chloé C. seront prévenus. » ou
« Échange refusé. Antoine C. et Chloé C. seront prévenus. » (« seront », jamais « sont » :
`docs/WORKFLOWS.md § 5`). La ligne passe dans « Terminés ».
**Échec à la validation** (`failed`) : la ligne passe dans « Terminés » avec son badge « N'a pas pu
se faire », et une bannière d'erreur au-dessus du panneau dit « L'échange n'a pas pu se faire :
{cause}. Rien n'a changé dans le planning. »

### 8.4 Ce que montrent « En attente d'un collègue » et « Terminés »

Lecture seule. Mêmes lignes, sans panneau d'action : le panneau montre le fil et l'état. « Terminés »
couvre les **30 derniers jours** **[H]**, plus récents en tête. Les validations automatiques y
figurent avec « Validé automatiquement ». L'admin ne peut pas annuler la demande d'un pompier
**[H]** : le ticket ne lui donne que valider et refuser, et refuser un `open` n'a pas de sens tant
que personne n'a accepté.

### 8.5 Le suivi et la matrice après validation

Rien de nouveau à dessiner : l'attribution de A passe `replaced`, la ligne du suivi la montre
« Remplacé · remplacé par Chloé C. » (020), la nouvelle attribution de B est `accepted`. **[H]** Si
le contrat lie l'attribution à l'échange, la mention devient « remplacé par Chloé C. · échange
validé » ; sinon elle reste celle du 020.

### 8.6 Le réglage

Dans **Paramètres de la caserne**, un nouveau groupe **« Échanges d'astreintes »**, après les
relances :

- `SwitchListTile` (jamais `.adaptive`, `§ Écarts 024`) : **« Valider automatiquement »** ;
  sous-titre « Quand le collègue qui reprend s'était dit disponible ce créneau, l'échange est validé
  dès son accord. Tu es seulement prévenu. Sinon, il attend ta validation. » Désactivé par défaut.
- `ChampNombre` : **« Fin des demandes »**, suffixe « heures avant le créneau », défaut 24
  **[H]** bornes 1–168, à aligner sur le contrat.

Le formulaire recompose `settings` en entier : les deux nouvelles clés doivent être **relues et
réécrites** même quand l'admin ne les touche pas (`docs/SCHEMA.md § 2.1`).

## 9. Ce que l'écran attend du contrat (chantier 073a)

Le brief ne fixe aucun nom de colonne. Il a besoin, à confirmer ou à refuser par `supabase-dev` :

1. **Qui a refusé** : distinguer un `rejected` de B d'un `rejected` de l'admin (acteur, ou deux
   motifs distincts). Sans ça, « Chloé C. a refusé » et « Refusé par Marie D. » se confondent.
2. **Qui a validé et quand**, et si la validation était **automatique**.
3. **Un motif d'échec codé** (`failed`) parmi une liste fermée, que l'app traduit (§ 5.3).
4. **Les gardes à venir de B**, lisibles par A au moment de choisir l'échange, réduites à la date et
   au créneau (la RLS n'ouvre les attributions des autres que sur un planning `validated`). Une
   fonction dédiée est probablement nécessaire. **Sans elle, « Échanger » ne peut pas être livré
   sur un planning seulement publié** — c'est le point le plus bloquant du brief.
5. **La liste des membres actifs** lisible par un membre (nom affiché seulement) pour l'étape 1.
6. **La charge projetée** du repreneur (et de A pour un échange) pour l'admin : `v_member_load`
   suffit si l'écran fait le calcul « + 1 garde ».
7. **La disponibilité déclarée** du repreneur sur le créneau (admin), et le booléen « pris
   ailleurs » du ticket 072.
8. **Le réglage d'échéance et de validation automatique** lisible par un membre (pour la phrase de
   l'étape 3 et « expire le … »), ou l'échéance calculée sur chaque demande (préférable : une
   colonne `expires_at`, l'app n'a rien à recalculer).
9. **Liens publics** des notifications, à ajouter à `docs/WORKFLOWS.md § 8` et à
   `destinationInterne` :

| Lien public proposé | Emplacement interne |
|---|---|
| `/exchanges` | `/boite?onglet=propositions` (demande reçue, à reprendre) |
| `/exchanges/<id>` | `/astreintes`, détail de l'échange ouvert (issues pour A et B) |
| `/admin/exchanges` | `/admin/echanges?filtre=a-valider` *(admin seulement)* |

10. **Types de notification** : demande reçue et « à reprendre » exclus de « Rappels » et du compte
    (comme `assignment_proposed`) ; toutes les issues dans « Rappels ».

## 10. Textes

Tous dans `AppStrings`, préfixe `echange…`. Tutoiement du membre ; l'admin est tutoyé aussi dans
ses phrases d'aide (« Tu es seulement prévenu »), comme le reste de l'admin ; aucun vouvoiement.
Glyphes : uniquement ceux de la liste vérifiée (`glyphes_couverts_test.dart`) — guillemets « »,
point médian, tiret demi-cadratin, apostrophe droite. **Aucune flèche.**

### 10.1 Pompier A

| Clé (indicative) | Texte |
|---|---|
| `echangeProposer` | Proposer un échange |
| `echangeTitre` | Proposer un échange |
| `echangeEtape(n, total)` | Étape {n} sur {total} |
| `echangeQuiTitre` | À qui ? |
| `echangeCollegue` | Un collègue |
| `echangeCollegueAide` | Tu choisis la personne. Tu peux céder ta garde ou l'échanger contre une des siennes. |
| `echangeCaserne` | Toute la caserne |
| `echangeCaserneAide` | Les collègues qui se sont dits disponibles ce créneau la verront. Le premier qui accepte la prend. |
| `echangeChercher` | Chercher un collègue |
| `echangeChercherVide(q)` | Aucun collègue ne correspond à « {q} ». |
| `echangeSeul` | Tu es seul dans ta caserne pour l'instant. |
| `echangeContinuer` | Continuer |
| `echangeChoisirQui` | Choisis un collègue ou toute la caserne. |
| `echangeQuoiTitre` | Céder ou échanger ? |
| `echangeCeder` | Céder |
| `echangeCederAide(nom)` | {nom} prend ta garde. Tu ne prends rien en retour. |
| `echangeEchanger` | Échanger |
| `echangeEchangerAide(nom)` | {nom} prend ta garde, et tu prends une des siennes. |
| `echangeSesGardes(nom)` | Les gardes à venir de {nom} |
| `echangeAucuneGarde(nom)` | {nom} n'a pas de garde à venir à échanger. |
| `echangeGardeEngagee` | Déjà dans une demande en cours |
| `echangeChoisirGarde` | Choisis la garde que tu prends en retour. |
| `echangeVerifierTitre` | Vérifie ta demande |
| `echangeTuDonnes` | Tu donnes |
| `echangeTuPrends` | Tu prends |
| `echangeA` | À |
| `echangeLesDisponibles` | Les collègues disponibles ce créneau |
| `echangeInfoValidation(nom)` | Ton chef de centre devra valider après l'accord de {nom}. |
| `echangeInfoValidationCaserne` | Ton chef de centre devra valider après l'accord d'un collègue. |
| `echangeInfoAuto(nom)` | Si {nom} s'était dite disponible ce créneau, l'échange sera validé dès son accord. Sinon, ton chef de centre validera. |
| `echangeExpireLe(date, heure)` | La demande expire le {date} à {heure}. |
| `echangeEnvoyer` | Envoyer la demande |
| `echangeEnvoyeeA(nom)` | Demande envoyée à {nom}. |
| `echangeEnvoyeeCaserne` | Demande envoyée aux collègues disponibles. |
| `echangeEnvoiEchec` | Ta demande n'est pas partie. Vérifie le réseau et réessaie. |
| `echangeEnvoiRefuse(cause)` | Ta demande n'a pas pu partir : {cause}. |
| `echangeEnvoiRefuseAide` | Le récapitulatif est resté là : change de collègue ou de garde et réessaie. |
| `echangeTropTard(date, heure)` | Trop tard pour proposer un échange : la demande devait partir avant le {date} à {heure}. |
| `echangeHorsLigneRaison` | Une demande d'échange a besoin du réseau. |
| `echangeLectureSeuleRaison` | Caserne suspendue : les échanges sont bloqués. Contacte ton chef de centre. |
| `echangeEnCoursMention` | Échange en cours |
| `echangeSection(n)` | Échanges · {n} |
| `echangeVoirTous(n)` | Voir les {n} échanges |
| `echangeDetailTitreEchange(creneau)` | Échange de la {creneau} | 
| `echangeDetailTitreCession(creneau)` | Cession de la {creneau} |
| `echangeFilDemandee(date)` | Demandée le {date} |
| `echangeFilAcceptee(nom, date)` | Acceptée par {nom} le {date} |
| `echangeFilValidee(nom, date)` | Validée par {nom} le {date} |
| `echangeFilValideeAuto(date)` | Validée automatiquement le {date} |
| `echangeFilRefusee(nom, date)` | Refusée par {nom} le {date} |
| `echangeFilAnnulee(date)` | Annulée le {date} |
| `echangeFilExpiree(date)` | Expirée le {date} |
| `echangeFilEchec(date)` | Échec le {date} |
| `echangeAnnuler` | Annuler la demande |
| `echangeAnnulerTitre` | Annuler ta demande ? |
| `echangeAnnulerTexteCollegue(nom, creneau)` | {nom} sera prévenue. Ta garde du {creneau} reste la tienne. |
| `echangeAnnulerTexteCaserne` | Les collègues qui la voyaient ne la verront plus. Ta garde reste la tienne. |
| `echangeAnnulerTexteAcceptee(nom)` | {nom} avait accepté. Elle et ton chef de centre seront prévenus. Ta garde reste la tienne. |
| `echangeGarder` | Garder la demande |
| `echangeAnnulee` | Demande annulée. |
| `echangeAnnulerTropTard` | Trop tard : l'échange vient d'être validé. |
| `echangeFermer` | Fermer |

Accord grammatical : « prévenue / prévenu », « dite / dit » suivent le genre **inconnu** du
collègue. **[H]** Le profil ne porte pas de genre : la forme par défaut est le masculin générique
(« sera prévenu », « s'était dit disponible »), et les exemples féminins ci-dessus illustrent
seulement le cas de Chloé. Pas d'écriture inclusive à points médians (lecture au soleil).

### 10.2 États (badges et détails)

| Clé | Texte |
|---|---|
| `echangeEtatAttenteDe(nom)` | En attente de {nom} |
| `echangeEtatCherche` | Cherche un remplaçant |
| `echangeEtatAValider` | À valider par le chef |
| `echangeEtatValide` | Validé |
| `echangeEtatRefuse` | Refusé |
| `echangeEtatAnnule` | Annulé |
| `echangeEtatExpire` | Expiré |
| `echangeEtatEchec` | N'a pas pu se faire |
| `echangeDetailEnvoyee(depuis, date, heure)` | Envoyée {depuis}. Expire le {date} à {heure}. |
| `echangeDetailVisibleDispos(date, heure)` | Visible des collègues disponibles ce créneau. Expire le {date} à {heure}. |
| `echangeDetailAccepteParPourA(nom, depuis)` | {nom} a accepté {depuis}. Ton chef de centre doit valider. |
| `echangeDetailTuAsAccepte(depuis)` | Tu as accepté {depuis}. Ton chef de centre doit valider. |
| `echangeDetailRetractation` | Pour revenir sur ton accord, contacte ton chef de centre. |
| `echangeDetailValidePourA(nom, date, repreneur)` | Validé par {nom} le {date}. {repreneur} assure cette garde. |
| `echangeDetailValidePourB(nom, date)` | Validé par {nom} le {date}. C'est ta garde. |
| `echangeDetailValideAuto(date)` | Validé automatiquement le {date}. |
| `echangeDetailRefusePair(nom)` | {nom} a refusé. |
| `echangeDetailTuAsRefuse` | Tu as refusé. |
| `echangeDetailRefuseChef(nom)` | Refusé par {nom}. |
| `echangeDetailRefuseChefMotif(nom, motif)` | Refusé par {nom} : « {motif} » |
| `echangeDetailAnnuleParA` | Tu as annulé ta demande. |
| `echangeDetailAnnulePourB(nom)` | {nom} a annulé sa demande. |
| `echangeDetailExpirePourA` | Personne n'a répondu à temps. Ta garde reste la tienne. |
| `echangeDetailExpire` | Cette demande a expiré. |
| `echangeDetailEchecPourA(cause)` | L'échange n'a pas pu se faire : {cause}. Ta garde reste la tienne. |
| `echangeDetailEchec(cause)` | L'échange n'a pas pu se faire : {cause}. |

Causes (insérées dans les phrases ci-dessus) :

| Clé | Texte |
|---|---|
| `echangeCauseGardeChangee` | la garde a changé entre-temps |
| `echangeCauseDejaPris(nom)` | {nom} est déjà pris sur ce créneau |
| `echangeCausePlafondAstreintes(nom)` | {nom} a atteint son maximum d'astreintes du mois |
| `echangeCausePlafondWeekends(nom)` | {nom} a atteint son maximum de weekends du mois |
| `echangeCauseInactif(nom)` | {nom} n'est plus membre de la caserne |
| `echangeCauseSuspendue` | la caserne est en lecture seule |
| `echangeCauseCommence` | le créneau a commencé |
| `echangeCauseAutre` | la situation a changé entre-temps |

### 10.3 Pompier B

| Clé | Texte |
|---|---|
| `echangeGroupeRecues(n)` | Demandes de collègues · {n} |
| `echangeLigneCession(nom)` | {nom} te propose sa garde |
| `echangeLigneEchange(nom, garde)` | {nom} te propose un échange contre ton {garde} |
| `echangeLigneReprendre(nom)` | À reprendre · {nom} cherche un remplaçant |
| `echangePanneauTitreEchange(nom)` | Échange proposé par {nom} |
| `echangePanneauTitreCession(nom)` | Garde proposée par {nom} |
| `echangePanneauTitreReprendre(nom)` | {nom} cherche un remplaçant |
| `echangePanneauExpire(depuis, date, heure)` | {depuis} · expire le {date} à {heure} |
| `echangePanneauInfo` | Ton chef de centre validera après ton accord. |
| `echangePanneauInfoReprendre` | Le premier qui accepte la prend. Ton chef de centre validera ensuite. |
| `echangeAccepterGarde` | Accepter la garde |
| `echangeAccepterEchange` | Accepter l'échange |
| `echangeJeLaPrends` | Je la prends |
| `echangeRefuser` | Refuser |
| `echangeAccordEnvoye` | Accord envoyé. Ton chef de centre doit valider. |
| `echangeAccordValide(creneau)` | C'est fait : la garde du {creneau} est à toi. |
| `echangeRefusEnvoye(nom)` | Refus envoyé à {nom}. |
| `echangeDejaReprise` | Cette garde a déjà été reprise par un collègue. |
| `echangeAnnuleeParA(nom)` | {nom} a annulé sa demande. |
| `echangeExpiree` | Cette demande a expiré. |
| `echangePlusOuverte` | Cette demande n'est plus ouverte. |
| `echangeTonPlafondAstreintes` | Tu as atteint ton maximum d'astreintes du mois : tu ne peux pas accepter. |
| `echangeTonPlafondWeekends` | Tu as atteint ton maximum de weekends du mois : tu ne peux pas accepter. |
| `echangeTuEsDejaPris` | Tu es déjà de garde sur ce créneau : tu ne peux pas accepter. |
| `echangeReponseHorsLigne` | Une réponse a besoin du réseau. Elle repartira dès qu'il revient. *(réemploi de `propositionsHorsLigneRaison`)* |
| `echangeReponseEchec` | Ta réponse n'est pas partie. *(réemploi de `propositionsEchecTitre`)* |

Sémantique des rangées : `echangeRangeeSemantique(verbe, date, creneau, debut, fin)` → « Tu donnes :
mardi 15 octobre, jour, de 07:00 à 19:00 ».

### 10.4 Admin

| Clé | Texte |
|---|---|
| `echangesTitre` | Échanges d'astreintes |
| `echangesLien` | Échanges d'astreintes |
| `echangesFiltreAValider(n)` | À valider · {n} |
| `echangesFiltreEnAttente(n)` | En attente d'un collègue · {n} |
| `echangesFiltreTermines` | Terminés |
| `echangesAnnonceFiltre(n)` | {n} échanges à valider |
| `echangesBlocSuivi(n)` | {n} échange à valider / {n} échanges à valider |
| `echangesBlocSuiviAction` | Voir les échanges |
| `echangesVideAValiderTitre` | Aucun échange à valider |
| `echangesVideAValiderTexte` | Quand un pompier accepte de reprendre la garde d'un collègue, la demande arrive ici. |
| `echangesVideEnAttente` | Aucune demande en attente d'un collègue. |
| `echangesVideTermines` | Aucun échange terminé ces 30 derniers jours. |
| `echangesErreur` | Impossible de charger les échanges. |
| `echangesReessayer` | Réessayer |
| `echangesLigneCede(a, b)` | {a} cède à {b} |
| `echangesLigneEchange(a, b)` | {a} échange avec {b} |
| `echangesLigneCession(depuis, date, heure)` | Cession · accepté {depuis} · expire {date} {heure} |
| `echangesLigneContre(garde)` | Échange contre le {garde} |
| `echangesPanneauTitreCession(creneau)` | Cession · {creneau} |
| `echangesPanneauTitreEchange(creneau)` | Échange · {creneau} |
| `echangesCede(nom)` | {nom} cède |
| `echangesChargeTitre` | Charge après l'échange |
| `echangesLibere` | libère cette garde |
| `echangesDepasseAstreintes(max)` | Dépasserait son maximum d'astreintes ({max}). |
| `echangesDepasseWeekends(max)` | Dépasserait son maximum de weekends ({max}). |
| `echangesDispoDeclaree` | Disponibilité déclarée |
| `echangesPrisAilleurs` | Déjà de garde ailleurs sur ce créneau. |
| `echangesValider` | Valider l'échange |
| `echangesValiderCession` | Valider la cession |
| `echangesRefuser` | Refuser |
| `echangesConfirmerValiderTitre` | Valider l'échange ? / Valider la cession ? |
| `echangesConfirmerCession(creneau, a, b)` | La {creneau} passe de {a} à {b}. Les deux seront prévenus. |
| `echangesConfirmerEchange(c1, b, c2, a)` | La {c1} passe à {b}, et le {c2} à {a}. Les deux seront prévenus. |
| `echangesValiderEtPrevenir` | Valider et prévenir |
| `echangesRevenir` | Revenir |
| `echangesRefuserTitre` | Refuser l'échange ? |
| `echangesRefuserTexte(a, creneau, b)` | {a} garde sa {creneau}. {a} et {b} seront prévenus. |
| `echangesMotif` | Motif (facultatif) |
| `echangesMotifAide` | Il sera envoyé aux deux pompiers. |
| `echangesRefuserEtPrevenir` | Refuser et prévenir |
| `echangesValide(a, b)` | Échange validé. {a} et {b} seront prévenus. |
| `echangesRefuse(a, b)` | Échange refusé. {a} et {b} seront prévenus. |
| `echangesEchec(cause)` | L'échange n'a pas pu se faire : {cause}. Rien n'a changé dans le planning. |
| `echangesHorsLigneRaison` | Une décision a besoin du réseau. |
| `echangesLectureSeuleRaison` | Caserne suspendue : les échanges sont bloqués. |
| `echangesReserveAdmin` | Cet écran est réservé aux administrateurs de la caserne. |

### 10.5 Réglages

| Clé | Texte |
|---|---|
| `parametresEchangesTitre` | Échanges d'astreintes |
| `parametresEchangesAuto` | Valider automatiquement |
| `parametresEchangesAutoAide` | Quand le collègue qui reprend s'était dit disponible ce créneau, l'échange est validé dès son accord. Tu es seulement prévenu. Sinon, il attend ta validation. |
| `parametresEchangesEcheance` | Fin des demandes |
| `parametresEchangesEcheanceSuffixe` | heures avant le créneau |
| `parametresEchangesEcheanceErreur` | Entre 1 et 168 heures. |

### 10.6 Notifications (titre · corps), pour `send-notification`

| Événement | Destinataire | Titre | Corps |
|---|---|---|---|
| demande à un collègue | B | Demande d'échange | {A} te propose sa {créneau}. *(échange : « {A} te propose un échange : sa {créneau A} contre ton {créneau B}. »)* |
| demande à la caserne | disponibles | Garde à reprendre | {A} cherche un remplaçant pour la {créneau}. |
| accord de B | admins actifs | Échange à valider | {B} accepte de reprendre la {créneau} de {A}. |
| validation | A et B | Échange validé | La {créneau} est maintenant assurée par {B}. *(échange : les deux gardes)* |
| validation automatique | admins | Échange validé automatiquement | {B} reprend la {créneau} de {A}. Il s'était dit disponible. |
| refus de B | A | Échange refusé | {B} ne peut pas reprendre ta {créneau}. |
| refus admin | A et B | Échange refusé | {admin} a refusé l'échange de la {créneau}. *(+ « « {motif} » » s'il existe)* |
| annulation | B, ou B et admins si déjà accepté | Demande annulée | {A} a annulé sa demande pour la {créneau}. |
| expiration | A | Demande expirée | Personne n'a repris ta {créneau}. Elle reste la tienne. |
| échec | A et B | Échange impossible | L'échange de la {créneau} n'a pas pu se faire : {cause}. |

`{créneau}` s'écrit « nuit du samedi 12 octobre » / « jour du mardi 15 octobre ».

## 11. Contraintes et décisions ouvertes

**Contraintes de construction :**

- **Fraîcheur (070)** : une nouvelle `Donnee.echanges`. Toute action d'échange relit `echanges`,
  `astreintes`, `propositions` (la Boîte et l'accueil), et côté admin `suivi` et `planningAdmin`.
  Un push d'échange reçu au premier plan relit `echanges` et `propositions`.
- **Plusieurs casernes (072)** : tout est dans la caserne courante. Un push d'échange d'une autre
  caserne bascule de caserne avec le bandeau du 072, puis ouvre l'écran.
- **Caches locaux** : si la liste des échanges est gardée pour la lecture hors ligne, elle porte
  des noms de tiers et **doit** être branchée dans `OubliLocal` (`lib/core/session/oubli_local.dart`),
  effacée par préfixe caserne/membre. Le repli sur le cache ne couvre qu'une panne de réseau. Aucune
  action d'échange ne part d'une file locale : comme une réattribution, elle fait sonner un
  téléphone (`design/020 § 6.5`).
- **Charges utiles** : appels de fonctions avec arguments construits à la main, jamais un
  `toJson()` de modèle (leçon du 021 § 3).
- **Une seule `AppBanner` à la fois**, ordre de priorité inchangé.

**Décisions ouvertes, à valider par le propriétaire** (le brief applique la colonne « hypothèse »
en attendant) :

| # | Question | Hypothèse du brief |
|---|---|---|
| 1 | B peut-il se rétracter après avoir accepté, avant la validation ? | Non ; il passe par le chef. |
| 2 | Un disponible peut-il « refuser » une demande à la caserne pour la faire disparaître de sa Boîte ? | Non ; elle disparaît quand elle est prise ou expire. |
| 3 | B doit-il donner un motif quand il refuse ? | Non. |
| 4 | Le motif de refus de l'admin est-il obligatoire ? | Facultatif, comme l'annulation du 020. |
| 5 | Le plafond dépassé grise-t-il « Valider » (règle du ticket) ou seulement avertit-il (principe produit 4) ? | Grisé : le ticket fait du plafond une condition de la validation. |
| 6 | Combien de temps une demande terminée reste-t-elle visible pour A et B ? | Tant que le créneau est à venir. Admin : 30 jours. |
| 7 | Le compte « Propositions · N » de l'accueil inclut-il les demandes d'échange ? | Oui. |
| 8 | Une garde de B déjà engagée dans une autre demande peut-elle être choisie en retour ? | Listée, grisée. Dépend du contrat. |
| 9 | L'admin peut-il annuler la demande d'un pompier ? | Non. |
| 10 | Bornes de l'échéance réglable. | 1 à 168 heures, défaut 24. |
| 11 | Accord en genre dans les phrases (le profil n'a pas de genre). | Masculin générique. |

**Point bloquant côté contrat** : § 9, point 4. Sans lecture des gardes à venir de B, « Échanger »
se réduit à « Céder » sur un planning publié non validé.

## 12. Widgets Flutter

**À réutiliser (`lib/core/widgets/`)** : `AppScaffold` (`fondDoux`, `panneauLateral`,
`filActions`, `banniere`), `CarteDouce`, `CarreCreneau`, `EnteteSection.discret`, `StatusBadge`
(`.descripteur`), `PrimaryButton` (primaire, secondaire, danger), `BoutonRetour`, `ChampTexte`,
`AvatarInitiales`, `EmptyState`, `LoadingSkeleton`, `AppBanner`, `SlotChip` (compacte, inerte,
pour la disponibilité déclarée), `BarreActionsBasse`, `AppDivider`. Côté feature, réemployer les
formes de `PanneauReponse` (asymétrie, seuil 350), `ConfirmationReattribution` (feuille/dialogue
de confirmation nommée), `FiltresSuivi`, `LigneCandidat` (format de charge), `ChampNombre`.

**À créer dans `lib/core/widgets/`** (car partagés par plusieurs features) :

- **`ChoixExclusif`** — rangée de choix exclusif, 56 dp minimum (64 avec ligne d'aide), icône à
  gauche, titre `corps` gras, aide `corps-secondaire`, `Icons.check_circle` + fond
  `primary-container` quand choisi, filet 1 dp sinon, raison écrite dessous quand inerte.
  `Semantics(selected:, inMutuallyExclusiveGroup: true, button: true)`. Sert aux étapes 1 et 2,
  à la liste des collègues et à celle des gardes.
- **`RangeeGarde`** — la rangée « verbe + carré + date + heures » de la paire de gardes, avec
  l'icône de sens ; une phrase sémantique complète.

**À créer dans `lib/features/echanges/`** (`data`, `domain`, `presentation`) :

- `domain` : `Echange` (statut, forme, mode, gardes, acteurs, horodatages, cause), `EtatEchange`
  et son `StatusDescriptor` (§ 5.3, aucune encre nouvelle), `CauseEchange` et sa traduction,
  `EchangesController`, `FileEchangesController` (admin).
- `presentation` : `DemandeEchangeScreen` (étapes, étape dans l'URL), `CarteEchange`,
  `DetailEchange` (+ `ouvrirDetailEchange` : feuille / dialogue), `ConfirmationAnnulationEchange`,
  `SectionEchanges` (tête des Astreintes), `CarteDemandeRecue` (variante de `CarteProposition`),
  `PanneauEchange`, `EchangesAdminScreen`, `LigneEchangeAdmin`, `PanneauDecisionEchange`,
  `ChargeApresEchange`, `ConfirmationDecisionEchange` (valider / refuser avec motif),
  `BlocEchangesSuivi`, `SqueletteEchanges`.
- Modifiés : `feuille_astreinte.dart` (bouton ou carte par créneau), `ligne_astreinte.dart`
  (mention), `astreintes_screen.dart` (section), `boite_screen.dart` et `composition_boite.dart`
  (groupe, tri, exclusion de « Rappels »), `composition_accueil.dart` (compte), `suivi_screen.dart`
  (bloc), `matrice_screen.dart` (lien et menu), `formulaire_parametres.dart` (groupe),
  `destination_push.dart` (liens), `fraicheur.dart` (`Donnee.echanges`), `/dev/components`
  (`ChoixExclusif`, `RangeeGarde`, `CarteEchange` dans ses huit états).

## 13. Disposition par largeur

| | 390 (compact) | 768 (medium) | 1280 (large) |
|---|---|---|---|
| Demande (A) | écran poussé plein, bouton épinglé en bas | colonne ≤ 720 centrée, rail à gauche | colonne 560 centrée dans la zone de travail, bouton sous le contenu (pas de fil plein écran) |
| Détail d'un échange | feuille de bas d'écran | feuille | dialogue 480 |
| Réponse (B) | feuille de bas d'écran, boutons empilés si < 350 | feuille | volet latéral 360, étendu, boutons empilés |
| File admin | liste, panneau en feuille | liste, panneau en feuille | liste + panneau 360 à droite, première ligne ouverte |

À ×1,6 d'échelle de texte, rien ne tronque : les rangées de garde passent sur deux lignes (date,
puis créneau et heures), les filtres admin s'enroulent (`Wrap`), les deux boutons s'empilent.

## 14. Checklist `craft-floor` (Impeccable)

- [x] **Contraste** : aucune paire nouvelle. Badges, blocs et textes réemploient des descripteurs
  déjà mesurés dans `contraste_test.dart`. À vérifier quand même : `etat-attente-sur-fond` dans le
  bloc du Suivi (déjà mesuré au 023).
- [x] **Profondeur** : aucune ombre nouvelle ; feuilles et dialogues au niveau 3 existant ; cartes
  au filet.
- [x] **Espacement** : 24 au-dessus d'un titre, 8 dessous ; 8 entre deux cibles ; 8 entre deux
  cartes (`§ Écarts 064c`).
- [x] **Typographie** : Archivo seulement à 18 et plus (titres d'écran, de feuille, de bloc) ;
  Atkinson pour tout le reste ; chiffres de charge et heures en Atkinson Mono, figures tabulaires.
  Texte réel à 390 et ×1,6 à éprouver avec les vraies polices (`test/support/polices.dart`) :
  « Accepter l'échange » dans le volet de 360 ; « En attente d'un collègue · 12 » dans les filtres.
- [x] **Mouvement** : un seul moment, le tampon existant sur « Validé ». Reduce Motion respecté.
- [x] **États** : vide, chargement, erreur, hors ligne, suspendue, disparu, échec, 60 membres —
  tous au § 5.4. Pas de survol requis ; focus visible sur chaque `ChoixExclusif`.
- [x] **Surfaces du navigateur** : rien de nouveau (sélection, curseur, anneau de focus déjà
  réglés par le thème).
- [x] **Textes** : chaque bouton nomme son action (« Envoyer la demande », « Valider et
  prévenir »), chaque erreur nomme la cause et la sortie. Pas de « OK », pas de « Êtes-vous sûr ».
- [x] **Couverture** : les trois parcours du ticket, les sept états, le réglage, les liens.
- [x] **Refus** : pas de cartes icône-titre-texte comme structure de page (les cartes d'échange sont
  des données, la section est une liste) ; pas de surtitre ; pas de numéros de section à l'écran
  (« Étape 1 sur 3 » est un texte, pas un décor) ; pas de modale sans protection (seules
  l'annulation, la validation et le refus en ouvrent une, trois gestes qui sortent de l'app) ;
  pas de filet coloré à gauche ; pas d'emoji ni de glyphe Unicode comme icône.

## 15. Checklist app mobile (ui-ux-pro-max)

- [x] **Cibles tactiles** : 48 dp visés, 44 au plancher ; rangées de choix 56–64 ; boutons 52 ;
  ligne admin 56 au moins en compact.
- [x] **Écart entre cibles** : 8 dp minimum ; aucun bouton sur les lignes de liste du pompier.
- [x] **Navigation** : cinq destinations au plus, inchangées ; nouvel écran admin derrière les
  liens existants ; parcours de demande en route poussée, étape dans l'URL, retour fonctionnel.
- [x] **Liens profonds** : adresses à jour à chaque changement d'étape, d'onglet et de filtre.
- [x] **Confirmation avant irréversible** : annuler, valider, refuser. Pas de confirmation sur ce
  qui se défait ou ne coûte rien (accepter, refuser côté B, envoyer — annulable).
- [x] **Retour après action** : message passager de 8 s après chaque geste ; chargement intégré au
  bouton.
- [x] **Erreurs avec sortie** : chaque refus de la base a sa phrase et son geste suivant ; annoncé
  (`liveRegion`).
- [x] **États vides** : chacun explique et, quand une sortie existe, la propose.
- [x] **Compte annoncé** : « 2 échanges à valider », jamais « 2 » seul ; un seul compte vivant par
  écran.
- [x] **Zones sûres iOS en PWA** : écran poussé en `SafeArea(top: false)`, fil d'actions au-dessus
  de la barre d'accueil ; aucun glissement dans les 24 premiers dp du bord gauche.
- [x] **Listes longues** : `ListView.builder` / slivers pour les collègues et la file admin.
- [x] **Accessibilité** : `Semantics` sur chaque carte (phrase complète : « Échange de la nuit du
  samedi 12 octobre, en attente de Chloé C. »), choix exclusifs `selected`, décoratifs exclus.
- [x] **Jamais la couleur seule** : marque + icône + libellé pour chacun des huit badges ; vérifié
  en niveaux de gris par paires de même famille (§ 5.3).
- [x] **Gants et soleil** : aucun geste caché, aucune cible sous 44, thème clair par défaut,
  textes ≥ 14 pour toute information, 16 pour le corps.
