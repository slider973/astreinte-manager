# 029 — Abonnement Stripe par caserne — brief de design

Mode Impeccable : **Operate**. Monde visuel : le registre de garde (`DESIGN.md`).
Références : `docs/PRD.md § 6.6`, `docs/SCHEMA.md § 2.13, 7 et 8`, `tickets/in-progress/029-…`.

> `ui-ux-pro-max` interrogé avec `--stack flutter` et `--domain ux` sur « subscription billing
> status screen », « pricing plan card selection » : **aucune correspondance dans la base**
> (0 résultat, trois formulations). Le brief retombe donc sur `DESIGN.md` et sur les écrans
> d'administration déjà écrits (010, 014), ce qui est de toute façon la bonne source ici :
> l'écran d'abonnement n'est pas une page de vente, c'est une fiche d'état.

---

## 0. Le fait qui décide de tout

**Aucun compte Stripe n'existe.** Le propriétaire devra en créer un ; en attendant, et
peut-être longtemps, l'application tourne chez des casernes qui n'ont **rien** à payer et
**aucun** moyen de payer. Comme au ticket 024 pour Firebase, la règle est la même et elle prime
sur tout le reste de ce brief :

> **Une caserne sans configuration Stripe reste pleinement utilisable, en essai, sans carte.**
> Rien ne plante, rien ne clignote, rien ne réclame. L'écran d'abonnement dit l'état vrai —
> « L'abonnement n'est pas encore ouvert » — et ne propose pas un bouton qui échouerait.

Conséquence directe sur l'architecture visible : **le statut n'est jamais inventé côté client.**
`subscriptions.status` est la vérité, et `station_writable()` (migration `0007`) en tire déjà les
conséquences d'écriture depuis le ticket 008. L'écran ne fait que le montrer.

## 1. Où ça vit

Un cinquième écran de la destination **Admin**, au même niveau que Matrice, Suivi, Membres,
Paramètres et Périodes : `/admin/abonnement`. **Aucune destination de navigation ne s'ajoute**
(`DESIGN.md § Navigation` en fixe cinq, un admin les a toutes). On y va par l'icône
`card_membership` de la barre d'application des écrans « Paramètres » et « Périodes », et le
retour du navigateur ramène d'où l'on vient.

Pourquoi pas dans « Paramètres » ? Parce que « Paramètres » est **un document qu'on enregistre
d'un bloc** (migration `0011`, contrainte `stations_settings_valide`). L'abonnement n'a rien à
enregistrer : il a un état et deux portes de sortie vers un site externe. Les mélanger donnerait
un formulaire dont deux boutons quittent l'application au milieu d'une saisie non enregistrée.

## 2. L'écran, en trois blocs et jamais plus

Pas de carte ombrée, pas de grille de tarifs façon page d'accueil SaaS. Trois **blocs réglés**
(fond `surface`, filet 1 dp `outline-variant`, rayon 8, sans ombre), empilés, séparés par
`AppSpacing.xl`.

### Bloc 1 — l'état, en une ligne qu'on lit à 40 cm

Un `StatusBadge` + une phrase de date. L'état est porté par **marque + icône + libellé**, la
couleur en quatrième, exactement comme les autres familles d'état du produit. Cinq états,
alignés sur l'énumération `subscription_status` :

| Statut | Icône | Libellé | Encre (réemploi) | Deuxième ligne |
|---|---|---|---|---|
| `trialing` | `hourglass_top` | « Période d'essai » | ocre d'attente (`attribution.propose`) | « Gratuite jusqu'au 20 novembre — 60 jours. » |
| `active` | `verified` | « Abonnement actif » | vert (`planning.valide`) | « Prochain paiement le 20 novembre. » |
| `past_due` | `error_outline` | « Paiement en retard » | vermillon (`error`) | « Mets ta carte à jour avant le 4 décembre, sinon la caserne passera en lecture seule. » |
| `suspended` | `visibility` | « Caserne suspendue » | gris-encre hachuré (`periode.verrouillee`) | « Lecture seule depuis le 4 décembre. Rien n'a été supprimé. » |
| `cancelled` | `inventory_2` | « Abonnement résilié » | gris atténué (`planning.archive`) | « Lecture seule depuis le 4 décembre. Rien n'a été supprimé. » |

Trois décisions qui ne se négocient pas :

1. **« Suspendu » est gris, jamais rouge.** `DESIGN.md § Do's` : « Traiter *verrouillé*,
   *suspendu*, *annulé* comme des faits gris, pas comme des alarmes rouges. » Une caserne
   suspendue n'est pas en panne ; elle est en lecture seule, et c'est réversible.
2. **« Rien n'a été supprimé » est obligatoire** dès que l'état est `suspended` ou `cancelled`.
   C'est une promesse du produit (`docs/PRD.md § 6.6`) et c'est la seule phrase qui compte pour
   un chef de centre qui découvre l'écran un mardi soir.
3. **Seul `past_due` est rouge**, parce qu'il y a une action à faire et une échéance réelle :
   quatorze jours, puis la suspension (tâche planifiée de ce ticket).

Quand la date manque (pas d'essai posé, pas de période Stripe), la deuxième ligne **disparaît** ;
elle n'affiche jamais « Non définie ». Une phrase d'état incomplète vaut mieux qu'un trou nommé.

### Bloc 2 — les deux formules

Deux lignes, pas deux cartes. Chacune : libellé, prix, période, et un bouton
« S'abonner ». La formule annuelle porte en plus une mention d'économie **calculée**, jamais
écrite en dur : `12 × mensuel − annuel`.

```
Formules
──────────────────────────────────────────────
Mensuel                   12 € par mois
                                 [ S'abonner ]

Annuel                    120 € par an
Deux mois offerts.               [ S'abonner ]
```

- Les montants viennent **du serveur** (`create-checkout`, action `state`), jamais d'une
  constante Dart : le jour où le propriétaire règle un autre prix chez Stripe, l'écran suit sans
  recompilation. Sans configuration Stripe, le serveur rend les montants par défaut de
  `docs/PRD.md § 6.6` (12 €, 120 €) : on peut donc **annoncer le tarif avant d'avoir un compte**,
  ce qui est exactement ce qu'un chef de centre en essai veut savoir.
- Les deux boutons sont `secondaire` tant qu'aucun abonnement n'existe, pour ne pas donner deux
  boutons noirs pleins qui se disputent l'œil. Aucune formule n'est « recommandée » ni mise en
  avant par une pastille : on ne pousse pas une caserne de bénévoles vers l'engagement long.
- **Bloc masqué** quand l'abonnement est `active` : il n'y a plus rien à souscrire, et le
  changement de formule se fait dans le portail (bloc 3). Le montrer serait proposer un second
  abonnement.

### Bloc 3 — gérer

Un bouton `secondaire` **« Gérer mon abonnement »** (`open_in_new`), présent dès qu'un client
Stripe existe (donc dès la première souscription, même résiliée), avec sous lui la phrase qui dit
où il mène :

> « Carte bancaire, factures et résiliation se règlent sur la page sécurisée de Stripe. »

Annoncer la sortie de l'application est la même règle qu'au 024 pour la fenêtre du navigateur :
**une ouverture d'onglet ne surprend jamais.** L'icône `open_in_new` la double.

## 3. Les trois états de bord

### a. Stripe n'est pas configuré — **le cas d'aujourd'hui**

Bannière `information` (`info_outline`, jamais `erreur` : rien n'est cassé) :

> « L'abonnement n'est pas encore ouvert. Ta caserne fonctionne normalement pendant l'essai. »

Le bloc 1 reste entier et affiche l'essai avec sa date de fin. Le bloc 2 reste visible — les
tarifs sont une information, pas un bouton — mais **ses boutons sont désactivés avec leur raison
écrite à côté** (`DESIGN.md § Buttons` : un bouton grisé sans explication est un défaut) :
« Bientôt disponible. » Le bloc 3 est absent : il n'y a rien à gérer.

C'est le seul endroit du ticket où l'on choisit délibérément de montrer un contrôle inerte plutôt
que de le cacher : cacher les tarifs laisserait un chef de centre sans réponse à « ça coûtera
combien ? », qui est la question qu'il se pose pendant l'essai.

### b. L'essai est expiré mais la caserne n'est pas encore suspendue

La tâche planifiée tourne une fois par jour ; il existe donc une fenêtre où `trial_ends_at` est
passé et `status` vaut encore `trialing`. L'écran ne ment pas et ne panique pas : bannière
`attention` (`schedule`), « Ta période d'essai est terminée. Abonne-toi pour continuer à publier
des plannings. » Le statut reste « Période d'essai » — parce que c'est ce que la base dit — et la
deuxième ligne devient « Terminée le 20 novembre ».

### c. Chargement et erreur

Squelette à la forme des trois blocs, **jamais de roue au milieu de l'écran**
(`DESIGN.md § Don't`). Une lecture qui échoue donne un `EmptyState.erreur` avec « Réessayer » ;
une erreur survenue alors que l'état est déjà affiché se dit en bannière `erreur` et **ne vide
pas l'écran** — même règle qu'aux écrans 010 et 014.

Un membre ordinaire qui force l'URL voit `EmptyState` « Réservé aux administrateurs », et de
toute façon le routeur ferme la porte avant (préfixe `/admin`, `redirectionAuth`).

## 4. Le geste de souscription

Un seul aller-retour visible :

1. appui sur « S'abonner » → le bouton passe en **chargement, libellé conservé, largeur figée** ;
2. la fonction serveur rend une adresse → **nouvel onglet** ;
3. retour sur l'application : Stripe redirige vers `/admin/abonnement?paiement=ok`, l'écran
   **relit** l'état et affiche une bannière `information` « Paiement enregistré. »

Trois précautions :

- **L'écran ne croit pas le paramètre d'URL.** `?paiement=ok` déclenche une relecture, pas un
  changement d'état : c'est le webhook qui écrit, et il peut arriver deux secondes plus tard. Si
  la relecture montre encore `trialing`, la bannière dit « Paiement enregistré. Le statut se met
  à jour dans un instant. » — et l'écran relit une fois de plus, dix secondes après. Jamais de
  sablier infini.
- **L'abandon n'est pas un échec.** Retour par `?paiement=annule` : aucune bannière, aucun
  message. Quelqu'un a regardé le prix et fermé l'onglet ; ce n'est pas une erreur à annoncer.
- **Un refus serveur nomme sa sortie** : « L'abonnement n'est pas encore ouvert. » (non
  configuré), « Il faut être administrateur de cette caserne. » (droits), « Le paiement n'a pas
  pu s'ouvrir. Réessaie dans un instant. » (le reste).

## 5. Ce que ce ticket ne dessine pas

- **Le bandeau de lecture seule et le mode suspendu** : ticket 030. `AppBanner` a déjà sa
  variante `lecture-seule` depuis le 004, ce ticket ne la pose nulle part.
- Aucune notification d'abonnement : l'énumération `notification_type` n'en a pas, et en ajouter
  une pour dire « paie » à des bénévoles serait un mauvais usage du seul canal qui sert à dire
  « tu es d'astreinte ».
- Aucun écran de facture : les factures vivent chez Stripe, et le bloc 3 y mène.
- Aucune vue super-admin : ticket dédié.

## 6. Accessibilité et terrain

- Les trois boutons font 52 dp de haut, pleine largeur sur téléphone (`PrimaryButton`).
- Le badge d'état est annoncé en une phrase complète : « Période d'essai, gratuite jusqu'au
  20 novembre. » — pas « trialing ».
- Les montants prennent le cut **Mono** et `tabularFigures` : ce sont des nombres qui s'alignent.
- Tout est lisible en niveaux de gris : essai = sablier, actif = tampon, retard = point
  d'exclamation, suspendu = hachures. La couleur ne porte aucun de ces quatre faits seule.
