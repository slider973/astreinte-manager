# 072 — Un pompier dans plusieurs casernes

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web**,
Material 3, une seule apparence. Ce ticket n'ouvre **aucun écran nouveau** : il ajoute un sélecteur
hors du Profil, un bandeau de bascule, une carte d'invitation sur l'accueil, un filtre et une
passerelle dans la Boîte, et une marque « astreinte ailleurs » chez l'admin. Tout ce qu'il ne
redit pas est tranché dans `DESIGN.md`, `design/007`, `design/016`, `design/017`, `design/018`,
`design/026`, `design/051` et `design/064`.

Sources : ticket `tickets/in-progress/072-plusieurs-casernes.md` (constats et décisions du
propriétaire du 28 septembre 2026) ; `docs/PRD.md § 6.1` (« Un sélecteur de caserne apparaît dans
ce cas ») ; `docs/SCHEMA.md § 2.12` (`notifications.station_id`) ; code lu :
`profil/presentation/widgets/bloc_caserne.dart`, `auth/presentation/aucune_caserne_screen.dart`,
`invitation/domain/invitation_providers.dart`, `notifications/domain/centre_providers.dart`,
`notifications/presentation/couche_notifications.dart`, `accueil/presentation/accueil_screen.dart`,
`accueil/presentation/widgets/entete_accueil.dart`, `core/widgets/app_scaffold.dart`,
`core/widgets/entete_travail.dart`, `core/widgets/app_banner.dart`, `core/widgets/case_attribution.dart`.

Pas d'entretien possible depuis cet agent : les deux décisions du propriétaire sont binding, le
reste est tranché ici et les **hypothèses sont marquées « Hypothèse »**. Les points qui méritent un
regard du propriétaire sont regroupés au § 9.

---

## 1. Job et audience

**Le pompier à deux casernes.** Rare, réel : un regroupement de centres, un volontaire qui tient
des gardes dans le centre de son village et dans celui de son travail. Il ouvre l'application
quelques secondes entre deux activités, souvent dehors, parfois avec des gants. Ce qu'il doit
savoir sans réfléchir : **dans quelle caserne il est en ce moment**, et comment passer à l'autre
sans fouiller le Profil. Ce qu'il ne doit jamais vivre : répondre à une proposition de la caserne
Sud en croyant être dans la caserne Nord, ou saisir son mois dans la mauvaise.

**Le membre d'une caserne invité dans une seconde.** Aujourd'hui il ne l'apprend que par courriel
(`aucune_caserne_screen.dart` n'est vu que par qui n'a aucune caserne). Il doit la voir dans
l'application, là où il passe tous les jours.

**Le chef de centre.** Sur ordinateur, dans la matrice. Il doit comprendre pourquoi la proposition
automatique n'a pas désigné un pompier disponible — sans rien apprendre de l'autre caserne que le
fait que ce créneau-là est déjà pris.

## 2. Résultat et preuve

1. Sur l'accueil, la caserne ouverte se lit **en toutes lettres** sous la salutation ; en changer
   coûte **deux touches** (le sélecteur, puis la caserne).
2. Un push ou un lien de la caserne Sud ouvre la caserne Sud **et le dit** dans un bandeau qui
   nomme les deux casernes et propose de revenir.
3. Après la bascule, **aucune donnée de l'ancienne caserne n'est peinte**, pas même une image :
   squelette, puis les données de la nouvelle.
4. Une invitation en attente apparaît sur l'accueil d'un membre déjà rattaché, avec un geste.
5. La Boîte ne montre que la caserne ouverte, et dit combien de non-lues attendent dans l'autre.
6. L'admin voit « Astreinte ailleurs » sur la case et dans le panneau des candidats, jamais le nom
   de l'autre caserne, ni l'heure, ni l'état de cette autre astreinte.

## 3. Direction retenue

Le monde visuel ne bouge pas : registre de garde chez l'admin, papier doux et `CarteDouce` chez le
pompier, `AppBanner` comme composant signature. **Aucun token nouveau, aucune paire de couleurs
nouvelle.** La thèse de ce ticket tient en une phrase : **la caserne ouverte est un fait de
contexte, donc elle s'écrit là où se lit le contexte** — l'en-tête — et elle ne se change que par
un contrôle visible, jamais par un geste caché.

### 3.1 Où vit le sélecteur — tranché : l'en-tête, pas la navigation

| Option | Verdict | Pourquoi |
|---|---|---|
| Une destination de navigation | **Refusée** | `DESIGN.md § Navigation` : cinq destinations au maximum, et un admin en a déjà cinq. Une caserne n'est pas un endroit où l'on va, c'est le cadre de tous les endroits. |
| Un sélecteur dans la barre de navigation (au-dessus, en tiroir) | **Refusée** | Le tiroir n'existe pas en `compact` ; une rangée au-dessus de la `NavigationBar` coûterait 48 points à chaque écran, Calendrier compris, dont la grille a été mesurée ligne à ligne au 064d. |
| **L'en-tête de l'accueil (`compact`, `medium`) et l'en-tête de travail (`expanded`, `large`)** | **Retenue** | L'accueil est l'écran qu'on ouvre en lançant l'application et celui où arrive toute bascule : c'est là que la question « où suis-je ? » se pose. Sur grand écran, `EnTeteTravail` **titre déjà chaque destination du nom de la caserne** (`AppScaffold`, paramètre `caserne`) : le rendre actionnable ne coûte aucun point. |

Conséquence assumée : sur téléphone, depuis le Calendrier, les Astreintes ou la Boîte, changer de
caserne passe par l'accueil (une touche de plus). C'est le prix de ne pas retirer une ligne de
grille à tous les pompiers pour un cas rare. **Le sélecteur n'existe qu'à partir de deux
appartenances actives**, comme au Profil (`design/007 § 5.2`) : pour la très grande majorité, rien
ne change à l'écran.

Le sélecteur du Profil **reste** : c'est l'endroit où on le cherchera en dernier recours, et son
contenu est extrait pour être partagé (§ 8).

### 3.2 Centre de notifications — tranché : filtré, avec une passerelle

| Option | Verdict | Pourquoi |
|---|---|---|
| Étiqueté (toutes les casernes mêlées, nom en tête de ligne) | **Refusée** | C'est une vue consolidée, hors périmètre du ticket. Et une ligne Sud touchée depuis la Boîte Nord ferait basculer l'application au milieu d'une liste — le pire moment pour changer de cadre. Elle mêlerait aussi deux pastilles en une : « 3 non lues » ne dirait plus où agir. |
| **Filtré par la caserne ouverte**, plus une ligne-passerelle par autre caserne qui a des non-lues | **Retenue** | La Boîte reste un journal d'**un** cadre, cohérent avec l'accueil et les propositions qu'elle porte. La passerelle empêche l'oubli : on sait qu'il se passe quelque chose ailleurs, et on y va d'une touche, consciemment. |

Les notifications sans `station_id` (rattachées au compte, pas à une caserne) s'affichent **quelle
que soit la caserne ouverte**.

## 4. Périmètre et limites

**Dans le ticket (côté PWA, ce brief) :**

- Sélecteur de caserne dans l'en-tête (§ 6.1), feuille et menu de choix (§ 6.2).
- Bandeau « caserne ouverte » après une bascule **automatique** (push, lien, accès désactivé) (§ 6.3).
- Bascule après acceptation d'une invitation (§ 6.4).
- Carte d'invitation en attente sur l'accueil et dans le Profil (§ 6.5).
- Boîte filtrée, pastilles par caserne, passerelle (§ 6.6).
- Admin : « Astreinte ailleurs » dans la matrice, le panneau des candidats et le récapitulatif de
  la proposition automatique (§ 6.7).

**Hors périmètre :** vue consolidée de plusieurs casernes ; compte des propositions en attente par
caserne (demanderait une lecture nouvelle) ; nom, heure ou état de l'astreinte de l'autre caserne
chez l'admin ; blocage de l'attribution manuelle d'un pompier pris ailleurs (la décision 1 ne
vise que le planning automatique) ; tout écran iOS (`foco/` suit le même contrat et les mêmes
textes, dans son dépôt).

**Anti-objectifs :** un sélecteur en menu déroulant natif ; une bascule silencieuse ; un toast qui
s'efface avant d'être lu ; de la couleur pour distinguer les casernes (pas de « caserne bleue,
caserne verte » : une teinte de ce système dit un état).

## 5. États et plages de contenu

### 5.1 Plages réelles

| Donnée | Minimum | Typique | Maximum à tenir |
|---|---|---|---|
| Appartenances actives | 1 (rien ne change) | 2 | 4 (feuille sans défilement à 390 × 844) |
| Nom de caserne | « CS Ury » (6) | « CS Maurepas » (11) | « Centre de secours de Saint-Rémy-lès-Chevreuse » (47) : une ligne, ellipse, nom entier en sémantique et dans la feuille sur deux lignes |
| Invitations en attente | 0 | 1 | 3 (une carte chacune) |
| Non-lues dans les autres casernes | 0 | 1–3 | « 9+ », comme la pastille de la Boîte |
| Cases « astreinte ailleurs » dans une matrice | 0 | 0–10 | 62 pour un même membre (tout son mois pris ailleurs) |

### 5.2 Les états

| État | Ce que voit le pompier |
|---|---|
| **Une seule caserne** | Exactement l'écran d'aujourd'hui. Ni sélecteur, ni passerelle, ni bandeau. |
| **Plusieurs casernes, au repos** | Le sélecteur sous la salutation (ou le titre actionnable en grand écran). |
| **Bascule en cours** (choix manuel ou automatique) | Le sélecteur affiche **déjà** le nom de la nouvelle caserne (il vient des appartenances, en mémoire). Le contenu de chaque destination montre **son squelette**, jamais les lignes de l'ancienne caserne, jusqu'à la première réponse de la nouvelle. La pastille de la Boîte disparaît pendant ce temps plutôt que de garder l'ancien compte. |
| **Bascule réussie, manuelle** | Pas de bandeau : la personne vient de le faire. Une annonce de lecteur d'écran seulement (« Caserne Sud ouverte »). |
| **Bascule réussie, automatique** | Bandeau (§ 6.3). |
| **Bascule, hors ligne ou lecture en échec** | Les états d'erreur existants de chaque section (« Réessayer »), **dans la nouvelle caserne**. Jamais de repli sur les données d'une autre caserne. Un cache local n'est relu que s'il est rangé sous la nouvelle caserne. |
| **Push d'une caserne où l'accès n'est plus actif** | L'application reste dans la caserne ouverte, va à l'accueil, et le bandeau d'information dit pourquoi (§ 7, `bandeauLienCaserneInactive`). |
| **Accès désactivé dans la caserne ouverte, une autre reste active** | Bascule automatique vers l'autre, bandeau « accès désactivé » (§ 7). Si aucune ne reste : l'écran « Aucune caserne » existant. |
| **Invitation en attente** | Carte sur l'accueil (§ 6.5). Expirée : **rien sur l'accueil** (aucun geste possible), ligne au Profil. Lecture en échec ou hors ligne : **rien sur l'accueil** — l'invitation est une source secondaire et ne doit pas mettre un tableau de bord en erreur ; le Profil dit l'échec. |
| **Mois verrouillé, caserne suspendue** | Inchangés, mais propres à la caserne ouverte : basculer peut faire apparaître ou disparaître la bannière de lecture seule. C'est voulu. |

**Ce que ces états ne font jamais :** peindre une ligne, un compte ou un nom de l'ancienne caserne
sous le nom de la nouvelle (le constat iOS `AppStore.swift:259-263` est le défaut à ne pas
reproduire) ; annoncer une bascule qui n'a pas eu lieu ; confondre « accès désactivé » et « erreur ».

## 6. Interaction et layout

### 6.1 Le sélecteur dans l'en-tête — `BoutonCaserne`

**`compact` et `medium` — sur l'accueil seulement**, dans `EnteteAccueil`, **sous** la rangée
avatar / salutation / cloche, aligné sur le bord gauche de la salutation (pas de l'avatar), 8 points
au-dessus, 16 points avant la première section.

```
390 pt
┌──────────────────────────────────────────┐
│ (A)  Bonsoir,                       (🔔) │  rangée existante
│      Marie                               │
│      [⌂ CS Maurepas            ⌄ · 2]    │  BoutonCaserne, 48 de haut
│                                          │
│  Invitation ─ carte (§ 6.5) si besoin    │
│  Mes astreintes …                        │
```

- **Forme** : bouton texte à rayon `controle` 8, **filet 1 dp `outline-variant`** (le papier doux
  ne détache rien à 1,06:1), fond `surface`, hauteur **48**, largeur intrinsèque bornée à la
  colonne. Icône d'en-tête `local_fire_department_outlined` 20 dp (celle du `BlocCaserne`, par
  cohérence), nom en `libelle-action` 16/600 encre `on-surface`, puis `expand_more` 20 dp.
- **Pastille des non-lues ailleurs** : si au moins une autre caserne a des notifications non lues,
  une pastille indigo (`badgeTheme`, comme la Boîte) avec le **chiffre** après le chevron. Le
  chiffre porte l'information, la couleur ne fait que la signaler ; la sémantique la dit en mots.
- **Ellipse** sur une ligne ; le nom entier est dans la sémantique et dans la feuille.
- **×1,6** : le bouton grandit en hauteur (il ne borne pas sa hauteur), le nom reste sur une ligne.
- **Pressé** : surimpression 8 % d'encre ; **focus** : anneau 2 dp `primary` + 2 dp de décalage.
- **Sémantique** : `button: true`, libellé « Caserne ouverte : CS Maurepas. Changer de caserne. »
  plus, s'il y a lieu, « 2 notifications non lues dans tes autres casernes. »

**`expanded` et `large` — sur toutes les destinations**, c'est le **titre d'`EnTeteTravail`** qui
devient le bouton quand il y a plusieurs casernes : même nom en `titre-section` 22, suivi de
`expand_more` 24 dp et de la pastille éventuelle, cible de 48 de haut sur toute la largeur du
texte. Une seule caserne : le titre reste un titre, inerte. L'accueil en grand écran ne double pas
le sélecteur sous sa salutation (même règle que l'avatar et la cloche, `design/064a`).

```
1280 pt
┌ navigation 180 ┬───────────────────────────────────────────────────────┐
│ Accueil        │ CS Maurepas ⌄ ·2                      [🔔] [A]         │ EnTeteTravail
│ Calendrier     ├───────────────────────────────────────────────────────┤
│ Astreintes     │ ┌ menu ancré sous le titre, 320 de large ┐            │
│ Boîte          │ │ ● CS Maurepas          ✓ Ouverte        │            │
│ Admin          │ │   Admin                                  │            │
│                │ │ ○ CS Ury                                 │            │
│                │ │   Membre · 2 non lues                    │            │
│                │ │ ─────────────────────────────────────── │            │
│                │ │ Invitation : CS Élancourt   Voir         │            │
│                │ └──────────────────────────────────────────┘            │
```

### 6.2 Le choix — feuille en `compact`/`medium`, menu ancré au-delà

Même contenu, deux contenants, extrait du `_Selecteur` du Profil (§ 8) :

- **`compact` / `medium`** : feuille de bas d'écran (`showModalBottomSheet`, rayon `feuille` en
  haut, poignée, geste retour, zone sûre basse). Titre « Changer de caserne » en `titre-bloc`.
- **`expanded` / `large`** : menu ancré sous le titre (`MenuAnchor`, élévation 2, rayon `feuille`),
  320 de large, fermé par `Échap`, clic extérieur ou nouvelle touche sur le titre.
- **Une ligne par caserne active**, 64 de haut minimum : radio à gauche (la sélection est portée
  par le **radio rempli + l'icône `check` + le mot « Ouverte »** à droite, la teinte indigo en
  quatrième), nom en `corps` 16 (600 pour l'ouverte) sur deux lignes au plus, seconde ligne en
  `corps-secondaire` : le rôle, puis « · 2 non lues » s'il y a lieu.
- **Toucher une ligne bascule tout de suite et ferme** : pas de bouton « Valider ». Deux touches,
  promesse du produit. Toucher la caserne déjà ouverte ferme sans rien faire.
- **Section « Invitations en attente »**, sous un filet, si `invitationsRecuesProvider` en rend une
  non expirée : « Invitation : {caserne} » et un bouton « Voir » 48 → `/rejoindre/:id`. Ordre de
  la liste : celui des appartenances (alphabétique), **pas** l'ordre d'usage — une liste qui se
  réordonne sous le pouce trompe.
- **Où l'on atterrit après un choix manuel** : la même destination si elle existe dans la nouvelle
  caserne pour ce rôle (Calendrier → Calendrier de Sud), sinon l'accueil (admin à Nord, membre à
  Sud, depuis `/admin`). Un écran poussé (détail) revient à la racine de sa destination. Jamais un
  identifiant de l'ancienne caserne dans l'adresse.

### 6.3 Le bandeau « caserne ouverte » après bascule automatique

**Quand** : seulement quand l'application a changé de caserne **sans** que la personne l'ait
demandé ici : notification touchée (arrière-plan ou bandeau de push au premier plan), lien ouvert
qui porte une autre caserne, accès désactivé dans la caserne ouverte. Pas après un choix manuel.
Pas après une invitation (la page « Bienvenue » le dit déjà, § 6.4).

**Forme** : le bandeau des messages de `CoucheNotifications` — même place (en haut, sous la zone
sûre, au-dessus de toutes les routes, pleine largeur), même composant `AppBanner` variante
`information`, **icône `swap_horiz`** (l'événement est un changement de cadre, pas une
information neutre ; la dérogation d'icône est celle que `AppBanner.icone` prévoit), filet haut et
bas. Il **remplace** un bandeau de push affiché, il ne s'empile pas : une seule bannière à la fois.

```
┌──────────────────────────────────────────────────┐
│ ⇄  CS Ury est ouverte.                  [Fermer] │
│    La notification venait de cette caserne.      │
│    Tu étais dans CS Maurepas.   [Revenir à CS M…]│
└──────────────────────────────────────────────────┘
```

- **Texte** : nom de la caserne ouverte en premier (c'est le fait), raison et ancienne caserne en
  `detail` (deux lignes au plus, ellipse sur le nom).
- **Action « Revenir à {ancienne} »** : rebascule vers l'ancienne caserne **et** l'accueil (la
  destination ouverte par la notification n'a pas d'équivalent garanti là-bas), sans nouveau
  bandeau. Absente dans le cas « accès désactivé » (on ne revient pas là où l'on n'a plus accès).
- **Fermer** : `close` 48 dp, nommé « Fermer le bandeau ».
- **Durée : 8 secondes**, `CoucheNotifications.duree`, la durée déjà retenue pour un téléphone posé
  et regardé avec retard. **Elle ne s'efface pas toute seule quand un lecteur d'écran ou la
  navigation au clavier est actif** (`MediaQuery.accessibleNavigation`) : elle attend « Fermer ».
  Rien ne se perd si elle s'efface : le nom reste écrit dans le sélecteur.
- **Accessibilité** : `liveRegion: true` (annonce polie), phrase annoncée = texte + détail, sans le
  libellé des boutons. Le focus n'est **pas** déplacé dans le bandeau (la personne arrive sur la
  destination qu'elle a demandée). Contraste : `etat-info-sur-fond` sur `etat-info-fond`, paire
  existante.
- **Mouvement** : apparition `courant` 180 ms en opacité, rien sous Reduce Motion.
- **Pendant le bandeau** : le contenu dessous est déjà celui de la nouvelle caserne (ou son
  squelette). Le bandeau ne masque jamais un bouton de réponse plus de 8 s : sur téléphone il
  recouvre la barre d'application, pas le contenu.

**Bandeau de push au premier plan venu d'une autre caserne** : avant toute bascule, le bandeau du
message (ticket 024) préfixe son titre du nom de la caserne : « CS Ury · Nouvelle astreinte
proposée ». Son bouton « Voir » déclenche la bascule puis le bandeau ci-dessus. Pour un message
de la caserne ouverte, rien ne change.

### 6.4 Après l'acceptation d'une invitation

La caserne rejointe **devient la caserne ouverte** au moment où les appartenances sont relues
(`AcceptationController._relireLesAppartenances` suivi de `choisir(stationId)`). La page
« Bienvenue » existante dit déjà « Tu fais maintenant partie de CS Ury. » : **pas de bandeau en
plus**. Pour un compte qui a déjà une caserne, la suite ne repasse pas par le profil d'accueil ni
le guide déjà vus (Hypothèse : ces repères sont par compte ; si l'un d'eux est par caserne, il
s'affiche une fois, comme pour un nouveau membre). Le bouton de la page mène à l'accueil de la
caserne rejointe.

Hypothèse : l'identifiant de la caserne rejointe se lit dans la réponse d'`accept_invitation`
(`membership.station_id`) ; `CaserneInvitation` ne garde aujourd'hui que le nom. À défaut, la
relecture des appartenances suffit à la retrouver par différence. Pas de colonne nouvelle.

### 6.5 Invitations en attente pour un membre déjà rattaché

**Accueil** — une `CarteDouce` par invitation non expirée, **en tête du contenu**, avant « Mes
astreintes » (c'est la seule chose de l'écran qui demande une décision qu'aucun autre écran
n'offre) :

```
┌──────────────────────────────────────────┐
│ [✉]  CS Ury t'invite                      │  titre-bloc 18
│      Par Jean Martin · jusqu'au 18 oct.  │  corps-secondaire
│                      [ Voir l'invitation ]│  PrimaryButton secondaire, 48
└──────────────────────────────────────────┘
```

- Carré de tête 40 × 40, rayon 12, icône `mark_email_unread_outlined` en `on-primary-container`
  sur `primary-container` — même grammaire que `CarreCreneau`, décoratif (`ExcludeSemantics`).
- « Par {inviteur} » omis si l'inviteur est inconnu (règle de `design/051`), jamais remplacé par une
  adresse. Échéance en date courte.
- « Voir l'invitation » ouvre `/rejoindre/:id`, l'écran existant qui porte l'acceptation et ses six
  fins de parcours. **On n'accepte pas sur la carte** : même raison qu'au ticket 051.
- Pas de bouton « Ignorer » : rien dans le schéma ne le permet (une invitation expire seule).
- Lecture : à l'ouverture de l'accueil et au retour au premier plan, comme les autres données du
  tableau de bord (`FraicheurEcran`). Rien n'est écrit sur l'appareil (règle de
  `invitationsRecuesProvider`).
- Hypothèse : `my_pending_invitations()` répond aussi pour un compte déjà membre d'une caserne (la
  fonction filtre par adresse de session). À vérifier par `supabase-dev`.

**Profil** — dans `BlocCaserne`, sous le sélecteur (ou sous le rôle s'il n'y a qu'une caserne) :
une ligne par invitation, « Invitation : CS Ury · jusqu'au 18 octobre » et « Voir » 48. Expirée :
« Invitation expirée : CS Ury. Demande à ton chef de centre de la renvoyer. », sans bouton. Échec
de lecture : « Impossible de vérifier tes invitations. » et « Réessayer ».

### 6.6 La Boîte, filtrée

- **Filtre** : `station_id` = caserne ouverte, **ou** `station_id` nul. Les trois onglets (« Tout »,
  « Propositions », « Rappels ») appliquent le même filtre. Hypothèse : la lecture du centre rend
  déjà toutes les notifications du compte (`lister(userId:)`) ; le filtre se fait sur la liste, et
  les comptes par caserne en sortent sans requête nouvelle. `station_id` s'ajoute au modèle
  `NotificationInterne` (colonne existante).
- **Pastilles** : la cloche, la pastille de la barre et le titre « Boîte · N non lues » comptent
  **la caserne ouverte** (plus les lignes sans caserne). Les non-lues des autres casernes vont à la
  pastille de `BoutonCaserne` et aux lignes de la feuille.
- **Passerelle** : en tête de la liste, au-dessus de la première ligne, une `CarteDouce` par autre
  caserne qui a au moins une non-lue :

  ```
  ┌──────────────────────────────────────────┐
  │ [⇄]  CS Ury · 2 non lues      [ Ouvrir ] │
  └──────────────────────────────────────────┘
  ```

  56 de haut minimum, icône `swap_horiz` décorative, bouton secondaire « Ouvrir » 48. Toucher
  « Ouvrir » bascule (choix **manuel**, donc pas de bandeau) et reste sur la Boîte, même onglet.
  Elle n'apparaît pas sur l'onglet « Propositions » (elle ne parle que de non-lues, qui sont des
  rappels) ni quand le compte est à zéro.
- **« Tout marquer comme lu »** ne marque que ce qui est à l'écran : la caserne ouverte et les
  lignes sans caserne. Jamais l'autre caserne en silence.
- **Toucher une ligne** : elle est forcément de la caserne ouverte (ou sans caserne) ; aucune
  bascule ne peut partir de la liste.

### 6.7 L'admin : « Astreinte ailleurs »

**Source** (Hypothèse, nom à fixer par `supabase-dev`) : une fonction `security definer` qui, pour
la caserne et le mois de la matrice, rend l'ensemble des triplets (membre, date, créneau) où le
membre est **proposé ou accepté** dans une autre caserne sur un créneau qui chevauche. **Un
booléen par triplet, rien d'autre** : ni caserne, ni heure, ni état. L'écran ne peut donc rien
afficher de plus, par construction. Lu avec la matrice, relu avec elle.

**La marque, en matrice** — sur la case de disponibilité **et** sur le bloc d'attribution
(`SlotChip` dense ou compacte, `CaseAttribution`) :

- un **coin rabattu** : triangle plein dans l'angle haut droit, 8 px en densité dense (case de
  28), 12 dp en compacte (40), encre `on-surface` (`dark-on-surface` en sombre), séparé du fond par
  un liseré `surface` de 1 px pour rester lisible sur l'indigo plein et sur l'orange. **Forme, pas
  teinte** : le coin se voit en niveaux de gris sur les trois états de disponibilité et les trois
  états d'attribution ; il ne touche pas le glyphe central, qui reste le premier signal de l'état.
- **Pas de hachures** (réservées à « absent » et « verrouillé »), pas de rose (ce n'est ni un refus
  ni une erreur), pas d'orange (ce n'est pas une attente de la caserne ouverte).
- **Légende** de la barre de commande : une entrée de plus, « Astreinte ailleurs », avec un
  échantillon de case à coin rabattu. Elle n'apparaît que si le mois en contient au moins une.
- **Sémantique** de la case : la phrase existante + « , astreinte dans une autre caserne sur ce
  créneau ». Exemple : « Marie Lefebvre, samedi 4 octobre, nuit, disponible, astreinte dans une
  autre caserne sur ce créneau ».
- Info-bulle au survol permise **en plus** (« Astreinte dans une autre caserne sur ce créneau »),
  jamais seule : la légende, la sémantique et le panneau portent la même phrase.
- La ligne « Disponibles » de l'en-tête **ne change pas** : elle compte des déclarations, pas des
  candidats. Le panneau explique l'écart.

**Le panneau des candidats** (`design/017 § 6.3`, latéral en `large`, feuille ailleurs) :

- Un pompier disponible mais pris ailleurs reste dans « Disponibles », **en fin de section**, après
  tous les autres disponibles (même logique que le quota négatif : le dernier qu'on dérange, et la
  machine ne le choisira pas).
- Sa ligne : nom et quotas en `on-surface-variant`, puis une ligne `event_busy` 16 dp + « Astreinte
  ailleurs sur ce créneau » en `corps-secondaire` encre `on-surface-variant` (gris : c'est un fait
  sur lequel la caserne n'a pas la main, pas une alerte).
- Bouton **« Attribuer quand même »**, **sans dialogue** : comme le quota, l'information est sur la
  ligne avant le geste, et le pompier pourra refuser la proposition. Le dialogue reste réservé à
  l'absence déclarée. Si le pompier est à la fois absent et pris ailleurs, il reste dans « Non
  disponibles » avec les deux mentions, et c'est le dialogue d'absence qui s'applique.

**La proposition automatique** (`design/018 § 5.2`) :

- La prédiction Dart lit le même ensemble et **exclut** ces triplets, comme la base : le
  récapitulatif annonce ce qui sera vraiment appliqué.
- La phrase de garantie de la feuille gagne une clause (texte § 7).
- Un créneau laissé à découvert parce que ses seuls disponibles sont pris ailleurs est compté dans
  « créneaux à découvert » et listé comme les autres. **Pas de sous-compte par raison** : il dirait
  combien de membres de cette caserne ont une autre caserne, et le panneau l'explique déjà créneau
  par créneau.
- Après application, si la base a écarté des lignes parce que la personne a été prise ailleurs
  entre la lecture et l'écriture, la phrase de résultat les compte avec « déjà pris entre-temps »
  (§ 7). Hypothèse : `apply_auto_proposal` rend ce compte avec les autres écarts ; s'il ne distingue
  pas la raison, la phrase existante suffit.

### 6.8 Téléphone, tablette, grand écran

| | 390 × 844 (`compact`) | 768 (`medium`) | 1280 (`large`) |
|---|---|---|---|
| Sélecteur | `BoutonCaserne` sous la salutation de l'accueil | idem | titre d'`EnTeteTravail` actionnable, toutes destinations |
| Choix | feuille de bas d'écran | feuille | menu ancré, 320 |
| Bandeau de bascule | haut, sous la zone sûre, pleine largeur | idem | idem, au-dessus de la colonne de navigation et du contenu |
| Invitation | carte en tête de l'accueil | idem | idem, dans la colonne de contenu |
| Passerelle de la Boîte | carte en tête de liste | idem | en tête de la liste, pas dans le volet de réponse |
| « Astreinte ailleurs » | panneau en feuille (vue par jour), coin 12 dp en compacte | idem | coin 8 px en dense, panneau latéral 360 |

Zones sûres : la feuille réserve `viewPadding.bottom` ; le bandeau est sous `SafeArea(top)`. Le
geste retour iOS ferme la feuille ; le bouton précédent du navigateur après une bascule revient à
l'écran précédent **dans la caserne ouverte** (la caserne n'est pas dans l'historique).

## 7. Textes

Tous dans `AppStrings`, tutoiement. Glyphes : apostrophe droite, `·` et `–` seulement, déjà vérifiés par
`glyphes_couverts_test.dart` — pas de flèche, pas d'apostrophe typographique. `{caserne}` = nom tel que stocké.

### 7.1 Sélecteur

| Clé proposée | Texte |
|---|---|
| `caserneSelecteurSemantique(caserne)` | « Caserne ouverte : {caserne}. Changer de caserne. » |
| `caserneSelecteurNonLuesAilleurs(n)` | « {n} notification non lue dans tes autres casernes. » / « {n} notifications non lues dans tes autres casernes. » |
| `caserneChoixTitre` | « Changer de caserne » |
| `caserneChoixOuverte` | « Ouverte » |
| `caserneChoixLigne(role, n)` | « {rôle} » / « {rôle} · 1 non lue » / « {rôle} · {n} non lues » |
| `caserneChoixInvitationsTitre` | « Invitations en attente » |
| `caserneChoixInvitation(caserne)` | « Invitation : {caserne} » |
| `caserneChoixInvitationAction` | « Voir » |
| `caserneOuverteAnnonce(caserne)` | « {caserne} ouverte. » (annonce lecteur d'écran, choix manuel) |
| `caserneChoixFermer` | « Fermer » |

### 7.2 Bandeau de bascule

| Clé proposée | Texte |
|---|---|
| `bandeauCaserneOuverte(caserne)` | « {caserne} est ouverte. » |
| `bandeauRaisonNotification(ancienne)` | « La notification venait de cette caserne. Tu étais dans {ancienne}. » |
| `bandeauRaisonLien(ancienne)` | « Le lien venait de cette caserne. Tu étais dans {ancienne}. » |
| `bandeauRaisonDesactivee(ancienne)` | « Ton accès à {ancienne} a été désactivé. » |
| `bandeauRevenir(ancienne)` | « Revenir à {ancienne} » |
| `bandeauFermer` | « Fermer le bandeau » |
| `bandeauLienCaserneInactive` | « Cette notification concerne une caserne où ton accès n'est plus actif. » |
| `pushTitreAutreCaserne(caserne, titre)` | « {caserne} · {titre} » |

### 7.3 Invitations

| Clé proposée | Texte |
|---|---|
| `accueilInvitationTitre(caserne)` | « {caserne} t'invite » |
| `accueilInvitationDetail(inviteur, date)` | « Par {inviteur} · jusqu'au {date} » |
| `accueilInvitationDetailSansInviteur(date)` | « Jusqu'au {date} » |
| `accueilInvitationAction` | « Voir l'invitation » |
| `accueilInvitationSemantique(caserne, date)` | « Invitation de {caserne}, valable jusqu'au {date}. » |
| `profilInvitationLigne(caserne, date)` | « Invitation : {caserne} · jusqu'au {date} » |
| `profilInvitationExpiree(caserne)` | « Invitation expirée : {caserne}. Demande à ton chef de centre de la renvoyer. » |
| `profilInvitationsEchec` | « Impossible de vérifier tes invitations. » (+ `actionReessayer` existant) |

### 7.4 Boîte

| Clé proposée | Texte |
|---|---|
| `boitePasserelle(caserne, n)` | « {caserne} · 1 non lue » / « {caserne} · {n} non lues » |
| `boitePasserelleAction` | « Ouvrir » |
| `boitePasserelleSemantique(caserne, n)` | « {n} non lues dans {caserne}. Ouvrir cette caserne. » (singulier : « 1 non lue ») |

### 7.5 Admin

| Clé proposée | Texte |
|---|---|
| `matriceLegendeAilleurs` | « Astreinte ailleurs » |
| `matriceCaseAilleursSemantique` | « astreinte dans une autre caserne sur ce créneau » (ajouté à la phrase de la case, précédé d'une virgule) |
| `matriceCaseAilleursInfobulle` | « Astreinte dans une autre caserne sur ce créneau » |
| `candidatAilleurs` | « Astreinte ailleurs sur ce créneau » |
| `propositionAutoGarantie` | « Les créneaux que tu as remplis toi-même ne sont pas touchés. Personne ne dépasse le nombre d'astreintes qu'il a accepté, et personne n'est proposé sur un créneau où il a déjà une astreinte dans une autre caserne. » (remplace la phrase du 018) |
| `propositionAutoResultatEcartes(remplis, ecartes)` | « {remplis} créneaux remplis, {ecartes} déjà pris entre-temps. » (existant au 018, inchangé : il couvre aussi l'astreinte ailleurs survenue entre-temps) |

« Astreinte ailleurs » est choisi pour rester neutre en genre (« pris·e » est évité) et pour ne
rien dire de l'autre caserne.

## 8. Widgets Flutter

### 8.1 Réemployés tels quels

`AppBanner` (variante `information`, paramètre `icone`), `CarteDouce`, `PrimaryButton` (variante
secondaire), `EnteteSection`, `LoadingSkeleton`, `EmptyState`, `SlotChip`, `CaseAttribution`,
`LegendeEtats`, `BlocRegle`, le `badgeTheme` indigo, `CoucheNotifications` (sa place et sa durée).

### 8.2 À extraire ou créer

| Widget | Où | Rôle |
|---|---|---|
| `ListeCasernes` | `lib/core/widgets/liste_casernes.dart` | Le contenu du `_Selecteur` du Profil, extrait : `RadioGroup`, lignes de 64, « Ouverte » + `check`, rôle et non-lues, section d'invitations. Utilisé par le Profil, la feuille et le menu. Une seule écriture. |
| `BoutonCaserne` | `lib/core/widgets/bouton_caserne.dart` | Le déclencheur, en deux formes : `BoutonCaserne.puce` (accueil, 48, filet) et `BoutonCaserne.titre` (dans `EnTeteTravail`). Ouvre la feuille ou le menu selon la classe de fenêtre. Ne se construit pas s'il n'y a qu'une caserne. |
| `EnTeteTravail` | existant, étendu | Accepte un `titreActionnable` (le `BoutonCaserne.titre`) à la place du `Text`. |
| `BandeauBascule` | `lib/features/notifications/presentation/` ou `core/session/` | Le bandeau du § 6.3, porté par la même couche que le bandeau de push (une seule bannière à la fois, timer, `accessibleNavigation`). |
| `CarteInvitation` | `lib/features/invitation/presentation/widgets/` | La carte de l'accueil (§ 6.5). |
| `CartePasserelle` | `lib/features/boite/presentation/widgets/` | La ligne « {caserne} · N non lues · Ouvrir ». |
| `CoinAilleurs` | `lib/core/widgets/` (avec `SlotChip`) | Le coin rabattu, peint par un `CustomPainter`, posé par `SlotChip` et `CaseAttribution` via un booléen `ailleurs`. Sa taille suit la densité. |

**Caches** : aucun cache nouveau n'est demandé par ce brief. Si le développeur range sur l'appareil
une marque liée à la bascule (dernière caserne, bandeau vu…), elle passe par
`lib/core/session/deconnexion.dart` (règle des caches locaux), et les caches d'une caserne où
l'accès a été désactivé sont effacés (`oubli_local.dart`, constat du ticket).

### 8.3 Tests attendus (forme, en plus de ceux du ticket)

- Une caserne : ni `BoutonCaserne`, ni passerelle, ni entrée de légende.
- Deux casernes : le bouton à 390 et le titre actionnable à 1280 ; feuille vs menu.
- Bascule : aucun texte de l'ancienne caserne dans l'arbre entre le choix et la première réponse.
- Bandeau : texte exact, 8 s puis absent ; reste affiché avec `accessibleNavigation` ; « Revenir ».
- Nom de 47 caractères à ×1,6 et à 390 : pas de débordement (vraies polices,
  `test/support/polices.dart`).
- Coin rabattu lisible en niveaux de gris sur les six états (test de contraste ou de peinture).

## 9. Contraintes et décisions ouvertes

### 9.1 Tranché dans ce brief (à valider par le propriétaire)

1. **Sélecteur dans l'en-tête de l'accueil** sur téléphone et tablette, **titre actionnable** sur
   grand écran ; pas de destination de navigation. Sur téléphone, changer de caserne depuis le
   Calendrier coûte une touche de plus (passer par l'accueil).
2. **Boîte filtrée** par caserne ouverte, plus une passerelle « {caserne} · N non lues » ; pas de
   liste étiquetée.
3. **Bandeau de 8 s**, maintenu tant qu'un lecteur d'écran est actif, avec « Revenir à
   {ancienne} ».
4. **« Attribuer quand même » sans dialogue** pour un pompier pris ailleurs (comme le quota).
5. **La ligne « Disponibles »** de la matrice continue de compter les déclarations, pas les
   candidats.
6. **Pas de sous-compte** « à découvert parce que pris ailleurs » dans le récapitulatif.
7. Libellé **« Astreinte ailleurs »** plutôt que « pris ailleurs » (neutre en genre).

### 9.2 Hypothèses à vérifier par `supabase-dev` / `flutter-dev`

- `my_pending_invitations()` répond pour un compte déjà membre.
- L'identifiant de la caserne rejointe est lisible dans la réponse d'`accept_invitation`.
- La lecture du centre rend toutes les notifications du compte, toutes casernes.
- La fonction « pris ailleurs » rend des booléens par (membre, date, créneau) pour un mois.
- `apply_auto_proposal` rend un compte d'écarts qui inclut les écarts « pris ailleurs ».
- Les repères « profil d'accueil vu » et « guide vu » sont par compte.

### 9.3 Ce qu'un développeur ne doit pas inventer

Un nom, une heure ou un état de l'autre caserne côté admin ; une couleur par caserne ; un
sélecteur dans la barre de navigation ; un compte de propositions par caserne ; une bascule depuis
une ligne de la Boîte ; un dialogue de confirmation de bascule.

## 10. Checklists

### 10.1 Craft floor (Impeccable)

| Point | État |
|---|---|
| **Contraste** | Aucune paire nouvelle : `on-surface` sur `surface` (bouton), `etat-info-sur-fond` sur `etat-info-fond` (bandeau), `on-primary-container` sur `primary-container` (carré d'invitation), badge indigo, `on-surface-variant` sur `surface` (mention de candidat). Le coin rabattu est un élément graphique (≥ 3:1) : encre `#131C23` sur `#7655FA` ≈ 3,9:1, sur `#CEE5E1` et `#FDEAD7` > 12:1 ; liseré `surface` pour le séparer. ✓ (à mesurer dans `contraste_test.dart` pour la paire encre / indigo plein) |
| **Profondeur** | Seuls le menu (niveau 2) et la feuille (niveau 3) flottent, aux ombres existantes. Bouton, cartes, passerelle : filet, pas d'ombre. ✓ |
| **Espacement** | Échelle de 4 : 8 au-dessus du bouton, 16 après, cartes à 8 d'écart, lignes de 64 et 56. ✓ |
| **Typographie** | Aucune taille nouvelle ; Archivo pour `titre-section`/`titre-bloc`, Atkinson au-dessous, chiffres de pastille et dates en Mono tabulaire. Nom de 47 caractères vérifié à ×1,6. ✓ |
| **Motion** | Un seul mouvement : l'apparition du bandeau, `courant` 180 ms, nul sous Reduce Motion. Le tampon reste réservé à l'acceptation. ✓ |
| **États** | Une / plusieurs casernes, bascule en cours, réussie manuelle / automatique, hors ligne, échec, accès désactivé, lien inactif, invitation en attente / expirée / en échec, Boîte avec et sans passerelle, matrice avec et sans marque : § 5.2. ✓ |
| **Surfaces du navigateur** | Anneau de focus thématisé sur le bouton et le titre actionnable ; `Échap` ferme le menu ; curseur `click` sur le titre actionnable seulement. ✓ |
| **Copie** | Chaque contrôle nomme son action (« Voir l'invitation », « Revenir à CS Maurepas », « Ouvrir »). Le bandeau dit le fait puis la raison. Tutoiement. ✓ |
| **Couverture** | Les points du ticket côté PWA ont leur § : sélecteur hors Profil (6.1–6.2), bascule sur push/lien avec bandeau (6.3), après invitation (6.4), invitations visibles (6.5), centre filtré (6.6), « pris ailleurs » admin et proposition automatique (6.7), aucune donnée de l'ancienne caserne (5.2). ✓ |
| **Refus** | Pas de carte comme structure de page (une carte d'invitation conditionnelle, une passerelle conditionnelle), pas de surtitre, pas de glyphe Unicode, pas d'emoji, pas de modale de confirmation de bascule. ✓ |

### 10.2 Checklist application mobile (ui-ux-pro-max)

Requêtes faites : `--stack flutter` (« multi tenant workspace switcher header account », « bottom
sheet radio selection list » : **aucune correspondance** en base ; « navigation state » : go_router
et Riverpod, déjà la pile du projet), `--domain ux` (« context switch notification deep link toast
announce » : URL qui reflète l'état, toast 3–5 s ; « live region screen reader announcement
banner »), `--domain web` (« touch target accessibility dynamic type »). Écart assumé à la règle
« toast 3–5 s » : 8 s et maintien sous lecteur d'écran, pour le contexte d'usage (téléphone posé,
gants), décision déjà prise au ticket 024.

**Qualité visuelle** — pas d'emoji ✓ · une seule famille d'icônes, Material (`swap_horiz`,
`expand_more`, `event_busy`, `mark_email_unread_outlined`, `local_fire_department_outlined`) ✓ ·
tokens sémantiques uniquement ✓.

**Interaction** — cibles de 48 partout où un doigt agit (bouton, lignes de 64, « Voir », « Ouvrir »,
« Fermer », « Revenir ») ✓ · écart de 8 entre cibles ✓ · aucun survol ni clic droit comme seul
accès (l'info-bulle de la case est doublée par la légende, la sémantique et le panneau) ✓ · la
case dense de 28 n'est jamais servie au doigt ✓ · geste retour iOS et bouton précédent intacts ;
la caserne n'est pas dans l'historique, la destination l'est ✓.

**Clair / sombre** — coin rabattu en `dark-on-surface` et liseré `dark-surface` ; bandeau et badge
en paires sombres existantes ⚠︎ *(à vérifier à l'implémentation sur les six états de case)*.

**Mise en page** — zones sûres : feuille (`viewPadding.bottom`), bandeau (`SafeArea` haut) ✓ ·
vérifier à **390** et **1280**, plus 768 pour la feuille en `medium` ⚠︎ *(à l'implémentation)* · le
bouton ne pousse pas la grille du Calendrier (il n'existe que sur l'accueil) ✓.

**Accessibilité** — la caserne ouverte est portée par le texte, le radio, `check` et « Ouverte »,
jamais par la teinte seule ✓ · « astreinte ailleurs » par la forme (coin), la légende, la phrase
de sémantique et la mention du panneau ✓ · bandeau en `liveRegion`, sans vol de focus, sans
effacement sous lecteur d'écran ✓ · tailles dynamiques jusqu'à ×1,6 sans débordement ⚠︎ *(test
de peinture avec les vraies polices)* · Reduce Motion respecté ✓.
