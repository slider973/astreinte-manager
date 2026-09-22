# 052 — Le centre de notifications n'a pas de retour — brief de design

Mode Impeccable : **Operate**. Monde visuel : le registre de garde (`DESIGN.md`).
Périmètre : la PWA. Dépend de `design/026-centre-notifications.md`, qu'il ne réécrit pas.

Ce brief ne redessine rien. Il tranche **une topologie de navigation** et l'affordance qui en
découle. Tout ce que le ticket 026 a fixé — la ligne, la marque de non-lue, les icônes par type,
le bouton « Tout marquer comme lu », les états — reste tel quel et n'est pas rouvert.

---

## 1. Job et audience

Un pompier volontaire, sur son téléphone, PWA installée en plein écran. Il consultait ses
propositions. La cloche portait « 2 ». Il l'a touchée pour savoir ce qu'il avait raté, il a lu, et
maintenant il veut **revenir à ce qu'il faisait**.

Il n'y arrive pas. Pas de flèche, pas de navigation en bas, pas de barre d'adresse — le plein
écran la supprime. Il n'a que deux sorties : fermer l'application et la rouvrir, ou toucher au
hasard. Le propriétaire du produit l'a signalé le 21 septembre 2026 avec les mots exacts d'un
utilisateur : « je ne peux pas retourner en arrière ».

Public secondaire : le même pompier, réveillé par une notification, qui ouvre le centre
**application fermée**. Il n'a pas d'écran précédent, et pourtant il doit pouvoir sortir.

Ce n'est pas un défaut d'esthétique, c'est un défaut d'issue. `PRODUCT.md` : « Sur iPhone en PWA,
respecter les zones sûres, le geste retour ». Un écran sans issue est la seule faute que le mode
Operate ne pardonne pas.

## 2. Résultat et preuve

**Résultat** : depuis chacun des cinq écrans qui portent la cloche, ouvrir le centre puis revenir
ramène **à cet écran, dans l'état où il était** — même onglet, même mois affiché, même position de
défilement, mêmes propositions dépliées.

**Preuve**, au sens d'Impeccable, en cinq gestes vérifiables sur un iPhone en PWA installée :

1. Onglet « Propositions », défilé jusqu'à la quatrième carte → cloche → flèche → la quatrième
   carte est toujours sous le pouce, et la barre du bas dit toujours « Propositions ».
2. « Mon mois » sur novembre → cloche → geste retour depuis le bord gauche → novembre, pas
   octobre.
3. Le centre ouvert par un lien profond, application fermée → une sortie **nommée** vers
   l'accueil, pas une flèche muette qui ne mène nulle part.
4. Flèche, geste retour iOS et bouton précédent du navigateur : **trois gestes, un seul
   résultat**, et **un seul cran** d'historique consommé.
5. Aucun autre écran de l'application n'enferme : l'inventaire du § 7 le dit route par route.

## 3. Direction retenue

### 3.1 Les trois options, pesées

**A. Route enfant.** Écarté. « Enfant de qui ? » est sans réponse : la cloche est portée par
`accueil`, `mois`, `propositions`, `astreintes` et `profil`, qui sont **un seul et même
emplacement** — la coquille `/` et son index d'onglet local (`AccueilScreen._destination`). Faire
du centre l'enfant de `/` rendrait bien une flèche, mais la coquille sous la pile serait
reconstruite depuis l'URL de l'enfant, laquelle ne porte pas `?onglet=` : le retour tomberait sur
« Mon mois » quel que soit l'onglet d'où l'on vient. Il faudrait recopier l'onglet et le mois dans
l'URL du centre à chaque pression de la cloche, c'est-à-dire réinventer une pile à la main. Une
route enfant résout la flèche et rate l'état.

**B. Empilement.** **Retenu.** `push` pose le centre **au-dessus** de l'écran courant sans y
toucher : le `State` de la coquille n'est ni démonté ni reconstruit, donc l'onglet, le mois et le
défilement survivent sans qu'on ait rien à sérialiser. La flèche dépile, et la pile est
exactement l'objet que le geste retour iOS et le bouton précédent du navigateur savent déjà
manipuler. C'est le mécanisme dont le produit se sert déjà pour « Inviter » et « Importer » —
sauf que ces deux-là l'obtiennent par leur place dans l'arbre, quand le centre doit l'obtenir par
le geste, parce qu'il s'ouvre depuis cinq endroits et qu'aucun n'est son parent.

**C. Destination de l'ossature `AppScaffold`.** Écarté, deux fois. D'abord `DESIGN.md
§ Navigation` fixe cinq destinations au maximum et un admin les a toutes — le ticket 026 avait
déjà tranché ce point et rien n'a changé. Ensuite, et c'est la vraie raison : une barre de
navigation ne répond pas à la question posée. Elle offre « va sur un onglet », pas « reviens où tu
étais ». Le pompier qui lisait ses propositions retomberait sur « Mon mois » après avoir choisi
une destination au jugé. On aurait remplacé une impasse par un détour.

### 3.2 La thèse

**Le centre est un détour, pas une destination.** On y va en laissant son travail ouvert derrière
soi, on en revient. Tout découle de là : la pile, la flèche, et le fait que toucher une ligne
**quitte** le détour au lieu de l'empiler (on ne revient pas au journal après avoir ouvert ce
qu'il annonçait).

### 3.3 Le mécanisme, pour que le développeur n'invente rien

- **La cloche empile.** `BoutonNotifications` passe de `context.goNamed(...)` à
  `context.pushNamed(AppRoutes.notificationsName)`.
- **Garde anti-double-poussée.** Deux touches rapprochées sur la cloche empileraient deux
  centres, donc deux flèches à presser pour sortir : la plainte d'origine, en pire. La cloche ne
  fait rien si l'emplacement courant est déjà `/notifications`.
- **L'URL doit dire la vérité.** Vérifié dans les sources de `go_router 17.5.0` installé
  (`lib/src/router.dart:340`) : `GoRouter.optionURLReflectsImperativeAPIs` vaut **`false`** par
  défaut, et `lib/src/parser.dart:233` n'utilise l'adresse de la route empilée que si ce drapeau
  est vrai. Sans lui, le centre s'afficherait pendant que la barre d'adresse resterait sur `/`, et
  un rechargement rendrait l'accueil au lieu du centre. Ce serait un écart direct à `DESIGN.md
  § Navigation` — « chaque écran est une route nommée, jamais un état local ». **Le drapeau est
  posé à `true`, une fois, au montage du routeur.**
  À savoir, pour éviter un faux diagnostic : l'entrée d'historique, elle, est poussée dans les
  deux cas — `information_provider.dart` compare aussi l'état encodé, qui change à chaque
  empilement, donc `replace` reste faux. Le bouton précédent fonctionnerait déjà sans le drapeau.
  C'est l'URL et le rechargement qui l'exigent, pas le retour.
- **La flèche est explicite, jamais devinée.** Le `leading` de la barre est construit par le
  produit (§ 9), pas laissé au `BackButton` implicite de Flutter : c'est la seule façon de
  traiter le cas de la pile vide, qui est justement celui du lien profond.
- **`onExit` est écarté.** C'est le garde-fou d'un écran qui a quelque chose à perdre — un
  formulaire à demi rempli. Le centre n'a rien à enregistrer : le marquage est optimiste et déjà
  parti (`design/026 § 2`). Poser `onExit` ici poserait une question à quelqu'un qui cherche la
  sortie. C'est l'inverse du ticket.
- **`PopScope` est écarté** pour la même raison : rien à intercepter, rien à confirmer.
- **Toucher une ligne reste un `go`.** Le centre est quitté, pas empilé sous sa destination. La
  pile redevient `[destination]`.

## 4. Périmètre et limites

**Dans le ticket :**

- la cloche empile au lieu de remplacer, sur les cinq écrans qui la portent (un seul widget) ;
- la flèche de retour du centre, ses deux formes, et le repli vers l'accueil du rôle ;
- le drapeau d'URL du routeur ;
- le même traitement pour les deux pages légales, qui sont le seul frère atteint du même défaut
  de structure (§ 7) ;
- la zone sûre basse du centre quand le bouton « Tout marquer comme lu » est absent (§ 7, ligne 3
  du tableau) ;
- l'inventaire complet des routes de premier niveau, livré dans la PR.

**Hors du ticket, et volontairement :**

- aucune modification de la ligne de notification, de la pastille, des états, des textes de
  l'écran 026 ;
- aucune destination de navigation ajoutée ou retirée ;
- aucun écran d'administration touché : ils portent tous l'ossature et sa navigation ;
- le parcours d'accueil `/bienvenue/*` ne gagne pas de retour arrière (§ 7) ;
- la déconnexion manquante de l'écran de l'éditeur : c'est un manque de fonction, pas une
  impasse de route, et il lui faut son ticket (§ 7).

**Anti-objectifs.** Pas de fil d'Ariane. Pas de titre d'écran qui nomme la provenance (« Retour à
Propositions ») : cinq provenances, cinq chaînes à traduire, et un mot de plus à lire pour un
geste qui doit être réflexe. Pas d'animation de transition propre au centre : `DESIGN.md
§ Motion` n'autorise qu'un seul moment chorégraphié dans l'application, et ce n'est pas celui-ci.

## 5. États et plages de contenu

Les états de contenu du ticket 026 sont inchangés : chargement (squelette de cinq lignes), vide,
erreur liste vide, erreur liste affichée, jusqu'à deux cents lignes virtualisées. Ce brief ajoute
**un seul axe d'état, celui de la pile**, et il est orthogonal aux autres : la sortie existe dans
les six cas.

| État de la pile | Quand | Ce qu'on montre en tête de barre |
|---|---|---|
| **Pile pleine** (cas normal) | la cloche a été pressée depuis un des cinq écrans | flèche `arrow_back` seule, 48 dp, libellé annoncé « Retour » |
| **Pile vide** | lien profond application fermée, URL collée, rechargement de la PWA, onglet restauré par le navigateur | flèche `arrow_back` **suivie du mot « Accueil »**, même position, même cible |

**La pile vide n'est pas un cas rare.** Trois chemins y mènent tous les jours : une PWA iOS
rouverte reprend sa dernière adresse ; un rechargement sur `/notifications` repart d'une pile
d'un seul écran, l'empilement n'étant pas restauré ; et le ticket 045 a mesuré ce chemin exact
(« 1 fois sur 4 pour `/notifications` ouvert par un simple membre »). C'est le deuxième état
nominal, pas une dégradation.

**Ce que « l'accueil du rôle » veut dire ici**, sans ambiguïté possible :

| Rôle | Accueil | Pourquoi |
|---|---|---|
| Membre | `/` (onglet « Mon mois ») | sa destination d'arrivée |
| Admin de caserne | `/` (onglet « Mon mois ») | un admin est d'abord un pompier ; la cloche n'existe que sur ses écrans de membre, et `redirectionAuth` le pose sur `/` |
| Éditeur du produit | sans objet | il n'est membre d'aucune caserne : `/notifications` le renvoie sur « Aucune caserne » avant d'afficher quoi que ce soit |

Il n'y a donc **qu'un seul repli**, `AppRoutes.accueilName`. Ne pas inventer de branche par rôle.

Deux états de bord à ne pas oublier :

- **la session se ferme pendant que le centre est ouvert** (déconnexion sur un téléphone prêté) :
  la redirection d'authentification reprend la main et la pile empilée disparaît avec le reste.
  C'est voulu, et la règle des caches locaux l'exige ;
- **hors ligne** : rien ne change. Le retour est de la navigation locale, il n'attend aucun
  réseau. Une flèche qui tourne avant de rendre l'écran précédent serait un défaut.

## 6. Interaction et layout

### 6.1 La barre, en compact (téléphone, PWA installée — la référence)

```
┌──────────────────────────────────────────────┐
│ ←   Notifications                         ↻  │   pile pleine
├──────────────────────────────────────────────┤
│ ← Accueil   Notifications                 ↻  │   pile vide
└──────────────────────────────────────────────┘
```

- **Position.** La sortie est toujours au même endroit, en tête de barre, sous le pouce gauche.
  Ce qui change entre les deux états est **le mot, pas la place** : un repère qui se déplace vaut
  moins qu'un repère qui s'explique.
- **« Et il le dit ».** Le ticket l'exige et une info-bulle ne le dit pas : il n'y a pas de survol
  en PWA (`DESIGN.md § Don't`). Le mot « Accueil » est donc **écrit, visible, à côté de la
  flèche**, et seulement quand la flèche ne ramène pas d'où l'on vient. Les deux états restent
  distinguables en niveaux de gris : c'est du texte, pas une couleur.
- **Cible.** 48 × 48 dp au minimum dans les deux formes, 8 dp d'écart avec le titre, 8 dp entre
  la flèche et l'action « Relire » à l'autre bout — elles ne se touchent jamais, elles sont aux
  deux extrémités.
- **Largeur du `leading`.** 56 dp en pile pleine (le défaut de Material). En pile vide, la place
  du mot est calculée à partir de l'échelle de texte, **plafonnée à 45 % de la largeur de
  l'écran**. Au-delà — échelle 200 %, téléphone étroit — le mot tombe et la flèche seule reste :
  la sortie ne disparaît jamais, son commentaire peut. Le libellé annoncé, lui, reste complet
  dans les deux cas.
- **Zone sûre haute** : celle de la barre d'application, déjà gérée par le thème. La flèche ne
  passe jamais sous l'heure du système.
- **Zone sûre basse** : la liste doit réserver `viewPadding.bottom` sous sa dernière ligne quand
  le bouton « Tout marquer comme lu » est absent — sans lui, la dernière notification passe sous
  la barre d'accueil de l'iPhone. Avec le bouton, `BarreActionsBasse` s'en charge déjà.

### 6.2 Tablette et grand écran

Rien de particulier, et c'est une décision : le centre garde sa colonne bornée à 720 dp centrée,
sa barre et sa flèche. **Pas de rail de navigation, pas de panneau latéral** — un détour n'est pas
une destination, et l'ajouter donnerait au centre l'air d'un cinquième onglet. Sur un poste fixe,
la flèche double le bouton précédent du navigateur, ce qui est exactement ce qu'on veut.

### 6.3 Les trois gestes, et comment on les vérifie en PWA

Les trois doivent produire **le même résultat** et consommer **un seul cran**.

| Geste | Chemin technique | Vérification |
|---|---|---|
| Flèche | `context.pop()`, ou `goNamed(accueil)` si `canPop()` est faux | Chrome et iPhone |
| Bouton précédent du navigateur | entrée d'historique posée par l'empilement → le routeur dépile | Chrome, barre d'adresse visible |
| Geste retour iOS (glissement depuis le bord gauche, PWA `standalone`) | Safari le traduit en retour d'historique → même chemin que ci-dessus | iPhone, PWA installée sur l'écran d'accueil |

**Protocole manuel, à joindre à la PR** (précédent : le compte rendu de mesures du ticket 042) :

1. Chrome, `flutter run -d chrome --dart-define-from-file=env/dev.json`. Aller sur l'onglet
   « Propositions », défiler, presser la cloche. **L'adresse devient `/notifications`** — si elle
   reste sur `/`, le drapeau d'URL n'est pas posé. Presser le bouton précédent : l'onglet
   « Propositions », à sa position de défilement.
2. Même chose avec la flèche. Même résultat, un seul cran.
3. Recharger la page pendant que le centre est affiché : le centre revient, en pile vide, et la
   sortie porte le mot « Accueil ».
4. iPhone, PWA installée depuis l'écran d'accueil (pas Safari) : reprendre 1 et 2 avec le
   glissement depuis le bord gauche. Vérifier que le glissement n'est pas mangé par la liste —
   elle n'a aucun geste horizontal, donc il ne doit pas l'être.
5. Les cinq écrans porteurs de la cloche, un par un. C'est le premier critère d'acceptation, il
   se vérifie cinq fois ou pas du tout.
6. Régler iOS sur « Réduire les animations » et refaire 4 : la transition devient un fondu, le
   retour reste un retour.

**Ce qu'un test automatisé peut tenir** (à écrire, sans remplacer le protocole ci-dessus) :

- la cloche empile : après la touche, `/notifications` est à l'écran **et** l'écran d'origine est
  toujours monté ;
- retour et état : onglet « Propositions » → cloche → flèche → l'onglet « Propositions » est
  rendu, et son `State` n'a pas été recréé ;
- pile vide : routeur démarré sur `/notifications`, la sortie porte le mot « Accueil », la presser
  mène à `/` ;
- double touche sur la cloche en moins d'une image : un seul centre dans la pile ;
- le retour système (`handlePopRoute`) produit le même emplacement que la flèche ;
- `destinationInterne` et le repli de `_ouvrir` restent inchangés — un test de non-régression du
  026 suffit.

## 7. La revue des frères

Inventaire complet des routes déclarées dans `lib/core/router/app_router.dart`, colonne
« impasse » au sens strict : **sur iPhone en PWA plein écran, cet écran a-t-il une sortie
visible ?**

| Route | Ouverte depuis | Ossature | Impasse ? | Ce ticket |
|---|---|---|---|---|
| `/notifications` | cloche de 5 écrans, `goNamed` | `Scaffold` nu, aucune sortie | **Oui** | **Corrigée** |
| `/legal/confidentialite`, `/legal/mentions` | `LiensLegaux` (profil, connexion), `goNamed` | `Scaffold` nu + flèche à repli fait main | Non, mais le retour **perd la provenance** : lues depuis l'onglet « Profil », elles renvoient sur « Mon mois » | **Corrigées** : `push` + la même flèche factorisée |
| `/notifications`, bas de liste | — | `Scaffold` nu sans zone sûre basse quand tout est lu | Non, mais la dernière ligne passe sous la barre d'accueil iOS | **Corrigée** (une ligne, même écran, même phrase de `PRODUCT.md`) |
| `/` | destination | `AppScaffold` | Non | — |
| `/admin/planning`, `/admin/suivi`, `/admin/membres`, `/admin/parametres`, `/admin/periodes`, `/admin/abonnement` | destination « Admin », menu de la barre, bannière de suspension | `AppScaffold` (navigation présente) | Non : la barre ou le rail ramènent aux onglets de membre | — |
| `/admin/membres/inviter`, `/admin/membres/importer` | `goNamed` depuis « Membres » | `Scaffold` nu, **mais routes enfants** : flèche implicite + bouton « Retour à la liste » | Non | — |
| `/superadmin` | aucun lien dans l'app, URL seule | `Scaffold` nu | Non au sens du ticket : c'est **l'accueil** de l'éditeur, pas un détour. **Mais il n'y a aucune déconnexion** : l'éditeur ne peut pas quitter son compte | **Non couverte.** Manque de fonction, pas de route → ticket à ouvrir, « l'éditeur ne peut pas se déconnecter » |
| `/invite/:jeton` | courriel | `EcranSimple` | Non : chaque état porte son action (« Se connecter », « Continuer », « Aller à l'accueil ») | — |
| `/bienvenue/profil`, `/guide`, `/installation`, `/notifications` (activation) | parcours d'accueil, en chaîne | `EcranSimple` | Non : chaque étape a sa sortie vers l'avant. Revenir d'une étape est impossible — c'est un assistant linéaire, assumé au ticket 006 | **Non couverte**, et rien à ouvrir : aucun pompier n'y est enfermé |
| `/install` | adresse dictée, affiche publique | `EcranSimple` + « Ouvrir l'application » | Non | — |
| `/connexion`, `/connexion/code` | parcours | `EcranSimple`, le code porte « Modifier l'adresse » | Non | — |
| `/aucune-caserne` | redirection | `Scaffold` nu + bouton de déconnexion | Non : la déconnexion **est** la sortie | — |
| `/demarrage`, `/configuration` | redirection | écrans techniques, traversés | Sans objet | — |
| `/proposals`, `/schedule/:p`, `/admin/schedule/:p`, `/availability/:p` | notifications | routes de redirection, sans écran | Sans objet | — |
| `/dev/components` | URL, builds de développement seulement | `Scaffold` nu, aucune sortie | Oui, techniquement — **absente de la production** | **Non couverte** : c'est un outil interne, et le ticket 004 l'a voulu ainsi |

**Conclusion de la revue, telle qu'elle doit figurer dans la PR** : une seule impasse réelle dans
le produit livré, `/notifications`. Deux défauts du même lignage corrigés en passant (les pages
légales, la zone sûre basse du centre). Deux constats laissés ouverts, dont un seul mérite un
ticket : la déconnexion absente de l'écran de l'éditeur.

**La cause de structure, nommée pour qu'elle ne revienne pas :** un écran atteint par `goNamed`
depuis un autre écran, déclaré au premier niveau, sans ossature de navigation, n'a par
construction aucune sortie. La règle qui en sort, et qui a sa place dans la revue de toute
nouvelle route : *un écran qui ne porte ni `AppScaffold` ni un parent dans le routeur s'ouvre par
`push` et porte une flèche à repli.*

## 8. Contraintes et décisions

### 8.1 Fermes

- La flèche existe dans les deux états de pile. Aucun écran de ce produit ne s'ouvre sans issue.
- Un seul repli : l'accueil, `/`. Pas de branche par rôle.
- La position de la sortie ne bouge jamais ; seul le mot apparaît.
- Aucune couleur ne porte la différence entre les deux états : c'est du texte.
- 48 dp de cible, 16 sp de texte, contraste hérité du thème de la barre (`onSurface` sur
  `surface`, mesuré au ticket 004).
- Les cinq écrans porteurs de la cloche partagent **un seul** widget de cloche : la correction est
  faite une fois.

### 8.2 Tranchées pendant ce brief

- **Empilement contre route enfant** : § 3.1. L'état de l'onglet tranche.
- **Le mot « Accueil » plutôt qu'une info-bulle** : il n'y a pas de survol en PWA.
- **Pas de titre de provenance dans la flèche** : cinq provenances, un geste réflexe.
- **Le drapeau d'URL du routeur** : posé, parce que `DESIGN.md § Navigation` exige qu'un écran
  soit une route nommée et qu'un rechargement doive rendre le centre.
- **La garde anti-double-poussée** : une pile de deux centres reproduirait la plainte d'origine.
- **`onExit` et `PopScope` écartés** : le centre n'a rien à protéger.

### 8.3 Ce qu'un développeur ne doit pas inventer ici

- une sixième destination de navigation ;
- une modale ou une feuille de bas d'écran pour le centre (`DESIGN.md § Don't` : une tâche qui ne
  demande ni interruption ni protection n'est pas une modale — et une feuille perdrait l'URL) ;
- une animation de transition propre à cet écran ;
- une flèche qui referme le centre **et** marque tout comme lu ;
- un message d'erreur quand la pile est vide : il n'y a pas d'erreur, il y a un autre chemin
  d'arrivée.

### 8.4 Hypothèses, à corriger si la vérification les dément

- **Le geste retour de la PWA iOS en `standalone` est un retour d'historique.** Vérifié par
  Safari, pas par nous : si le protocole du § 6.3 montre qu'il ne fait rien sur l'appareil du
  propriétaire, la flèche reste la seule sortie et il faut le noter dans la PR — le ticket est
  tenu quand même, mais le constat doit être écrit.
- **Un empilement survit à un recalcul de redirection** (`refreshListenable` s'active à chaque
  changement d'authentification). Les empilements sont enregistrés dans la liste de
  correspondances de `go_router 17.5`, donc ils devraient survivre ; une redirection **effective**
  remet la pile à plat, ce qui est le comportement voulu.

## 9. Widgets Flutter

### 9.1 Réemployés tels quels

`AppBanner`, `EmptyState`, `LoadingSkeleton`, `BarreActionsBasse`, `PrimaryButton`, `AppDivider`,
`LigneNotification`, `AppTouch.cible`, `AppSpacing.colonneMax`.

### 9.2 À créer dans `lib/core/widgets/`

**`BoutonRetour`** (`bouton_retour.dart`) — la sortie d'un écran sans ossature de navigation.

- Se place en `leading` d'un `AppBar`. Deux formes, une seule règle :
  - `context.canPop()` vrai → `BackButton` : icône `Icons.arrow_back`, cible 48 dp, libellé
    annoncé `AppStrings.actionRetour` ;
  - faux → `TextButton.icon` : `Icons.arrow_back` + `AppStrings.retourAccueil`, même hauteur,
    même couleur que la barre, libellé annoncé `AppStrings.retourAccueilSemantique`.
- Expose la largeur à donner au `leadingWidth` de la barre : 56 dp en pile pleine ; en pile vide,
  la largeur du mot selon l'échelle de texte, plafonnée à 45 % de la largeur de l'écran, au-delà
  de quoi la forme retombe sur la flèche seule.
- Paramètre unique : le nom de route de repli, `AppRoutes.accueilName` par défaut.
- Aucune couleur propre, aucune ombre, aucun fond : c'est un élément de barre.

### 9.3 À modifier

| Fichier | Changement |
|---|---|
| `features/notifications/presentation/widgets/bouton_notifications.dart` | `pushNamed` au lieu de `goNamed` ; garde anti-double-poussée |
| `features/notifications/presentation/notifications_screen.dart` | `leading: BoutonRetour(...)` + `leadingWidth` ; zone sûre basse de la liste quand la barre d'actions est absente |
| `features/legal/presentation/document_legal_screen.dart` | remplace sa flèche faite main par `BoutonRetour` (même comportement, un seul endroit) |
| `core/widgets/liens_legaux.dart` | `pushNamed` au lieu de `goNamed` : les pages légales redeviennent un détour |
| `core/router/app_router.dart` | `GoRouter.optionURLReflectsImperativeAPIs = true`, posé une fois, **avec le commentaire qui dit pourquoi** — un drapeau statique sans raison écrite se fait retirer au ticket suivant |

### 9.4 Tests attendus

Ceux du § 6.3, plus : un test du catalogue de composants (`/dev/components`) pour les deux formes
de `BoutonRetour`, à l'échelle de texte 100 % et 200 %.

## 10. Textes

Tout dans `AppStrings`, jamais dans un widget. Tutoiement du membre. Deux chaînes nouvelles, pas
une de plus.

| Clé | Texte | Emploi |
|---|---|---|
| `actionRetour` *(existe)* | « Retour » | libellé annoncé de la flèche, pile pleine |
| `retourAccueil` *(nouveau)* | « Accueil » | le mot visible à côté de la flèche, pile vide |
| `retourAccueilSemantique` *(nouveau)* | « Aller à l'accueil » | libellé annoncé de la même, pile vide |

**Rien d'autre ne change.** `centreTitre` (« Notifications »), `centreRafraichir`, `centreVideTitre`,
`centreVideTexte`, `centreErreurTexte`, `centreToutMarquerLu`, `centreCompte(...)`,
`centreNonLuesBadge(...)` restent tels que le ticket 026 les a posés. Ne pas en profiter pour
réécrire une phrase.

**Ce qu'on n'écrit pas** : « Vous ne pouvez pas revenir en arrière », « Impossible de revenir »,
« Page d'accueil ». Le premier décrit le défaut au lieu de le corriger, le deuxième annonce une
impasse, le troisième est du vocabulaire de site web dans une application installée.

---

## Checklist `craft-floor` (Impeccable)

| Point | État |
|---|---|
| Contraste | ✅ `onSurface` sur `surface` de la barre, mesuré au ticket 004. Le mot « Accueil » est du texte de barre, pas un gris inventé |
| Profondeur | ✅ Rien d'ajouté. La barre garde son filet de 1 dp, aucune ombre |
| Espacement | ✅ 8 dp entre la flèche et le titre, 8 dp entre cibles, `leadingWidth` explicite |
| Typographie | ⚠️ Le mot « Accueil » à l'échelle 200 % sur téléphone étroit : la règle de repli (flèche seule) est écrite au § 6.1, **à vérifier à la construction**, pas à supposer |
| Mouvement | ✅ Aucun moment ajouté. Le seul chorégraphié du produit reste le tampon |
| États | ✅ Pile pleine, pile vide, hors ligne, session fermée, chargement, vide, erreur : § 5 |
| Surfaces du navigateur | ✅ L'anneau de focus du thème s'applique aux deux formes ; l'historique du navigateur redevient exact grâce au drapeau d'URL |
| Copie | ✅ Chaque commande nomme son action ; aucun message d'erreur là où il n'y a pas d'erreur |
| Couverture | ✅ Les cinq critères d'acceptation du ticket ont chacun leur § : 1 → § 3/6, 2 → § 5, 3 → § 6.3, 4 → § 7, 5 → outillage |
| Refus | ✅ Pas de modale, pas de carte, pas de fil d'Ariane, pas de glyphe en guise d'icône, pas de numérotation de section décorative |

## Checklist application mobile (`ui-ux-pro-max`)

| Point | Source | État |
|---|---|---|
| Retour prévisible, état préservé | `Navigation / Back Behavior`, sévérité **critique** — « Use goBack and keep screen state », « Don't reset stack » | ✅ C'est exactement la direction retenue : `pop` sur une pile, jamais une remise à plat |
| Zones sûres | `Safe Areas / Safe Area Insets`, sévérité haute | ✅ Haute par le thème de la barre ; basse corrigée dans la liste (§ 7) |
| Conflits de gestes | `Touch / Gesture Conflicts`, sévérité haute | ✅ La liste du centre n'a aucun geste horizontal ; le glissement de bord reste au système |
| Historique et bouton précédent | `Navigation / Back Button` (web) — « Preserve navigation history », « Don't break browser back » | ✅ Une entrée d'historique par empilement, un cran par retour |
| L'URL reflète l'écran | `Navigation / Deep Linking` — « Update URL on state changes » | ✅ Drapeau d'URL posé ; un rechargement sur `/notifications` rend le centre |
| Cibles tactiles | `DESIGN.md § Cibles tactiles` | ✅ 48 dp dans les deux formes, 8 dp d'écart |
| `PopScope` plutôt que `WillPopScope` | guide Flutter, sévérité haute | ✅ Sans objet : aucun des deux n'est utilisé, et le § 3.3 dit pourquoi |
