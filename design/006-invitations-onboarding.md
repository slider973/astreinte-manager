# 006 — Invitations et onboarding des membres

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web
mobile-first**, Material 3, une seule apparence sur toutes les cibles. `DESIGN.md` gagne sur ce
brief pour toute valeur de token.

**Écrit après le code, et il faut le dire.** Le déroulé du projet veut ce brief avant
l'implémentation ; il a été sauté au lancement du ticket. Ce document décrit donc les écrans tels
qu'ils ont été livrés, pour que `pr-reviewer` ait une référence et que les tickets suivants
héritent d'un vocabulaire écrit. Les décisions qu'il consigne ont été prises pendant le code, pas
avant.

---

## 1. Job et audience

**Qui arrive, et dans quel état.**

1. **Le chef de centre, assis, cinq minutes.** Il vient de recevoir la liste des pompiers de son
   centre et veut les faire entrer. Il a des adresses e-mail dans un tableur ou un SMS. Il veut
   coller, envoyer, et savoir **quelles adresses sont parties**. Il revient plus tard voir qui a
   rejoint.
2. **La recrue, dehors, deux minutes.** Elle reçoit un courriel, appuie sur un lien depuis son
   téléphone. Elle ne sait pas ce qu'est Astreinte SP, n'a pas de compte, et n'a rien à installer
   pour l'instant. Si quoi que ce soit échoue, elle n'a personne sous la main : chaque impasse doit
   nommer la sortie.

**Ce qui se joue.** Une invitation perdue, c'est un pompier qui n'apparaît jamais dans le planning,
donc une garde non couverte. Un lien qui tombe sur un écran muet, c'est un abandon définitif : on
ne recommence pas une inscription qu'on n'a pas demandée.

## 2. Résultat et preuve

**Résultat.** Un admin peut faire entrer vingt pompiers en un envoi et suivre, adresse par adresse,
ce qui s'est passé. Un invité passe du courriel à l'accueil de l'application sans jamais rencontrer
un écran qui ne dit rien.

**Preuves, vérifiables.**

- Un envoi de lot affiche autant de verdicts que d'adresses, jamais un verdict unique.
- Les six fins de parcours du lien (acceptée, expirée, déjà utilisée, mauvaise adresse, caserne
  suspendue, incident) ont chacune un titre, une phrase et une sortie.
- L'aide à l'installation ne s'affiche pas deux fois, ni en mode autonome.
- Chaque cible tactile ≥ 48 dp, chaque état lisible en niveaux de gris.

## 3. Direction retenue

**Un registre d'entrée, pas un tunnel d'inscription.** Le ton reste celui du système : listes
réglées séparées par un filet, blocs sans ombre, états portés par marque + icône + libellé. Aucun
écran de célébration, aucune illustration : l'arrivée dans une caserne est un acte administratif
qu'on veut voir aboutir, pas une fête.

**Deux ossatures seulement.**

- `AppScaffold` pour l'écran « Membres » : c'est une destination de premier niveau, elle garde la
  navigation.
- `EcranSimple` (promu depuis `features/auth` au même ticket) pour tout le reste : invitation,
  profil, guide, installation. Quelqu'un qui n'est pas encore entré dans la caserne n'a pas le
  droit d'avoir la barre de navigation sous les yeux.

## 4. Périmètre et limites

**Dans le périmètre.** Écran « Membres » (liste + invitations en attente + renvoi + annulation),
formulaire d'invitation en route fille, route `/invite/:jeton`, complément de profil, guide de
trois écrans, aide « Ajouter à l'écran d'accueil ».

**Hors périmètre, explicitement.** Modifier le rôle d'un membre, le désactiver, le retirer : ce
sont des écritures d'administration à part, avec leurs propres protections (ticket ultérieur). Le
reste du profil (photo, préférences, notifications) appartient au ticket 007. Le lien d'invitation
n'est jamais montré à l'admin : le jeton ne sort que par courriel.

## 5. Écrans, états et textes

Tous les textes sont dans `AppStrings` ; les libellés ci-dessous sont ceux qui sont rendus.

### 5.1 « Membres » — `/admin/membres`

Barre : titre « Membres », action « Relire la liste » (icône `refresh`). Bouton principal en fil
d'actions, pleine largeur : **« Inviter des pompiers »**.

Contenu, dans cet ordre : une phrase de cadrage, la section **« Membres de la caserne »** avec son
compte (« 9 membres actifs »), une ligne par membre (nom, puis adresse · rôle si admin, marqueur
`admin_panel_settings` à droite), puis la section **« Invitations en attente »** avec son compte.
Listes virtualisées, lignes séparées par le filet, jamais des cartes.

Une invitation : l'adresse en titre, un badge d'état et l'échéance en dessous, deux actions de
48 dp à droite — `refresh` (« Renvoyer l'invitation à … ») et `delete_outline` (« Annuler
l'invitation de … »), libellés annoncés, jamais accessibles par le seul survol. Le badge est
`attente` (« En attente ») ou `annulé` (« Expirée ») : gris pour un fait, jamais rouge.

| État | Ce qui s'affiche |
|---|---|
| Chargement | Squelette à la forme de la liste, jamais une roue |
| Vide | « Aucun membre » + la piste : inviter avec une adresse e-mail |
| Sans invitation en attente | La section reste, avec une phrase grise : « Aucune invitation en attente. Les invitations acceptées rejoignent la liste des membres. » |
| Erreur de première lecture | `EmptyState.erreur` + « Réessayer » |
| Erreur de relecture, liste déjà affichée | Bannière `erreur` + « Réessayer ». On ne vide pas une page juste pour annoncer un échec |
| Non-admin | « Cet écran est réservé aux administrateurs de la caserne. » |
| Après une action | Snackbar : « Invitation renvoyée. », « Invitation annulée. », ou le motif d'échec |

**Fraîcheur.** Pas de temps réel (`docs/SCHEMA.md § 9`) : relecture à l'ouverture de l'écran, au
retour de l'application au premier plan, et après chaque action. L'écart est écrit sous le critère
d'acceptation du ticket.

### 5.2 « Inviter des pompiers » — `/admin/membres/inviter`

Route fille, barre avec retour : le bouton du navigateur ramène à la liste. **Pas une modale** —
rien ici ne demande d'interrompre ni de protéger.

Formulaire : champ multiligne « Adresses e-mail » (une par ligne, ou séparées par des virgules),
choix exclusif « Rôle dans la caserne » (Membre / Admin de caserne), rappel neutre « Vingt adresses
au maximum par envoi. ». Bouton « Envoyer les invitations ».

Refus avant tout appel réseau, sous le champ : adresse incomplète nommée (« Adresse incomplète :
… »), saisie vide, plus de vingt adresses (le message dit combien et quoi faire).

Après envoi, le même écran devient un compte rendu : une ligne de résumé annoncée (« 2 invitations
envoyées, 1 échec. »), puis **« Résultat par adresse »**, une ligne par adresse avec son icône, son
statut — « Invitée », « Renvoyée », « Échec » — et le motif en français. Un courriel qui n'est pas
parti n'est **pas** un échec : icône `schedule_send`, statut inchangé, et la phrase « Invitation
créée, mais le courriel n'est pas parti. Renvoie-la, ou transmets le lien toi-même. » Les refus qui
portent sur la requête entière (caserne suspendue, plus admin) s'affichent en bannière `erreur`.

Sorties : « Réessayer les adresses en échec » (repose les seules adresses fautives dans le champ)
et « Revenir aux membres ».

### 5.3 Invitation — `/invite/:jeton`

**Le lien ne porte que le jeton** : ni l'adresse invitée, ni le nom de la caserne. Un lien transféré
ne révèle donc rien, et rien n'est affiché de la caserne avant que le serveur ait confronté
l'adresse de la session à celle de l'invitation.

| État | Titre | Corps et sortie |
|---|---|---|
| Déconnecté | « Ton invitation » | « Entre l'adresse e-mail qui a reçu cette invitation… » + « Me connecter pour accepter » |
| Vérification | « Ton invitation » | « Vérification du lien… » + squelette |
| Acceptée | « Bienvenue » | « Tu fais maintenant partie de <caserne>. », « Invitation envoyée par <inviteur>. » + « Continuer » |
| Expirée | « Invitation expirée » | La phrase + « Écris à l'administrateur de <caserne> pour en recevoir une nouvelle. » |
| Déjà utilisée | « Invitation déjà utilisée » | La phrase + « Continuer » (la caserne l'attend déjà) |
| Mauvaise adresse | « Autre adresse » | Les deux adresses, **l'invitée masquée par le serveur** + « Se déconnecter » |
| Caserne suspendue | « Caserne suspendue » | La phrase + contact du chef de centre |
| Réseau / incident | « Pas de connexion » / « Ça n'a pas marché » | « Réessayer » |

**La séquence.** Lien → cet écran → connexion par code (celle du ticket 005, réutilisée telle
quelle : l'adresse n'est pas pré-remplie, le lien ne la porte pas) → **retour automatique** sur
l'invitation dès que la session s'ouvre → acceptation sans clic. Le retour est fait par le routeur,
qui garde le jeton en mémoire ; il n'est jamais écrit dans le stockage du navigateur.

### 5.4 Complément de profil — `/bienvenue/profil`

« Ton profil ». Trois champs : Prénom, Nom, « Téléphone (facultatif) » — le caractère facultatif est
dans le libellé, pas dans une note. Chaque champ vide obligatoire dit quoi faire (« Écris ton
prénom. »). Échec d'écriture : bannière `erreur` + « Réessayer ». Bouton « Enregistrer et
continuer ».

### 5.5 Guide — `/bienvenue/guide`

« Prise en main », trois écrans, pas un de plus, **toujours passable** (« Passer le guide »). Repère
de progression écrit, pas des points : « Étape 1 sur 3 », annoncé. Une icône Material de 48 dp, un
titre, trois lignes : dire ses disponibilités, répondre aux propositions, lire le planning du
centre. Boutons « Suivant », puis « C'est parti » à la dernière étape. Le guide ne revient jamais :
le repère est posé à la sortie, par la fin comme par le passage.

### 5.6 Ajouter à l'écran d'accueil — `/bienvenue/installation`

Ne s'affiche **pas** si l'application tourne déjà en mode autonome, ni sur un navigateur dont on ne
connaît pas la procédure (navigateur de bureau, navigateur tiers sur iOS : trois gestes faux sont
pires que le silence). Une seule fois.

Sur iPhone, une bannière `attention` — un fait, pas une panne : « Sur iPhone, les notifications
n'existent que pour une application installée. », et l'intro insiste : sans installation, pas de
proposition d'astreinte. Puis « Trois gestes », numérotés dans un petit bloc réglé, avec les
libellés réels de Safari (« Partager », « Sur l'écran d'accueil », « Ajouter ») ou de Chrome (menu
à trois points, « Ajouter à l'écran d'accueil », « Installer »). Sorties : « C'est fait » et « Plus
tard » — les deux posent le repère, aucune ne ment sur ce qui s'est passé.

## 6. Interaction et layout

- Compact (téléphone) d'abord : une colonne, bouton principal pleine largeur en bas, listes
  virtualisées. `EcranSimple` borne la colonne à 420 dp ; le formulaire d'invitation à 720.
- Cibles : 48 dp partout, 8 dp entre les deux actions d'une invitation.
- Aucune information portée par la seule couleur : badge = marque + icône + libellé.
- Mouvement : aucun ajouté. Le guide glisse d'une page à l'autre en `surface` (240 ms), rien de
  plus.
- Accessibilité : chaque action d'invitation porte l'adresse dans son libellé annoncé (« Renvoyer
  l'invitation à recrue@exemple.fr ») ; le résumé d'envoi et les erreurs sont des `liveRegion` ;
  les étapes d'installation sont annoncées numérotées.

## 7. Contraintes et décisions

**Fermes.**

- Le jeton d'invitation n'est jamais affiché, ni lu par une requête client : la colonne est hors du
  grant de select. Les requêtes énumèrent leurs colonnes.
- Les écritures passent par les Edge Functions, jamais par les fonctions SQL, réservées au service
  role.
- Le routeur est en **stratégie de dièse** : le lien envoyé doit être `/#/invite/{token}`
  (`APP_INVITE_PATH`).

**Tranchées pendant le code.**

- Un envoi de lot rend compte **par adresse** plutôt que par un verdict global : c'est la seule
  forme qui dit la vérité quand deux adresses sur trois passent.
- L'acceptation ne saute pas directement au profil : un écran « Bienvenue » nomme la caserne, parce
  que c'est la première fois que l'invité apprend où il entre.
- L'annulation d'une invitation ne demande pas confirmation : l'acte est réversible d'un renvoi, et
  une modale pour ça serait du bruit.

**Ce qu'un développeur ne doit pas inventer ici.** Un écran de succès animé, une carte par membre,
une pastille de notification sur la destination Admin, ou un aperçu du lien d'invitation.
