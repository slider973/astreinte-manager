# 032 — Build web PWA et déploiement

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web**,
Material 3, une seule apparence. Bref : ce ticket dessine **trois surfaces que Flutter ne dessine
pas** — l'icône posée sur l'écran d'accueil, l'écran de chargement en HTML avant que le moteur
existe, et une page d'aide joignable sans compte.

`DESIGN.md` gagne sur ce brief pour toute valeur de token. Les écarts constatés à
l'implémentation sont au § 7.

Sources : `tickets/in-progress/032-web-pwa-deploy.md` ; `tickets/backlog/037-canvaskit-autoheberge.md`
(compression des polices) ; `tickets/backlog/042-transition-de-route.md` (600 ms perdus avant la
première requête) ; `DESIGN.md § Brand World`, `§ Colors`, `§ Typography`, `§ Zones sûres et chrome
PWA`, `§ Motion` ; `design/004-design-system.md § Don't` (« pas de roue au milieu de l'écran ») ;
`design/006-invitations-onboarding.md` (l'écran d'installation du parcours d'accueil).

---

## 1. Ce qui est déjà là, et qu'on ne refait pas

| Surface | État au ticket 004/024 | Décision ici |
|---|---|---|
| `theme-color` du document | deux valeurs, claire et sombre, prises sur `surface-container-low` | **conservée telle quelle** |
| Préchargement des trois polices du premier écran | en place dans `index.html` | conservé, `crossorigin` conservé |
| `display: standalone`, `orientation: portrait-primary` | en place | conservés |
| `firebase-messaging-sw.js` | posé au 024 | non touché |
| Écran « Ajoute Astreinte SP à ton écran » du parcours d'accueil | `/bienvenue/installation` | **réemployé**, pas dupliqué |
| **Icônes** | les quatre PNG **par défaut de Flutter** (le logo bleu) | refaites — § 2 |
| `background_color` du manifeste | `#FFFFFF` | conservé, et il devient une **promesse** — § 3 |

## 2. L'icône — la case du registre, cochée

`DESIGN.md § Brand World` refuse le rouge pompier, le gyrophare et le casque, et pose que « la
preuve de la direction, en une image, c'est la case du registre ». L'icône est donc **exactement
cette image** : une case pleine, cochée, posée au-dessus de deux filets de réglure.

- Fond **encre** `#16212A` plein bord. Pas de dégradé, pas d'ombre portée : le système pose déjà
  son propre masque et sa propre ombre.
- La case en **papier** `#FFFFFF`, rayon 36/512, la coche en encre **détourée dans** le papier —
  16.34:1, le contraste le plus fort du système.
- Deux filets `#45535C` sous la case : la réglure. Ils ne portent aucune information, ils donnent
  le mot « registre ». À 48 px ils deviennent une texture, ce qui est le résultat voulu — la forme
  reconnaissable à cette taille est la case cochée, et elle seule.
- **Aucune couleur saturée.** Un vert dans l'icône dirait « disponible », et `§ Colors` réserve
  le vert à un état. Une icône n'est pas un état.
- Version **masquable** : la même marque repliée à 78 %, centrée, sur le même fond plein bord.
  Le masque du système (cercle, squircle, goutte) ne mange que le bord.
- **Favicon** : à 16 px les filets ne disent plus rien. Elle ne garde que la case cochée, coin
  arrondi 96/512 parce qu'aucun navigateur ne masque une favicon.

Source vectorielle versionnée dans `design/assets/` ; les PNG en sont dérivés, jamais dessinés à
la main.

## 3. L'écran de chargement HTML — la continuité, pas un logo qui clignote

**Le problème réel.** Entre l'ouverture de l'onglet et la première image de Flutter, il y a le
téléchargement de `main.dart.js`, celui de CanvasKit et l'amorçage du moteur. Sur la 4G rurale
visée par le brief, c'est plusieurs secondes de **page blanche** : rien ne dit que quelque chose
se passe, et une page blanche qui dure se referme.

**Ce qu'on refuse.** Un logo centré qui pulse, et une roue. `design/004 § Don't` interdit la roue
au milieu de l'écran, et le premier écran Flutter — `DemarrageScreen` — porte déjà un **squelette
à la forme du contenu attendu**. Poser un logo avant lui produirait deux scènes successives et un
saut visuel au moment du passage de relais.

**Ce qu'on fait.** L'écran HTML est **le même squelette**, dessiné en CSS : la ligne de titre et
les deux blocs réglés, aux mêmes largeurs, mêmes hauteurs, mêmes rayons et mêmes surfaces tonales
que `SkeletonLigne` et `SkeletonBloc`. Le haut de l'écran est donc **identique** avant et après le
relais — c'est là que l'œil est, et c'est là que rien ne doit bouger.

La marque vit **en pied de page**, hors de la zone que Flutter va redessiner : la petite case
cochée (SVG en ligne, la même que l'icône) et le nom écrit, puis la ligne d'attente. Ce pied
disparaît au relais, et c'est le seul élément qui change. Un en-tête qui se transformerait en barre
grise se verrait ; un pied qui s'efface, non.

| Élément | Valeur | Vient de |
|---|---|---|
| Fond | `#FFFFFF` clair / `#0F161B` sombre | `surface` |
| Barres du squelette | `#E9EDF0` / `#222C33` | `surface-container-high`, comme `SkeletonLigne` |
| Crête du balayage | `#F7F9FA` / `#141C22` | `surface-container-low`, comme le dégradé de `LoadingSkeleton` |
| Filet des blocs | `#C3CDD3` / `#3A454C`, 1 px | `outline-variant` |
| Nom du produit | `#131C23` / `#E2E8EC`, 15 px, graisse 600 | `on-surface` |
| Ligne d'attente | `#45535C` / `#B3C0C8`, 15 px | `on-surface-variant` |
| Marque du pied | encre `#16212A` / `#D8E2E8`, papier `#FFFFFF` / `#16212A`, 28 px | § 2 |
| Balayage du squelette | 1 400 ms, linéaire, en boucle | `AppDuration.balayage`, `AppCurve.balayage` |
| Disparition | 180 ms, `easeOutCubic`, opacité | token `courant` |

- **Police système assumée.** Le squelette HTML ne charge aucune police : Atkinson arrive avec le
  bundle. Le seul texte affiché est le nom du produit et une phrase d'attente, en `system-ui` ; un
  FOUT sur deux lignes de 15 px n'est pas le FOUT que `§ Typography` interdit sur une grille de
  62 cases. Charger la police pour l'écran de chargement retarderait l'écran de chargement.
- **Le thème suit le système** (`prefers-color-scheme`), parce qu'à ce moment-là l'application
  n'a pas encore lu la préférence de la personne. C'est la seule surface du produit dans ce cas.
- **`prefers-reduced-motion` coupe le balayage et le fondu.** `§ Motion` l'exige, et ici le
  respect est intégral : rien ne bouge, l'écran est simplement remplacé.
- **Le passage de relais se fait sur `flutter-first-frame`**, jamais sur une durée devinée.
- **L'écran sait échouer.** Si aucune première image n'arrive au bout de **20 secondes**, la ligne
  d'attente est remplacée par une phrase qui nomme le problème et la sortie — « Le chargement
  prend plus de temps que prévu. Vérifie ta connexion, puis recharge la page. » — et un bouton
  « Recharger ». Sans cela, un réseau qui se tait laisse un squelette qui balaie pour l'éternité,
  et c'est le pire des deux mondes : ça a l'air de marcher.

## 4. `/install` — la page d'aide, sans compte

**Le job.** Quelqu'un reçoit l'adresse par SMS, par affiche dans la salle de garde, par le chef de
centre au téléphone. Il n'a pas de compte, ou il en a un mais sur un autre téléphone. Il veut
**mettre l'icône sur son écran d'accueil**, et rien d'autre.

`/bienvenue/installation` ne peut pas servir : elle est derrière la session, elle appartient à un
parcours en quatre étapes et son bouton principal (« C'est fait ») fait avancer ce parcours. On
garde donc **les trois gestes** et on change tout le reste.

| | `/bienvenue/installation` (006) | `/install` (ce ticket) |
|---|---|---|
| Joignable | connecté, une fois | **toujours**, y compris sans configuration Supabase |
| Titre | « Ajoute Astreinte SP à ton écran » | le même |
| Bannière iOS | oui | oui |
| Après les gestes | « C'est fait » / « Plus tard » → étape suivante | **« Ouvrir Astreinte SP »** → `/` |
| Navigateur inconnu | ne dit rien (l'écran est sauté) | **dit quelque chose** — § 4.1 |

### 4.1 Le troisième cas

`ContextePlateforme` connaît Safari iOS et Chrome Android ; tout le reste est `autre`, et le
parcours d'accueil saute simplement l'écran. Une page qu'on ouvre **exprès** n'a pas ce droit :
elle doit rendre quelque chose à un ordinateur de bureau, à Firefox Android, à Samsung Internet.

Ce cas n'affiche pas trois gestes faux. Il affiche deux phrases : où chercher (« le menu de ton
navigateur, entrée “Installer” ou “Ajouter à l'écran d'accueil” ») et l'aveu (« selon le
navigateur, cette entrée n'existe pas — l'application marche aussi dans un onglet »). Nommer le
problème et la sortie, comme une erreur.

### 4.2 Structure

`EcranSimple`, colonne bornée à 420, exactement comme les autres écrans sans navigation. Les
gestes numérotés réemploient le composant du 006, **extrait** dans un fichier partagé plutôt que
copié. Le bouton final est un `PrimaryButton` primaire ; aucune seconde action — il n'y a rien à
remettre à plus tard sur une page qu'on a ouverte pour ça.

## 5. Le manifeste, en tant que design

Le manifeste n'est pas un fichier de configuration : c'est **la fiche produit affichée par le
système** au moment d'installer. Trois valeurs sont des décisions de design, pas des réglages.

- `background_color: #FFFFFF` est ce que le système peint **avant** que le document existe. Il
  doit être `surface` du thème clair, et l'écran de chargement HTML doit commencer par la même
  valeur — sinon l'installation produit un flash blanc puis un fond différent. C'est déjà le cas,
  et c'est ce qui rend la valeur intouchable.
- `theme_color: #F7F9FA` (`surface-container-low`) suit `§ Zones sûres et chrome PWA`. La variante
  sombre vit dans `index.html`, pas dans le manifeste, qui n'en accepte qu'une.
- `name` et `short_name` sont identiques et courts — « Astreinte SP » tient sous une icône
  d'écran d'accueil sans être coupé, ce qui est la seule contrainte réelle.

S'ajoutent `id`, `scope`, `lang: fr` et `dir: ltr` : sans `id`, deux déploiements de la même
application s'installent comme deux applications différentes.

## 6. Do's / Don'ts propres à ce ticket

**Do**

- Laisser l'écran HTML et le premier écran Flutter se ressembler au point qu'on ne voie pas la
  couture.
- Dire ce qui ne va pas quand le chargement traîne, et proposer le geste de sortie.
- Dériver les PNG d'une source vectorielle versionnée.

**Don't**

- Pas de roue, pas de logo qui pulse, pas de barre de progression mensongère (on ne connaît pas
  l'avancement du téléchargement).
- Pas de fondu d'entrée sur le squelette HTML : il doit être là à la première image du navigateur.
- Ne pas faire dépendre la disparition du squelette d'un `setTimeout`.
- Ne pas afficher trois gestes inventés à un navigateur qu'on ne connaît pas.

## 7. Écarts constatés à l'implémentation

| Point du brief | Écart | Raison |
|---|---|---|
| Balayage du squelette | Flutter promène **un** dégradé sur toute l'ossature (`ShaderMask`) ; le CSS en promène un **par barre**, en phase | Aligner un dégradé unique sur plusieurs éléments demande `background-attachment: fixed`, coûteux au rendu et inégal sur iOS — sur l'écran dont le seul métier est d'arriver vite. Les barres démarrent ensemble ; la crête traverse chacune sur sa propre largeur au lieu de la page. Visible si on cherche, invisible autrement. |
| `apple-mobile-web-app-status-bar-style` | `black` (valeur du gabarit Flutter) → `default` | Une barre d'état noire au-dessus d'un produit clair (`surface` = papier blanc, `background_color` = `#FFFFFF`) est une bande étrangère en haut de l'écran. Personne n'avait choisi `black` : c'est ce que `flutter create` écrit. **À vérifier sur un iPhone réel**, en clair et en sombre : c'est la seule surface de ce ticket qu'aucun test ne couvre. |
| `/install` | l'application est servie avec la **stratégie de hash** de `go_router` (`supabase/functions/README.md`, `APP_INVITE_PATH`) : l'adresse réelle est `/#/install` | Changer de stratégie d'URL toucherait les quatre liens profonds des notifications et deux secrets d'Edge Functions — hors de ce ticket. L'hébergeur fait le pont par une **redirection temporaire** `/install` → `/#/install` : l'adresse qu'on dicte au téléphone n'a pas de dièse, et la redirection disparaîtra d'elle-même le jour où `usePathUrlStrategy()` sera activé. |
