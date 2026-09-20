# 012 — Raccourcis de sélection

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web
mobile-first**, Material 3, une seule apparence.

`DESIGN.md` gagne sur ce brief pour toute valeur de token, et `design/011-saisie-dispos-grille.md`
pour tout ce qui concerne la grille : ce brief n'ajoute qu'une bande et deux surfaces. Il est
court exprès. L'essentiel est au 011.

Sources : `tickets/in-progress/012-raccourcis-selection.md`, `docs/PRD.md § 6.3`,
`design/011-saisie-dispos-grille.md § 4, § 6.5`.

---

## 1. Le job

Le pompier ne vient pas explorer, il vient **déverser une intention déjà formée** (011 § 1) :
« mes nuits en semaine », « tous mes weekends », « pareil que le mois dernier ». Le 011 lui a
donné la touche et la peinture, qui coûtent respectivement 62 gestes et 2 gestes plus un doigt
posé sur un téléphone tenu d'une main. Ce ticket lui donne la phrase entière en deux touches.

Le chiffre du PRD — **un mois saisi en moins de deux minutes** — est déjà tenu par la peinture.
Ce que les raccourcis ajoutent, c'est la saisie **sans regarder la grille** : on peut remplir son
mois debout, en marchant, sans viser.

## 2. Ce qui est livré

**Une bande de cinq boutons**, à la place exacte que le 011 lui avait réservée (§ 6.5, point 4) :
entre le sélecteur de mois et le bloc d'aide, au-dessus de l'en-tête épinglé, en `compact` et
`medium` ; **en tête du panneau de droite**, au-dessus des compteurs, en `large`.

Chaque bouton est une **portée** — quels jours — et ouvre une feuille de bas d'écran qui demande
le **créneau** — jour, nuit, ou les deux :

| Bouton | Ce qu'il couvre | Ce qu'il pose |
|---|---|---|
| **Les weekends** | samedis et dimanches | disponible |
| **La semaine** | lundi → vendredi, fériés compris | disponible |
| **Tout le mois** | les 28 à 31 jours | disponible |
| **Copier le mois précédent** | tout le mois | les valeurs du mois précédent, alignées |
| **Tout effacer** | tout le mois | non saisi |

**Les six raccourcis du ticket sont ces couples.** « Toutes les nuits en semaine » est
*La semaine × Nuit* ; « tous les jours en semaine » est *La semaine × Jour*. Le couple en donne
quinze au lieu de six, sans un bouton de plus à l'écran.

**Pourquoi une feuille plutôt qu'un menu.** Le menu Material accroche des cibles de 36 dp au
bouton ; ce public porte des gants et `DESIGN.md § Cibles tactiles` plancher à 48. La feuille
donne trois rangées de 56 dp au pouce, se referme au geste retour, et affiche **le nombre de
cases que chaque choix changerait** — « 10 cases » — avant l'acte. Un raccourci qui afficherait
« 0 case » dit qu'il est déjà appliqué, ce qu'aucun libellé ne dirait.

**Pourquoi pas un mode armé** (« je pose : disponible / absent / effacer »). Le 011 l'interdit
explicitement (§ 4, anti-objectifs) et la raison vaut ici : un mode invisible, avec des gants, à
6 h du matin, est la pire panne possible.

## 3. Les deux décisions à trancher

### 3.1 Les fériés en semaine ne sont **pas** des weekends, ici

`PRD § 6.3` dit : « Jours fériés français affichés et considérés comme weekend **pour le
comptage** ». C'est une règle de quota, pas une règle de calendrier, et elle reste vraie : le
compteur « Weekends » du 011 compte déjà le 14 juillet comme une unité (`uniteWeekend`).

Le raccourci, lui, est **calendaire**. Le critère d'acceptation du ticket est sans ambiguïté :
« coche **exactement** les samedis et dimanches nuit ». Un membre qui touche « Les weekends » et
récupère le 11 novembre aurait raison de se sentir trahi — et il ne le verrait pas, parce qu'il
ne regarde pas la grille quand il utilise un raccourci.

**Conséquence, tenue par un test** : « Les weekends » et « La semaine » partagent le mois sans
trou ni recouvrement, et leur union est exactement « Tout le mois ». Un férié en semaine
appartient à « La semaine ». Il reste étoilé et nommé dans la grille, à une touche.

### 3.2 « Copier » aligne les semaines, pas les numéros

Un mois ne commence presque jamais le même jour que le précédent. Copier le 1er sur le 1er
mettrait les weekends en plein milieu de la semaine — exactement ce que le critère interdit.

La règle : un décalage `a` tel que chaque jour source et son jour cible tombent le **même jour de
la semaine**. Il y en a une infinité, espacés de sept ; on prend celui de plus petite valeur
absolue, donc dans `[-3, 3]`, pour que la copie reste à sa place dans le mois au lieu de glisser
d'une semaine.

**Conséquence assumée** : jusqu'à trois jours d'un bord n'ont pas de source et repartent à
« non saisi ». Copier, c'est **reproduire** le mois précédent, pas se superposer à ce qui est là.
C'est aussi pourquoi cette action demande confirmation.

*Vérifié en vrai* : octobre 2026 (commence un jeudi) copié dans novembre 2026 (commence un
dimanche) donne un décalage de −3. Les treize nuits saisies d'octobre arrivent toutes sur le même
jour de semaine ; celle du jeudi 1er octobre, qui viserait le 28 septembre, est abandonnée.

## 4. Protéger et défaire

**Confirmation** avant « Tout effacer » et « Copier le mois précédent », et **seulement si des
saisies existent** dans la portée visée. Le titre porte le compte exact : « Effacer 47 saisies ? ».
Effacer un mois déjà vierge ne protège rien et n'ouvre aucune modale. Les trois autres raccourcis
n'enlèvent rien à personne : les confirmer tous ferait du bruit et userait celles qui comptent
(`DESIGN.md § Don't`).

**Annulation : une ligne de résultat sous la bande**, qui n'existe que quand elle a quelque chose
à dire — « 47 cases mises à jour · Tout effacer, jour et nuit » à gauche, « Annuler » à droite.

Trois raisons de l'avoir choisie plutôt qu'un `SnackBar` :

1. **Elle ne part pas toute seule.** Un `SnackBar` s'efface en quatre secondes. Le membre qui
   relève les yeux pour ranger un tuyau aurait perdu son annulation, et une erreur de raccourci
   coûte soixante-deux cases.
2. **Elle est au même endroit que la cause.** Le doigt vient de quitter cette bande.
3. **Elle ne coûte aucune surface nouvelle.** Du texte et un bouton dans un bloc qui existe déjà.

Ce n'est pas l'annulation générale que le 011 refuse (§ 4) : **un seul cran**, celui du dernier
raccourci, et il **tombe dès qu'une case est touchée à la main** — à ce moment-là, annuler
emporterait la retouche, et la case redevient son propre annulateur. L'annulation restitue les
valeurs exactes d'avant, `absent` compris, et repart par la même file : une requête.

## 5. Période verrouillée, caserne suspendue

La bande **reste à sa place**, boutons inertes : fond `surface-container-highest`, encre
`outline`, `Semantics(enabled: false)`, et **la raison juste en dessous** —
« Mois verrouillé : les raccourcis ne s'appliquent plus. » (`DESIGN.md § Do` : « Expliquer
pourquoi un contrôle est désactivé, à côté du contrôle »). Les faire disparaître changerait la
forme de l'écran entre deux mois et laisserait chercher une action qui n'est plus là.

Le contrôleur garde la règle une seconde fois : un raccourci appelé sur un mois verrouillé ne
lit rien, n'écrit rien, ne propose rien à annuler.

## 6. Le coût réseau

**Aucun second chemin d'écriture n'est ouvert.** `appliquerRaccourci` descend dans le `_poser` du
011, donc dans la même file `Map<CreneauCle, …>` coalescée, la même persistance locale et le même
traitement des refus. Soixante-deux modifications posées d'un coup sont **une** entrée par case
dans la file, partent après le même délai de 500 ms, et coûtent **une requête par type
d'opération** : un envoi groupé, une suppression groupée.

Le ticket évoque une RPC `bulk_set_availabilities`. **Elle n'existe pas dans `docs/SCHEMA.md` et
n'est pas nécessaire** : `enregistrerLot` et `supprimerLot` valent déjà exactement une requête
chacune, le contrat est écrit dans l'interface du dépôt (011), et la RLS de `availabilities` dit
déjà qui écrit et quand. Ajouter une fonction serait un second chemin à sécuriser pour zéro
requête gagnée.

*Mesuré en vrai, dans Chrome, contre la pile locale* : « La semaine × Nuit » sur dix cases → un
`POST`. « Tout effacer × Jour et nuit » sur quarante-sept saisies → un `DELETE`. Son annulation →
un `POST`. « Copier le mois précédent » → un `GET` (le mois source) + un `POST` + un `DELETE`.

## 7. États et textes

| État | Rendu |
|---|---|
| **Au repos** | Cinq boutons, pas de ligne de résultat. |
| **Feuille ouverte** | Titre = la portée, une phrase de portée, trois rangées avec leur compte. |
| **Confirmation** | `AlertDialog`, titre chiffré, bouton `danger`. Les deux seules modales du ticket. |
| **Lecture du mois précédent** | Le bouton garde son libellé, un indicateur de 20 dp prend la place de son icône. |
| **Appliqué** | Ligne de résultat + « Annuler », annoncée en `liveRegion`. |
| **Sans effet** | « Rien à changer : ces cases sont déjà comme ça. » à la place de la ligne. |
| **Copie impossible** | « Impossible de lire le mois précédent. Vérifie ta connexion, puis réessaie. » |
| **Verrouillé / lecture seule** | Boutons inertes + la raison. |
| **Hors ligne** | Rien de particulier : le raccourci s'empile comme une touche, et part au retour du réseau. |

Toutes les chaînes sont dans `AppStrings`, section « Raccourcis de sélection (ticket 012) ».

## 8. Ce qui n'est pas là

- **Poser « absent » en masse.** Les raccourcis posent `disponible` ou effacent. Un mois entier
  d'absence se fait par « Tout le mois » puis une seconde touche par case, ou par la peinture.
  Hors ticket ; à rouvrir si les casernes le demandent.
- **Un raccourci « les jours fériés ».** Il aurait du sens pour un chef de centre ; le membre en
  a zéro à trois par mois, et la grille les étoile déjà.
- **Plus d'un cran d'annulation.** Un historique serait un troisième modèle mental (011 § 4).

## 9. Écart reporté

La bande occupe une soixantaine de dp entre le sélecteur et l'en-tête épinglé. Sur un écran de
390 × 844, c'est **une ligne de jour de moins visible d'emblée**. C'est le prix annoncé par le
011 quand il a réservé la place, et il est payé : deux touches contre soixante-deux valent bien
un jour de défilement.
