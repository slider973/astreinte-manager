# 019 — Publication et suivi des réponses

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web**,
Material 3, une seule apparence. Ce brief **prolonge** `design/016-matrice-admin.md` et
`design/017-brouillon-attribution.md` : il occupe le dernier emplacement que le 017 a nommé et
laissé vide — `filActions`, le bouton « Publier » — et il ouvre l'écran que les liens profonds
`/admin/schedule/<AAAA-MM>` visent depuis le ticket 024 sans rien trouver.

`DESIGN.md` gagne sur ce brief pour toute valeur de token. Les écarts sont listés au § 7.3, les
écarts constatés à l'implémentation au § 9.

Sources : `docs/PRD.md § 5.4`, `§ 6.4`, `§ 7` ; `docs/SCHEMA.md § 2.8` à `§ 2.10`, `§ 4`, `§ 5`,
`§ 6`, `§ 7`, `§ 9` ; `docs/WORKFLOWS.md § 2`, `§ 3`, `§ 4`, `§ 8` ;
`supabase/functions/README.md § send-notification` ; `tickets/in-progress/019-publication-suivi.md`.

---

## 1. Job et audience

**Le chef de centre, le jeudi soir de la troisième semaine.** Le brouillon est fini. Soixante-deux
créneaux, une soixantaine d'attributions, une heure de travail. Il lui reste un geste, et c'est le
seul de tout le produit qui sort du bureau : **appuyer sur « Publier », c'est faire vibrer trente
téléphones**.

Ce que l'outil actuel lui coûte à ce moment-là, et que le produit remplace : un tableur envoyé par
courriel, trente réponses qui arrivent par SMS, par téléphone et de vive voix pendant deux semaines,
une feuille de relance tenue à la main, et jamais de certitude sur qui n'a pas répondu.

Deux publics, deux moments, un seul écran de chaque côté :

1. **Avant l'envoi** — il veut savoir ce qu'il envoie. Trois questions, toujours les mêmes :
   *reste-t-il des trous ?*, *ai-je surchargé quelqu'un ?*, *ai-je écrit contre le refus explicite
   de quelqu'un ?* Le produit les pose à sa place, une fois, au moment où elles se corrigent encore.
2. **Après l'envoi** — il veut savoir où ça en est **sans demander à personne**. La progression,
   qui a répondu quoi, qui traîne, et un bouton pour relancer ceux qui traînent.

**Le pompier, lui, n'est pas sur cet écran.** Il reçoit **une** notification — pas sept — et il
répond depuis l'écran des propositions (ticket 023). Ce ticket est la moitié administrative de
cet échange.

## 2. Résultat et preuve

**Résultat.** Le planning quitte le bureau du chef de centre en un geste réfléchi, et la boucle des
réponses se referme toute seule : quand la dernière attribution requise est acceptée, le planning
se valide sans que personne n'appuie sur rien, et tout le monde l'apprend.

**Preuve, dans l'ordre :**

1. Le chef voit ce qu'il envoie **avant** de l'envoyer, et il peut encore reculer.
2. Un pompier qui a sept créneaux reçoit **une** notification qui les résume. Pas sept.
3. À tout moment après la publication, l'écran de suivi dit en un chiffre où on en est, et en une
   liste qui manque à l'appel.
4. La validation est **un fait de la base**, pas une case qu'un humain coche : elle survient même si
   personne n'a l'application ouverte.
5. L'écran de suivi bouge tout seul quand une réponse arrive, et **rien ne bouge sous la main**.

**Ce que la base donne, et qu'il ne faut pas recalculer.** `v_schedule_progress` (migration `0018`,
livrée au ticket 017 et **lue par personne jusqu'ici**) rend, en une ligne : créneaux totaux,
créneaux couverts, attributions en attente, acceptées, refusées et **en retard**. C'est la source de
la barre de progression et des quatre compteurs. Aucun de ces nombres ne se recompte en Dart.

## 3. Direction retenue

Le monde visuel est posé et cet écran ne l'invente pas : **le registre de garde** (`DESIGN.md`).

**La thèse : publier est un envoi, pas un enregistrement.** Tout le vocabulaire de l'écran le dit.
Le bouton ne s'appelle pas « Valider » ni « Enregistrer » mais **« Publier le planning »**, et il
est suivi, dans le même souffle, du nombre de personnes qui recevront quelque chose. Le récapitulatif
qui précède n'est pas une boîte de confirmation générique : c'est **un bordereau d'expédition** —
combien de créneaux, combien de pompiers, et les trois réserves que le chef doit voir avant de
signer.

**La seconde thèse : un suivi est une liste, pas un tableau de bord.** La tentation de la catégorie
serait un écran de graphiques. Ce qu'il faut à 21 h dans une salle de garde, c'est un chiffre en
haut et **des noms en dessous** : qui a accepté, qui a refusé, qui n'a rien dit. Le seul élément
graphique de l'écran est une barre de progression, et elle ne porte **aucune** information que le
texte à côté d'elle ne porte pas déjà.

**La troisième : le retard est un fait gris, pas une alarme rouge.** Un pompier qui n'a pas répondu
en 72 h était en intervention, en vacances, ou n'a pas vu passer la notification. L'écran le dit
sans le juger — ocre d'attente, jamais vermillon — et propose **une** action : relancer.

## 4. Périmètre et limites

**Livré :** les gardes de la machine à états des plannings en base ; la publication (Edge Function
`publish-schedule`, récapitulatif, notifications groupées par membre) ; l'écran de suivi
(progression, créneaux par état, retardataires, relance) ; la validation automatique par
déclencheur ; le temps réel sur `assignments` et `schedules`.

**Pas livré, et à ne pas esquisser :**

- l'écran du membre qui répond (ticket 023) et le sien qui accepte ou refuse (ticket 019 ne montre
  que le versant admin) ;
- la réattribution après un refus (`reassign-shift`, ticket 020) : le suivi **montre** un refus, il
  ne le répare pas. Le chef repart dans la matrice ;
- les crons de relance automatique et le rapport `late_responders` aux admins (ticket 022). Ce
  ticket livre la relance **manuelle**, celle qu'on déclenche en regardant la liste ;
- la notification `schedule_all_accepted` aux administrateurs. `docs/WORKFLOWS.md § 4` — la séquence
  que ce ticket implémente — ne demande que `schedule_validated` « à tous », et les admins sont des
  membres. Le rapport propre aux admins part avec les autres rapports d'admin, au 022 ;
- la proposition automatique (018), l'export ICS, l'historique (021).

**Anti-objectifs explicites :**

- **Pas de publication partielle.** On ne publie pas « les weekends d'abord ». Un planning se publie
  entier, une fois. La modification d'un créneau publié est le ticket 020.
- **Pas de dépublication.** Aucun bouton « Revenir au brouillon », et surtout aucune transition qui
  le permettrait en base : c'est la condition d'entrée du ticket (§ 7.1).
- **Pas de blocage sur le récapitulatif.** Trois trous et deux quotas dépassés n'empêchent pas de
  publier. `docs/PRD.md § 7.4` : « L'app avertit, l'admin décide. » Un chef qui publie un mois
  incomplet sait ce qu'il fait — il complétera après les refus.
- **Pas de relance individuelle.** Un bouton par retardataire, c'est trente boutons et trente
  notifications envoyées une par une. La relance est un geste de lot, comme la publication.
- **Pas de graphique.** Ni camembert, ni courbe, ni « taux d'acceptation ».

## 5. États et plages de contenu

### 5.1 Plages réelles

| Grandeur | Minimum | Typique | Maximum retenu |
|---|---|---|---|
| Créneaux d'un planning | 56 | 60 | **62** |
| Attributions d'un planning publié | 0 | ~70 | 3 720 (absurde, rien ne l'interdit) |
| Membres destinataires d'une publication | **0** | 18 | 60 |
| Créneaux par membre | 1 | 4 | 62 |
| Créneaux non pourvus au récapitulatif | 0 | 2 | 62 |
| Membres au-delà de leur quota | 0 | 1 | 60 |
| Membres attribués hors disponibilité | 0 | 0 | 60 |
| Retardataires | 0 | 3 | 60 |
| Délai de retard (`late_report_hours`) | 1 h | 72 h | 336 h |

Trois valeurs piègent. **Zéro destinataire est légal** : on peut publier un planning sans aucune
attribution — le récapitulatif le dit en toutes lettres et le bouton reste actif, parce que publier
un mois vide, c'est en ouvrir la lecture aux membres. **Un planning à 62 créneaux et 0 requis
partout est validé dès sa publication** : le déclencheur doit s'en apercevoir sans qu'aucune réponse
n'arrive. Et **`late_report_hours` vaut 1 heure au minimum** : la liste des retardataires peut se
remplir le jour même.

### 5.2 Les états de l'écran de publication (dans la matrice)

| État | Ce qu'on voit |
|---|---|
| **Planning absent** | `filActions` est vide. Rien à publier. |
| **Brouillon** | `filActions` : `PrimaryButton` primaire **« Publier le planning »**, pleine largeur sur compact, et sous lui une `mention` : « 18 pompiers recevront une notification. » |
| **Récapitulatif ouvert** | Feuille de bas d'écran (compact/medium/expanded) ou dialogue (large) : le bordereau du § 6.2. Deux boutons : « Annuler », « Publier et notifier ». |
| **Publication en vol** | Le bouton garde son libellé, un indicateur de 20 dp le précède, la largeur ne bouge pas. **Le récapitulatif ne se ferme pas** : on ne retire pas la feuille sous le doigt d'un envoi qui dure deux secondes. |
| **Publié** | La feuille se ferme, `SnackBar` « Planning d'octobre publié : 18 pompiers notifiés. », et **l'écran de suivi s'ouvre**. La matrice passe en lecture (le 017 le prévoyait déjà, sans pouvoir l'atteindre). |
| **Échec de publication** | La feuille **reste ouverte**, bannière `erreur` en tête de feuille + « Réessayer ». Rien n'est perdu : la publication est atomique en base. |
| **Déjà publié par l'adjoint** | `SnackBar` : « Ce planning a déjà été publié. » L'écran se relit. Ce n'est pas une panne. |
| **Caserne suspendue / hors ligne** | Bouton désactivé **avec sa raison** à côté, comme partout ailleurs. |

### 5.3 Les états de l'écran de suivi

| État | Ce qu'on voit |
|---|---|
| **Chargement** | Squelette à la forme du contenu : un bloc de progression, trois lignes de créneaux. Jamais un `CircularProgressIndicator` centré. |
| **Aucune période** | `EmptyState`, « Aucun mois de saisie », action « Ouvrir un mois ». Le même qu'au 016. |
| **Planning absent pour ce mois** | `EmptyState` `campaign_outlined`, « Rien à suivre pour octobre », texte « Le planning de ce mois n'a pas encore été construit », action **« Construire le planning »** → la matrice. |
| **Planning en brouillon** | `EmptyState` `edit_note`, « Le planning d'octobre est encore en brouillon », action « Ouvrir la construction ». Le suivi d'un brouillon n'a pas de sens : rien n'est parti. |
| **Publié, réponses en cours** | La composition complète du § 6.4. |
| **Publié, tout accepté mais pas encore validé** | N'existe pas : le déclencheur valide dans la même transaction que la dernière acceptation. Si l'écran le voyait quand même (planning à 0 requis publié avant la migration), il l'afficherait tel quel sans mentir. |
| **Validé** | `StatusBadge` « Validé » avec **le tampon** — le seul moment chorégraphié de l'application (`DESIGN.md § Motion`). Bannière `information` : « Planning validé le 22 septembre. Tout le monde peut le voir. » La liste et les compteurs restent. |
| **Archivé** | Même écran, `StatusBadge` « Archivé », bouton de relance absent avec sa raison. |
| **Aucun retardataire** | Le bloc « Retardataires » **n'existe pas**. Pas de « 0 retardataire » : un bloc vide est du bruit. |
| **Relance en vol** | Bouton en chargement, libellé stable. |
| **Relance faite** | `SnackBar` « 3 pompiers relancés. » Le bloc reste : ils sont toujours en retard, ils ont juste été prévenus. `last_reminder_at` passe dans la ligne. |
| **Relance sans effet** | « Ces pompiers ont déjà été relancés dans l'heure. » — la clé de dédoublonnage a fait son travail, et le dire vaut mieux que de feindre un envoi. |
| **Direct interrompu** | `cloud_off` + « Direct interrompu », à côté de « Rafraîchir ». Identique au 017. |
| **Échec de lecture** | `EmptyState.erreur` + « Réessayer ». |

### 5.4 Ce que ces états ne font jamais

- Aucune réserve du récapitulatif ne désactive le bouton de publication.
- Aucun changement reçu en temps réel ne déplace le défilement, ne rouvre une feuille, ni n'ouvre de
  `SnackBar`. Les chiffres changent, la liste se réordonne à la prochaine lecture, c'est tout.
- Aucun état ne remplace la liste des créneaux par un message : filtre vide compris, la liste garde
  sa place et explique.

## 6. Interaction et layout

### 6.1 Le bouton « Publier », et l'endroit exact où il vit

`AppScaffold.filActions`, la barre d'actions collée en bas du contenu, **réservée pour lui depuis le
016** et laissée vide par le 017. C'est la bonne place et pour une raison : `filActions` est la seule
zone de l'ossature qui ne défile pas avec la matrice. Un bouton « Publier » perdu sous 62 colonnes
serait un bouton qu'on cherche.

```
│ [ ✉ Publier le planning ]                                  │
│ 18 pompiers recevront une notification.                    │
```

- Variante **primaire** (bloc d'encre), hauteur 52, pleine largeur sur compact, ≥ 160 dp ailleurs.
- Icône `campaign` à gauche, 20 dp — la même que le `StatusBadge` « Publié ». Deux endroits, un
  glyphe, aucune ambiguïté.
- La `mention` sous le bouton compte **les membres**, pas les attributions : c'est le nombre de
  téléphones qui vont sonner, et c'est la seule grandeur que le chef ait besoin de sentir.
- Désactivé ⇒ sa raison à côté (`DESIGN.md § Buttons`).

### 6.2 Le récapitulatif — un bordereau, pas une boîte de dialogue

**Feuille de bas d'écran** en compact, medium et expanded ; **dialogue** en large. C'est la seule
exception du produit à « pas de modale pour une tâche qui ne demande ni interruption ni
protection » — et elle est méritée : publier est irréversible et sort de l'application.

```
┌──────────────────────────────────────────────┐
│ Publier le planning d'octobre                │
│                                              │
│  62      18        4                         │
│ créneaux pompiers  weekends                  │
│                                              │
│ ── À vérifier avant d'envoyer ─────────────  │
│ ⚠ 3 créneaux ne sont pourvus par personne    │
│   ven. 3 nuit · sam. 11 jour · dim. 26 nuit  │
│                                              │
│ ⚠ 1 pompier au-delà de son quota             │
│   Marie L. — 5 astreintes pour un plafond de 4│
│                                              │
│ ⚠ 2 pompiers attribués hors disponibilité    │
│   Thomas M. — sam. 11 nuit                   │
│   Émilie R. — mar. 14 jour                   │
│                                              │
│ Chaque pompier recevra une seule notification│
│ listant tous ses créneaux.                   │
│                                              │
│ [ Annuler ]        [ Publier et notifier ]   │
└──────────────────────────────────────────────┘
```

**Trois blocs de compteurs en tête** (`CountStat`, chiffres mono tabulaires) : créneaux du planning,
pompiers destinataires, unités de weekend attribuées. Ils disent l'ampleur avant les réserves.

**Les trois réserves, toujours dans le même ordre**, et chacune absente quand elle est vide :

| Réserve | Icône | Ce qu'elle liste | Encre |
|---|---|---|---|
| Créneaux non pourvus | `report_problem_outlined` | jusqu'à 6 créneaux, puis « et 9 autres » | `etat-attente` sur `etat-attente-fond` |
| Membres au-delà du quota | `person_alert` → **`warning_amber`** (voir § 7.3) | nom + « n astreintes pour un plafond de m » | idem |
| Membres hors disponibilité | `event_busy` | nom + ses créneaux forcés | idem |

**Aucune des trois n'est rouge**, et c'est une décision : ce ne sont pas des erreurs, ce sont des
décisions que le chef a prises et qu'on lui remet sous les yeux. Le vermillon est réservé à
« absent, refusé, cassé » (`DESIGN.md`).

**Quand il n'y a aucune réserve**, le bloc « À vérifier » disparaît entièrement et une ligne le
remplace : `task_alt` + « Tous les créneaux sont pourvus, aucun quota dépassé, aucune attribution
forcée. » Un récapitulatif silencieux ferait douter qu'il ait regardé.

**La dernière phrase est la promesse du ticket**, écrite noir sur blanc dans la feuille :
« Chaque pompier recevra une seule notification listant tous ses créneaux. » C'est le critère
d'acceptation, et le chef doit pouvoir le lire avant de le croire.

**Le bouton d'action s'appelle « Publier et notifier »**, pas « Confirmer ». Un libellé de
confirmation nomme l'action, jamais l'accord (`DESIGN.md § Do's`).

### 6.3 Les créneaux d'un membre, dans la notification

C'est l'endroit où ce ticket touche le pompier, et il n'a qu'un geste à faire : **grouper**.
`send-notification` sait le faire depuis le ticket 025, son auteur a décrit la forme exacte de
l'appel (`supabase/functions/README.md`), et ce brief ne réinvente rien :

```jsonc
{
  "type": "assignment_proposed",
  "station_id": "<uuid>",
  "payload": { "period": "2026-10" },
  "recipients": [
    { "user_id": "<uuid>", "payload": { "shifts": [
        { "date": "2026-10-03", "slot": "night", "assignment_id": "<uuid>" },
        { "date": "2026-10-11", "slot": "day",   "assignment_id": "<uuid>" }
    ] } }
  ]
}
```

**Le regroupement se fait en SQL, pas en TypeScript.** `publish_schedule` rend déjà **une entrée par
membre**, créneaux triés. `send-notification` regroupe de nouveau — c'est sa promesse et elle est
testée chez elle — mais la fonction SQL ne lui envoie pas soixante-dix entrées à fusionner : elle
lui en envoie dix-huit. Deux raisons, et aucune n'est la performance : le groupement devient
**testable par `scripts/test_rls.sh`**, qui tourne en CI là où les Edge Functions ne sont pas
joignables ; et la réponse rendue à l'admin (« 18 pompiers notifiés ») vient du même comptage que
l'envoi, jamais d'un second.

### 6.4 L'écran de suivi — composition

Route **`/admin/suivi?mois=AAAA-MM`**, quatrième écran de la destination « Admin », au même niveau
que « Membres », « Paramètres » et « Mois de saisie ». C'est la cible du lien public
`/admin/schedule/<AAAA-MM>` (`docs/WORKFLOWS.md § 8`), qui retombait jusqu'ici sur les périodes
faute de mieux.

```
┌ rail ┬────────────────────────────────────────────────────────┐
│      │ Suivi du planning       [membres][…][↻]                │
│      ├────────────────────────────────────────────────────────┤
│      │ (bannière, au plus une)                                │
│      ├────────────────────────────────────────────────────────┤
│      │ [Octobre 2026 ▾]   ⬤ Publié    ⟳ Direct               │
│      ├────────────────────────────────────────────────────────┤
│      │ ┌ Progression ────────────────────────────────────────┐│
│      │ │ ████████████████████░░░░░░░░  42 réponses sur 70    ││
│      │ │                                                     ││
│      │ │   28        42        6         58/62               ││
│      │ │ en attente acceptées refusées  créneaux pourvus      ││
│      │ └─────────────────────────────────────────────────────┘│
│      │ ┌ Retardataires (3) ──────────────────────────────────┐│
│      │ │ Sans réponse depuis plus de 72 h.                   ││
│      │ │ Marie L.    2 créneaux · proposé il y a 4 jours     ││
│      │ │ Thomas M.   1 créneau  · proposé il y a 3 jours     ││
│      │ │ Émilie R.   1 créneau  · proposé il y a 3 jours     ││
│      │ │            [ Relancer maintenant ]                  ││
│      │ └─────────────────────────────────────────────────────┘│
│      │ [Tous 62] [En attente 28] [Acceptés 42] [Refusés 6]…   │
│      │ ── jeu. 2 octobre ────────────────────────────────────  │
│      │  ☀ Jour  1/1   ✓ Marie L. — accepté                    │
│      │  🌙 Nuit  0/1   ⚠ personne                              │
│      │ ── ven. 3 octobre ────────────────────────────────────  │
│      │  ☀ Jour  1/2   ⏳ Thomas M. — en attente depuis 3 j     │
│      │                ✗ Lucas B. — refusé : « en formation »  │
└──────┴────────────────────────────────────────────────────────┘
```

**Une colonne, du général au particulier.** Le chef lit de haut en bas et s'arrête où il veut. Sur
`large`, la colonne est centrée et bornée à 1440 comme partout (`AppScaffold`). **Aucun panneau
latéral** : il n'y a rien à ouvrir ici, tout est déjà déplié.

### 6.5 Le bloc de progression

Un bloc réglé (filet 1 dp `outline-variant`, rayon 8, **pas d'ombre**).

- **La barre** : `LinearProgressIndicator`, hauteur 8, rayon `case` (4), piste
  `surface-container-high`, remplissage `primary` — **l'encre, pas une couleur d'état**. Une barre
  qui verdirait à 100 % ajouterait une quatrième sémantique de vert à un système qui en a déjà
  deux (« disponible », « accepté »).
- **Le texte qui la double** : « 42 réponses sur 70 attendues ». La barre ne porte **aucune**
  information que cette phrase ne porte pas. C'est la règle « jamais la couleur seule » appliquée à
  une forme : jamais la longueur seule.
- **Le dénominateur est le nombre d'attributions actives**, pas le nombre de créneaux : ce sont des
  réponses de personnes qu'on compte, pas des cases. `assignments_pending + _accepted + _declined`,
  les trois colonnes de `v_schedule_progress`.
- **Quatre `CountStat`** en dessous, dans l'ordre de l'action : *en attente* (ce qui reste à faire),
  *acceptées*, *refusées*, *créneaux pourvus* (`shifts_filled` / `shifts_total`, la seule fraction
  du bloc).
- **`shifts_filled` compte les attributions actives**, pas les acceptations. C'est ce que la vue
  fait, c'est écrit dans `docs/SCHEMA.md § 6`, et l'écran ne réinterprète pas : un créneau dont
  l'unique attribution est refusée **redevient non pourvu**, et c'est exactement ce que le chef doit
  voir.
- **`Semantics(liveRegion: true)`** sur la phrase de progression : quand le temps réel la fait
  changer, un lecteur d'écran l'annonce. C'est le seul `liveRegion` de l'écran — quatre compteurs
  qui s'annoncent à chaque réponse seraient inécoutables.

### 6.6 Le bloc des retardataires

- **Existe seulement s'il y en a.** Zéro retardataire ⇒ pas de bloc.
- Titre « Retardataires (3) », sous-titre « Sans réponse depuis plus de 72 h. » — **le délai réel de
  la caserne**, lu dans `settings.late_report_hours`, jamais un 72 écrit en dur.
- Une ligne par membre, 56 dp : nom en `corps`, puis en `mention` « 2 créneaux · proposé il y a
  4 jours ». Le nombre de créneaux d'abord : c'est ce qui dit l'enjeu.
- Une ligne relancée dans l'heure porte en plus « relancé il y a 20 min » : sans cela, le chef
  relance trois fois et croit que rien ne part.
- **Un seul bouton pour le bloc**, secondaire, 52 dp : **« Relancer maintenant »**. Pas un bouton
  par ligne (§ 4).
- L'icône du bloc est `schedule` (l'ocre d'attente), **jamais** `warning` ni `error`.

### 6.7 La liste des créneaux par état

**Des filtres en `FilterChip`, pas des onglets.** Cinq états, et le chef veut souvent en voir deux à
la fois (« en attente » + « non pourvu » = ce qui reste à traiter). Des onglets forceraient un
choix exclusif ; des puces filtrantes laissent le choix et affichent leur compte.

| Puce | Compte | Ce qu'elle garde |
|---|---|---|
| **Tous** | 62 | tous les créneaux |
| **En attente** | 28 | créneaux portant au moins une attribution `proposed` |
| **Acceptés** | 42 | … au moins une `accepted` |
| **Refusés** | 6 | … au moins une `declined` |
| **Non pourvus** | 4 | créneaux dont les attributions actives < `required_count` |

- Les puces ne sont pas exclusives entre elles ; « Tous » les désélectionne toutes.
- Le compte est **dans la puce**, en mono tabulaire. Une puce à 0 reste visible et **désactivée
  avec sa raison** en info-bulle : la faire disparaître ferait sauter les autres sous le doigt.
- **La liste garde toujours sa place.** Un filtre qui ne rend rien affiche une ligne d'explication
  et le bouton « Tout afficher », jamais un écran vide.

**Une journée = un groupe**, en-tête `titre-bloc` collant (`jeu. 2 octobre`), weekend et jours
fériés marqués comme dans la grille du mois (fond `surface-dim`, nom en gras, `Icons.star`).
Sous l'en-tête, une ligne par créneau :

```
☀ Jour   1/2   ⏳ Thomas M. — en attente depuis 3 j
               ✗ Lucas B. — refusé : « en formation »
```

- **La fraction reprend celle du 017** (`1/2`, mono tabulaire) : même grammaire, même signification,
  le chef ne réapprend rien.
- Un créneau **non pourvu et sans personne** porte la ligne « personne », hachurée — troisième
  emploi des hachures, déjà acté au 017 (§ 7.3 du 017).
- Chaque attribution porte son `StatusBadge` d'attribution : `hourglass_top` en attente,
  `task_alt` accepté, `cancel` refusé, `block` annulé. **Marque + icône + libellé, couleur en
  quatrième**, comme partout.
- **Le motif de refus est affiché quand il existe**, entre guillemets français, sur la même ligne.
  C'est l'information la plus utile de tout l'écran : elle dit au chef s'il doit chercher quelqu'un
  d'autre ou attendre.
- **Virtualisation obligatoire** : `ListView.builder` sur les journées, jamais une `Column` de 62
  groupes. La liste peut porter 3 720 lignes dans le pire cas.
- Les lignes **ne sont pas cliquables**. Il n'y a rien à ouvrir : la réattribution est le ticket 020.
  Un élément qui a l'air cliquable et ne fait rien est pire qu'un élément inerte.

### 6.8 Le temps réel

**Deux tables, une seule discipline.** `assignments` était déjà dans la publication depuis le 017 ;
`schedules` y entre ici, parce que la validation automatique est un `update` sur `schedules` que
personne ne déclenche depuis cet écran (§ 7.2).

**Ce que le temps réel fait :** les compteurs changent, la barre bouge, une attribution passe de
« en attente » à « accepté » à sa place dans la liste, le `StatusBadge` du planning passe à
« Validé » **avec le tampon**.

**Ce qu'il ne fait jamais :** déplacer le défilement, ouvrir un `SnackBar` par événement, réordonner
la liste sous la main. Trente réponses en dix minutes produiraient trente notifications à l'écran ;
le signal est déjà dans les chiffres.

**Une exception, et une seule : le passage à « Validé ».** C'est l'aboutissement du mois, c'est
l'unique moment chorégraphié du système de design, et il mérite son tampon de 180 ms plus une
bannière `information` persistante. Ce n'est pas un événement de plus : c'est **le** événement.

**L'état du canal est affiché**, comme au 017 : `sync` + « Direct », ou `cloud_off` + « Direct
interrompu » avec « Rafraîchir » à un pixel.

### 6.9 Détails de facture

- **Cibles 48 dp** partout sur cet écran : il n'y a aucune densité dense ici, et il se consulte au
  téléphone autant qu'au poste.
- **Chiffres tabulaires** sur tous les compteurs, toutes les fractions, tous les délais.
- **Les durées sont relatives et arrondies** : « il y a 3 jours », « il y a 4 h », « à l'instant ».
  Une date absolue (`2026-09-18 21:04`) oblige à calculer ; le chef veut savoir si c'est vieux.
  La date exacte reste dans le `tooltip` et dans la sémantique.
- **Séparation par filet**, jamais par ombre. Les blocs ne s'imbriquent pas.
- **Toutes les chaînes dans `AppStrings`**, aucune en dur dans un widget.

## 7. Contraintes et décisions

### 7.1 La condition d'entrée : la machine à états n'était gardée par rien

Relevé en revue du ticket 017, et c'est le premier travail de ce ticket. Deux trous, deux gardes.

**Trou n° 1 — la transition libre.** `docs/WORKFLOWS.md § 2` décrit cinq transitions et rien en base
ne les imposait : `schedules_update_admin` laisse un admin écrire n'importe quel statut, y compris
`published → draft`. Enchaîné avec la politique de suppression d'attribution du 017 — réservée au
brouillon — l'exploit tenait en deux écritures : je ramène le planning en brouillon, je supprime
l'attribution qu'un pompier a déjà reçue, je republie. La règle produit « l'historique n'est jamais
supprimé » (`PRD § 7.6`) ne tenait qu'à la discipline des écrans.

**Garde :** `schedules_guard_transition`, `before update` sur `schedules`.

| Depuis \ vers | `draft` | `published` | `validated` | `archived` |
|---|---|---|---|---|
| `draft` | = | **oui** | non | non |
| `published` | **non** | = | **oui** | **oui** |
| `validated` | **non** | **oui** | = | **oui** |
| `archived` | **non** | non | non | = |

Tout le reste lève `schedule_invalid_transition`. Le déclencheur gèle en outre `station_id` et
`period_id` (`schedule_key_immutable`), comme `periods_guard_transition` gèle la clé d'un mois, et
il tient les deux horodatages :

- `published_at` est posé à la **première** publication et **jamais réécrit** : un retour de
  `validated` vers `published` (une modification de créneau, ticket 020) ne réécrit pas l'histoire ;
- `validated_at` est posé à la validation et **effacé** au retour en `published` : un planning qui
  n'est plus validé n'a pas de date de validation.

**`security invoker`, et la règle vaut aussi pour le rôle de service.** C'est la même position que
`periods_guard_transition` : une machine à états est une propriété du domaine, pas une règle
d'interface. `publish-schedule` fait `draft → published`, le déclencheur d'auto-validation fait
`published → validated`, le cron d'archivage fait `* → archived` : les trois sont dans le tableau.
Une écriture serveur qui voudrait en sortir est un bogue, et il doit s'entendre.

**Trou n° 2 — la suppression du planning, et la cascade.** `schedules_delete_admin` laissait
supprimer un planning à n'importe quel statut. Supprimer un planning publié, c'est supprimer ses
créneaux et **toutes ses attributions** par cascade : l'historique disparaît sans laisser de trace,
et l'exploit est plus court que le premier. Pire : `periods` cascade vers `schedules`, donc
supprimer le **mois** emportait le planning publié par la bande — et **une suppression en cascade ne
consulte aucune politique RLS**.

**Garde, et elle est double** :

1. la politique `schedules_delete_admin` est restreinte à `status = 'draft'` ;
2. un déclencheur `schedules_guard_suppression`, `before delete`, refuse la suppression d'un planning
   qui n'est pas en brouillon (`schedule_delete_published`). **C'est lui qui attrape la cascade** :
   les actions d'intégrité référentielle ne consultent pas les politiques, mais elles **déclenchent
   les triggers de ligne** de la table enfant. Supprimer une période dont le planning est publié
   échoue donc, par la bonne erreur.

La politique seule ne suffisait pas ; le déclencheur seul suffirait, mais la politique reste, parce
qu'un refus par politique donne une erreur plus lisible qu'un refus par exception et parce que le
§ 4 de `docs/SCHEMA.md` décrit les droits table par table.

### 7.2 Ce que la base garantit, et ce que l'écran doit en faire

- **`proposed_at` est renseigné par la publication, jamais par un client.** En brouillon il est nul,
  et c'est ce qui fait qu'un brouillon n'est jamais « en retard » (`v_schedule_progress`) et que les
  crons de relance l'ignorent (`WORKFLOWS § 3`).
- **La publication est atomique.** Statut, horodatages et audit dans **une** transaction plpgsql
  (`publish_schedule`). Un échec ne laisse pas la moitié des attributions horodatées. L'envoi des
  notifications, lui, est **après** : il ne peut pas annuler une publication déjà faite, et une
  notification perdue se rattrape (file, relance), alors qu'une publication à moitié faite ne se
  rattrape pas.
- **`assignments_member_transition` (migration `0008`) tient déjà la réponse du membre** : un membre
  ne passe que de `proposed` à `accepted` ou `declined`, sur ses propres lignes, et `responded_at`
  est posé par la base. Ce ticket n'y touche pas — il en dépend.
- **La validation se juge sur les acceptations seules**, jamais sur `shifts_filled`. Deux questions,
  deux chiffres (`docs/SCHEMA.md § 6`). `schedule_auto_validate` compte `count(accepted) >=
  required_count` pour **chaque** créneau du planning.
- **La validation ne se déclenche qu'une fois.** L'`update ... where status = 'published' returning`
  arbitre la course : deux acceptations simultanées qui voient toutes deux le planning complet ne
  produisent qu'une ligne rendue, donc **une** salve de notifications. Compter sur l'ordre d'arrivée
  aurait donné deux « Planning validé » à soixante personnes.
- **Aucune colonne inventée.** `schedules`, `shifts`, `assignments` sont celles du § 2.8 au § 2.10.
- **`v_schedule_progress` n'est pas retouchée.** Elle a été livrée au 017 avec ses six chiffres ;
  ce ticket la lit, il ne la modifie pas.

**`schedules` entre dans `supabase_realtime`**, et les trois vérifications du 017 § 7.2 sont
refaites table par table, parce que c'est la règle :

1. **Aucun `grant` de colonne restrictif** sur `schedules` : ce que `authenticated` lit par `select`,
   il peut le recevoir ici. Les huit colonnes sont des identifiants, un statut et des dates ; aucune
   n'est un porteur de droits, contrairement à `invitations.token`.
2. **Le filtrage ligne à ligne suffit** : `schedules_select_member_published` ne donne un planning à
   un membre que si `status <> 'draft'`. Un brouillon ne part donc à personne, **y compris par ce
   canal** — et c'est l'événement `draft → published` lui-même qui ouvre la porte, ce qui est
   exactement le comportement voulu.
3. **L'identité de réplique reste `default`.** Une suppression ne diffuse que la clé primaire. Et
   depuis ce ticket, une suppression de planning publié n'existe plus du tout (§ 7.1).

### 7.3 Écarts à `DESIGN.md` et aux briefs 016 et 017, à reporter dans la PR

| Point | Ce que disaient les documents | Ce que fait ce brief | Pourquoi |
|---|---|---|---|
| Modale | « pas de modale pour une tâche qui ne demande ni interruption ni protection » | le récapitulatif est une **feuille** sous 1200 dp et un **dialogue** en large | Publier est irréversible et sort de l'application. C'est la définition même d'une tâche qui demande protection, et le 017 avait déjà ouvert cette porte pour l'attribution hors disponibilité. |
| Barre de progression | non traitée dans `DESIGN.md § Components` | `LinearProgressIndicator` 8 dp, rayon `case`, remplissage `primary` | Le système n'a pas de composant de progression parce qu'aucun écran n'en avait besoin. Celui-ci en a besoin **une fois**, et il le prend en encre, pas en couleur d'état : la couleur reste réservée à l'information. |
| Onglets | `DESIGN.md` n'en parle pas ; le produit n'en a aucun | **refusés** au profit de `FilterChip` | Le chef veut « en attente » **et** « non pourvus » ensemble. Des onglets l'interdiraient. |
| `CountStat` | quota d'un membre, totaux de la matrice | employé pour les quatre compteurs du suivi et les trois du récapitulatif | Même objet, même grammaire. `plafondAttendu: false` pour les totaux sans plafond, comme au 011. |
| Destinations de navigation | cinq au maximum, « Admin » est une destination | le suivi est un **écran** de la destination « Admin », atteint par la barre d'application | Cinquième écran admin, aucune destination de plus. La barre d'application replie ses liens en menu nommé sur compact, comme au 016. |
| Hachures | « absent », « mois verrouillé », puis « personne » (017) | même troisième emploi, sur la ligne « personne » d'un créneau non pourvu | Aucune sémantique nouvelle : c'est le vide, exactement comme au 017. |
| Tampon (`DESIGN.md § Motion`) | « quand une proposition passe à Accepté ou qu'un planning passe à Validé » | **la seconde moitié de la phrase est enfin implémentée** | Ce n'est pas un écart, c'est l'exécution d'une réservation. |

### 7.4 Décisions tranchées pendant ce brief

1. **La machine à états se garde en base, pas dans les écrans** (§ 7.1). C'est la condition d'entrée
   et elle passe avant le reste.
2. **La suppression d'un planning publié est impossible, cascade comprise** — par un déclencheur, le
   seul mécanisme que la cascade consulte.
3. **Le regroupement des notifications se fait en SQL** (§ 6.3), pour être testé là où la CI tourne.
4. **La publication est atomique ; l'envoi vient après et ne peut pas la défaire.**
5. **Le récapitulatif avertit et ne bloque jamais.** Trois réserves, jamais rouges.
6. **La relance est un geste de lot**, sur les retardataires tels que `v_schedule_progress` les
   définit — une seule définition du retard dans tout le produit.
7. **La relance est idempotente à l'heure** : `p_dedupe_key` porte l'heure courante, un double clic
   ne coûte rien et l'écran le dit.
8. **`schedule_validated` part à tous les membres actifs** ; `schedule_all_accepted` attend le 022.
9. **Le suivi n'a pas de panneau latéral et ses lignes ne sont pas cliquables** : il n'y a rien à
   ouvrir tant que la réattribution n'existe pas.
10. **Le lien public `/admin/schedule/<AAAA-MM>` pointe enfin sur un écran réel.** Une seule ligne
    de `destination_push.dart` change, comme le ticket 024 l'avait prévu.

### 7.5 Ce qu'un développeur ne doit pas inventer ici

- Aucun bouton « Revenir au brouillon », aucune dépublication, aucune suppression d'attribution
  publiée.
- Aucun écran de réponse pour le membre, aucune réattribution, aucune proposition automatique.
- Aucun recomptage en Dart de ce que `v_schedule_progress` rend déjà.
- Aucune notification envoyée depuis le client : tout passe par `publish-schedule` (clé de service)
  ou par `notify(...)` (base).
- Aucun statut d'attribution écrit par l'écran d'administration.
- Aucune chaîne en dur : tout passe par `AppStrings`.

### 7.6 Décisions ouvertes

- **Le nombre de destinataires affiché sous le bouton** est compté sur les attributions chargées à
  l'écran. Si l'adjoint attribue quelqu'un pendant que le récapitulatif est ouvert, le chiffre de la
  feuille peut différer d'une unité de celui de la réponse. La réponse du serveur gagne, et c'est
  elle qu'annonce le `SnackBar`.
- **La relance ne distingue pas les canaux.** Elle part avec les canaux par défaut
  d'`assignment_reminder` (push puis courriel de repli). Le second palier « courriel à 48 h » est un
  cron du ticket 022.
- **Le suivi ne montre pas les attributions `replaced`.** Elles n'existeront qu'au ticket 020 ; la
  lecture les accepte et les affiche comme « annulées » plutôt que de les ignorer, mais l'écran ne
  leur consacre ni filtre ni libellé propre tant qu'elles ne sont pas produites.

## 8. Widgets Flutter

### 8.1 Réemployés tels quels

| Composant | Emploi |
|---|---|
| `AppScaffold` (`filActions`) | le bouton « Publier », à la place réservée par le 016 |
| `AppBanner` | `erreur`, `hors-ligne`, `lecture-seule`, `information` (planning validé) |
| `StatusBadge` | état du planning (avec `tampon: true` pour « Validé »), état de chaque attribution |
| `CountStat` | les quatre compteurs du suivi, les trois du récapitulatif |
| `EmptyState` | planning absent, planning en brouillon, filtre sans résultat, erreur |
| `PrimaryButton` | « Publier le planning », « Publier et notifier », « Relancer maintenant » |
| `Hachures` | la ligne « personne » d'un créneau non pourvu |
| `AppDivider`, `EnteteSection` | séparation et titres des blocs |
| `LoadingSkeleton` | le squelette du suivi |

### 8.2 À créer

`lib/features/planning/domain/` :

- **`recapitulatif_publication.dart` — `RecapitulatifPublication`** : le bordereau, **fonction
  pure** construite depuis le `PlanningMois` et les lignes de matrice déjà chargées. Aucune requête.
- **`suivi_planning.dart`** : `SuiviPlanning`, `AttributionSuivi`, `ProgressionPlanning`,
  `FiltreSuivi`.
- **`suivi_providers.dart`** : le contrôleur du suivi et ses dérivés mémorisés.

`lib/features/planning/data/suivi_repository.dart` : lecture du suivi, `publish-schedule`,
`remind_schedule`, canal temps réel des deux tables.

`lib/features/planning/presentation/` :

- **`suivi_screen.dart`** ;
- **`widgets/bloc_progression.dart`**, **`widgets/bloc_retardataires.dart`**,
  **`widgets/filtres_suivi.dart`**, **`widgets/journee_suivi.dart`**,
  **`widgets/squelette_suivi.dart`** ;
- **`widgets/recapitulatif_publication.dart`** : la feuille / le dialogue, sur le modèle de
  `confirmation_hors_dispo.dart`.

Aucun nouveau composant dans `lib/core/widgets/` : la barre de progression est un
`LinearProgressIndicator` thémé, pas un composant du système.

## 9. Écarts d'implémentation (ticket 019)

Écrits après coup, comme le veut la convention du projet : ce document reste normatif, et ces
lignes sont désormais la référence.

| Point | Ce que disait ce brief | Ce que fait le code | Pourquoi |
|---|---|---|---|
| Icône de la réserve « quota » (§ 6.2) | `person_alert` | `warning_amber` | `person_alert` n'existe pas dans le jeu Material embarqué. `warning_amber` est déjà l'icône de l'avertissement de quota sur la ligne de candidat du 017 : deux endroits, un glyphe. |
| Retardataires : « relancé il y a 20 min » (§ 6.6) | sur chaque ligne | livré, et **le bouton reste actif** | Désactiver le bouton pendant une heure cacherait la raison. Le dédoublonnage est côté base ; l'écran dit ce qui s'est passé au lieu d'interdire le geste. |
| Filtre « Non pourvus » (§ 6.7) | une puce parmi cinq | livrée, et **elle est la seule non exclusive avec les autres par nature** : un créneau non pourvu peut porter une attribution en attente | Aucune exclusivité n'a été imposée ; les puces se cumulent en union, ce qui est la sémantique attendue de « ce qui reste à traiter ». |
| Groupe de journée collant (§ 6.7) | en-tête `titre-bloc` collant | en-tête non collant | `ListView.builder` + `SliverPersistentHeader` par journée aurait demandé de convertir la page entière en `CustomScrollView` pour un gain de repérage nul sur une liste où chaque ligne porte déjà sa date en sémantique. |
| `schedules` en temps réel (§ 6.8) | deux tables, un canal | **un seul canal Supabase**, deux souscriptions `postgres_changes` | Un canal par table doublait le coût de connexion pour la même information. Le tri par caserne reste côté client, comme au 017. |
| Notification de validation | « tous les membres actifs » | tous les membres **actifs**, admins compris, en une salve groupée | Conforme. Noté ici parce que l'admin reçoit donc « Planning d'octobre validé » comme les autres : c'est voulu, il n'a pas déclenché la transition. |
