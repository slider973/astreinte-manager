# 016 — La matrice des disponibilités de l'admin

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web**,
Material 3, une seule apparence. Cet écran est le seul du produit conçu **d'abord pour grand
écran**, puis dégradé — l'inverse de tous les autres.

`DESIGN.md` gagne sur ce brief pour toute valeur de token. Trois points seulement s'en écartent,
avec leur démonstration et leur report au § 7.3 : le verrouillage n'inerte pas la matrice de
l'admin, la case dense gagne un état, et la destination « Admin » change d'écran d'atterrissage.

Sources : `docs/PRD.md § 5.3`, `§ 6.3`, `§ 6.4` ; `docs/SCHEMA.md § 2.6`, `§ 2.7`, `§ 6` ;
`supabase/migrations/0017_matrice_admin.sql` ; `tickets/in-progress/016-matrice-admin.md` ;
`design/004-design-system.md`, `design/011-saisie-dispos-grille.md`,
`design/013-preferences-quotas.md`, `design/014-periodes-verrouillage.md`.

---

## 1. Job et audience

**Un chef de centre, assis, une fois par mois, une heure durant.** La saisie s'est verrouillée le
15. Il ouvre son ordinateur — pas son téléphone — et il doit couvrir soixante-deux créneaux avec
les disponibilités que soixante pompiers ont bien voulu donner. C'est le seul moment du produit
où quelqu'un travaille longtemps, avec attention, sur un écran large.

Ce n'est pas le même homme que le pompier du ticket 011. Il n'a pas de gants, il n'est pas
debout, il a une souris et un clavier. Mais c'est souvent **le même téléphone** qu'il ressortira
le samedi soir pour vérifier qui est dispo. Les deux scènes existent, elles n'ont pas les mêmes
droits, et ce brief refuse de les servir avec la même mise en page (§ 6.6).

**Ce qui se joue.** C'est l'écran d'où sort le planning qui couvre la commune. S'il est illisible,
le chef retourne à son intranet et à son tableur, et le produit n'existe plus. Les deux
mécanismes qui distinguent ce produit — les quotas déclarés et la distinction absent / non
saisi — ne valent que s'ils sont **lisibles ici**. Un quota que le chef ne voit pas est un quota
que le membre a rempli pour rien.

Second enjeu : le commentaire du mois. « Pas plus d'un weekend, garde des enfants » est souvent
la moitié utile d'une décision, et c'est la seule information de cet écran qui soit une phrase et
non un état. Une phrase enfouie derrière une icône que personne ne survole est une phrase jamais
lue, et le membre qui l'a écrite s'en apercevra au premier weekend attribué.

## 2. Résultat et preuve

**Résultat.** Le chef ouvre le mois, voit en un regard **quelles journées sont mal couvertes**,
puis, membre par membre, qui peut prendre quoi et à quel prix. Il repart avec une décision, pas
avec une liste à recopier.

**Preuve, dans l'ordre :**

1. Soixante membres × soixante-deux colonnes s'affichent **en moins de deux secondes**
   (critère d'acceptation du ticket), mesurées sur un build `--profile` dans un vrai navigateur
   — pas en test de widgets (`DESIGN.md § Coût de la case dense, mesuré`).
2. Les quotas affichés **sont** ceux de `v_member_load` : la fonction les rend déjà joints, aucun
   calcul n'est refait côté Dart (second critère d'acceptation, et la seule façon durable de le
   tenir).
3. Une journée sans personne de disponible se voit **avant tout défilement**, sans compter les
   cases à l'œil.
4. Le commentaire d'un membre se lit **sans aucun geste** quand il existe.

**Ce que la base donne déjà, et qu'il ne faut pas redemander.** `availability_matrix(station,
period)` rend une ligne par membre actif : nom affiché, commentaire du mois, plafonds déclarés,
charge, restes, astreintes acceptées sur les trois mois précédents, et deux chaînes d'un
caractère par jour (`.` non saisi, `D` disponible, `A` absent). **Les trois filtres de l'écran et
le compte de couverture se dérivent de ces données, sans un seul aller-retour réseau.** Une
recherche qui déclenche une requête serait une régression sur un jeu de 60 lignes déjà en
mémoire.

## 3. Direction retenue

Le monde visuel est posé : **le registre de garde** (`DESIGN.md`). Cet écran est celui où la
métaphore cesse d'être une métaphore. Un registre mural de caserne, c'est exactement ça : des
noms en marge, des jours en tête, des cases cochées, un filet plus gras le lundi.

**La thèse structurelle : deux axes figés, un seul objet mobile.** La colonne des noms ne bouge
jamais horizontalement, l'en-tête des dates ne bouge jamais verticalement, et le coin où les deux
se croisent ne bouge pas du tout. Ce qui défile, c'est la feuille. C'est le geste d'un doigt posé
sur une ligne pendant qu'on suit une colonne, et c'est la seule chose qui rende une matrice de
3 720 cases navigable.

**Le moment focal : la ligne « Disponibles ».** Sous l'en-tête des dates, épinglée avec lui, une
ligne d'un chiffre par colonne : combien de pompiers sont disponibles ce jour-là, sur ce créneau.
C'est la première chose que le chef lit, avant d'avoir défilé d'un pixel, et c'est elle qui lui
dit où regarder. Un zéro y est hachuré : il se voit à un mètre et il se voit en noir et blanc.

**Conséquence d'implémentation assumée.** L'arithmétique est impitoyable et il faut la dire :
62 colonnes × 30 px + 280 px de colonne figée = **2 140 px**. Le mois entier ne tient sur aucun
écran de bureau ordinaire. Un poste à 1 920 px en montre 22 jours, un portable à 1 440 px en
montre 14. **Le défilement horizontal n'est donc pas un repli, c'est le régime normal**, et tout
le reste du brief en découle : les repères verticaux (lundi, weekend, aujourd'hui), la barre de
défilement toujours visible, et le fait que l'en-tête épinglé porte la date en toutes lettres et
pas seulement un numéro.

## 4. Périmètre et limites

**Livré :** l'écran « Planning du mois » avec sa matrice, sa ligne de couverture, ses trois
filtres, son sélecteur de mois, sa saisie par l'admin, et la vue « par jour » du téléphone.

**Pas livré, et à ne pas esquisser :** aucun créneau, aucune attribution, aucun candidat, aucune
publication, aucun `realtime`, aucune proposition automatique. Ces objets appartiennent aux
tickets 017, 018 et 019. Les emplacements qui leur sont réservés sont **nommés et vides** (§ 6.8),
jamais dessinés en gris comme une promesse.

**Anti-objectifs explicites :**

- Pas de réordonnancement de colonnes, pas de redimensionnement de la colonne figée, pas
  d'export. Rien de tout cela n'est au ticket.
- Pas de sélection multiple ni de peinture par glissement dans la matrice. Le glissement du
  ticket 011 est un geste que le membre fait **sur ses propres cases** ; peindre trente cases
  d'un coup sur le mois de quelqu'un d'autre est exactement ce qu'un écran de saisie par
  procuration ne doit pas rendre facile.
- Pas de graphique, pas de jauge, pas de pourcentage de couverture. Le taux de saisie a déjà son
  écran (ticket 014, `v_period_completion`) et le dupliquer ici ferait deux chiffres pour une
  chose.
- Pas de `realtime`. Deux admins qui construisent en même temps, c'est le ticket 017. Ici, un
  bouton « Rafraîchir » nommé, et c'est tout.

## 5. États et plages de contenu

### 5.1 Plages réelles

| Grandeur | Minimum | Typique | Maximum retenu |
|---|---|---|---|
| Membres actifs | 1 | 25 | **60** (cible du produit) |
| Jours du mois | 28 | 30 | 31 |
| Colonnes | 56 | 60 | **62** |
| Cases | 56 | 1 500 | **3 720** |
| Membres ayant saisi | 0 | 40 sur 60 | 60 |
| Membres ayant écrit un commentaire | 0 | 5 à 10 | 60 |
| Longueur d'un commentaire | 1 | ~90 caractères | 280 (borne posée par le client au 013 — **la base ne la garantit pas**, tronquer proprement) |
| Longueur d'un nom affiché | 2 | « Jean-Marc Dubois » | non borné — `display_name` est un `text` libre (ticket 009) |
| Plafond d'astreintes | `null` (illimité) | 3 à 6 | 20 |
| Reste d'astreintes | **négatif** (au-delà) | 0 à 6 | `null` (illimité) |

Deux valeurs piègent : **`null` ne veut pas dire zéro, il veut dire illimité**, et **le reste peut
être négatif** parce que le PRD autorise l'admin à dépasser un quota. Un écran qui grise un
illimité ou qui affiche `0` à la place de `−1` ment sur les deux cas qui comptent.

### 5.2 Les états de l'écran

| État | Ce qu'on voit |
|---|---|
| **Chargement** | Squelette **à la forme de la matrice** : colonne figée de 12 lignes grises, en-tête de dates gris, damier de cases grises. Jamais un `CircularProgressIndicator` au centre (`DESIGN.md § Don't`). |
| **Aucune période** | `EmptyState`, icône `event_busy`, « Aucun mois ouvert », action **« Ouvrir un mois »** → `/admin/periodes`. |
| **Aucun membre actif** | `EmptyState`, icône `group_off`, action **« Inviter un membre »** → `/admin/membres/inviter`. |
| **Mois vierge** (aucun membre n'a rien saisi) | La matrice s'affiche **quand même**, entièrement en « non saisi » — c'est la vérité du mois. Bannière `information` : « Personne n'a encore saisi octobre. » |
| **Filtre sans résultat** | `EmptyState` à la place de la grille, la barre de commande reste. « Aucun membre ne correspond à « dupond ». » + action **« Effacer la recherche »**. |
| **Mois verrouillé** | Bannière `verrouille` — **et la matrice reste vivante** : l'admin peut encore saisir (PRD § 6.3). Aucune hachure sur la grille (§ 7.3). |
| **Caserne suspendue** | Bannière `lecture-seule`. L'interrupteur de saisie est désactivé **et la raison est écrite à côté**, pas seulement dans la bannière. |
| **Hors ligne** | Bannière `hors-ligne`. La matrice déjà chargée reste lisible ; l'interrupteur de saisie est désactivé avec sa raison. **Aucune file d'attente d'écriture** ici (§ 7.4). |
| **Échec d'enregistrement d'une case** | La case prend le contour 2 dp `error` de `SlotChip.erreur` **et garde la valeur demandée**. Bannière `erreur` avec « Réessayer ». Un rechargement rétablit la valeur du serveur. |
| **Échec de lecture, matrice déjà affichée** | Bannière `erreur` + « Réessayer ». **On ne vide pas l'écran** pour annoncer l'échec d'une relecture (même règle qu'au 014). |
| **Échec de lecture, écran vide** | `EmptyState.erreur` + « Réessayer ». |
| **`forbidden`** | Ne devrait pas arriver : `redirectionAuth` ferme `/admin`. Traité quand même : `EmptyState`, « Réservé aux administrateurs de la caserne. » |
| **`period_not_found`** | L'URL porte un mois qui n'existe plus. Retour silencieux au mois par défaut + `SnackBar` « Ce mois n'existe plus. » |
| **Écran étroit ou texte > ×1.6** | La matrice **change de forme** : vue « par jour » (§ 6.6). Ce n'est pas une erreur, c'est la même donnée autrement. |

### 5.3 Ce que ces états ne font jamais

- Aucun état ne remplace la matrice par un message quand la matrice est juste. Une erreur de
  relecture, un mois vierge, un mois verrouillé : la grille reste.
- Aucun état n'est porté par la couleur seule. Le zéro de la ligne « Disponibles » est un
  **chiffre** avant d'être une teinte ; le dépassement de quota est un **signe moins**.
- Le verrouillage n'est jamais rouge (`DESIGN.md § Do's` : c'est un fait, pas une panne).

## 6. Interaction et layout

### 6.1 La composition, `large` (≥ 1200 dp) — la référence

```
┌ rail ┬──────────────────────────────────────────────────────────────────┐
│      │ Planning du mois                    [membres][params][périodes][↻]│  AppBar
│      ├──────────────────────────────────────────────────────────────────┤
│      │ (bannière, au plus une)                                          │
│      ├──────────────────────────────────────────────────────────────────┤
│      │ [Octobre 2026 ▾] [🔍 Rechercher] [Masquer non saisis] [Trier ▾]  │  barre de commande
│      │ [⌨ Saisir à la place]     ✓ Disponible ✗ Absent · Non saisi   ⟳ │  (collée, 2 rangs)
│      ├────────────┬─────────────────────────────────────────────────────┤
│      │            │  L    M    M    J    V    S    D    L   …           │  ┐
│      │ Membre     │  1    2    3    4    5    6    7    8   …           │  │ bloc
│      │ Astr. W-E  │ ☀🌙  ☀🌙  ☀🌙  ☀🌙  ☀🌙  ☀🌙  ☀🌙  ☀🌙  …           │  │ épinglé
│      │            │ ╌╌╌╌ réservé ticket 017 : créneaux à pourvoir ╌╌╌╌  │  │ (2 axes
│      │ Disponibles│  4 3  5 2  4 2  6 3 ▒0▒2  8 5  7 4  3 1  …          │  ┘  figés)
│      ├────────────┼─────────────────────────────────────────────────────┤
│      │ Dubois J-M │  ✓ ✓  ✓ ·  · ·  ✗ ✗  · ·  ✓ ✓  ✓ ·  · ·  …          │
│      │   2/3  1/1 │                                                     │
│      │ ⌐ Pas plus d'un weekend, garde des enfants.                      │  2ᵉ ligne
│      │ Martin A.  │  · ·  ✓ ✓  ✓ ✓  · ·  ✓ ·  · ·  · ·  ✓ ✓  …          │
│      │   −1/4 0/2 │                                                     │
└──────┴────────────┴─────────────────────────────────────────────────────┘
        ↑ colonne figée                    ↑ défile horizontalement ────────►
```

**De haut en bas :**

1. **Barre d'application** `AppScaffold`, titre « Planning du mois ». Actions : liens vers les
   trois autres écrans admin + « Rafraîchir ». Sur `compact`, les trois liens se replient dans un
   menu `more_vert` **avec leurs libellés en clair** — quatre icônes plus un titre ne tiennent pas
   sur 320 dp, et un menu nommé vaut mieux qu'une icône devinée.
2. **Zone de bannière**, au plus une, priorité de `AppBannerVariante`.
3. **Barre de commande**, collée sous la bannière, deux rangs sur `large`, qui se replie en
   `Wrap` dès que la place manque. Elle ne défile pas : ses contrôles pilotent ce qui est en
   dessous.
4. **Le bloc épinglé** : en-tête des dates (2 niveaux), l'emplacement du ticket 017, puis la ligne
   « Disponibles ». Épinglé verticalement, solidaire horizontalement de la grille.
5. **La grille**, virtualisée sur les deux axes.
6. **`filActions` reste vide** en 016 : c'est la place du bouton « Publier » du ticket 019.
7. **`panneauLateral` reste vide** en 016 : c'est la place du panneau de candidats du ticket 017.

Marge de page 32 (`large`), contenu **non borné à 1440** — c'est le seul écran du produit qui a
le droit de prendre toute la largeur disponible, parce que chaque pixel gagné est une demi-journée
de plus à l'écran.

### 6.2 La colonne figée et l'en-tête de ligne

Largeur **280 dp** en `large`, **240 dp** en `expanded`. Fixe, non redimensionnable.

| Zone | Largeur | Contenu |
|---|---|---|
| Nom | reste | `display_name`, `corps-secondaire` 14/20, une ligne, `TextOverflow.ellipsis`. Le nom complet en info-bulle **et** en sémantique. |
| Astreintes | 48 | `2/3` en `nombre-petit` mono tabulaire, précédé de `event_available` 14 dp |
| Weekends | 48 | `1/1` idem, précédé de `weekend` 14 dp |

**Hauteur de ligne : 32 px** (case 28 + 2 px d'écart en haut et en bas), portée à **52 px** quand
le membre a écrit un commentaire. Les deux hauteurs sont exactes et partagées par la colonne
figée et par la grille : une ligne est une ligne des deux côtés, sinon tout se décale.

**Le commentaire n'est pas derrière une icône.** Quand il existe, il s'écrit **en clair, sous le
nom**, sur une seconde ligne de 20 px : icône `chat_bubble_outline` 14 dp + le texte en `mention`
13, tronqué à une ligne, le texte entier en info-bulle et en sémantique. Un interrupteur
« Commentaires » dans la barre de commande replie toutes ces secondes lignes d'un coup pour qui
veut la grille la plus serrée possible ; **il est ouvert par défaut**.

> Pourquoi cette dépense. Dix membres sur soixante écrivent un commentaire : la vue coûte 200 px
> de défilement vertical, un axe qui n'est pas contraint ici. Les cinquante autres lignes ne
> paient rien. Une icône à survoler aurait coûté zéro pixel et cent pour cent des lectures.

**Les quotas, et les trois cas que le schéma autorise :**

| Cas | Rendu | Sémantique |
|---|---|---|
| Plafond posé, reste > 0 | `2/3`, encre `on-surface` | « 2 astreintes restantes sur 3 » |
| Plafond posé, reste = 0 | `0/3`, encre `etat-attente` | « quota d'astreintes atteint » |
| Plafond posé, reste < 0 | `−1/3`, encre `etat-attente-sur-fond` sur fond `etat-attente-fond`, rayon 4 | « 1 astreinte au-delà de ce qu'il acceptait » |
| **Aucun plafond** (`null`) | **la charge seule, sans barre de fraction** : `3`, encre `on-surface-variant` | « 3 astreintes ce mois, pas de plafond » |

La barre de fraction **est** le signe qu'un plafond existe. Son absence dit l'illimité sans
écrire un mot qui ne tient pas dans 48 px, et sans le `∞` que le ticket 013 a déjà proscrit. Le
zéro et le signe moins sont des caractères : la couleur ne fait que les renforcer.

`accepted_previous` **n'est pas affiché** — le ticket n'en demande pas de colonne et 48 px de
plus la coûteraient à la grille. Il vit dans l'info-bulle et la sémantique du bloc quotas
(« … , 4 astreintes acceptées sur les trois mois précédents ») et il sera le second critère de
tri des candidats du ticket 017.

**Toucher l'en-tête de ligne** déplie le commentaire en entier (trois lignes maximum) et le
replie. Rien d'autre : pas de panneau, pas de fiche, pas de modale. La place du panneau est
réservée au 017 et deux panneaux concurrents sur le même écran seraient une dette immédiate.

### 6.3 L'en-tête des dates et la lecture des 62 colonnes

Colonne : **28 px de large, 2 px d'écart**, soit 30 px de pas. Une journée = deux colonnes
solidaires, soit 58 px, séparée de la suivante par 4 px.

**En-tête, deux niveaux, 56 px au total :**

- Niveau 1, sur les deux colonnes du jour : la lettre du jour en `etiquette` 12 (`L M M J V S D`)
  au-dessus du numéro en `nombre-petit` 15 mono tabulaire.
- Niveau 2, une par colonne : `light_mode` / `bedtime` 14 dp. C'est le **seul** endroit où les
  icônes de créneau sont écrites — soixante-deux petits soleils répétés dans la grille seraient du
  bruit, exactement comme au ticket 011.

**Les quatre repères verticaux**, sans lesquels 62 colonnes sont une bouillie :

| Repère | Rendu |
|---|---|
| Début de semaine | **filet 2 dp `outline`** à gauche de chaque lundi, sur toute la hauteur de la grille |
| Weekend et jour férié | fond `surface-dim` sur les deux colonnes, sur toute la hauteur ; lettre du jour en gras |
| Jour férié | `star` 12 dp `tertiary` dans l'en-tête, **et le nom du férié** en info-bulle et en sémantique |
| Aujourd'hui | **filet 2 dp `primary`** à gauche de la colonne du jour, sur toute la hauteur (`DESIGN.md` : le filet du jour courant est l'un des emplois de `primary`) |

Les fériés et les unités de weekend sont **calculés côté application** par
`lib/core/l10n/jours_feries.dart` (ticket 011), dont la parité avec les fonctions SQL de la
migration 0017 est testée des deux côtés. Ne pas redemander au serveur ce qui est déjà juste en
mémoire.

**La croix de repérage.** La case survolée au pointeur, ou focalisée au clavier, teinte **son
en-tête de date et son en-tête de ligne** (fond `secondary-container`) — pas sa ligne ni sa
colonne entières, qui repeindraient 90 cases par mouvement de souris. Deux petits rectangles
suffisent à répondre à « quel membre, quel jour ». C'est une aide de lecture, pas un accès : rien
ne dépend du survol.

**La barre de défilement horizontale est toujours visible** (`Scrollbar(thumbVisibility: true)`,
encre `outline`). Sur macOS, une barre qui s'efface au repos transforme un défilement de 2 000 px
en découverte par accident.

### 6.4 La ligne « Disponibles » — le premier regard

Une ligne de 28 px, dernière du bloc épinglé, un chiffre par colonne : **le nombre de membres
actifs marqués `D` sur ce créneau**. Calculée côté client sur les chaînes déjà chargées, zéro
requête.

| Compte | Rendu |
|---|---|
| `0` | fond **hachuré** ocre (`Hachures`, le motif déjà employé par « absent » et « verrouillé »), chiffre `0` en `etat-attente-sur-fond` |
| `1` | fond `etat-attente-fond`, chiffre en `etat-attente` |
| `≥ 2` | fond `surface-container-high`, chiffre en `on-surface-variant` |

Chiffre en `etiquette` 12 mono tabulaire. Au-delà de 99 — impossible à 60 membres — le nombre est
tronqué à `99`.

**Le compte ignore les filtres.** Masquer les non-saisis ou chercher « Dubois » ne change jamais
ce chiffre : c'est le nombre de pompiers disponibles dans la caserne, pas dans la vue. Un compte
de couverture qui bouge quand on tape dans un champ de recherche est un mensonge sur l'état du
mois.

**Pourquoi deux seuils seulement.** L'effectif requis par créneau (`station_settings`,
`required_count`) appartient au ticket 017 ; le comparer ici serait inventer une règle que le
ticket ne demande pas. Zéro et un se justifient seuls : personne, ou personne en réserve.

Libellé « Disponibles » dans le coin figé, en `etiquette` 12. Sémantique de chaque cellule :
« Samedi 6 octobre, nuit : 2 disponibles ».

### 6.5 La saisie à la place d'un membre

C'est une action inhabituelle, tracée en base, qui écrit sur les données de quelqu'un d'autre.
Elle est traitée comme telle, en trois temps.

**1. Un mode, pas un geste.** La matrice s'ouvre **en lecture**. Les cases sont inertes : aucun
`State`, aucun `Focus`, aucun `MouseRegion` (c'est le budget mesuré au ticket 004). Un
interrupteur nommé dans la barre de commande, **« Saisir à la place d'un membre »**
(`Icons.edit_note`), arme l'écriture.

**2. Un mode qui se voit sans le lire.** Mode armé :

- une **bannière `attention` permanente** : « Tu saisis à la place des membres. Chaque
  modification est enregistrée à ton nom. » — non fermable tant que le mode est armé ;
- un **liseré 2 dp `tertiary`** autour de la zone de grille entière ;
- le curseur passe à `SystemMouseCursors.click` sur les cases.

Trois signaux, dont deux ne demandent pas de lire. Le mode se désarme par l'interrupteur ou par
`Échap`, et **se désarme tout seul au changement de mois** : le mois quitté ne laisse jamais un
écran armé derrière lui.

**3. Une confirmation, la première fois, et une seule.** À l'armement initial — repère local par
navigateur, même mécanique que `RepereAccueil` du ticket 011 — un **dialogue** (le cas rare où
`DESIGN.md` autorise une modale : écriture irréversible sur les données d'un tiers) :

> **Saisir à la place d'un membre**
> Tu vas modifier les disponibilités d'un autre pompier. Chaque modification est enregistrée à
> ton nom dans l'historique de la caserne. Le membre n'est pas prévenu.
> [ Annuler ] [ **Saisir à sa place** ]

Ensuite, l'interrupteur arme sans rien demander : redemander à chaque fois apprend à cliquer
« Oui » sans lire.

**Le geste.** Clic sur une case : **même cycle qu'au ticket 011** — non saisi → disponible →
absent → non saisi. Un chef qui a vu l'écran d'un pompier ne réapprend rien. Au clavier : flèches
pour déplacer le focus, `Espace` ou `Entrée` pour cycler, `Origine` / `Fin` pour le premier et le
dernier jour du mois.

**Le défilement automatique du focus doit poser la case en dehors du bloc épinglé et de la colonne
figée** (WCAG 2.4.11). Une case focalisée à demi cachée sous l'en-tête des dates est un défaut
bloquant.

**Ce qu'une case saisie par l'admin montre.** Dans la session, la case modifiée garde un **contour
2 dp `tertiary`** (nouveau drapeau `saisiParAdmin` de `SlotChip`, priorité sous `erreur` et sous
`selectionne`) et sa sémantique dit « saisi par toi ». **Cette marque ne survit pas à un
rechargement**, et c'est une limite assumée : `availability_matrix` ne rend pas `set_by`. La trace
durable est l'audit, pas la grille. Une extension possible est notée au § 7.6.

**Ce que le client n'écrit pas.** `set_by` est posé par le déclencheur `availabilities_trace_auteur`
(migration 0012). L'écran fait un `upsert` sur `(station_id, user_id, date, slot)` et un `delete`
pour revenir à « non saisi » — rien d'autre, et surtout pas une RPC d'écriture inventée.

**Aucune file d'attente hors ligne.** Le ticket 011 persiste ses écritures parce qu'un pompier
saisit dans une remise sans réseau. Un chef de centre est à son bureau ; et une écriture différée
sur les disponibilités **d'un tiers**, rejouée une heure plus tard sans qu'il la voie partir,
serait pire que l'échec. Échec = case en erreur + « Réessayer », visible tout de suite.

**Sur un mois verrouillé, tout ceci fonctionne** : c'est précisément le droit que le PRD § 6.3
donne à l'admin. La bannière `verrouille` le dit en seconde ligne : « Tu peux encore saisir à la
place d'un membre. »

### 6.6 Le téléphone, et l'honnêteté

**Sur `compact` (< 600 dp) et `medium` (600–839 dp), la matrice n'existe pas.** 360 dp moins la
colonne des noms laissent 240 px, soit quatre jours. Faire défiler sept écrans pour atteindre le
28 n'est pas une consultation, c'est une punition.

**Ce que le chef voit à la place : la vue « par jour ».** Une journée à la fois, tous les membres.

```
┌──────────────────────────────────┐
│ Planning du mois            [↻⋮] │
│ [Octobre 2026 ▾]                 │
│ ◄ ven. 2 │ SAM. 3 │ dim. 4 ►     │  ruban des jours, défilant
│    4 2   │  8 5   │  7 4         │  le compte de disponibles y vit
├──────────┴────────┴──────────────┤
│              ☀ Jour    🌙 Nuit   │  en-tête épinglé
├──────────────────────────────────┤
│ Dubois Jean-Marc    [ ✓ ] [ ✓ ]  │
│ 2/3 astr. · 1/1 w-e              │
│ ⌐ Pas plus d'un weekend, garde…  │
├──────────────────────────────────┤
│ Martin Alice        [ · ] [ ✗ ]  │
│ −1/4 astr. · 0/2 w-e             │
└──────────────────────────────────┘
```

- **Le ruban des jours** porte le même compte de disponibles que la ligne du grand écran : on
  balaie le mois et on voit les trous, sans matrice.
- **Une ligne membre** fait 76 dp : nom en `corps` **16 sp** — la taille de base, enfin possible —,
  quotas en clair sur la seconde ligne, commentaire sur la troisième quand il existe. Deux
  `SlotChip` en densité `confortable` **48 dp**, avec 8 dp entre elles.
- **La saisie à la place d'un membre marche ici aussi**, mode armé compris : ce sont des cibles de
  48 dp, pas la densité dense. Rien n'est perdu sauf la vue à deux dimensions.
- La barre de commande garde la recherche, le masquage et le tri ; la légende passe sous le ruban.
- Une ligne de fait, en `mention`, sous la barre de commande : **« La matrice complète s'ouvre sur
  un écran large. »** Un fait, pas une excuse, et pas un lien vers rien.

**Bascule.** `expanded` (≥ 840 dp) et au-delà : la matrice. En dessous : la vue par jour. **Et
au-delà de ×1.6 d'échelle de texte, la vue par jour reprend à toutes les largeurs** — la règle de
`DESIGN.md § Typography` dit que la matrice change de forme plutôt que de rogner son texte, et
c'est exactement ce cas.

**Tablette tactile en paysage (840–1199 dp).** La matrice s'affiche, mais la densité `dense` reste
**inerte au doigt** (`SlotChipDensite.actionnableDans`) : on lit, on ne saisit pas. Pour saisir sur
une tablette, on tourne l'appareil et on retrouve la vue par jour. C'est la règle de `DESIGN.md`,
sans exception, et l'interrupteur de saisie porte alors sa raison : « Saisie possible sur écran
large avec une souris, ou depuis la vue par jour. »

### 6.7 Les filtres, le tri et le mois

Tous côté client, sur les 60 lignes déjà en mémoire.

| Contrôle | Comportement |
|---|---|
| **Sélecteur de mois** | Même composant qu'au ticket 011 (rangée de boutons de 64 dp, état de la période en seconde ligne). Mois par défaut : **le mois le plus proche à venir, mois courant inclus** — le chef construit octobre en septembre, pas novembre. Le mois voyage dans l'URL (`?mois=AAAA-MM`). |
| **Recherche** | `ChampTexte` avec `search`, 280 dp, « Rechercher un membre ». Insensible à la casse **et aux accents**. Débounce 200 ms. Bouton `close` pour effacer. |
| **Masquer les non-saisis** | `FilterChip` « Masquer ceux qui n'ont rien saisi ». Masque les membres dont les deux chaînes ne contiennent que des `.`. Le libellé dit ce qu'il masque, jamais « Filtrer ». |
| **Trier** | Menu nommé, trois valeurs : **Nom** (défaut, l'ordre que rend déjà la fonction), **Astreintes restantes**, **Weekends restants**. |
| **Commentaires** | `FilterChip` d'affichage, ouvert par défaut (§ 6.2). |
| **Compte affiché** | En `mention` à droite : « 47 membres sur 60 » dès qu'un filtre est actif, avec une action **« Tout afficher »**. |

**L'ordre du tri par quota restant est décroissant, et `null` passe en tête.** Un illimité est la
plus grande capacité disponible, pas l'absence de capacité — le ranger en queue mettrait les
membres les plus disponibles hors de vue. Égalités départagées par `accepted_previous` croissant
puis par le nom : c'est **exactement** l'ordre des candidats du PRD § 5.3, et le chef retrouvera
le même classement au ticket 017.

**Les filtres ne vont pas dans l'URL.** Seul le mois y va. Trois contrôles qui empilent chacun une
entrée d'historique transformeraient le bouton retour du navigateur en machine à défaire des
filtres.

### 6.8 Les places réservées, nommées et vides

| Ticket | Objet | Emplacement exact |
|---|---|---|
| **017** | ligne des créneaux à pourvoir (`0/1`, `1/1`, sur-pourvu) | dans le bloc épinglé, **entre l'en-tête des dates et la ligne « Disponibles »**, hauteur 28 px, même pas de colonne |
| **017** | panneau des candidats d'un créneau | `AppScaffold.panneauLateral` en `large`, feuille de bas d'écran en dessous. **Un seul panneau à la fois** : c'est pour lui que l'en-tête de ligne n'en ouvre pas un second (§ 6.2) |
| **019** | progression, retardataires, états de réponse | un bandeau pleine largeur **sous la barre de commande, au-dessus du bloc épinglé**, hauteur ≤ 56 dp. Les états d'attribution enrichissent la ligne du 017, ils n'ajoutent pas un quatrième rang |
| **019** | bouton « Publier » | `AppScaffold.filActions`, vide en 016 |

Rien de tout cela n'est dessiné, ni grisé, ni annoncé à l'écran en 016. Une place réservée se
tient dans le code et dans ce tableau, pas dans l'interface.

### 6.9 Détails de facture

- **Virtualisation sur les deux axes, obligatoire.** Seules les lignes **et** les colonnes
  visibles sont construites. `TwoDimensionalScrollView` du framework, ou `TableView` de
  `two_dimensional_scrollables` (paquet Dart pur, compatible web) — `flutter-dev` tranche.
  **Interdit :** deux `SingleChildScrollView` imbriqués, qui construiraient les 3 720 cases.
- **Le défilement est synchronisé** : la colonne figée partage le contrôleur vertical de la
  grille, le bloc épinglé partage son contrôleur horizontal. Un décalage d'un pixel entre le nom
  et sa ligne rend l'écran faux.
- **Aucune animation dans la matrice** (`DESIGN.md § Motion`). Une case qui change ne fait pas
  bouger ses voisines ; le mois qui se charge n'entre pas en cascade.
- **Sélection de texte neutralisée** sur la grille : sur le web, un glissement surligne la moitié
  de l'écran en bleu système.
- **Chiffres tabulaires** partout où un nombre s'aligne : dates, quotas, comptes.
- **Séparation par filet, jamais par ombre.** La colonne figée est séparée par un **filet 2 dp
  `outline`** permanent, le bloc épinglé par le même en bas. Pas d'ombre portée qui apparaîtrait
  au défilement.
- **Anneau de focus 2 dp `primary`**, jamais supprimé, y compris sur une case pleine.
- **Une ligne = un objet observable.** Chaque ligne observe sa propre tranche d'état : changer une
  case ne reconstruit pas les 59 autres membres.

## 7. Contraintes et décisions

### 7.1 Ce que la base garantit, et ce que l'écran doit en faire

- **`availability_matrix` lève `forbidden`** pour un non-admin. La route est déjà fermée par
  `redirectionAuth` ; l'écran traite quand même le cas.
- **La chaîne est indexée à partir de 0 : `jours[jour − 1]`.** Un décalage d'un se voit à l'œil sur
  la première colonne, et c'est le premier test à écrire.
- **La longueur des chaînes est le nombre de jours du mois** — 28, 30 ou 31. Ne jamais supposer 31.
- **`.` non saisi, `D` disponible, `A` absent.** Trois caractères, pas un de plus. Un caractère
  inconnu se rend comme « non saisi » sans faire planter la grille.
- **`shifts_left` / `weekends_left` valent `null` quand le plafond est `null`**, et peuvent être
  **négatifs**. Les deux cas ont un rendu défini au § 6.2 ; aucun ne se coerce à zéro.
- **`comment` est un `text` sans contrainte de longueur** en base. La borne de 280 caractères est
  posée par le client au ticket 013 : tronquer à l'affichage, ne pas la supposer.
- **Aucune colonne inventée.** La fonction rend quatorze champs ; l'écran n'en attend pas un
  quinzième.

### 7.2 Le budget de deux secondes

Le ticket 004 a mesuré la structure : une case dense inerte ne coûte plus aucun `State` et treize
éléments. **Ce qui reste à faire ici, c'est la mesure de bout en bout** : `flutter build web
--profile`, 60 membres × 62 colonnes, chronomètre entre l'arrivée sur la route et la première
image de la grille peinte, sur un navigateur réel. C'est un critère d'acceptation, pas une
intention, et un test de widgets en mode debug ne le prouve pas (`DESIGN.md § Coût de la case
dense, mesuré`).

Ce qui tient le budget, dans l'ordre d'importance : la virtualisation à deux axes, l'absence de
`State` par case en lecture, le décodage des chaînes **une fois** au chargement (pas à chaque
`build`), et le fait que les filtres ne rechargent rien.

### 7.3 Écarts à `DESIGN.md`, à reporter dans la PR

| Point | Ce que dit `DESIGN.md` | Ce que fait ce brief | Pourquoi |
|---|---|---|---|
| Mois verrouillé | « fond hachuré gris, cases non interactives », hachures sur la grille entière | La matrice de l'admin **reste vivante et non hachurée** ; le fait est dit par la bannière | Le verrouillage vise le membre. Le PRD § 6.3 donne explicitement à l'admin le droit de saisir sur un mois verrouillé, et un motif hachuré sur 3 720 cases détruirait la lecture de l'écran central du produit. |
| `SlotChip` | cinq états visuels, `selectionne` / `verrouille` / `enEnregistrement` / `erreur` + les trois de disponibilité | un sixième drapeau, **`saisiParAdmin`**, contour 2 dp `tertiary`, priorité sous `erreur` et `selectionne` | Une saisie par procuration doit se distinguer d'une saisie du membre au moment où elle se fait. Le contour est le seul signal qui tienne à 28 px sans écraser le glyphe. |
| Navigation | la destination « Admin » ouvre `/admin/membres` | elle ouvre **`/admin/planning`** | Le ticket pose cet écran comme « la vue centrale de l'admin ». La destination doit tomber sur le travail, pas sur l'annuaire. Les trois autres écrans restent à un clic dans la barre d'application. |
| Largeur de contenu | `large` : contenu centré, maximum 1440 | la matrice n'est **pas bornée** | Chaque pixel de largeur est un demi-jour de mois visible. C'est le seul écran du produit dans ce cas, et la borne reste pour tout le reste. |

### 7.4 Décisions tranchées pendant ce brief

1. **Le téléphone ne montre pas la matrice.** Vue « par jour », même donnée, même saisie, à 48 dp.
   Une matrice illisible sur six pouces aurait coché la case « consultable sur téléphone » du
   ticket en trahissant son intention.
2. **La ligne « Disponibles » ignore les filtres.** Un compte de couverture qui bouge à la frappe
   est un mensonge.
3. **Le commentaire est affiché, pas indiqué.** Seconde ligne en clair, repliable, ouverte par
   défaut.
4. **La saisie par l'admin est un mode armé, pas un clic.** Trois signaux visibles, une
   confirmation unique, `Échap` pour sortir, désarmement au changement de mois.
5. **Pas de file d'attente hors ligne.** Écrire en différé sur les disponibilités d'un tiers est
   pire que l'échec visible.
6. **Pas de `realtime` en 016.** Un bouton « Rafraîchir » nommé ; le temps réel arrive avec les
   attributions, au 017.
7. **Le tri par quota est décroissant, `null` en tête**, égalités départagées comme les candidats
   du PRD § 5.3.
8. **Un seul panneau latéral sur l'écran**, réservé au 017.

### 7.5 Ce qu'un développeur ne doit pas inventer ici

- Aucun effectif requis, aucun créneau, aucune attribution, aucun candidat, aucun bouton
  « Publier ».
- Aucun seuil de couverture autre que 0 et 1.
- Aucune requête déclenchée par un filtre, une recherche ou un tri.
- Aucune RPC d'écriture : `upsert` et `delete` sur `availabilities`, `set_by` laissé au
  déclencheur.
- Aucun `∞`, aucun emoji, aucun glyphe Unicode en guise d'icône.
- Aucune chaîne en dur dans un widget : tout passe par `AppStrings`.

### 7.6 Décisions ouvertes

- **Rendre `set_by` dans la matrice.** Un quatrième et cinquième caractère (`d` et `a` minuscules
  pour « posé par un admin ») dans les chaînes de `availability_matrix` rendrait la marque de
  saisie par procuration **durable** au lieu de vivre le temps d'une session. C'est une migration,
  donc `supabase-dev`, et le ticket ne la demande pas : à proposer pour le 017, qui touchera la
  même fonction.
- **Le repère de première confirmation est local au navigateur.** Un chef qui change de poste
  reverra le dialogue une fois. Acceptable ; le stocker en base serait une colonne de préférence
  qui n'existe pas.
- **Quatre icônes dans la barre d'application admin.** Le repli en menu `more_vert` est spécifié
  pour `compact` ; si l'encombrement se voit aussi en `medium`, appliquer la même règle et le
  signaler.

## 8. Widgets Flutter

### 8.1 Réemployés tels quels

| Composant | Emploi |
|---|---|
| `AppScaffold` | ossature, barre d'application, bannière, `panneauLateral` et `filActions` laissés vides |
| `AppBanner` | `verrouille`, `information`, `attention` (mode armé), `erreur`, `hors-ligne`, `lecture-seule` |
| `SlotChip` densité `dense` | les 3 720 cases de la matrice |
| `SlotChip` densité `confortable` | les deux cases de la vue par jour |
| `Hachures` | fond du compte « 0 disponible » |
| `EmptyState`, `EmptyState.erreur` | aucune période, aucun membre, filtre sans résultat, non-admin, échec |
| `LoadingSkeleton` | squelette à la forme de la matrice |
| `ChampTexte` | recherche |
| `AppDivider` | filets de la colonne figée et du bloc épinglé |
| `SaveIndicator` | état d'enregistrement, dans la barre de commande |
| `StatusBadge` | état de la période dans le sélecteur de mois |
| `PrimaryButton` | actions des états vides |
| `jours_feries.dart` | fériés et unités de weekend, **calculés, jamais redemandés** |
| `PeriodeSaisie` + `periodes_providers` | liste des mois et leur état |

### 8.2 À étendre dans `lib/core/`

- **`SlotChip`** : drapeau `saisiParAdmin` (contour 2 dp `tertiary`), priorité après `erreur` et
  `selectionne`. La case reste sans `State` ; le drapeau est une valeur, pas un état interne.

### 8.3 À créer dans `lib/core/widgets/`

- **`legende_etats.dart` — `LegendeEtats`** : les trois cases denses + leurs libellés, en ligne ou
  en `Wrap`. Réemployable par les tickets 017, 019 et 023, qui montreront tous une grille d'états.

Rien d'autre ne monte dans `core`. La matrice à deux axes figés est un objet de cet écran et de
ses successeurs immédiats : la généraliser avant d'avoir un second appelant serait une abstraction
inventée.

### 8.4 À créer dans `lib/features/planning/`

Nouvelle feature — les tickets 017, 018 et 019 s'y installeront.

**`data/`**
- `matrice_repository.dart` : appel de `availability_matrix`, `upsert` et `delete` sur
  `availabilities`. Traduction des erreurs `forbidden` et `period_not_found`.

**`domain/`**
- `ligne_matrice.dart` : le modèle d'une ligne, **décodage des deux chaînes une seule fois**,
  accès `etatDe(jour, creneau)` en temps constant, `aSaisiQuelqueChose`, quotas typés
  (`null` = illimité, entiers négatifs conservés).
- `matrice_mois.dart` : l'ensemble des lignes + les comptes de disponibles par colonne, calculés
  une fois et invalidés à chaque écriture locale.
- `matrice_filtres.dart` : recherche insensible aux accents, masquage, tri. **Pur et testable
  sans widget.**
- `matrice_providers.dart` : chargement, mois courant, état du mode armé, file d'écritures en vol.

**`presentation/`**
- `matrice_screen.dart` : l'écran, la bascule matrice / vue par jour, les bannières.
- `widgets/barre_commande_matrice.dart` : mois, recherche, filtres, tri, mode armé, légende,
  indicateur d'enregistrement.
- `widgets/entete_dates.dart` : les deux niveaux d'en-tête + les repères verticaux.
- `widgets/ligne_disponibles.dart` : la ligne de couverture.
- `widgets/entete_ligne_membre.dart` : nom, quotas, commentaire, dépliage.
- `widgets/grille_matrice.dart` : la vue à deux axes virtualisée et ses contrôleurs synchronisés.
- `widgets/vue_jour.dart` : la composition du téléphone, ruban des jours compris.
- `widgets/confirmation_saisie_admin.dart` : le dialogue de première fois.
- `widgets/squelette_matrice.dart` : le chargement.

### 8.5 Tests attendus

| Test | Ce qu'il protège |
|---|---|
| Décodage des chaînes sur 28, 30 et 31 jours | le décalage d'un, le mois court |
| Caractère inconnu dans une chaîne | la grille ne plante pas, la case est « non saisi » |
| Quotas `null`, `0` et négatifs | les trois rendus du § 6.2, et surtout pas de coercition à zéro |
| Tri par quota restant | décroissant, `null` en tête, égalités par `accepted_previous` puis nom |
| Recherche « dupond » ↔ « Dupond » ↔ « Dupónd » | l'insensibilité aux accents |
| Ligne « Disponibles » sous filtre actif | le compte **ne bouge pas** |
| Mode armé | cases inertes tant qu'il n'est pas armé ; désarmé au changement de mois ; `Échap` |
| Confirmation de première fois | affichée une fois, pas deux |
| Mois verrouillé | l'admin écrit quand même, la bannière le dit |
| Caserne suspendue / hors ligne | interrupteur désactivé **avec sa raison affichée** |
| Échec d'écriture | case en erreur, valeur conservée, bannière « Réessayer » |
| Largeur 390 dp et échelle ×1.7 | la vue par jour prend la main |
| 60 × 62 en test de widgets | garde-fou grossier (10 s), **pas** un budget — la mesure réelle est au navigateur |
| Sémantique | nom complet, quotas en phrase, case en phrase complète, compte de disponibles |

## 9. Textes

Toutes les chaînes dans `AppStrings`, préfixe `matrice`. Tutoiement, phrases courtes, vocabulaire
de caserne.

### 9.1 Écran et navigation

| Clé | Texte |
|---|---|
| `matriceTitre` | Planning du mois |
| `matriceRafraichir` | Rafraîchir |
| `matriceVersMembres` | Membres de la caserne |
| `matriceVersParametres` | Réglages de la caserne |
| `matriceVersPeriodes` | Mois de saisie |
| `matriceReserveAdmin` | Cet écran est réservé aux administrateurs de la caserne. |

### 9.2 Barre de commande

| Clé | Texte |
|---|---|
| `matriceRechercheLibelle` | Rechercher un membre |
| `matriceRechercheEffacer` | Effacer la recherche |
| `matriceMasquerNonSaisis` | Masquer ceux qui n'ont rien saisi |
| `matriceAfficherCommentaires` | Commentaires |
| `matriceTrier` | Trier |
| `matriceTriNom` | Nom |
| `matriceTriAstreintes` | Astreintes restantes |
| `matriceTriWeekends` | Weekends restants |
| `matriceCompteFiltre` | {n} membres sur {total} |
| `matriceToutAfficher` | Tout afficher |
| `matriceEcranLarge` | La matrice complète s'ouvre sur un écran large. |

### 9.3 En-têtes et légende

| Clé | Texte |
|---|---|
| `matriceColonneMembre` | Membre |
| `matriceColonneAstreintes` | Astr. |
| `matriceColonneWeekends` | W-E |
| `matriceLigneDisponibles` | Disponibles |
| `matriceLegendeTitre` | Légende |
| *(états)* | « Disponible », « Absent », « Non saisi » — descripteurs existants du ticket 004, réemployés |

### 9.4 Quotas et commentaire

| Clé | Texte |
|---|---|
| `matriceQuotaAstreintes` | {reste} astreintes restantes sur {max} |
| `matriceQuotaAstreintesAtteint` | Quota d'astreintes atteint : {max} sur {max} |
| `matriceQuotaAstreintesDepasse` | {n} astreintes au-delà de ce qu'il acceptait |
| `matriceQuotaWeekends` | {reste} weekends restants sur {max} |
| `matriceQuotaWeekendsAtteint` | Quota de weekends atteint : {max} sur {max} |
| `matriceQuotaWeekendsDepasse` | {n} weekends au-delà de ce qu'il acceptait |
| `matriceQuotaSansPlafond` | {n} astreintes ce mois, pas de plafond |
| `matriceChargePrecedente` | {n} astreintes acceptées sur les trois mois précédents |
| `matriceCommentaireVide` | Pas de commentaire ce mois |

### 9.5 Saisie à la place d'un membre

| Clé | Texte |
|---|---|
| `matriceModeSaisie` | Saisir à la place d'un membre |
| `matriceModeSaisieActif` | Tu saisis à la place des membres. Chaque modification est enregistrée à ton nom. |
| `matriceModeSaisieQuitter` | Quitter le mode saisie |
| `matriceConfirmationTitre` | Saisir à la place d'un membre |
| `matriceConfirmationTexte` | Tu vas modifier les disponibilités d'un autre pompier. Chaque modification est enregistrée à ton nom dans l'historique de la caserne. Le membre n'est pas prévenu. |
| `matriceConfirmationValider` | Saisir à sa place |
| `matriceConfirmationAnnuler` | Annuler |
| `matriceCaseSaisieParAdmin` | Saisi par toi |
| `matriceSaisieIndisponibleTactile` | Saisie possible sur écran large avec une souris, ou depuis la vue par jour. |
| `matriceSaisieIndisponibleSuspendue` | Caserne suspendue : lecture seule. |
| `matriceSaisieIndisponibleHorsLigne` | Hors ligne : la saisie reprendra au retour du réseau. |

### 9.6 États vides, erreurs, faits

| Clé | Texte |
|---|---|
| `matriceAucunePeriodeTitre` | Aucun mois ouvert |
| `matriceAucunePeriodeTexte` | Ouvre un mois de saisie pour commencer à construire un planning. |
| `matriceAucunePeriodeAction` | Ouvrir un mois |
| `matriceAucunMembreTitre` | Aucun membre actif |
| `matriceAucunMembreTexte` | Invite des pompiers pour qu'ils saisissent leurs disponibilités. |
| `matriceAucunMembreAction` | Inviter un membre |
| `matriceMoisViergeTexte` | Personne n'a encore saisi {mois}. |
| `matriceAucunResultatTitre` | Aucun membre ne correspond |
| `matriceAucunResultatTexte` | Aucun membre ne correspond à « {recherche} ». |
| `matriceVerrouilleTexte` | Saisie verrouillée depuis le {date}. Tu peux encore saisir à la place d'un membre. |
| `matriceErreurTexte` | Impossible de charger la matrice. |
| `matriceErreurEcriture` | Impossible d'enregistrer cette case. |
| `matriceMoisIntrouvable` | Ce mois n'existe plus. |
| `actionReessayer` | Réessayer *(existant)* |

### 9.7 Sémantique

| Clé | Texte |
|---|---|
| `matriceCaseSemantique` | {prénom} {nom}, {jour} {date}, {créneau}, {état} |
| `matriceCaseAction` | Appuie pour le marquer {état suivant} |
| `matriceDisponiblesSemantique` | {jour} {date}, {créneau} : {n} disponibles |
| `matriceDisponiblesAucun` | {jour} {date}, {créneau} : personne de disponible |
| `matriceLigneSemantique` | {nom}. {quotas}. {commentaire} |

## 10. Checklists

### 10.1 Craft floor (Impeccable)

| Point | État |
|---|---|
| **Contraste** | Aucun couple nouveau. Tout vient de `DESIGN.md`, ratios déjà mesurés : disponible 6.55:1, absent 7.47:1, non saisi 6.32:1, ocre d'attente 5.82:1, texte 17.24:1. Le chiffre de couverture est en `on-surface-variant` sur `surface-container-high`, couple existant. ✓ |
| **Profondeur** | **Zéro ombre sur cet écran.** La colonne figée et le bloc épinglé se séparent par un filet 2 dp `outline`, jamais par une ombre portée au défilement. ✓ |
| **Espacement** | Échelle de 4 exclusivement : pas de colonne 30 (28 + 2), ligne 32 ou 52, en-tête 56, marge de page 32. ✓ |
| **Typographie** | Aucune taille nouvelle. Chiffres tabulaires sur dates, quotas et comptes. Le nom en 14 dans la matrice, en **16** dans la vue par jour — la taille de base revient dès que la place existe. Textes réels à ×1.0, ×1.6, ×2.0. ✓ |
| **Motion** | **Rien ne bouge dans la matrice** (`DESIGN.md § Motion`). Seuls l'indicateur d'enregistrement et l'apparition d'une bannière animent, aux durées existantes. Le tampon reste réservé à l'acceptation d'une astreinte. ✓ |
| **États** | Survol, focus, pressé, désactivé (avec raison), chargement, vide, filtre vide, erreur de lecture, erreur d'écriture, hors ligne, verrouillé, suspendu, non-admin : tous au § 5.2. ✓ |
| **Surfaces du navigateur** | Barre de défilement horizontale **thématisée et toujours visible**, curseur `click` sur les cases armées, sélection de texte neutralisée sur la grille, anneau de focus thématisé, chiffres tabulaires. C'est l'écran où ces quatre détails décident de la crédibilité. ✓ |
| **Copie** | Chaque contrôle nomme son action (« Masquer ceux qui n'ont rien saisi », pas « Filtrer »). Chaque erreur nomme le problème et la sortie. Chaque contrôle désactivé porte sa raison. Tutoiement partout. ✓ |
| **Couverture** | Les cinq points du ticket sont traités et localisables : matrice et colonne figée (§ 6.1–6.3), en-tête de ligne avec quotas et commentaire (§ 6.2), trois états de cellule (§ 6.3, `DESIGN.md`), filtres (§ 6.7), saisie par l'admin (§ 6.5). Les deux critères d'acceptation ont leur § dédié (7.2 pour les 2 s, § 2 et § 6.2 pour `v_member_load`). ✓ |
| **Refus** | Pas de carte comme structure, pas de métrique héroïque, pas de surtitre, pas de jauge ni d'anneau de progression, pas de dégradé, pas de glyphe Unicode, pas de modale **sauf** la confirmation de saisie par procuration, qui est exactement le cas que `DESIGN.md` autorise (écriture irréversible sur les données d'un tiers). ✓ |

### 10.2 Checklist application mobile (ui-ux-pro-max)

**Qualité visuelle** — pas d'emoji ✓ · une seule famille d'icônes, Material Icons ✓ · l'état pressé
ne déplace aucune limite de mise en page ✓ · tokens sémantiques uniquement, zéro couleur en dur ✓.

**Interaction** — cibles de 48 dp partout où un doigt agit : vue par jour, barre de commande,
sélecteur de mois ✓ · **la densité 28 px n'est jamais servie au doigt**, la règle de `DESIGN.md`
tient sans exception et l'interrupteur porte sa raison sur tablette tactile ✓ · pas de survol ni
de clic droit comme seul accès : la croix de repérage est une aide, le commentaire est affiché,
les liens admin sont dans un menu nommé ✓ · aucun conflit de geste : pas de glissement de
sélection dans cet écran (§ 4) ✓ · retour du navigateur et geste retour iOS fonctionnels, le mois
étant dans l'URL ✓.

**Clair / sombre** — les deux thèmes existent depuis le ticket 004 et **les deux doivent être
vérifiés**, en particulier les hachures du compte « 0 » et le liseré ocre du mode armé sur fond
sombre ⚠︎ *(à faire à l'implémentation)*.

**Mise en page** — zones sûres respectées sur la vue par jour (`viewPadding.bottom` + navigation)
✓ · rien ne se cache derrière le bloc épinglé, y compris la case focalisée au clavier
(§ 6.5, WCAG 2.4.11) ✓ · quatre classes de fenêtre décrites, **à vérifier sur 320, 390, 840,
1280 et 1920 dp** ⚠︎ *(à faire à l'implémentation)* · le commentaire et les états vides sont bornés
en mesure de lecture ; la grille ne l'est pas, et n'a pas à l'être ✓.

**Accessibilité** — chaque case porte une phrase complète avec le nom du membre, la date, le
créneau et l'état ✓ · **la couleur n'est jamais seule** : remplissage, texture, glyphe, puis
teinte pour les cases ; chiffre puis hachures pour la couverture ; signe moins puis fond pour le
dépassement ✓ · navigation clavier complète, ordre de focus identique à l'ordre visuel, focus
jamais masqué ✓ · Reduce Motion sans objet (rien n'anime dans la grille) ✓ · tailles dynamiques :
au-delà de ×1.6, changement de forme et non troncature ✓ · pas de contenu auto-défilant ✓.

**Point resté ouvert, écrit et non dissimulé** — un utilisateur de lecteur d'écran parcourt la
matrice case par case, sans accélérateur de ligne ou de colonne. La vue par jour, plus linéaire,
lui est un meilleur chemin ; elle n'est pourtant pas proposée explicitement sur grand écran. À
reconsidérer si un besoin remonte.
