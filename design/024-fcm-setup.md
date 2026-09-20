# 024 — Push web (PWA) — brief de design

Mode Impeccable : **Operate**. Monde visuel : le registre de garde (`DESIGN.md`).
Périmètre : **le web seul**. Les notifications natives sont le ticket 036.

Ce ticket est surtout de la plomberie. Il n'a que **quatre moments visibles**, et un cinquième
qui compte autant : celui où les notifications sont **impossibles** et où il faut le dire sans
mentir ni alarmer.

## 0. Le fait qui décide de tout

Sur iPhone, **une page ouverte dans Safari ne reçoit aucune notification.** Il faut que
l'application soit sur l'écran d'accueil. Ce n'est pas un confort, c'est la condition. L'aide à
l'installation du ticket 006 le dit déjà (`installAvertissementIos`) ; ce ticket en tire la
conséquence : **on ne demande jamais une permission qu'on sait perdue.** Un refus est définitif
dans le navigateur — le redemander demande d'aller dans les réglages du système. Une demande faite
au mauvais moment coûte donc toutes les propositions d'astreinte de ce pompier.

D'où la règle de ce brief : **la demande de permission arrive en dernier, après le profil, le
guide et l'aide à l'installation, et seulement quand elle a une chance d'aboutir.**

## 1. Moment 1 — l'écran « Reçois les propositions » (fin de l'accueil)

Quatrième et dernière étape du parcours d'accueil (`/bienvenue/notifications`), après
`profil → guide → installation`. Jamais au premier lancement de l'app : à ce moment-là,
personne ne sait encore ce qu'est une proposition d'astreinte.

`EcranSimple`, même ossature que les trois écrans qui précèdent. Trois états de contenu, un seul
écran :

**a. On peut demander** (Chrome Android, Chrome/Firefox bureau, iOS **installé**)

```
Reçois les propositions
──────────────────────────────────────────────
Quand un chef te propose une astreinte, ton
téléphone te prévient. Sans ça, il faut ouvrir
l'application pour le savoir.

Ce que tu recevras :
  ▸ Une astreinte t'est proposée
  ▸ Le planning de ton mois est validé
  ▸ Un rappel avant la date limite de saisie

Le navigateur va te demander l'autorisation.

              [ Activer les notifications ]
                      Plus tard
```

La phrase « Le navigateur va te demander l'autorisation » est **obligatoire** : la fenêtre du
navigateur est brutale et arrive sans prévenir. On l'annonce une ligne avant qu'elle s'ouvre.
« Plus tard » est un vrai bouton texte, pas un lien gris : un accueil se saute
(ui-ux-pro-max § Onboarding / User Freedom).

La liste des trois événements n'est pas de la décoration : elle est la seule réponse à
« qu'est-ce que je vais recevoir ? », la question qui décide du oui ou du non. Trois puces, pas
plus, avec les mots du métier, jamais les noms techniques de `docs/WORKFLOWS.md § 8`.

**b. iPhone, application non installée** — bannière `attention` (`schedule`), pas d'erreur :

> « Sur iPhone, les notifications n'arrivent que si l'application est sur ton écran d'accueil. »

Le bouton principal devient **« Comment l'installer »** et renvoie à l'écran d'installation. Il
n'y a **aucun** bouton qui demanderait la permission : la demander ici la brûlerait.

**c. Le navigateur ne sait pas faire** (Firefox iOS, navigation privée, pas de configuration
Firebase) — bannière `information`, une phrase, et le seul bouton est « Continuer ». On ne
promet rien qu'on ne tiendra pas.

## 2. Moment 2 — la bannière au premier plan

L'application est ouverte, un push arrive. Le système **n'affiche rien** (c'est la règle du web) :
c'est à nous de le montrer.

Un bandeau `AppBanner` variante `information` (`info_outline`, bleu de réglure), **en haut de
l'écran, au-dessus de tout, quel que soit l'écran ouvert** — donc posé dans la racine de l'app,
pas dans chaque écran. Titre de la notification en une ligne, corps en une ligne, tronqués à deux
lignes au total, jamais plus.

- Action à droite : **« Voir »** — nomme la destination quand elle est connue (« Voir la
  proposition »). Elle navigue vers le lien profond et referme la bannière.
- Bouton `close` de 48 dp à l'extrême droite : la bannière est fermable, parce qu'elle décrit un
  **événement**, pas un état persistant (`DESIGN.md § AppBanner`).
- Elle disparaît d'elle-même au bout de **8 secondes**. C'est plus que les 3–5 s d'un toast
  standard : la scène d'usage est un téléphone posé, regardé avec un temps de retard, souvent avec
  des gants. Rien ne se perd si elle s'efface : le centre de notifications (ticket 026) garde tout.
- Une seule à la fois. Un second push remplace le premier sans animation d'empilement.
- Pas de son, pas de vibration, pas de mouvement autre que l'apparition (`courant`, 180 ms) :
  l'application est déjà sous les yeux.

## 3. Moment 3 — le réglage dans le profil

Dans l'onglet « Profil », sous le bloc d'identité, un **bloc réglé** (filet 1 dp, rayon 8, pas de
carte ombrée), avec **une ligne d'état d'abord, un interrupteur ensuite** :

```
Notifications
──────────────────────────────────────────────
✓ Activées sur cet appareil

Rappels et infos                        [ ●—]
Rappels de saisie, planning validé,
changement de créneau.

Les propositions d'astreinte arrivent
toujours. Elles ne se coupent pas.
```

- La **ligne d'état** est le fait, porté par icône + libellé + couleur en quatrième :
  `notifications_active` / « Activées sur cet appareil », `notifications_off` / « Refusées dans ton
  navigateur » (+ la sortie : « Rouvre l'autorisation dans les réglages du navigateur »),
  `install_mobile` / « Ajoute l'application à ton écran d'accueil pour les recevoir »,
  `notifications_paused` / « Pas encore activées » + bouton « Activer les notifications ».
- L'**interrupteur** ne coupe que les notifications non critiques (`profiles.push_enabled`).
  Il est désactivé, avec sa raison écrite à côté, tant que la permission n'est pas accordée
  (`DESIGN.md § Buttons` : un contrôle désactivé affiche sa raison).
- La dernière phrase est **non négociable** (`docs/PRD.md § 6.5`) : les propositions d'astreinte ne
  sont jamais désactivables, et le produit le dit au lieu de le cacher. Elle est écrite en
  `corps-secondaire`, sous l'interrupteur, pas en info-bulle.
- Aucune formulation ne laisse croire que couper l'interrupteur coupe tout.

## 4. Moment 4 — l'ouverture depuis une notification

Invisible quand ça marche, désastreux quand ça rate. Rien à dessiner : on touche la notification,
l'application s'ouvre **sur la destination**, jamais sur l'accueil. Les quatre destinations sont
celles de `docs/WORKFLOWS.md § 8`.

Une seule règle visible : si le lien mène à un écran auquel ce compte n'a pas droit (un lien admin
reçu puis rétrogradé), on atterrit sur l'accueil **sans message d'erreur**. Un pompier n'a rien
fait de mal ; lui dire « accès refusé » serait l'accuser.

## 5. Ce que ce ticket ne fait pas

- Aucune pastille de compteur sur « Propositions » : c'est le ticket 021.
- Aucun centre de notifications : c'est le ticket 026.
- Aucun écran de profil complet : c'est le ticket 007. Le réglage se pose dans l'onglet existant
  et déménagera tel quel.
- Aucune demande de permission déclenchée par un écran métier, jamais, sous aucun prétexte.

## 6. Le cas « pas de clés »

Aucun projet Firebase n'existe encore. **L'application doit s'ouvrir et fonctionner exactement
comme aujourd'hui**, sans clés : l'étape d'accueil est sautée, le réglage du profil affiche
« Notifications indisponibles sur cette installation », aucun réseau n'est appelé, rien ne plante.
C'est le canal principal du produit : il ne se casse pas faute de configuration.
