# Brief 075 — Le site vitrine astreinte-sp.fr

Ticket : `tickets/in-progress/075-site-vitrine.md`. Mode Impeccable : **Persuade** (page de
conversion, pas un écran d'outil). Plateforme enregistrée : `web`. Surface nouvelle **dans un
monde établi** : `DESIGN.md` (registre de garde, indigo, Archivo / Atkinson) fixe l'identité, ce
brief fixe la composition, les textes et la technique. Écrit le 30 septembre 2026 sans entretien
avec le propriétaire : les hypothèses sont marquées **[H]** et reprises au § 11.

Ce brief ne produit pas de code. Le site vit dans `site/`, hors de Flutter.

---

## 1. Job et audience

**Qui arrive.** Un chef de centre ou son adjoint, un président ou trésorier d'amicale de
sapeurs-pompiers volontaires. Il ne connaît pas Astreinte SP. Il arrive par un lien envoyé par un
collègue, une recherche « planning astreinte pompiers », ou un message sur un groupe. **Sur
téléphone la plupart du temps**, le soir ou entre deux activités ; sur l'ordinateur du centre
quand le bureau en parle.

**Son état d'esprit.** Prudent. Il gère aujourd'hui le planning avec du papier, un tableur et un
groupe WhatsApp ; ça marche mal, mais ça marche. Trois questions décident :

1. Est-ce que ça règle **mon** problème (les dispos qui arrivent par morceaux, les relances, le
   planning refait quand quelqu'un ne peut plus) ?
2. Combien ça coûte, qui paie, et puis-je arrêter ? Le budget se vote en bureau d'amicale : il
   faut un chiffre clair, une durée d'essai, une sortie.
3. Où vont les données de mes pompiers ? Il répond d'eux.

**Ce qu'il doit faire.** Demander un essai gratuit pour son centre, ou transmettre la page au
bureau avec les réponses dedans.

**La promesse en une phrase :**

> Vos pompiers saisissent leurs disponibilités sur leur téléphone, vous construisez le planning,
> chacun accepte son créneau — et un refus ne défait pas le reste du mois.

---

## 2. Résultat et preuve

**Action principale** : « Demander un essai gratuit » (voir § 2.1, c'est la décision la plus
importante du brief). **Action secondaire** : « Voir le prix ». **Action de service** :
« Se connecter » pour qui a déjà un compte.

**Succès** : en un écran, le visiteur sait ce que c'est, pour qui, et comment essayer ; en trois
défilements, il a le prix, l'essai, les données et la résiliation ; il peut envoyer la page au
bureau sans rien ajouter.

**La preuve disponible, et seulement elle.** `PRODUCT.md` le dit : aucun témoignage, aucune
donnée d'usage, aucun chiffre client. Le site n'a donc que trois preuves, et il les met au premier
plan :

1. **L'app elle-même**, en captures réelles, avec des données fictives de démonstration.
2. **Les deux mécanismes que les outils actuels n'ont pas** (`PRODUCT.md` § Positioning) :
   « disponible » n'est pas « volontaire » (quotas du mois), et la validation se fait **par
   créneau** (un refus ne touche qu'un créneau).
3. **Des faits vérifiables** : le prix, l'essai, où sont les données, ce que l'app ne fait pas.

Interdits : faux chiffres (« 200 casernes », « 3 h gagnées par mois »), faux témoignages, logos
de SDIS, étoiles, `aggregateRating` dans les données structurées, compteurs animés, « utilisé
par… ». Les objectifs du PRD (§ 2 : « < 2 minutes », « < 48 h ») sont des **cibles**, pas des
résultats mesurés : ils ne s'écrivent pas sur le site.

### 2.1 Le bouton d'essai : ce que le produit permet réellement

**Constat.** L'app ne sait pas créer une caserne en libre-service : une caserne est créée par le
super-admin (`super_admin_create_station`, PRD § 6.7, ticket 031), et l'essai de 60 jours démarre
à ce moment (`subscription_bootstrap`, migration 0023). Un chef de centre inconnu qui touche un
bouton « Essayer » menant à `https://astreinte.staticflow.ch` se connecte… et tombe sur
« Aucune caserne — demande à ton admin ». C'est une impasse, et la pire première impression.

**Décision du brief.** Le bouton principal s'appelle **« Demander un essai gratuit »** et ouvre
un **courriel prérempli** vers l'adresse de contact (§ 7.3). Le lien vers l'app existe, mais comme
**« Se connecter »** dans l'en-tête et dans la dernière section, pour les centres déjà inscrits
et les pompiers invités.

**Écart avec le ticket** : le critère « Le bouton d'essai ouvre l'app » ne peut pas être tenu
sans une impasse. Le brief le remplace par « le bouton d'essai ouvre la demande d'essai ; le lien
"Se connecter" ouvre l'app ». À valider par le propriétaire (§ 11, point 1). Un parcours
d'inscription en libre-service serait un autre ticket (base, Edge Function, Stripe), hors
périmètre ici.

---

## 3. Direction retenue

### 3.1 Les structures envisagées

Le monde visuel étant fixé, le choix porte sur la composition. Sept structures, classées par
résonance avec ce public :

1. **Le mois qui se remplit** — la page suit la vie d'un mois : ouverture de la saisie, date
   limite, publication, validation.
2. **Avant / après** — papier, tableur et WhatsApp face à l'app, en regard.
3. **La fiche pour le bureau** — la page est le document qu'un chef de centre présenterait au
   bureau d'amicale : ce que c'est, comment ça marche, combien, où vont les données, comment
   arrêter. Les faits qui décident sont en tête, dans un tableau réglé.
4. **Deux rôles, deux écrans** — la page coupée en deux : le pompier (téléphone), le chef
   (ordinateur).
5. **Le créneau refusé** — tout le récit autour d'un seul créneau : proposé, refusé, réattribué,
   accepté, sans toucher au reste.
6. **Les questions d'abord** — la FAQ du chef de centre prudent comme structure de page.
7. **Le registre littéral** — toute la page en registre réglé, une ligne par section.

Le tirage d'Impeccable (`concept-seed`, clé `45d2d0a0`, mode persuade, **tiré en mode dégradé**,
service de tirage injoignable, sans challenger externe) a distribué **3, 1 et 5, le 3 en tête**.
Faute de propriétaire pour trancher pendant la rédaction, le brief **construit le 3** et garde
1 et 5 comme alternatives (§ 11, point 12).

### 3.2 « La fiche pour le bureau »

**Thèse.** La page est une fiche de décision, pas une plaquette. Elle refuse la mise en page par
défaut de la catégorie SaaS (héros à dégradé, trois cartes icône-titre-texte, bande de logos,
témoignages, trois formules de prix dont une « populaire »). Elle répond dans l'ordre où un
bureau d'amicale pose ses questions, et **chaque affirmation est adossée à une capture ou à un
fait**.

**Monde propre (reconnaissable sans le texte).** Le papier et l'encre du registre : fond blanc et
papier doux `#F7F9FA`, encre `#131C23`, **filets de 1 px** `#C3CDD3` qui règlent la page en
bandes pleine largeur, cases à rayon 4, boutons-blocs à rayon 8 (jamais de gélule). **Une seule
couleur saturée hors captures : l'indigo, qui veut dire « choisir, agir »** (boutons, et la
bande finale d'appel à l'essai, § 4.8). Le vert, l'orange et le rose n'apparaissent que là où ils
disent un état, dans l'illustration des trois étapes et dans les captures. Aucune ombre sauf sur
le téléphone posé par-dessus la capture d'ordinateur.

**Récit.** Le visiteur comprend (le planning d'astreinte, validé créneau par créneau), croit
(il voit l'app, pas une promesse), vérifie (prix, essai, données, résiliation, limites) et agit
(demande d'essai).

**Moment signature : le tampon.** `DESIGN.md` § Motion n'autorise qu'un geste chorégraphié dans
tout le produit : le badge « Accepté » qui se pose (`scale 1.06 → 1.00` + opacité, 180 ms, une
fois). Le site reprend **ce geste et lui seul**, sur la case « Accepté » de l'étape 3, quand elle
entre dans la vue. Rien d'autre ne bouge sur la page.

**Premier écran.** Voir § 6.1. À 390 px : nom, promesse, bouton, et le haut du téléphone qui
dépasse sous le pli. À 1280 px : texte à gauche, à droite la matrice de l'admin sur ordinateur
avec le téléphone du pompier posé devant, en chevauchement.

**Contrat de direction dans le code.** Le développeur place en **premier enfant du `<body>`**
de `site/index.html` un commentaire HTML de 150 mots au plus : THESIS, OWN-WORLD, STORY, FIRST
VIEWPORT, FORM (« 3 — La fiche pour le bureau », clé `45d2d0a0`), et la ligne FINISH d'Impeccable.
Le contenu est celui de ce § 3.2 et du § 6.1.

---

## 4. Structure de la page, section par section

Une page d'accueil (`/`), deux pages de texte (`/mentions-legales`, `/confidentialite`), une
page d'erreur (`404.html`). Toutes les chaînes sont au § 10 ; ce paragraphe dit ce que chaque
section fait et comment elle est composée.

**Adresse au lecteur [H].** Le site parle **au centre**, au pluriel : « vos pompiers », « votre
centre », « écrivez-nous ». Ce n'est pas le vouvoiement de politesse de l'app (qui tutoie le
membre) : c'est l'adresse à un collectif, un bureau, une équipe. Les phrases impersonnelles sont
préférées quand elles suffisent (« Chaque pompier saisit… »). Alternative à valider : tutoiement
partout, plus proche du ton de l'app, plus risqué face à un président d'amicale inconnu.

### 4.1 En-tête

- À gauche : la marque (icône `design/assets/icone.svg`, 32 px, + « Astreinte SP » en Archivo 700
  20 px), lien vers `/`.
- À droite : « Prix » (ancre `#prix`, masqué sous 600 px) et « Se connecter » (lien vers l'app,
  bouton secondaire compact, 48 px de haut).
- **Pas collant** : sur téléphone, une barre fixe mange l'écran et masque le focus clavier.
- Lien d'évitement « Aller au contenu » en premier élément focalisable, visible au focus.

### 4.2 Accroche (héros)

- Titre `h1`, sous-titre, bouton primaire « Demander un essai gratuit », lien « Voir le prix »
  (ancre), une ligne de réassurance en `mention` : « 60 jours gratuits, sans carte bancaire. »
- Visuel : capture de l'**accueil du pompier** (tableau de bord, 064) sur téléphone ; à partir
  de 840 px, capture de la **matrice admin** derrière, en partie masquée par le téléphone.
- Pas de surtitre (« eyebrow ») au-dessus du titre : proscrit par la charte d'Impeccable.

### 4.3 L'essentiel (la fiche)

Tableau réglé de quatre lignes, directement sous l'accroche, **le cœur de la direction** : ce
qu'un trésorier veut savoir avant de lire le reste. Libellé à gauche en `libelle-champ`, valeur à
droite en `corps`, filet entre chaque ligne, chiffres en Atkinson Mono.

| Libellé | Valeur |
|---|---|
| Prix | 55 € par mois, ou 550 € par an, pour tout le centre |
| Essai | 60 jours gratuits, sans carte bancaire |
| Données | Stockées en Europe, jamais revendues |
| Engagement | Aucun : l'abonnement s'arrête quand vous voulez |

Balisage : `<dl>` ou `<table>` avec en-têtes de ligne ; pas quatre cartes. Chaque valeur est
reprise et détaillée plus bas (prix § 4.6, données et résiliation § 4.7) ; aucune n'est dite ici
sans l'être là.

### 4.4 Le problème

Titre, puis **trois constats**, chacun une phrase en `titre-bloc` et une phrase d'explication.
Composition en liste réglée (filets), pas en cartes. Aucune statistique. Les trois constats
viennent du PRD § 1, ce sont les frictions nommées par le produit, pas des chiffres :

1. Les dispos arrivent par morceaux, et quelqu'un les recopie.
2. « Disponible » devient « de garde » : qui coche tous ses week-ends pour laisser le choix se
   retrouve de garde tous les week-ends.
3. Un pompier ne peut plus, on l'apprend tard, et on refait le mois.

Mention des outils actuels (papier, tableur, WhatsApp) dans le titre, sans les moquer : c'est ce
que le lecteur utilise ce soir.

### 4.5 Comment ça marche, en trois étapes

**Les numéros 1, 2, 3 sont permis ici** (la séquence porte l'information : l'ordre du mois).
Chaque étape : numéro en Atkinson Mono dans une case, titre `h3`, deux à trois phrases, **une
case d'état du registre** qui illustre l'étape, et **la capture qui la prouve**.

| Étape | Case d'état (marque + icône + libellé, couleur en 4e) | Capture |
|---|---|---|
| 1. Chaque pompier saisit ses disponibilités | case pleine indigo `#7655FA`, coche blanche, « Disponible » | la saisie du mois (onglet Calendrier), téléphone |
| 2. Vous construisez le planning | case fond `#FDEAD7`, icône sablier `#9F6224`, « Proposé » | la matrice du mois, ordinateur |
| 3. Chacun accepte et reçoit ses rappels | case fond `#CEE5E1`, icône coche-cercle `#086959`, « Accepté » — **le tampon** | une proposition avec « Accepter » / « Refuser », téléphone |

Sous l'étape 3, un paragraphe distinct, **le second mécanisme**, en `titre-bloc` : « Un refus ne
défait pas le reste », avec sa phrase. Sous l'étape 1, le premier mécanisme : « Disponible, ce
n'est pas volontaire » (quotas du mois).

### 4.6 Le prix

Ancre `#prix`. **Une formule, deux rythmes de paiement**, dans un seul bloc réglé (pas trois
cartes, pas de formule « populaire ») :

- Deux colonnes égales sur grand écran, empilées sur téléphone : **Mensuel — 55 €** « par mois » ;
  **Annuel — 550 €** « par an », avec « 110 € offerts par rapport au mensuel ». Les montants en
  Atkinson Mono 700, 40 px. Les libellés « Mensuel », « Annuel », « par mois », « par an »
  reprennent **mot pour mot** ceux de l'écran Abonnement (`AppStrings.abonnementFormule*`,
  `abonnementPeriode*`).
- Dessous, ce que le prix couvre, en liste à coches (icône + texte) : tous les membres du centre
  jusqu'à 60 ; les administrateurs ; les notifications et les rappels ; l'export vers l'agenda ;
  les mises à jour.
- Ligne d'essai : « 60 jours gratuits, sans carte bancaire. À la fin, vous choisissez : vous
  abonner, ou rester en lecture seule. Rien n'est supprimé. »
- Ligne « Plus de 60 membres ? Écrivez-nous. », lien vers le courriel prérempli « plus de
  60 membres ».
- Ligne de paiement : « Paiement par carte bancaire, factures téléchargeables. »
- Bouton primaire « Demander un essai gratuit ».

**Égalité avec l'app (critère du ticket).** Les montants affichés par l'écran Abonnement
viennent des secrets `STRIPE_AMOUNT_MONTHLY` / `STRIPE_AMOUNT_YEARLY` ; les valeurs documentées
(`docs/STRIPE.md` § 5) sont encore 1200 / 12000 (12 € / 120 €). Avant la mise en ligne, vérifier
en production que ces secrets valent **5500 / 55000** et que les prix Stripe sont à 55 € / 550 €,
et mettre `docs/STRIPE.md` à jour. Sinon le site et l'app se contredisent (§ 11, point 3).

**HT ou TTC [H].** Non tranché : le brief écrit les montants sans mention, et le propriétaire
dit s'il faut « TTC », « HT » ou « TVA non applicable » (§ 11, point 4).

### 4.7 Questions fréquentes

`<details>` / `<summary>` natifs (clavier et lecteurs d'écran sans JavaScript), fermés par défaut,
un filet entre chaque, zone de touche de toute la ligne (≥ 56 px), chevron Material Symbols à
droite qui pivote (sans animation si mouvement réduit). Neuf questions, dans l'ordre des
objections d'un bureau : données, responsabilité, téléphones, hors ligne, fin d'essai,
résiliation, démarrage, mot de passe, ce que l'app ne fait pas. Textes au § 10.6.

Honnêteté exigée sur les données : la base est en Europe **[H : région à confirmer]**, mais les
notifications push passent par Firebase (Google, États-Unis) et contiennent parfois une date de
garde (`docs/RGPD.md` § 5). Le site le dit. Un chef de centre qui le découvre plus tard ne fait
plus confiance au reste.

### 4.8 Appel à l'essai (clôture)

**La seule bande de couleur pleine de la page** : fond indigo `#7655FA` sur toute la largeur,
texte blanc (4,72:1, conforme AA pour tout le texte de la bande, qui est ≥ 16 px). Titre, une
phrase, bouton **inversé** (fond blanc, texte `#5840BC`, 7,31:1), et en dessous « Déjà inscrit ?
Se connecter » en lien blanc souligné. C'est le seul endroit où l'indigo devient un champ : il dit
« choisir », comme dans l'app.

### 4.9 Pied de page

Fond papier doux `#F7F9FA`, filet haut. Marque en petit, puis liens : « Mentions légales »,
« Confidentialité », « Contact » (courriel), « Se connecter ». Ligne d'éditeur : « Astreinte SP
est édité par Staticflow LLC. » Ligne : « Ce site ne dépose aucun cookie. » Présent **à
l'identique sur les quatre pages** (critère du ticket : mentions et confidentialité liées depuis
chaque page).

### 4.10 Pages Mentions légales et Confidentialité

Mêmes en-tête et pied. Colonne de lecture de 68 caractères, `h1` Archivo, `h2` par rubrique,
texte en Atkinson 16/24. Contenu au § 8. Date de mise à jour en tête.

### 4.11 Page 404

« Cette page n'existe pas. » + « Retour à l'accueil ». Mêmes en-tête et pied.

---

## 5. États et plages de contenu

Un site statique a peu d'états, mais ceux-ci existent et sont spécifiés :

| Situation | Comportement attendu |
|---|---|
| JavaScript désactivé | Tout fonctionne, y compris le contact **si l'alias existe** (lien `mailto:` en clair). Seul le tampon ne s'anime pas : la case « Accepté » est dans son état final. |
| JavaScript désactivé **et** alias absent | Le bouton de contact ne peut pas s'assembler : il pointe vers `#contact`, une ligne dans le pied de page qui dit « Écrivez-nous à l'adresse affichée en activant JavaScript, ou depuis l'application. » Raison supplémentaire de créer l'alias avant la mise en ligne (§ 7.3). |
| Fontes lentes ou bloquées | `font-display: swap` avec une fonte de repli système réglée (`size-adjust`, `ascent-override`) pour ne pas décaler la page (CLS ≈ 0). |
| Image qui ne charge pas | `width` / `height` posés, texte alternatif complet (§ 10.8) : la mise en page ne bouge pas, le sens reste. |
| Mouvement réduit | Aucun mouvement : pas de tampon, pas de défilement doux vers les ancres, chevron de FAQ sans rotation animée. |
| Texte agrandi à 200 % | Rien ne se chevauche, rien ne se coupe ; le héros passe en une colonne dès que le titre dépasse la moitié de la largeur. |
| 320 px (petit téléphone) | Titre sur quatre lignes au plus, boutons pleine largeur, aucun défilement horizontal. |
| Mode sombre du système | **Ignoré volontairement** (§ 6.3) : `color-scheme: light`, la page reste claire et lisible. |
| Lien d'ancre partagé (`/#prix`) | La section s'ouvre sous l'en-tête, titre visible (`scroll-margin-top`). |
| Impression (le bureau imprime la page) | Feuille d'impression minimale : pas de captures, pas de bande indigo, adresses des liens affichées. Utile pour une réunion de bureau, peu coûteux. |

Plages de contenu : textes figés, mais **chaque chaîne doit tenir** à 320 px avec la fonte de
repli (plus large qu'Archivo). Les prix restent sur une ligne à toutes les largeurs.

---

## 6. Interaction et mise en page

### 6.1 Premier écran

**390 × 844 (iPhone, Safari, pas en PWA).** En-tête 64 px ; marge 20 px ; `h1` Archivo 700
**36/40**, interlettrage −0,02 em, trois lignes au plus ; sous-titre Atkinson 18/28 en
`on-surface-variant` ; bouton primaire pleine largeur 52 px ; lien « Voir le prix » 48 px ; mention
« 60 jours gratuits, sans carte bancaire. » ; sous le pli, le haut de la capture du téléphone
(cadre à rayon 20, filet 1 px), qui invite à défiler. Le bouton principal est **au-dessus du pli**
sur un iPhone de 844 px de haut, barres de Safari comprises.

**1280 × 800.** Grille de 12 colonnes, contenu max 1120 px, marges 32. Texte sur les colonnes
1 à 6 : `h1` **56/60**, sous-titre 20/30, boutons côte à côte (primaire 52 px, lien « Voir le
prix »). Colonnes 7 à 12 : capture de la matrice (cadre rayon 12, filet 1 px, pas d'ombre), le
téléphone posé devant en bas à gauche, chevauchant de 25 %, avec l'**ombre de niveau 3** de
`DESIGN.md` (`0 8 24 rgba(11,20,26,0.14)`) : c'est le seul objet qui flotte réellement. Le fond
de ce premier écran est le papier doux ; la fiche (§ 4.3) commence sur fond blanc juste après un
filet.

### 6.2 Points de rupture

| Largeur | Composition |
|---|---|
| < 600 | une colonne ; marges 20 ; captures centrées à 280 px de large (téléphone) ; matrice en **recadrage** (§ 7.4) ; FAQ pleine largeur |
| 600–839 | une colonne, contenu max 640 ; marges 24 ; en-tête montre « Prix » |
| 840–1199 | héros sur deux colonnes ; étapes : texte et capture côte à côte, en alternance gauche / droite ; prix sur deux colonnes |
| ≥ 1200 | idem, contenu max 1120, marges 32 ; la matrice s'affiche en entier |

Échelle typographique fixe par palier (pas de `clamp` fluide), cohérente avec `DESIGN.md`
§ Hierarchy qui refuse la typographie fluide : deux paliers, < 840 et ≥ 840.

| Rôle | < 840 | ≥ 840 | Fonte |
|---|---|---|---|
| `h1` | 36/40 | 56/60 | Archivo 700, −0,02 em |
| `h2` de section | 28/34 | 36/42 | Archivo 700, −0,02 em |
| `h3` (étape, question) | 20/26 | 22/28 | Archivo 600 |
| sous-titre, chapeau | 18/28 | 20/30 | Atkinson Next 400 |
| corps | 16/24 | 17/26 | Atkinson Next 400 |
| mention | 14/20 | 14/20 | Atkinson Next 400 |
| prix | 40/44 | 48/52 | Atkinson Mono 700, chiffres tabulaires |
| numéro d'étape | 20/24 | 20/24 | Atkinson Mono 700 |

Le passage de 16 à 17 px en corps sur grand écran est le seul écart à l'échelle de l'app : une
page de lecture à 1280 px lit mieux à 17. Mesure de la prose : 65–72 caractères.

Espacement : échelle de 4 de `DESIGN.md` (`4, 8, 12, 16, 24, 32, 48`) plus deux crans de page,
**64** (entre sections, < 840) et **96** (entre sections, ≥ 840). Plus d'espace au-dessus d'un
titre qu'en dessous.

### 6.3 Clair seulement

Scène : un chef de centre lit un lien reçu, sur son téléphone, le soir chez lui ou au bureau du
centre, puis le bureau regarde la page sur un portable ou un vidéoprojecteur. Un document qui se
présente et s'imprime : **thème clair seulement**. Les captures de l'app sont en clair ; une page
sombre autour de captures claires ferait des trous de lumière. Le critère « clair et sombre si le
brief le prévoit » ne s'applique donc pas. `<meta name="color-scheme" content="light">` et
`theme-color` `#F7F9FA`.

### 6.4 Interactions

- Aucun survol nécessaire. Survol = retour visuel seulement (bouton : surimpression 8 % ; lien :
  soulignement épaissi) ; même retour sur `:active` pour le tactile, et `:focus-visible` avec
  l'anneau de `DESIGN.md` (2 px `#7655FA` + 2 px de décalage ; sur la bande indigo, anneau blanc).
- Cibles : 48 px de haut minimum pour tout lien d'action et tout bouton ; liens dans le texte à
  hauteur de ligne 24, espacés.
- Liens externes (l'app) dans le même onglet : c'est une destination, pas une digression.
- Ancres : défilement doux sauf mouvement réduit.
- Tampon : déclenché une fois par un `IntersectionObserver` de quelques lignes quand la case
  « Accepté » est visible à 60 % ; état final dans le HTML, l'animation part d'un état déjà
  visible (le script n'ajoute une classe qu'après détection, la case n'est jamais cachée).

---

## 7. Identité, images, contact

### 7.1 Couleurs (sous-ensemble des jetons de `DESIGN.md`, clair)

| Jeton site | Valeur | Emploi |
|---|---|---|
| `--papier` | `#F7F9FA` | fond du héros, du pied de page |
| `--blanc` | `#FFFFFF` | fond des sections |
| `--encre` | `#131C23` | texte, titres |
| `--encre-2` | `#45535C` | texte secondaire (7,94:1 sur blanc, 7,52:1 sur papier) |
| `--filet` | `#C3CDD3` | réglure 1 px |
| `--contour` | `#6E7D87` | contour du bouton secondaire, cases (4,25:1, objet non textuel ≥ 3:1, jamais du texte) |
| `--indigo` | `#7655FA` | bouton primaire, bande finale, anneau de focus |
| `--indigo-texte` | `#5840BC` | liens, texte indigo (7,31:1) |
| `--indigo-pale` | `#E4DDFE` | sélection de texte (`::selection`, encre dessus) |
| états | `#FDEAD7`/`#9F6224`, `#CEE5E1`/`#086959` | cases des étapes 2 et 3 uniquement |

Interdits hérités : `orange-vif`, `rose-vif`, `accent-decoratif` jamais en texte ; pas de rouge
pompier, pas de gyrophare, pas de casque, pas de dégradé, pas de texte en dégradé, pas de verre.
Les navigateurs dessinent aussi : `::selection`, `accent-color`, `caret-color`, soulignement
(`text-underline-offset: 3px`, épaisseur 1 px, 2 px au survol) prennent la palette.

### 7.2 Typographie et fontes

Les trois fontes de l'app, **auto-hébergées**, jamais depuis Google Fonts ni un CDN :

| Fichier (WOFF2, sous-ensemble latin + diacritiques français) | Usage | Poids visé |
|---|---|---|
| `archivo-700.woff2` | `h1`, `h2` | ≤ 22 Ko |
| `archivo-600.woff2` | `h3` | ≤ 22 Ko |
| `atkinson-next-400.woff2` | corps | ≤ 18 Ko |
| `atkinson-next-700.woff2` | gras, libellés | ≤ 18 Ko |
| `atkinson-mono-700.woff2` | prix, numéros | ≤ 10 Ko (sous-ensemble chiffres, €, espace fine, ponctuation) |

**Contrairement à l'app, le WOFF2 est le bon format ici** : c'est le navigateur qui décode, pas
Skia (`DESIGN.md` § Typography explique pourquoi Flutter ne le lit pas). Produire depuis les
mêmes sources OFL que `assets/fonts/README.md`, avec `pyftsubset --flavor=woff2`, procédure
écrite dans `site/fonts/README.md`. Précharger (`<link rel="preload">`) **deux fichiers
seulement** : Archivo 700 et Atkinson Next 400. Fichier `OFL.txt` joint.

### 7.3 L'adresse de contact

**Recommandation : créer `contact@astreinte-sp.fr` avant la mise en ligne**, en redirection
simple chez OVH (gratuite avec le domaine) vers l'adresse du propriétaire. Raisons : l'adresse
personnelle ne s'expose pas aux robots ; le lien `mailto:` s'écrit en clair et marche sans
JavaScript ; l'adresse survit à un changement de boîte ; si elle est inondée, on la remplace sans
toucher au site.

Tous les liens de contact sont alors des `mailto:contact@astreinte-sp.fr` avec objet et corps
préremplis (§ 10.7), encodés en URL.

**En attendant l'alias** : l'adresse n'apparaît pas en clair dans le HTML. Les liens portent
`href="#contact"` et un attribut de données avec l'adresse découpée et inversée ; un script en
ligne de moins de 1 Ko assemble le `mailto:` **au clic** et l'ouvre. Il faut alors ajouter son
empreinte `sha256` à la CSP. Le jour où l'alias existe, ce script disparaît.

### 7.4 Images : quelles captures, comment les produire

**Quatre captures, toutes réelles, toutes avec des données fictives :**

| # | Écran | Format | Où |
|---|---|---|---|
| A | Accueil du pompier (tableau de bord : salutation, prochaine astreinte, propositions, appel à saisir) | téléphone | héros |
| B | Matrice du mois de l'admin (membres × jours × créneaux, quotas) | ordinateur 1440 × 900 ; recadrage 8 membres × 10 jours pour < 840 | héros (≥ 840), étape 2 |
| C | Saisie du mois (onglet Calendrier, cases jour / nuit, compteur) | téléphone | étape 1 |
| D | Une proposition ouverte, boutons « Accepter » / « Refuser » | téléphone | étape 3 |

**Production (reproductible, écrite dans `site/images/README.md`) :**

1. Base locale : `supabase db reset` avec `supabase/seed.sql` (caserne fictive « CIS
   Saint-Martin », membres fictifs : Jean Dupont, Marie Lefebvre, Camille Girard…). Le mois
   montré est un mois futur rempli par le seed, avec un planning publié pour que D existe.
   **Aucune donnée de production, jamais.** Vérifier sur chaque capture qu'aucune adresse
   électronique, aucun numéro de téléphone réel et aucun nom de caserne réelle n'apparaît.
2. App en local (`flutter run -d chrome --dart-define-from-file=env/dev.json`), thème clair.
3. Téléphone : Chrome, émulation 390 × 844, facteur 3, puis rognage de la barre d'adresse ;
   ou captures sur un iPhone avec la PWA installée pointée sur la base locale, barre d'état
   nettoyée (heure 9:41, batterie pleine). Même méthode pour A, C et D.
4. Ordinateur : fenêtre 1440 × 900, facteur 2.
5. Pas de cadre de téléphone photographique ni de maquette 3D : le cadre est dessiné en CSS
   (rayon 20, filet 1 px), identique pour les trois captures téléphone.
6. Export PNG sans perte, puis conversion en **AVIF** et **WebP** à deux largeurs (1x, 2x), servies
   par `<picture>` + `srcset` + `sizes`, avec `width` / `height` et `alt`. La capture A du héros
   est chargée avec `fetchpriority="high"` et sans `loading="lazy"` ; toutes les autres en
   `loading="lazy"` et `decoding="async"`.
7. Sous chaque capture, une légende en `mention` : « Données fictives de démonstration. »

**Budgets** (vérifiés en CI, § 9.3) : capture téléphone ≤ 60 Ko par variante AVIF à 2x ;
matrice ≤ 140 Ko en 2x, ≤ 50 Ko pour le recadrage ; image de partage ≤ 120 Ko ; **total des
images d'une visite complète à 390 px ≤ 350 Ko**.

**Captures de l'app iOS native (Foco) [H].** Le ticket parle de « captures réelles de l'app (PWA
et iPhone) ». Le brief lit : **la PWA sur iPhone**. Foco n'est aujourd'hui distribuée que par
TestFlight (`docs/IOS.md`) : montrer une app qu'on ne peut pas installer serait une promesse
invérifiable. À trancher par le propriétaire (§ 11, point 7).

**Image de partage (Open Graph).** 1200 × 630, PNG optimisé : fond papier doux, marque en haut à
gauche, le `h1` en Archivo 700 à gauche, la capture A recadrée à droite. Produite une fois en
HTML/CSS puis capturée, ou composée à la main ; source gardée dans `site/images/`.

**Favicon.** `design/assets/icone.svg` en `favicon.svg`, plus `apple-touch-icon.png` 180 × 180
et `favicon.ico` 32 × 32 dérivés.

### 7.5 Icônes

**Material Symbols Rounded** (Apache 2.0), la famille de l'app, graisse 400, taille optique 24,
style contour, **en SVG en ligne** (aucune fonte d'icônes à télécharger). Liste fermée : coche
(`check`), sablier (`hourglass_top`), coche-cercle (`check_circle`), calendrier
(`calendar_month`), cloche (`notifications`), cadenas (`lock`), téléphone (`smartphone`),
courriel (`mail`), chevron (`expand_more`), flèche sortante (`arrow_forward`). Taille 20 à côté
d'un texte de 16, 24 seules. Décoratives : `aria-hidden="true"`. Aucun emoji, aucun glyphe
Unicode en guise d'icône (ni ✓ ni →).

---

## 8. Mentions légales et confidentialité : contenu minimal

Les marques `[À COMPLÉTER : …]` suivent la convention de `docs/RGPD.md` : une mention trouée se
corrige, une mention inventée se croit. **Le site ne se publie pas avec une marque restante** :
la CI la cherche (§ 9.3).

### 8.1 Mentions légales (`/mentions-legales`)

- **Éditeur** : Staticflow LLC, `[À COMPLÉTER : forme, État d'immatriculation, numéro
  d'enregistrement]`, `[À COMPLÉTER : adresse du siège]`. Contact : l'adresse de contact
  (§ 7.3).
- **Directeur de la publication** : `[À COMPLÉTER : nom et qualité — a priori Jonathan
  Lemaine, gérant]`.
- **Hébergeur** : Vercel Inc., 440 N Barranca Ave #4133, Covina, CA 91723, États-Unis,
  `[À COMPLÉTER : téléphone ou moyen de contact de l'hébergeur, exigé par la LCEN — vérifier sur
  vercel.com/legal]`.
- **L'application** : Astreinte SP est servie depuis `https://astreinte.staticflow.ch` ; ses
  propres mentions et sa politique de confidentialité sont dans l'application
  (`/legal/mentions`, `/legal/confidentialite`), liens directs.
- **Propriété intellectuelle** : textes et captures © Staticflow LLC. Fontes Archivo et
  Atkinson Hyperlegible sous licence SIL Open Font License 1.1 ; icônes Material Symbols sous
  licence Apache 2.0.
- **Date de mise à jour**.

### 8.2 Confidentialité du site (`/confidentialite`)

Porte **sur le site vitrine seulement** ; les données des centres et des pompiers relèvent de
la politique de l'application, liée en tête de page.

1. **Ce que ce site ne fait pas** : aucun cookie, aucune mesure d'audience, aucun outil de suivi,
   aucun formulaire, aucune fonte ni image chargée chez un tiers.
2. **Ce que l'hébergeur enregistre** : Vercel tient des journaux techniques (adresse IP,
   navigateur, page demandée, date) pour la sécurité et le fonctionnement,
   `[À COMPLÉTER : durée de conservation selon Vercel]`. Base légale : intérêt légitime.
   Transfert : États-Unis, `[À COMPLÉTER : encadrement — clauses contractuelles types ou Data
   Privacy Framework]`.
3. **Quand vous écrivez** : le courriel sert à répondre et à ouvrir l'essai du centre ; il est
   conservé `[À COMPLÉTER : durée — proposition : trois ans après le dernier échange, usage
   courant pour un contact commercial]`, jamais revendu ni partagé. Il transite par la
   messagerie de l'éditeur `[À COMPLÉTER : OVH pour la redirection, puis le fournisseur de la
   boîte]`.
4. **Vos droits** : accès, rectification, effacement, opposition, par courriel à l'adresse de
   contact ; réclamation possible auprès de la CNIL (cnil.fr).
5. **Responsable** : Staticflow LLC. `[À COMPLÉTER : représentant dans l'Union européenne
   (article 27 du RGPD) si l'éditeur, établi hors de l'Union, en a besoin ; question juridique à
   trancher par le propriétaire]`.
6. **Date de mise à jour**.

**Mesure d'audience [H].** Le brief retient **aucune** au lancement. Vercel Web Analytics (sans
cookie, script servi depuis le domaine) resterait possible plus tard ; il faudrait alors ajouter
une rubrique ici. Décision au propriétaire (§ 11, point 9).

---

## 9. Technologie, hébergement, performances

### 9.1 HTML et CSS statiques, sans étape de construction

**Choix : HTML et CSS écrits à la main, pas Astro.** Justification :

- **Quatre fichiers HTML** (accueil, mentions, confidentialité, 404). Le seul gain d'Astro serait
  de factoriser l'en-tête et le pied de page, et sa chaîne d'images. Le prix : Node, un
  `package.json`, un fichier de verrou, une étape de construction dans la CI et dans Vercel, des
  mises à jour de dépendances à suivre. Pour quatre pages figées, le rapport est mauvais.
- Sans construction, **ce qui est dans le dépôt est ce qui est servi** : la revue lit le HTML
  livré, le contrat de direction (§ 3.2) survit forcément, et Lighthouse mesure le fichier relu.
- Les images sont préparées **une fois** par un script (`site/scripts/images.sh`, `cwebp`,
  `avifenc` ou `sharp` en `npx` épinglé) et les fichiers produits sont versionnés, avec leur
  source PNG.
- **Aucun JavaScript** sauf deux scripts en ligne de moins de 1 Ko chacun, tous deux facultatifs :
  le tampon (§ 6.4) et, tant que l'alias n'existe pas, l'assemblage du courriel (§ 7.3). Leur
  empreinte `sha256` figure dans la CSP.
- Le risque de la duplication (un pied de page modifié sur une page et pas sur les autres) est
  couvert par un contrôle de CI : le bloc `<footer>` est identique sur les quatre pages.

Arborescence proposée : `site/index.html`, `site/mentions-legales.html`,
`site/confidentialite.html`, `site/404.html`, `site/style.css`, `site/print.css`,
`site/fonts/`, `site/images/`, `site/icons/` (favicons), `site/robots.txt`, `site/sitemap.xml`,
`site/vercel.json`, `site/README.md`.

### 9.2 Vercel et en-têtes

`vercel.json` : `cleanUrls: true`, `trailingSlash: false`, redirections 301 de
`www.astreinte-sp.fr`, `astreint-sp.fr`, `www.astreint-sp.fr` vers `https://astreinte-sp.fr`
(par la configuration des domaines du projet), et en-têtes :

- `Content-Security-Policy: default-src 'none'; style-src 'self'; font-src 'self'; img-src 'self'; script-src 'sha256-…'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'` — aucun tiers ne peut être chargé, c'est la preuve technique du « zéro traceur ».
- `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` vide (caméra, micro, géolocalisation, `interest-cohort` refusés).
- Cache : fontes et images `max-age=31536000, immutable` (noms de fichiers versionnés par un suffixe, `style.v1.css`) ; HTML `max-age=0, must-revalidate`.

### 9.3 Contrôles de la CI (job déclenché seulement si `site/` change)

1. **HTML valide** : `html-validate` (version épinglée) sur les quatre pages.
2. **Liens internes** : `lychee --offline` ou `linkinator` sur `site/` ; ancres comprises.
3. **Poids** : script qui échoue si une image dépasse son budget (§ 7.4), si les fontes dépassent
   90 Ko au total, si `style.css` dépasse 20 Ko.
4. **Aucun tiers** : aucune URL `http(s)://` dans `src`, `href` de feuille de style ou `srcset`
   qui ne soit pas relative ; aucun `<script src>`.
5. **Aucune marque `[À COMPLÉTER`** dans les pages publiées.
6. **Pied de page identique** sur les quatre pages.
7. Lighthouse : le rapport mobile est joint à la PR (critère du ticket) ; un job Lighthouse CI est
   un plus, pas une exigence du brief.

### 9.4 Budgets de performance (Lighthouse mobile ≥ 95 sur les quatre catégories)

| Poste | Budget |
|---|---|
| HTML de l'accueil, brotli | ≤ 12 Ko |
| CSS, brotli | ≤ 8 Ko |
| Fontes préchargées | 2 fichiers, ≤ 40 Ko |
| Image du héros (LCP) à 390 px | ≤ 45 Ko |
| Poids au premier affichage à 390 px | ≤ 130 Ko |
| JavaScript | ≤ 2 Ko en ligne, aucun fichier |
| LCP (4G lente simulée) | < 2,0 s |
| CLS | < 0,02 |

### 9.5 Référencement

- `<html lang="fr">`, un seul `h1` par page, titres dans l'ordre.
- `title` et `meta description` par page (§ 10.1), `link rel="canonical"` vers
  `https://astreinte-sp.fr/…`.
- Open Graph : `og:title`, `og:description`, `og:image` (1200 × 630, URL absolue), `og:url`,
  `og:type=website`, `og:locale=fr_FR` ; `twitter:card=summary_large_image`.
- `sitemap.xml` (trois URL, sans la 404), `robots.txt` qui l'annonce et autorise tout.
- Données structurées JSON-LD `SoftwareApplication` : `name`, `applicationCategory:
  BusinessApplication`, `operatingSystem: "Web, iOS, Android"` (navigateur), `url`,
  `offers` = deux `Offer` (55 EUR / mois, 550 EUR / an, `priceCurrency: EUR`), `publisher`
  Staticflow LLC. **Pas d'`aggregateRating` ni de `review`.**

---

## 10. Textes

Toutes les chaînes du site. Aucune n'est à inventer par le développeur.

### 10.1 Métadonnées

| Page | `title` | `description` |
|---|---|---|
| Accueil | Astreinte SP — le planning d'astreinte des centres de secours | Les pompiers saisissent leurs disponibilités sur leur téléphone, le chef de centre construit le planning, chacun valide son créneau. 55 € par mois, essai gratuit. |
| Mentions | Mentions légales — Astreinte SP | Éditeur, hébergeur et directeur de la publication du site Astreinte SP. |
| Confidentialité | Confidentialité du site — Astreinte SP | Ce site ne dépose aucun cookie et ne mesure pas votre visite. Ce que l'hébergeur enregistre, et vos droits. |
| 404 | Page introuvable — Astreinte SP | — |

`og:title` de l'accueil : « Le planning d'astreinte, validé par chaque pompier ».

### 10.2 En-tête et commun

- Marque : « Astreinte SP »
- Lien d'évitement : « Aller au contenu »
- Navigation : « Prix » · « Se connecter »
- Légende de capture : « Données fictives de démonstration. »

### 10.3 Accroche

- `h1` : **« Le planning d'astreinte, validé par chaque pompier. »**
- Sous-titre : « Chacun saisit ses disponibilités sur son téléphone. Vous construisez le mois.
  Chaque pompier accepte ou refuse son créneau, et un refus ne défait pas le reste. »
- Bouton : « Demander un essai gratuit »
- Lien : « Voir le prix »
- Réassurance : « 60 jours gratuits, sans carte bancaire. »

Variante de `h1` à garder en réserve : « Les astreintes du mois, sans tableur ni relances. »

### 10.4 L'essentiel

- Titre (visuellement discret, `h2` pour la structure) : « L'essentiel »
- « Prix » — « 55 € par mois, ou 550 € par an, pour tout le centre »
- « Essai » — « 60 jours gratuits, sans carte bancaire »
- « Données » — « Stockées en Europe, jamais revendues »
- « Engagement » — « Aucun : l'abonnement s'arrête quand vous voulez »

### 10.5 Problème, étapes, mécanismes

**Problème**

- `h2` : « Papier, tableur, WhatsApp : le planning se fait à la main »
- « Les disponibilités arrivent par morceaux. » — « Un message, une feuille, un appel. Quelqu'un
  recopie tout, case par case, et relance ceux qui n'ont pas répondu. »
- « “Disponible” finit en “de garde”. » — « Celui qui coche tous ses week-ends pour vous laisser
  le choix se retrouve de garde tous les week-ends. »
- « Un pompier ne peut plus, et on refait le mois. » — « Le planning n'est validé par personne.
  On apprend le problème tard, et on reprend tout. »

**Comment ça marche**

- `h2` : « Comment ça marche »
- Chapeau : « Trois temps, chaque mois. »
- Étape 1 — « Chaque pompier saisit ses disponibilités » — « Jour et nuit, pour tout le mois, en
  quelques touches : tous les week-ends, toutes les nuits de semaine, copier le mois précédent.
  La saisie se ferme à la date que vous fixez. » — Case : « Disponible »
- Mécanisme 1 — « Disponible, ce n'est pas volontaire. » — « Chacun indique aussi combien
  d'astreintes et de week-ends il veut vraiment faire dans le mois. Vous voyez qui est
  disponible, et qui a déjà son compte. »
- Étape 2 — « Vous construisez le planning » — « Le mois entier sur un écran : qui est
  disponible, qui est absent, qui n'a rien saisi. Une proposition automatique remplit les
  créneaux en équilibrant la charge ; vous corrigez. Rien n'est visible avant que vous publiiez. »
  — Case : « Proposé »
- Étape 3 — « Chacun accepte et reçoit ses rappels » — « À la publication, chaque pompier reçoit
  ses créneaux et répond pour chacun. Sans réponse, un rappel part tout seul. Les astreintes
  acceptées s'ajoutent à son agenda. » — Case : « Accepté »
- Mécanisme 2 — « Un refus ne défait pas le reste. » — « Si quelqu'un refuse, seul ce créneau
  est à réattribuer, et seule la nouvelle personne est prévenue. Le reste du mois ne bouge pas. »

### 10.6 Prix et questions

**Prix**

- `h2` : « Un prix pour tout le centre »
- « Mensuel » — « 55 € » — « par mois »
- « Annuel » — « 550 € » — « par an » — « 110 € offerts par rapport au mensuel »
- Liste « Compris » : « Tous les membres du centre, jusqu'à 60 » · « Autant d'administrateurs
  que nécessaire » · « Notifications et rappels automatiques » · « Export vers l'agenda du
  téléphone » · « Les nouvelles versions, sans supplément »
- Essai : « 60 jours gratuits, sans carte bancaire. À la fin, vous choisissez : vous abonner, ou
  garder vos plannings en lecture seule. Rien n'est supprimé. »
- « Plus de 60 membres ? Écrivez-nous. »
- « Paiement par carte bancaire, factures téléchargeables. Payé par le centre ou par l'amicale. »
- Bouton : « Demander un essai gratuit »

**Questions fréquentes** — `h2` : « Questions fréquentes »

1. « Où sont stockées les données de nos pompiers ? » — « Dans une base de données hébergée en
   Europe [à confirmer : région]. Chaque centre est cloisonné : un centre ne voit jamais les
   données d'un autre. Les notifications push passent par le service de Google (Firebase), aux
   États-Unis ; elles contiennent le texte de la notification, parfois une date de garde. Les
   données ne sont jamais revendues. »
2. « Qui est responsable de ces données ? » — « Votre centre, qui décide de ce qu'il y met.
   L'éditeur les héberge et les traite pour votre compte. Chaque pompier peut exporter ses données
   personnelles et supprimer son compte depuis l'application ; son historique d'astreintes reste,
   au nom de “Membre supprimé”. »
3. « Ça marche sur iPhone et sur Android ? » — « Oui, dans le navigateur, sans rien télécharger
   sur un store. L'application s'installe sur l'écran d'accueil en deux gestes. Sur iPhone, les
   notifications demandent cette installation ; l'application explique comment à la première
   connexion. »
4. « Et sans réseau ? » — « Le dernier état connu reste lisible : vos astreintes et votre mois.
   Saisir ses disponibilités et répondre à une proposition demandent une connexion. »
5. « Que se passe-t-il à la fin de l'essai ? » — « Si vous ne vous abonnez pas, le centre passe
   en lecture seule : tout reste consultable, rien n'est supprimé. Vous pouvez vous abonner à tout
   moment pour reprendre. »
6. « Comment arrêter l'abonnement ? » — « Depuis l'écran Abonnement de l'application, à tout
   moment, sans engagement. Le centre passe alors en lecture seule ; aucune donnée n'est
   supprimée pour un abonnement arrêté ou impayé. » [H : préciser « à la fin de la période
   payée » si c'est le réglage du portail Stripe.]
7. « Combien de temps pour démarrer ? » — « Le temps d'importer la liste de vos pompiers depuis
   un tableur et de leur envoyer l'invitation. Chacun se connecte avec son adresse
   électronique. »
8. « Faut-il un mot de passe ? » — « Non. On se connecte avec un code à 6 chiffres reçu par
   courriel. Rien à retenir, rien à réinitialiser. »
9. « Qu'est-ce que l'application ne fait pas ? » — « Elle gère les disponibilités et le planning
   d'astreinte. Elle ne gère pas les interventions, le matériel, les formations ni la paie,
   n'envoie pas de SMS et n'est pas reliée aux logiciels du SDIS. »

### 10.7 Clôture, contact, pied de page, 404

- Bande finale, `h2` : « Essayez sur votre prochain mois »
- Phrase : « Écrivez-nous le nom de votre centre : nous l'ouvrons, vous invitez vos pompiers,
  vous publiez un premier planning. 60 jours gratuits, sans carte bancaire. »
- Bouton : « Demander un essai gratuit »
- Lien : « Déjà inscrit ? Se connecter »

**Courriel prérempli « essai »**
- Objet : « Essai d'Astreinte SP »
- Corps :
  ```
  Bonjour,

  Nous aimerions essayer Astreinte SP.

  Centre de secours :
  Département :
  Nombre de membres (environ) :
  Adresse électronique de l'administrateur :
  Téléphone (facultatif) :

  Merci.
  ```

**Courriel prérempli « plus de 60 membres »**
- Objet : « Astreinte SP — centre de plus de 60 membres »
- Corps : même trame, première phrase « Notre centre compte plus de 60 membres. »

**Pied de page**
- « Astreinte SP est édité par Staticflow LLC. »
- « Ce site ne dépose aucun cookie. »
- Liens : « Mentions légales » · « Confidentialité » · « Contact » · « Se connecter »
- Sans alias et sans JavaScript (ancre `#contact`) : « Pour nous écrire, activez JavaScript ou
  écrivez-nous depuis l'application. »

**404**
- `h1` : « Cette page n'existe pas. »
- Phrase : « Le lien est peut-être ancien. »
- Lien : « Retour à l'accueil »

### 10.8 Textes alternatifs des captures

- A : « Accueil de l'application sur un téléphone : la prochaine astreinte, deux propositions à
  répondre et l'appel à saisir le mois. »
- B : « Planning du mois sur ordinateur : une ligne par pompier, deux cases par jour, jour et
  nuit, avec les disponibilités et le nombre d'astreintes de chacun. »
- C : « Saisie des disponibilités sur un téléphone : le calendrier du mois, deux cases par jour,
  et le compteur des jours, nuits et week-ends cochés. »
- D : « Une astreinte proposée, avec ses boutons Accepter et Refuser. »
- Cases d'état des étapes : texte visible (« Disponible », « Proposé », « Accepté ») ; icônes
  décoratives.

(Les textes alternatifs seront relus contre les captures finales : ils décrivent ce qui est
réellement à l'écran.)

---

## 11. Décisions ouvertes, à valider par le propriétaire

1. **Le bouton d'essai** ouvre une demande par courriel, pas l'app, faute d'inscription en
   libre-service (§ 2.1). Remplacer le critère d'acceptation en conséquence, ou ouvrir un ticket
   d'inscription en libre-service.
2. **Créer l'alias `contact@astreinte-sp.fr`** chez OVH avant la mise en ligne (§ 7.3). Sans lui,
   le bouton principal dépend de JavaScript.
3. **Prix réels de l'app** : confirmer que `STRIPE_AMOUNT_MONTHLY` / `STRIPE_AMOUNT_YEARLY`
   valent 5500 / 55000 en production et que les prix Stripe sont à 55 € / 550 € ;
   `docs/STRIPE.md` dit encore 12 € / 120 €.
4. **HT, TTC ou « TVA non applicable »** à côté des prix.
5. **Région Supabase** (Europe, laquelle ?) avant d'écrire « Stockées en Europe » (`docs/RGPD.md`
   § 5 la marque encore `[À COMPLÉTER]`).
6. **Mentions légales** : adresse et immatriculation de Staticflow LLC, directeur de la
   publication, contact de Vercel, représentant dans l'UE (art. 27) si nécessaire.
7. **Foco** : montrer ou non l'app iOS native, aujourd'hui en TestFlight seulement (§ 7.4). Le
   brief ne la montre pas.
8. **Adresse au lecteur** : « vous » collectif (retenu) ou tutoiement (§ 4).
9. **Mesure d'audience** : aucune (retenu) ou Vercel Web Analytics.
10. **Résiliation** : immédiate ou à la fin de la période payée (FAQ 6).
11. **Nom** : « Astreinte SP » reste un nom de travail (`PRODUCT.md`) ; le site le fixe
    publiquement avec le domaine.
12. **Composition** : « La fiche pour le bureau » (retenue) ; alternatives tirées : « Le mois qui
    se remplit » (la page suit un mois, de l'ouverture de la saisie à la validation) et « Le
    créneau refusé » (tout le récit autour d'un seul créneau). Tirage dégradé, sans challenger.

---

## 12. Checklist craft-floor (Impeccable), annotée pour le développeur

- [x] **Contraste** : paires de texte prises dans `DESIGN.md`, toutes ≥ 4,5:1 ; blanc sur indigo
  4,72:1 ; `--encre-2` 7,94:1 ; aucun gris clair sur gris. À **mesurer** sur le rendu.
- [x] **Profondeur** : une seule ombre (téléphone du héros), avec décalage et flou. Aucun halo.
- [x] **Espacement** : échelle de 4, crans de section 64 / 96, plus d'espace au-dessus des titres.
- [x] **Typographie** : mesure 65–72 caractères, titre ≤ 56 px, interlettrage ≥ −0,02 em,
  `text-wrap: balance` sur les titres, paliers nets. Passer les vrais textes à 320, 390, 1280.
- [x] **Mouvement** : un seul moment (le tampon), depuis un état visible, désactivé en mouvement
  réduit.
- [x] **États** : survol, `:active`, `:focus-visible`, sans JS, images absentes, 404 (§ 5).
- [x] **Surfaces du navigateur** : `::selection`, `caret-color`, `accent-color`, soulignements,
  chiffres tabulaires des prix, anneau de focus — tous dans la palette (§ 7.1).
- [x] **Textes** : le vocabulaire des pompiers (§ 10), les boutons nomment l'action.
- [x] **Couverture** : accroche, problème, trois étapes, captures, prix, FAQ, essai, pied de page
  avec mentions et confidentialité — tout le périmètre du ticket, rien de plus.
- [x] **Refusés** : pas de cartes identiques icône-titre-texte, pas de héros à chiffre, **pas de
  surtitre**, pas de numéros de section (sauf les étapes, dont l'ordre informe), pas de modale,
  pas de dégradé ni de texte en dégradé, pas de verre, pas de bordure gauche colorée, pas
  d'ombre dure, pas de mono en costume (Mono = prix et numéros, de la mesure), pas d'emoji ni de
  glyphe Unicode, clair choisi par la scène et non par la catégorie.

## 13. Checklist ui-ux-pro-max (app mobile), annotée pour le web

Les requêtes métier (`--domain web|ux|landing|typography|color`) n'ont rendu que des règles
génériques (optimisation d'images, lien d'évitement, mouvement réduit, prix annuel transparent) ;
aucune palette ni fonte proposée n'a été retenue (Poppins, Space Grotesk, palettes « podcast »
hors sujet). La checklist ci-dessous est celle de l'app mobile, lue pour une page web sur
téléphone.

**Visuel**
- [x] Aucun emoji comme icône ; une seule famille (Material Symbols Rounded, contour, 400).
- [x] Marque officielle (`icone.svg`) sans déformation.
- [x] États de pression sans déplacement de mise en page (surimpression, pas de `transform`).
- [x] Jetons sémantiques en variables CSS, aucune couleur en dur hors `:root`.

**Interaction**
- [x] Retour visuel à la pression sur chaque bouton et lien d'action.
- [x] Cibles ≥ 48 px de haut, 8 px entre deux cibles.
- [x] Durées issues des jetons de `DESIGN.md` (`courant` 180 ms).
- [n/a] États désactivés : aucun contrôle désactivé sur le site.
- [x] Ordre de focus = ordre visuel ; libellés explicites (« Demander un essai gratuit », pas
  « En savoir plus »).
- [x] Aucun geste : pas de carrousel, pas de glissement, rien au bord gauche qui gêne le retour
  iOS.

**Clair / sombre**
- [x] Texte ≥ 4,5:1 en clair.
- [n/a] Sombre : non prévu, décision motivée (§ 6.3) ; `color-scheme: light` déclaré.
- [x] Filets visibles (`#C3CDD3` sur blanc et sur `#F7F9FA`).

**Mise en page**
- [x] Zones sûres : `viewport-fit=cover` **non** utilisé, donc Safari garde ses marges ; aucune
  barre fixe.
- [x] Aucun contenu masqué par un élément collant (en-tête non collant, `scroll-margin-top`).
- [x] Vérifier à 320, 390, 768, 1280 px, et en paysage téléphone.
- [x] Marges adaptées par palier (20 / 24 / 32).
- [x] Rythme de 4 / 8.
- [x] Mesure de lecture tenue sur grand écran (prose ≤ 72 caractères).

**Accessibilité**
- [x] Icônes décoratives `aria-hidden="true"` ; captures avec texte alternatif (§ 10.8).
- [x] La FAQ annonce son état ouvert / fermé (natif avec `<details>`).
- [n/a] Formulaires : aucun.
- [x] Couleur jamais seule : cases d'état avec marque, icône et libellé.
- [x] Mouvement réduit et texte à 200 % sans casse.
- [x] Rien de collant ne masque le focus clavier.
- [x] Aucun contenu qui défile tout seul.
- [x] Lien d'évitement, repères (`header`, `main`, `footer`, `nav` avec nom), `lang="fr"`.
