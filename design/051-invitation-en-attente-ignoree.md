# 051 — Une invitation en attente reste invisible pour qui vient de se connecter

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web
mobile-first**, Material 3, une seule apparence sur toutes les cibles. `DESIGN.md` gagne sur ce
brief pour toute valeur de token. `design/006-invitations-onboarding.md` décrit l'écran
d'invitation (`/invite/:jeton`) et « Aucune caserne » tels qu'ils sont livrés : ce ticket ne les
réécrit pas, il branche l'un sur l'autre.

**Ce ticket répare un mensonge, il n'ajoute pas un écran.** « Aucune caserne » affirme aujourd'hui
quelque chose qu'il n'a jamais vérifié. Tout le travail consiste à lui faire poser la question
avant de répondre, et à ne rien dire de plus que ce qu'il a le droit de savoir.

---

## 1. Job et audience

**Un pompier, sur son téléphone, la première fois, sans son courriel sous les yeux.**

Son chef de centre vient de l'inviter. Peut-être qu'il a reçu le message et ne l'a pas ouvert.
Peut-être qu'il l'a rangé. Peut-être qu'il avait déjà installé la PWA et qu'il l'a simplement
rouverte. Peut-être qu'on lui a dit « télécharge le truc, je t'ai ajouté » et qu'il n'a jamais
pensé au courriel. Dans les quatre cas il fait la même chose : il tape son adresse, il reçoit son
code à six chiffres, il entre — et il tombe sur un écran qui lui dit d'aller demander ce qu'il a
déjà reçu.

C'est le fait vécu du 21 septembre 2026, par le propriétaire du produit lui-même, sur son premier
compte de pompier. Ce n'est pas un cas limite : c'est le chemin **le plus court** entre l'invitation
et l'application, et c'est celui que prendra n'importe qui à qui on présente le produit de vive
voix.

**Ce qui se joue.** Un cul-de-sac au tout premier écran, sur un compte qui vient de naître. La
personne n'a aucune raison de réessayer : l'application lui a dit, noir sur blanc, qu'elle n'était
pas attendue. Elle referme, elle n'y revient pas, et le chef de centre voit une invitation « En
attente » qu'il finira par renvoyer — pour rien, puisque le courriel n'a jamais été le problème.
Le coût est une personne qui n'entre jamais dans le planning, c'est-à-dire une garde à couvrir
autrement.

**Le mécanisme, en une phrase.** `invite-member` fait naître le compte, `accept-invitation` fait
naître l'appartenance ; entre les deux vit un compte sans caserne, et « Aucune caserne » est le
seul écran qui le reçoit.

## 2. Résultat et preuve

**Résultat.** Qui se connecte avec une adresse invitée voit la caserne qui l'attend, qui l'a
invité, jusqu'à quand, et entre d'une touche. Qui n'a réellement rien voit exactement l'écran
d'aujourd'hui. Qui a laissé passer le délai l'apprend, et apprend à qui le dire.

**Preuves, vérifiables.**

- Une session dont l'adresse porte une invitation en attente n'affiche **jamais** la phrase
  « Demande une invitation à ton chef de centre » — ni après la réponse du serveur, ni **pendant**
  l'attente de cette réponse.
- « Expirée » et « aucune » sont deux écrans différents, avec deux titres différents et deux
  sorties différentes.
- Une session sans invitation voit le texte du ticket 006, caractère pour caractère.
- Rejoindre depuis cet écran et rejoindre depuis le lien du courriel produisent la même page de
  bienvenue, la même suite (profil, guide), et les mêmes fins de parcours en cas d'échec.
- Le corps de la réponse serveur, lu au réseau, ne contient **ni jeton, ni identifiant de caserne,
  ni adresse autre que celle de la session**, et une requête posée sous une autre identité rend
  zéro ligne.
- Chaque cible tactile ≥ 48 dp, chaque état lisible en niveaux de gris.

## 3. Direction retenue

**L'écran pose la question avant de répondre.** Toute la conception tient dans l'ordre des
opérations : « Aucune caserne » n'est plus un état vide, c'est un **verdict** qui attend son
enquête. Trois réponses possibles, trois formes, un seul écran, une seule route.

| Réponse du serveur | Ce que l'écran devient |
|---|---|
| Une invitation en attente, ou plusieurs | Le panneau d'invitations reçues (§ 5.2) |
| Uniquement des invitations expirées | Le panneau, en forme d'échéance manquée (§ 5.3) |
| Rien | L'`EmptyState` actuel, inchangé (§ 5.4) |

**Le meuble ne bouge pas entre les trois.** Même `Scaffold`, même `SafeArea`, même bouton « Se
déconnecter » au même endroit en bas. Ce qui change est le contenu de la zone centrale, jamais la
structure : un écran qui se réorganise sous les doigts pendant qu'une réponse arrive est un écran
qu'on quitte.

**L'invitation se lit comme la ligne que l'administrateur voit déjà.** Nom, qui, badge d'état,
échéance : c'est `LigneInvitation` de l'écran « Membres » (006 § 5.1), vue de l'autre côté. Même
badge `StatusBadge.attribution`, mêmes libellés « En attente » et « Expirée », mêmes phrases
d'échéance. Les deux bouts du produit nomment la même chose du même mot — c'est ce qui permet à un
chef de centre de dire au téléphone « tu dois voir “En attente” » et d'être compris.

**Ce que l'écran ne fait pas : accepter sur place.** Voir § 7, c'est la décision centrale du
ticket.

## 4. Périmètre et limites

**Dans le périmètre.** La recherche d'invitations en attente pour l'adresse de la session, les
trois formes de `/aucune-caserne` ci-dessus, l'état d'attente et l'état d'échec de cette recherche,
le geste « Rejoindre », la route qui mène à l'acceptation sans jeton, et les textes.

**Hors périmètre, explicitement.**

- **Demander une nouvelle invitation depuis l'application.** Une invitation expirée renvoie vers
  une personne, pas vers un bouton. Écrire à l'administrateur depuis l'écran supposerait un canal
  (courriel sortant vers un admin, notification) qui n'existe pas dans le MVP, et un compte sans
  appartenance n'a aucun droit d'écrire à qui que ce soit.
- **Une notification, une pastille, un rappel.** Personne n'est abonné à quoi que ce soit avant
  d'avoir une appartenance.
- **Rendre l'adresse invitée visible à la connexion.** L'écran de connexion ne change pas, le lien
  ne porte pas l'adresse (006 § 5.3), et rien ici ne se pré-remplit.
- **Toucher aux deux écrans du ticket 006.** `/invite/:jeton` garde ses six fins de parcours, et il
  les garde **seul** : elles ne se recopient pas ici.
- **Un cache local.** Cette lecture n'est jamais écrite sur l'appareil. Elle décide d'un droit
  d'entrée ; un cache ne décide jamais d'un droit (`CLAUDE.md`), et rien n'est à brancher dans
  `deconnexion.dart`. Hors ligne, l'écran le dit (§ 5.5) plutôt que de deviner.

## 5. Écrans, états et textes

Route inchangée : `/aucune-caserne`. Ossature inchangée : `Scaffold` > `SafeArea` > `Column`, une
zone centrale extensible, et `BoutonDeconnexion` dans son `Padding` de `AppSpacing.lg` en bas.
**La sortie « Se déconnecter » reste dans les cinq formes** : se tromper d'adresse est exactement
le genre d'erreur que cet écran reçoit, et elle doit rester réparable d'une touche.

Tous les textes sont dans `AppStrings` (§ 9).

### 5.1 Pendant la recherche — l'état qui n'existait pas

**C'est l'état le plus important du ticket.** Aujourd'hui l'écran affiche sa phrase fausse
immédiatement. Si la recherche prend six cents millisecondes et que la phrase s'affiche pendant ces
six cents millisecondes, le défaut est intact : la personne l'a lue, elle a compris qu'elle n'était
pas attendue, et elle est partie.

Zone centrale : le titre neutre **« Ton compte »**, la phrase annoncée **« Vérification de tes
invitations… »** (`Semantics(liveRegion: true)`), puis un squelette à la forme du contenu attendu —
`SkeletonLigne`, `SkeletonLigne(largeur: 220)`, `SkeletonBloc(hauteur: AppTouch.bouton)`. Jamais de
roue au milieu de l'écran (`DESIGN.md § Don't`). C'est exactement l'`AttenteInvitation` de
`/invite/:jeton`, et il n'y a aucune raison d'en dessiner une seconde.

### 5.2 Une invitation en attente — le cas nominal

| | |
|---|---|
| Titre | « Une caserne t'attend » — au pluriel : « 2 casernes t'attendent » |
| Cadrage | « Une invitation a été envoyée à `marie.dupont@exemple.fr`. Rejoins-la ici, sans ouvrir ton courriel. » |

L'adresse de la session est dans la phrase de cadrage, et c'est délibéré : la personne vient de
taper cette adresse il y a trente secondes, et c'est le seul fait qui relie ce qu'elle voit à ce
qu'elle a fait. C'est sa propre adresse, elle ne révèle rien.

Puis une **ligne réglée par invitation**, séparées par `AppDivider`, dans l'ordre d'échéance la
plus proche d'abord, les expirées en dernier :

1. **Le nom de la caserne**, `titleMedium`. Le point focal de l'écran : c'est la seule chose qui
   donne un sens au bouton d'en dessous. Personne ne rejoint « une caserne », on rejoint le CS
   Maurepas.
2. **« Invitation envoyée par Marc Dubois. »**, `bodyMedium` / `on-surface-variant`. C'est ce qui
   fait passer l'invitation de « un logiciel me réclame » à « mon chef m'attend ». Ligne omise
   quand le serveur ne rend pas de nom — jamais remplacée par une adresse.
3. **Le badge et l'échéance**, dans un `Wrap` : `StatusBadge.attribution(propose)` libellé « En
   attente », puis « Expire le 5 octobre » (`formaterDateLongue`). Marque + icône + libellé, gris
   pour un fait : une invitation en attente n'est pas une alarme.
4. **Le bouton**, `PrimaryButton` : **« Rejoindre le CS Maurepas »**. Le libellé nomme la caserne,
   parce qu'avec deux invitations à l'écran deux boutons « Rejoindre » identiques seraient un piège
   — et parce qu'un bouton nomme son action (`DESIGN.md § Do`).

**Variante du bouton selon le compte.** Une seule invitation : `primaire`, pleine largeur — c'est
l'action de l'écran. Plusieurs : **`secondaire` pour toutes**, pleine largeur aussi. Aucune n'est
« la » bonne, et hiérarchiser au hasard deux casernes serait un avis que le produit n'a pas à
donner.

Pendant l'appel : le bouton touché passe en chargement, **libellé inchangé, largeur inchangée**
(`DESIGN.md § Buttons`) ; les autres boutons de la liste deviennent inertes, avec leur raison à
côté (« Acceptation en cours… »). On n'entre pas dans deux casernes à la fois.

### 5.3 Une invitation expirée — ce qui n'est pas « aucune invitation »

C'est l'insistance du ticket, et elle est juste : les deux écrans n'ont pas la même sortie. « Aucune
invitation » dit « fais-toi inviter ». « Invitation expirée » dit « fais-la renvoyer », ce qui est
un geste de trois secondes pour l'administrateur, et il sait déjà de quoi on parle puisque la ligne
est sous ses yeux, marquée « Expirée ».

Quand il n'y a **que** des expirées, le titre devient **« Ton invitation a expiré »** (pluriel :
« Tes invitations ont expiré ») et le cadrage disparaît au profit de la ligne elle-même.

La ligne expirée garde la même forme, avec trois différences :

- badge `StatusBadge.attribution(annule)` libellé **« Expirée »**, et « Expirée le 1er octobre » ;
- **pas de bouton.** Un bouton dont on sait qu'il échouera est un piège, et un bouton grisé n'aurait
  rien à dire de plus que la phrase qui le remplace ;
- à la place, la sortie, en `bodyMedium` : **« Demande à Marc Dubois de te la renvoyer. »**, ou
  **« Demande à l'administrateur de la caserne de te la renvoyer. »** quand le nom manque.

Une expirée listée **sous** une invitation valide garde sa ligne et sa phrase : elle explique
pourquoi la caserne où l'on a été invité en août n'est pas dans la liste des choix.

### 5.4 Rien du tout — le texte actuel, et on n'y touche pas

`EmptyState(titre: aucuneCaserneTitre, texte: aucuneCaserneTexte, icone:
Icons.markunread_mailbox_outlined)`, exactement comme aujourd'hui. « Aucune caserne » / « Ton
compte existe, mais il n'est rattaché à aucune caserne. Demande une invitation à ton chef de
centre : il t'ajoutera avec cette adresse e-mail. »

**Cette phrase n'a jamais été mauvaise** — elle était mal adressée. Elle dit le fait, elle dit le
geste, elle nomme la personne, elle explique même pourquoi l'adresse compte. Une fois qu'on ne la
montre plus qu'à qui n'a effectivement rien, elle est la bonne phrase, et la réécrire serait perdre
du temps sur le seul morceau de cet écran qui fonctionnait.

La branche « accès désactivé » (`caserneDesactiveeTitre`) est également **inchangée**.

### 5.5 Les états dégradés, et pourquoi ils ne mentent pas non plus

| Cas | Ce qui s'affiche |
|---|---|
| **Échec de la recherche** (serveur, 500, réponse illisible) | Titre « Ton compte », `AppBanner` variante `erreur` : « Impossible de vérifier tes invitations. Tu en as peut-être une en attente. » + action « Réessayer ». En dessous, **le fait seul** : « Ton compte existe, mais il n'est rattaché à aucune caserne. » |
| **Hors ligne** | Même forme, `AppBanner` variante `hors-ligne` : « Hors ligne. Impossible de vérifier tes invitations. » + « Réessayer » |
| **Échec de l'acceptation** | On ne le traite pas ici : le geste a déjà quitté l'écran (§ 7), et les fins de parcours sont celles du 006 |
| **Retour depuis une acceptation ratée** | La liste est **relue**, pas restituée de mémoire : entre-temps l'invitation a pu expirer ou être annulée |
| **Membre désactivé + invitation en attente** | Le panneau d'invitations gagne, et `AppBanner` variante `information` rappelle le fait : « Ton accès à CS Trappes a été désactivé. » La seule chose actionnable à l'écran est l'invitation ; c'est elle qui occupe le centre |
| **Membre désactivé, aucune invitation** | Écran « Accès désactivé » actuel, inchangé |

**La phrase se coupe en deux, et c'est la leçon du ticket.** Le texte actuel additionne un **fait**
(« ton compte n'est rattaché à aucune caserne ») et un **conseil** (« demande une invitation »).
Le fait est toujours vrai, il vient des appartenances, qui sont déjà chargées. Le conseil dépend
d'une chose qu'on n'avait jamais vérifiée. Quand la vérification échoue, on garde le fait et on
abandonne le conseil : c'est la seule forme qui ne peut pas se tromper.

**Plafonds de contenu.** Une invitation dans 99 % des cas. Deux ou trois pour un pompier qui change
de département ou qui est double-affecté. Le serveur en rend au plus dix (§ 6) ; au-delà, la liste
défile, elle ne se replie pas. Un nom de caserne peut faire quarante caractères (« Centre de
secours principal de Rambouillet ») : il s'enroule sur deux lignes, le bouton aussi, rien ne se
tronque.

## 6. Ce que la base doit rendre — à trancher par `supabase-dev`

**Le problème posé.** Un compte sans appartenance n'a, par construction, aucun droit de lecture sur
`invitations` : la politique `invitations_select_admin` (migration `0008`, `docs/SCHEMA.md § 4`)
l'ouvre à l'administrateur de la caserne et à personne d'autre. L'écran ne peut donc pas lire la
table, et ce n'est pas un oubli à corriger : élargir cette politique ouvrirait la liste des
invitations d'une caserne à des comptes qui n'y sont pas.

**La forme proposée.** Une fonction `security definer`, `stable`, `set search_path = public`, sans
paramètre, exécutable par `authenticated` seul (`revoke` sur `public` et `anon`), qui rend au plus
ce qui concerne l'adresse de la session. Nom proposé : `my_pending_invitations()`. `docs/SCHEMA.md`
gagne : `supabase-dev` tranche la signature, le type de retour et la migration.

**Sans paramètre, et c'est la contrainte principale.** L'adresse vient de
`auth.jwt() ->> 'email'`, jamais d'un argument. Une fonction qui accepterait une adresse serait un
oracle : n'importe quel compte connecté saurait, adresse par adresse, qui est invité où. La
comparaison se fait sur `lower(email)`, comme l'index `invitations_pending_uniq`, et le filtre est
`accepted_at is null`.

### Les champs, et la raison de chacun

| Champ | Type | Pourquoi l'écran en a besoin |
|---|---|---|
| `id` | `uuid` | Désigner **laquelle** on rejoint, quand il y en a plusieurs, et la passer à l'acceptation (§ 7). Ce n'est pas un porteur de droits : seul le compte dont l'adresse correspond peut en faire quoi que ce soit, et le serveur le revérifie |
| `station_name` | `text` | Le point focal de l'écran (§ 5.2). Sans lui, « Rejoindre » demande un consentement à l'aveugle, et le produit redemande à la personne d'aller chercher son courriel — c'est-à-dire ne corrige rien |
| `invited_by_name` | `text`, nullable | « Invitation envoyée par Marc Dubois. » Ce qui distingue une invitation attendue d'une erreur, et **qui nommer** quand elle a expiré (§ 5.3). Prénom + nom recomposés côté serveur, comme le fait déjà `accept-invitation` dans son objet `inviter`. `null` quand le profil n'a pas de nom : l'écran omet la ligne |
| `expires_at` | `timestamptz` | « Expire le 5 octobre » / « Expirée le 1er octobre ». Dit s'il y a urgence, et date l'échec quand il est passé |
| `status` | `text` (`pending` \| `expired`) | Le serveur tranche l'expiration, pas le téléphone. L'horloge d'un appareil dérive, et un téléphone de caserne prêté dérive davantage ; ce ticket existe parce que l'application a affirmé quelque chose qu'elle n'avait pas vérifié, on ne va pas la laisser recommencer sur une soustraction de dates locale. C'est aussi la garantie que l'écran et `accept_invitation` placent la frontière au même endroit |

Cinq champs. Tri par `expires_at` décroissant, **au plus dix lignes** : personne n'est invité par
quarante casernes, et une réponse dont la taille dépend d'un appelant est une réponse à borner.
**Zéro ligne, jamais une exception**, pour qui n'a rien : « pas d'invitation » et « pas le droit »
doivent être indiscernables.

### Ce que la fonction ne rend pas, et pourquoi

| Refusé | Raison |
|---|---|
| `token` | Porteur de droits. Il est hors du `grant` de select depuis `0008` ; une fonction `security definer` qui le rendrait rouvrirait par la fenêtre la porte que la migration a fermée. Aucun écran n'en a besoin : § 7 |
| `station_id` | L'écran n'interroge rien avec. Un compte non membre ne peut pas lire `stations` de toute façon, et un identifiant est une prise sur un tenant qu'on ne lui doit pas |
| `role` | Savoir qu'on est invité comme admin ne change aucun geste sur cet écran. Le rôle s'affiche sur l'accueil, une fois entré. Un contenu lu par un non-membre ne porte que ce dont le geste a besoin |
| `email` (l'adresse invitée) | C'est l'adresse de la session, le client l'a déjà. La rendre inviterait à filtrer côté client, c'est-à-dire à ne pas filtrer |
| `email_sent_at`, `email_error` | Le diagnostic de l'administrateur (`0035`, ticket 048), attaché à son écran. L'invité n'a rien à faire de savoir si le courriel est parti : il est là, précisément sans l'avoir lu |
| `invited_by` (uuid), adresse ou téléphone de l'invitant | Aucun geste n'en dépend. Un nom suffit à nommer quelqu'un |
| `first_name`, `last_name` de l'invitation | La personne connaît son nom. Lui montrer celui que son chef a tapé dans un tableur ouvre une discussion que le ticket 047 a explicitement refusée |
| Statut d'abonnement de la caserne | Une caserne suspendue refuse à l'acceptation, avec sa fin de parcours déjà écrite (006 § 5.3). L'annoncer d'avance dupliquerait le vocabulaire et livrerait l'état commercial d'une caserne à quelqu'un qui n'en fait pas partie |
| `created_at` | Personne ne s'en sert |

### Le test sous identité, demandé par le critère d'acceptation

Connecté comme B : `my_pending_invitations()` ne rend rien de l'invitation de A ; rend bien la
ligne **expirée** de B (et non zéro ligne, sinon « expirée » redevient « aucune ») ; `select token
from invitations` reste refusé ; et un `select` direct sur `invitations` rend zéro ligne.

### Hypothèses posées, à confirmer par `supabase-dev`

- La conservation actuelle (`prune_retention` : `invitations` purgées **30 jours après
  expiration**) laisse largement la place à l'affichage « expirée ». Aucun changement de rétention
  n'est demandé.
- Une invitation adressée à quelqu'un dont l'appartenance à cette même caserne est `disabled` est
  rendue comme les autres : elle est réelle et actionnable, et c'est au serveur de dire à
  l'acceptation ce qu'il en fait.
- Si le JWT porte une revendication de vérification d'adresse, l'exiger. Avec la connexion par code
  à six chiffres elle est vraie par construction, mais l'écrire coûte une ligne.

## 7. La décision centrale : rejoindre ouvre l'écran d'invitation

**« Aucune caserne » n'accepte pas sur place. Le bouton ouvre l'écran d'invitation, qui accepte.**

Le geste part bien d'ici — le critère d'acceptation dit « depuis cet écran, sans relire son
courriel », et il est tenu : une touche, pas de courriel, pas de jeton à retrouver. Ce qui est
décidé, c'est **où s'affiche le résultat**. Il s'affiche là où il s'affiche déjà, pour trois
raisons dont la dernière est décisive.

**1. Les six fins de parcours existent déjà, et une seule fois.** Expirée, déjà utilisée, mauvaise
adresse, caserne suspendue, réseau, incident : chacune a son titre, sa phrase et sa sortie dans
`ErreurAcceptation` (006 § 5.3). Accepter sur place obligerait à les redessiner sur
`/aucune-caserne`, c'est-à-dire à entretenir deux vocabulaires pour les mêmes échecs — exactement
ce que le ticket 047 a refusé pour les résultats d'invitation.

**2. Ce qui suit l'acceptation n'est pas l'accueil.** C'est « Bienvenue », qui nomme la caserne —
la première fois que la personne apprend où elle entre —, puis `/bienvenue/profil`, puis le guide.
Toute cette chaîne pend sous l'écran d'invitation.

**3. Le routeur emporte la décision.** Dès que l'appartenance apparaît, `redirectionAuth` passe en
`EtatAuth.connecte`, et cette branche renvoie **tout ce qui est sur `/aucune-caserne` vers
`/accueil`**. Une acceptation jouée sur place serait donc arrachée de l'écran à la seconde où elle
réussit : pas de « Bienvenue », pas de nom de caserne, pas de profil, pas de guide — un saut sec
vers un accueil que personne n'a demandé. La règle qui protège `/invite/` de ce sort
(`chemin.startsWith(AppRoutes.prefixeInvitation) → null`) est précisément ce qu'il faut réemployer.

### Ce que ça demande au code, et rien de plus

- **Une route sans jeton**, nommée en français comme ses voisines : `/rejoindre/:invitation`, qui
  porte l'identifiant d'invitation (pas le jeton). Elle doit être **exemptée de la redirection
  `sansCaserne`** au même titre que `/invite/`, sinon elle est renvoyée sur « Aucune caserne » avant
  d'avoir affiché quoi que ce soit. C'est la seule modification du routeur, et elle est
  load-bearing.
- **Le même écran**, `InvitationScreen`, avec une seconde entrée : par jeton (le lien du courriel)
  ou par identifiant (cet écran). Même contrôleur d'acceptation, mêmes états, même page de
  bienvenue. Pas de second écran, pas de second modèle de résultat.
- **La même Edge Function**, `accept-invitation`. Proposition de contrat, à trancher dans
  `docs/SCHEMA.md` : le corps accepte `{ "invitation_id": "<uuid>" }` **en alternative** à
  `{ "token": "…" }`, exactement l'un des deux. Le serveur résout la ligne par son identifiant,
  **confronte `lower(email)` à l'adresse de la session avant toute autre chose**, puis poursuit son
  chemin habituel. Les codes, les statuts HTTP et les phrases françaises ne changent pas. Le jeton
  est lu côté serveur et n'apparaît nulle part dans la réponse.
- **Pourquoi c'est au moins aussi sûr que le jeton.** Le jeton est un porteur **transférable** : il
  circule par courriel, il se copie. Une session dont l'adresse a été vérifiée par un code à six
  chiffres envoyé à cette adresse ne se transfère pas. Et le contrôle d'adresse que fait déjà
  `accept_invitation` (`p_email`) reste en place : il est doublé, pas remplacé.

## 8. Interaction et layout

- **Compact d'abord.** Une colonne bornée à 420 dp (la mesure d'`EcranSimple` et d'`EmptyState`),
  centrée, défilante dès que l'échelle de texte ou le clavier mange la hauteur. Pas de disposition
  grand écran particulière : cet écran s'adresse à un pompier sur son téléphone, et sur un écran de
  bureau la même colonne centrée est la bonne réponse.
- **Zones sûres** : `SafeArea`, et le bouton « Se déconnecter » ne passe jamais sous la barre de
  geste iOS.
- **Cibles** : 48 dp partout, 8 dp entre deux boutons voisins.
- **Rien n'est porté par la couleur seule** : le badge est marque + icône + libellé, la bannière
  porte son icône, l'expiration est dite par un mot avant de l'être par un gris.
- **Mouvement : aucun ajouté.** Le passage du squelette au contenu est un changement de contenu, pas
  une transition. Pas d'entrée en fondu, pas de liste qui se déplie.
- **Accessibilité.** Le titre est le premier élément lu. La phrase d'attente et la bannière d'échec
  sont des `liveRegion`. Chaque ligne d'invitation est un `Semantics(container: true)` qui exclut
  ses enfants et se lit comme une phrase : « CS Maurepas, invitation envoyée par Marc Dubois,
  en attente, expire le 5 octobre ». Le bouton porte déjà le nom de la caserne dans son libellé
  visible, donc rien à ajouter en `semanticsLabel`. Un bouton inerte annonce sa raison.
- **Chiffres tabulaires** pour les dates, comme partout ailleurs.
- **Fraîcheur.** Lecture à l'ouverture de l'écran, au retour de l'application au premier plan, au
  retour depuis `/rejoindre`, et sur « Réessayer ». Pas de temps réel : `invitations` n'entre pas
  dans le canal Realtime, et c'est une décision de sécurité écrite (`docs/SCHEMA.md § 9`).

## 9. Widgets Flutter

**À réutiliser tels quels** — aucune variante, aucune copie :

| Composant | Emploi |
|---|---|
| `EmptyState` (`lib/core/widgets/`) | Les deux branches inchangées : « Aucune caserne », « Accès désactivé » |
| `AppBanner` | Échec de recherche (`erreur`), hors ligne (`hors-ligne`), rappel de désactivation (`information`) |
| `PrimaryButton` | « Rejoindre … », variantes `primaire` / `secondaire`, états chargement et inerte |
| `StatusBadge.attribution` | `propose` → « En attente », `annule` → « Expirée ». Le même badge que l'écran « Membres » |
| `AppDivider` | Entre deux invitations. Un filet, jamais une carte |
| `LoadingSkeleton`, `SkeletonLigne`, `SkeletonBloc` | L'attente de la recherche |
| `AttenteInvitation`, `TexteInvitation` (`features/invitation/presentation/widgets/`) | L'attente et les paragraphes, déjà écrits pour ce parcours |
| `BoutonDeconnexion` (`core/session/deconnexion.dart`) | La sortie du bas, inchangée |
| `formaterDateLongue` (`core/l10n/format_date.dart`) | Les échéances |
| `AppSpacing`, `AppTouch` | L'espacement et les cibles |

**À créer**, et dans la feature, pas dans `core/` — un widget à un seul appelant n'est pas un
composant de système :

- `lib/features/invitation/presentation/widgets/ligne_invitation_recue.dart` —
  `LigneInvitationRecue` : la ligne réglée décrite au § 5.2, avec son instant de référence injecté
  (`maintenant`) comme `LigneInvitation`, pour que « expirée » se teste.
- `lib/features/invitation/presentation/widgets/panneau_invitations_recues.dart` — le titre, le
  cadrage, la liste, l'attente et l'échec. C'est lui que `AucuneCaserneScreen` place dans sa zone
  centrale.
- `lib/features/invitation/domain/invitation_recue.dart` — le modèle des cinq champs du § 6, avec
  `depuisJson` tolérant (un champ manquant n'est pas une exception, c'est une ligne ignorée).
- `lib/features/invitation/domain/invitation_providers.dart` — un `FutureProvider` d'invitations
  reçues, invalidable. **Aucune écriture sur l'appareil**, donc rien à brancher dans
  `deconnexion.dart` ; l'écrire dans le commentaire du provider pour que la prochaine lecture ne
  cherche pas.
- `lib/features/invitation/data/invitation_repository.dart` — l'appel `rpc`, à ajouter au dépôt
  existant.

**Modifié** : `AucuneCaserneScreen` (l'aiguillage des cinq formes, meuble inchangé),
`app_router.dart` (la route `/rejoindre/:invitation`), `auth_redirection.dart` (l'exemption),
`invitation_screen.dart` (la seconde entrée).

**Ce qu'un développeur ne doit pas inventer ici.** Une carte ombrée par invitation, un écran de
succès sur `/aucune-caserne`, un compte à rebours avant expiration, une icône décorative en haut du
panneau, un second jeu de messages d'échec d'acceptation, un cache local de la liste, un bouton
« Demander une invitation », ou un `CircularProgressIndicator` au milieu de l'écran.

## 10. Textes

Tous dans `AppStrings`, tutoiement, phrases courtes. Les existants sont réemployés **tels quels** :
`aucuneCaserneTitre`, `aucuneCaserneTexte`, `caserneDesactiveeTitre`, `caserneDesactiveeTexte`,
`invitationEnAttente`, `invitationExpiree`, `invitationExpireLe`, `invitationExpireeDepuis`,
`invitationParQui`, `actionReessayer`, `erreurReseauTitre`.

Nouveaux, sous un intitulé « Invitation en attente sur “Aucune caserne” (ticket 051) » :

| Clé proposée | Texte |
|---|---|
| `aucuneCaserneTitreNeutre` | « Ton compte » |
| `aucuneCaserneVerification` | « Vérification de tes invitations… » |
| `aucuneCaserneFait` | « Ton compte existe, mais il n'est rattaché à aucune caserne. » |
| `invitationsRecuesTitre(int n)` | `n <= 1` → « Une caserne t'attend » ; sinon « $n casernes t'attendent » |
| `invitationsRecuesIntro(String email, int n)` | `n <= 1` → « Une invitation a été envoyée à $email. Rejoins-la ici, sans ouvrir ton courriel. » ; sinon « $n invitations ont été envoyées à $email. Choisis la caserne que tu rejoins. » |
| `invitationsExpireesTitre(int n)` | `n <= 1` → « Ton invitation a expiré » ; sinon « Tes invitations ont expiré » |
| `invitationRejoindre(String caserne)` | « Rejoindre $caserne » |
| `invitationAcceptationEnCours` | « Acceptation en cours… » *(raison d'un bouton inerte)* |
| `invitationExpireeDemander(String inviteur)` | « Demande à $inviteur de te la renvoyer. » |
| `invitationExpireeDemanderSansNom` | « Demande à l'administrateur de la caserne de te la renvoyer. » |
| `invitationsRecuesEchec` | « Impossible de vérifier tes invitations. Tu en as peut-être une en attente. » |
| `invitationsRecuesHorsLigne` | « Hors ligne. Impossible de vérifier tes invitations. » |
| `invitationRecueSemantique({caserne, inviteur, etat, echeance})` | « $caserne, invitation envoyée par $inviteur, $etat, $echeance » |

## 11. Checklist `craft-floor` (Impeccable)

- [x] **Contraste** — aucune couleur nouvelle : rôles M3 de `DESIGN.md`, texte secondaire en
  `on-surface-variant` (≥ 4.5:1 sur `surface` dans les deux thèmes, vérifié au ticket 004).
- [x] **Profondeur** — aucune ombre. Filets et crans de surface, comme tout le produit.
- [x] **Espacement** — rythme 4/8 dp d'`AppSpacing` ; plus d'air au-dessus d'un titre qu'en dessous ;
  8 dp entre deux cibles.
- [x] **Typographie** — échelle existante, colonne à 420 dp donc mesure de lecture tenue ; le nom de
  caserne le plus long s'enroule, rien ne se tronque.
- [x] **Mouvement** — aucun moment animé ajouté, et c'est le bon choix : le seul « moment » de cet
  écran est l'arrivée d'une réponse, et elle se dit par du texte.
- [x] **États** — attente, échec, hors ligne, expiré, vide, plusieurs, désactivé, bouton en
  chargement, bouton inerte avec sa raison. Le survol n'existe pas ici (PWA tactile) ; le focus
  clavier reste celui du thème.
- [x] **Surfaces du navigateur** — rien de nouveau : anneau de focus, sélection et chiffres
  tabulaires viennent du thème du ticket 004.
- [x] **Copie** — les boutons nomment leur action **et la caserne** ; chaque échec nomme le problème
  et la sortie ; le seul état vide qui reste est celui qui était déjà correct.
- [x] **Couverture** — les quatre demandes du ticket : proposer l'invitation (§ 5.2), décider la
  route de sécurité (§ 6), garder le texte juste quand il n'y a rien (§ 5.4), distinguer l'expirée
  (§ 5.3).

**Refus tenus** : pas de carte à icône + titre + texte comme structure de page ; pas de modale ;
pas de numéros d'étape ; pas de surtitre ; pas d'emoji ; pas de dégradé ; pas de bordure colorée
épaisse ; pas de squelette qui se substitue au contenu réel.

## 12. Checklist app mobile (ui-ux-pro-max)

**Visuel** — [x] aucune emoji-icône, Material Icons uniquement, une seule graisse · [x] jetons
sémantiques du thème, aucune couleur en dur · [x] l'état pressé ne déplace rien (le bouton en
chargement garde sa largeur).

**Interaction** — [x] retour tactile par les états standards de `PrimaryButton` · [x] cibles ≥ 48 dp
(la recommandation Android, retenue partout dans ce produit, couvre les 44 pt iOS) · [x] états
inertes visibles **et expliqués à côté** · [x] ordre de lecture du lecteur d'écran = ordre visuel ·
[x] aucun geste en conflit : le geste retour iOS et le bouton retour du navigateur restent ceux du
routeur, chaque forme étant une route nommée.

**Clair / sombre** — [x] les deux thèmes sont ceux du ticket 004, aucun composant nouveau ne peint
hors des rôles ; à vérifier au montage, dans les deux thèmes, pas déduit d'un seul.

**Layout** — [x] `SafeArea` en haut et en bas, le bouton du bas ne passe pas sous la barre de geste ·
[x] le contenu défile sans passer sous un élément fixe · [x] à vérifier sur petit téléphone, grand
téléphone et bureau · [x] rythme 4/8 dp · [x] mesure de lecture bornée à 420 dp.

**Accessibilité** — [x] les icônes des badges sont décoratives et exclues, leur libellé est visible ·
[x] chaque contrôle a un nom accessible qui nomme la caserne · [x] la couleur n'est jamais seule ·
[x] Reduce Motion sans objet (aucune animation) et grandes tailles de texte prises en charge par le
défilement · [ ] *sans objet* : pas de champ de saisie, pas de formulaire, pas de rotation
automatique, pas de glissement sur cet écran.

## 13. Décisions ouvertes

Aucune ne bloque l'implémentation ; elles appartiennent à `supabase-dev` et s'écrivent dans
`docs/SCHEMA.md`.

1. **Signature exacte** de `my_pending_invitations()` : `setof` d'un type composite ou un `jsonb`.
   Le brief fixe les cinq champs et leurs raisons, pas la mécanique.
2. **Entrée par identifiant dans `accept-invitation`** : deuxième champ du corps (proposé) ou
   deuxième fonction SQL `accept_invitation_by_id`. Une seule exigence : une Edge Function, un seul
   vocabulaire de codes, aucun jeton sur le réseau.
3. **Nom de la route** `/rejoindre/:invitation` — français, cohérent avec `/aucune-caserne` et
   `/bienvenue/…`. `flutter-dev` peut proposer mieux ; la contrainte, elle, ne bouge pas :
   l'exemption dans `redirectionAuth`.
