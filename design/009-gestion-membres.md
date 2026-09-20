# 009 — Gestion des membres par l'admin

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web
mobile-first**, Material 3, une seule apparence sur toutes les cibles. `DESIGN.md` gagne sur ce
brief pour toute valeur de token, et `design/006-invitations-onboarding.md` décrit l'écran auquel
ce ticket ajoute.

**Ce ticket complète un écran livré, il ne le réécrit pas.** « Membres » existe depuis le ticket
006 : deux listes, inviter, renvoyer, annuler. Le présent brief ne décrit que ce qui s'ajoute, et
ce que ces ajouts déplacent.

---

## 1. Job et audience

**Le chef de centre, debout, une minute.** Il connaît déjà ses pompiers ; ce qu'il vient chercher
ici, c'est une décision sur **une** personne. Trois occasions, toujours les mêmes :

1. Quelqu'un part du centre — mutation, arrêt long, fin d'engagement. Il faut lui couper l'accès
   sans effacer son historique (`docs/PRD.md § 6.2`).
2. Il se décharge d'une partie du travail : il nomme un adjoint administrateur.
3. Il regarde qui ne saisit plus ses disponibilités. C'est le premier signe d'un membre décroché,
   et c'est la question qu'il pose à l'écran avant de relancer quelqu'un de vive voix.

Le hors-périmètre du 006 est levé ici, avec ses protections : « modifier le rôle d'un membre, le
désactiver, le retirer : ce sont des écritures d'administration à part ».

**Ce qui se joue.** Une désactivation ratée, c'est un ancien membre qui reçoit encore des
propositions d'astreinte. Une rétrogradation de trop, c'est **une caserne sans administrateur** :
plus personne ne publie de planning, et personne dans l'application ne peut réparer. C'est le seul
acte irréversible de l'écran, et il doit être impossible plutôt que déconseillé.

## 2. Résultat et preuve

**Résultat.** Un admin trouve un membre parmi cent, voit en une ligne son rôle, son statut et sa
dernière saisie, et agit sur lui sans jamais pouvoir décapiter sa propre caserne.

**Preuves, vérifiables.**

- Le dernier administrateur actif ne peut être ni rétrogradé ni désactivé : l'action est **inerte
  avec sa raison écrite à côté** dans l'interface, et refusée par la base si on la contourne.
- Un admin ne peut ni se rétrograder ni se désactiver lui-même, même règle, même double barrière.
- Un membre désactivé ne voit plus la caserne à sa prochaine connexion : il arrive sur « Accès
  désactivé », avec le nom de la caserne quand il peut encore le lire (§ 5.4) et de quoi se
  déconnecter.
- Chaque membre affiche sa dernière saisie de disponibilités, ou dit qu'il n'en a aucune.
- La recherche filtre sur le nom **et** sur l'adresse, sans accent ni casse.
- Chaque cible tactile ≥ 48 dp, chaque état lisible en niveaux de gris.

## 3. Direction retenue

**La ligne reste la ligne ; l'action est au bout.** On n'ajoute ni carte, ni accordéon, ni second
écran par membre. Le registre garde ses lignes réglées : on leur ajoute une troisième ligne de
texte (la dernière saisie), un marqueur de statut quand il y a quelque chose à signaler, et **un
bouton « ⋮ » de 48 dp** qui ouvre une feuille de bas d'écran. `DESIGN.md § Points de rupture` :
« Toute action de menu contextuel a un équivalent visible (bouton « ⋮ » de 48 dp) », et « sur
téléphone, dans une feuille de bas d'écran avec le geste retour ».

**Les refus sont montrés avant d'être tentés.** Un garde-fou qui ne se manifeste qu'après le geste
apprend au chef de centre que l'application est capricieuse. Dans la feuille, l'action impossible
reste **visible, inerte, avec sa phrase** — `DESIGN.md § Do` : « Expliquer pourquoi un contrôle est
désactivé, à côté du contrôle ». Le message d'erreur du serveur existe quand même : il est le
filet, pas la pédagogie.

**Le statut « désactivé » est un fait gris, pas une alarme.** `DESIGN.md § Do` : « Traiter
"verrouillé", "suspendu", "annulé" comme des faits gris ». Le marqueur est un bloc réglé à rayon 4
— marque, icône `block`, libellé — jamais rouge, jamais une pastille.

## 4. Périmètre et limites

**Dans le périmètre.** La recherche, la troisième ligne d'information (statut, rôle, dernière
saisie), la feuille d'actions d'un membre, les quatre écritures (promouvoir, rétrograder,
désactiver, réactiver), le renommage du nom affiché, les deux garde-fous dans l'interface **et**
dans la base, et l'arrivée d'un membre désactivé sur « Accès désactivé ».

**Hors périmètre, explicitement.**

- **Supprimer** un membre. L'historique n'est jamais supprimé (`docs/PRD.md § 8`) : désactiver est
  la seule sortie, et la ligne `memberships` reste.
- Le détail d'un membre (ses astreintes, ses quotas, sa charge) : ticket de la matrice admin.
- Le transfert de propriété d'une caserne, la suppression d'une caserne, le super-admin.
- Les notifications : personne n'est prévenu par courriel d'un changement de rôle. Le chef de
  centre le dit de vive voix, comme aujourd'hui.

**Limite assumée, écrite ici parce qu'elle sera constatée.** Une session déjà ouverte au moment de
la désactivation garde l'écran qu'elle a sous les yeux jusqu'au prochain chargement de
l'application : les appartenances sont relues au changement de session, pas en continu
(`core/session/session_providers.dart`). Le critère du ticket porte sur la **prochaine connexion**,
et les écritures, elles, sont refusées immédiatement par la RLS — `is_member()` exige
`status = 'active'`.

## 5. Écrans, états et textes

Tous les textes sont dans `AppStrings` ; les libellés ci-dessous sont ceux qui sont rendus.

### 5.1 « Membres » — `/admin/membres`, section « Membres de la caserne »

**En-tête.** Le compte reste une phrase, et il dit désormais les deux nombres quand il y a quelque
chose à dire : « 9 membres actifs » ou « 9 membres actifs · 1 désactivé ». Un membre désactivé
reste dans la liste : on ne réactive pas quelqu'un qu'on ne voit plus.

**Recherche.** Un champ du système (`ChampTexte`, libellé « Rechercher un membre », texte d'invite
« Nom ou adresse e-mail », icône `search` en préfixe, croix « Effacer la recherche » en suffixe dès
qu'on a tapé), posé sous l'en-tête de section dès qu'il y a au moins un membre. Filtre local, sans
requête réseau : la liste est déjà en mémoire, et un chef de centre qui tape doit voir la liste
fondre à chaque lettre. Comparaison sans accent ni casse, sur le
nom, le nom affiché et l'adresse. Le compte de la section suit le filtre : « 2 membres sur 9 ».

**La ligne d'un membre**, dans cet ordre :

1. Le nom (`titleMedium`), suivi du marqueur « Désactivé » s'il y a lieu.
2. L'adresse e-mail (`bodyMedium`, `on-surface-variant`).
3. Le rôle s'il est administrateur — icône `admin_panel_settings_outlined` de 14 dp + « Admin de
   caserne » — puis la dernière saisie : « Dispos saisies le 4 octobre 2026 » ou « Aucune saisie de
   disponibilités ».
4. Au bout, le bouton `more_vert` de 48 dp, libellé annoncé « Actions pour Marie Lefebvre ».

La dernière saisie est la **ligne de `availabilities` la plus récemment écrite** par ce membre pour
cette caserne (`updated_at`), lue par la vue `v_member_last_availability`. Ce n'est pas « la
dernière date disponible », c'est « la dernière fois qu'il a rempli son mois ».

| État | Ce qui s'affiche |
|---|---|
| Aucune saisie | « Aucune saisie de disponibilités » — un fait gris, pas un reproche |
| Recherche sans résultat | « Aucun membre ne correspond à « durand ». » + « Effacer la recherche » |
| Membre désactivé | Marqueur `block` + « Désactivé », nom et adresse inchangés |
| Après une action | Snackbar : « Marie Lefebvre administre maintenant la caserne. », etc. (§ 5.3) |

Le reste de l'écran — squelette, vide, erreur de première lecture, bannière de relecture, réservé
aux admins — est celui du 006, inchangé.

### 5.2 Feuille d'actions d'un membre

`showModalBottomSheet`, rayon `feuille` en haut, poignée de préhension, fermable par le geste
retour et par le bouton retour du navigateur. **Pas un écran** : c'est une décision de dix
secondes, sur un objet qu'on a déjà sous les yeux.

En tête, ce sur quoi on va agir : le nom, l'adresse, puis deux faits en clair — « Rôle : Admin de
caserne », « Statut : Actif », « Dispos saisies le 4 octobre 2026 ». Puis les actions, chacune une
ligne de 48 dp, icône + libellé :

| Action | Icône | Libellé |
|---|---|---|
| Renommer | `badge_outlined` | « Modifier le nom affiché » |
| Promouvoir | `admin_panel_settings_outlined` | « Nommer administrateur » |
| Rétrograder | `person_outline` | « Retirer le rôle d'administrateur » |
| Désactiver | `block` | « Désactiver l'accès » |
| Réactiver | `check_circle_outline` | « Réactiver l'accès » |

Les actions incompatibles avec l'état du membre ne sont pas affichées (on ne propose pas
« Réactiver » un membre actif). Les actions **interdites par un garde-fou** sont affichées,
inertes, avec leur raison sous le libellé, en `on-surface-variant` :

- Soi-même : « Tu ne peux pas modifier ton propre rôle ni désactiver ton accès. Demande-le à un
  autre administrateur de la caserne. »
- Dernier administrateur : « C'est le dernier administrateur actif de la caserne. Nomme un autre
  administrateur avant de retirer celui-ci. »

**Renommer** remplace le contenu de la feuille par un champ « Nom affiché » pré-rempli, un rappel
(« Ce nom remplace le prénom et le nom dans les plannings de la caserne. »), et deux sorties :
« Enregistrer le nom » et « Annuler ». Un champ vidé remet le nom du profil : « Laisse le champ
vide pour revenir au nom du profil. » Le clavier ne recouvre jamais le champ
(`isScrollControlled` + `viewInsets`).

**Désactiver** demande confirmation — c'est la seule action de l'écran qui coupe un accès, donc la
seule qui mérite d'interrompre : « Désactiver l'accès de Marie Lefebvre ? », « Elle ne verra plus
la caserne à sa prochaine connexion. Son historique d'astreintes est conservé, et tu peux la
réactiver quand tu veux. », boutons « Désactiver l'accès » (variante `danger`) et « Annuler ».
Aucune autre action ne demande de confirmation : toutes sont réversibles d'un geste et visibles
immédiatement dans la liste.

### 5.3 Les verdicts

Une action réussie relit les deux listes et l'annonce en snackbar, au passé, en nommant la
personne :

- « Marie Lefebvre administre maintenant la caserne. »
- « Marie Lefebvre n'administre plus la caserne. »
- « L'accès de Marie Lefebvre est désactivé. »
- « L'accès de Marie Lefebvre est réactivé. »
- « Nom affiché enregistré. »

Les verdicts sont écrits **sans genre** : la caserne compte des femmes et des hommes, et le
prénom ne le décide pas de façon fiable.

Un refus dit le problème **et** la sortie, dans le même bandeau d'erreur (`errorContainer`) :

| Refus | Message |
|---|---|
| Dernier admin (base) | « C'est le dernier administrateur actif de la caserne. Nomme un autre administrateur avant de retirer celui-ci. » |
| Soi-même (base) | « Tu ne peux pas modifier ton propre rôle ni désactiver ton accès. Demande-le à un autre administrateur de la caserne. » |
| Refus de la RLS | « Modification refusée par la caserne. Tu n'es peut-être plus administrateur, ou l'abonnement est suspendu. Relis la liste. » |
| Réseau / incident | « La modification n'a pas abouti. Vérifie ta connexion, puis réessaie. » |

**Une seule phrase pour « plus admin » et « abonnement suspendu », et c'est voulu.** Les deux
donnent exactement la même réponse HTTP : une politique `using` qui ne matche pas filtre la ligne
en silence, un `with check` qui échoue rend `42501`, et rien ne dit laquelle des deux conditions a
lâché. Inventer deux phrases reviendrait à deviner devant quelqu'un qui, lui, ne devine pas.

### 5.4 « Accès désactivé » — `/aucune-caserne`

Écran existant (ticket 005), inchangé dans sa forme. Deux corrections, toutes deux trouvées en
essayant le parcours contre la base locale :

1. L'appartenance affichée est **la première appartenance désactivée**, et non la première
   appartenance tout court — un compte qui aurait une ligne `invited` traînante voyait le mauvais
   nom de caserne.
2. **Le nom de la caserne peut manquer.** La politique de `stations` n'ouvre la lecture qu'aux
   membres *actifs* (`is_member`) : à la seconde où l'accès est coupé, le compte ne lit plus le
   nom de son centre, et la phrase devenait « Ton accès à  a été désactivé. ». Une variante sans
   nom est servie dans ce cas : « Ton accès à cette caserne a été désactivé. Contacte ton chef de
   centre pour le rouvrir. » On ne rouvre pas `stations` à un compte désactivé pour une question
   de cosmétique.

Titre « Accès désactivé », `BoutonDeconnexion` en bas.

## 6. Interaction et layout

- Compact d'abord : une colonne, la feuille d'actions occupe au plus 80 % de la hauteur et défile.
- Cibles : 48 dp pour le « ⋮ » et pour chaque ligne d'action, 8 dp entre deux cibles.
- Aucune information portée par la seule couleur : le marqueur « Désactivé » est marque + icône +
  libellé ; le rôle est icône + libellé.
- Mouvement : aucun ajouté. La feuille utilise l'animation Material par défaut, la liste filtrée ne
  s'anime pas — un filtre est une réduction, pas un événement.
- Accessibilité : le « ⋮ » porte le nom du membre dans son libellé annoncé ; la feuille est un
  `Semantics(namesRoute: true)` titré par le nom du membre ; le compte filtré et les verdicts sont
  des `liveRegion` ; une action inerte annonce sa raison dans son `Semantics.hint`.
- Chiffres tabulaires pour les dates, comme partout ailleurs.

## 7. Contraintes et décisions

**Fermes.**

- **Les deux garde-fous vivent dans la base**, pas seulement dans l'écran. Un déclencheur sur
  `memberships` refuse la rétrogradation ou la désactivation du dernier administrateur actif d'une
  caserne, et l'auto-rétrogradation comme l'auto-désactivation. Il laisse passer `service_role` et
  `postgres`, exactement comme `assignments_member_transition()` : les fonctions serveur
  (`accept_invitation`, migrations, cron) ne doivent pas être bloquées.
- Les écritures passent par PostgREST sous la politique `memberships_update_admin` : pas d'Edge
  Function, il n'y a qu'une table touchée et rien à garder secret.
- La dernière saisie vient de la vue `v_member_last_availability` en `security_invoker` : la RLS de
  `availabilities` s'applique telle quelle, donc un membre n'y lit que ses propres lignes.
- Un membre désactivé reste lisible par l'admin : `membres()` lit les statuts `active` **et**
  `disabled`, jamais `select *`. La politique de `profiles` a dû être élargie d'une branche pour
  les admins (migration `0010`) : sans elle, la jointure `profiles!inner` perdait la ligne et
  « Réactiver l'accès » portait sur quelqu'un d'invisible.

**Tranchées pendant le brief.**

- La recherche est **locale**. Une caserne compte quelques dizaines de membres ; une requête par
  frappe coûterait plus cher que la liste entière, et fonctionnerait moins bien hors réseau.
- Un seul badge, « Désactivé ». Pas de badge « Actif » : l'absence de marqueur est l'état normal,
  et un badge sur chaque ligne serait du bruit sur quatre-vingt-dix-neuf lignes.
- La dernière saisie est une date longue, pas un « il y a 3 mois ». Le chef de centre compare avec
  la date de clôture de la période ; un relatif l'obligerait à compter.

**Ce qu'un développeur ne doit pas inventer ici.** Un bouton « Supprimer le membre », une
confirmation sur chaque action, un badge « Actif », une carte par membre, un envoi de courriel au
membre promu, ou un affichage du nombre de jours depuis la dernière saisie.
