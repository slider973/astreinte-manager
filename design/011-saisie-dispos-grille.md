# 011 — Grille de saisie des disponibilités

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web
mobile-first**, Material 3, une seule apparence sur toutes les cibles.

`DESIGN.md` gagne sur ce brief pour toute valeur de token. Deux points seulement s'en écartent,
avec leur démonstration et leur report au § 7.3 : la forme de la grille sur téléphone, et l'usage
de `SlotChip.enEnregistrement`.

Sources : `docs/PRD.md § 5.2` et `§ 6.3`, `docs/SCHEMA.md § 2.5–2.7`,
`tickets/in-progress/011-saisie-dispos-grille.md`, `design/004-design-system.md`.

---

## 1. Job et audience

**Un sapeur-pompier volontaire, debout, une fois par mois.** Il a reçu un rappel, ou il a deux
minutes avant de repartir. Il sait déjà, dans sa tête, ce qu'il va donner : « mes nuits, sauf la
semaine du 12 où je suis en vacances ». Il ne vient pas explorer, il vient **déverser** une
intention déjà formée.

La scène est toujours la même : dehors ou dans la remise, en pleine lumière, le téléphone d'une
main, parfois avec des gants, jamais assis. Aisance numérique très variable — de l'adjudant de
55 ans qui n'installe rien à l'étudiant qui vit dans son téléphone. Les deux doivent réussir.

**Ce qui se joue.** C'est l'écran le plus ouvert du produit et le seul qui porte le chiffre du
PRD : **un mois saisi en moins de deux minutes**, contre soixante-deux touches case par case sur
l'intranet remplacé. Si cet écran est aussi lent que l'ancien, le produit n'a plus qu'un argument
au lieu de deux, et le taux de saisie avant date limite (> 90 %) ne suit pas.

Second enjeu, plus discret : c'est ici que naît la distinction **absent** / **non saisi**. Un mois
à moitié vide ne dit pas à l'admin si le pompier est en vacances ou s'il a oublié. Chaque case
« absente » posée ici est une relance que le chef de centre ne fera pas.

## 2. Résultat et preuve

**Résultat.** Le membre ouvre le mois ouvert à la saisie, pose ses créneaux, et repart sans avoir
cherché de bouton « Enregistrer ». Il sait, en quittant l'écran, combien de jours, de nuits et de
weekends il a donnés, et que c'est parti.

**Preuves mesurables, reprises des critères d'acceptation du ticket.**

| Preuve | Mesure |
|---|---|
| Un mois complet au glissement | **< 30 s**, deux gestes continus (une colonne « jour », une colonne « nuit ») |
| Un mois typique (mes nuits + un weekend + une semaine d'absence) | **< 60 s** |
| Une perte de réseau en cours de saisie | la grille reste éditable, l'écran le dit, et tout repart seul au retour du réseau |
| Lisibilité des trois états | distinguables **en niveaux de gris**, à 40 cm, au soleil |
| Coût réseau d'une peinture de 40 cases | **2 requêtes**, pas 40 |

**Preuve produit.** Le registre de garde tient en une page. Cet écran aussi : un mois est **une
seule liste continue**, jamais une pagination par semaine, jamais un détail à ouvrir.

## 3. Direction retenue

**Autorité visuelle.** Le monde du registre de garde, établi au ticket 004, sans ajout. La case du
registre (`SlotChip`) et le jour (`DayCell`) ont été dessinés pour cet écran : ce brief les emploie,
il n'en invente pas.

**Thèse structurelle — le registre, pas le calendrier.** Sur téléphone, le mois est une **liste
réglée d'une ligne par jour**, à trois colonnes : `Date | Jour | Nuit`. Pas une grille calendaire
de sept colonnes.

La raison est arithmétique et elle est bloquante. Une cible tactile fait 48 dp, l'écart minimal
entre deux cibles fait 8 dp (`DESIGN.md § Cibles tactiles`, § Espacement). Sept colonnes de cases
réclament donc `7 × 48 + 6 × 8 = 384 dp` de grille nue. Un téléphone de 360 dp offre `360 − 32 =
328 dp` entre ses marges ; un 320 dp en offre 288. **La grille calendaire à sept colonnes ne rentre
pas sur un téléphone**, et la faire rentrer coûte soit des cases de 43 dp (sous le plancher WCAG),
soit des écarts de 2 dp (l'erreur de saisie garantie avec des gants). Sur l'écran le plus important
du produit, on ne paie ni l'une ni l'autre.

Ce que la liste gagne en échange :

1. **Trois colonnes au lieu de sept** : chaque case fait ~104 × 48 dp sur un téléphone de 360. Un
   couloir de peinture large comme un pouce ganté.
2. **La peinture devient verticale et longue.** « Toutes mes nuits » est un seul geste qui descend
   la colonne de droite. C'est exactement le geste que le chiffre des deux minutes exige.
3. **C'est le registre lui-même** : « des colonnes réglées, une ligne par entrée »
   (`DESIGN.md § Overview`). La grille calendaire de l'intranet remplacé était l'**anti-référence**
   du ticket 004 ; la reproduire au pixel près sur téléphone était l'erreur à ne pas faire.

La forme calendaire n'est pas abandonnée : elle revient dès `expanded` (≥ 840 dp), où la largeur la
paie honnêtement et où voir la forme du mois a une vraie valeur. C'est la même donnée, deux
compositions, une seule règle de geste (§ 6.2).

**Thèse d'interaction — la touche et le pinceau sont le même geste.** Une touche fait avancer la
case d'un cran. Un appui long suivi d'un glissement fait avancer d'un cran la case d'origine, puis
**pose cette valeur** sur toutes celles que le doigt traverse. Rien à apprendre en plus : le
pinceau, c'est la touche qui continue.

**Moment focal.** Pendant la peinture, la barre du bas cesse d'être un tableau de bord et devient
le pinceau : elle affiche la valeur en cours de pose (marque + icône + libellé) pendant que les
trois compteurs grimpent sous le doigt. C'est le seul moment où l'écran parle. Il se termine quand
le doigt se lève.

**Conséquence d'implémentation.** L'enregistrement automatique ne part **jamais** pendant un geste :
la file est retenue tant que le doigt est posé, puis vidée 500 ms après le relâchement, en deux
requêtes au plus. Un mois peint est donc une seule transition d'indicateur, pas quarante.

## 4. Périmètre et limites

**Dans le ticket.**

- L'écran « Mon mois » : sélecteur de mois, grille du mois, barre de compteurs.
- Les trois valeurs d'affichage : disponible, absent, non saisi (absence de ligne en base).
- La touche simple, la peinture au glissement, le clavier.
- L'enregistrement automatique avec indicateur, la reprise après échec, la file hors ligne.
- Les compteurs jours / nuits / weekends.
- Le mois verrouillé, la caserne suspendue, le hors-ligne, l'erreur, le mois vierge.
- Les weekends et les jours fériés français, calculés.

**Hors du ticket, et la place qui leur est réservée.**

| Sujet | Ticket | Place réservée par ce brief |
|---|---|---|
| Raccourcis (« tous les weekends », « copier le mois précédent »…) | **012** | Une bande pleine largeur **entre le sélecteur de mois et l'en-tête de colonnes**, en `compact`/`medium` ; le **haut du panneau de droite** en `large`. Rien n'y est posé en 011 — pas de bouton fantôme, pas de place vide dessinée. |
| Quotas du mois et commentaire | **013** | Une section **sous le dernier jour du mois**, en `compact`/`medium` ; **sous les compteurs dans le panneau de droite** en `large`. De plus, les trois `CountStat` sont construits dès 011 avec `plafond: null` : 013 n'a qu'à le remplir pour obtenir « 4 / 2 weekends ». |
| Réouverture, saisie par l'admin, cron de verrouillage | **014** | L'écran **subit** le verrouillage, il ne le pilote pas. |
| Matrice admin | **016** | Aucun rapport ; la densité `dense` de `SlotChip` n'est pas employée ici. |

**Anti-objectifs explicites.**

- **Pas de bouton « Enregistrer ».** L'écran enregistre seul. Un bouton en plus mentirait sur qui
  fait le travail et ajouterait un état « modifications non enregistrées » à gérer.
- **Pas de mode pinceau.** Aucune barre « Je pose : disponible / absent / effacer » qui resterait
  armée. Un mode invisible, avec des gants, à 6 h du matin, est la pire panne possible : chaque
  case toucherait alors autre chose que ce que le doigt croit.
- **Pas de changement de mois au glissement horizontal.** Le glissement appartient à la peinture.
  Le mois se change par les boutons du sélecteur.
- **Pas d'annulation générale (« Annuler ma dernière action »).** La case est son propre annulateur :
  une touche de plus la ramène. Un historique serait un troisième modèle mental.
- **Pas de modale, pas de feuille de détail par créneau.** Il n'y a rien à détailler : un créneau
  est une valeur parmi trois.

## 5. États et plages de contenu

### 5.1 Plages réelles

| Donnée | Minimum | Typique | Maximum |
|---|---|---|---|
| Jours du mois | 28 | 30 | 31 |
| Cases | 56 | 60 | 62 |
| Mois proposés au sélecteur | 1 | 3 (M en cours verrouillé, M+1 et M+2 ouverts) | 5 |
| Jours fériés dans un mois | 0 | 0–1 | 3 (mai, années à Ascension + Pentecôte) |
| Cases modifiées en une session | 1 | 20–25 | 62 |
| Échelle de texte | ×0.85 | ×1.0 | ×2.0 |

### 5.2 Les états de l'écran

| État | Condition | Rendu |
|---|---|---|
| **Chargement** | période et disponibilités en vol | Sélecteur de mois réel si les périodes sont déjà en cache, sinon un `LoadingSkeleton` de sa forme. En-tête de colonnes réel. **8 lignes squelette** à la forme exacte d'une ligne de jour. Jamais de `CircularProgressIndicator`. |
| **Mois vierge** | 0 disponibilité enregistrée sur la période | La grille complète, toutes cases « non saisi », **plus un bloc d'aide** (§ 6.7) sous le sélecteur. Ce n'est pas un `EmptyState` : il n'y a rien à remplacer, la grille **est** le contenu. |
| **Mois saisi** | ≥ 1 disponibilité | La grille. Le bloc d'aide disparaît dès la première saisie de la période. |
| **Mois verrouillé** | `periods.status = 'locked'` | Bannière `verrouille` non fermable. Toutes les cases en `verrouille: true` : hachures grises, valeurs **parfaitement lisibles**, aucune interaction, aucun focus. Compteurs maintenus. Indicateur d'enregistrement retiré (il n'y a plus rien à enregistrer). Bloc d'aide jamais affiché. |
| **Caserne suspendue** | abonnement suspendu | Bannière `lectureSeule`. Même traitement des cases que le verrouillage — `SlotChip` n'a qu'un rendu de lecture seule, et c'est le bon : le motif dit « tu ne peux pas écrire », la bannière dit pourquoi. |
| **Hors ligne** | connectivité perdue | Bannière `horsLigne`. **La grille reste entièrement éditable.** Indicateur « Hors ligne ». Les modifications s'empilent. **Aucune case ne porte de contour d'erreur** : hors ligne n'est pas un échec, c'est une attente. |
| **Échec d'enregistrement** | la requête est partie et a échoué | Contour 2 dp `error` sur **les seules cases concernées**. Indicateur « Non enregistré » + « Réessayer » (`liveRegion`). Une relance automatique à 1 s, une à 4 s, puis on s'arrête et on attend l'humain ou le retour du réseau. |
| **Échec persistant** | la relance automatique a échoué à son tour | La bannière `erreur` apparaît en plus, avec « Réessayer ». C'est le seuil : un raté ne mérite pas un bandeau, un blocage si. |
| **Refus du serveur (403 / RLS)** | le mois s'est verrouillé ou la caserne s'est suspendue pendant la saisie | Bannière `erreur` : « Le mois vient d'être verrouillé. Tes dernières modifications n'ont pas été enregistrées. » + action « Recharger ». Après rechargement, l'écran passe dans son état verrouillé normal. Les cases refusées gardent leur contour d'erreur jusqu'au rechargement. |
| **Aucune période ouverte** | l'admin n'a créé aucun mois | `EmptyState` à la place de la grille : titre, explication, aucune action (le membre ne peut rien y faire, et un bouton mort serait pire que pas de bouton). |
| **Chargement impossible** | erreur réseau sans cache | `EmptyState.horsLigne` avec « Réessayer ». |

### 5.3 Ce que ces états ne font jamais

- La grille ne disparaît pas derrière un voile pendant un enregistrement. Les valeurs à l'écran
  sont la vérité que l'utilisateur vient de poser ; on ne la lui reprend pas en attendant le
  serveur.
- Un échec ne remet aucune case à son ancienne valeur. La valeur affichée reste celle voulue, et
  c'est le contour d'erreur qui dit qu'elle n'est pas arrivée. La reprise finit le travail.
- Deux bannières ne coexistent jamais : ordre `erreur > horsLigne > lectureSeule > verrouille >
  attention > information` (`AppBannerVariante.prioritaire`).

## 6. Interaction et layout

### 6.1 Le geste de saisie — la touche cyclique, tranchée

**Décision : une touche simple qui fait avancer la case d'un cran**, dans l'ordre
`non saisi → disponible → absent → non saisi`. Pas de menu contextuel, pas d'appui long pour
choisir, pas de sélecteur à trois boutons.

Pourquoi, contre les deux autres options :

| Option | Coût pour « je coche vingt nuits » | Verdict |
|---|---|---|
| **Touche cyclique** | 20 touches, ou **un seul glissement** | **Retenue.** L'action dominante (se déclarer disponible) coûte une touche depuis l'état par défaut. La cible fait 104 × 48 dp. |
| Menu contextuel (appui long → trois choix) | 20 × (appui long + visée d'un item de menu + fermeture) ≈ 60 interactions, et **aucune peinture possible** | Rejetée. Multiplie par trois le coût de l'action la plus fréquente pour rendre plus sûre la plus rare. Et elle confisque l'appui long, qui vaut beaucoup plus cher en pinceau qu'en menu. |
| Barre de mode (« je pose : disponible ») | 1 touche par case, mais un mode invisible et persistant | Rejetée (§ 4, anti-objectifs). |

L'ordre du cycle n'est pas arbitraire : il place « disponible » à une touche du repos, « absent » à
deux, « effacer » à trois — exactement l'ordre décroissant des fréquences réelles. Les libellés
d'action existent déjà dans `AppStrings` (`slotActionMarquerDisponible`, `slotActionMarquerAbsent`,
`slotActionEffacer`) et `DayCell` les branche déjà.

**Le dépassement est sans gravité, et c'est ce qui rend le cycle acceptable avec des gants.** Une
touche de trop mène toujours à un état visible, immédiat, et réversible d'une touche de plus ; et
comme rien ne part sur le réseau avant 500 ms de calme, une correction rapide ne coûte même pas une
requête.

**Retour d'appui.** État pressé de `SlotChip` au `pointerDown` (assombrissement de 8 % de l'encre
d'état, **sans changement de taille ni de bordure** : rien ne doit bouger sous un doigt ganté).
La valeur change au relâchement. Animation `instantane` (120 ms), supprimée sous Reduce Motion.

**Pas de retour haptique.** Sur le canal web, `HapticFeedback` ne se déclenche pas. Un signal qui
n'existe que sur une cible qu'aucune caserne n'a demandée n'est pas un signal ; le prétendre serait
concevoir pour un appareil imaginaire.

### 6.2 Le glissement continu — la peinture

**Ce qui démarre le geste.**

- **Au doigt** (toutes classes de fenêtre) : **appui long d'environ 300 ms sur une case, puis
  glissement.** Au moment où l'appui est accepté, trois choses arrivent ensemble : la case d'origine
  avance d'un cran, elle prend le contour 2 dp `primary` de `SlotChip(selectionne: true)`, et la
  barre du bas bascule en indicateur de pinceau. **La valeur obtenue par ce cran est le pinceau.**
- **Au pointeur fin** (`context.estPointeurFin`) : **pression et mouvement suffisent**, sans délai.
  Une souris ne fait pas défiler la page en tirant le contenu ; il n'y a rien à départager.

Pourquoi l'appui long et pas une amorce directionnelle (« part horizontal, continue où tu veux ») :
la peinture utile ici est **verticale** (descendre une colonne de nuits), donc elle entre en
concurrence frontale avec le défilement de la page. Imposer une amorce horizontale obligerait à
tracer un crochet avant chaque colonne — un geste que personne ne connaît et que des gants rendent
imprécis. L'appui long, lui, est le vocabulaire universel du « je prends cet objet » (réordonner une
liste, sélectionner du texte), il ne vole **rien** au défilement, et il s'auto-annonce : la case se
sélectionne sous le doigt au moment exact où le geste devient disponible.

**Ce que fait le geste.**

- Chaque case traversée est **mise à la valeur du pinceau**, jamais cyclée. Repasser dessus ne fait
  rien. C'est ce qui rend un aller-retour inoffensif.
- **Chemin libre, pas rectangle** : seules les cases que le doigt traverse changent. Un weekend
  entier (samedi jour, samedi nuit, dimanche jour, dimanche nuit) se peint par un trait en Z sur
  deux lignes. Le remplissage rectangulaire serait plus tolérant mais deviendrait destructeur au
  moindre dépassement, et il interdirait les tracés en peigne.
- Les cases inertes (hors du mois dans la vue calendaire, mois verrouillé) sont **traversées sans
  effet** : `DayCell` ne leur passe pas de `onDragEnter`.
- Pour qu'un glissement rapide ne saute pas de case, le segment entre deux positions de pointeur est
  échantillonné au plus tous les **16 dp** (un tiers de hauteur de case) et chaque point est testé.

**Comment il cohabite avec le défilement vertical.** Totalement : le défilement n'est jamais
intercepté. Un doigt posé et tiré fait défiler la page, partout, y compris sur une case. Seul
l'appui maintenu ouvre la peinture. C'est la règle `Gesture Conflicts` de ui-ux-pro-max
(« Custom gestures must not break system scroll/back », sévérité High) appliquée sans exception.

**Comment il cohabite avec le geste retour depuis le bord gauche de l'iPhone.**

- Dans la vue registre (téléphone), la bande des 24 premiers dp ne contient **aucune case** : c'est
  la colonne « Date ». Le conflit n'existe pas.
- Dans la vue calendaire (tablette, ordinateur), une peinture **ne peut pas démarrer** à moins de
  `max(MediaQuery.systemGestureInsets.left, 24 dp)` du bord gauche. Une touche simple y fonctionne
  normalement ; seule l'initiation du glissement est refusée. Une peinture déjà en cours, elle,
  couvre tout l'écran sans restriction — le geste système a déjà perdu l'arène.

**Le bord haut et le bord bas de l'écran — le défilement automatique.** Quand le doigt en peinture
entre dans la bande des **72 dp** haute ou basse de la zone de grille visible, la page défile
d'elle-même, et les cases qui passent sous le doigt sont peintes. Vitesse : rampe linéaire de 0 au
bord intérieur de la bande à **400 dp/s** au bord de l'écran. 400 dp/s, c'est 3,5 lignes de jour par
seconde : assez rapide pour couvrir les 1 736 dp d'un mois de 31 jours en 4,3 s, assez lent pour
qu'on voie les cases se remplir. Le défilement s'arrête net aux extrémités du mois. Il est
**maintenu sous Reduce Motion** : ce n'est pas une décoration, c'est le déplacement du document ;
il est simplement appliqué par saut de frame, sans courbe.

**Ce qui termine le geste.**

| Événement | Effet |
|---|---|
| Le doigt se lève | Fin normale. Les valeurs peintes sont confirmées, le délai de 500 ms démarre, la barre revient aux compteurs. Annonce `liveRegion` : « 14 cases mises à jour, disponible ». |
| Le doigt sort de la grille (barre du bas, marge, hors écran) | Le geste **continue** et ne peint rien ; rentrer dans la grille reprend la peinture au même pinceau. |
| **Un second doigt se pose** (zoom, appui accidentel) | **Annulation**. Toutes les cases touchées par ce geste reprennent la valeur qu'elles avaient à son démarrage, y compris la case d'origine. Annonce : « Peinture annulée ». |
| **Échap** (clavier, pointeur fin) | Même annulation. C'est la convention du bureau, et elle rejoint celle du doigt. |
| Changement de route, application mise en arrière-plan, apparition d'une bannière d'erreur | Fin immédiate, **sans** annulation : ce qui est peint est peint, et part. |
| Un 403 arrive pendant le geste | Fin immédiate, la grille bascule en lecture seule, la bannière explique. |

L'annulation est **gratuite et sûre** parce que **rien ne part sur le réseau pendant un geste** :
le délai de 500 ms ne démarre qu'au relâchement. L'instantané d'avant-geste est déjà en mémoire —
c'est le même que celui de la reprise après échec.

**Équivalents obligatoires** (ui-ux-pro-max, « No Gesture-Only Actions », sévérité Critical). Aucune
valeur n'est atteignable **uniquement** par le glissement :
- la touche simple sur chaque case ;
- le clavier : `Tab` et les flèches parcourent la grille dans l'ordre visuel, `Espace` et `Entrée`
  font avancer la case d'un cran (`SlotChip` gère déjà `ActivateIntent`) ;
- les raccourcis du ticket 012, qui donneront le même résultat en une touche.

**Lecteur d'écran.** Un utilisateur de VoiceOver ou TalkBack ne peut pas peindre : il saisit case
par case, chacune annoncée en phrase complète et basculée par le geste d'activation standard. C'est
un écart de vitesse reconnu, et il se referme au ticket 012, dont les raccourcis sont de simples
boutons. À noter dans la revue, pas à masquer.

**Coût du pinceau « absent ».** Peindre une plage d'absence depuis des cases vierges demande une
touche (vierge → disponible) puis un appui long glissé (disponible → absent, puis pose). Deux
gestes au lieu d'un. C'est assumé : l'absence est un cas de vacances, contigu et mensuel, alors que
la disponibilité est le geste de tous les mois. Le raccourci du ticket 012 le ramènera à une touche.

### 6.3 Le retour visuel de l'enregistrement

**Un seul endroit.** L'état d'enregistrement vit dans la barre du bas, à gauche des compteurs, en
`SaveIndicator` **plein** (icône + libellé). La variante `compact` n'est pas employée ici : un
nuage seul, dont le libellé n'apparaît qu'au survol, n'est pas lisible pour le public de cette app.

**La séquence, et pourquoi elle ne clignote pas.**

1. Repos à l'ouverture : « À jour » (`SyncEtat.repos`).
2. **Première** modification de la session : « Enregistrement… ». L'indicateur y reste tant que la
   file n'est pas vide. Toutes les modifications suivantes — les quarante cases d'une peinture —
   **ne changent rien à l'affichage** : elles rejoignent une file dont l'état est déjà annoncé.
3. Vidage de la file réussi : « Enregistré », une seule fois, avec la pulsation d'apparition
   `courant` (180 ms).
4. « Enregistré » **reste** jusqu'à la modification suivante. Il ne retombe pas sur « À jour » :
   cette retombée serait un clignotement de plus, sans information nouvelle.

Donc **une session de peinture produit exactement deux transitions** : une à la première case, une
au retour du serveur. Le seul mouvement continu est la rotation de l'icône `sync`, déjà le seul
mouvement perpétuel autorisé par `DESIGN.md`, et supprimée sous Reduce Motion.

**Pendant un geste, l'indicateur laisse la place au pinceau.** De l'acceptation de l'appui long au
relâchement, la fente de gauche affiche « Tu peins : Disponible » avec la marque et l'icône de
l'état. Cela résout trois choses d'un coup : la peinture devient visible pendant qu'elle a lieu, le
pinceau est nommé, et l'indicateur d'enregistrement ne peut pas bouger au moment le plus agité. Les
trois compteurs, eux, **restent affichés et montent en direct** sous le doigt : c'est la vérification
immédiate du geste.

**Aucune pulsation par case.** `SlotChip.enEnregistrement` n'est **pas** employé sur cet écran.
Quarante contours qui pulsent, c'est un jeu de lumière, pas une information ; et l'état
d'enregistrement est global par construction, puisque la file part en bloc. La pulsation par case
reste au catalogue pour un écran qui enregistrerait une case isolée. Écart à reporter dans
`DESIGN.md § Écarts d'implémentation`.

**Ce qui est envoyé.** À l'expiration du délai de 500 ms suivant la dernière modification :
la file est **coalescée** (une seule entrée par couple date + créneau, la dernière gagne), puis
envoyée en **deux requêtes au plus** — un `upsert` de toutes les lignes `disponible`/`absent`, un
`delete` groupé de tous les couples revenus à « non saisi ». Quarante cases peintes coûtent deux
requêtes. C'est ce qui rend le critère des 30 secondes tenable sur un réseau de caserne.

La file est aussi vidée **immédiatement**, sans attendre le délai, quand l'application passe en
arrière-plan ou quand on quitte l'écran.

**Reprise.** « Réessayer » rejoue toute la file en attente. Le retour du réseau la rejoue seul. Une
case dont l'écriture est repartie perd son contour d'erreur au succès, pas avant.

### 6.4 Les compteurs

Trois, et seulement trois : **Jours**, **Nuits**, **Weekends**. Ils comptent les créneaux
**disponibles** — jamais les absents, jamais les non saisis.

**Définitions, tranchées ici.**

- **Jours** : nombre de créneaux `jour` à l'état disponible dans le mois affiché.
- **Nuits** : idem pour les créneaux `nuit`.
- **Weekends** : nombre d'**unités de weekend** portant au moins un créneau disponible, une unité
  étant :
  - le couple samedi + dimanche d'une même semaine (`PRD § 6.3` : « une astreinte sur l'un de ces
    créneaux compte pour un weekend ») ;
  - **chaque jour férié tombant du lundi au vendredi**, qui forme à lui seul une unité (`PRD § 6.3` :
    fériés comptés comme weekend). Un férié tombant un samedi ou un dimanche se fond dans l'unité
    de ce weekend et ne compte pas deux fois ;
  - si un seul des deux jours du couple appartient au mois affiché (début ou fin de mois), ce jour
    forme à lui seul l'unité du mois. *(Hypothèse de conception : le PRD ne tranche pas le bord de
    mois. À confirmer au ticket 013, qui adossera le quota à ce même calcul.)*

**Place.** Barre fixe en bas du contenu, au-dessus de la navigation, via `AppScaffold.filActions` —
jamais posée par-dessus la grille, jamais à faire défiler pour la trouver. Composition, de gauche à
droite : l'indicateur d'enregistrement (ou le pinceau), puis les trois `CountStat` alignés à droite.
Chiffres en chasse fixe tabulaire : ils changent en place sans faire sauter la mise en page.

À grande échelle de texte (> ×1.3), la barre passe sur deux lignes — indicateur au-dessus,
compteurs en dessous — plutôt que de rogner quoi que ce soit. `CountStat` réduit déjà son nombre
plutôt que de le tronquer.

En `large`, la barre disparaît du bas et son contenu s'installe en tête du panneau de droite, les
compteurs en `grand: true`.

**Accessibilité.** La barre est un conteneur sémantique unique, étiqueté en phrase :
« Total du mois : 12 jours, 20 nuits, 4 weekends disponibles ». Elle n'est pas une `liveRegion` —
elle changerait à chaque case peinte et noierait les annonces utiles ; c'est l'annonce de fin de
geste qui porte le résultat.

**Réservé.** `CountStat` est construit avec `plafond: null` dès 011. Le ticket 013 remplit ce
plafond et ajoute son marqueur de quota atteint, sans toucher à la barre.

### 6.5 Disposition

**`compact` (< 600 dp) — le registre. La composition de référence.**

De haut en bas :

1. Barre d'application `AppScaffold`, titre « Mon mois ».
2. Bannière, au plus une (§ 5.2).
3. **Sélecteur de mois** : rangée horizontale de boutons, un par période connue, défilante au-delà
   de trois. Chaque bouton : le nom du mois et son année en `titre-bloc` (18/600), puis une ligne
   d'état en `mention` (13) précédée de son icône 16 dp — `lock_open` + « Ouvert jusqu'au 15 sept. »
   ou `lock` + « Verrouillé ». Hauteur 64 dp. Sélectionné : fond `secondary-container`, filet 2 dp
   `secondary`, encre `on-secondary-container`. Non sélectionné : fond `surface`, filet 1 dp
   `outline-variant`. Le bouton sélectionné **est** le titre de l'écran ; il n'y a pas de second
   titre qui répéterait le mois.
   *C'est aussi là que vit la date limite : une bannière `information` permanente coûterait 48 dp de
   grille sur tous les mois ouverts pour redire ce que le sélecteur dit déjà. La bannière `attention`
   (« Plus que 2 jours pour saisir octobre ») reste, elle, à J-3 et moins.*
4. **Emplacement réservé au ticket 012.** Vide en 011.
5. Bloc d'aide, si le mois est vierge ou si la peinture n'a jamais été utilisée (§ 6.7).
6. **En-tête de colonnes épinglé** (`SliverPersistentHeader(pinned: true)`) : `Date` · `Jour`
   (icône `light_mode` + libellé) · `Nuit` (icône `bedtime` + libellé), en `etiquette` 12/700,
   fond `surface-container-high`, filet bas 1 dp. Épinglé parce que c'est lui qui dit, à tout
   moment de la peinture, quelle colonne est la nuit.
7. **La liste des jours**, une ligne par jour du mois, hauteur fixe 56 dp.
8. **Emplacement réservé au ticket 013.** Vide en 011.

Tout cela dans un `CustomScrollView` unique : le mois défile d'un seul tenant, sélecteur compris.

**La ligne de jour** (`DayCell`, orientation `ligne`), trois colonnes de largeur égale séparées de
8 dp — soit ~104 dp chacune sur un téléphone de 360 dp :

| Colonne | Contenu |
|---|---|
| **Date** | Le numéro en `nombre-petit` (15 mono), le nom court du jour en `etiquette` (« sam. »), en gras si weekend ou férié. Si férié : `Icons.star` 14 dp `tertiary` **et le nom du férié en clair** en `mention`, tronqué — la place existe, et une info-bulle au survol ne serait pas un accès. |
| **Jour** | Une `SlotChip` `confortable`, 48 dp de haut, étirée sur la colonne. |
| **Nuit** | Idem. |

Réglure : filet 1 dp `outline-variant` entre deux jours ; **filet 2 dp `outline` au-dessus de chaque
lundi**, qui donne au mois son rythme hebdomadaire sans numéro de semaine. Samedi, dimanche et
fériés : fond de ligne `surface-dim`. Aujourd'hui : filet 2 dp `primary` en marge gauche de la
ligne, déjà géré par `DayCell`.

En orientation `ligne`, **l'icône du créneau n'est pas répétée dans chaque cellule** : elle vit dans
l'en-tête de colonne épinglé, et c'est la position en colonne qui distingue le jour de la nuit
(`DESIGN.md § Créneau` : « ce qui distingue le jour de la nuit est l'icône et la position »). Soixante-
deux petits soleils et lunes sur un registre seraient du bruit. La sémantique de chaque case, elle,
continue de dire « nuit » en toutes lettres. Écart à reporter dans `DESIGN.md`.

**`medium` (600–839 dp)** — même registre, contenu **borné à 560 dp et centré**. Au-delà, les cases
deviendraient absurdement larges. Navigation en `NavigationRail`, marge de page 24.

**`expanded` (840–1199 dp) — la vue calendaire.** Sept colonnes, `DayCell` en orientation `colonne`
telle que `DESIGN.md` la décrit : numéro + nom du jour + étoile de férié en tête, puis les deux cases
empilées, chacune précédée de son icône de créneau. Semaine du lundi au dimanche. Les jours des mois
voisins complètent les semaines en `horsMois: true` (atténués, inertes). Écart entre cases : 6 dp.
À 840 dp, chaque colonne fait ~108 dp et chaque case ~72 × 48 dp — le seuil où la forme calendaire
devient honnête. En-tête de colonnes épinglé : `L M M J V S D`, les deux dernières en gras.

**`large` (≥ 1200 dp)** — vue calendaire, contenu centré, largeur maximale 1440. Le
`AppScaffold.panneauLateral` (360 dp) accueille, de haut en bas : l'emplacement réservé au ticket
012, les compteurs en `grand: true`, l'indicateur d'enregistrement, puis l'emplacement réservé au
ticket 013. La barre du bas disparaît.

**Échelle de texte > ×1.6** — la vue calendaire **retombe sur le registre**, quelle que soit la
largeur (`DESIGN.md § Typography, Named Rules` : la grille change de forme plutôt que de rogner).
Dans le registre, la ligne passe à deux niveaux : la date sur une ligne, les deux cases pleine
largeur en dessous. La hauteur fixe des lignes est alors abandonnée au profit d'un `prototypeItem`.

**Zones sûres.** La barre du bas ajoute `MediaQuery.viewPadding.bottom` ; la liste reçoit un
rembourrage bas égal à la hauteur de la barre plus la navigation plus la zone sûre, pour qu'aucune
case du 31 ne se cache derrière quoi que ce soit.

### 6.6 Navigation entre les mois

- Route : la coquille d'accueil, onglet 0, avec le mois porté par l'URL en paramètre de requête
  `mois=AAAA-MM` à côté de `onglet`. Le retour du navigateur et le geste retour iOS reviennent donc
  au mois précédemment consulté, jamais à un état perdu. *(La route dédiée `/mois` annoncée dans
  `DESIGN.md § Navigation` attend que la coquille éclate en routes ; elle ne fait pas partie de ce
  ticket.)*
- Mois ouvert par défaut : **la première période `open` par ordre chronologique**. S'il n'y en a
  aucune, la période verrouillée la plus récente.
- Changer de mois avec une file en attente : la file est vidée **avant** le changement. Le mois
  quitté ne laisse jamais de modification derrière lui.

### 6.7 Apprendre le geste

Un bloc réglé, sous le sélecteur, au plus deux lignes, jamais fermable à la main — il s'efface tout
seul :

- Ligne 1, affichée tant que **le mois affiché n'a aucune saisie** : icône `touch_app`, « Appuie sur
  une case pour te déclarer disponible. Appuie encore pour t'absenter. »
- Ligne 2, affichée tant que **le membre n'a jamais terminé une peinture** sur cet appareil (repère
  local, même mécanique que `RepereAccueil`) : icône `swipe_vertical`, « Astuce : appui long puis
  glisse pour cocher plusieurs cases d'un coup. »

Le bloc disparaît dès la première saisie pour la ligne 1, dès la première peinture réussie pour la
ligne 2. Sur un mois verrouillé, il ne s'affiche jamais.

### 6.8 Détails de facture

- **Curseur** : `click` sur les cases ; pendant une peinture au pointeur fin, la grille entière
  passe en `SystemMouseCursors.cell`.
- **Sélection de texte désactivée sur la grille** : sur le web, un glissement sélectionne le texte
  et surligne la moitié du mois en bleu système. À neutraliser explicitement.
- **Anneau de focus** : 2 dp `primary`, jamais supprimé, y compris sur une case pleine
  (`SlotChip` le gère déjà, avec priorité au contour d'erreur puis de sélection).
- **Pas d'animation de liste** : une case qui change ne fait pas bouger ses voisines, un mois qui se
  charge n'entre pas en cascade.
- **Reconstruction** : une peinture ne doit pas reconstruire les 62 cases à chaque événement de
  pointeur. Chaque ligne de jour observe **sa propre** tranche d'état (sélecteur par date) ; le
  mouvement du doigt ne reconstruit que la case qui change.

## 7. Contraintes et décisions

### 7.1 Ce que la base garantit, et ce que l'écran doit en faire

- **Absence de ligne = non saisi.** « Non saisi » est une valeur d'affichage, jamais une valeur
  stockée : l'écran écrit par `upsert` et **supprime** pour revenir au vide (`SCHEMA § 2.6`).
- **La RLS refuse l'écriture** quand la période est `locked` ou la caserne non `writable`. L'écran
  ne se contente pas de griser : il traite le refus comme un état légitime (§ 5.2, 403).
- **Unicité `(station_id, user_id, date, slot)`** : l'`upsert` doit viser cette contrainte.
- Aucune colonne inventée. `set_by` n'est pas touché par cet écran : le membre saisit pour lui-même.

### 7.2 Jours fériés — calculés, pas tabulés

Calcul plutôt que table en dur sur trois ans : l'application ouvre des mois deux mois à l'avance,
indéfiniment, et une table qui périme en silence produirait un weekend manquant au compteur sans que
personne ne s'en aperçoive.

Onze fériés métropolitains : huit à date fixe (1er janvier, 1er mai, 8 mai, 14 juillet, 15 août,
1er novembre, 11 novembre, 25 décembre) et trois adossés à Pâques (lundi de Pâques = Pâques + 1,
Ascension = + 39, lundi de Pentecôte = + 50), Pâques par l'algorithme de Meeus/Butcher grégorien.
**Les fériés d'Alsace-Moselle (Vendredi saint, 26 décembre) ne sont pas traités** : ce serait un
paramètre de caserne, il n'existe pas au schéma, et rien dans le ticket ne l'appelle.

### 7.3 Écarts à `DESIGN.md`, à reporter dans la PR

| Point | Ce que dit `DESIGN.md` | Ce que fait ce brief | Pourquoi |
|---|---|---|---|
| Forme de la grille en `compact` | « grille mensuelle 7 colonnes × 2 créneaux » | registre à trois colonnes, une ligne par jour ; le calendrier 7 colonnes reprend dès `expanded` | `7 × 48 + 6 × 8 = 384 dp` contre 328 dp disponibles sur un téléphone de 360. La contrainte tactile gagne (§ 3). |
| Icône de créneau par case | « moitié haute / moitié basse », icône par case | en orientation `ligne`, l'icône vit dans l'en-tête de colonne épinglé | La position en colonne et l'en-tête épinglé portent la distinction ; 62 icônes répétées sont du bruit sur un registre. |
| `SlotChip.enEnregistrement` | prévu pour cet écran | non employé | L'enregistrement est global par construction (file en bloc). 40 contours qui pulsent ne sont pas une information. |
| Bannière `information` de date limite | listée | non employée ici ; l'information vit dans le sélecteur de mois | 48 dp de grille sur tous les mois ouverts pour une phrase déjà lisible ailleurs. |
| Route `/mois` | annoncée | onglet 0 de la coquille + paramètre `?mois=AAAA-MM` | La coquille n'éclate pas en routes dans ce ticket ; l'URL reste néanmoins porteuse d'état. |

### 7.4 Décisions tranchées pendant ce brief

1. **Touche cyclique, pas menu.** Le menu triple le coût de l'action la plus fréquente et interdit
   la peinture (§ 6.1).
2. **Appui long pour démarrer la peinture au doigt, pression directe au pointeur fin.** Le
   défilement vertical de la page n'est jamais confisqué (§ 6.2).
3. **Annulation par second doigt ou par Échap, avec restitution des valeurs d'avant-geste.** Gratuit,
   parce que rien ne part sur le réseau pendant un geste.
4. **Chemin libre, pas rectangle de sélection.**
5. **Un seul indicateur d'enregistrement, deux transitions par session, pas de pulsation par case.**
6. **La file part en deux requêtes au plus, après coalescence.**
7. **Hors ligne n'est pas une erreur** : aucune case marquée, aucune saisie bloquée.
8. **Les compteurs comptent les disponibles seulement.**
9. **Registre sur téléphone, calendrier sur grand écran**, même donnée, même règle de geste.

### 7.5 Ce qu'un développeur ne doit pas inventer ici

Un bouton « Enregistrer ». Une barre de mode pinceau. Un changement de mois au glissement
horizontal. Un « Annuler » global. Une confirmation avant d'effacer une case. Une carte par jour.
Un quatrième compteur. Un badge « Complet ». Un `CircularProgressIndicator`. Une info-bulle comme
seul accès à une information. Un placeholder pour les tickets 012 et 013.

### 7.6 Décisions ouvertes

- **Unité de weekend au bord du mois** : un dimanche 1er du mois compte-t-il comme un weekend entier
  pour le quota du mois ? Hypothèse retenue ici : oui, il forme une unité. À confirmer au ticket 013,
  qui doit utiliser exactement le même calcul côté quota et côté matrice admin.
- **Découverte de la peinture** : le repère local se perd si le membre change d'appareil ou vide son
  navigateur, et le bloc d'aide réapparaît. Accepté : un rappel de trop coûte deux lignes, un geste
  jamais découvert coûte cent vingt touches par mois.
- **« Disponible en dernier recours »**, toujours ouvert au niveau produit (`PRODUCT.md`). S'il
  arrive, il deviendra une quatrième valeur du cycle : à ce moment-là, le cycle à quatre crans devra
  être réévalué contre un sélecteur explicite. Rien à prévoir aujourd'hui.

## 8. Widgets Flutter

### 8.1 Réemployés tels quels

| Composant | Emploi |
|---|---|
| `lib/core/widgets/app_scaffold.dart` | coquille : titre, bannière, navigation, `filActions` pour la barre de compteurs, `panneauLateral` en `large` |
| `lib/core/widgets/app_banner.dart` | les cinq états de bandeau, tri par `AppBannerVariante.prioritaire` |
| `lib/core/widgets/slot_chip.dart` | la case, densité `confortable` partout sur cet écran |
| `lib/core/widgets/save_indicator.dart` | variante pleine, jamais `compact` |
| `lib/core/widgets/count_stat.dart` | les trois compteurs, `plafond: null` |
| `lib/core/widgets/empty_state.dart` | aucune période, échec de chargement |
| `lib/core/widgets/loading_skeleton.dart` | les 8 lignes de chargement |
| `lib/core/widgets/app_divider.dart` | réglures |
| `lib/core/preferences/reperes_locaux.dart` | repère « a déjà peint une fois » |

### 8.2 À étendre dans `lib/core/`

- **`lib/core/widgets/day_cell.dart`** — ajouter `DayCellOrientation { colonne, ligne }`, paramètre
  `orientation` (défaut `colonne`, l'existant ne bouge pas). En `ligne` : trois colonnes égales
  (date, jour, nuit), pas d'icône de créneau par case, nom du férié affiché en clair. Mêmes
  `DaySlot`, mêmes `Semantics`, mêmes tokens. Le catalogue `/dev/components` montre les deux
  orientations.
- **`lib/core/l10n/app_strings.dart`** — la section « Mon mois » du § 9.
- **`lib/core/l10n/format_date.dart`** — ajouter `nomJourCourt`, `nomJourLong`, et
  `dateAvecJourSemaine` (« samedi 4 octobre »), qui alimente `DayCell.dateLongue`.

### 8.3 À créer dans `lib/core/`

- **`lib/core/l10n/jours_feries.dart`** — `Set<DateTime> joursFeriesDuMois(int annee, int mois)` et
  `String? nomJourFerie(DateTime jour)`. Pâques par Meeus/Butcher. Testé sur 2026–2030 et sur les
  bords (Pâques de mars, Pentecôte de juin).
- **`lib/core/widgets/peinture_grille.dart`** — le mécanisme de peinture, isolé du métier :
  reconnaissance du geste (appui long au doigt / pression au pointeur fin), test de position par
  `MetaData`, échantillonnage du segment, défilement automatique aux bords, garde du bord gauche,
  annulation. Il ne connaît que « une case sous ce point » et « applique cette valeur ».

### 8.4 À créer dans `lib/features/dispos/`

```
lib/features/dispos/
  data/dispos_repository.dart          upsert groupé, delete groupé, lecture du mois
  domain/creneau_cle.dart              (date, créneau) — clé de file et de carte
  domain/disponibilite_mois.dart       la carte du mois + les trois compteurs + les unités de weekend
  domain/periode_saisie.dart           période, statut, date limite, libellé
  domain/dispos_providers.dart         périodes, mois sélectionné, disponibilités
  presentation/mois_screen.dart        l'écran, la composition par classe de fenêtre
  presentation/controllers/saisie_controller.dart
                                       cycle, peinture, file, coalescence, délai 500 ms,
                                       relances, reprise, instantané d'annulation
  presentation/widgets/selecteur_mois.dart
  presentation/widgets/grille_registre.dart      compact et medium
  presentation/widgets/grille_calendrier.dart    expanded et large
  presentation/widgets/entete_colonnes.dart      en-tête épinglé, les deux formes
  presentation/widgets/barre_compteurs.dart      compteurs + indicateur + pinceau
  presentation/widgets/bloc_astuce.dart
```

### 8.5 Tests attendus

- Cycle des trois valeurs, dans l'ordre, y compris le retour au vide.
- Une peinture pose la valeur du premier cran sur toutes les cases traversées, et **ne cycle pas**
  une case déjà à cette valeur.
- Une peinture annulée (second pointeur, Échap) restiture exactement l'état d'avant-geste.
- Un glissement purement vertical **sans** appui long fait défiler et ne peint rien.
- Aucune écriture réseau tant que le geste n'est pas terminé.
- 40 modifications coalescées produisent **2 requêtes**.
- Perte de réseau : aucune case en erreur, file conservée, rejeu au retour.
- Échec serveur : contour d'erreur sur les seules cases concernées, « Réessayer » rejoue tout.
- Mois verrouillé : aucune case focalisable, aucune case actionnable, valeurs lisibles.
- Compteurs : weekend avec un seul créneau coché = 1 ; férié un mardi = 1 ; férié un samedi ne
  double pas le weekend.
- Fériés : mai 2026, Pâques 2027, Pentecôte 2029.
- Échelle ×2.0 : aucune troncature, la ligne passe à deux niveaux.

## 9. Textes

Toutes les chaînes vont dans `AppStrings`, section « Mon mois (ticket 011) ». Tutoiement, phrases
courtes. Les chaînes déjà présentes sont signalées et **réemployées telles quelles**.

### 9.1 Écran et sélecteur de mois

| Clé | Texte |
|---|---|
| `navMonMois` *(existe)* | `Mon mois` |
| `moisSelecteurLabel` | `Mois à saisir` |
| `moisNomEtAnnee(mois, annee)` | `Octobre 2026` *(capitale initiale, contrairement à `moisLongs`)* |
| `moisOuvertJusquAuCourt(date)` | `Ouvert jusqu'au 15 sept.` |
| `moisVerrouilleCourt` | `Verrouillé` |
| `moisSelectionSemantique(mois)` | `Mois sélectionné : octobre 2026` |

### 9.2 En-tête de colonnes

| Clé | Texte |
|---|---|
| `grilleColonneDate` | `Date` |
| `creneauJour` *(existe)* | `Jour` |
| `creneauNuit` *(existe)* | `Nuit` |
| `grilleJoursCourts` | `['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.']` |
| `grilleJoursInitiales` | `['L', 'M', 'M', 'J', 'V', 'S', 'D']` *(vue calendaire)* |
| `grilleJoursLongs` | `['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche']` |

### 9.3 États des cases *(tous existants, réemployés)*

`etatDisponible` = `Disponible` · `etatAbsent` = `Absent` · `etatNonSaisi` = `Non saisi` ·
`slotSemantique(...)` = « samedi 4 octobre, nuit, disponible » ·
`slotActionMarquerDisponible` = `Appuie pour te marquer disponible` ·
`slotActionMarquerAbsent` = `Appuie pour te marquer absent` ·
`slotActionEffacer` = `Appuie pour effacer` · `slotVerrouille` = `Créneau verrouillé` ·
`jourAujourdhui` = `Aujourd'hui` · `jourWeekend` = `Weekend` ·
`jourFerieNomme(nom)` = `Jour férié : {nom}`.

### 9.4 Peinture

| Clé | Texte |
|---|---|
| `peintureEnCours(etat)` | `Tu peins : Disponible` |
| `peintureAnnulee` | `Peinture annulée` |
| `peintureResultat(n, etat)` | `1 case mise à jour, disponible` / `14 cases mises à jour, disponible` |
| `peintureIndiceSemantique` | `Appui long puis glissement pour cocher plusieurs cases` |

### 9.5 Bloc d'aide

| Clé | Texte |
|---|---|
| `astuceSaisieTouche` | `Appuie sur une case pour te déclarer disponible. Appuie encore pour t'absenter.` |
| `astuceSaisieGlissement` | `Astuce : appui long puis glisse pour cocher plusieurs cases d'un coup.` |

### 9.6 Compteurs

| Clé | Texte |
|---|---|
| `compteurJours` *(existe)* | `Jours` |
| `compteurNuits` *(existe)* | `Nuits` |
| `compteurWeekends` *(existe)* | `Weekends` |
| `compteursResume(j, n, w)` | `Total du mois : 12 jours, 20 nuits, 4 weekends disponibles` |

### 9.7 Enregistrement, réseau, verrouillage

| Clé | Texte |
|---|---|
| `saveAuRepos` *(existe)* | `À jour` |
| `saveEnCours` *(existe)* | `Enregistrement…` |
| `saveTermine` *(existe)* | `Enregistré` |
| `saveEchec` *(existe)* | `Non enregistré` |
| `saveEchecDetail` *(existe)* | `Impossible d'enregistrer. Vérifie ta connexion.` |
| `actionReessayer` *(existe)* | `Réessayer` |
| `horsLigneDetail` *(existe)* | `Hors ligne. Tes modifications partiront au retour du réseau.` |
| `lectureSeuleDetail` *(existe)* | `Caserne suspendue : tu peux consulter, pas modifier.` |
| `periodeVerrouilleeDetail(date)` *(existe)* | `Mois verrouillé depuis le 15 septembre. Contacte ton chef de centre pour une modification.` |
| `periodeBientotFermee(n, mois)` *(existe)* | `Plus que 2 jours pour saisir octobre` |
| `moisErreurEnregistrementBanniere` | `Impossible d'enregistrer tes disponibilités. Elles sont conservées sur ton téléphone.` |
| `moisErreurVerrouilleEnCours` | `Le mois vient d'être verrouillé. Tes dernières modifications n'ont pas été enregistrées.` |
| `moisErreurSuspendueEnCours` | `Ta caserne est passée en lecture seule. Tes dernières modifications n'ont pas été enregistrées.` |
| `actionRecharger` | `Recharger` |

### 9.8 États vides

| Clé | Texte |
|---|---|
| `moisAucunePeriodeTitre` | `Aucun mois à saisir` |
| `moisAucunePeriodeTexte` | `Ton chef de centre n'a pas encore ouvert de mois. Tu recevras une notification dès que la saisie sera possible.` |
| `moisChargementSemantique` *(réemploi de `chargementSemantique`)* | `Contenu en cours de chargement` |

### 9.9 Jours fériés

| Clé | Texte |
|---|---|
| `feriePremierJanvier` | `Jour de l'an` |
| `feriePaques` | `Lundi de Pâques` |
| `ferieFeteTravail` | `Fête du Travail` |
| `ferieVictoire1945` | `Victoire 1945` |
| `ferieAscension` | `Ascension` |
| `feriePentecote` | `Lundi de Pentecôte` |
| `ferieFeteNationale` | `Fête nationale` |
| `ferieAssomption` | `Assomption` |
| `ferieToussaint` | `Toussaint` |
| `ferieArmistice` | `Armistice` |
| `ferieNoel` | `Noël` |

---

## 10. Checklists

### 10.1 Craft floor (Impeccable)

| Point | État |
|---|---|
| **Contraste** | Tous les couples viennent de `DESIGN.md`, ratios déjà mesurés : disponible 6.55:1, absent 7.47:1, non saisi 6.32:1, texte 17.24:1. Clair et sombre. **Rien de nouveau n'est introduit.** ✓ |
| **Profondeur** | Aucune ombre sur cet écran. Filets et crans de surface. La barre du bas est niveau 1 : surface tonale + filet, pas d'ombre. ✓ |
| **Espacement** | Échelle de 4 exclusivement. 8 dp entre deux cibles, 24 dp au-dessus d'un titre, 8 en dessous. Lignes à 56 dp. ✓ |
| **Typographie** | Échelle fixe de `DESIGN.md`, aucune taille nouvelle. Chiffres tabulaires sur les numéros de jour et les compteurs. Textes réels vérifiés à ×1.0, ×1.6 et ×2.0. ✓ |
| **Motion** | Aucun moment chorégraphié ajouté — le tampon reste réservé à l'acceptation d'une astreinte. Ne bougent que : la case au changement de valeur (120 ms), l'icône `sync` pendant l'envoi, l'apparition de « Enregistré » (180 ms). Tout tombe à 0 sous Reduce Motion, sauf le défilement automatique, qui est un déplacement de document. ✓ |
| **États** | Pressé, focus, désactivé, chargement, vide, erreur, hors ligne, verrouillé, suspendu, refus serveur : tous décrits au § 5.2. ✓ |
| **Surfaces du navigateur** | Curseur `cell` pendant la peinture, sélection de texte neutralisée sur la grille, anneau de focus thématisé, chiffres tabulaires. ✓ |
| **Copie** | Chaque contrôle nomme son action ; chaque erreur nomme le problème **et** la sortie. Tutoiement partout. ✓ |
| **Couverture** | Les huit points du ticket sont traités et localisables : geste (§ 6.1), glissement (§ 6.2), enregistrement (§ 6.3), compteurs (§ 6.4), verrouillé / hors ligne / erreur / mois vierge (§ 5.2), grand écran (§ 6.5), weekends et fériés (§ 6.5, § 7.2). ✓ |
| **Refus** | Pas de carte comme structure de page, pas de métrique héroïque, pas de surtitre, pas de modale, pas de dégradé, pas de glyphe Unicode, pas de monospace décoratif (il est ici réservé aux nombres, qui **sont** des mesures). ✓ |

### 10.2 Checklist application mobile (ui-ux-pro-max)

**Qualité visuelle** — pas d'emoji ✓ · une seule famille d'icônes, Material Icons ✓ · l'état pressé
ne déplace aucune limite de mise en page ✓ · tokens sémantiques uniquement, zéro couleur en dur ✓ ·
*(pas d'actif de marque : aucun n'existe, `PRODUCT.md` le confirme)*.

**Interaction** — retour d'appui sur chaque case ✓ · cibles 104 × 48 dp sur téléphone, très
au-dessus des 48 dp ✓ · durées prises dans `AppMotion` ✓ · cases verrouillées visiblement inertes et
non focalisables ✓ · ordre de focus du lecteur d'écran identique à l'ordre visuel ✓ ·
**conflits de gestes : traités explicitement au § 6.2 — le défilement vertical et le geste retour
iOS ne sont jamais interceptés** ✓.

**Clair / sombre** — les deux thèmes sont définis au ticket 004 et **les deux doivent être vérifiés**
avant livraison, pas déduits l'un de l'autre ⚠︎ *(à faire à l'implémentation)* · filets et états
distinguables dans les deux ✓ · pas de voile sur cet écran (aucune modale) ✓.

**Mise en page** — zones sûres respectées, barre du bas + navigation + `viewPadding` ✓ · rien ne se
cache derrière l'en-tête épinglé ni derrière la barre du bas ✓ · quatre classes de fenêtre décrites,
**à vérifier sur 320, 360, 390 et 430 dp en portrait, et en paysage** ⚠︎ *(à faire à
l'implémentation)* · marges 16 / 24 / 32 selon la classe ✓ · rythme 4/8 ✓ · pas de prose pleine
largeur (les blocs d'aide et les états vides sont bornés à 420) ✓.

**Accessibilité** — icônes décoratives exclues de l'arbre (`excludeSemantics` déjà posé par
`SlotChip` et `CountStat`) ✓ · chaque case porte une phrase complète et son état basculé ✓ · **la
couleur n'est jamais seule** : remplissage + texture + icône + libellé ✓ · Reduce Motion et tailles
dynamiques jusqu'à ×2.0 sans casse ✓ · **le glissement a deux alternatives : la touche et le
clavier** ✓ · pas de contenu auto-défilant ✓ · pas de formulaire ici · rôles et états annoncés
(`toggled`, `selected`, `enabled`) ✓.

**Point resté ouvert** : un utilisateur de lecteur d'écran saisit case par case, sans accélérateur,
jusqu'au ticket 012 (§ 6.2). C'est écrit, pas dissimulé.
