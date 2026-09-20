# 010 — Paramètres de la caserne

Brief de design, format `shape` (Impeccable). Mode : **Operate**. Plateforme : **PWA web
mobile-first**, Material 3, une seule apparence sur toutes les cibles. `DESIGN.md` gagne sur ce
brief pour toute valeur de token ; `design/009-gestion-membres.md` décrit l'autre écran de
l'espace d'administration, dont celui-ci reprend la grammaire.

---

## 1. Job et audience

**Le chef de centre, une fois.** Cet écran n'est pas visité toutes les semaines : il est réglé à
l'installation de la caserne, puis retouché deux ou trois fois par an — quand l'effectif de garde
change, quand la date limite de saisie ne convient plus, quand les relances arrivent trop tard.

Trois occasions, toujours les mêmes :

1. **Le premier réglage.** La caserne vient d'être créée avec les valeurs par défaut (1 pompier
   jour, 1 nuit, saisie fermée le 15). Le chef de centre les confronte à son règlement intérieur.
2. **La règle du samedi.** « Le weekend, il m'en faut deux, et trois le 31 décembre. » C'est la
   seule vraie complexité de l'écran, et c'est aussi ce qui évite de corriger le planning à la
   main tous les mois.
3. **La relance qui arrive trop tard.** Les pompiers ne répondent pas aux propositions ; il
   avance le rappel de 24 h à 12 h.

**Ce qui se joue.** Un effectif requis mal réglé produit un planning entier faux. Une date limite
déplacée **ferme la saisie plus tôt pour tout le monde** : des membres qui comptaient sur le 20
pour remplir leur mois se retrouvent devant un mois verrouillé. C'est la conséquence la moins
devinable de l'écran, et elle doit être écrite à l'endroit où on la déclenche.

## 2. Résultat et preuve

**Résultat.** Un chef de centre règle sa caserne en une minute, comprend ce que chaque réglage
déplace avant de l'enregistrer, et ne peut pas écrire un document invalide.

**Preuves, vérifiables.**

- Chaque réglage numérique s'ajuste sans clavier : deux cibles de 48 dp, « moins » et « plus ».
- Le jour limite affiche sa conséquence en clair, avec une vraie date : « Les disponibilités de
  novembre 2026 se ferment le 15 octobre 2026 à 23:59. »
- L'écran dit, **avant** l'enregistrement, que changer l'effectif requis ne touchera pas les
  plannings déjà créés, et que changer le jour limite déplacera la date limite des mois encore
  ouverts.
- Une valeur hors bornes est refusée par l'écran avec sa phrase, et par la base avec sa
  contrainte : les deux disent la même chose.
- Un membre ordinaire n'atteint pas l'écran ; s'il force l'URL, il lit « Réservé aux
  administrateurs » et rien d'autre.
- Chaque cible tactile ≥ 48 dp, chaque état lisible en niveaux de gris.

## 3. Direction retenue

**Le formulaire est un registre de réglages, pas un panneau de préférences.** Six sections
réglées, chacune ouverte par un `EnteteSection` (titre + phrase de compte), séparées par des
filets de 1 dp. Aucune carte, aucune ombre, aucun accordéon : on doit pouvoir lire l'état complet
de la caserne en faisant défiler une fois, comme on lit une page de registre.

**Un nombre se règle avec des gants.** Le composant central de l'écran est `ChampNombre` : un
libellé, une valeur en `nombre` (chasse fixe, elle change en place), et deux boutons carrés de
48 dp `−` et `+`. Pas de champ texte pour un nombre à deux chiffres, pas de curseur, pas de
`Slider` — un curseur ne se vise pas avec un gant et ne dit pas sa valeur exacte. Le clavier reste
disponible : la valeur elle-même est un champ de saisie numérique, borné au relâchement.

**Les conséquences sont écrites sous le réglage qui les produit**, jamais dans une modale de
confirmation. `DESIGN.md § Do` : « Expliquer pourquoi un contrôle est désactivé, à côté du
contrôle » — la même règle vaut pour ce qu'un contrôle va déplacer. Deux phrases fixes, toujours
présentes, jamais des alertes :

- sous l'effectif requis : « Les plannings déjà créés gardent leur effectif. Ce réglage s'applique
  aux plannings créés ensuite. »
- sous le jour limite : « La date limite des mois encore ouverts sera recalculée. »

**Une surcharge est une ligne, pas une grille.** Sept jours × deux créneaux = quatorze contrôles :
une grille de quatorze `ChampNombre` noierait l'écran alors que la caserne n'en règle qu'un ou
deux. Chaque jour de semaine est donc **une ligne de registre** qui dit son état en toutes lettres
(« Par défaut » ou « 2 en journée · 3 la nuit ») et porte un bouton d'édition de 48 dp ouvrant une
feuille de bas d'écran. Les dates précises suivent la même ligne, avec en plus « Retirer ».

**Un seul enregistrement, explicite.** L'écran n'enregistre pas au fil de la frappe : ces réglages
sont un document cohérent, et un effectif enregistré à mi-saisie produirait un planning faux. Le
bouton « Enregistrer les paramètres » est en fil d'actions, permanent, et dit ce qu'il fait. Tant
que rien n'a changé, il est inerte avec sa raison : « Aucune modification à enregistrer. »

## 4. Périmètre et limites

**Dans le périmètre.** Le nom de la caserne, son fuseau, les heures d'affichage du créneau de
jour, l'effectif requis jour et nuit, les surcharges par jour de semaine et par date, le jour
limite de saisie, les trois délais de relance, la validation côté app **et** côté base, et le
recalcul des dates limites des périodes ouvertes.

**Hors périmètre, explicitement.**

- Créer ou supprimer une caserne, transférer sa propriété : super-admin, pas cet écran.
- L'abonnement et la facturation (ticket 026).
- Le nombre de créneaux par jour : jour et nuit sont fixes (`docs/PRD.md § 6.2`).
- Rouvrir une période verrouillée, verrouiller à la main : c'est l'écran des périodes.
- Les jours fériés : ils sont calculés, pas configurés.

**Limites assumées.**

- **Le fuseau est un choix dans une liste**, pas un champ libre : neuf fuseaux couvrent la
  métropole et l'outre-mer. Une caserne hors de cette liste est un cas qui n'existe pas au MVP, et
  un fuseau inventé casserait le calcul des dates limites.
- **Les heures jour/nuit sont de l'affichage.** Elles ne découpent rien : une astreinte reste
  « le 12 octobre, nuit ». L'écran l'écrit sous la section pour que personne ne croie avoir
  reprogrammé la garde.
- Les dates de surcharge passées ne sont pas nettoyées automatiquement : elles restent lisibles et
  retirables à la main. Effacer une règle sans le dire serait pire.

## 5. Écrans, états et textes

Route `/admin/parametres`, destination « Admin », accessible par l'icône `tune` de la barre
d'application de « Membres » (et retour par l'icône `group_outlined`). Tous les textes sont dans
`AppStrings`.

### 5.1 Structure

Titre d'écran : **« Paramètres »**. Sous-titre : « Les réglages de ta caserne. Ils s'appliquent à
tous les plannings créés ensuite. »

| Section | Contenu | Texte de compte |
|---|---|---|
| **La caserne** | Nom (`ChampTexte`), fuseau horaire (`ChampChoix`) | « Le nom vu par les membres et dans les courriels. » |
| **Créneaux** | Début et fin du créneau de jour (`ChampHeure`) | « Heures d'affichage. Elles ne découpent pas l'astreinte. » |
| **Effectif requis** | Jour, nuit (`ChampNombre`, 0–50) | « Le nombre de pompiers attendus sur chaque créneau. » |
| **Surcharges** | 7 lignes de jour de semaine + n lignes de date | « Les exceptions à l'effectif requis. » |
| **Saisie des disponibilités** | Jour limite (`ChampNombre`, 1–28) | « Le jour du mois précédent où la saisie se ferme. » |
| **Relances** | Rappel push, relance e-mail, rapport des retardataires (`ChampNombre`, 1–336 h) | « Le délai après la publication d'un planning. » |

La nuit est déduite et écrite : « La nuit couvre le reste : de 19:00 à 07:00. »

### 5.2 États

- **Chargement** : `LoadingSkeleton`, l'ossature des six sections — jamais une roue.
- **Erreur de lecture** : `EmptyState.erreur` avec « Réessayer ».
- **Non-admin** : `EmptyState` « Réservé aux administrateurs », icône `lock_outline`, aucun champ
  rendu.
- **Modifié** : le fil d'actions s'active ; la barre d'application porte un `SaveIndicator`
  compact.
- **Enregistrement** : bouton en chargement, champs inertes, indicateur « Enregistrement… ».
- **Enregistré** : indicateur « Enregistré », `SnackBar` « Paramètres enregistrés. »
- **Refusé (validation)** : bannière d'erreur en tête — « Deux réglages sont à corriger. » — et
  chaque champ fautif porte sa phrase sous lui. Les erreurs des champs déjà quittés s'affichent
  sans attendre l'enregistrement.
- **Refusé (serveur)** : bannière d'erreur avec la phrase du refus (droits, fuseau inconnu,
  document refusé) et « Réessayer ».

### 5.3 Messages de validation (les mêmes des deux côtés)

| Champ | Règle | Phrase |
|---|---|---|
| Nom | non vide, ≤ 80 | « Donne un nom à la caserne. » / « 80 caractères au maximum. » |
| Fuseau | dans la liste | « Choisis un fuseau horaire dans la liste. » |
| Heures | `HH:MM`, 00:00–23:59 | « Écris une heure comme 07:00. » |
| Début = fin | interdit | « Le jour ne peut pas commencer et finir à la même heure. » |
| Effectifs | entier 0–50 | « Un effectif va de 0 à 50. » |
| Jour limite | entier 1–28 | « Le jour limite va du 1 au 28. » (28 : le mois le plus court) |
| Délais | entier 1–336 | « Un délai va de 1 à 336 heures. » |
| Surcharge | au moins une valeur | « Une surcharge doit fixer l'effectif du jour ou celui de la nuit. » |
| Date de surcharge | `JJ/MM/AAAA` réelle | « Écris une date comme 31/12/2026. » |

### 5.4 Accessibilité

`ChampNombre` est un seul nœud (`MergeSemantics`) : libellé, valeur, et deux actions nommées
(« Diminuer l'effectif de jour », « Augmenter l'effectif de jour »). Les lignes de surcharge
annoncent leur état en toutes lettres. Le bouton d'enregistrement annonce son refus par une
région vivante, sans déplacer le focus.

## 6. Ce que la base garantit

Le brief n'existe pas sans la migration `0011`, qui rend les deux règles métier vraies même sans
l'écran :

- `stations.settings` porte une contrainte `check` appuyée sur `station_settings_valid()` : clés
  connues, clés obligatoires, types, bornes, format des heures, structure des surcharges.
- `shifts.required_count` est une colonne propre à chaque créneau : changer les paramètres ne la
  touche pas. C'est la règle « seulement les plannings créés ensuite », et elle est prouvée par un
  test.
- Un déclencheur recalcule `periods.deadline_at` des périodes `open` dans le fuseau de la caserne
  dès que le jour limite ou le fuseau change.
- Les politiques RLS de `stations` (migration `0007`) réservent déjà l'écriture à l'admin de la
  caserne : rien n'est réimplémenté, tout est testé.
