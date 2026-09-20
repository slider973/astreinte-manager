# 017 — La construction du planning en brouillon

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web**,
Material 3, une seule apparence. Ce brief **prolonge** `design/016-matrice-admin.md` : il occupe
les deux emplacements que le 016 a nommés et laissés vides, et il ne redéfinit rien de ce que le
016 a tranché.

`DESIGN.md` gagne sur ce brief pour toute valeur de token. Les écarts sont listés au § 7.3.

Sources : `docs/PRD.md § 5.3`, `§ 6.4`, `§ 7` ; `docs/SCHEMA.md § 2.8` à `§ 2.10`, `§ 4`, `§ 5`,
`§ 9` ; `docs/WORKFLOWS.md § 2` et `§ 3` ; `design/016-matrice-admin.md § 6.8` ;
`tickets/in-progress/017-brouillon-attribution.md`.

---

## 1. Job et audience

**Le même chef de centre qu'au 016, une heure plus tard.** Il a lu la matrice, il sait qui peut
quoi. Maintenant il décide. C'est le seul moment du produit où quelqu'un **écrit sur le mois de
quelqu'un d'autre pour de bon** : une attribution deviendra, à la publication, une notification
dans la poche d'un pompier et une garde à tenir.

Deux choses changent par rapport au 016, et elles changent tout :

1. **L'écran n'est plus en lecture.** Au 016, toucher la matrice était un mode armé, exceptionnel,
   tracé. Ici, attribuer **est** le travail : le geste doit être immédiat, sans mode, sans
   confirmation, et réversible en un geste symétrique.
2. **Ils peuvent être deux.** Un chef et son adjoint construisent souvent le même mois, chacun sur
   son poste. Deux écrans qui divergent produisent deux plannings, dont un seul survit. Le temps
   réel n'est donc pas un agrément, c'est la condition pour que l'écran soit utilisable à deux.

## 2. Résultat et preuve

**Résultat.** Le chef ouvre le mois, crée le planning en un geste, voit d'un regard **quels
créneaux manquent de monde**, et les remplit un par un en sachant à chaque fois ce que son choix
coûte au pompier qu'il désigne.

**Preuve, dans l'ordre :**

1. Un créneau non pourvu se voit **avant tout défilement et sans compter** : la ligne des créneaux
   est épinglée, et elle porte un chiffre, pas une teinte.
2. Le premier nom de la liste des candidats est **celui qu'il faut prendre** dans la majorité des
   cas : c'est l'ordre du PRD § 5.3, appliqué à la lettre.
3. Ce que le chef voit du quota d'un membre dans le panneau est **exactement** ce que la ligne de
   ce membre affiche dans la matrice : même source, même chiffre (`v_member_load`), jamais deux
   calculs.
4. Une attribution faite par l'adjoint apparaît sur l'écran du chef **sans qu'il touche à rien**,
   et sans que l'écran bouge sous sa main.

**Ce que la base donne, et qu'il ne faut pas recalculer.** `availability_matrix` rend déjà, par
membre : le reste de quota d'astreintes, le reste de weekends, la charge des trois mois précédents
et l'état de chaque case du mois. **Les deux critères de tri des candidats et leur disponibilité
sortent de ces lignes**, déjà en mémoire. Un panneau de candidats qui interrogerait le serveur pour
trier douze noms serait une régression sur un jeu de soixante lignes déjà chargé.

## 3. Direction retenue

Le monde visuel est posé et cet écran ne l'invente pas : **le registre de garde** (`DESIGN.md`).

**La thèse : la fraction est la signature du créneau.** La ligne « Disponibles » du 016 porte un
**chiffre nu** — combien de pompiers sont disponibles. La ligne des créneaux porte une
**fraction** — combien sont attribués sur combien sont requis. `4` et `1/2` ne se confondent pas,
même à 28 px, même en niveaux de gris, même au coin de l'œil : la barre oblique **est** la marque.
C'est le même argument qu'au 016 pour les quotas (« la barre de fraction est le signe qu'un plafond
existe »), et le réemployer ici vaut mieux que d'inventer une seconde grammaire.

**Trois états, trois écritures :** `0/1` à pourvoir, `1/1` pourvu, `2/1` sur-pourvu. Ce sont
**trois suites de caractères différentes**. La couleur arrive en quatrième, et un zéro se hachure
comme le zéro de la ligne « Disponibles » — même motif, même raison : personne.

**Le panneau n'est pas une modale.** Le 016 a réservé `AppScaffold.panneauLateral` pour lui, et a
refusé d'ouvrir un second panneau pour l'en-tête de ligne précisément pour qu'il soit libre. Sur
grand écran, le créneau s'ouvre **à droite, à côté de la matrice**, et la matrice reste lisible :
le chef choisit un candidat en regardant le mois, pas en regardant une boîte qui cache le mois.

## 4. Périmètre et limites

**Livré :** la création du planning du mois et de ses créneaux ; la ligne des créneaux à pourvoir ;
le panneau des candidats avec attribution, retrait et avertissements ; la modification de l'effectif
requis d'un créneau ; le temps réel sur les attributions.

**Pas livré, et à ne pas esquisser :** la publication, les états de réponse (`accepté`, `refusé`,
`en attente`), la progression du planning, les relances, la réattribution, la proposition
automatique. Ce sont les tickets 018, 019 et 022. **L'emplacement du bouton « Publier »
(`filActions`) reste vide**, comme au 016.

**Anti-objectifs explicites :**

- **Pas de glisser-déposer d'un membre vers un créneau.** La matrice du 016 refuse déjà la
  peinture par glissement ; traîner un nom sur une case de 28 px avec pour conséquence une
  notification dans la poche de quelqu'un serait le geste le plus facile à rater de toute
  l'application.
- **Pas de sélection multiple de créneaux**, pas de « remplir la semaine ». Le remplissage en
  masse a un nom et un ticket : la proposition automatique (018).
- **Pas de second compteur de couverture.** La ligne des créneaux dit tout ; un bandeau
  « 42 créneaux sur 62 pourvus » appartient au 019 et ferait deux chiffres pour une chose.
- **Aucun blocage.** Un quota atteint avertit, il n'interdit pas. Une non-disponibilité avertit,
  elle n'interdit pas. `docs/PRD.md § 7.4` : « L'app avertit, l'admin décide. »
- **Pas de journal des modifications à l'écran.** Qui a fait quoi vit dans `audit_log` et dans le
  ticket 021.

## 5. États et plages de contenu

### 5.1 Plages réelles

| Grandeur | Minimum | Typique | Maximum retenu |
|---|---|---|---|
| Créneaux d'un mois | 56 | 60 | **62** |
| Effectif requis d'un créneau | **0** | 1 | 50 (borne de `station_settings`) |
| Attributions sur un créneau | 0 | 1 | non borné en base — 60 en pratique |
| Candidats disponibles sur un créneau | **0** | 8 | 60 |
| Membres non disponibles listés | 0 | 50 | 60 |
| Attributions d'un mois | 0 | ~70 | 3 720 (absurde, mais rien ne l'interdit) |

Trois valeurs piègent. **Un effectif requis de 0 est légal** (`check (required_count >= 0)`) : un
créneau à 0 est « pas d'astreinte ce jour-là », et il est **pourvu** dès qu'il est vide. **Le
sur-pourvu n'est pas une erreur** : un renfort est une décision. Et **la liste des candidats
disponibles peut être vide** alors que le créneau est à pourvoir : c'est le cas qui fait exister
la section « non disponibles ».

### 5.2 Les états de l'écran

| État | Ce qu'on voit |
|---|---|
| **Aucun planning pour ce mois** | La ligne des créneaux **n'existe pas** (28 px rendus à la grille). Dans la barre de commande : `PrimaryButton` secondaire **« Créer le planning d'octobre »**, suivi d'une `mention` qui dit ce que ça fera : « 62 créneaux seront créés avec l'effectif requis actuel. » |
| **Création en cours** | Le bouton garde son libellé, un indicateur de 20 dp le précède, la largeur ne bouge pas (`DESIGN.md § Buttons`). |
| **Planning créé** | La ligne des créneaux apparaît. `SnackBar` : « Planning d'octobre créé : 62 créneaux. » Un `StatusBadge` **« Brouillon »** s'installe dans la barre de commande et n'en bouge plus. |
| **Échec de création** | Bannière `erreur` + « Réessayer ». Le mois reste lisible. |
| **Créneau sélectionné** | Sa cellule porte le contour 2 dp `primary` de la sélection, le panneau s'ouvre à droite (ou en feuille). |
| **Panneau : aucun candidat disponible** | `EmptyState` **dans le panneau**, icône `person_off`, « Personne n'est disponible sur ce créneau. » L'action reste : « Voir les non disponibles » déplie la seconde section. |
| **Panneau : créneau à 0 requis** | Le bandeau d'état dit « Aucune astreinte requise ». Les candidats restent listés : on peut attribuer quand même, le créneau passe en sur-pourvu. |
| **Attribution en vol** | La ligne du candidat garde sa place, son bouton passe en chargement. La cellule de la ligne des créneaux **se met à jour tout de suite** (optimiste). |
| **Attribution refusée : doublon** | `SnackBar` : « Marie Lefebvre est déjà attribuée à ce créneau. » Le panneau se relit. Ce n'est pas une panne, c'est l'autre admin. |
| **Attribution refusée : autre** | La cellule revient à sa valeur, bannière `erreur` + « Réessayer ». |
| **Retrait** | La ligne disparaît de « Attribués », la cellule se met à jour, `SnackBar` « Attribution retirée » + action **« Annuler »**. |
| **Changement distant** | La ligne des créneaux change, **sans animation, sans toast**. Si le panneau ouvert est concerné, une `mention` s'affiche sous son titre : « Modifié à l'instant par Jean D. » |
| **Direct interrompu** | Dans la barre de commande, à côté de « Rafraîchir » : `cloud_off` + « Direct interrompu ». C'est la seule façon honnête de ne pas mentir sur la fraîcheur de l'écran. |
| **Hors ligne** | Bannière `hors-ligne` (déjà au 016). Attribution et retrait désactivés, **avec leur raison**. |
| **Caserne suspendue** | Bannière `lecture-seule`. Création, attribution, retrait et effectif désactivés avec leur raison. |
| **Planning déjà publié** | Le cas n'arrive pas encore (rien ne publie avant le 019) mais l'écran ne le suppose pas : les actions d'attribution sont désactivées et la raison le dit — « Planning publié : la modification d'un créneau publié arrive avec la publication. » |
| **Mois verrouillé** | **Sans effet ici.** Le verrouillage ferme la saisie des membres, jamais la construction du planning (`PRD § 7.5`). |

### 5.3 Ce que ces états ne font jamais

- Aucun état ne remplace la matrice par un message. Pas de planning, pas de candidats, échec de
  lecture : la grille reste.
- Aucun avertissement ne devient un blocage. Un candidat au quota atteint reste cliquable, un
  membre absent reste attribuable.
- Aucun changement distant ne déplace ce qui est sous la main : le défilement ne bouge pas, le
  panneau ouvert ne se ferme pas, la sélection ne saute pas.

## 6. Interaction et layout

### 6.1 La composition, `large` — ce qui s'ajoute au 016

```
┌ rail ┬──────────────────────────────────────────────┬──────────────────────┐
│      │ Planning du mois         [membres][…][↻]     │                      │
│      ├──────────────────────────────────────────────┤  panneauLateral      │
│      │ (bannière, au plus une)                      │  360 dp              │
│      ├──────────────────────────────────────────────┤ ┌──────────────────┐ │
│      │ [Octobre 2026 ▾] [🔍] [filtres] [Brouillon]  │ │ Samedi 4 octobre │ │
│      │ [⌨ Saisir à la place]  ⟳ Direct  ✓ Enregistré│ │ Nuit             │ │
│      ├────────────┬─────────────────────────────────┤ │ 0/1 à pourvoir   │ │
│      │            │  L    M    M    J    V    S   … │ │                  │ │
│      │ Membre     │  1    2    3    4    5    6   … │ │ Effectif requis  │ │
│      │ Astr.  W-E │ ☀🌙  ☀🌙  ☀🌙  ☀🌙  ☀🌙  ☀🌙 … │ │   [−]  1   [+]   │ │
│      │ Créneaux   │1/1 ▒0/1▒ 1/1 0/1 2/1 1/1 …      │ │                  │ │
│      │ Disponibles│ 4 3  5 2  4 2  6 3  0 2  8 5  … │ │ ATTRIBUÉS (0)    │ │
│      ├────────────┼─────────────────────────────────┤ │ —                │ │
│      │ Dubois J-M │  ✓ ✓  ✓ ·  · ·  ✗ ✗  · ·  ✓ ✓ … │ │ DISPONIBLES (7)  │ │
│      │   2/3  1/1 │                                 │ │ Dubois J-M       │ │
│      │ Martin A.  │  · ·  ✓ ✓  ✓ ✓  · ·  ✓ ·  · · … │ │ 2/3 astr · 1/1 we│ │
│      │  −1/4  0/2 │                                 │ │        [Attribuer]│ │
└──────┴────────────┴─────────────────────────────────┴─┴──────────────────┴─┘
```

Deux ajouts, et rien d'autre :

1. **Un rang de plus dans le bloc épinglé**, entre l'en-tête des dates et la ligne
   « Disponibles » — la place exacte que le 016 avait réservée (§ 6.8). Le bloc épinglé passe de
   84 px à **112 px**.
2. **Le panneau latéral**, qui n'existe que lorsqu'un créneau est sélectionné.

### 6.2 La ligne des créneaux

Une ligne de **28 px**, même pas de colonne que tout le reste de la matrice, une cellule par
créneau. Libellé **« Créneaux »** dans le coin figé, en `etiquette` 12.

| État | Contenu | Marque | Encre claire |
|---|---|---|---|
| **à pourvoir, personne** | `0/1` | fond **hachuré** ocre | `etat-attente` sur `etat-attente-fond` |
| **à pourvoir, incomplet** | `1/2` | fond ocre plein | `etat-attente` sur `etat-attente-fond` |
| **pourvu** | `1/1` | fond vert pâle | `etat-disponible-sur-fond` sur `etat-disponible-fond` |
| **sur-pourvu** | `2/1` | fond bleu de réglure | `on-secondary-container` sur `secondary-container` |
| **sélectionné** | idem | **contour 2 dp `primary`** par-dessus l'état | — |

Chiffres en `etiquette` 12, famille **mono tabulaire** : `0/1`, `1/1` et `2/1` occupent la même
largeur, et la ligne entière s'aligne en colonnes comme un registre. Trois caractères dans 28 px,
soit ~22 px de glyphes : cela tient, et c'est la limite — **au-delà de 9, le nombre est tronqué à
`9+`** (`9+/1`), cas qu'aucune caserne n'atteindra.

**Pourquoi le sur-pourvu est bleu et non rouge.** Le rouge veut dire « absent, refusé, cassé »
(`DESIGN.md`). Trois pompiers sur un créneau qui en demande deux n'est pas une panne : c'est un
renfort, une décision, un fait. Le bleu de réglure est l'encre des faits neutres du système.

**Interaction.** Un clic ouvre le panneau du créneau. La cellule est un `button` sémantique :
« Samedi 4 octobre, nuit : 0 attribué sur 1 requis, à pourvoir. Appuie pour voir les candidats. »
Au clavier, la ligne est atteignable par `Tab` et chaque cellule par les flèches, comme les cases
de la grille.

**28 px, donc pointeur seulement** — même règle que la case dense du 016, sans exception. Sur
tablette tactile, la ligne des créneaux **se lit** et ne s'ouvre pas ; le panneau s'ouvre depuis la
vue par jour (§ 6.5).

### 6.3 Le panneau des candidats

**`large` : `AppScaffold.panneauLateral`, 360 dp, permanent tant qu'un créneau est sélectionné.
En dessous : feuille de bas d'écran** (`showModalBottomSheet`, rayon `feuille` en haut,
`isScrollControlled`, hauteur initiale 70 %). Jamais un `Dialog` : ce n'est ni une interruption ni
une protection.

De haut en bas :

1. **Titre** : « Samedi 4 octobre » en `titre-bloc`, « Nuit » avec son icône en `corps-secondaire`.
   Bouton `close` de 48 dp à droite (et `Échap`, et le geste retour sur la feuille).
2. **L'état de couverture**, en clair : `StatusBadge` « À pourvoir » / « Pourvu » / « Sur-pourvu »
   + « 0 attribué sur 1 requis ».
3. **L'effectif requis** (§ 6.4).
4. **« Attribués (1) »** — les membres déjà posés. Nom, quotas, et un bouton `person_remove`
   « Retirer » de 48 dp. Section absente quand elle est vide, sauf si le créneau est à pourvoir,
   où elle affiche une ligne « Personne pour l'instant. »
5. **« Disponibles (7) »** — les candidats, dans l'ordre du PRD (§ 6.5).
6. **« Non disponibles (12) »** — repliée, `ExpansionTile` fermé par défaut. Les absents et les
   non saisis, chacun avec sa puce d'état, dans le même ordre.

**Une ligne de candidat** fait **72 dp** minimum : nom en `corps` 16, quotas en `mention` sur la
seconde ligne (`2/3 astr. · 1/1 w-e · 4 acceptées sur 3 mois`), commentaire du mois sur une
troisième ligne quand il existe — **le même commentaire qu'au 016, au même endroit de la
hiérarchie**, parce que c'est là qu'il sert le plus. À droite, le bouton d'action.

| Cas | Ligne | Bouton | Ce qui se passe au clic |
|---|---|---|---|
| Disponible, quota libre | encre normale | **« Attribuer »** | attribution immédiate |
| Disponible, **quota atteint ou dépassé** | nom et quotas en `on-surface-variant`, `warning_amber` 16 dp + « Quota atteint » en `etat-attente` | **« Attribuer quand même »** | attribution immédiate |
| **Non disponible** (absent ou non saisi) | puce d'état `absent` / `non saisi` | **« Attribuer quand même »** | **dialogue de confirmation** |

**Pourquoi le quota n'ouvre pas de dialogue et la non-disponibilité si.** Le quota est un
**réglage du membre**, affiché en clair sur la ligne avant le geste : le chef le lit, décide, et
un dialogue ne lui apprendrait rien qu'il n'ait déjà sous les yeux. La non-disponibilité est un
**refus explicite** du membre, qui sera tracé en base (`was_available = false`) et dans
`audit_log` : elle mérite le seul dialogue de cet écran, et il nomme les conséquences.

> **Attribuer Marie Lefebvre hors de ses disponibilités**
> Marie Lefebvre s'est déclarée **absente** samedi 4 octobre, nuit. Elle recevra la proposition
> comme les autres et pourra la refuser. Cette attribution est enregistrée à ton nom dans
> l'historique de la caserne.
> [ Annuler ] [ **Attribuer quand même** ]

(Pour un membre qui n'a rien saisi, la première phrase devient « n'a pas saisi ses
disponibilités » : ne pas avoir répondu n'est pas avoir dit non, et l'écran ne confond pas les
deux — c'est le mécanisme central du produit.)

**Le retrait ne demande rien.** En brouillon, retirer supprime la ligne et rien d'autre : il n'y a
ni notification partie, ni historique à préserver (`WORKFLOWS § 3` : `proposed_at` est nul tant que
le planning n'est pas publié). Un dialogue pour un geste réversible en deux clics apprendrait à
cliquer « Oui » sans lire. La sortie est un `SnackBar` **« Attribution retirée »** avec
**« Annuler »**, 8 s — la durée retenue au ticket 024 pour un téléphone posé.

### 6.4 L'effectif requis d'un créneau

Dans le panneau, sous l'état de couverture :

```
Effectif requis        [ − ]  1  [ + ]
Ne change que ce créneau.
```

Deux `IconButton` de 48 dp, le nombre en `nombre` 20 mono tabulaire entre eux. Bornes **0 à 50**,
celles de `station_settings`. `−` est désactivé à 0, `+` à 50, chacun avec sa raison en info-bulle.
Écriture optimiste, immédiate, sans validation : c'est un réglage, pas un formulaire.

**La phrase « Ne change que ce créneau » n'est pas décorative.** C'est la règle du ticket 010 rendue
visible : `required_count` est une **copie** faite à la création du planning, jamais une référence
aux réglages de la caserne. Un chef qui change l'effectif ici ne change pas sa caserne ; un chef
qui change sa caserne ne change pas les plannings déjà créés. Les deux écrans le disent, chacun de
son côté.

### 6.5 L'ordre des candidats, et d'où il vient

**Quota d'astreintes restant décroissant, puis astreintes acceptées sur les trois mois précédents
croissant, puis nom.** C'est `docs/PRD.md § 5.3` mot pour mot, et c'est **exactement l'ordre du
tri « Astreintes restantes » du 016** : le chef retrouve le classement qu'il connaît déjà.

- **`null` (aucun plafond) passe en tête.** Un illimité est la plus grande capacité disponible.
  Même règle qu'au 016 § 6.7, et pour la même raison.
- **Un reste négatif passe en queue**, après les zéros : celui qui est déjà au-delà de ce qu'il
  acceptait est le dernier qu'on dérange.
- **Les deux valeurs sont lues telles quelles dans les lignes de la matrice.** Aucun recomptage,
  aucune requête : le tri de douze noms se fait sur des lignes déjà en mémoire.
- Le tri est **stable** et ne change pas pendant que le panneau est ouvert : attribuer quelqu'un
  ne fait pas sauter les autres lignes sous la main. Le classement se recalcule à la prochaine
  ouverture du panneau.

### 6.6 Le téléphone : la vue par jour

La vue par jour du 016 reçoit les mêmes deux ajouts, à sa densité :

- **Sous le ruban, un bloc réglé** : deux boutons de 48 dp, « Jour 1/1 » et « Nuit 0/1 », avec leur
  icône et leur état. Ils ouvrent le panneau en feuille de bas d'écran. C'est le seul accès au
  panneau sous 840 dp, et il est en pleine cible tactile.
- **Le ruban des jours ne porte pas la couverture** (décision d'implémentation, § 9) : il garde le
  seul compte de disponibles du ticket 016.
- Tout le reste du panneau est identique : mêmes sections, mêmes avertissements, mêmes 48 dp.

**Rien n'est perdu sur téléphone**, contrairement à la matrice. Attribuer est un geste court, sur
un objet unique, avec une liste : c'est exactement ce qu'un téléphone fait bien. Un chef qui reçoit
un refus le samedi soir doit pouvoir réattribuer depuis sa cuisine.

### 6.7 Le temps réel, et sa discrétion

**Ce que le temps réel fait :** les cellules de la ligne des créneaux changent, le panneau ouvert
se met à jour, les listes se réordonnent au prochain tri.

**Ce que le temps réel ne fait jamais :**

- il ne déplace pas le défilement, ne ferme pas le panneau, ne change pas la sélection ;
- il n'anime rien (`DESIGN.md § Motion` : aucune animation dans la matrice) ;
- il n'ouvre **aucun toast** par événement. Deux adjoints qui attribuent trente créneaux
  produiraient trente `SnackBar` : le bruit couvrirait le signal, et le signal est déjà à l'écran.

**Une seule mention, et seulement là où elle sert :** dans le panneau ouvert, sous le titre, quand
c'est **ce créneau-là** qui a changé sous une autre main — « Modifié à l'instant par Jean D. »
(le nom vient des lignes de la matrice déjà chargées ; à défaut, « par un autre administrateur »).
Elle s'efface au geste suivant.

**L'état du canal est affiché.** À côté de « Rafraîchir » : `sync` + « Direct » quand le canal est
abonné, `cloud_off` + « Direct interrompu » sinon, avec l'action « Rafraîchir » à un pixel. Un
écran collaboratif qui perd son abonnement en silence est un écran qui ment.

### 6.8 Détails de facture

- **La ligne des créneaux partage le ruban virtualisé** de la matrice : mêmes 30 px de pas, même
  fenêtre horizontale, même contrôleur de défilement. Elle ne construit que les journées visibles.
- **Le panneau n'est pas dans le bloc épinglé.** Il observe sa propre tranche d'état : attribuer
  ne reconstruit pas la matrice, changer de mois ferme le panneau.
- **Chiffres tabulaires** partout, et famille mono pour toutes les fractions.
- **Séparation par filet**, jamais par ombre : la ligne des créneaux est séparée de la ligne
  « Disponibles » par rien du tout (elles forment un bloc), et le bloc épinglé garde son filet 2 dp
  en bas.
- **Cibles :** 28 px au pointeur dans la matrice, 48 dp partout ailleurs, 8 dp entre deux cibles.
- **Anneau de focus 2 dp `primary`**, y compris sur une cellule pleine.
- **Une attribution optimiste garde sa place** : la cellule se met à jour avant la réponse du
  serveur, et revient à sa valeur si le serveur refuse.

## 7. Contraintes et décisions

### 7.1 Ce que la base garantit, et ce que l'écran doit en faire

- **`unique (schedule_id, date, slot)`** : un créneau par jour et par créneau, point. La création
  du planning est **idempotente** : relancée, elle ne double rien.
- **`assignments_active_uniq (shift_id, user_id) where status in ('proposed','accepted')`** : la
  base refuse une seconde attribution active du même membre sur le même créneau. L'écran ne
  **prévient** pas cette erreur (il ne peut pas : l'autre admin est plus rapide que lui), il la
  **traduit** — code `23505` → « déjà attribuée à ce créneau », et relecture.
- **`required_count` est une copie**, posée à la création depuis `settings` et ses surcharges.
  Rien en base ne la réécrit ensuite (`SCHEMA § 2.9`, critère du ticket 010).
- **En brouillon, `status = 'proposed'` et `proposed_at is null`** (`WORKFLOWS § 3`). L'écran
  n'invente aucun statut et n'écrit jamais `proposed_at`.
- **`was_available` n'est pas une opinion du client** : la base la calcule à l'insertion depuis les
  disponibilités réelles. Un client qui se tromperait — ou qui mentirait — ne ferait pas disparaître
  la trace.
- **Aucune colonne inventée.** Les tables sont celles du § 2.8 au § 2.10, sans un champ de plus.

### 7.2 Le temps réel et les colonnes exposées

La revue du ticket 006 a posé la règle : **une publication diffuse toutes les colonnes de la table,
et les politiques RLS filtrent des lignes, pas des colonnes.** Avant d'inscrire `assignments` dans
`supabase_realtime`, il faut donc répondre à trois questions.

1. **Quelles colonnes partent ?** Toutes celles d'`assignments`. Aucune n'est un porteur de droits :
   il n'y a ici ni jeton, ni secret, ni adresse. La seule colonne sensible au sens humain est
   `decline_reason`, le motif d'un refus — et elle n'est visible que des lignes qu'un abonné a déjà
   le droit de lire. `assignments` n'a **aucun `grant` de colonne restrictif** à contourner,
   contrairement à `invitations.token`, et c'est exactement ce qui fait la différence entre les deux
   tables.
2. **Qui reçoit quoi ?** La diffusion est filtrée ligne à ligne par les politiques de `select`
   existantes. Conséquence directe et voulue : **un membre ne reçoit rien d'un planning en
   brouillon**, puisque aucune politique ne lui en donne la lecture. Le brouillon reste invisible
   (`WORKFLOWS § 2`), y compris par ce canal.
3. **Et les suppressions ?** C'est le point qui décide du reste. Pour un `delete`, Postgres ne
   diffuse que l'**identité de réplique** de la ligne, et la charge utile d'un `delete` n'est
   **pas** filtrée par les politiques. L'identité de réplique d'`assignments` reste donc
   **`default`** — la clé primaire, un `uuid` opaque et rien d'autre. **Passer la table en
   `replica identity full` diffuserait toutes les colonnes de chaque ligne supprimée à tous les
   abonnés, sans filtre** : c'est précisément ce qu'il ne faut pas faire, et le retrait d'une
   attribution en brouillon est un `delete`.

**Conséquence d'implémentation, assumée :** puisqu'une suppression n'annonce qu'un identifiant,
le client doit garder les attributions **indexées par leur identifiant** pour savoir quel créneau
redessiner. C'est une contrainte de structure, pas un contournement.

**`shifts` n'entre pas dans la publication.** `docs/SCHEMA.md § 9` limite le temps réel à
`assignments`, `schedules` et `notifications` ; et un changement d'effectif requis est rare,
délibéré, et rattrapé par « Rafraîchir ». Inscrire une table de plus pour un événement par mois
serait payer un canal pour rien.

### 7.3 Écarts à `DESIGN.md` et au brief 016, à reporter dans la PR

| Point | Ce que disait le document | Ce que fait ce brief | Pourquoi |
|---|---|---|---|
| Hachures | réservées à « absent » et « mois verrouillé » | **troisième emploi** : le créneau que personne ne couvre (`0/r`) | Le 016 les a déjà étendues au « 0 disponible » pour la même raison : « personne » est le seul état de cet écran qui doive se voir à un mètre et en noir et blanc. Trois emplois, une seule sémantique : le vide. |
| `secondary-container` | « sélection dans les listes denses », état « publié » | porte aussi le **sur-pourvu** | C'est l'encre des faits neutres. Le vert dirait « bien », le rouge dirait « cassé » ; un renfort n'est ni l'un ni l'autre. |
| Bloc épinglé du 016 | 84 px (en-tête 56 + disponibles 28) | **112 px** | La ligne des créneaux était prévue et sa hauteur annoncée (016 § 6.8). C'est l'exécution de la réservation, pas un écart. |
| `panneauLateral` | « détail de créneau, jamais une modale » | exactement cela, **plus** un unique dialogue pour l'attribution hors disponibilité | `DESIGN.md` autorise la modale pour « une tâche qui demande interruption ou protection ». Écrire contre le refus explicite d'un membre en est une. |
| Densité dense « jamais servie au tactile » | — | la ligne des créneaux suit la même règle | Aucune exception : le téléphone passe par la vue par jour et ses 48 dp. |

### 7.4 Décisions tranchées pendant ce brief

1. **La fraction est la marque du créneau**, le chiffre nu reste celui des disponibles. Deux lignes
   voisines, deux grammaires, aucune confusion possible en niveaux de gris.
2. **Le sur-pourvu est un fait bleu, pas une erreur rouge.**
3. **Le quota avertit sur la ligne ; la non-disponibilité ouvre un dialogue.** Un seul dialogue
   dans tout l'écran, et il est mérité.
4. **Le retrait ne demande pas confirmation**, il offre « Annuler ».
5. **Le temps réel est silencieux.** Aucun toast par événement, une mention dans le panneau
   concerné, et l'état du canal affiché en clair.
6. **L'identité de réplique d'`assignments` reste `default`** : une suppression ne diffuse qu'un
   identifiant (§ 7.2).
7. **`was_available` est calculé par la base**, pas déclaré par le client.
8. **La création du planning vit dans la barre de commande**, pas dans un écran à part : elle est
   le premier geste du mois, au même endroit que tous les autres contrôles du mois.

### 7.5 Ce qu'un développeur ne doit pas inventer ici

- Aucun bouton « Publier », aucun état de réponse, aucune relance, aucune réattribution, aucune
  proposition automatique.
- Aucun blocage sur un quota ou sur une non-disponibilité.
- Aucun `status` d'attribution autre que `proposed` ; aucun `proposed_at`.
- Aucun recalcul de quota ni de charge côté Dart : les deux valeurs viennent de la matrice.
- Aucune requête déclenchée par l'ouverture du panneau, le tri ou le dépliage d'une section.
- Aucune chaîne en dur dans un widget : tout passe par `AppStrings`.

### 7.6 Décisions ouvertes

- **Le nom de l'auteur d'un changement distant** est résolu depuis les lignes de la matrice, donc
  seulement si l'autre admin est un membre actif de la caserne — ce qu'il est toujours en pratique.
  À défaut : « un autre administrateur ». Aucune requête supplémentaire pour un nom.
- **La création du planning ne rattrape pas les créneaux manquants** d'un planning existant (mois
  qui aurait changé de longueur : impossible). Si le besoin apparaît, ce sera une fonction séparée
  et nommée, pas un effet de bord de la création.
- **L'ordre des candidats ne tient pas compte des weekends restants.** Le PRD n'en parle pas, et
  ajouter un troisième critère non demandé rendrait l'ordre impossible à expliquer au chef. La
  valeur reste affichée sur chaque ligne : il décide.

## 8. Widgets Flutter

### 8.1 Réemployés tels quels

| Composant | Emploi |
|---|---|
| `AppScaffold` (`panneauLateral`) | le panneau des candidats en `large` |
| `AppBanner` | `erreur`, `hors-ligne`, `lecture-seule` — aucune nouvelle variante |
| `StatusBadge` | état du planning (« Brouillon »), état de couverture du créneau, état de disponibilité d'un candidat |
| `EmptyState` | « personne n'est disponible » dans le panneau |
| `PrimaryButton` | « Créer le planning », « Attribuer », « Attribuer quand même » |
| `Hachures` | le créneau que personne ne couvre |
| `AppDivider` | séparation des sections du panneau |
| `RubanJours`, `GeoMatrice`, `FondJour` | virtualisation, géométrie et fonds partagés avec la matrice |
| `SaveIndicator` | l'enregistrement des attributions, dans la barre de commande |

### 8.2 À créer dans `lib/features/planning/presentation/widgets/`

- **`ligne_creneaux.dart` — `CasesCreneaux`** : les deux cellules de fraction d'une journée, sur le
  modèle exact de `CasesDisponibles`.
- **`panneau_creneau.dart` — `PanneauCreneau`** : le panneau, indépendant de son contenant (volet
  ou feuille).
- **`ligne_candidat.dart` — `LigneCandidat`** : une ligne de la liste, ses avertissements et son
  bouton.
- **`champ_effectif.dart` — `ChampEffectif`** : le `−  n  +` de l'effectif requis.
- **`confirmation_hors_dispo.dart`** : le dialogue, sur le modèle de `confirmation_saisie_admin.dart`.

Aucun nouveau composant dans `lib/core/widgets/` : tout ce que cet écran montre existe déjà en
tokens et en composants du système.


## 9. Écarts d'implémentation (ticket 017)

Écrits après coup, comme le veut la convention du projet : ce document reste normatif, et ces
lignes sont désormais la référence.

| Point | Ce que disait ce brief | Ce que fait le code | Pourquoi |
|---|---|---|---|
| Couverture dans le ruban des jours (§ 6.6) | le ruban porte la fraction sous le compte de disponibles | **non livré** : le bloc des deux créneaux, juste en dessous, la porte seul | 28 dp de plus sur **tous** les téléphones, sur tous les mois, pour redire en petit ce que le bloc dit juste en dessous en toutes lettres et en 48 dp. Le ruban reste ce que le 016 en a fait. |
| Libellé du bouton d'attribution (§ 6.3) | « Attribuer quand même » sur les lignes à avertissement | toujours **« Attribuer »** ; l'avertissement est sur la ligne, et « quand même » est dans le dialogue | À 360 dp, « Attribuer quand même » ne tient pas dans la ligne sans tronquer un nom ou le libellé lui-même — et un libellé de bouton tronqué est pire qu'un libellé court. Le contexte est déjà porté par la puce « Quota atteint » ou « Absent » posée au-dessus. |
| Panneau en volet (§ 6.3) | volet à droite en `large`, feuille en dessous | inchangé, et la **feuille couvre donc aussi `expanded`** (840–1199 dp) | `AppScaffold` n'ouvre son `panneauLateral` qu'en `large` (ticket 004). Ouvrir un second mécanisme de volet pour la fenêtre intermédiaire aurait dupliqué la composition de l'ossature. |
| `StatusBadge` | « aucun nouveau composant » (§ 8.2) | un constructeur de plus, `StatusBadge.descripteur` | La couverture n'a pas de famille dans le thème, mais son descripteur se compose **de ses encres**. Le type continue de garantir l'essentiel : pas d'état sans icône ni libellé. |
| Quotas de la ligne membre | non traité — le brief renvoyait aux valeurs de `v_member_load` | les quotas sont **recomptés à l'écran** sur les attributions déjà chargées (`PlanningMois.charges`) | C'est un critère d'acceptation du ticket : « les quotas de la ligne membre se mettent à jour à chaque attribution ». Les recompter coûte zéro requête et donne exactement le même nombre que la vue : même définition d'astreinte, même unité de weekend (`uniteWeekend`, parité SQL testée). Relire la matrice à chaque attribution aurait coûté 22 ko et une seconde par créneau posé. |
| Sémantique des cases de créneau | non traité | l'action est portée par le nœud `Semantics` **qui exclut ses enfants**, pas par l'`InkWell` | `excludeSemantics: true` avale aussi le geste de l'enfant : le lecteur d'écran annonçait un bouton que rien ne permettait d'activer. Vu en vrai dans Chrome, sur l'arbre d'accessibilité. Le même défaut existait sur le bouton de jour du ruban (ticket 016) et est corrigé au passage. |
| Élision du mois | non traité | `AppStrings.moisAvecDe` : « d'octobre », jamais « de octobre » | Trois mois commencent par une voyelle. Vu en vrai à l'écran. |
