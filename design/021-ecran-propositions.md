# 021 — Écran des propositions pour le membre

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web**,
Material 3, une seule apparence. Ce brief est **le pendant exact** de `design/019-publication-suivi.md` :
le 019 a livré le geste qui fait vibrer trente téléphones, celui-ci livre ce qui se passe quand
un de ces trente téléphones vibre.

`DESIGN.md` gagne sur ce brief pour toute valeur de token. Les écarts demandés sont au § 8, les
écarts constatés à l'implémentation au § 10.

Sources : `docs/PRD.md § 5.4`, `§ 6.2`, `§ 7.1-7.2` ; `docs/SCHEMA.md § 2.8` à `§ 2.10`, `§ 4`
(liste blanche de colonnes), `§ 5` ; `docs/WORKFLOWS.md § 3`, `§ 4`, `§ 5`, `§ 8` ;
`design/019-publication-suivi.md` ; `lib/core/session/README.md` ;
`tickets/in-progress/021-ecran-propositions.md`.

---

## 1. Job et audience

**Le pompier volontaire, un mardi à 18 h 40, en marchant vers sa voiture.** Son téléphone a vibré
il y a deux heures : « 3 astreintes proposées en octobre ». Il a une main libre, trente secondes,
et il sait déjà s'il peut. Ce qu'il veut, c'est **dire oui et ranger son téléphone.**

Ce qu'il fait aujourd'hui, et que le produit remplace : il lit un SMS, il ouvre un tableur en
pièce jointe qu'il ne sait pas lire sur un écran de 6 pouces, il cherche son nom, et il répond
« ok pour le 12 » par SMS — que le chef recopiera à la main dans sa feuille de relance.

Une seule audience, un seul moment, une seule question : **« est-ce que je prends ce créneau ? »**
Posée trois ou quatre fois de suite, jamais quarante.

**Ce n'est pas l'écran de son planning.** Il ne vient pas ici consulter ses gardes — c'est le
ticket 027 — ni voir celles des autres — ticket 023. Il vient répondre, et repartir. Une
proposition répondue n'a plus rien à faire ici.

## 2. Résultat et preuve

**Résultat.** Répondre coûte **deux touches depuis la notification**, et c'est la promesse la plus
littérale du produit. Toucher la notification ouvre cet écran ; toucher « Accepter » clôt
l'affaire. Il n'y a pas de troisième écran, pas de confirmation, pas d'enregistrement à valider.

**Preuve, dans l'ordre :**

1. Notification → écran → « Accepter ». **Deux touches, chronométrables.** Toute étape ajoutée sur
   ce chemin est un défaut de revue, pas un compromis.
2. La liste est vide neuf jours sur dix, et l'écran vide **dit quoi faire à la place** au lieu de
   se taire.
3. Un créneau que le chef a repris pendant que le pompier lisait sa notification ne produit pas une
   erreur : il produit **une phrase qui explique**, et la ligne s'en va.
4. La réponse partie en base ne fait bouger **que** `status` et, au refus, `decline_reason`.
   Vérifiable colonne par colonne.
5. Quand sa réponse est la dernière que le planning attendait, le pompier l'apprend : le mois est
   validé, et c'est un peu grâce à lui.

**Ce que la base fait toute seule, et qu'il ne faut pas réimplémenter.** `responded_at` est posé
par `assignments_member_transition` (`docs/SCHEMA.md § 4`). La bascule `published → validated` est
posée par `schedule_auto_validate` (migration `0019`). La visibilité d'une attribution est décidée
par RLS : un planning en brouillon **ne renvoie rien**, et c'est le comportement voulu, pas un
chargement qui échoue.

## 3. La contrainte qui gouverne tout : la charge utile

Ce n'est pas un détail d'implémentation, c'est **la** règle d'architecture de cet écran, et elle
appartient au brief parce qu'elle décide de la forme du code.

`assignments_member_transition` compare `to_jsonb(new) - colonnes_libres` à `to_jsonb(old) -
colonnes_libres`, avec `colonnes_libres = {status, responded_at, decline_reason, updated_at}`.
Toute colonne différente en dehors de cette liste lève `forbidden` et **fait échouer l'`update`
entier** — pas seulement le champ fautif. Une sérialisation complète du modèle (`toJson()`) qui
renverrait `station_id`, `was_available` ou `proposed_at`, même inchangés, est une bombe à
retardement : elle passe tant que PostgREST renvoie les mêmes valeurs, et elle casse le jour où
une colonne se normalise différemment à l'aller et au retour.

**Conséquence de conception, non négociable :**

- Aucun objet du domaine de cet écran n'expose de `toJson()`. La charge utile est construite à la
  main, littéralement, dans le dépôt :
  `{'status': 'accepted'}` — deux caractères de plus seraient un bogue.
  `{'status': 'declined', 'decline_reason': motif}` quand le motif existe, sinon `{'status':
  'declined'}` seul.
- **`responded_at` ne part jamais.** La base le pose. L'envoyer serait dire l'heure du téléphone,
  qui peut avoir trois minutes de retard ou trois heures.
- Un test unitaire **inspecte la charge utile envoyée** et échoue si elle contient autre chose que
  ces deux clés. C'est le seul garde-fou qui survivra à un refactor distrait.

## 4. Périmètre et limites

**Livré :** la liste des propositions en attente, groupée par mois ; l'acceptation en une touche ;
le refus avec motif court facultatif ; la pastille chiffrée sur l'onglet ; l'ouverture depuis une
notification (`/proposals`) ; le cas de l'attribution disparue ; l'état vide ; les états de
chargement, d'erreur, hors ligne et caserne suspendue.

**Pas livré, et à ne pas esquisser :**

- **« Mes astreintes »** (ticket 027) : la liste des gardes acceptées, l'export ICS, l'historique.
  Cet écran ne montre **pas** ce qui a été accepté — une proposition répondue disparaît.
- Le planning de la caserne pour les membres (ticket 023).
- La réattribution côté administrateur (ticket 020). Cet écran doit **survivre** à une
  réattribution, il ne la provoque pas et ne la répare pas.
- Les relances automatiques (ticket 022). La ligne affiche « relancé hier » si la base le dit, mais
  rien ici ne déclenche de relance.
- Toute modification d'une réponse déjà donnée. La machine à états l'interdit
  (`docs/WORKFLOWS.md § 3` : `declined --> [*]`), et un bouton qui échouerait à tous les coups est
  pire que pas de bouton. Le pompier qui s'est trompé appelle son chef, qui réattribue.

**Anti-objectifs explicites :**

- **Pas de confirmation à l'acceptation.** C'est l'objet même du ticket. Un dialogue « Confirmer ? »
  transformerait deux touches en trois et coûterait la promesse.
- **Pas de tout accepter en un bouton.** Trois créneaux, ce sont trois décisions distinctes ; un
  bouton de lot ferait accepter le 24 décembre à qui ne visait que le 12 octobre.
- **Pas de glissement latéral pour répondre.** Le geste est invisible, il n'a pas d'équivalent au
  clavier, et il se déclenche tout seul dans une poche ou avec un gant. `DESIGN.md § Points de
  rupture` : aucun geste caché sans équivalent visible — ici, la version visible **est** la bonne
  version, la cachée n'apporte rien.
- **Pas de canal temps réel.** Justifié au § 7.3.
- **Pas de carte.** `DESIGN.md § Cards / Containers` : une liste de blocs identiques faits d'une
  icône, d'un titre et d'un texte est interdite comme structure de page. Cette liste est un
  registre : des lignes réglées.

## 5. États et plages de contenu

### 5.1 Plages réelles

| Grandeur | Minimum | Typique | Maximum retenu |
|---|---|---|---|
| Propositions en attente | **0** (le cas le plus fréquent) | 3 | 62 |
| Mois représentés dans la liste | 0 | 1 | 3 (M, M+1, M+2 se chevauchent en fin de mois) |
| Longueur du motif de refus | 0 | 18 caractères | **120**, coupés à la saisie |
| Délai entre la proposition et la réponse | 4 s | 6 h | 14 j |
| Relances déjà reçues sur une ligne | 0 | 0 | 2 |

Deux valeurs piègent. **Zéro est le cas nominal**, pas le cas dégradé : l'état vide est l'écran que
ce produit affichera le plus souvent, il mérite donc autant de soin que la liste pleine.
**Soixante-deux propositions sont légales** — un planning entier attribué à une seule personne dans
une toute petite caserne — donc la liste est virtualisée et les en-têtes de mois vivent *dans* le
défilement, jamais au-dessus.

### 5.2 Les états de l'écran

| État | Ce qu'on voit |
|---|---|
| **Chargement** | Squelette à la forme du contenu : un en-tête de mois, trois lignes. Jamais de roue centrée. |
| **Vide** | `EmptyState` `inbox_outlined`, « Aucune proposition en attente », texte « Quand ton chef de centre publiera le planning, tes astreintes proposées s'afficheront ici. », action **« Voir mon mois »** → onglet 0. |
| **Liste** | La composition du § 6. Un en-tête par mois, une ligne par créneau. |
| **Réponse en vol** | La ligne **part tout de suite** (§ 7.1). Aucun bouton en chargement, aucune ligne grisée. |
| **Acceptée** | `SnackBar` : « Samedi 12 octobre, nuit : acceptée. » La ligne n'est plus là, la pastille a baissé de un. |
| **Refusée** | `SnackBar` : « Samedi 12 octobre, nuit : refusée. Ton chef de centre est prévenu. » |
| **Dernière réponse d'un planning** | En plus : bannière `information` fermable « Planning d'octobre validé : tout le monde peut le voir maintenant. » C'est le seul endroit où l'écran parle du planning entier. |
| **Attribution disparue** | La ligne est déjà partie ; bannière `information` fermable « Ce créneau ne t'est plus proposé : ton chef de centre l'a repris ou confié à quelqu'un d'autre. » **Pas une erreur, pas de rouge.** |
| **Échec réseau** | La ligne **revient à sa place**, bannière `erreur` « Ta réponse n'est pas partie. » + action « Réessayer ». |
| **Hors ligne** | Bannière `horsLigne` permanente, les deux boutons de chaque ligne désactivés **avec leur raison** sous la première ligne visible : « Une réponse a besoin du réseau. » |
| **Caserne suspendue** | Bannière `lectureSeule`, boutons désactivés avec leur raison. |
| **Échec de lecture** | `EmptyState.erreur` + « Réessayer ». |
| **Pas de caserne / membre désactivé** | Le routeur a déjà tranché avant cet écran (`redirectionAuth`). Rien à prévoir ici. |

### 5.3 Ce que ces états ne font jamais

- **Aucun état ne remplace la liste par un message.** Une bannière se pose au-dessus, la liste
  reste. On ne retire pas sous les yeux du pompier les deux autres créneaux auxquels il n'a pas
  encore répondu parce que le troisième a échoué.
- Aucun bouton ne devient « en chargement ». Le retour est la disparition de la ligne, pas un
  indicateur qui tourne sous le pouce.
- Aucune ligne ne se déplace toute seule. Le tri est fixe (§ 6.1) et il ne se recalcule qu'à la
  relecture complète.
- Une proposition **refusée ou acceptée ne réapparaît jamais**, même après un rafraîchissement :
  elle n'est plus `proposed`.

## 6. Interaction et layout

### 6.1 La liste, et son ordre

**Un seul ordre, et il est celui du calendrier** : par date croissante, jour avant nuit. Pas de tri
par « le plus urgent », pas de tri par date de proposition. Le pompier cherche « le 12 » ; il doit
le trouver là où le 12 se trouve dans un mois.

Le groupement par mois est un `EnteteSection` (composant existant) : titre « Octobre 2026 » en
`titre-section`, compte en dessous (« 3 propositions »), filet de réglure, et la liste dessous. Les
en-têtes **défilent avec le contenu** — ils ne sont pas collants. À trois propositions typiques,
un en-tête collant volerait 44 dp de hauteur pour ne rien dire de plus que la ligne qu'il surplombe.

```
┌────────────────────────────────────────────┐
│ Octobre 2026                               │
│ 3 propositions                             │
├────────────────────────────────────────────┤
│  12  samedi 12 octobre        ◗ Nuit       │
│ sam. proposé il y a 2 h                    │
│                                            │
│ [ ✓ Accepter            ] [ ✕ Refuser   ]  │
├────────────────────────────────────────────┤
│  19  samedi 19 octobre        ☀ Jour       │
│ sam. proposé il y a 2 h · relancé hier     │
│ …                                          │
```

### 6.2 La ligne, signal par signal

Une ligne, trois zones, et **rien qui ne soit une information** :

1. **La marge du registre**, 44 dp de large : le numéro du jour en `nombre` (mono, chiffres
   tabulaires — deux dates alignées doivent l'être vraiment) et le jour de la semaine abrégé en
   `etiquette`. C'est la marge d'un registre de garde, la même que `DayCell` au ticket 011.
   Un jour de weekend prend le fond `surface-dim` sur cette marge seulement, comme dans la grille.
2. **Le corps** : la date en toutes lettres (« samedi 12 octobre ») en `corps`, puis un
   `StatusBadge.creneau` — l'icône `bedtime` ou `light_mode` et le mot « Nuit » ou « Jour », jamais
   une couleur. Sous elle, une `mention` en `on-surface-variant` : « proposé il y a 2 h », suivie
   de « · relancé hier » quand `reminder_count > 0`.
3. **Les deux actions**, sur leur propre rangée, pleine largeur de la ligne :
   - **« Accepter »**, `PrimaryButton` **primaire** (bloc d'encre), icône `task_alt` 20 dp — la même
     que le `StatusBadge` « Accepté », un glyphe pour un sens.
   - **« Refuser »**, `PrimaryButton` **secondaire**, icône `cancel` 20 dp — celle de « Refusé ».
   - Hauteur 52 dp chacun, écart 8 dp, **répartition 3/2 en faveur d'« Accepter »**. L'asymétrie
     est l'information : le produit sait quelle réponse il espère, et le pouce trouve la plus
     grande cible sans viser. À 360 dp de large, cela donne 192 et 128 dp — les deux au-dessus du
     plancher de 160 ? Non : le plancher de 160 dp de `DESIGN.md § Buttons` vaut pour un bouton
     **isolé**, pas pour deux boutons appairés qui partagent la largeur d'une ligne. Ce qui doit
     être tenu ici, c'est la cible tactile : 128 × 52 dp, très au-dessus des 48.

   **« Refuser » n'est pas `danger`.** Le vermillon veut dire « absent, refusé, cassé »
   (`DESIGN.md`) : il appartient à l'**état** qui en résultera, pas au bouton qui y mène. Un refus
   est une réponse légitime, pas une destruction. Le rouge n'apparaît qu'une fois, sur le bouton de
   confirmation de la feuille de refus, qui, lui, commet.

Le séparateur entre deux lignes est un `AppDivider` (`outline-variant`, 1 dp), pas une carte, pas
une ombre. Une ligne est haute d'environ 132 dp en compact ; la liste est construite par
`ListView.builder` sur une liste **aplatie** d'éléments (en-tête ou ligne) calculée une seule fois
par état, jamais reconstruite au défilement.

**Sémantique.** Chaque ligne est un conteneur annoncé d'une phrase complète — « Samedi 12 octobre,
nuit. Proposé il y a 2 heures. » — et chaque bouton nomme son créneau : `Semantics(label:
'Accepter samedi 12 octobre, nuit')`. Un lecteur d'écran qui annonce quatre fois « Accepter » sur
le même écran est un écran inutilisable.

### 6.3 L'asymétrie assumée : accepter coûte une touche, refuser en coûte deux

C'est la seule décision de ce brief qui mérite d'être défendue.

Accepter est **immédiat et sans confirmation**. Refuser ouvre une **feuille de bas d'écran** où le
motif s'écrit, et se confirme par un bouton. Trois raisons, dans l'ordre :

1. **Le produit promet deux touches sur la réponse attendue.** Le chef a proposé ce créneau parce
   que le pompier s'était déclaré disponible (`was_available = true` dans l'immense majorité des
   cas). « Oui » est la réponse que la donnée prédit ; c'est donc elle qui doit être gratuite.
2. **Un refus a un destinataire.** Il envoie un push à tous les administrateurs (« Thomas a refusé
   le 12 nuit », `docs/WORKFLOWS.md § 8`) et il ouvre un travail de réattribution. Un refus posé
   par erreur dans une poche fait sonner le téléphone du chef de centre à 23 h. Une touche de plus
   est le prix juste.
3. **Le motif n'existe nulle part ailleurs.** `docs/PRD.md § 5.4.2` le demande, et c'est
   l'information la plus utile de l'écran de suivi (`design/019 § 6`) : « en formation » et « je
   pars en vacances » n'appellent pas la même réattribution. Le proposer *après* le refus, dans un
   message passager, serait le perdre neuf fois sur dix.

**Ni l'un ni l'autre n'est réversible**, et l'écran ne fait semblant de rien : aucun bouton
« Annuler » dans le message de confirmation, parce que la machine à états n'a pas de retour
(`declined --> [*]`). Prétendre le contraire pendant huit secondes serait mentir.

### 6.4 La feuille de refus

Feuille de bas d'écran en compact, medium et expanded ; dialogue en large. Rayon `feuille` (12,
haut seulement), scrim 32 %, élévation 3 — les valeurs de `DESIGN.md § Elevation`.

```
│ Refuser samedi 12 octobre, nuit            │
│                                            │
│ Motif (facultatif)                         │
│ ┌────────────────────────────────────────┐ │
│ │ ex. en formation ce week-end           │ │
│ └────────────────────────────────────────┘ │
│ Ton chef de centre le verra en cherchant   │
│ quelqu'un d'autre.                         │
│                                            │
│ [ Garder le créneau ]  [ ✕ Refuser ]       │
```

- Titre : **le créneau**, pas « Êtes-vous sûr ? ». La feuille dit ce qu'elle va faire.
- Un `ChampTexte` d'une seule ligne, libellé **« Motif (facultatif) »** au-dessus (jamais un simple
  texte d'invite), 120 caractères maximum, clavier texte, `textCapitalization` de phrase. Le champ
  **ne prend pas le focus tout seul** : ouvrir un clavier logiciel sur un écran qu'on consulte en
  marchant pousse les deux boutons hors de vue. Le pompier qui veut écrire touche le champ.
- Sous le champ, une `mention` qui dit à quoi sert le motif. C'est ce qui fait qu'on l'écrit.
- Deux boutons : **« Garder le créneau »** (secondaire — il nomme l'action, pas « Annuler ») et
  **« Refuser »** (variante `danger`, icône `cancel`). C'est le seul rouge de tout le parcours.
- Pendant l'envoi : rien. La feuille se ferme dès la confirmation et la réponse part derrière
  (§ 7.1). Une feuille qui reste ouverte avec un bouton qui tourne coûte une seconde de plus à
  chaque refus.
- Retour matériel, geste retour iOS, `Échap` : ferment la feuille sans refuser. Le focus revient
  sur le bouton « Refuser » de la ligne.

### 6.5 La pastille

`AppDestination.pour(propositionsEnAttente:)` existe depuis le ticket 004 et **n'a jamais été
alimentée** : ce ticket la branche, il ne la réinvente pas. Le compte est le nombre de lignes
affichées, pas une seconde requête `count(*)` — deux sources pour un nombre, ce sont deux nombres
différents un jour sur dix.

- Plafonnée à « 9+ » visuellement, le nombre réel annoncé aux lecteurs d'écran
  (« 3 propositions en attente »), déjà en place dans `AppScaffold`.
- Le compte est **construit une fois pour toute la coquille** : `AccueilScreen` le lit et le passe
  aux destinations, que la barre du bas et le rail latéral partagent. `MoisScreen` les reçoit déjà
  telles quelles, donc la pastille est visible depuis « Mon mois » sans que « Mon mois » sache ce
  qu'est une proposition.
- Le contrôleur des propositions est donc **non auto-disposé** : la pastille vit sur tous les
  onglets, et un compte qui repart de zéro à chaque changement d'écran clignoterait. Même
  raisonnement, mêmes mots, que le centre de notifications au ticket 026.

### 6.6 L'arrivée depuis une notification

Le lien public est `/proposals` (`docs/WORKFLOWS.md § 8`), la traduction interne vit dans
`destinationInterne` (`features/notifications/domain/destination_push.dart`) depuis le ticket 024,
et elle rend déjà `/?onglet=1`. **Il n'y a rien à ajouter et surtout rien à dupliquer :** une
seconde liste blanche de destinations serait une seconde vérité qui divergerait à la première
refonte d'écran. Ce ticket se contente de mettre un écran derrière l'onglet 1 et d'écrire le test
qui va de la notification à la première ligne de la liste.

Le démarrage à froid est déjà couvert : `DestinationInitiale` garde la destination demandée
pendant la restauration de session (ticket 024). Un pompier qui touche la notification avec
l'application fermée atterrit ici, pas sur l'accueil.

### 6.7 Points de rupture

| Classe | Composition |
|---|---|
| **compact** (< 600) | Une colonne, marge 16. Les deux boutons sous le corps de la ligne. `RefreshIndicator` : le geste attendu sur un téléphone. |
| **medium** (600–839) | Colonne bornée à 720, centrée. Même ligne. |
| **expanded** (840–1199) | Colonne bornée à 720. Les deux boutons **remontent à droite du corps** de la ligne : la largeur existe, la ligne descend à 72 dp, et un pompier sur un portable voit six propositions au lieu de trois. |
| **large** (≥ 1200) | Identique à expanded. Pas de panneau de détail : une proposition n'a pas de détail, elle a deux réponses. |

Le rafraîchissement a **toujours** un équivalent visible au clavier : une action `refresh` dans la
barre d'application, à côté de la cloche. Le geste de tirage n'est jamais le seul chemin.

## 7. Décisions techniques qui sont des décisions de design

### 7.1 La réponse est optimiste, et c'est une décision d'usage

La ligne disparaît **avant** que la base ait répondu, et l'écriture part derrière.

Ce n'est pas une optimisation : c'est la scène d'usage. En 4G rurale, dans une remise, un aller-
retour serveur coûte 300 ms à 3 s. Un écran qui attend transforme « deux touches » en « deux touches
et une attente », et un pompier qui ne voit rien bouger appuie une seconde fois.

Le contrat, en trois lignes :

- **Succès** → la ligne reste partie, message passager, pastille à jour.
- **Refus de la base parce que la ligne n'est plus `proposed`** (annulée, remplacée, ou répondue
  depuis un autre appareil) → la ligne reste partie, **bannière `information`** qui explique.
  L'`update` porte `status = 'proposed'` dans son `where` : zéro ligne touchée est la réponse
  normale de ce cas, pas une exception, et aucun déclencheur ne se plaint.
- **Échec réseau ou refus de droit** → la ligne **revient à sa place exacte**, bannière `erreur`
  avec « Réessayer ». Rien n'est perdu.

### 7.2 Ce qui est lu, et rien de plus

Une seule requête, à l'ouverture et à chaque rafraîchissement : les attributions du membre dont le
statut est `proposed` et `proposed_at` n'est pas nul, jointes à leur créneau et au statut de leur
planning. Jamais `select *`.

- `proposed_at is null` est **le brouillon** (`docs/WORKFLOWS.md § 3`) : ces lignes existent, le
  membre ne les voit pas, et le filtre est explicite côté client en plus de la RLS. Deux ceintures
  sur une donnée qui, affichée par erreur, ferait répondre un pompier à un planning que le chef est
  en train d'écrire.
- Un planning en `draft` ne renvoie rien du tout : la RLS de `shifts` et d'`assignments` s'en
  charge (`docs/SCHEMA.md § 4`). L'écran affiche alors son état vide, ce qui est **exact** — il n'y
  a rien à répondre.
- Le tri se fait en Dart. Soixante-deux lignes au pire ; ordonner par une colonne de table jointe
  côté PostgREST ajouterait une syntaxe fragile pour économiser une comparaison.

### 7.3 Pas de temps réel ici, et pourquoi

Le suivi du 019 écoute `assignments` et `schedules` : un administrateur reste sur son écran une
demi-heure pendant que trente réponses arrivent, et le mouvement des chiffres **est** son travail.

Le pompier, lui, reste quarante secondes. Ouvrir un canal WebSocket par pompier — trente par
caserne — pour peut-être diffuser un événement qu'il ne verra pas coûterait une connexion permanente
sur un téléphone en 4G, et n'apporterait rien : **le moment de vérité est la touche**, et à cet
instant l'`update` conditionnel dit la vérité de toute façon (§ 7.1).

Ce qui remplace le temps réel, et qui suffit :

- rafraîchissement au retour de l'application au premier plan (le cas exact du pompier qui revient
  de sa notification) ;
- rafraîchissement par geste de tirage et par l'action de la barre d'application ;
- la vérité à la touche, toujours.

### 7.4 La validation du planning se constate, elle ne se déclenche pas

`schedule_auto_validate` bascule le planning dans **la transaction de la dernière acceptation**.
L'écran n'a rien à appeler. Mais il peut le constater sans coûter cher : quand l'acceptation qui
vient de réussir était **la dernière proposition de ce planning pour ce pompier**, l'écran relit une
ligne — le statut du planning — et, s'il est `validated`, affiche la bannière. Une requête d'une
colonne, au plus une fois par mois et par pompier, pour le seul moment du mois où le produit peut
dire « c'est bouclé ».

Si le planning n'est pas validé (d'autres pompiers doivent encore répondre), il ne se passe
**rien** : pas de bannière « en attente des autres », qui ne serait qu'une façon de designer
l'absence de nouvelle.

## 8. Écarts demandés à `DESIGN.md`

| Point | Ce que dit `DESIGN.md` | Ce que demande ce brief | Pourquoi |
|---|---|---|---|
| Largeur minimale d'un bouton hors compact | « largeur intrinsèque ≥ 160 dp » | 128 dp pour « Refuser » quand les deux boutons partagent la largeur d'une ligne | Le plancher de 160 vise un bouton isolé dans une page. Deux boutons appairés se partagent une ligne ; ce qui doit tenir est la cible tactile (48), largement dépassée. |
| Confirmation d'une action irréversible | non traité explicitement | **« Accepter » ne confirme pas**, « Refuser » confirme | L'asymétrie est le ticket lui-même (§ 6.3). Confirmer les deux coûterait la promesse des deux touches ; ne confirmer aucun ferait sonner le chef de centre à 23 h. |
| `EnteteSection` | conçu pour des sections de page | employé comme en-tête de groupe **dans** une liste virtualisée | Même composant, même rythme (24 au-dessus, 8 en dessous), zéro variante à maintenir. |

Aucun token nouveau. Aucune couleur nouvelle. Aucun composant nouveau hors de la feuille de refus,
qui est une composition de `ChampTexte` et de `PrimaryButton` existants.

## 9. Critères d'acceptation, traduits en observables

1. Deux touches depuis la notification à la réponse envoyée : `/proposals` → liste → « Accepter ».
2. La ligne acceptée disparaît, la pastille passe de 3 à 2, et l'écran ne recharge pas la liste.
3. Un refus sans motif envoie `{status: 'declined'}` ; avec motif, `{status: 'declined',
   decline_reason: '…'}`. Rien d'autre, jamais.
4. Une attribution annulée entre-temps produit une phrase et pas une erreur ; la ligne ne revient
   pas.
5. La liste est groupée par mois, triée par date, jour avant nuit.
6. L'état vide explique et propose une action.
7. `flutter analyze` vierge, `flutter test` vert, `flutter build web` qui passe.

## 10. Écarts constatés à l'implémentation

> Rempli par `flutter-dev` après le code. Ce qui est ici est **la** référence, pas ce qui précède.

| Point | Ce que disait ce brief | Ce que fait le code | Pourquoi |
|---|---|---|---|
| Rangée d'actions en `expanded` | « les deux boutons remontent à droite du corps » | livré comme décrit, avec un plancher : en dessous de 320 dp de largeur restante pour le corps, la rangée retombe sous le corps | Deux boutons de 52 dp à droite d'un corps comprimé produisaient un retour à la ligne au milieu de « samedi 12 octobre » dès que l'échelle de texte dépassait ×1.3. |
| Bannière de validation du planning | une bannière `information` fermable | idem, **plus** le libellé du mois pris du planning relu, pas de la ligne répondue | Une réponse donnée le 31 octobre sur un créneau de novembre nommait le mauvais mois. |
| Rafraîchissement au retour au premier plan | annoncé au § 7.3 | livré dans l'écran via `WidgetsBindingObserver`, et **seulement quand l'onglet des propositions est monté** | Rafraîchir depuis le contrôleur aurait relu la liste au retour de n'importe quel écran, y compris la matrice admin, pour une pastille qui n'avait pas bougé. |
