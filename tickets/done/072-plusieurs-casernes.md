# 072 — Un pompier dans plusieurs casernes, de bout en bout

- **Épopée** : E9 Release
- **Priorité** : P1
- **Dépend de** : 070, 071
- **Branche** : `feat/072-plusieurs-casernes`
- **PR** : —
- **Statut** : terminé le 2026-10-04 (PR créée)

## Contexte

Demande du propriétaire le 28 septembre 2026 : un collaborateur doit pouvoir être dans plusieurs
casernes. Le PRD le prévoit (l. 160 : « Un sélecteur de caserne apparaît dans ce cas ») et la base
le permet (`memberships unique (station_id, user_id)`), mais l'audit du même jour a relevé :

- Le sélecteur n'existe que dans le Profil (`bloc_caserne.dart:27, 94`) côté PWA ; iOS l'a dans
  Réglages (`SettingsView.swift:71`).
- Après acceptation d'une invitation d'une seconde caserne, on reste dans l'ancienne
  (`invitation_providers.dart:77-84` relit sans appeler `choisir`).
- Un membre de B ne voit une invitation de A que par le courriel (`aucune_caserne_screen.dart`).
- Un push ou un lien d'une caserne B s'ouvre dans A : le push ne porte que `data.route`
  (`destinationInterne`, `PushDestination.swift:28-57`), alors que `notifications.station_id`
  existe.
- Le centre de notifications mêle les casernes (`centre_providers.dart:84-88`).
- `apply_auto_proposal` (`0028:172-190`) peut proposer la même personne au même créneau dans deux
  casernes.
- iOS : pendant la bascule, l'accueil affiche le nom de B avec les propositions de A
  (`AppStore.swift:259-263`).
- Les caches d'une caserne où le membre a été désactivé ne sont pas effacés
  (`oubli_local.dart:92`).
- Aucun test à deux appartenances (SQL, widget, store, déconnexion).

## Décisions du propriétaire (28 septembre 2026)

1. **Même personne, même créneau, deux casernes** : le planning automatique ne la propose pas si
   elle est déjà proposée ou acceptée ailleurs sur un créneau qui chevauche ; l'admin voit qu'elle
   est prise ailleurs (sans voir le détail de l'autre caserne).
2. **Lien ou push d'une autre caserne** : l'app bascule d'elle-même vers la bonne caserne et un
   bandeau dit quelle caserne est ouverte.

## À faire

1. `supabase-dev` : `station_id` dans les données du push (`send-notification`) ; règle 1 dans
   `apply_auto_proposal` sans exposer les données d'une autre caserne (fonction `security definer`
   qui ne rend qu'un booléen « pris ailleurs ») ; tests SQL à deux appartenances.
2. PWA et iOS : bascule sur lien ou push (décision 2) ; bascule après acceptation d'une invitation ;
   invitations en attente visibles pour un membre déjà rattaché ; sélecteur accessible hors du
   Profil (navigation ou accueil) ; centre de notifications filtré ou étiqueté par caserne ; iOS
   n'affiche jamais l'état de A pendant la bascule ; caches d'une caserne désactivée effacés.
3. Documents : PRD et WORKFLOWS décrivent les deux décisions.

## Critères d'acceptation

- Tests SQL : un membre de B accepte une invitation de A et a deux appartenances actives ; la
  proposition automatique ne double pas une personne prise ailleurs ; aucune donnée de B lisible
  depuis A.
- Tests PWA et iOS : bascule sur push d'une autre caserne avec bandeau ; bascule après invitation ;
  aucune donnée de l'ancienne caserne affichée après bascule ; déconnexion à deux casernes efface
  tout.
- CI verte (PWA et fork iOS), build TestFlight publié.

## Hors périmètre

- Vue consolidée de plusieurs casernes sur un même écran.

## Livraison

**Fait**, en trois chantiers fusionnés en squash sur `main` :

- **Base** : [#84](https://github.com/slider973/astreinte-manager/pull/84) (`f060939`) —
  migration `0040_plusieurs_casernes.sql` (`member_taken_elsewhere`, motif `taken_elsewhere` dans
  `apply_auto_proposal`, colonnes « pris ailleurs » de `availability_matrix`), `station_id` et
  `?station=` dans les push, tests SQL à deux appartenances. Revue : « prêt », aucun bloquant.
- **PWA** : [#86](https://github.com/slider973/astreinte-manager/pull/86) (`7e7f26c`) — sélecteur
  de caserne, invitations en attente, bascule sur push ou lien avec bandeau et « Revenir », centre
  filtré, « Astreinte ailleurs » chez l'admin, caches d'une caserne quittée effacés. Revue : deux
  tours ; les deux bloquants du premier (démarrage à froid, écrans d'administration) levés ; sondes
  de sécurité (lien forgé, cache admin hors ligne) 15/15 sans accès admin.
- **iOS** : [#88](https://github.com/slider973/astreinte-manager/pull/88) (`8dc2e41`, commun
  avec le 073) — pointeur `foco/` sur `c1b75da`, `docs/IOS.md` § 4 octies, et correctif PWA du
  double point après un nom abrégé (`AppStrings.nomEnFinDePhrase`).
- **PR du fork** `slider973/Foco` : [Foco#17](https://github.com/slider973/Foco/pull/17)
  (`cb5be0c`, ce ticket) et [Foco#18](https://github.com/slider973/Foco/pull/18) (`c1b75da`,
  ticket 073, visé par le pointeur).
- **Courses `iOS` vertes** : [37195706808](https://github.com/slider973/Foco/actions/runs/37195706808),
  [37196395636](https://github.com/slider973/Foco/actions/runs/37196395636) (`main` du fork,
  `cb5be0c`), [37197187365](https://github.com/slider973/Foco/actions/runs/37197187365),
  [37197977329](https://github.com/slider973/Foco/actions/runs/37197977329) (`main`, `c1b75da`,
  291 tests) ; zéro avertissement Swift. Une course rouge **non volontaire**,
  [37196427941](https://github.com/slider973/Foco/actions/runs/37196427941) (Foco#18), corrigée.
- **TestFlight** : **1.0 (108)**, course
  [37199233742](https://github.com/slider973/Foco/actions/runs/37199233742).
- **Revue iOS** (072 et 073 ensemble) : « prêt », aucun bloquant.

**Suites à faire** (non bloquantes) :
- PWA : tests de lien forgé gardés au dépôt (les sondes de la revue n'ont pas été commitées) ;
  relance du routeur quand une bascule de caserne échoue.
- iOS (revue commune 072/073) : `invitationInvitedBy` double encore le point après un nom abrégé ;
  « Refuser » reste actif dans une caserne en lecture seule ; deux tests manquants relevés par la
  revue.

**Reste à vérifier par le propriétaire sur l'iPhone** (TestFlight 1.0 (108)) :
- [ ] push d'une autre caserne : l'app bascule, le bandeau dit laquelle est ouverte, « Revenir »
  ramène à la précédente ;
- [ ] pendant la bascule, aucune donnée de l'ancienne caserne à l'écran ;
- [ ] sélecteur sur l'accueil avec deux casernes, non-lues des autres casernes comptées ;
- [ ] invitation d'une seconde caserne visible sur l'accueil, puis rejointe : la nouvelle caserne
  s'ouvre ;
- [ ] centre de notifications limité à la caserne ouverte, passerelle vers l'autre ;
- [ ] accès retiré dans la caserne ouverte : bascule vers l'autre, sans « Revenir ».
