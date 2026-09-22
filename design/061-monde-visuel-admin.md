# 061 — Un nouveau monde visuel, à partir de l'écran de l'admin

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web
mobile-first**, Material 3, une seule apparence sur toutes les cibles. `DESIGN.md` du ticket 004 est
le monde sortant ; ce brief le remplace après validation par le propriétaire. Références :
`design/assets/061-reference-admin.png` (écran de planning d'équipe), et la charte envoyée par le
propriétaire : police Archivo (Regular, Medium, SemiBold, Bold), couleurs violet `#B142E8`,
indigo `#7655FA`, vert `#097C69`, orange `#F59638`, rose `#F9357C`.

---

## 1. Job et audience

**Le chef de centre, assis, une heure par mois pour couvrir soixante-deux créneaux ; plus le suivi
rapide sur téléphone. Les pompiers, sur téléphone, dehors, parfois avec des gants.**

Ce qui se joue : la lisibilité d'abord, l'agrément ensuite. Le propriétaire veut que l'admin
ressemble à la référence : navigation latérale, bandeau de chiffres, bande de semaine, une ligne
par personne avec ses créneaux en blocs colorés.

---

## 2. Décision 1 — Périmètre : tout le produit, par les tokens, l'admin en premier chantier

**Options :** (a) tout le produit d'un coup ; (b) l'admin seul, deux mondes coexistant ;
(c) tout le produit via les tokens, avec le travail de structure réservé à l'admin.

**Recommandation : (c).** Raison : `PRODUCT.md` fixe « une seule apparence partout » et tous les
écrans lisent leurs couleurs et polices dans les tokens de `DESIGN.md` ; changer les tokens change
tout le produit d'un coup, à coût faible. Ce qui coûte est la structure de l'écran de l'admin, qui
ne concerne que lui. Deux mondes qui coexistent, c'est deux applications à maintenir et une
transition que les pompiers verraient tous les jours.

---

## 3. Décision 2 — Palette : l'indigo devient l'accent, l'encre reste le texte

| Couleur | WCAG sur blanc | WCAG indigo sur blanc | WCAG sur sombre | Usage |
|---------|---|---|---|---|
| Indigo `#7655FA` | 4,72 | — | 3,87 | Accent : boutons, sélection, jour courant |
| Vert `#097C69` | 5,12 | — | 3,56 | Accepté, couvert, publié |
| Orange `#F59638` | 2,26 | 7,24 | 8,08 | À pourvoir, proposé ; jamais en texte |
| Rose `#F9357C` | 3,60 | 4,54 | 5,06 | Refusé, conflit, réattribution urgente |
| Violet `#B142E8` | 4,36 | 3,75 | 4,18 | Décoratif, marque, état vide |
| Encre `#16212A` | — | — | — | Texte, titres, chiffres |

**Rôles décidés :**

- **Indigo `#7655FA` : l'accent.** Bouton principal (texte blanc dessus, 4,72), élément de
  navigation sélectionné, focus, jour courant, filet de sélection. En texte, uniquement sur blanc
  pur, jamais sur le papier `#F7F9FA` (4,47, sous le seuil).
- **Encre `#16212A` : le texte.** Reste la couleur du texte, des titres et des chiffres. Elle n'est
  plus la couleur des boutons.
- **Vert `#097C69` : accepté, couvert, publié.** Passe en texte sur blanc.
- **Orange `#F59638` : à pourvoir, proposé en attente de réponse.** Jamais en texte. En bloc de
  fond avec texte encre, ou en badge avec icône et libellé encre.
- **Rose `#F9357C` : refusé, conflit, réattribution urgente.** Jamais en texte sur blanc. En bloc
  avec texte encre.
- **Violet `#B142E8` : décoratif seulement.** Marque, illustration d'état vide. Jamais texte,
  jamais porteur d'état.
- **Règle inchangée : aucun état porté par la couleur seule ;** icône plus libellé partout ; les
  couleurs d'état existantes de `DESIGN.md` (disponible, absent, non saisi, proposé, accepté,
  refusé, verrouillé) reçoivent chacune une correspondance dans cette palette, à mesurer une par
  une au ticket des tokens, avec la règle : texte encre sur bloc teinté, jamais texte coloré sur
  blanc sauf indigo et vert.
- **Thème sombre :** orange et rose passent en texte ; indigo, vert et violet doivent être
  éclaircis et mesurés au ticket des tokens.

---

## 4. Décision 3 — Typographie : Archivo pour les titres, Atkinson pour tout le reste

**Options :** (a) Archivo partout ; (b) Atkinson partout, comme aujourd'hui ; (c) Archivo pour les
titres et la navigation, Atkinson Hyperlegible Next pour le corps et Atkinson Mono pour tous les
chiffres.

**Recommandation : (c).** Raison : Atkinson a été choisie au 004 pour une raison de brief, pas de
goût : distinction 1/l/I et 0/O, lecture au soleil, écrans pleins de chiffres (dates, codes,
quotas, matrice). Ces raisons n'ont pas changé. Archivo apporte le caractère de la référence là où
il se voit, les titres à 18 points et plus, où la confusion de glyphes n'a pas d'enjeu. Archivo est
sous licence SIL OFL, à embarquer dans `assets/fonts/` comme les autres, jamais depuis un CDN.
Chiffres tabulaires : Atkinson Mono, inchangé.

---

## 5. Décision 4 — Structure de l'écran de l'admin, sur grand écran

Ce qui existe : `AppScaffold` a déjà un rail de navigation sur fenêtre moyenne, un rail étendu et
un panneau latéral sur grande fenêtre ; la matrice du 016 a sa colonne figée de 280 points et ses
cases de 28 points par créneau ; le panneau des candidats du 017 s'ouvre à droite.

Ce qui change, de haut en bas :

- **Navigation latérale :** le rail étendu devient une colonne blanche à coins arrondis, libellés
  visibles, élément sélectionné en pastille teintée indigo avec texte indigo, mêmes cinq
  destinations. Pas de recherche, pas de boîte promotionnelle.
- **En-tête :** nom de la caserne, cloche, compte. La barre de recherche de la référence est
  remplacée par le filtre de membres que le 016 a déjà.
- **Bandeau du mois, trois chiffres :** créneaux couverts, créneaux à pourvoir, réponses en
  attente ; sous les chiffres, une barre de répartition, vert couvert, orange à pourvoir, rose
  refusé, gris non saisi ; le mois en titre.
- **Bande de semaine :** les jours du mois en ligne, le jour courant en pastille indigo, défilement
  horizontal, sert à faire défiler la matrice à la semaine visée.
- **Lignes :** une par membre, avatar à initiales (pas de photos, les pompiers n'en ont pas et ce
  serait une donnée de plus), nom, ligne de quotas sous le nom (existante). Colonne figée
  inchangée.
- **Cases :** le modèle jour / nuit est conservé, deux cases par jour, 28 points de pas. Un
  créneau attribué devient un bloc teinté selon son état (indigo disponible, vert accepté, orange
  proposé, rose refusé, gris non saisi ou verrouillé) avec icône et, quand la place le permet,
  libellé encre. Pas de filet coloré en bord gauche (interdit par la règle de fini), le bloc entier
  porte la teinte.
- **Fenêtre compacte :** rien de nouveau. Barre du bas conservée, bandeau réduit à une ligne de
  trois chiffres, bande de semaine conservée, matrice dans sa forme mobile du 016.

---

## 6. Décision 5 — Ce qu'on ne copie pas

Le logo et le nom de la référence ; la boîte « premium » ; la barre de recherche ; les cases
horaires ; les photos d'avatar ; les montants ; le filet coloré en bord gauche des blocs.

---

## 7. Ce que le propriétaire tranche

1. Tout le produit par les tokens, l'admin en premier chantier. **Recommandé : oui.**
2. L'indigo remplace l'encre sur les boutons et la sélection ; le texte reste encre. **Recommandé :
   oui.**
3. Archivo pour les titres seulement, Atkinson pour le corps et les chiffres. **Recommandé : oui.**
4. Violet clair décoratif uniquement ; orange et rose jamais en texte. **Recommandé : oui.**
5. Avatars à initiales, pas de photos. **Recommandé : oui.**

---

## 8. Découpage après validation

- **061a :** `DESIGN.md` version 2 par `document`, tokens de couleur et de police, thème Flutter,
  Archivo embarquée, contrastes mesurés en clair et en sombre pour chaque état. Tout le produit
  change d'apparence à ce ticket.
- **061b :** coquille de l'admin sur grand écran, navigation latérale, en-tête, bandeau du mois,
  bande de semaine.
- **061c :** lignes de la matrice, avatars, blocs d'état, revue de la matrice et du panneau des
  candidats.
- **061d :** passe de revue Impeccable sur les écrans pompier après le changement de tokens,
  corrections de fini seulement.

---

## 9. Ce que ce brief ne décide pas

Les valeurs exactes des teintes claires et sombres dérivées, les tailles de police de chaque style,
l'espacement : ils se fixent au 061a, mesure par mesure, dans `DESIGN.md`.
