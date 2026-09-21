# 031 — Interface super-admin — brief de design

Mode Impeccable : **Operate**. Monde visuel : le registre de garde (`DESIGN.md`).
Références : `docs/PRD.md § 3.3` et § 6.7, `docs/SCHEMA.md § 2.15, 3 et 4`,
`design/030-gating-suspension.md`, `tickets/in-progress/031-super-admin.md`.

> `ui-ux-pro-max --stack flutter` sur « internal operator console tenant list suspend
> account » : zéro résultat, comme aux 029 et 030. `--domain ux` rend trois règles
> utilisables, et elles sont reprises telles quelles : confirmer avant une action
> irréversible, ne pas laisser une table déborder sur téléphone, ne jamais réussir en
> silence.

---

## 0. Ce que cet écran est, en une phrase

**L'écran de l'éditeur, pas celui d'un client.** Une liste de casernes, cinq faits par
ligne, quatre actions. Aucune destination de navigation ne s'ajoute : le super-admin n'est
pas un membre, il n'a pas de barre de navigation, il a une URL.

Conséquence directe sur la forme : `EcranSimple` — pas `AppScaffold` — mais avec la
colonne élargie, parce qu'une liste de casernes n'est pas une colonne de connexion.

## 1. Le point qui décide de tout le reste : ce que le super-admin ne voit pas

Vérifié en base, pas supposé (`supabase/tests/super_admin_test.sql` le fige) :

| Table | Ce qu'un super-admin lit aujourd'hui | Verdict |
|---|---|---|
| `stations` | **les deux casernes, `settings` compris** | trop large |
| `stations` (update) | **`update` accepté sur une caserne dont il n'est pas membre** — nom, slug, fuseau, effectif requis, date limite — **et non tracé** | trop large |
| `periods`, `schedules`, `shifts`, `assignments`, `availabilities` | 0 ligne | correct, rien à faire |
| `memberships`, `profiles`, `invitations`, `audit_log` | 0 ligne hors ses propres casernes | correct |

La règle du produit est que **les données d'une caserne appartiennent à la caserne**.
Régler l'effectif requis d'un centre est une décision du centre ; l'éditeur n'a pas à
pouvoir le faire, et surtout pas sans laisser de trace.

La migration `0025` retire donc `is_super_admin()` des **trois** politiques de `stations`.
Après elle, une seule politique de tout le schéma cite encore `is_super_admin()` :
`super_admins_select_super_admin`. C'est une propriété, et elle se teste comme telle —
une requête sur `pg_policies`, pas une relecture à l'œil.

Tout ce que le super-admin peut faire passe alors par **quatre fonctions nommées**, et
par rien d'autre :

| Fonction | Écrit ? | Trace |
|---|---|---|
| `super_admin_stations()` | non | — |
| `super_admin_create_station(nom, fuseau)` | `stations` | `station.created` |
| `super_admin_set_station_suspended(caserne, suspendu, raison)` | `subscriptions` | `subscription.suspended` / `subscription.reactivated` |
| `super_admin_support_schedules(caserne, raison)` | `audit_log` seulement | `support.schedules_read` |

Les traces sont écrites dans l'`audit_log` **de la caserne concernée**, donc lisibles par
ses administrateurs (`audit_log_select_admin`). C'est ça, la garantie : la caserne voit
quand l'éditeur a regardé. Une trace que seul l'éditeur peut lire ne protège personne.

## 2. La consultation de support : une raison, une ligne d'audit, à chaque fois

Pas de « session de support » ouverte pour une heure. **Une lecture = une ligne d'audit**,
avec sa raison écrite à la main. Une fenêtre ouverte est une fenêtre qu'on oublie de
fermer ; un acte qui coûte une phrase est un acte qu'on ne fait pas par curiosité.

La raison est **obligatoire** (≥ 10 caractères) et le serveur refuse sans elle
(`reason_required`) — pas seulement le formulaire.

Ce que la consultation rend, et rien de plus : par mois, le statut du planning, ses dates
de publication et de validation, le nombre de créneaux et le décompte des attributions par
statut. **Aucun nom, aucun `user_id`, aucune disponibilité.** Un diagnostic d'éditeur est
« où en est le planning de novembre », jamais « qui est de garde le 12 ».

La feuille le dit avant l'action, pas après : « Cette consultation est inscrite au journal
d'audit de la caserne. Ses administrateurs la verront. »

## 3. La ligne de caserne

Un **bloc réglé** (filet 1 dp `outline-variant`, rayon 8, sans ombre), jamais une carte
ombrée ni une grille de cartes identiques. Trois étages :

1. le nom en `titre-section`, et à droite le `StatusBadge` d'abonnement — `descripteurAbonnement`
   du 029, réemployé tel quel, **aucune encre nouvelle** ;
2. une ligne de faits en `corps-secondaire`, nombres en `AppTextStyles.nombre` :
   « 9 membres actifs · 1 administrateur » — et, quand il y a zéro administrateur actif,
   la mention passe en `attention` parce que c'est le seul défaut qui appelle une action ;
3. « Créée le 3 mars 2026 » et « Dernier planning publié : novembre 2026 », ou
   « Aucun planning publié » — un fait gris, pas un vide.

Les actions sont des `TextButton` de 44 dp alignés en bas du bloc : « Inviter un
administrateur », « Suspendre » ou « Réactiver », « Consulter les plannings ».
Sur compact, elles s'enroulent (`Wrap`) : c'est la réponse à « les tables débordent sur
mobile » — il n'y a pas de table, il y a des blocs qui s'empilent.

## 4. Les trois actions, et leur protection

- **Créer une caserne** : feuille de bas d'écran, nom + fuseau. Le slug est **dérivé du
  nom côté serveur** avec un suffixe en cas de collision : c'est un détail technique, il
  n'a rien à faire dans un formulaire. La caserne naît en essai de 60 jours par le trigger
  du 029, rien à saisir. À la réussite, la feuille enchaîne **immédiatement** sur
  l'invitation du premier administrateur : une caserne sans administrateur est un
  cul-de-sac, on ne laisse pas l'éditeur y arriver par distraction.
- **Inviter le premier administrateur** : le **même** chemin que le ticket 006 —
  l'Edge Function `invite-member` avec `role: "admin"`, qui appelle `create_invitation`.
  Aucun second chemin d'invitation n'est écrit ; `create_invitation` gagne une seule
  branche (« admin actif de cette caserne **ou** super-admin ») et une clé
  `by_super_admin` dans sa ligne d'audit.
- **Suspendre** : action `danger`, **confirmation obligatoire** avec une raison, et la
  phrase qui compte — « Rien n'est supprimé. La caserne passe en lecture seule. » C'est la
  même promesse qu'au 030 § 2, et elle est due ici aussi.
  **Réactiver** n'est pas destructeur, donc pas de confirmation : un bouton, un résultat
  annoncé. La réactivation d'une caserne sans abonnement souscrit **reporte la fin d'essai
  à au moins 30 jours** — sans quoi la tâche de 3 h 30 la re-suspendrait dans la nuit, et
  une réactivation qui se défait toute seule est un bug, pas une action.

Chaque action réussie le dit (« Caserne suspendue. » / « CIS … créée. ») : pas de succès
silencieux. Chaque échec nomme le problème **et** la sortie, comme partout ailleurs.

## 5. La garde de route

`/superadmin`, gardée **par la même mécanique que `/admin`** : `redirectionAuth`, fonction
pure, testée sans routeur. Trois différences avec le préfixe admin, et elles sont toutes
nécessaires :

- un super-admin **sans aucune caserne** (le cas nominal de l'éditeur) est en
  `EtatAuth.sansCaserne` et serait envoyé sur « Aucune caserne » : la garde le laisse
  passer sur `/superadmin`, et seulement là ;
- le statut n'est pas dans la session, il vient d'un appel : tant qu'il est **inconnu**,
  la garde ne tranche pas et laisse l'écran afficher son squelette. Rediriger sur un
  statut non résolu perdrait l'URL tapée à froid ; l'écran, lui, ne peut rien montrer sans
  droits, puisque toutes ses données viennent de fonctions qui refusent ;
- le routeur écoute désormais `estSuperAdminProvider` en plus de `etatAuthProvider` :
  sans ça, la réponse arrive et personne ne la lit.

Quand le statut revient `false`, l'écran affiche un `EmptyState` sobre le temps que le
routeur reprenne la main — « Cet écran est réservé à l'éditeur de l'application. » Pas de
message d'erreur : se tromper d'URL n'est pas une faute.

## 6. Accessibilité et terrain

Cet écran n'est pas utilisé avec des gants dans un véhicule, mais les règles ne changent
pas de porte : 44 dp partout, `Semantics` sur chaque action avec le nom de la caserne dans
l'annonce (« Suspendre CIS Saint-Martin » — quatre boutons « Suspendre » ne se distinguent
pas à l'oreille), état jamais porté par la couleur seule, squelette à la forme du contenu
plutôt qu'un rond qui tourne.
