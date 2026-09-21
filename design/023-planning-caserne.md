# 023 — Vue du planning de la caserne pour les membres

> Brief de design. Suite directe de `design/027-mes-astreintes.md`, dont il reprend la décision
> d'architecture (§ 4 du 027) plutôt que d'en prendre une nouvelle. À lire après lui.
>
> Mode Impeccable : **Operate**. Plateforme : `web` (PWA mobile-first, Material 3).

## 1. La scène

Un pompier volontaire, un mardi soir, veut savoir **qui est de garde samedi**. Pas pour lui : il
sait déjà, c'est l'écran voisin. Il veut savoir s'il connaît la personne, s'il peut lui demander
d'échanger, si l'équipe de nuit tient. C'est une question de **caserne**, pas de calendrier
personnel.

Trois faits cadrent tout le reste.

1. **La réponse n'existe pas toujours.** Tant que le chef de centre n'a pas *validé* le planning,
   la base ne rend à un pompier que **ses propres** attributions. Un planning seulement *publié*
   est un planning en cours de réponse : la moitié des gens n'ont pas encore accepté, et montrer
   un état intermédiaire ferait prendre des décisions sur du sable.
2. **Elle se consulte souvent sans réseau**, exactement comme « Mes astreintes » : remise en
   béton, zone rurale, trajet. Le même cache, la même règle.
3. **Elle se lit en dix secondes**, debout, parfois avec des gants. Une grille dense de noms n'est
   pas lisible dans cette scène.

## 2. La décision d'architecture : pas d'écran séparé

Le ticket 027 a tranché : la troisième destination s'appelle **« Astreintes »** et non « Mes
astreintes », précisément pour que ce ticket-ci s'y range. La décision est reprise telle quelle.

**« Moi » et « La caserne » sont deux filtres d'une même donnée.** Même table (`assignments`),
même politique (`assignments_select_own_published` puis `assignments_select_station_validated`),
même cache, même bannière de fraîcheur. Les séparer en deux destinations demanderait à un pompier
de savoir, avant de toucher, si la réponse qu'il cherche le concerne lui ou la caserne — et la
réponse à « qui est de garde samedi » est souvent « moi et Thomas », qui traverse les deux.

Un sélecteur à deux segments est donc posé **en tête de l'écran**, au-dessus de tout le reste.

```
┌─────────────────────────────────────┐
│  Planning de la caserne        🔔 ⟳ │   barre d'application — le titre suit la portée
├─────────────────────────────────────┤
│  [✓ La caserne]  [👥 Moi        ]   │   portée — toujours présent
├─────────────────────────────────────┤
│         ‹   Octobre 2026   ›        │   mois — publiés seulement
├─────────────────────────────────────┤
│  …                                  │
```

### Ce que le sélecteur ne fait pas

**Il ne s'ajoute pas à la bascule « Liste » / « Calendrier ».** Deux rangées de boutons empilées
coûteraient 128 dp de chrome sur un téléphone de 844, pour deux questions qui ne sont pas du même
ordre. La bascule de vue **appartient à la portée « Moi »** et reste dans son sous-arbre ; la
portée « La caserne » n'a qu'une forme, donc pas de bascule. Le chrome est le même des deux côtés :
deux rangées à gauche (portée + vue), deux rangées à droite (portée + mois).

## 3. La forme : un registre de journées, pas une grille

Le ticket dit « le calendrier du mois avec, pour chaque créneau, les noms des membres acceptés ».
**Les noms ne tiennent pas dans une case de calendrier.** Une case du calendrier de « Mes
astreintes » fait 45,7 dp de large sur un téléphone de 360 (`design/027 § 7.5`) ; « Camille G. »
en fait 68 en `corps`. Trois sorties existaient :

| Forme | Pourquoi elle est refusée / retenue |
|---|---|
| Grille 7 colonnes avec les noms dans la case | Impossible sous 500 dp. Rognés, les noms deviennent « Cam… », ce qui ne répond à aucune question. |
| Grille 7 colonnes avec un **compte** par case, noms au tap | Deux gestes pour une réponse, et le compte seul (« 2 ») ne dit pas *qui*. Ce serait une vue de couverture — le travail du chef de centre, ticket 019 — pas une vue d'équipe. |
| **Registre de journées défilant** | Retenu. Une journée = un en-tête de date + ses créneaux ; un créneau = son badge, ses heures, ses noms. Zéro geste : la réponse est dans le défilement. C'est l'idiome `§ Cards / Containers` de `DESIGN.md` — registre, filets, marge — et celui du suivi du ticket 019, que les chefs de centre lisent déjà. |

Le mot « calendrier » du ticket est donc tenu par **le mois entier, jour après jour, dans
l'ordre**, ce qu'un calendrier est. Il n'est pas tenu par une grille à sept colonnes.

### Anatomie d'une journée

```
─────────────────────────────────────
★ samedi 24 octobre                      ← en-tête, fond surface-dim si weekend ou férié
─────────────────────────────────────
 ☀ Jour     07:00 → 19:00
   Marie L. · Thomas M.                  ← noms, séparés par un point médian
─────────────────────────────────────
 🌙 Nuit     19:00 → 07:00
   Personne n'est d'astreinte.           ← un trou est une information, pas un vide
─────────────────────────────────────
```

- **Le badge de créneau** est `StatusBadge.creneau`, celui du détail de « Mes astreintes ». Rien à
  réapprendre.
- **Les heures** viennent des paramètres de la caserne (`stations.settings`), jamais d'un
  7 h – 19 h en dur. Même source qu'au 027.
- **Mon nom est marqué**, et pas seulement en gras : `Icons.person` plein devant, `primary` en
  encre, et la phrase annoncée dit « toi ». Trois signaux, jamais la couleur seule.
- **Les noms sont du texte, pas des puces.** Une liste de pastilles de 28 dp pour douze personnes
  mangerait trois hauteurs d'écran. Un `Wrap` de noms séparés par « · » se lit d'un coup et
  s'enroule proprement à ×2 d'échelle de texte.
- **Un créneau sans personne** dit « Personne n'est d'astreinte. » — à ne pas confondre avec un
  créneau dont l'effectif requis est zéro, qui n'apparaît pas du tout. La distinction vient de
  `shifts.required_count`, lu avec le reste.

### Ce que le registre montre, selon l'état du planning

| Planning | Journées affichées | Pourquoi |
|---|---|---|
| **validé** | **toutes** celles du mois qui portent au moins un créneau requis | La base rend tout. Un jour sans personne est un trou réel du planning, et c'est une information qu'un pompier a le droit de lire. |
| **publié** | **seulement les créneaux où ce pompier est attribué**, et donc les journées qui en portent | La base ne rend que ses attributions. Afficher les autres avec « Personne n'est d'astreinte » serait un **mensonge de mise en page** : quelqu'un y est sûrement, on n'a simplement pas le droit de savoir qui. Le tri se fait **au créneau**, pas à la journée : un samedi où il est de nuit ne doit pas montrer son créneau de jour comme vide (vu dans Chrome, § 10). |

C'est la seule différence de forme entre les deux états, et elle est portée par le bloc suivant.

## 4. La règle de visibilité, dite à l'écran

`docs/SCHEMA.md § 4` : `assignments_select_station_validated` n'ouvre les attributions des autres
qu'`on a schedule 'validated'`. **La règle est dans la base ; l'écran ne la double pas, il
l'explique.** Aucune requête de cet écran ne contourne la RLS, aucune ne s'y substitue : ce qui
n'arrive pas n'est pas filtré côté client, il n'arrive pas.

Tant que le planning est `published`, un **bloc réglé** se pose sous la barre de mois, au-dessus du
registre — dans le contenu, pas dans `AppBanner` :

> ⏳ **Planning publié, pas encore validé**
> Tu ne vois que tes propres créneaux. Les autres noms s'afficheront quand ton chef de centre aura
> validé le planning.

**Pourquoi pas une `AppBanner`.** La bannière transverse porte un seul fait à la fois, par ordre de
priorité (`DESIGN.md § Signature Component`), et cet écran l'utilise déjà pour « Hors ligne » et
« Ces astreintes n'ont pas pu être actualisées ». Un pompier hors ligne sur un planning publié
perdrait alors exactement l'explication dont il a besoin. Et ce fait n'est pas transverse : il ne
décrit pas l'écran, il décrit **le mois affiché**. Il se déplace donc avec lui.

**Pourquoi un bloc et pas une phrase grise.** `DESIGN.md § Don't` : « pas de texte gris clair sur
fond gris ». Le bloc prend le fond `etat-attente-fond` et l'encre `etat-attente` de l'état
**proposé** — l'ocre d'attente —, avec `Icons.hourglass_top` : la même grammaire que « En attente
de ta réponse », pour la même raison (quelque chose est en cours et ne dépend pas de toi). Pas de
filet coloré à gauche : `DESIGN.md § Écarts, ticket 020` l'a déjà tranché.

**Le mot compte.** Pas « Planning incomplet », pas « Accès restreint », pas « Données
partielles » : rien n'est cassé et personne n'est puni. Le planning est *publié* — c'est un état
nommé du produit, que le pompier a vu dans sa notification — et la suite dépend de son chef de
centre. La phrase dit qui, quoi, et quand ça change.

## 5. Le sélecteur de mois

**Il ne marche pas de mois en mois : il marche de planning en planning.** Les flèches parcourent la
liste des plannings `published` ou `validated` de la caserne, dans l'ordre. Si octobre et décembre
ont un planning mais pas novembre, « › » depuis octobre mène à décembre. Un mois sans planning
n'est pas une destination : il n'y a rien à y voir, et y mener pour afficher un vide serait un
aller-retour pour rien.

- `archived` **n'est pas** une destination non plus, et ce n'est pas un choix de design : un
  planning archivé reste lisible (`schedules_select_member_published` : `status <> 'draft'`) mais
  **ses créneaux ne le sont plus** (`shifts_select_member_published` : `published` ou `validated`
  seulement). Un mois archivé n'afficherait donc rien. La base a déjà tranché.
- Une flèche sur une borne est **désactivée avec sa raison**, jamais cachée. La raison est le nom
  accessible et l'info-bulle, comme au 027 (`DESIGN.md § Écarts, ticket 027`).
- **Le mois d'ouverture** : le mois courant s'il a un planning ; sinon le premier planning à venir ;
  sinon le plus récent passé. Un pompier qui ouvre le 28 octobre pense à novembre, pas à septembre.
- Le mois choisi **survit à un aller-retour vers « Moi »** : revenir sur septembre après avoir
  regardé ses propres astreintes est un geste de consultation, pas un redémarrage.

## 6. États

| État | Ce que l'écran montre |
|---|---|
| **Chargement, rien en cache** | Le squelette, à la forme d'une journée du registre. Jamais de roue au milieu de l'écran. |
| **Chargement, cache présent** | Le mois gardé, tout de suite, et la requête passe derrière. Règle du 027 § 3. |
| **Aucun planning publié** | `EmptyState` : « Aucun planning publié. » / « Quand ton chef de centre publiera le planning du mois, tu le verras ici. » Action : « Voir mes astreintes », qui ramène à la portée « Moi ». |
| **Le mois demandé n'a plus de planning** | `EmptyState` : « Ce mois n'a plus de planning. » — le cas de course entre la liste des mois et la lecture d'un mois (planning supprimé, archivé). Action : « Réessayer ». |
| **Planning publié** | Le bloc d'attente, puis **mes** journées. Si je n'ai aucune astreinte ce mois-là : le bloc d'attente seul, suivi de « Tu n'as pas d'astreinte en octobre. » Le bloc reste, parce que c'est lui qui distingue « personne n'est de garde » de « je n'ai pas le droit de voir ». |
| **Planning validé** | Le registre complet. |
| **Hors ligne** | La bannière `hors-ligne` du 027 (« Hors ligne. » + âge de la lecture) et le mois gardé. Les flèches de mois restent actives : un autre mois gardé s'affichera, un mois jamais lu dira qu'il n'a pas pu être lu. |
| **Lecture échouée avec du contenu à l'écran** | La bannière `attention` du 027 et le contenu gardé. Rien ne disparaît sous les yeux de qui lit. |

## 7. Les données

Quatre requêtes au plus par mois affiché, deux pour la liste des mois.

### 7.1 La liste des mois

```
schedules.select('id, status, periods!inner(year, month)')
  .eq('station_id', …)
  .inFilter('status', ['published', 'validated'])
```

`periods` est lisible par tout membre (`docs/SCHEMA.md § 4`). Le filtre explicite sur `status`
n'est pas une redite de la RLS : **un administrateur voit aussi les brouillons**, et cet écran
n'est pas celui de son brouillon.

### 7.2 Un mois

1. **Les créneaux** : `shifts.select('id, date, slot, required_count').eq('schedule_id', …)` — 62
   lignes, l'ossature du mois. `required_count` sert à ne pas écrire « Personne n'est d'astreinte »
   sur un créneau dont la caserne ne veut personne.
2. **Les attributions acceptées**, jointes à leurs créneaux pour éviter une liste de 62
   identifiants dans l'URL :
   ```
   assignments.select('id, user_id, shift_id, shifts!inner(schedule_id)')
     .eq('station_id', …).eq('status', 'accepted').eq('shifts.schedule_id', …)
   ```
   **C'est ici que la RLS tranche, et nulle part ailleurs** : publié, elle rend les miennes ;
   validé, elle rend celles de tout le monde. Aucun `.eq('user_id', …)` n'est ajouté selon l'état
   du planning — le client n'a pas à deviner un droit qu'il ne détient pas.
3. **Les noms** : `memberships` de la caserne, une lecture de soixante lignes, exactement comme au
   019 et au 027. Le nom d'usage vit dans `memberships`, pas dans `profiles`
   (`docs/SCHEMA.md § 2.3`) : aucune jointure depuis `assignments` ne peut le rapporter. **Sautée
   quand aucune attribution n'est revenue.**
4. **Les heures d'affichage** de la caserne, par le même lecteur que le 027.

Un identifiant de membre sans nom lisible — quelqu'un qui a quitté la caserne — n'est pas affiché
comme un UUID : il est compté dans une mention « et 1 autre ». Un UUID à l'écran n'est pas une
information.

### 7.3 Le cache local

`CLAUDE.md § Règle des caches locaux` s'applique intégralement.

- **Une entrée par caserne, par membre et par mois**, sous
  `planning.caserne.<station>.<user>.<2026-10>`, plus une entrée `…​.mois` pour la liste des mois.
  Un mois est un instantané qui se remplace en bloc : ni file, ni fusion, ni conflit.
- **Effacé à la déconnexion**, par `DeconnexionController._oublierLesCaches`, **avant** la
  fermeture de session — après, la clé n'est plus composable. L'effacement balaie **toutes** les
  clés du préfixe, pas une seule : un pompier qui a consulté six mois en a laissé six.
  Ce document porte **les noms de toute la caserne** : c'est le cache le plus chargé en données de
  tiers du produit.
- **Le cache ne décide d'aucun droit.** Un document gardé quand le planning était `published` ne
  contient que mes créneaux ; il ne peut donc pas révéler ce que la base refusait. L'état du
  planning est gardé avec, pour que le bloc d'attente soit juste hors ligne aussi.
- **Version de format** : un document d'une version inconnue est ignoré, jamais réparé. Un mois se
  reconstruit en trois requêtes.

## 8. Accessibilité

- Chaque créneau est un **conteneur sémantique** qui se lit en une phrase : « Samedi 24 octobre,
  nuit, de 19:00 à 07:00, avec Marie L. et Thomas M. » — la flèche « → » ne se lit pas à voix
  haute, le point médian non plus.
- « toi » est dit, pas seulement peint : « … avec toi, Marie L. et Thomas M. ».
- Le sélecteur de portée porte `Semantics(selected:)` sur chaque segment, et la coche en tête,
  comme la bascule du 027.
- Cibles : 48 dp pour les segments et les flèches de mois. **Rien d'autre n'est cliquable dans le
  registre** — pas de fausse affordance sur une ligne qui n'ouvre rien.
- Le registre ne casse à aucune échelle de texte : le `Wrap` de noms s'enroule, l'en-tête de date
  passe à la ligne. Il n'y a donc **pas** de bascule de repli comme pour le calendrier du 027.

## 9. Ce qui n'est pas livré

- **Aucune action.** On ne demande pas un échange ici, on n'appelle personne, on ne contacte
  personne. `accepted` n'a aucune transition ouverte à un membre (`docs/WORKFLOWS.md § 3`) et le
  numéro de téléphone d'un membre n'est pas dans le périmètre de ce ticket.
- **Aucun filtre par personne.** « Quand Thomas est-il de garde » est une autre question, qui
  n'est pas dans le ticket.
- **Aucune vue de couverture** : les fractions « 1/2 », les créneaux en retard et les relances
  sont l'écran de suivi du chef de centre (ticket 019). Un membre n'a pas à lire un tableau de
  bord de production.
- **Pas de temps réel.** Ce qu'on lit a été décidé il y a trois semaines.
- **Pas d'export ni d'abonnement calendrier** (`docs/PRD.md § 5.5`).

## 10. Vérifié dans Chrome

Stack Supabase locale, caserne A. Décor construit pour la vérification : **octobre 2026 validé**
(trois journées pourvues, `required_count` à 0 ailleurs — la caserne ne demande personne) et
**novembre 2026 publié** (Marie L. acceptée sur le 7 au soir et le 14 en journée, Thomas M.,
Camille G., Lucas B. et Émilie R. encore en attente de réponse). Connecté en `membre1@caserne-a`,
c'est-à-dire Marie L.

| Ce qui a été vu | Ce qui a changé |
|---|---|
| **Sur le planning publié de novembre, un créneau affiché « Personne n'est d'astreinte »**. Le samedi 7, Marie est de nuit ; son créneau de jour, que la RLS ne lui rend pas, s'affichait vide. C'est **exactement la phrase que ce ticket existe pour ne pas écrire** : quelqu'un y est sûrement, on n'a pas le droit de savoir qui. | `assemblerJournees` trie désormais **au créneau**, plus à la journée : sur un planning seulement publié, seuls les créneaux du lecteur sont montés. Le § 3 le dit maintenant. Deux tests le tiennent, un de domaine et un d'écran. |
| **Démarrage à froid sans réseau : « Aucune caserne »** — un écran qui ne propose que la déconnexion, pour quelqu'un de parfaitement rattaché. Le repli du ticket 027 sur la caserne gardée n'avait jamais lieu. Cause : `appartenancesProvider` observe `sessionProvider`, il est d'abord calculé **sans session** — liste vide — puis recalculé quand la session est restaurée ; Riverpod garde la valeur précédente pendant ce recalcul, et `etatAuthProvider` décidait dessus. Sans réseau, la requête ne répondant jamais, la liste vide restait à l'écran pour toujours. | Une garde dans `etatAuthProvider` : **une liste vide encore en chargement ne décide rien**. La condition porte sur la liste vide et non sur le chargement seul, sinon un rafraîchissement de jeton renverrait à l'écran de démarrage toutes les heures. C'est un défaut du ticket 027, découvert ici parce que c'est ici que le critère « sans réseau » se vérifie. |
| **Un échec de lecture sans rien en cache s'affichait « Aucun planning publié »** — une caserne parfaitement organisée passait pour une caserne sans planning. Même cause : `AsyncValue` garde l'état vide du premier calcul à côté de l'erreur. | La condition de l'écran porte sur le **contenu** (`mois.isEmpty`) et non sur `hasValue`. Deux tests, en ligne et hors ligne. |
| Le reste tenait du premier coup : sélecteur de portée, titre qui suit la portée, registre des journées, marque « Toi », bloc d'attente ocre, flèches de mois désactivées avec leur raison en info-bulle, bandeau de fraîcheur, lecture complète depuis le cache avec l'API arrêtée, navigation d'un mois à l'autre hors ligne, et la disposition sur 1280 dp. | — |

**Ce que la vérification a aussi appris sur le décor.** Sur un planning **validé**, « Personne n'est
d'astreinte » ne peut presque jamais apparaître : `schedule_reevaluer` ramène à `published` tout
planning dont un créneau demandé perd son effectif — c'est ce qui s'est produit en montant
`required_count` à 2 sur octobre. La phrase est donc un filet de sécurité, pas une lecture
courante, et c'est bien `required_count` qui porte le travail utile : sans lui, un mois validé où
la caserne ne demande personne afficherait soixante-deux lignes de « Personne », ce qui serait le
même mensonge de mise en page à l'envers.
