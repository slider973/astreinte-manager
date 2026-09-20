# 014 — Périodes, date limite et verrouillage — brief de design

Mode Impeccable : **Operate**. Écran d'administration, consulté sur ordinateur en priorité,
utilisable sur téléphone. Monde visuel : le registre de garde (`DESIGN.md`).

## 1. Ce que l'écran doit rendre évident

Un admin ouvre « Périodes » pour répondre à **trois questions**, dans cet ordre :

1. *Est-ce que le mois prochain est encore ouvert, et jusqu'à quand ?*
2. *Est-ce que les gens ont saisi ?*
3. *Est-ce que je peux fermer maintenant, ou rouvrir ce que la machine a fermé ?*

La liste des mois répond aux trois sur une seule ligne. Rien d'autre n'est à l'écran.

## 2. Structure

`AppScaffold` « Périodes », troisième écran de la destination Admin, à côté de « Membres » et
« Paramètres », atteint par la barre d'application comme les deux autres (aucun nouvel onglet :
`DESIGN.md § Navigation` fixe cinq destinations).

```
Périodes                          [Membres] [Paramètres] [Rafraîchir]
──────────────────────────────────────────────────────────────────────
Un mois se verrouille tout seul à sa date limite. Tu peux le fermer
plus tôt, ou le rouvrir en repoussant sa date limite.

Mois à venir                                         2 mois
──────────────────────────────────────────────────────────────────────
Novembre 2026                            [🔓 Saisie ouverte]
Ouvert jusqu'au 15 oct.
▐▐▐▐▐▐▐░░  7 membres sur 9 ont saisi              [Verrouiller]
──────────────────────────────────────────────────────────────────────
Mois écoulés                                          1 mois
Octobre 2026                             [🔒 Mois verrouillé]
Verrouillé le 15 sept. · date limite du 15 sept.
▐▐▐▐▐▐▐▐▐  9 membres sur 9 ont saisi                  [Rouvrir]
──────────────────────────────────────────────────────────────────────
                                              [Ouvrir un mois]
```

Lignes réglées, séparées par le filet, jamais des cartes (`DESIGN.md § Don't`). Deux sections :
les mois à venir en tête, du plus proche au plus lointain — c'est là que l'admin agit ; les mois
écoulés en dessous, du plus récent au plus ancien.

## 3. Une ligne, une action nommée

Chaque ligne porte **une seule** action, écrite en toutes lettres dans un bouton secondaire :
« Verrouiller » sur un mois ouvert, « Rouvrir » sur un mois verrouillé. Pas de menu `⋮` : à un
seul choix, le menu cache l'action derrière un geste (`DESIGN.md § Don't` — pas de survol ni de
clic droit comme seul accès).

L'état est porté par `StatusBadge.periode` : marque (hachures pour le verrouillé), icône
(`lock_open` / `lock`), libellé — la couleur en quatrième. Le verrouillage est **gris-encre, jamais
rouge** : c'est un fait, pas une panne.

## 4. Le taux de saisie

Phrase d'abord, jauge ensuite : « 7 membres sur 9 ont saisi », chiffres en chasse fixe. La jauge
est un filet plein de 6 dp sur fond réglé, jamais un anneau ni une courbe ; elle répète ce que la
phrase dit déjà, elle ne la remplace pas. Quand la caserne n'a aucun membre actif, la ligne le dit
au lieu d'afficher « 0 % ».

Les deux nombres sont comptés en base et arrivent avec la liste : voir § 7.

## 5. Rouvrir, c'est dire jusqu'à quand

La réouverture ouvre une feuille de bas d'écran (pas une modale : il y a une saisie à faire), et
cette feuille **n'a pas de bouton « Rouvrir » sans date**. Elle montre :

- la phrase de la règle, en clair : « La tâche de verrouillage passe toutes les heures. Sans
  nouvelle date limite, le mois se refermerait dans l'heure. » ;
- la nouvelle date limite **en toutes lettres** (« mercredi 23 septembre, 23 h 59 »),
  pré-remplie à **trois jours** ;
- deux cibles de 48 dp, « Un jour plus tôt » et « Un jour plus tard », pour la déplacer. Pas de
  `showDatePicker` : l'application n'embarque pas `flutter_localizations`, et le sélecteur
  Material s'afficherait en anglais au milieu d'un écran français.

Si la date descend jusqu'à aujourd'hui ou avant, le bouton se désactive **et dit pourquoi**, à
côté de lui : « Choisis une date future, sinon le verrouillage automatique refermera le mois dans
l'heure. » C'est la règle de la base (`period_reopen_deadline_passed`) énoncée avant le refus,
pas après.

## 6. Ouvrir un mois

Bouton primaire en fil d'actions, « Ouvrir un mois ». Il ouvre une feuille qui liste les douze
prochains mois ; ceux qui existent déjà y sont présents mais inertes, avec leur état (« déjà
ouvert », « déjà verrouillé ») — montrer ce qui est déjà fait évite le double clic et l'erreur
« pourquoi rien ne s'est passé ». Aucun mois écoulé n'est proposé : la base les refuse
(`period_month_in_past`), l'écran ne les offre donc pas.

## 7. Le compte des saisies

**Compté en base**, par la vue `v_period_completion` (migration `0013`, revue du ticket 014) :
une ligne par période, `active_members` et `members_with_availability`. Une requête pour tout
l'écran, filtrée sur la caserne. Le coût ne dépend pas de l'effectif — deux nombres par mois —
mais du seul nombre de périodes.

Le premier jet comptait côté client, en rapatriant la colonne `user_id` des disponibilités du
mois. C'était **faux sans le dire** : PostgREST plafonne une réponse à mille lignes et rend `200`
sans en-tête d'alerte. À ~62 lignes par membre et par mois, le compte devenait faux dès dix-sept
membres et plafonnait vers seize — « 16 membres sur 60 ont saisi » quand les soixante avaient
saisi, et un chef de centre qui rouvre un mois pour rien. Une erreur de lecture qui provoque une
mauvaise décision sans jamais lever d'exception.

Conséquences sur l'écran, toutes des simplifications : plus de chargement paresseux ligne par
ligne, plus de squelette dans la ligne — les taux arrivent avec la liste. Reste un seul état
particulier, quand la vue elle-même n'a pas pu être lue : la ligne écrit « Comptage
indisponible » plutôt qu'un zéro qui se lirait « personne n'a saisi », et le reste de l'écran
continue de fonctionner.

Le numérateur se construisant sur le même ensemble que le dénominateur, un pompier désactivé
depuis qu'il a saisi ne produit plus « 10 membres sur 9 », et une caserne sans membre actif rend
`0` et `0` — l'écran dit alors « Aucun membre actif ».

## 8. Le message du membre sur un mois verrouillé

Ticket 011 : sur un mois verrouillé, la bannière dit « Mois verrouillé depuis le … » et les cases
sont inertes. **Inerte n'est pas une erreur claire** : un doigt qui appuie sur une case et
n'obtient rien n'apprend rien, et il recommence.

La case verrouillée reste donc non modifiable, mais elle **répond** : l'appui déclenche une phrase
en bas d'écran, « Novembre 2026 est verrouillé : la saisie est fermée. Demande à ton chef de
centre de rouvrir le mois. », annoncée aussi aux lecteurs d'écran. La caserne suspendue a sa
propre phrase. Aucune écriture n'est tentée — la RLS refuserait, et un aller-retour pour se faire
dire non n'apprend rien de plus que la période déjà lue.

## 9. États

| État | Rendu |
|---|---|
| chargement | squelette à la forme de trois lignes de période, jamais une roue |
| vide | « Aucun mois n'est encore ouvert » + l'action « Ouvrir un mois » |
| erreur de lecture | état d'erreur plein écran avec « Réessayer » ; si la liste est déjà à l'écran, bannière |
| comptage illisible | la liste reste, chaque ligne écrit « Comptage indisponible » |
| refus serveur | bannière d'erreur avec la phrase de la base (droits, caserne suspendue, mois écoulé) |
| action en cours | la ligne concernée garde sa place, son bouton passe en chargement |
| non admin | « Réservé aux administrateurs », comme « Membres » et « Paramètres » |
