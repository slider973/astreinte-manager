# 027 — Écran « Mes astreintes »

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web**,
Material 3, une seule apparence. Il est le pendant de `design/021-ecran-propositions.md` :
le 021 livre l'écran où l'on **répond**, celui-ci livre l'écran où l'on **consulte** ce qu'on a
répondu. Une proposition acceptée quitte le 021 et arrive ici — c'était déjà un critère
d'acceptation du 021.

`DESIGN.md` gagne sur ce brief pour toute valeur de token. Les écarts demandés sont au § 9, les
écarts constatés à l'implémentation au § 11.

Sources : `docs/PRD.md § 5.5`, `§ 6.4`, `§ 7.1` ; `docs/SCHEMA.md § 2.1`, `§ 2.8` à `§ 2.10`,
`§ 4` (RLS d'`assignments`) ; `docs/WORKFLOWS.md § 2`, `§ 3`, `§ 8` ;
`design/011-saisie-dispos-grille.md` (la file gardée sur l'appareil) ;
`design/021-ecran-propositions.md` ; `tickets/in-progress/027-mes-astreintes.md`.

---

## 1. Job et audience

**Le pompier volontaire, un jeudi soir, devant son frigo, en train de dire à quelqu'un s'il est
libre samedi.** Il ouvre l'application pour une seule raison : **savoir quand il est
d'astreinte**. Il ne veut ni répondre, ni saisir, ni comprendre : il veut lire une date.

C'est l'écran que ce produit affichera le plus souvent une fois le planning validé. Les autres
écrans se visitent une fois par mois — la saisie au 011, la réponse au 021, la construction au
016. Celui-ci se visite le mardi, le jeudi, le samedi matin, et tous les soirs de la semaine où
il y a un doute.

**Et il se visite souvent sans réseau.** Une caserne est un bâtiment de béton dans une zone
rurale ; une remise n'a pas de couverture ; un sous-sol non plus. Un écran de consultation qui
répond « Impossible de charger » dans la caserne elle-même n'a pas d'excuse : la réponse était
déjà connue la veille, et elle n'a pas changé.

Une seule audience, une seule question : **« suis-je d'astreinte, et quand ? »** Une question
secondaire, qui n'arrive qu'une fois le planning validé : **« avec qui ? »**

## 2. Résultat et preuve

**Résultat.** La prochaine astreinte est lisible **sans défiler, sans toucher, sans réseau**.

**Preuve, dans l'ordre :**

1. À l'ouverture, la première ligne de l'écran est la **prochaine** astreinte. Pas un en-tête de
   mois, pas un filtre, pas un onglet à choisir.
2. Avion activé, application rouverte : l'écran affiche les mêmes dates, avec un bandeau qui dit
   **quand** ces données ont été lues. Rien n'est vide, rien n'accuse le réseau d'être coupable.
3. Le passé ne coûte rien à celui qui regarde l'avenir : il est là, replié, compté, et il s'ouvre
   d'une touche.
4. Les autres membres du créneau apparaissent **exactement** quand la base les rend, c'est-à-dire
   quand le planning est `validated`. Tant qu'il est `published`, l'écran dit pourquoi ils ne sont
   pas là plutôt que de montrer une liste vide.
5. Les heures affichées (« 19:00 → 07:00 ») viennent des paramètres de **cette** caserne, jamais
   d'un 7 h – 19 h écrit en dur.

**Ce que la base fait toute seule, et qu'il ne faut pas réimplémenter.** La RLS d'`assignments`
(`docs/SCHEMA.md § 4`) dit tout : « membre : les siennes si schedule publié ; **tous les membres
si validé** ». Il n'y a donc aucune règle de visibilité à écrire côté client — seulement une
seconde ceinture, explicite, et une phrase à afficher quand la règle mord.

## 3. La contrainte qui gouverne tout : l'écran doit répondre hors réseau

Ce n'est pas une option de confort, c'est **la** règle d'architecture de cet écran, et elle décide
de la forme du code comme la charge utile décidait de celle du 021.

La conséquence est que **la source de vérité de l'affichage n'est pas la requête, c'est le
cache**. Le contrôleur ouvre toujours sur ce qu'il a gardé, puis va chercher mieux :

```
build() → lire le cache (synchrone à l'échelle humaine) → afficher
       → lire le réseau → si ça réussit : remplacer + réécrire le cache
                        → si ça échoue  : garder l'affichage + poser le bandeau de fraîcheur
```

Trois conséquences non négociables :

- **Un échec de lecture ne remplace jamais un contenu par une erreur.** `EmptyState.erreur`
  n'apparaît que si le cache est vide **et** la requête a échoué. C'est le seul cas où l'écran
  n'a rien à dire.
- **Le cache porte tout ce que l'écran affiche**, y compris les heures d'affichage de la caserne
  et les noms des équipiers. Un cache qui garderait les dates mais pas les heures produirait un
  détail à moitié vide hors ligne, ce qui est pire qu'un détail absent.
- **Le cache est daté.** Sans horodatage, le bandeau ne peut pas dire « ces données datent d'hier
  18 h 42 », et un bandeau qui dit seulement « données peut-être anciennes » n'apprend rien.

**Le rangement est celui du ticket 011.** `FileLocalePartagee` garde la file d'écriture des
disponibilités dans `shared_preferences` — `localStorage` sur le web — sous une clé préfixée par
domaine (`dispos.file.<station>.<user>.<mois>`), et **avale toute panne de stockage** : navigation
privée, quota plein, document illisible après une mise à jour. On reprend la même mécanique,
le même préfixage, la même politique d'échec silencieux, sous `astreintes.cache.<station>.<user>`.
Une entrée par caserne et par membre : ce n'est pas une file, c'est un instantané, et il se
remplace en bloc.

**Ce qu'on ne fait pas :** aucun service worker de données, aucune base locale, aucun plugin. Le
service worker de la PWA sert la coquille ; les données de cet écran tiennent dans un document
JSON de quelques kilo-octets et `shared_preferences` a déjà une implémentation web.

## 4. La place dans la navigation — la décision demandée par le ticket

`DESIGN.md § Navigation` fixe **cinq destinations au maximum**, et un administrateur les a toutes.
Le brief du ticket 004 notait que la décision serait à revoir à l'usage, ici. Elle est tranchée.

**Décision : la troisième destination devient « Astreintes », et cet écran est son contenu.**

| Avant (ticket 004) | Après (ce ticket) |
|---|---|
| `groups` / `groups_outlined` — « Planning » — écran de remplacement, vide | `event_available_outlined` / `event_available` — « Astreintes » — **« Mes astreintes »** |

Aucune destination ajoutée, aucune retirée, aucune renumérotée : « Mon mois » reste l'onglet 0,
« Propositions » l'onglet 1 avec sa pastille, « Profil » et « Admin » ne bougent pas. Le lien
public `/schedule/<période>` d'une notification `schedule_validated` mène déjà à l'onglet 2, et il
y mène désormais **à quelque chose**.

**Pourquoi cette destination-là, et pas une autre.**

1. **C'est la même question, posée à deux échelles.** « Quand suis-je d'astreinte » (027) et « qui
   est d'astreinte » (023) lisent la **même** table sous la **même** politique : mes attributions
   dès `published`, celles de tout le monde dès `validated`. Ce sont deux filtres d'une même vue,
   pas deux écrans. Les séparer en deux destinations demanderait à un pompier de savoir, avant de
   toucher, si la réponse qu'il cherche le concerne lui ou la caserne.
2. **Le ticket 023 s'y range sans rien déplacer** : il ajoutera un sélecteur à deux segments
   « Moi » / « La caserne » en tête de l'écran, et le mot « Astreintes » couvre déjà les deux.
   C'est pour ça que le libellé n'est ni « Mes astreintes » ni « Planning ».
3. **Rien d'autre ne pouvait céder sa place.** « Mon mois » est la seule porte de la saisie ;
   « Propositions » porte la pastille chiffrée, qui est le seul moyen d'apprendre qu'on doit
   répondre sans notification ; « Profil » porte la déconnexion, et l'enterrer derrière une icône
   de barre d'application coûterait un écran de sortie à qui prête son téléphone.
4. **L'icône `groups` mentait déjà.** Elle dit « les autres » sur une destination qui, pendant
   tout le temps où un planning reste `published`, ne montre que soi. `event_available` dit
   « une date retenue », ce qui est exactement le sujet.

**Coût du geste : une touche depuis n'importe quel écran de la coquille**, zéro depuis une
notification de planning validé. C'est mieux que les deux gestes que le ticket autorisait.

## 5. Périmètre et limites

**Livré :** la liste chronologique des astreintes **acceptées** à venir, groupée par mois ; le
repli des passées ; la vue calendrier mensuelle avec les jours marqués ; le détail d'une astreinte
(date, créneau, heures de la caserne, équipiers quand le planning est validé) ; le cache local
daté et son bandeau ; les états vide, chargement, erreur, hors ligne ; la destination de
navigation ci-dessus.

**Pas livré, et à ne pas esquisser :**

- **Le planning de la caserne** (ticket 023) : la vue « qui d'autre est d'astreinte ce mois-ci ».
  Cet écran ne montre les noms des autres **que sur les créneaux où le pompier est lui-même
  attribué**, et seulement quand le planning est validé.
- **L'export ICS et l'abonnement calendrier** (`docs/PRD.md § 5.5`), qui ne sont pas dans ce
  ticket.
- **Toute action sur une astreinte.** On ne refuse pas ici, on ne se fait pas remplacer ici, on
  n'échange pas ici. `accepted` n'a **aucune** transition ouverte à un membre
  (`docs/WORKFLOWS.md § 3` : la machine à états d'un membre va de `proposed` vers `accepted` ou
  `declined`, et s'arrête). Un bouton qui échouerait à tous les coups est pire que pas de bouton.
  Celui qui ne peut plus tenir sa garde appelle son chef, qui réattribue (ticket 020).
- **Les propositions en attente.** Elles vivent au 021 et nulle part ailleurs. Cet écran ne montre
  **que** du `accepted` : mélanger ce qui est acquis et ce qui attend une réponse est exactement
  la confusion que le découpage en deux écrans supprime.
- **Le temps réel.** Même raison qu'au 021 § 7.3, en plus fort : on consulte ici quarante
  secondes, et ce qu'on lit a été décidé il y a trois semaines.

**Anti-objectifs explicites :**

- **Pas de compte à rebours**, pas de « J-3 avant ta prochaine garde ». C'est de la décoration
  anxiogène : la date suffit, et le pompier sait compter.
- **Pas de carte.** `DESIGN.md § Cards / Containers` : une liste de blocs identiques faits d'une
  icône, d'un titre et d'un texte est interdite comme structure de page. Registre, filets, marge.
- **Pas de badge « Accepté » sur chaque ligne.** Tout ce que cet écran affiche est accepté ; un
  badge répété trente fois ne distingue rien de rien. L'état n'apparaît que là où il **varie** :
  dans le détail, sous forme de l'état du **planning** (publié / validé), qui, lui, change ce
  qu'on voit.
- **Pas de roue de chargement au milieu de l'écran**, ni au premier chargement ni au
  rafraîchissement : squelette à la forme du contenu, puis rafraîchissement silencieux par-dessus
  ce qui est déjà lisible.

## 6. États et plages de contenu

### 6.1 Plages réelles

| Grandeur | Minimum | Typique | Maximum retenu |
|---|---|---|---|
| Astreintes à venir | **0** | 3 à 6 | 62 (un mois entier pour une toute petite caserne) |
| Astreintes passées gardées | 0 | 20 | **plusieurs centaines** — l'historique n'est jamais supprimé (`docs/PRD.md § 7.6`) |
| Mois représentés à venir | 0 | 1 à 2 | 3 |
| Équipiers sur un créneau | 0 (on est seul) | 1 à 2 | 49 (`required_*` va jusqu'à 50) |
| Âge du cache au moment de la lecture | 0 s | quelques heures | **plusieurs semaines** |

Trois valeurs piègent.

**Zéro astreinte à venir est fréquent** — début de mois, planning pas encore publié, pompier peu
disponible ce mois-ci. L'état vide n'est pas un cas dégradé : il mérite le même soin que la liste.

**Les passées sont sans plafond.** L'historique n'est jamais supprimé, donc la liste des passées
peut atteindre plusieurs centaines de lignes après deux ans d'usage. Deux conséquences : la lecture
est **bornée côté serveur** (voir § 8.1), et la liste est virtualisée par construction.

**Quarante-neuf équipiers sont légaux.** La liste de noms du détail défile et ne présuppose ni deux
noms ni une ligne.

### 6.2 Les états de l'écran

| État | Ce qu'on voit |
|---|---|
| **Chargement, cache vide** | Squelette à la forme du contenu : un en-tête de mois, trois lignes. Jamais de roue centrée. |
| **Chargement, cache plein** | **Le cache**, tout de suite, sans squelette. La requête part derrière et remplace sans clignoter. |
| **Liste** | La composition du § 7. Un en-tête par mois, une ligne par astreinte, puis le repli des passées. |
| **Vide** | `EmptyState` `event_available_outlined`, « Aucune astreinte à venir », texte « Quand ton chef de centre publiera le planning et que tu auras accepté une astreinte, elle s'affichera ici. », action **« Voir mes propositions »** → onglet 1. |
| **Hors ligne, cache plein** | Bannière `horsLigne` **permanente**, texte « Hors ligne. » + détail « Dernière mise à jour hier à 18 h 42. » La liste reste entière et reste lisible. |
| **Hors ligne, cache vide** | `EmptyState.horsLigne` + « Réessayer ». C'est le seul cas où l'écran n'a rien. |
| **En ligne mais lecture échouée, cache plein** | Bannière `attention`, « Ces astreintes datent du 12 octobre. » + action « Réessayer ». Pas de rouge : rien n'est cassé, c'est juste vieux. |
| **En ligne, lecture échouée, cache vide** | `EmptyState.erreur` + « Réessayer ». |
| **Détail, planning validé** | La feuille du § 7.4 avec la liste des équipiers, ou « Tu es seul sur ce créneau. » quand il n'y en a pas. |
| **Détail, planning publié** | La même feuille, **sans** liste de noms, et une phrase qui dit pourquoi : « Les autres noms s'afficheront quand ton chef de centre aura validé le planning. » |
| **Pas de caserne / membre désactivé** | Le routeur a déjà tranché (`redirectionAuth`). Rien à prévoir ici. |

### 6.3 Ce que ces états ne font jamais

- **Aucun état ne remplace la liste par un message.** Une bannière se pose au-dessus, la liste
  reste. C'est la règle du 021 § 5.3, et elle compte double ici : la liste est la seule raison de
  venir.
- **Aucun bandeau n'accuse la connexion.** « Hors ligne » est un fait, ocre, pas rouge
  (`DESIGN.md § Hors ligne et synchronisation`). Rien n'est en attente d'envoi ici : l'écran ne lit
  que, donc la phrase parle de **fraîcheur**, pas de modifications à sauver.
- **Aucune ligne ne disparaît sous les yeux** au rafraîchissement. Si une astreinte a été annulée
  par le chef pendant la lecture, elle part au remplacement de la liste, et le pompier a été
  prévenu par un push (`assignment_cancelled`, `docs/WORKFLOWS.md § 8`) — ce n'est pas à cet écran
  de le lui apprendre en escamotant une ligne.

## 7. Interaction et layout

### 7.1 Deux vues, une bascule, et la liste par défaut

En tête d'écran, sous la barre d'application : **deux boutons de bascule**, « Liste » et
« Calendrier ». La liste est sélectionnée par défaut, partout, y compris sur grand écran.

Pourquoi la liste gagne : la question est « quand est la **prochaine** », et une liste triée répond
sans compter les cases. Le calendrier répond à une autre question, secondaire et réelle — « à quoi
ressemble mon mois », « est-ce que j'ai deux gardes le même week-end » — et il vaut le geste qu'il
coûte.

La bascule est composée comme les boutons du sélecteur de mois du ticket 011 : deux blocs à rayon
`controle`, le sélectionné en `secondary-container` avec `Icons.check` en tête, le non sélectionné
en `surface` avec un filet 1 dp. **Pas de `SegmentedButton` Material** : il est en gélule
(`StadiumBorder`), et `DESIGN.md § Shapes` proscrit la pastille sur un contrôle. Trois signaux pour
l'état sélectionné — la coche, le fond, le `Semantics(selected:)` — jamais la couleur seule.

Le choix de vue est un état d'écran, pas une route : on ne veut pas qu'un retour de navigateur
serve à revenir du calendrier à la liste, on veut qu'il sorte de l'écran.

### 7.2 La liste, et son ordre

```
┌────────────────────────────────────────────┐
│ Octobre 2026                               │
│ 2 astreintes                               │
├────────────────────────────────────────────┤
│  12  samedi 12 octobre        ◗ Nuit       │
│ sam. 19:00 → 07:00                         │
├────────────────────────────────────────────┤
│  19  samedi 19 octobre        ☀ Jour       │
│ sam. 07:00 → 19:00                         │
├────────────────────────────────────────────┤
│ Novembre 2026                              │
│ 1 astreinte                                │
├────────────────────────────────────────────┤
│   3  lundi 3 novembre         ☀ Jour       │
│ lun. 07:00 → 19:00                         │
├────────────────────────────────────────────┤
│ ▸  Astreintes passées (14)                 │
└────────────────────────────────────────────┘
```

**L'ordre des à venir est celui du calendrier** : date croissante, jour avant nuit. Le groupement
par mois est un `EnteteSection` (composant existant), qui défile avec le contenu et n'est pas
collant — même raison qu'au 021 § 6.1.

**L'ordre des passées est l'inverse.** La plus récente d'abord. On ne remonte pas le temps depuis
son entrée dans la caserne : on regarde en arrière depuis aujourd'hui. Les mois passés sont donc
en ordre décroissant, et les astreintes à l'intérieur aussi. C'est le seul endroit de l'application
où un tri est inversé, et c'est pour la même raison qu'un relevé bancaire commence par hier.

**La frontière entre passé et à venir est le jour, pas l'instant.** Une astreinte de nuit du jour
même reste « à venir » toute la journée : elle ne bascule pas dans les passées à 8 h du matin sous
prétexte que la nuit a commencé la veille au soir. La comparaison porte sur la **date** du créneau
contre la date d'aujourd'hui, à minuit local.

### 7.3 La ligne, signal par signal

Une ligne, deux zones, **et rien qui ne soit une information** :

1. **La marge du registre**, 48 dp : le numéro du jour en `nombre` (mono, chiffres tabulaires) et
   le jour de la semaine abrégé en `etiquette`, fond `surface-dim` pour un week-end ou un jour
   férié. C'est **exactement** la marge du ticket 011 et celle de la ligne de proposition du 021 :
   trois écrans, une seule marge, aucune variante à maintenir.
2. **Le corps** : la date en toutes lettres (« samedi 12 octobre ») en `corps`, un
   `StatusBadge.creneau` (icône `bedtime` ou `light_mode` + le mot), puis, en `mention`
   `on-surface-variant`, **les heures** : « 19:00 → 07:00 ».

La ligne entière est **actionnable** : elle ouvre le détail. C'est une différence assumée avec la
ligne de proposition du 021, qui est inerte parce qu'elle porte deux boutons irréversibles qu'un
gant déclencherait par accident. Ici, la ligne n'a qu'une seule destination, elle ne commet rien,
et l'ouvrir par erreur coûte un geste retour. Hauteur ≥ 64 dp, très au-dessus du plancher.

Le séparateur est un `AppDivider`. Aucune ombre, aucun fond, aucun rayon.

**Sémantique.** Chaque ligne est un bouton annoncé d'une phrase complète : « Samedi 12 octobre,
nuit, 19:00 à 07:00. Voir le détail. » Une liste de trente lignes qui annonceraient « Voir le
détail » trente fois est inutilisable.

### 7.4 Le repli des passées

Une seule ligne, pleine largeur, 52 dp, `Semantics(button: true, expanded: …)` :
**« Astreintes passées (14) »** précédée d'un chevron `expand_more` / `expand_less`.

- **Repliée par défaut, toujours.** L'écran s'ouvre sur l'avenir ; le passé est une consultation
  délibérée.
- Le compte est dans le libellé : un repli qui ne dit pas ce qu'il cache n'apprend rien, et ce
  nombre est lui-même une information (« j'ai fait 14 gardes cette année »).
- Le repli **n'existe pas** quand il n'y a rien derrière : un accordéon vide est un piège.
- Ouvert, il déroule les mois passés en `EnteteSection`, exactement comme les mois à venir. Les
  lignes passées sont **atténuées** (`on-surface-variant` pour la date, marge du registre sans
  fond de week-end) : ce sont des faits, pas des rendez-vous. Elles restent cliquables — leur
  détail est valable, et le nom d'un équipier d'octobre est parfois exactement ce qu'on cherche.

### 7.5 La vue calendrier

Sept colonnes, du lundi au dimanche, un mois à la fois, avec `‹ Octobre 2026 ›` en tête. Les
flèches sont deux `IconButton` de 48 dp, bornées à l'étendue réellement connue : du premier mois
qui porte une astreinte au dernier, et toujours le mois courant. Une flèche qui ne mène nulle part
est **désactivée avec sa raison**, pas cachée.

Chaque jour est un **bloc réglé** — filet 1 dp `outline-variant`, rayon `case`, aucune ombre :

| Ce qu'on voit | Comment |
|---|---|
| Le numéro du jour | `nombre-petit`, mono, tabulaire |
| Un jour sans astreinte | le numéro seul, sur `surface` (ou `surface-dim` le week-end) — **inerte, non focalisable** |
| Un jour d'astreinte | le numéro, puis **une marque par créneau** : l'icône du créneau (`light_mode` / `bedtime`) dans une case pleine à l'encre d'« accepté » (`#1A6B3A` clair, glyphe blanc) |
| Deux créneaux le même jour | deux marques empilées, jour au-dessus, nuit en dessous — l'ordre de la journée |
| Aujourd'hui | filet `primary` 2 dp sur le bord gauche, et « Aujourd'hui » en semantics |
| Un jour hors du mois affiché | atténué et inerte, il complète la semaine |

**Quatre signaux pour « je suis d'astreinte ce jour-là »** : la case est pleine (marque), elle
porte un glyphe (icône), sa sémantique le dit en toutes lettres (libellé), et elle est verte
(couleur, en quatrième). Une capture en niveaux de gris reste lisible : une case pleine sombre
contre une case vide blanche.

**Seuls les jours marqués sont actionnables**, et ils ouvrent le même détail que la liste. Un jour
vide n'a rien à montrer ; le rendre cliquable pour afficher « rien » est un faux affordance.

**Arithmétique de la grille, parce qu'elle décide de la faisabilité.** Le ticket 011 a refusé le
calendrier en compact : `7 × 48 + 6 × 8 = 384 dp` contre 328 disponibles sur un téléphone de 360.
Ici la contrainte est plus douce, parce que **la plupart des cases ne se touchent pas** : sur un
mois typique il y en a trois ou quatre d'actionnables. En ramenant la marge horizontale de la
grille à 8 et l'écart à 4, une case fait `(360 − 16 − 24) / 7 = 45,7 dp` de large sur le plus
petit téléphone visé et 49,9 sur un 390 — au-dessus du plancher de 44, et la hauteur est fixée à
au moins 56. Le calendrier tient donc en compact, et c'est ce qui permet de le proposer partout.

Au-delà de ×1,6 d'échelle de texte, la vue calendrier **change de forme** plutôt que de rogner :
elle bascule sur la liste, avec une phrase qui le dit (`DESIGN.md § Typography — Named Rules`).

### 7.6 Le détail d'une astreinte

Feuille de bas d'écran en compact, medium et expanded ; dialogue en large. Rayon `feuille`, scrim
32 %, élévation 3 — les valeurs de `DESIGN.md § Elevation`, et la mécanique exacte de
`demanderRefus` au 021 § 6.4.

```
│ Samedi 12 octobre 2026                     │
│ ◗ Nuit   19:00 → 07:00                     │
│ ─────────────────────────────────────────  │
│ Avec toi sur ce créneau                    │
│   Marie L.                                 │
│   Thomas B.                                │
│ ─────────────────────────────────────────  │
│ [ Fermer ]                                 │
```

- **Le titre est la date**, année comprise : c'est une feuille qu'on ouvre depuis un calendrier où
  l'année n'est plus à l'écran.
- Sous le titre, le `StatusBadge.creneau` et les heures de la caserne, ensemble : « Nuit,
  19:00 → 07:00 ». Les deux viennent de `stations.settings` (`day_start`, `day_end`,
  `docs/SCHEMA.md § 2.1`) — la nuit est l'intervalle complémentaire, `day_end → day_start`. **Rien
  n'est découpé par ces heures** : la colonne le dit, elles sont d'affichage. Elles répondent
  pourtant à la vraie question du pompier, « à quelle heure je prends ».
- **Les équipiers**, sous un titre de bloc « Avec toi sur ce créneau », un nom par ligne en
  `corps`. Le nom d'usage vient de `memberships.display_name`, avec repli sur le prénom et le nom
  de `profiles` — la même règle qu'au ticket 019, et la seule juste : le nom d'usage de la caserne
  n'est pas dans `profiles`.
- **Quand le planning est `published`**, ce bloc est remplacé par une `mention` : « Les autres noms
  s'afficheront quand ton chef de centre aura validé le planning. » C'est un fait de la RLS, écrit
  en français, à la place d'une liste vide qui se lirait « personne d'autre n'est de garde ».
- **Quand le planning est `validated` et qu'il n'y a personne d'autre** : « Tu es seul sur ce
  créneau. » C'est une information utile, pas une absence.
- Un seul bouton, secondaire : **« Fermer »**. Aucune action, parce qu'aucune n'est possible
  (§ 5). Retour matériel, geste retour iOS et `Échap` la ferment.
- Le détail **ne charge rien** : tout ce qu'il affiche a été lu avec la liste, donc il s'ouvre
  aussi vite hors ligne qu'en ligne. C'est la raison pour laquelle les équipiers sont lus d'avance
  (§ 8.1) plutôt qu'à l'ouverture de la feuille.

### 7.7 Points de rupture

| Classe | Composition |
|---|---|
| **compact** (< 600) | Une colonne, marge 16 (8 pour la grille du calendrier). `RefreshIndicator`. Détail en feuille de bas d'écran. |
| **medium** (600–839) | Colonne bornée à 720, centrée. Même liste, calendrier plus aéré (écart 6). |
| **expanded** (840–1199) | Colonne bornée à 720. Idem. |
| **large** (≥ 1200) | Idem, détail en dialogue. **Pas de panneau latéral permanent** : le détail d'une astreinte tient en six lignes et n'a aucune action ; un volet de 360 dp resterait vide l'essentiel du temps. |

Le rafraîchissement a **toujours** un équivalent visible au clavier : une action `refresh` dans la
barre d'application, à côté de la cloche. Le geste de tirage n'est jamais le seul chemin.

## 8. Décisions techniques qui sont des décisions de design

### 8.1 Ce qui est lu, et rien de plus

Trois requêtes à l'ouverture et à chaque rafraîchissement. Jamais `select *`.

1. **Mes attributions acceptées**, avec leur créneau et l'état de leur planning :
   `assignments` filtré sur `user_id`, `station_id`, `status = 'accepted'`, joint à
   `shifts!inner(id, date, slot, schedule_id, schedules!inner(id, status))`. Bornée : `date` ≥ il
   y a douze mois. **L'historique n'est pas supprimé, mais il n'a pas à être téléchargé** — au-delà
   d'un an, une astreinte n'intéresse plus personne et ce sont des centaines de lignes que le cache
   porterait à chaque ouverture.
2. **Les équipiers** : `assignments` filtré sur les `shift_id` de la première requête et
   `status = 'accepted'`. **La RLS fait le tri** : elle ne rend les lignes des autres que si le
   planning est validé. Une seconde ceinture, explicite côté client, écarte les créneaux dont le
   planning n'est pas `validated` — la même discipline que le filtre `proposed_at is null` du
   021 § 7.2, sur une donnée qui, montrée trop tôt, ferait croire à un planning figé.
3. **Les noms** : une lecture de `memberships` de la caserne — soixante lignes au plus — pour
   `display_name` et le repli `profiles`. C'est la requête du ticket 019, à l'identique.

Le tri est fait en Dart. L'ordre rendu par PostgREST n'est pas garanti, et le 021 l'a **mesuré**
sur la pile locale : trois attributions publiées dans la même transaction sont revenues 19, 24, 12.

### 8.2 Le cache, et ce qu'il garde exactement

Un document JSON par caserne et par membre, sous `astreintes.cache.<station>.<user>` :

```json
{
  "v": 1,
  "le": "2026-10-11T18:42:10.000Z",
  "jour": "07:00",
  "nuit": "19:00",
  "a": [
    {"id": "…", "c": "…", "p": "…", "d": "2026-10-12", "s": "night",
     "e": "validated", "m": ["Marie L.", "Thomas B."]}
  ]
}
```

- `v` est un **numéro de version de format**. Un document d'une version inconnue est ignoré, pas
  réparé : un cache illisible vaut un cache vide, et une migration de format pour un instantané
  qui se reconstruit en une requête serait du travail pour rien.
- `le` est l'horodatage de la **lecture réussie**, en UTC. C'est lui que le bandeau affiche, en
  relatif (« il y a 2 h », « hier ») via `formaterInstantRelatif`, qui dit la même chose ici qu'au
  021 sur l'ancienneté d'une proposition.
- `jour` et `nuit` sont les heures d'affichage de la caserne au moment de la lecture. Sans elles,
  le détail serait amputé hors ligne.
- Les noms sont **résolus** dans le cache, pas des identifiants : hors ligne, on n'a pas de table
  de correspondance à consulter.
- Toute panne de lecture ou d'écriture du stockage est **avalée**, exactement comme dans
  `FileLocalePartagee`. Perdre le cache est un défaut ; empêcher un pompier de lire son planning
  parce que son navigateur refuse le stockage en serait un vrai.
- Le cache est **écrit en entier à chaque lecture réussie**, et jamais autrement. Il n'y a pas de
  file, pas de fusion, pas de conflit : c'est un instantané du serveur, pas un brouillon local.

### 8.3 Le contrôleur est non auto-disposé, et il ne l'est pas pour une pastille

Contrairement à celui des propositions, celui-ci ne nourrit aucune pastille. Il reste néanmoins
non auto-disposé, pour une raison d'usage : **passer sur « Mon mois » et revenir ne doit pas
rejouer un squelette**. L'écran le plus consulté du produit doit être là instantanément au
deuxième passage, cache ou pas.

### 8.4 Pas de temps réel, et rafraîchissement au retour au premier plan

Trois déclencheurs de lecture, comme au 021 : l'ouverture, le geste de tirage (et son équivalent
clavier), et le retour de l'application au premier plan — posé par un `WidgetsBindingObserver`
**dans l'écran**, pas dans le contrôleur, pour ne pas relire depuis un autre onglet.

## 9. Écarts demandés à `DESIGN.md`

| Point | Ce que dit `DESIGN.md` | Ce que demande ce brief | Pourquoi |
|---|---|---|---|
| Destination 3 | `groups` / `groups_outlined`, « Planning », route `/planning` | `event_available_outlined` / `event_available`, **« Astreintes »**, route `astreintes` | § 4. Le compte reste à cinq, l'ordre ne bouge pas, et l'icône cesse de promettre « les autres » sur un écran qui ne montre que soi tant que le planning est publié. |
| Bannière `hors-ligne` | « Hors ligne. Tes modifications partiront au retour du réseau. » | « Hors ligne. » + détail « Dernière mise à jour hier à 18 h 42. » | Cet écran **n'écrit rien**. Promettre l'envoi de modifications inexistantes serait faux ; ce qu'il faut dire, c'est l'âge de ce qu'on lit. Même variante, même ocre, même icône. |
| Marge de page | 16 en compact | **8** pour la seule grille du calendrier | § 7.5. À 16, une case tombe à 43,4 dp sur un téléphone de 360, sous le plancher WCAG. La marge du reste de l'écran ne bouge pas. |
| Grille calendaire en compact | écart 011 : « le calendrier à sept colonnes reprend dès `expanded` » | le calendrier existe **aussi en compact**, sur demande explicite | L'écart du 011 vise une grille dont **les 62 cases** se touchent. Ici trois ou quatre cases sont actionnables et les autres sont du texte : l'arithmétique change, et la vue calendrier est une exigence du ticket. La liste reste la vue par défaut. |
| Bascule de vue | non traité | deux blocs à rayon `controle`, jamais un `SegmentedButton` | Le segmenté Material est en gélule ; `§ Shapes` proscrit la pastille sur un contrôle. La composition du sélecteur de mois du 011 existe déjà et tient les trois signaux. |

Aucun token nouveau. Aucune couleur nouvelle. Aucun composant de socle nouveau : le détail est une
composition de `StatusBadge`, `AppDivider` et `PrimaryButton` existants.

## 10. Critères d'acceptation, traduits en observables

1. Sans réseau, l'écran affiche les dernières données connues **et** un bandeau qui dit de quand
   elles datent. (Le critère du ticket.)
2. Une astreinte acceptée au ticket 021 apparaît ici, dans la liste et dans le calendrier. (Le
   critère laissé ouvert par le 021.)
3. Les astreintes à venir sont triées par date croissante, jour avant nuit, groupées par mois.
4. Les passées sont repliées par défaut, comptées dans leur libellé, et s'ouvrent d'une touche.
5. La vue calendrier marque les jours d'astreinte, un signe par créneau, et n'ouvre que ceux-là.
6. Le détail affiche les heures issues des paramètres de la caserne, pas des heures écrites en dur.
7. Le détail n'affiche les autres membres que si le planning est `validated` ; s'il est
   `published`, il affiche la phrase qui l'explique.
8. L'état vide explique et propose une action.
9. `flutter analyze` vierge, `flutter test` vert, `flutter build web` qui passe.

## 11. Écarts constatés à l'implémentation

> Rempli par `flutter-dev` après le code, et **après l'avoir regardé dans Chrome**. Ce qui est ici
> est la référence, pas ce qui précède.

| Point | Ce que disait ce brief | Ce que fait le code | Pourquoi |
|---|---|---|---|
| Lecture bornée à douze mois | « `date` ≥ il y a douze mois », énoncé comme une borne de requête | borne posée sur **`shifts.date`** via un filtre `gte` sur la table jointe (`shifts.date=gte.…`), pas sur `assignments` | `assignments` ne porte aucune date de créneau : la seule date qu'elle connaît est `proposed_at`, qui est celle de la publication, pas celle de la garde. Borner dessus aurait coupé un planning publié tôt pour un mois lointain. |
| Bascule de vue à grande échelle de texte | « au-delà de ×1,6 la vue calendrier bascule sur la liste » | seuil implanté à **×1,6 exactement** (`bascule si textScaler.scale(16) / 16 > 1.6`), et la bascule **désactive le bouton « Calendrier » avec sa raison** au lieu de rendre la liste sous un bouton qui dit « Calendrier » | Un bouton sélectionné qui montre autre chose que ce qu'il nomme est un mensonge ; un bouton désactivé qui dit pourquoi est un fait. |
| Détail « ne charge rien » | annoncé comme une propriété de l'écran | tenu : la feuille reçoit l'objet `Astreinte` déjà complet, et n'a **aucun** accès à un dépôt | Vérifié par construction : `FeuilleAstreinte` ne prend pas de `ref`. |
| Bandeau de fraîcheur en ligne | variante `attention`, « Ces astreintes datent du 12 octobre. » | la phrase dit l'ancienneté **en relatif** (« Ces astreintes datent d'hier. ») et garde la date absolue au-delà d'une semaine | `formaterInstantRelatif` fait déjà exactement cette bascule, et deux formulations de l'ancienneté dans une même application en feraient deux vocabulaires. |
| Repli des passées | « une seule ligne, pleine largeur, 52 dp » | 52 dp de haut **et** l'`EnteteSection` du premier mois passé n'apparaît qu'une fois le repli ouvert | Un en-tête de mois visible au-dessus d'un contenu replié annonce une section qui n'est pas là. |
