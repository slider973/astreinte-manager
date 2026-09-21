# 030 — Mode suspendu et bannières — brief de design

Mode Impeccable : **Operate**. Monde visuel : le registre de garde (`DESIGN.md`).
Références : `docs/PRD.md § 6.6` et § 7.6, `docs/SCHEMA.md § 2.13 et 7`, `design/029 § 5`,
`tickets/in-progress/030-gating-suspension.md`.

> `ui-ux-pro-max --stack flutter` interrogé sur « read-only mode banner subscription
> suspended » : trois résultats hors sujet (thème sombre, `StreamSubscription`). Rien à en
> tirer, comme au 029. Le brief retombe sur `DESIGN.md`, qui a déjà tout ce qu'il faut : la
> variante `lecture-seule` d'`AppBanner` existe depuis le 004 et n'a jamais été posée.

---

## 0. Ce que ce ticket change, en une phrase

La base refuse déjà les écritures d'une caserne suspendue (`station_writable`, migration
`0007`). **Ce ticket ne change aucun droit** : il rend le refus prévisible au lieu de le
laisser survenir.

Trois écrans le traitaient déjà — matrice, suivi, propositions — mais **après coup** : on
appuie, la base refuse, la bannière apparaît. Un geste perdu par écran, au mieux ; dans la
grille de saisie, une peinture de quatorze cases perdue. Le mode suspendu se sait **avant**
le premier geste.

## 1. La seule brique nouvelle : l'état de la caserne, lisible par tout le monde

`subscriptions` n'est lisible que des administrateurs (`subscriptions_select_admin`, 0007).
Un simple membre ne peut donc **pas** savoir pourquoi sa grille est inerte — c'est
exactement le mystère que le ticket veut lever.

Une fonction `station_access(uuid)` rend à **tout membre actif** les quatre faits dont
l'interface a besoin, et rien de plus : `writable`, `status`, `trial_ends_at`,
`suspended_at`. Aucun identifiant du prestataire, aucun montant : ce n'est pas l'écran
d'abonnement, c'est le drapeau qui pilote les autres écrans.

`writable` est calculé par `station_writable()` elle-même. **Une seule définition du droit
d'écrire**, et l'écran ne peut pas diverger de la RLS.

Côté PWA, un seul provider, `etatCaserneProvider`, et son dérivé `lectureSeuleCaserneProvider`.
Règle non négociable : **une lecture en échec n'invente jamais une suspension.** Réseau
coupé, fonction absente, réponse illisible → la caserne est réputée ouverte, exactement comme
`StatutAbonnement.depuisSql` retombe sur l'essai. Un faux bandeau de lecture seule bloquerait
une caserne qui paie ; un bandeau manquant ne coûte qu'un refus serveur, celui d'aujourd'hui.

## 2. Le bandeau de lecture seule

`AppBanner` variante `lecture-seule` : gris hachuré, icône `visibility`, **jamais rouge**
(`DESIGN.md § Do's`). Elle se pose telle quelle, sans nouvelle variante ni nouvelle encre.

Deux phrases, selon qui regarde — parce que la sortie n'est pas la même :

| Qui | Texte | Détail | Action |
|---|---|---|---|
| membre | « Caserne suspendue : tu peux consulter, pas modifier. » | « Rien n'a été supprimé. Contacte ton chef de centre. » | aucune |
| admin | idem | « Rien n'a été supprimé. Reprends l'abonnement pour rouvrir la saisie. » | « Abonnement » → `/admin/abonnement` |

**« Rien n'a été supprimé » est obligatoire**, même règle qu'au 029 § 2 : c'est une promesse
du produit (`PRD § 6.6`, § 7.6) et la seule phrase qui compte pour qui découvre l'écran.

La bannière garde sa place dans l'ordre de priorité déjà écrit : erreur > hors-ligne >
**lecture-seule** > verrouillé > attention > information. Une caserne suspendue hors ligne
annonce d'abord le réseau : c'est lui qui redeviendra vrai en premier.

Écrans concernés — **tous ceux qui écrivent**, et eux seuls :
« Mon mois » (grille et quotas), « Propositions », et les cinq écrans d'administration
(matrice, suivi, membres, périodes, paramètres). L'écran d'abonnement, lui, ne la porte pas :
il *est* l'explication.

## 3. Les actions désactivées disent leur raison

`PrimaryButton` l'impose déjà par assertion : `onPressed: null` sans `raisonDesactivation`
ne compile pas mentalement. Ce ticket remplit la raison partout où elle manquait, avec une
phrase par famille de geste, pas une phrase générique :

- grille : les cases restent lisibles mais inertes, et l'appui **répond** —
  « Caserne suspendue : la saisie est fermée. Tu peux consulter tes disponibilités, pas les
  changer. » (la chaîne existe déjà, elle n'était jamais atteinte avant un refus serveur) ;
- quotas et commentaire du mois : mêmes champs, désactivés, même raison ;
- propositions : « Caserne suspendue : les réponses sont bloquées. Contacte ton chef de
  centre. » ;
- périodes : « Abonnement suspendu : la caserne est en lecture seule, les mois ne bougent
  plus. » ;
- membres : « Abonnement suspendu : la caserne est en lecture seule, les invitations
  ne partent plus. » ;
- paramètres : « Abonnement suspendu : les réglages ne peuvent pas être enregistrés. »

Rien n'est **caché**. Un bouton retiré laisse un chef de centre sans réponse à « pourquoi je
ne peux plus inviter ? » ; un bouton gris avec sa phrase répond. C'est la règle du 029 § 3a,
appliquée une seconde fois.

## 4. Le bandeau d'essai — trois paliers, et rien entre eux

Pour les **administrateurs seulement** : un pompier n'a pas à savoir que sa caserne a
dix-sept jours d'essai devant elle, il n'a rien à y faire.

| Reste | Variante | Texte | Action |
|---|---|---|---|
| > 14 j | *aucune bannière* | — | — |
| ≤ 14 j | `information` (bleu de réglure, `info_outline`) | « Essai jusqu'au 20 novembre — il reste 14 jours. » | « Abonnement » |
| ≤ 3 j | `attention` (ocre, `schedule`) | « Essai jusqu'au 20 novembre — il reste 3 jours. » | « Abonnement » |
| terminé, pas encore suspendue | `attention` | « Ta période d'essai est terminée. La caserne passera en lecture seule. » | « Abonnement » |

Les deux paliers du ticket — J-14 et J-3 — sont des **seuils d'escalade**, pas deux
notifications. Une bannière permanente pendant soixante jours serait 48 dp de grille volés
chaque jour pour redire une chose sans échéance ; c'est la même décision qu'au 011 pour la
fermeture de mois, qui n'apparaît qu'à J-3.

L'`information` est la seule variante fermable (invariant d'`AppBanner`) : elle décrit un
délai, pas un blocage. Fermée, elle revient au palier suivant — l'ocre de J-3 n'est pas la
même bannière.

Le jour restant est calculé sur l'horloge locale via un provider injectable, jamais sur
`DateTime.now()` en dur : « il reste 3 jours » doit se tester sans attendre trois jours.

## 5. Les courriels : aucun second mécanisme

Deux nouveaux `notification_type`, et la voie existante — `notify(...)` depuis une tâche
planifiée, `notification_outbox`, `send-notification` — sans une ligne d'envoi nouvelle :

| Type | Quand | Destinataires | Canaux | Dédoublonnage |
|---|---|---|---|---|
| `subscription_trial_ending` | essai à J-7, tâche quotidienne | admins actifs | email + inapp | `subscription_trial_ending:<caserne>:<date de fin>` |
| `subscription_suspended` | au moment du passage en `suspended` | admins actifs | email + inapp | `subscription_suspended:<caserne>:<jour>` |

Le second est émis **par `cron_suspend_subscriptions` elle-même**, dans la transaction qui
suspend : la notification et le fait qu'elle annonce ne peuvent pas diverger.

Le canal `email` est explicite ici, contre l'habitude « push + inapp » des autres types : un
chef de centre ne règle pas un abonnement depuis une notification poussée au portail, et
c'est le courriel qui atteint quelqu'un qui n'a pas ouvert l'application depuis trois
semaines — cas nominal d'une fin d'essai.

Lien profond : `/admin/subscription`, cinquième destination publique de
`docs/WORKFLOWS.md § 8`, traduite en `/admin/abonnement` pour un administrateur et **ignorée
pour un membre** — `destinationInterne` rend `null`, et on retombe sur l'accueil sans message
d'erreur, comme pour `/admin/schedule/<mois>`.

Aucune notification n'est envoyée aux **membres**. Le 029 le disait déjà : le canal sert à
dire « tu es d'astreinte », pas « paie ».

## 6. Le point qui ne se négocie pas : la lecture reste entière

`PRD § 6.6` : « Suspendu : lecture seule pour tous. » § 7.6 : « L'historique n'est jamais
supprimé. » Donc, pour un membre d'une caserne suspendue :

- « Mes astreintes » et le planning de la caserne s'ouvrent, en ligne **et depuis le cache** ;
- « Mon mois » affiche la grille, les compteurs, les quotas et le commentaire, en lecture ;
- « Propositions » liste les propositions reçues, avec leurs dates et leurs créneaux ;
- le centre de notifications s'ouvre, et `read_at` reste écrivable — marquer une
  notification lue n'est pas une écriture métier et **ne passe pas par `station_writable`**
  (`grant` de colonne, `docs/SCHEMA.md § 5`). Vérifié, rien à changer.

Un test de bout en bout le fige : caserne `suspended`, membre connecté, les trois écrans
rendent leur contenu, aucun `EmptyState`, aucune bannière d'erreur.

## 7. Accessibilité et terrain

- La bannière est un `Semantics(container: true)` ; l'état de lecture seule est annoncé une
  fois, en haut, et non répété sur chaque case — soixante-deux « désactivé » à la suite
  rendraient l'écran illisible au lecteur d'écran.
- Les hachures portent l'état sans la couleur : l'écran reste juste en niveaux de gris et au
  soleil.
- Le bouton « Abonnement » de la bannière est un `TextButton` de 44 dp minimum, déjà garanti
  par `AppBanner`.
- Aucun `SnackBar` pour annoncer la suspension : un état persistant ne se dit pas dans
  quelque chose qui disparaît.
