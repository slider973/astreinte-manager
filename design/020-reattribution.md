# 020 — Réattribuer un créneau refusé, sans refaire le mois

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web**,
Material 3, une seule apparence. Ce brief **prolonge** `design/017-brouillon-attribution.md` et
`design/019-publication-suivi.md`. Il ne redéfinit rien de ce qu'ils ont tranché : il rouvre le
panneau du 017 sur un planning que le 019 a rendu public.

`DESIGN.md` gagne sur ce brief pour toute valeur de token. Les écarts sont au § 7.5.

Sources : `docs/PRD.md § 5.4`, `§ 7.2`, `§ 7.3`, `§ 7.6` ; `docs/SCHEMA.md § 2.8` à `§ 2.10`, `§ 3`,
`§ 5`, `§ 7` ; `docs/WORKFLOWS.md § 2`, `§ 3`, `§ 5` et `§ 8` ; `design/017 § 6.3` et `§ 6.4` ;
`design/019 § 6.7` et `§ 7.6` ; `supabase/functions/README.md` ;
`tickets/in-progress/020-reattribution.md`.

---

## 1. Job et audience

**Le même chef de centre, trois jours plus tard.** Le planning est parti, les réponses arrivent, et
l'une d'elles est un refus : « Bruno B. — refusé — *je suis en formation ce week-end* ». C'est le
moment que l'outil remplacé rend insupportable. Là-bas, un refus se répare en rouvrant le tableur,
en le refaisant, et en le renvoyant à tout le monde : trente téléphones sonnent pour une case.
Personne n'ose plus refuser, et un planning qui tient sur des gardes non tenues n'est pas un
planning.

**La promesse de ce ticket tient en une phrase : un refus ne coûte qu'un créneau.** Une case change
d'état, un téléphone sonne, et le reste du mois n'a pas bougé — ni les acceptations acquises, ni les
propositions en attente, ni la date de publication.

Ce qu'on livre, ce n'est donc pas un écran de plus. C'est **un geste de plus sur un écran qui
existe** : le panneau des candidats du 017, rouvert sur un planning publié, avec la conséquence qui
change tout — ici, attribuer fait sonner un téléphone.

## 2. Ce que le refus a déjà produit, et ce qui manque

À l'entrée du ticket, la caserne dispose de :

- une attribution `declined` avec son motif, visible dans le suivi (019) ;
- un créneau redevenu non pourvu — `shifts_filled` compte les attributions actives (017) ;
- un planning qui ne se validera pas, parce que `schedule_complet` juge sur les acceptations.

Il manque **la réparation** : donner le créneau à quelqu'un d'autre, et le lui dire. Et il manque
les deux gestes voisins : **annuler** une astreinte acceptée quand la caserne n'en a plus besoin, et
**ajouter** quelqu'un sur un créneau d'un planning déjà publié.

Les trois gestes sont le même geste en base : une attribution change d'état, une notification part à
une personne, et le planning se réévalue.

## 3. Le principe qui commande tout le ticket

> **Un changement d'état qui ne se dit pas est un mensonge.**

Un pompier qui a accepté une garde et dont l'attribution passe à `replaced` sans notification
continue de se croire d'astreinte. Il notera la date, il refusera un déplacement, et il ne viendra
pas parce que personne ne l'attend. La conséquence n'est pas un bogue d'affichage, c'est un trou
opérationnel.

D'où trois décisions qui ne sont pas des détails :

1. **La transition et la notification sont dans la même transaction.** `reassign_shift` et
   `cancel_assignment` écrivent le statut, le lien et la demande de notification en une fois. La
   file (`notification_outbox`, migration `0014`) garantit le rejeu ; elle ne garantit rien si on
   l'écrit depuis un autre processus que celui qui a changé l'état.
2. **Un client ne peut pas écrire `replaced` ni `cancelled` à la main.** Un déclencheur le refuse.
   Sans lui, la promesse ci-dessus ne tient qu'à la discipline des écrans — la même faille que le
   019 a fermée sur les plannings.
3. **`replaced_by` est posé systématiquement**, y compris quand l'ancienne attribution garde son
   statut terminal (`declined`, `cancelled`). C'est le fil de l'histoire : « ce trou-là a été comblé
   par cette attribution-là ».

## 4. Périmètre et limites

**Livré :**

- `reassign_shift` (SQL, transaction) et son Edge Function `reassign-shift` ;
- `cancel_assignment` (SQL, RPC de l'admin) ;
- le déclencheur qui interdit `replaced` / `cancelled` à un client ;
- la réévaluation du planning **dans les deux sens** : une acceptation qui disparaît ramène un
  planning validé en publié, et seuls les créneaux touchés changent d'état ;
- l'ouverture du panneau des candidats **depuis le suivi** et depuis la matrice, sur un planning
  publié ou validé ;
- l'historique lisible : `refusé`, `remplacé`, `annulé`, chacun avec son libellé propre.

**Pas livré, et à ne pas esquisser :**

- la réattribution **automatique** (proposer le suivant de la liste tout seul) : `auto-propose` est
  un autre ticket, et un logiciel qui choisit un pompier à la place du chef n'est pas ce produit ;
- la réattribution **en lot** (« réattribue-moi les six refus ») : six créneaux, six décisions, six
  personnes. Le lot cacherait justement ce que le chef doit regarder ;
- le changement de **créneau** d'une attribution (déplacer Bruno du 12 nuit au 13 jour) : ce n'est
  pas une réattribution, c'est une annulation et une attribution, et l'écran le dit ainsi ;
- les crons de relance (022), le rapport `late_responders` (022), l'export ICS.

**Anti-objectifs explicites :**

- **Pas de republication.** On ne renvoie jamais le planning entier après un refus. C'est
  exactement ce que fait l'outil remplacé, et c'est la raison d'être de ce ticket.
- **Pas de suppression.** Une attribution refusée, remplacée ou annulée **reste** (`docs/PRD.md
  § 7.6`). L'écran la barre, il ne l'efface pas.
- **Pas de notification à l'ancien quand il a refusé.** Il sait : c'est lui qui a refusé. Lui
  envoyer « ton créneau a été confié à quelqu'un d'autre » serait une notification qui n'apprend
  rien et qui punit d'avoir répondu.
- **Pas de notification à l'ancien quand il n'avait pas encore répondu.** `docs/WORKFLOWS.md § 3`
  marque la notification sur les seules transitions venues d'`accepted`. Une proposition retirée
  avant réponse disparaît de son écran « Propositions » (021) : il n'a rien à faire, et un push
  pour une garde qu'il n'avait pas acquise est du bruit.
- **Pas de tableau de bord des remplacements.** Le taux de réattribution est une métrique produit
  (`docs/PRD.md § 3`), pas un écran.

## 5. Le parcours, en trois gestes

### 5.1 Le geste central — réattribuer un refus

```
Suivi du planning
  └─ 12 octobre · nuit · 0/1 · « Bruno B. — refusé — je suis en formation »
       └─ [Réattribuer]                     ← la ligne du refus porte l'action
            └─ Panneau des candidats (017)  ← volet droit en large, feuille sinon
                 ├─ en-tête : date, créneau, couverture, + le bandeau de réattribution
                 ├─ Attribués (0)
                 ├─ Disponibles (4)  → [Réattribuer]
                 └─ Non disponibles (9) — repliés
                      └─ confirmation « Chloé C. recevra une notification »
                           └─ notification à Chloé, et à personne d'autre
```

**Le panneau est le même objet.** Mêmes trois listes, même tri (quota restant décroissant, puis
charge des trois mois précédents, puis nom), même repli des non disponibles, mêmes avertissements de
quota. Le chef ne réapprend rien ; ce qui change, c'est la conséquence, et elle se dit à deux
endroits : le bandeau de l'en-tête et le libellé du bouton.

### 5.2 Ce qui change par rapport au 017

| | Planning en brouillon (017) | Planning publié ou validé (020) |
|---|---|---|
| Libellé du bouton | « Attribuer » | « Réattribuer » |
| Retrait d'un attribué | « Retirer » — la ligne disparaît | « Annuler » — la ligne se barre et reste |
| Confirmation | aucune, sauf hors disponibilité | **toujours**, parce qu'un téléphone sonne |
| Réversible | oui, « Annuler » dans la phrase passagère | non : on ne rappelle pas un push |
| Effectif requis | modifiable | modifiable (il change la condition de validation) |

**La confirmation est la seule modale ajoutée, et elle est justifiée** : le geste est irréversible et
sort de l'application. `DESIGN.md § Don't` interdit la modale « pour une tâche qui ne demande ni
interruption ni protection » ; celle-ci demande une protection. Elle nomme la personne et la
conséquence — « Chloé C. recevra une notification pour le samedi 12 octobre, de nuit » — et son
bouton nomme l'action : « Réattribuer et notifier », jamais « OK ».

Quand le candidat n'est **pas** disponible ce jour-là, la même feuille porte les deux avertissements
plutôt que d'en empiler deux : « Chloé C. s'est déclarée absente » au-dessus de la phrase de
notification. Une confirmation par sujet aurait appris à cliquer sans lire.

### 5.3 Annuler une astreinte acceptée

Depuis le panneau, sur la ligne d'un attribué : **« Annuler »**. Confirmation nommée (« Bruno B.
sera prévenu que son astreinte du 12 octobre, de nuit, est annulée »), motif facultatif en une
ligne — il part dans la notification, parce qu'« annulée » sans raison est ce qui produit le coup de
téléphone que l'app devait éviter.

L'attribution passe à `annulé`, barrée, et **reste dans la liste du suivi**. Le créneau redevient
non pourvu, le planning repasse de validé à publié si l'annulation lui retire une acceptation.

### 5.4 Ajouter quelqu'un sur un planning publié

Le même panneau, le même bouton « Réattribuer », sans ancienne attribution derrière. C'est le
troisième cas et il ne mérite pas d'écran : un créneau non pourvu d'un planning publié se pourvoit
comme un créneau refusé se repourvoit. Le nouveau membre reçoit sa proposition ; personne d'autre
n'est prévenu.

## 6. Ce qui se voit à l'écran

### 6.1 La ligne du suivi devient actionnable — et seulement quand il y a quelque chose à faire

Le 019 a écrit noir sur blanc : « Les lignes ne sont pas cliquables. Il n'y a rien à ouvrir : la
réattribution est le ticket 020. » Il y a maintenant quelque chose à ouvrir.

**Mais pas sur toutes les lignes.** Une ligne de créneau est actionnable quand le planning est
`publié` ou `validé`, que la caserne est modifiable, et que le chef a quelque chose à y décider :
un refus, une annulation, ou un créneau non pourvu. Une ligne entièrement acceptée et pourvue reste
inerte — il n'y a rien à réparer, et un élément qui a l'air cliquable sans servir est pire qu'un
élément inerte (règle du 019, conservée).

L'action est portée par un **bouton nommé en fin de ligne**, pas par la ligne entière :

- « Réattribuer » quand le créneau porte un refus ou une annulation ;
- « Pourvoir » quand il est simplement vide.

Un bouton nommé, et non une zone cliquable, parce que la ligne porte déjà trois cibles de lecture
(la fraction, les noms, les motifs) et qu'une ligne entièrement cliquable au doigt, avec des gants,
sur un écran qui défile, s'ouvre par accident.

**Cible 48 dp, 8 dp entre deux cibles, jamais de survol comme seul accès.**

### 6.2 Le bandeau du panneau, en mode réattribution

Sous l'en-tête existant (date, créneau, badge de couverture), une ligne de plus, **et une seule** :

> `Icons.campaign` · **Planning publié — la personne choisie sera notifiée tout de suite.**

Fond `secondary-container` (le bleu de réglure : c'est une information, pas une alarme), icône +
libellé, jamais la couleur seule. Quand le panneau est ouvert sur un refus, la phrase nomme ce
qu'on répare :

> `Icons.campaign` · **Bruno B. a refusé ce créneau. La personne choisie sera notifiée tout de
> suite.**

Ce bandeau **remplace** la mention « modifié à l'instant par… » quand les deux voudraient s'afficher
(le 017 avait déjà réservé cet emplacement à une mention unique).

### 6.3 L'historique d'un créneau

Le suivi liste déjà toutes les attributions d'un créneau, dans l'ordre : en attente, accepté,
refusé, **remplacé**, annulé. Les deux derniers états entrent ici pour de bon.

| État | Marque | Icône | Libellé |
|---|---|---|---|
| remplacé | barré, atténué | `Icons.swap_horiz` | « Remplacé » |
| annulé | barré, atténué | `Icons.block` | « Annulé » |

Même encre et même fond que « annulé » (`DESIGN.md § Attribution`) : ce sont deux façons de ne plus
compter, et elles se distinguent par **l'icône et le libellé**, pas par une cinquième couleur. Le
tri les place après « refusé » : ce qui a été réparé se lit après ce qui a cassé.

Une attribution remplacée dit **par qui**, sur la même ligne, en mention : « remplacé par Chloé C. ».
Sans cette phrase, l'historique montre une sortie sans montrer l'entrée, et le chef recompte à la
main.

### 6.4 Ce qui ne bouge pas

Après une réattribution, **une seule chose change à l'écran** : le créneau touché. Les compteurs de
progression se recalculent (ils viennent de `v_schedule_progress`, relue), la fraction du créneau
passe de `0/1` à `1/1`, la ligne du refus reste avec sa nouvelle mention. Le défilement ne saute
pas, aucun autre créneau ne clignote, et le badge du planning ne repasse à « Publié » que si une
acceptation a réellement disparu.

C'est la démonstration visuelle de la promesse : **le reste du mois n'a pas bougé**.

### 6.5 États vides, erreurs, hors ligne

- Panneau ouvert alors que la matrice du mois n'est pas encore lue : **squelette à la forme du
  panneau** (en-tête + trois blocs de lignes), jamais un `CircularProgressIndicator` centré.
- Aucun candidat disponible : l'état vide du 017, qui propose de voir les non disponibles.
- Hors ligne : les boutons « Réattribuer » portent leur raison à côté d'eux. Une réattribution
  n'est pas une écriture qu'on met en file locale — elle fait sonner un téléphone, et une file
  locale enverrait une notification une heure plus tard, pour un créneau peut-être déjà pourvu.
- Caserne suspendue : même traitement, même phrase que partout.
- Échec de l'envoi : la réattribution est acquise (elle est en base), la demande de notification est
  en file et sera rejouée. La phrase passagère le dit sans dramatiser.

## 7. Ce que la base doit tenir

### 7.1 `reassign_shift(p_shift, p_user, p_actor, p_previous)`

Une transaction, dans cet ordre :

1. verrou de ligne sur le planning — deux adjoints qui réattribuent le même créneau en même temps
   ne doivent pas créer deux attributions et deux notifications ;
2. les refus métier, rendus en `{"ok": false, "code": …}` comme partout :
   `shift_not_found`, `not_admin`, `station_suspended`, `schedule_not_published` (un brouillon se
   modifie par insertion et suppression, pas par réattribution), `member_not_active`,
   `already_assigned`, `assignment_not_found`, `assignment_not_replaceable` ;
3. la nouvelle attribution : `proposed`, **`proposed_at = now()`** — elle est partie, les crons de
   relance doivent la voir —, `created_by = p_actor` et `was_available` **relu dans
   `availabilities`**. Une écriture serveur ne passe pas par
   `assignments_trace_disponibilite` : la trace se pose ici, à la main, ou elle ne se pose pas ;
4. l'ancienne, s'il y en a une : `accepted → replaced`, `proposed → replaced`, `declined` et
   `cancelled` **restent tels quels** — un statut terminal a déjà été notifié sous ce nom ; dans
   les quatre cas `replaced_by` pointe la nouvelle. Seul `replaced` n'est pas remplaçable : ce qui
   a trouvé son remplaçant ne s'en cherche pas un second ;
5. les notifications : `assignment_proposed` au nouveau, **toujours** ;
   `assignment_cancelled` à l'ancien **si et seulement si** son attribution était `accepted` ;
6. `audit_log` : `assignment.reassigned` ;
7. `schedule_reevaluer`, qui applique `validated → published` si une acceptation a disparu.

**Pourquoi `assignment_cancelled` et non `assignment_changed` pour l'ancien.** Du point de vue du
pompier remplacé, rien n'a « changé » : il n'a plus cette garde. Le texte d'`assignment_cancelled`
est exactement le sien (« Ton astreinte du lundi 12 octobre, de nuit, est annulée. Tu n'as rien à
faire. ») et son lien profond mène au planning du mois, là où il vérifiera. `assignment_changed`
mène à `/proposals`, où il n'a rien à faire.

### 7.2 Une notification, pas deux

`assignment_proposed` est un type **regroupé** (`docs/WORKFLOWS.md § 8`) : à la publication, sept
créneaux font une notification. Ici il n'y a qu'un créneau et qu'un destinataire — le regroupement
ne change rien, et c'est voulu : **une réattribution est un fait unique et daté**.

`assignment_cancelled`, lui, n'est **pas** regroupé, et ce n'est pas un oubli : deux annulations le
même jour sont deux gardes perdues, et les fondre en une ligne ferait disparaître une information
que le pompier doit avoir.

Le compte à tenir, celui du critère d'acceptation : **un refus suivi d'une réattribution produit
exactement une notification, au nouveau membre.** Le refus, lui, a déjà produit la sienne — aux
administrateurs — au moment où il a été prononcé ; c'est un autre événement, dans une autre
transaction.

### 7.3 `cancel_assignment(p_assignment, p_reason)`

Ouverte à `authenticated`, comme `remind_schedule` : l'admin l'appelle en RPC, la fonction vérifie
`is_admin` et `station_writable` elle-même. Pas d'Edge Function — il n'y a ni identité à établir
autrement que par `auth.uid()`, ni regroupement à faire, et `docs/SCHEMA.md § 7` n'en nomme pas.
`accepted → cancelled` notifie ; `proposed → cancelled` ne notifie pas (§ 4, anti-objectifs).

### 7.4 Le retour de `validated` vers `published`

La garde du 019 l'autorise déjà (`docs/WORKFLOWS.md § 2`), efface `validated_at` et **conserve**
`published_at` : l'histoire du mois ne se réécrit pas. Ce qui manquait, c'est l'appelant. Le
déclencheur d'auto-validation ne se réveillait qu'à une acceptation ; il se réveille désormais aussi
quand une acceptation **disparaît** — c'est la même question posée dans l'autre sens, et
`schedule_reevaluer` sait déjà y répondre.

Ce retour **ne notifie personne**. Ce n'est pas un fait nouveau pour la caserne : la conséquence est
déjà partie sous la forme de la notification de réattribution ou d'annulation, à la personne
concernée.

### 7.5 Écarts et décisions ouvertes

- **Un cinquième état d'attribution dans le thème.** `DESIGN.md § Attribution` en décrit quatre.
  « Remplacé » est ajouté avec l'encre et le fond d'« annulé » — contrastes déjà vérifiés — et son
  icône et son libellé propres. Consigné en fin de `DESIGN.md`.
- **Le lien implicite.** Quand le chef pourvoit un créneau sans désigner d'ancienne attribution, la
  base rattache la nouvelle au **plus ancien trou non encore comblé** du même créneau — un refus ou
  une annulation. Le statut ne bouge pas, seul `replaced_by` se pose. C'est ce que le chef fait dans
  sa tête, et le laisser vide obligerait l'historique à se reconstruire par la chronologie.
- **Une annulation se repourvoit comme un refus.** Trouvé en pilotant l'écran : la première version
  ne laissait remplacer qu'un refus, et le geste échouait en `409` sur une garde annulée — alors que
  c'est exactement le même trou et exactement le même geste. Le bandeau, lui, distingue les deux :
  « L'astreinte de X a été annulée » n'est pas « X a refusé », et mettre un refus sur le dos de
  quelqu'un qui n'a rien refusé serait une faute.
- **La réattribution est refusée hors ligne** plutôt que mise en file. Décision assumée au § 6.5.
- **Le panneau chargé depuis le suivi relit la matrice du mois.** Deux requêtes de plus, à
  l'ouverture du panneau seulement, jamais au chargement de l'écran. Mesurées au 016 : ~20 ms de
  bout en bout pour la matrice. Le faire autrement demanderait de dupliquer le calcul des candidats.

## 8. Widgets

### 8.1 Réemployés tels quels

| Composant | Emploi |
|---|---|
| `PanneauCreneau`, `LigneCandidat`, `ChampEffectif` (017) | le panneau, à l'identique |
| `AppScaffold.panneauLateral` | le volet droit en `large`, sur le suivi comme sur la matrice |
| `showModalBottomSheet` | la même feuille, en dessous de `large` |
| `StatusBadge.attribution` | les cinq états, « remplacé » compris |
| `AppBanner`, `EmptyState`, `LoadingSkeleton` | inchangés |

### 8.2 Ajoutés

| Composant | Rôle |
|---|---|
| `BandeauReattribution` | la ligne « la personne choisie sera notifiée », dans l'en-tête du panneau |
| `confirmerReattribution` | la feuille de confirmation, avec le nom, le créneau et l'avertissement de disponibilité s'il y a lieu |
| `confirmerAnnulation` | la même, avec le champ de motif facultatif |
| `SqueletteePanneau` | le squelette du panneau pendant que la matrice se lit |

### 8.3 Accessibilité

- Chaque bouton d'action porte un `Semantics` qui nomme **la personne et le créneau**, pas
  « Réattribuer » seul : une liste de douze boutons homonymes est inutilisable au lecteur d'écran.
- La confirmation est annoncée (`liveRegion`), son bouton principal a le focus initial.
- Le changement d'état d'un créneau après réattribution est annoncé une fois, en région vive, par la
  phrase passagère — jamais par créneau reçu du temps réel.
- Cibles 48 dp, texte ≥ 14 sp, aucun état porté par la couleur seule, tout vérifié en niveaux de
  gris.

## 9. Comment on saura que c'est réussi

1. Un refus, une réattribution, **un** téléphone qui sonne.
2. Le planning revient de « Validé » à « Publié » quand une acceptation disparaît, et seulement
   alors.
3. Aucune attribution n'a disparu de la base : `declined`, `replaced`, `cancelled` sont toutes
   lisibles dans le suivi, avec leur date et leur motif.
4. Le chef n'a rien réappris : le panneau est celui qu'il connaît depuis le 017.
5. `published_at` est toujours celui de la première publication.
