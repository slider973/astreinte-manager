# 070 — Les écrans de la PWA affichent des données périmées

- **Épopée** : E9 Release
- **Priorité** : P0
- **Dépend de** : 068
- **Branche** : `feat/070-fraicheur-ecrans-pwa`
- **PR** : —
- **Statut** : terminé le 2026-09-29 (PR créée)

## Contexte

Signalé par le propriétaire le 28 septembre 2026 : les astreintes n'apparaissent sur l'Accueil
qu'après un passage par l'onglet Astreintes. L'audit de couverture du même jour a trouvé la cause et
d'autres écrans du même type. Les onglets sont des `GoRoute` voisins, les contrôleurs ne sont pas
auto-disposés : un contrôleur ne relit que si un écran le lui demande. Seuls les mois (ticket 068)
et l'écran Membres ont un test de fraîcheur.

Causes relevées (lignes au commit `16bec64`) :

- `astreintes_providers.dart:83-90` : `build()` rend le cache local sans aller au réseau ; seul
  `astreintes_screen.dart:85-87` et `:100-101` appelle `rafraichir()`.
- `accueil_screen.dart:57-63` et `:71-72` : à l'ouverture et au retour au premier plan, l'Accueil
  ne relit que les mois, ni les astreintes ni les propositions (tirer et « Réessayer » seulement).
- `propositions_providers.dart:209-227` : accepter une proposition ne relit pas
  `astreintesControllerProvider` ; l'Accueil ne compte que les `accepted`
  (`astreintes_repository.dart:118`), le jour accepté y reste « libre ».
- `couche_notifications.dart:127-136` : un push reçu au premier plan ne relit que le centre de
  notifications.
- `caserne_providers.dart:28-33` : `etatCaserneProvider` (suspension, lecture seule, bannière) est
  lu une fois et jamais relu ; le commentaire l. 23 cite `relireEtatCaserne`, qui n'existe pas.
  Après un paiement (Stripe s'ouvre dans un autre onglet) ou une suspension en cours de session,
  les boutons gardent l'ancien état jusqu'au redémarrage.
- `session_providers.dart:57` : `appartenancesProvider` n'est relu qu'au changement de session ;
  un rôle retiré ou donné n'apparaît qu'au redémarrage, et un démarrage hors ligne laisse l'admin
  en simple membre sans nouvelle tentative.
- `matrice_screen.dart:124-128, 186` : la matrice n'est relue ni à l'ouverture ni au retour.
- `planning_providers.dart:223-230`, `suivi_providers.dart:201-206` : à la reconnexion du canal
  temps réel, aucune relecture de rattrapage.
- `matrice_screen.dart:450` : une publication n'invalide que le suivi ; un admin aussi pompier ne
  voit ses propositions qu'en passant par la Boîte.

## À faire

1. **Un seul endroit décide des relectures** : étendre le coordinateur du ticket 068
   (`RafraichissementPeriodes`) ou en créer le pendant, pour qu'au retour au premier plan et à
   l'ouverture d'un écran, les données qu'il affiche soient relues (au plus une fois toutes les
   10 s, jamais sous un geste ou une écriture en attente, jamais en vidant l'écran).
2. **Accueil** : relit astreintes et propositions à l'ouverture et au retour.
3. **Accepter / refuser** une proposition relit les astreintes.
4. **Push reçu au premier plan** : relit propositions, astreintes et mois, en plus du centre.
5. **État de la caserne** : créer `relireEtatCaserne`, appelée au retour au premier plan, au retour
   de la page Stripe, et après un refus `42501` ; un refus avec caserne accessible en écriture ne
   dit jamais « lecture seule » (même règle que l'iOS au ticket 068 : relire `station_access`).
6. **Appartenances et rôle** relus au retour au premier plan et au retour du réseau. Un rôle retiré
   fait sortir des écrans admin ; la base reste la seule autorité (règle des caches, CLAUDE.md).
7. **Matrice** relue à l'ouverture et au retour ; planning et suivi relus après une reconnexion du
   temps réel ; une publication relit aussi les propositions de l'admin.
8. **Faux backend** : `backend_memoire` gagne les astreintes et l'état de caserne, pour que le
   parcours vérifie « accepter → l'astreinte apparaît sur l'Accueil ».

## Critères d'acceptation

- Un test widget par écran partagé (Accueil, Astreintes, Boîte, matrice, bannière de suspension)
  simule `AppLifecycleState.resumed` après un changement en base et vérifie la donnée à jour.
- Test : accepter une proposition dans la Boîte puis revenir à l'Accueil → l'astreinte y est.
- Test : un push reçu au premier plan met à jour « À traiter » sur l'Accueil.
- Test : caserne suspendue puis réactivée pendant la session → les boutons se réactivent au retour
  au premier plan, sans redémarrage.
- Test : rôle admin retiré en base → au retour au premier plan, l'onglet Admin disparaît.
- Test : aucune relecture ne vide l'écran ni ne reconstruit une saisie en cours.
- Le parcours de bout en bout vérifie l'astreinte acceptée sur l'Accueil.
- `flutter analyze` sans avertissement, `flutter test` verts, `flutter build web` passe.
- Aucun nouveau cache local, ou alors branché dans `deconnexion.dart`.

## Hors périmètre

- L'app iOS (ticket 071).
- Plusieurs casernes (ticket 072).
- Le temps réel sur de nouvelles tables (demanderait une migration).
