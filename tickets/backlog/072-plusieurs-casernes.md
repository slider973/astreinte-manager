# 072 — Un pompier dans plusieurs casernes, de bout en bout

- **Épopée** : E9 Release
- **Priorité** : P1
- **Dépend de** : 070, 071
- **Branche** : `feat/072-plusieurs-casernes`
- **PR** : —
- **Statut** : à faire

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
