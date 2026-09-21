# 047 — Importer les membres d'une caserne depuis un fichier

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web
mobile-first**, Material 3, une seule apparence sur toutes les cibles. `DESIGN.md` gagne sur ce
brief pour toute valeur de token. `design/006-invitations-onboarding.md` décrit l'écran auquel
celui-ci s'ajoute, et `design/009-gestion-membres.md` ce qui l'a complété depuis.

**Ce ticket ajoute une porte à un écran livré, il ne le réécrit pas.** « Membres » a deux listes,
un formulaire d'invitation et une feuille d'actions. On lui ajoute une seconde façon d'entrer dans
le formulaire : un fichier.

---

## 1. Job et audience

**Le chef de centre, assis, la première fois.** Il vient d'ouvrir sa caserne. Il a devant lui, dans
un tableur, la liste de ses cinquante-huit pompiers : prénom, nom, adresse, parfois une colonne qui
dit qui l'aide à administrer. Il n'a aucune envie de la retaper, et il ne le fera pas : il collera
vingt adresses, se trompera, et abandonnera au deuxième lot. Ce qu'il veut tient en une phrase :
**donner son fichier et savoir ce qui s'est passé pour chaque ligne.**

Il ne revient pas ici. L'import est un geste de premier jour, joué une fois, éventuellement deux
quand une promotion de recrues arrive en septembre. C'est un écran qu'on utilise dans un état de
concentration rare pour ce produit — au bureau, sur un ordinateur, avec le tableur ouvert à côté —
et c'est le seul du MVP dont on peut supposer qu'il ne sera pas utilisé avec des gants.

**Ce qui se joue.** Trois choses, par ordre de gravité :

1. **Quelqu'un manque et personne ne le sait.** Soixante invitations parties, cinquante-huit
   reçues : les deux oubliés n'apparaissent jamais dans la matrice, et le chef de centre découvre
   le trou en novembre, un samedi soir, en cherchant qui est d'astreinte. C'est le risque que ce
   ticket existe pour supprimer.
2. **Les accents.** Un fichier produit par un tableur français est presque toujours en
   Windows-1252. Lu en UTF-8, « Lefèbvre » devient « Lef?bvre » ou fait échouer la lecture. Un
   import qui écrit les noms de travers est pire qu'un import qui n'écrit pas de noms : il faut
   ensuite les corriger un par un.
3. **Un envoi qui part trop vite.** Le plafond du ticket 038 est de soixante courriels par heure et
   par caserne. Une caserne de soixante personnes est exactement à la limite. Un import qui
   s'arrête au cinquante-neuvième sans le dire produit le risque n° 1.

## 2. Résultat et preuve

**Résultat.** Un chef de centre dépose le fichier qu'il a déjà, voit ligne par ligne ce qui va se
passer, confirme, et repart avec un compte rendu qui nomme chaque personne. Personne n'est perdu en
route, et quand tout ne peut pas partir tout de suite, l'écran l'a dit **avant** de commencer.

**Preuves, vérifiables.**

- Un fichier séparé par des virgules et un fichier séparé par des points-virgules donnent le même
  aperçu. Un fichier en Windows-1252 et le même en UTF-8 donnent les mêmes noms, accents compris.
- Les colonnes sont reconnues par leur intitulé, dans n'importe quel ordre, et sous les variantes
  françaises courantes.
- Rien ne part avant la confirmation : l'aperçu est une lecture, pas un envoi.
- Chaque ligne du fichier a un verdict dans l'aperçu, puis un verdict dans le rapport, et le
  vocabulaire du rapport est **celui du ticket 006**, sans mot nouveau.
- Quand le budget horaire ne suffit pas, l'aperçu annonce combien partent maintenant et **à quelle
  heure** le reste pourra suivre, avant le premier envoi.
- Un fichier trop gros est refusé par une phrase qui dit la limite et la taille du fichier.
- Chaque cible tactile ≥ 48 dp, chaque état lisible en niveaux de gris.

## 3. Direction retenue

**Trois temps sur une seule route, jamais un assistant.** `/admin/membres/importer` change de
contenu trois fois — choisir, relire, rendre compte — sans changer d'adresse et sans repère
d'étape. Ce n'est pas un tunnel : c'est le même geste que le formulaire d'invitation du 006, qui
devient son propre compte rendu après l'envoi. Un « Étape 2 sur 3 » mentirait, d'ailleurs, puisque
le deuxième temps peut renvoyer au premier autant de fois qu'on veut.

**L'aperçu est un registre, pas un tableur.** La tentation est de rendre le fichier tel qu'il est :
un tableau de colonnes, éditable en place. On ne le fait pas. Une ligne d'aperçu est la même ligne
réglée que partout ailleurs dans le produit — nom, adresse, verdict — parce que c'est ainsi que la
personne la reverra dans la liste des membres cinq minutes plus tard, et parce qu'un tableau de
quatre colonnes sur un téléphone est illisible. **Rien n'est éditable ici.** Le tableur est le lieu
de la correction ; l'écran est le lieu de la vérification. « Corrige ton fichier et redépose-le »
est une consigne qu'un chef de centre applique en dix secondes, alors qu'un champ de saisie dans
une liste de soixante lignes est une invitation à se tromper deux fois.

**Le budget d'envoi est un fait, pas une alarme.** Il s'affiche dans l'aperçu comme les autres
comptes, en `AppBanner` variante `information` quand tout passe, `attention` quand il faudra
reprendre. Jamais en rouge : ne pas pouvoir envoyer soixante-deux courriels dans la même minute
n'est pas une panne, c'est la règle de la maison, et elle protège le domaine d'envoi de toutes les
casernes.

**Le nom importé est une proposition.** Voir § 7, c'est la décision centrale du ticket.

## 4. Périmètre et limites

**Dans le périmètre.** Le bouton « Importer un fichier » sur « Membres », la route
`/admin/membres/importer` et ses trois temps, la lecture d'un fichier tableur (deux séparateurs,
deux encodages, en-têtes reconnus), l'aperçu ligne par ligne avec ses verdicts, l'annonce de
budget, l'envoi par lots de vingt, le rapport dans le vocabulaire du 006, le fichier d'exemple
téléchargeable, les noms portés jusqu'au profil de l'invité, et les deux refus de taille.

**Hors périmètre, explicitement.**

- **Le glisser-déposer.** Le sélecteur de fichier du navigateur suffit, il est accessible au
  clavier et il fonctionne sur téléphone. Une zone de dépôt ajoute un chemin que personne ne teste
  et qui n'existe pas au tactile.
- **Le tableur natif** (`.xlsx`, `.ods`). Lire un classeur binaire demande une bibliothèque, et
  « Enregistrer sous → CSV » est un geste que tout tableur connaît. L'écran le dit.
- **La correction en ligne dans l'aperçu.** Décidé ci-dessus.
- **La création de comptes sans adresse e-mail.** Le propriétaire a confirmé que tous ses pompiers
  en ont une. Le chemin reste l'invitation.
- **La reprise automatique différée.** Quand le budget est épuisé, l'application ne programme rien :
  elle dit l'heure et laisse revenir. Une file d'attente côté client mourrait avec l'onglet, et
  une file côté serveur est un ticket à elle seule (`notification_outbox` existe pour les
  notifications, pas pour les invitations).
- **L'export de la liste des membres.** Ce ticket lit un fichier, il n'en écrit pas — sauf le
  fichier d'exemple, qui ne contient aucune donnée réelle.

## 5. Écrans, états et textes

Tous les textes sont dans `AppStrings` ; les libellés ci-dessous sont ceux qui sont rendus.

### 5.1 « Membres » — le point d'entrée

Sous « Inviter des pompiers », un second bouton pleine largeur, variante **secondaire** : **«
Importer un fichier »**, icône `upload_file`. Secondaire parce que l'invitation à la main reste le
geste ordinaire ; l'import est le geste du premier jour. Les deux boutons sont séparés de 8 dp,
comme deux cibles adjacentes.

Rien d'autre ne bouge sur cet écran — sauf la ligne d'une invitation en attente, qui affiche
désormais **le nom quand il est connu** (§ 7) : « Marie Lefebvre » en titre, l'adresse en dessous,
au lieu de l'adresse seule. Une invitation sans nom garde exactement la forme du 006.

### 5.2 « Importer des membres » — `/admin/membres/importer`

Route fille de « Membres », barre avec retour, comme `/admin/membres/inviter`. Le bouton du
navigateur ramène à la liste, à n'importe lequel des trois temps.

#### Temps 1 — choisir

Une phrase de cadrage, puis ce que le fichier doit contenir, écrit noir sur blanc dans un bloc
réglé plutôt que dans un paragraphe : la ligne d'en-têtes attendue, et la mention des variantes
acceptées. Puis deux sorties :

- **« Choisir un fichier »**, bouton principal, icône `upload_file`.
- **« Télécharger un fichier d'exemple »**, lien secondaire : il produit un `.csv` de trois lignes
  fictives, en UTF-8 avec BOM et séparateur point-virgule — les deux réglages qu'Excel en français
  relit sans broncher. C'est la réponse la plus courte à « et il ressemble à quoi, ce fichier ? ».

| État | Ce qui s'affiche |
|---|---|
| Fichier trop gros | Bannière `erreur` : « Ce fichier fait 1,4 Mo. La limite est de 512 Ko — environ 5 000 pompiers. » |
| Trop de lignes | Bannière `erreur` : « Ce fichier compte 900 lignes. La limite est de 500 par import. » |
| Pas de colonne d'adresse | Bannière `erreur` nommant les intitulés reconnus, et l'invitation à corriger l'en-tête |
| Fichier vide | Bannière `erreur` : « Ce fichier ne contient aucune ligne. » |
| Sélection annulée | Rien. Fermer le sélecteur n'est pas un échec |
| Hors navigateur | Le bouton est inerte, avec sa raison à côté (`DESIGN.md § Do`) |

#### Temps 2 — l'aperçu

En tête, le nom du fichier et le compte annoncé : « 60 lignes lues : 58 à inviter, 2 écartées. »
(`liveRegion`.) Puis, quand il y a quelque chose à dire, **la bannière de budget** :

| Cas | Variante | Texte |
|---|---|---|
| Tout passe | `information` | « Les 58 invitations peuvent partir maintenant. » |
| Une partie seulement | `attention` | « 60 invitations peuvent partir maintenant, 2 à partir de 15 h 12. Reviens ici avec le même fichier : les personnes déjà invitées seront ignorées. » |
| Budget nul | `attention` | « Aucune invitation ne peut partir avant 15 h 12. » |
| Budget inconnu | *(rien)* | Le serveur reste l'autorité ; on ne fabrique pas une inquiétude à partir d'une lecture ratée |

Puis la liste, une ligne réglée par ligne du fichier, dans l'ordre du fichier :

1. Le nom (`titleMedium`), ou l'adresse en titre quand le nom manque.
2. L'adresse (`bodyMedium`, `on-surface-variant`), suivie de « · Admin de caserne » pour les seules
   lignes qui portent ce rôle.
3. Le verdict, quand il n'est pas « à inviter » : marque + icône + libellé, gris pour un fait,
   `error` pour une erreur, jamais la couleur seule.

Les sept verdicts d'aperçu, et **ils ne s'inventent pas** : ce sont les motifs du 006, plus ceux
que seul un fichier peut produire.

| Verdict | Icône | Libellé | Compté dans |
|---|---|---|---|
| À inviter | *(aucune)* | *(aucun)* | à inviter |
| Déjà membre | `person_outline` | « Déjà membre actif de la caserne. » | écartée |
| Déjà invitée | `schedule_send_outlined` | « Invitation déjà en attente. Ignorée. » | écartée |
| Doublon du fichier | `content_copy_outlined` | « Déjà présente ligne 12. » | écartée |
| Adresse invalide | `error_outline` | « Adresse e-mail incomplète. » | écartée |
| Adresse absente | `error_outline` | « Pas d'adresse sur cette ligne. » | écartée |
| Nom absent | *(aucune)* | « Sans nom : le pompier le saisira lui-même. » | à inviter |

Une ligne sans nom **part quand même**. L'adresse est ce qui fait entrer quelqu'un dans la caserne ;
le nom est un confort, et le refuser priverait le chef de centre d'une personne pour une colonne
vide. La ligne le dit, en gris, et n'est pas comptée comme une erreur.

Sorties, en bas : **« Envoyer les 58 invitations »** (le nombre est dans le libellé, parce que
c'est le seul chiffre qui engage) et **« Choisir un autre fichier »**. Le bouton principal est
inerte, avec sa raison à côté, quand rien n'est à inviter.

Pendant l'envoi : le bouton passe en chargement, son libellé ne bouge pas, et une ligne annoncée
dit l'avancement — « 40 invitations sur 58 envoyées… ». Un import de soixante personnes prend une
dizaine de secondes ; un écran muet pendant dix secondes est un écran qu'on recharge.

#### Temps 3 — le rapport

**Le vocabulaire du 006, sans un mot de plus.** Le rapport réutilise `RapportInvitationsVue` telle
quelle : ligne de résumé annoncée, « Résultat par adresse », une ligne par adresse avec son icône,
son statut — « Invitée », « Renvoyée », « Échec » — et son motif en français. Un courriel qui n'est
pas parti n'est pas un échec (`schedule_send`). Un refus de débit affiche **la phrase du serveur**,
délai compris.

Ce que le ticket ajoute autour, et seulement autour :

- **Au-dessus** : les lignes écartées à l'aperçu, repliées en une phrase — « 2 lignes du fichier
  n'ont rien reçu : 1 déjà membre, 1 adresse invalide. » Elles ne descendent pas dans « Résultat
  par adresse » : on n'y met que ce qui a été tenté.
- **En dessous**, quand le plafond a coupé l'envoi : une bannière `attention` qui reprend la phrase
  du serveur et nomme la suite — « Reprends l'import après 15 h 12 avec le même fichier : les
  personnes déjà invitées seront ignorées. »

Sorties : **« Reprendre l'import »** (retour au temps 1, seulement après un refus de débit) et
**« Revenir aux membres »**.

### 5.3 Ce que l'invité voit — `/bienvenue/profil`

Inchangé dans sa forme (006 § 5.4). Un seul ajout : **les champs Prénom et Nom arrivent
pré-remplis** avec ce que l'administrateur a saisi à l'import, quand le profil n'avait rien. Aucun
texte ne le signale — « voici ce que ton chef de centre a écrit de toi » n'apporte rien et invite à
discuter. Le pompier lit son nom, le corrige s'il le faut, et valide.

## 6. Interaction et layout

- Compact d'abord : une colonne, colonne de contenu bornée à 720 dp comme le formulaire
  d'invitation, boutons pleine largeur en bas dans une `SafeArea`.
- La liste d'aperçu est **virtualisée** : cinq cents lignes réglées ne se construisent pas d'un
  bloc. C'est le seul endroit du ticket où la performance décide d'une structure de widget.
- Cibles : 48 dp partout, 8 dp entre les deux boutons.
- Aucune information portée par la seule couleur : chaque verdict est icône + libellé, et la
  bannière de budget porte son icône.
- Mouvement : aucun ajouté. Le passage d'un temps à l'autre est un changement de contenu, pas une
  transition ; la liste d'aperçu ne s'anime pas.
- Accessibilité : le compte de lignes, le compte d'avancement et le résumé du rapport sont des
  `liveRegion` ; chaque ligne d'aperçu porte un `Semantics` unique (nom, adresse, verdict) et
  exclut ses enfants, pour être lue comme une phrase et non comme trois fragments ; le bouton
  d'envoi inerte annonce sa raison dans son `hint`.
- Chiffres tabulaires pour les comptes et les heures, comme partout ailleurs.

## 7. Contraintes et décisions

### La décision centrale : à qui appartient le nom

Un nom peut être écrit deux fois — par l'administrateur à l'import, par le pompier à sa première
connexion — et le ticket demande de trancher. La réponse tient en trois lignes, et elle s'appuie
sur une distinction que le schéma porte déjà :

1. **`profiles.first_name` / `last_name` appartiennent à la personne.** Le nom importé n'y est
   écrit que si la case est vide, par `accept_invitation`, au moment où l'invité entre dans la
   caserne. Il **pré-remplit** ensuite l'écran de profil : c'est une proposition, que le pompier
   lit, corrige et valide. **Ce qu'il valide gagne, toujours.** Un import n'écrase jamais un nom
   déjà écrit par quelqu'un sur lui-même, et un compte qui existait déjà — un pompier de la caserne
   voisine, un ancien membre réactivé — ne voit pas son profil réécrit par l'administrateur d'une
   caserne.
2. **`memberships.display_name` appartient à l'administrateur.** Il existe depuis le ticket 009
   (« Modifier le nom affiché »), il prime dans les plannings de **cette** caserne, et il est la
   sortie prévue quand le chef de centre n'est pas d'accord avec le nom qu'affiche un profil. Il
   n'est pas écrit par l'import : un surnom de caserne se décide, il ne se déduit pas d'un tableur.
3. **Entre les deux, la caserne voit le nom tout de suite** : `invitations.first_name` /
   `last_name` portent le nom importé jusqu'à l'acceptation, et la ligne d'invitation en attente
   l'affiche. Sans cela, le chef de centre passerait deux semaines devant une liste d'adresses.

Autrement dit : **l'administrateur propose, la personne dispose, l'administrateur garde le dernier
mot sur son propre planning.** Aucune des trois écritures n'écrase l'autre, parce qu'elles ne
visent pas la même colonne.

### Le plafond, et pourquoi l'aperçu sait compter

Le serveur reste l'autorité : `create_invitation` compte, refuse, et compose la phrase qui dit
quand réessayer. L'écran ne le double pas, il l'**anticipe** — et il le fait sans nouvelle fonction
serveur, parce que tout est déjà lisible par un administrateur de la caserne :
`invitation_rate_events` lui est ouverte en lecture (migration `0032`, « il subit le refus, il doit
pouvoir en voir la cause ») et `stations.settings` porte `invitation_hourly_limit`. Compter les
lignes de la dernière heure et lire la n-ième plus ancienne donne exactement le `retry_at` que le
serveur calculerait.

Trois conséquences assumées :

- **L'annonce est une prévision, pas une promesse.** Deux administrateurs qui invitent en même
  temps, ou un renvoi glissé entre l'aperçu et l'envoi, la démentent. C'est pourquoi le rapport
  affiche toujours la phrase du serveur, jamais celle de l'écran, dès qu'un refus arrive.
- **Le super-administrateur n'est pas prévu par l'aperçu.** Son plafond est de 200 par acteur,
  toutes casernes confondues, et il ne peut pas lire les compteurs des autres casernes. Il verra
  donc le budget de la caserne visée, et le vrai refus viendra du serveur. C'est un écart connu,
  pour un acteur qui n'importe pas de fichier.
- **L'envoi s'arrête franchement.** L'Edge Function court-circuite déjà les adresses suivantes dès
  qu'une est refusée ; le client fait pareil entre deux lots. On ne tente pas les quarante
  restantes pour récolter quarante fois la même phrase.

### Fermes

- **Le fichier ne quitte jamais le navigateur autrement qu'en adresses.** Il est lu en mémoire,
  découpé, et seules les colonnes retenues partent dans l'appel. Aucun envoi du fichier brut, aucun
  stockage.
- **Aucun plugin.** Le sélecteur de fichier est un `input[type=file]` derrière un import
  conditionnel, exactement comme `telechargement_web.dart` du ticket 034. Hors navigateur, le stub
  dit non plutôt que de faire semblant.
- **La limite de taille est vérifiée avant la lecture**, sur `File.size`, et pas après avoir chargé
  le fichier en mémoire : un refus qui commence par faire planter l'onglet n'est pas un refus.
- **L'encodage est deviné, jamais demandé.** UTF-8 strict d'abord ; s'il échoue, Windows-1252, qui
  ne peut pas échouer. Personne ne doit savoir ce qu'est un encodage pour importer ses pompiers.
- **Les écritures passent par `invite-member`**, comme au 006 : les fonctions SQL d'invitation sont
  réservées au `service_role`, et le jeton ne sort pas du serveur.

### Tranchées pendant le brief

- **Vingt adresses par appel restent vingt.** Le client découpe, le serveur ne change pas de
  plafond. Ce plafond borne le temps d'une requête et la taille d'une réponse ; l'import n'a aucune
  raison de l'assouplir, il a juste besoin de savoir compter jusqu'à trois lots.
- **Une personne déjà invitée est ignorée, pas renvoyée.** C'est ce qui rend l'import rejouable :
  redéposer le même fichier après le plafond n'envoie que ce qui manquait. Un renvoi consommerait
  du budget pour prolonger une invitation que personne n'a demandé à prolonger.
- **Le rôle est par ligne, pas par lot.** Un fichier porte une colonne « rôle » ; imposer un rôle
  unique au lot obligerait à importer deux fois. L'appel accepte donc un rôle par personne, avec le
  rôle du lot en repli.
- **Le fichier d'exemple est produit par l'écran, pas livré en `assets/`.** Trois lignes de texte
  n'ont pas besoin d'un fichier embarqué, et le produire sur place garantit qu'il suit les
  intitulés que le code reconnaît vraiment.

### Ce qu'un développeur ne doit pas inventer ici

Une zone de glisser-déposer, un tableau éditable, une barre de progression circulaire au milieu de
l'écran, un écran de succès, un import qui écrase un profil existant, une file d'attente qui
promettrait d'envoyer plus tard, ou un second vocabulaire de résultats à côté de celui du 006.

## 8. Le fichier attendu

Séparateur virgule ou point-virgule, détecté sur la ligne d'en-têtes. Encodage UTF-8 ou
Windows-1252, détecté. Guillemets acceptés autour des champs, doublés à l'intérieur (RFC 4180).
Limites : **512 Ko** et **500 lignes**.

```csv
prenom;nom;email;role
Marie;Lefèbvre;marie.lefebvre@exemple.fr;admin
Thomas;Nguyen;thomas.nguyen@exemple.fr;membre
Camille;Roux;camille.roux@exemple.fr;
```

Intitulés reconnus, accents, casse et ponctuation indifférents :

| Colonne | Intitulés acceptés | Obligatoire |
|---|---|---|
| Prénom | `prenom`, `prénom`, `first name`, `firstname`, `given name` | non |
| Nom | `nom`, `nom de famille`, `last name`, `lastname`, `surname`, `famille` | non |
| Adresse | `email`, `e-mail`, `courriel`, `mail`, `adresse e-mail`, `adresse mail`, `adresse` | **oui** |
| Rôle | `role`, `rôle`, `fonction`, `droits`, `statut` | non |

Valeurs de la colonne rôle qui donnent le rôle d'administrateur : `admin`, `administrateur`,
`administratrice`, `chef`, `chef de centre`, `responsable`. Tout le reste — y compris une case vide
— donne `membre`. On ne refuse pas une ligne pour un rôle qu'on ne comprend pas : le rôle se
change en deux gestes dans la feuille d'actions du ticket 009, l'invitation ne se rattrape pas.
