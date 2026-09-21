# 018 — La proposition automatique de remplissage

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web**,
Material 3. Volontairement **bref** : ce ticket n'ouvre aucun écran, il ajoute **un bouton et une
feuille** à l'écran que le 016 et le 017 ont déjà dessiné. Tout ce qu'il ne redit pas est déjà
tranché dans `design/016-matrice-admin.md` et `design/017-brouillon-attribution.md`.

Sources : `docs/PRD.md § 5.3`, `§ 6.4` et `§ 7.4` ; `docs/SCHEMA.md § 2.9`, `§ 2.10`, `§ 6`, `§ 7` ;
`docs/WORKFLOWS.md § 3` ; `design/017-brouillon-attribution.md` ; `design/019-publication-suivi.md`
(la feuille de récapitulatif) ; `design/020-reattribution.md § 3` ; ticket 018.

---

## 1. Job et audience

Le même chef de centre, au même endroit, **dix minutes après avoir créé le planning**. Soixante-deux
créneaux vides, soixante colonnes de disponibilités, et une heure de travail devant lui dont
l'essentiel est mécanique : trouver qui peut, vérifier qu'il n'a pas déjà son compte, cliquer.

Ce ticket lui rend **la partie mécanique**, et rien d'autre. Il ne décide pas à sa place : il
propose un remplissage entier, lui montre ce que ça donne, et attend qu'il dise oui.

## 2. Résultat et preuve

**Résultat.** Un appui, un récapitulatif chiffré, un second appui, et le mois est rempli — sauf les
créneaux que personne ne peut tenir, qui restent vides et se voient.

**Preuve, dans l'ordre :**

1. Le chef lit **deux nombres** avant d'appliquer : combien de créneaux seraient remplis, combien
   resteraient à découvert faute de candidat.
2. Aucune attribution qu'il a posée à la main ne bouge.
3. Aucun pompier ne dépasse un plafond qu'il a déclaré.
4. Aucun pompier absent, ni aucun pompier qui n'a rien saisi, n'est désigné.

## 3. La règle, et son seul écart

`docs/PRD.md § 6.4` : « pour chaque créneau vide, choisir le membre disponible avec le plus de quota
restant, puis le moins d'astreintes sur les 3 derniers mois. Pas d'optimisation globale au MVP. »
Le ticket ajoute une troisième clause : « puis aléatoire ».

**Ce tri existe déjà** : c'est `comparerCandidats` (`lib/features/planning/domain/candidat.dart`,
ticket 017), celui qui ordonne le panneau des candidats. Le remplissage automatique **l'appelle**.
Écrire une seconde règle — en SQL, par exemple — donnerait deux classements de la même liste, et le
jour où ils divergeraient, le chef verrait la machine choisir le troisième nom de son panneau sans
comprendre pourquoi.

**L'écart, assumé : « puis aléatoire » devient « puis le moins chargé sur le mois en construction,
puis le nom ».** Trois raisons :

- Le hasard rend le récapitulatif **menteur** : le chef valide « 48 créneaux remplis » sur un tirage,
  et un second tirage appliquerait autre chose. Un récapitulatif qui n'engage pas ce qu'il annonce ne
  sert à rien.
- Le hasard n'est là, dans le ticket, que pour **ne pas désigner toujours le même**. Un pompier sans
  plafond déclaré a un quota restant infini : sans ce départage, il reste premier du classement à
  chaque créneau et ramasse le mois entier. Compter les astreintes **déjà posées ce mois-ci** répond
  exactement au même besoin, et il se vérifie.
- Le nom en dernier recours est déjà le départage du 017. Le classement reste **le même objet**.

Ce départage est ajouté **dans `comparerCandidats`**, donc le panneau en profite aussi : entre deux
illimités, celui qui a le moins d'astreintes ce mois-ci passe devant. C'est ce qu'un chef attend.

**Le plafond de weekends est une limite, pas un critère de tri.** Le tri classe sur le quota
d'astreintes restant ; les weekends, eux, **excluent** — un pompier qui a rempli son compte de
weekends n'est pas proposé pour un samedi, il reste proposable pour un mardi. Deux natures
différentes, deux traitements.

**Rien d'autre.** Pas d'optimisation globale, pas de rattrapage, pas de second passage, pas de
préférence de créneau. Le ticket l'écrit, le brief le répète pour que la revue le vérifie.

## 4. Où vit quoi

| Ce qui est décidé | Où | Pourquoi |
|---|---|---|
| **L'ordre des candidats** | Dart, `comparerCandidats` (017) | Le chef le lit dans le panneau ; la machine doit choisir comme le panneau montre. Une seule écriture. |
| **Le remplissage** | Dart, `PropositionAutomatique.construire` — fonction **pure**, zéro requête | Toute la matière est déjà à l'écran (matrice + créneaux + attributions). Le plan que le chef valide est **exactement** celui qui part. |
| **Les limites** | SQL, `apply_auto_proposal` (migration 0028) | Ne jamais dépasser un quota, ne jamais désigner un absent, ne jamais dépasser l'effectif requis : ce sont des **règles**, elles se tiennent en base, dans la transaction, et elles se testent en SQL. |

C'est la même division que partout ailleurs dans ce produit : l'écran **prédit**, la base **décide**
(`design/017 § 7`). Ici la prédiction est juste par construction — elle est faite sur les nombres que
la base vient de rendre — et la base la revérifie ligne à ligne sans jamais lever pour un refus
attendu.

**Cohérence avec le 020.** Une place occupée ne se reprend pas : le remplissage ne pose une
attribution que tant que `attributions actives < required_count`, exactement le test de
`reassign_shift` (`shift_already_filled`). Un créneau qui demande deux personnes reçoit deux appels
successifs du tri, chacun sur un classement **recalculé** — le premier choisi n'est plus candidat au
second, et son quota a déjà baissé.

## 5. Ce que l'écran gagne

### 5.1 Le bouton

Dans la **barre de commande** (`BarreCommandeMatrice`), à côté de l'état du planning, jamais dans la
barre d'actions du bas : celle-là porte « Publier », le geste qui sort de l'application, et on ne met
pas deux gestes de poids différent au même endroit.

- Libellé : **« Proposer automatiquement »**. L'action est nommée, pas l'outil.
- Icône : `auto_fix_high`. Variante **secondaire** : c'est une aide, pas la conclusion du mois.
- Visible **seulement en brouillon** et seulement s'il reste un créneau à pourvoir. Le bouton
  disparaît quand le mois est complet — un bouton qui ne ferait rien est un bouton qui ment.
- Désactivé hors ligne ou caserne suspendue, **avec sa raison à côté** (`DESIGN.md § Do's`).

### 5.2 La feuille de récapitulatif

Même forme que le bordereau de publication du 019 — dialogue en `large`, feuille de bas d'écran en
dessous — et pour la même raison : le geste engage tout le mois. C'est la seconde exception méritée
à « pas de modale pour une tâche qui ne demande ni interruption ni protection ».

Trois nombres en tête, dans cet ordre, en `CountStat` (chiffres tabulaires) :

| `créneaux remplis` | `astreintes posées` | `créneaux à découvert` |

Puis, quand il en reste, **la liste des créneaux qui resteraient vides** — « sam. 11 nuit · dim. 12
jour · … », six au plus puis « et 4 autres », exactement la présentation des réserves du 019. Elle
n'est **pas rouge** : ce n'est pas une panne, c'est l'état des disponibilités de la caserne.

Une phrase dit ce que la feuille ne dira pas deux fois :

> Les créneaux que tu as remplis toi-même ne sont pas touchés. Personne ne dépasse le nombre
> d'astreintes qu'il a accepté.

Deux boutons : **Annuler** / **Appliquer la proposition**. Le second porte le compte : appliquer 48
attributions n'est pas appliquer 3.

### 5.3 Après

Les attributions apparaissent dans la grille au retour du serveur, la barre passe en
« Enregistré », et une phrase passagère annonce le résultat réel — pas celui qui était prévu :
« 48 créneaux remplis, 6 sans candidat. » Si la base a écarté des lignes (l'adjoint a rempli le même
créneau pendant la lecture), elle le dit : « 46 remplis, 2 déjà pris entre-temps. »

**Pas d'annulation en masse.** Chaque attribution se retire d'un geste dans le panneau, comme les
autres ; un « Tout annuler » ferait disparaître d'un coup des lignes que le chef aurait pu retoucher
entre-temps. Le brouillon reste le lieu où tout est réversible un par un.

## 6. Accessibilité et opération

- Le bouton et les deux boutons de la feuille : 48 dp, écart de 8 dp.
- Le récapitulatif est annoncé comme un en-tête ; les trois nombres sont lus avec leur libellé
  (`CountStat` le fait déjà).
- Les nombres sont en chiffres tabulaires : ils changent en place entre l'annonce et le résultat.
- Le calcul est synchrone et tient sous la frame : 62 créneaux × 60 membres, aucune requête. S'il
  devait un jour coûter, il irait dans un isolat — pas aujourd'hui.

## 7. Écarts au `DESIGN.md`

Aucun nouveau. La feuille réemploie le patron du 019, déjà inscrit comme exception méritée.

## 8. Hors périmètre

Pas de réglage de l'heuristique, pas de « refaire la proposition avec d'autres critères », pas de
proposition partielle sur une sélection de jours, pas d'aperçu dans la grille avant d'appliquer, pas
de proposition sur un planning publié — celui-là se répare créneau par créneau (ticket 020).
