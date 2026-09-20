# 013 — Préférences de charge par mois

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web
mobile-first**, Material 3, une seule apparence.

`DESIGN.md` gagne sur ce brief pour toute valeur de token. `design/011-saisie-dispos-grille.md`
gagne pour tout ce qui concerne la grille. **Ce brief s'écarte du 011 sur un point, la place de
la section, et l'argumente au § 3.**

Sources : `tickets/in-progress/013-preferences-quotas.md`, `docs/PRD.md § 5.2, § 6.3, § 7.4`,
`docs/SCHEMA.md § 2.7`, `PRODUCT.md § Positioning`, `design/011 § 4, § 6.4, § 6.5`,
`design/012 § 5`.

---

## 1. Le job, et pourquoi c'est le ticket qui décide du produit

`PRODUCT.md § Positioning` nomme deux mécanismes que l'intranet remplacé n'a pas. Le premier est
celui-ci : **séparer « je peux » de « je veux »**. Aujourd'hui, un pompier qui coche ses quatre
weekends pour laisser le choix à son chef se retrouve planifié quatre weekends. Alors il ne coche
qu'un weekend — et le chef perd les trois autres, qui étaient possibles.

L'outil perd donc l'information deux fois : il ne sait pas ce qui est possible, et il ne sait pas
ce qui est voulu. Ce ticket rend les deux, et il les rend **sur le même écran, à quelques
centimètres l'un de l'autre**, parce que c'est l'écart entre les deux qui est la leçon.

Le texte pédagogique n'est pas une décoration autour du champ : **c'est lui qui apprend au membre
que l'outil a changé de logique.** Un pompier qui lit « cocher tous tes weekends ne t'engage pas à
tous les faire » et qui coche ensuite ses quatre weekends a fait basculer le produit. Un pompier
qui ne le lit pas continue d'en cocher un.

## 2. Ce qui est livré

Une section **« Ce mois, je veux faire au maximum »**, portant trois valeurs d'une ligne de
`availability_preferences` (`docs/SCHEMA.md § 2.7`) :

| Valeur | Colonne | Domaine |
|---|---|---|
| Nombre maximal d'astreintes | `max_shifts` | `null` (autant que nécessaire) ou `0..62` |
| Nombre maximal de weekends | `max_weekends` | `null` (autant que nécessaire) ou `0..` nombre d'unités de weekend du mois |
| Commentaire du mois | `comment` | 0 à 280 caractères |

Une **astreinte** est un créneau : `max_shifts` plafonne `jours + nuits`. Un **weekend** est une
unité au sens de `uniteWeekend` (011 § 6.4) — samedi + dimanche d'une même semaine, ou un férié en
semaine. **Le quota emprunte exactement le calcul du compteur**, ce que le 011 § 7.6 laissait
ouvert : un seul calcul, donc jamais deux chiffres différents pour la même chose.

`0` est une valeur légitime et atteignable : « je suis disponible, mais ne me planifie pas ce
mois-ci » est précisément le cas extrême que le produit existe pour exprimer.

## 3. La place de la section — l'écart au 011, argumenté

Le 011 § 4 a réservé **une section sous le dernier jour du mois** en `compact`/`medium`, et **le
panneau de droite sous les compteurs** en `large`.

**Le panneau de droite est gardé tel quel.** Il est visible sans défiler, il a la place, et les
compteurs sont juste au-dessus : rien à discuter.

**Sous le dernier jour du mois, en revanche, la section ne serait pas lue** — et la personne qui
ne la lirait pas est exactement celle pour qui le ticket existe.

Le calcul : un mois de 31 jours mesure `31 × 56 = 1736 dp` de lignes. Sur un iPhone de 390 × 844,
la zone de grille visible fait environ 600 dp. Atteindre la section demande donc **trois écrans de
défilement**. Or le membre qui pose ses weekends le fait, depuis le ticket 012, en **deux touches
sans défiler** : « Les weekends » puis « Jour et nuit ». Il a fini, il range son téléphone, et il
n'a jamais su que les maximums existaient. Il vient de cocher quatre weekends en croyant s'engager
sur quatre weekends : **la friction que le produit devait supprimer est intacte.**

Ce n'est pas une hypothèse sur l'utilisateur, c'est la conséquence arithmétique du raccourci livré
au ticket précédent.

**Décision : en `compact` et `medium`, la section remonte entre la bande de raccourcis et
l'en-tête de colonnes épinglé.** Elle est donc visible à l'ouverture du mois, au-dessus de la
grille, dans le même champ de vision que les boutons qui viennent de tout cocher.

L'ordre de lecture devient : *quel mois* → *comment remplir vite* → **combien j'en veux
vraiment** → *le détail jour par jour*. C'est l'ordre du sens : on déclare une intention, puis on
la détaille.

**Ce que cette place coûte, et comment il est payé.** La section complète mesure environ 230 dp,
soit quatre lignes de jour. C'est trop cher pour être payé tous les mois. D'où deux formes :

| Forme | Quand | Hauteur |
|---|---|---|
| **Complète** | tant qu'aucune ligne de préférences n'existe pour ce mois — donc au premier passage, y compris quand les valeurs sont reprises du mois précédent | ~230 dp |
| **Résumée** | dès qu'une ligne existe : le membre s'est déjà prononcé | **56 dp**, une ligne de jour |

La forme résumée n'est pas un repli qui cache : elle **énonce les valeurs** — « Au maximum :
4 astreintes, 1 weekend » — et elle s'ouvre d'une touche sur toute sa largeur. Ce qu'elle range,
c'est l'explication et les contrôles, pas l'information.

En `large`, la section est **toujours complète** : le panneau a la place, et rien n'y est en
concurrence avec la grille.

## 4. La composition de la section

Un **bloc réglé** (`DESIGN.md § Cards / Containers`) : fond `surface`, filet 1 dp
`outline-variant`, rayon 8, aucune ombre. Marge de page de sa classe de fenêtre.

### 4.1 Forme complète, de haut en bas

```
┌─────────────────────────────────────────────────┐
│ Ce mois, je veux faire au maximum               │  titre-bloc 18/600
│                                                 │
│ Cocher tous tes weekends ne t'engage pas à      │  corps-secondaire 14
│ tous les faire. Dis ici combien tu en veux      │  on-surface-variant
│ vraiment : c'est ce que ton chef regarde.       │
│                                                 │
│ ─────────────────────────────────────────────── │  filet 1 dp
│ Astreintes                            4      › │  56 dp, touchable
│ 33 cochées ce mois                              │
│ ─────────────────────────────────────────────── │
│ Weekends                              1      › │  56 dp, touchable
│ 5 cochés ce mois                                │
│ ─────────────────────────────────────────────── │
│ ⓘ Tu as coché 5 weekends pour 1 voulu.          │  ligne d'écart
│   C'est normal : tu laisses le choix à ton chef.│  (§ 4.4)
│ ─────────────────────────────────────────────── │
│ 💬 Un mot pour ton chef                      › │  56 dp, touchable
└─────────────────────────────────────────────────┘
```

Rythme : 16 de rembourrage, 24 au-dessus du titre et 8 en dessous, filets pleine largeur entre
les rangées (`DESIGN.md § Layout`). Les icônes sont des Material Icons, jamais des glyphes.

### 4.2 Les deux rangées de plafond

Une rangée = un plafond. Elle porte **les deux nombres qui font la leçon** : ce qui est voulu
(à droite, en `nombre` mono 20/600, tabulaire) et ce qui est coché (en sous-ligne,
`corps-secondaire`). Sans plafond, la droite lit « autant que nécessaire » en `corps`, sans
nombre : le mot est écrit en toutes lettres, jamais un `∞`.

Hauteur 56 dp minimum, pleine largeur, chevron `chevron_right` de 20 dp à droite.
`Semantics(button: true, label: 'Astreintes, au maximum 4', hint: '33 cochées ce mois')`.

**Toucher la rangée ouvre une feuille de bas d'écran**, exactement le composant que le 012 a déjà
justifié : rangées de 56 dp au pouce, geste retour pour fermer, une seule apparence sur téléphone
et sur poste. Le contenu :

| Rangée | Valeur |
|---|---|
| **Autant que nécessaire** | `null` — première de la liste, c'est le défaut du produit |
| `0` | « Aucune astreinte ce mois » / « Aucun weekend ce mois » |
| `1`, `2`, `3`… | le nombre, en mono tabulaire |

La liste des astreintes va de 0 à 20 ; celle des weekends de 0 au nombre d'unités de weekend
réellement présentes dans le mois affiché (4 à 8). **Les bornes viennent du mois, pas d'une
constante inventée** : proposer « 6 weekends » dans un mois qui en compte 5 serait un chiffre
faux.

La valeur courante porte `Icons.check` et `Semantics(selected: true)`.

**Pourquoi une feuille et pas un incrémenteur ni un champ.** Un incrémenteur `− n +` ne sait pas
loger « autant que nécessaire » : l'illimité est le *plus grand* des choix et se rangerait sous
zéro, ce qui ne se lit pas. Un champ de nombre ouvre le clavier, accepte l'invalide, et demande
une validation là où il n'y a que sept choix réels. Un `DropdownButton` Material fait des cibles
de 36 dp — le 012 a déjà tranché ce point contre les gants.

### 4.3 Le commentaire

Une rangée de 56 dp, `Icons.chat_bubble_outline`, qui **ouvre un champ multiligne en place** (pas
une feuille : le clavier couvrirait la moitié d'une feuille sur téléphone, et le membre doit voir
ce qu'il écrit).

- Libellé au-dessus du champ, jamais en simple invite : « Un mot pour ton chef ».
- 4 lignes visibles, `TextInputType.multiline`, texte à 16 sp (en dessous, iOS zoome à la saisie).
- **280 caractères**, imposés. Un compteur « 32 caractères restants » apparaît **sous 40
  restants** et pas avant : un compteur permanent transforme une phrase libre en épreuve.
- Rempli, il reste affiché en clair sous la rangée, tronqué à deux lignes.

280 caractères, c'est la longueur d'une phrase utile — « Pas plus d'un weekend, garde des enfants.
Je peux dépanner en semaine si besoin. » — et c'est la longueur que la matrice du ticket 016
pourra montrer dans une cellule sans devenir illisible. La colonne `comment` est un `text` sans
contrainte : **la borne est posée côté client, et le 016 ne doit pas supposer qu'elle a toujours
été là.** *(Une `check (char_length(comment) <= 280)` serait la version robuste ; c'est une
migration, donc `supabase-dev`, et le ticket ne la demande pas.)*

### 4.4 La ligne d'écart — le cœur pédagogique

Elle n'existe **que** quand un plafond est posé et que le coché le dépasse.

> ⓘ Tu as coché 5 weekends pour 1 voulu. C'est normal : tu laisses le choix à ton chef.

Elle est en **`etat-info`** (`#0F5C7A` sur `#CDE7F2`, 7.41:1) avec `Icons.info_outline`. **Jamais
en rouge, jamais en ocre, jamais un avertissement** : l'écart n'est pas une faute, c'est le
comportement que le produit cherche à obtenir. Une alerte ici ferait exactement le contraire de ce
que le ticket veut — elle apprendrait au membre à décocher.

C'est la phrase qui transforme un chiffre bizarre (« 5 / 1 ») en une décision comprise.

## 5. Le lien avec les compteurs

Le 011 a construit les trois `CountStat` avec `plafond: null` et `plafondAttendu: false` pour que
le 013 n'ait qu'à remplir.

**Ce qui est rempli.** Le compteur **Weekends** de la barre du bas reçoit `max_weekends` et lit
`5 / 1`, en mono tabulaire. Il est visible pendant tout le défilement de la grille : le membre qui
coche son quatrième weekend voit le rapport bouger sans rien chercher. Sa sémantique devient
« 5 weekends cochés, 1 voulu au maximum ».

**Ce qui n'est pas rempli, et pourquoi.** `max_shifts` plafonne `jours + nuits`, que **aucun des
trois compteurs ne totalise**. Trois issues ont été pesées :

| Option | Verdict |
|---|---|
| Un quatrième compteur « Astreintes 33 / 4 » | **Rejetée.** Le 011 § 7.5 l'interdit, et la raison tient : sur 320 dp, l'indicateur d'enregistrement et trois compteurs passent déjà en `Wrap` sur deux rangs. Un quatrième coûterait 40 dp de grille en permanence, sur tous les mois, y compris sans plafond. |
| Poser `max_shifts` sur *Jours* **et** sur *Nuits* | **Rejetée.** « 20 / 4 nuits » est faux : le plafond porte sur la somme, pas sur chaque terme. |
| Le porter dans la section, sur sa propre rangée | **Retenue.** La rangée « Astreintes » lit déjà « 4 » à droite et « 33 cochées ce mois » dessous : c'est le rapport, à l'endroit exact où on le règle. |

Le résumé sémantique de la barre nomme les deux plafonds quand ils existent, pour qu'un
utilisateur de lecteur d'écran ait l'écart complet sans entrer dans la section.

**Pas de marqueur « quota atteint ».** Le 011 en annonçait un. Il n'est pas livré, et c'est
délibéré : sur **cet** écran, atteindre ou dépasser son maximum est le résultat recherché
(`PRD § 7.4` : les quotas informent, ils ne bloquent pas). Un marqueur dirait au membre qu'il a
mal fait. Le marqueur a sa place dans la matrice du ticket 016, où « quota atteint » change ce que
l'**admin** doit faire.

## 6. La reprise du mois précédent

`PRD § 6.3` : « Par défaut, les préférences du mois précédent sont reprises. »

Règle, en trois lignes :

1. Une ligne existe pour ce mois → elle fait foi. Pas de reprise.
2. Pas de ligne, **et** le mois précédent en a une, **et** le mois affiché est modifiable → ses
   trois valeurs sont reprises, **écrites par la file ordinaire**, et **annoncées** : une rangée
   `Icons.history` en tête de section, « Repris de septembre. Change-le si ce n'est plus vrai. »
   La mention disparaît à la première modification, parce que la valeur est alors celle du membre.
3. Sinon → autant que nécessaire, aucun commentaire, **aucune ligne écrite**.

**Pourquoi la reprise s'écrit au lieu d'être seulement proposée.** Si elle restait un pré-remplissage
non enregistré, le membre verrait « 1 weekend » et l'admin, au ticket 016, ne verrait rien. Deux
vérités pour le même mois, et c'est celle de l'admin qui construit le planning. Le PRD dit que la
reprise **est** le défaut du produit : elle doit donc exister en base comme elle existe à l'écran.
Ce qui est interdit, c'est qu'elle soit **silencieuse** — d'où la rangée « Repris de septembre »,
qui est visible avant même que le membre ait touché quoi que ce soit.

**Aucune préférence ne se supprime jamais.** Une ligne dont les deux plafonds sont `null` et le
commentaire vide n'est pas une ligne vide : c'est le membre qui a **dit** « autant que nécessaire »
pour ce mois. La supprimer ferait repartir la reprise du mois précédent à la prochaine ouverture,
et la valeur qu'il vient de choisir lui reviendrait en pleine figure. C'est la différence entre
« n'a rien dit » et « a dit : sans limite », et la base la porte déjà — `max_shifts` y est
nullable, et `null` y signifie illimité.

*(C'est le seul endroit où ce ticket s'écarte de la grammaire du 011, pour qui « revenir au vide »
veut dire « supprimer la ligne ». Sur une case, l'absence de ligne est une valeur d'affichage
neutre ; sur une préférence, c'est une réponse qu'on efface.)*

## 7. L'enregistrement — le chemin de la grille, pas un second

**Aucun second mécanisme.** Le 011 a construit un chemin d'écriture complet : file coalescée,
délai de 500 ms, envoi groupé, persistance sur l'appareil, relances à 1 s et 4 s, détection des
refus RLS par comptage de lignes, bannières. Les préférences y entrent, elles n'en ouvrent pas un
autre.

Concrètement, dans `SaisieController` :

- un champ `_preferencesEnAttente` à côté de `_file` ; `_poserPreferences` est au plafond ce que
  `_poser` est à la case : il publie l'état optimiste, marque l'attente, et appelle `_planifier` ;
- `_envoyer` ajoute l'`upsert` des préférences au `Future.wait` existant. Poser un plafond et
  peindre dix cases dans la même seconde coûte donc **trois requêtes au plus, en parallèle**, et
  **une** transition d'indicateur ;
- `_persister` garde la préférence en attente dans `localStorage` à côté de la file, sous
  `dispos.prefs.<caserne>.<membre>.<AAAA-MM>`. La bannière hors ligne promet que rien n'est perdu :
  elle doit être vraie pour un maximum comme pour une case ;
- le refus RLS se détecte comme ailleurs, **en comptant les lignes rendues** : la clause `using`
  d'une politique filtre sans lever, et un `upsert` refusé répond « 0 ligne, tout va bien »
  (`supabase/README.md`, ticket 008). Zéro ligne rendue = refus = bannière « Le mois vient d'être
  verrouillé » ;
- changer de mois vide la file **et** la préférence en attente, comme le 011 le fait déjà.

L'indicateur d'enregistrement est **celui de l'écran**, dans la barre du bas. La section n'a pas
le sien : deux indicateurs pour une seule file diraient deux choses d'une seule vérité.

**En cas d'échec propre à la préférence**, la section prend un filet 2 dp `error` — l'équivalent
du contour d'erreur d'une case — et garde **la valeur voulue** à l'écran. Rien ne revient en
arrière : c'est la règle du 011 § 5.3, et elle vaut ici.

## 8. Période verrouillée, caserne suspendue

Comme la grille et comme les raccourcis du 012 : **la section reste en place, en lecture seule.**

- Les deux rangées perdent leur chevron, leur `InkWell` et leur focus ; elles gardent leurs
  nombres, parfaitement lisibles.
- Le commentaire reste affiché **en entier** : ce sont les mots du membre, il a le droit de les
  relire.
- La raison est écrite juste en dessous : « Mois verrouillé : tu ne peux plus changer tes
  maximums. » (`DESIGN.md § Do` — un contrôle inerte dit pourquoi, à côté du contrôle).
- Forme **toujours complète** sur un mois verrouillé : la forme résumée ne sert qu'à récupérer de
  la place pour saisir, et il n'y a plus rien à saisir.
- Rien de vide et de muet : sans préférence enregistrée, « Aucun maximum indiqué pour ce mois. »
- Le contrôleur garde la règle une seconde fois : aucune écriture n'est tentée sur un mois non
  modifiable, même appelée par un autre chemin.

## 9. États

| État | Rendu |
|---|---|
| **Vierge, jamais repris** | Forme complète, « autant que nécessaire » aux deux rangées, leçon visible, pas de ligne d'écart. |
| **Repris du mois précédent** | Forme complète + rangée « Repris de septembre. Change-le si ce n'est plus vrai. » |
| **Réglé** | Forme résumée : « Au maximum : 4 astreintes, 1 weekend », plus le commentaire tronqué s'il existe. |
| **Réglé, sans limite** | Forme résumée : « Au maximum : autant que nécessaire. » |
| **Écart** | Ligne d'écart en `etat-info`, dans la forme complète ; le rapport `5 / 1` reste visible dans la barre du bas dans les deux formes. |
| **Feuille ouverte** | Titre = le plafond réglé, valeur courante cochée. |
| **Enregistrement** | L'indicateur de la barre du bas, partagé avec la grille. |
| **Échec** | Filet 2 dp `error` sur la section, valeur conservée, bannière et « Réessayer » de l'écran. |
| **Hors ligne** | Rien de particulier : la préférence s'empile comme une case et part au retour du réseau. |
| **Verrouillé / lecture seule** | § 8. |
| **Chargement** | La section n'apparaît qu'avec l'état : pas de squelette pour 56 dp. |

## 10. Textes

Section « Préférences de charge (ticket 013) » d'`AppStrings`. Tutoiement, phrases courtes.

| Clé | Texte |
|---|---|
| `preferencesTitre` | `Ce mois, je veux faire au maximum` |
| `preferencesLecon` | `Cocher tous tes weekends ne t'engage pas à tous les faire. Dis ici combien tu en veux vraiment : c'est ce que ton chef regarde.` |
| `preferencesAstreintes` | `Astreintes` |
| `preferencesWeekends` | `Weekends` |
| `preferencesSansLimite` | `autant que nécessaire` |
| `preferencesCochees(n)` | `33 cochées ce mois` / `1 cochée ce mois` |
| `preferencesCochesWeekends(n)` | `5 cochés ce mois` |
| `preferencesAucune(n)` | `Aucune astreinte ce mois` / `Aucun weekend ce mois` |
| `preferencesResume(a, w)` | `Au maximum : 4 astreintes, 1 weekend` |
| `preferencesResumeSansLimite` | `Au maximum : autant que nécessaire` |
| `preferencesEcartWeekends(c, m)` | `Tu as coché 5 weekends pour 1 voulu. C'est normal : tu laisses le choix à ton chef.` |
| `preferencesEcartAstreintes(c, m)` | `Tu as coché 33 astreintes pour 4 voulues. C'est normal : tu laisses le choix à ton chef.` |
| `preferencesReprise(mois)` | `Repris de septembre. Change-le si ce n'est plus vrai.` |
| `preferencesCommentaireRangee` | `Un mot pour ton chef` |
| `preferencesCommentaireInvite` | `Ex. : pas plus d'un weekend, garde des enfants.` |
| `preferencesCommentaireRestants(n)` | `32 caractères restants` |
| `preferencesVerrouille` | `Mois verrouillé : tu ne peux plus changer tes maximums.` |
| `preferencesLectureSeule` | `Caserne en lecture seule : tu ne peux plus changer tes maximums.` |
| `preferencesAucuneVerrouille` | `Aucun maximum indiqué pour ce mois.` |
| `preferencesOuvrir` | `Modifier mes maximums` |
| `preferencesFeuilleAstreintes` | `Au maximum, combien d'astreintes ?` |
| `preferencesFeuilleWeekends` | `Au maximum, combien de weekends ?` |

## 11. Ce qu'un développeur ne doit pas inventer ici

Un bouton « Enregistrer ». Un quatrième compteur. Un avertissement rouge ou ocre sur l'écart. Un
blocage de la saisie quand le plafond est atteint. Un plafond par créneau, par semaine ou par type
de jour. Une colonne hors de `docs/SCHEMA.md § 2.7`. Une RPC : l'`upsert` sur
`(station_id, user_id, period_id)` vaut une requête et la RLS dit déjà qui écrit et quand. Une
suppression de ligne de préférence. Un second minuteur d'enregistrement.

## 12. Tests attendus

- Mois sans préférence et sans mois précédent : deux « autant que nécessaire », aucune écriture.
- Mois précédent renseigné : les trois valeurs sont reprises, **écrites**, et la mention « Repris
  de » est à l'écran.
- Mois verrouillé : aucune reprise écrite, aucune rangée actionnable, la raison affichée.
- Poser un plafond, puis le retirer : la valeur revient à « autant que nécessaire », **la ligne
  reste** en base.
- Passage à « autant que nécessaire » → `null` envoyé, pas `0`.
- Le compteur « Weekends » de la barre affiche `5 / 1` dès qu'un plafond de weekends est posé, et
  reprend sa forme nue quand il est retiré.
- La ligne d'écart n'apparaît que lorsque le coché dépasse le voulu.
- Commentaire : borné à 280 caractères, compteur sous 40 restants.
- Enregistrement automatique : une seule requête après 500 ms, gardée sur l'appareil avant de
  partir, oubliée du stockage après confirmation.
- Un plafond posé et dix cases peintes dans la même fenêtre : trois requêtes, une transition
  d'indicateur.
- Refus RLS (0 ligne rendue) : bannière de refus, valeur conservée à l'écran.

## 13. Écarts à reporter dans la PR

| Point | Ce que disait la référence | Ce que fait ce brief | Pourquoi |
|---|---|---|---|
| Place de la section en `compact`/`medium` | 011 § 4 : sous le dernier jour du mois | entre les raccourcis et l'en-tête épinglé, en deux formes (complète / résumée à 56 dp) | Trois écrans de défilement contre deux touches de raccourci : la section ne serait jamais vue par la personne que le ticket vise (§ 3). |
| Marqueur « quota atteint » sur `CountStat` | 011 § 6.4 : le 013 l'ajoute | non livré | Dépasser son maximum est ici le résultat recherché (`PRD § 7.4`). Le marqueur appartient à la matrice admin du 016 (§ 5). |
| Plafond sur les trois compteurs | 011 § 6.4 : « 013 n'a qu'à le remplir » | seul **Weekends** le reçoit | Aucun compteur ne totalise les astreintes, et un quatrième coûterait 40 dp de grille en permanence (§ 5). |
| Retour au vide = suppression de la ligne | 011 § 7.1, pour `availabilities` | **jamais** de suppression de préférence | « A dit : sans limite » n'est pas « n'a rien dit » : supprimer relancerait la reprise du mois précédent au prochain chargement (§ 6). |
| Longueur du commentaire | `docs/SCHEMA.md § 2.7` : `text` sans borne | 280 caractères imposés côté client | Le 016 doit pouvoir l'afficher dans une cellule de matrice. La borne SQL reste à faire par `supabase-dev` si elle est jugée nécessaire (§ 4.3). |

## 14. Craft floor (Impeccable)

| Point | État |
|---|---|
| **Contraste** | Aucune encre nouvelle. Ligne d'écart `#0F5C7A` sur `#CDE7F2` (7.41:1) ; sous-lignes `on-surface-variant` sur `surface` (7.94:1) ; filet d'erreur `error` (7.47:1). ✓ |
| **Profondeur** | Aucune ombre. Bloc réglé, filets, rangées séparées par un trait. La feuille de bas d'écran est le seul niveau 3, et elle existait déjà. ✓ |
| **Espacement** | Échelle de 4. Rangées 56 dp, 24 au-dessus du titre, 8 en dessous, 16 de rembourrage. ✓ |
| **Typographie** | `titre-bloc`, `corps-secondaire`, `nombre` mono tabulaire sur les plafonds et les comptes. Rien sous 14 sp. Prose bornée à 420 dp. ✓ |
| **Motion** | Aucun moment chorégraphié ajouté. L'ouverture de la forme complète prend `surface` (240 ms), à 0 sous Reduce Motion. ✓ |
| **États** | Vierge, repris, réglé, écart, feuille, enregistrement, échec, hors ligne, verrouillé, suspendu : § 9. ✓ |
| **Surfaces du navigateur** | Chiffres tabulaires, anneau de focus thématisé, `inputmode` multiligne sur le commentaire, curseur `click` sur les rangées. ✓ |
| **Copie** | Chaque rangée nomme sa valeur ; la leçon nomme le malentendu qu'elle corrige ; l'inerte dit pourquoi. Tutoiement partout. ✓ |
| **Refus** | Pas de carte comme structure, pas de métrique héroïque, pas de surtitre, pas de modale (la feuille en est une au sens Material, mais c'est le choix déjà justifié au 012 pour les gants), pas d'emoji, pas de `∞`, pas de barre de progression pour un quota. ✓ |
