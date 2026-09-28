# 071 — L'app iOS garde la lecture seule et des données périmées

- **Épopée** : E9 Release
- **Priorité** : P0
- **Dépend de** : 068
- **Branche** : `feat/071-fraicheur-ecrans-ios`
- **PR** : —
- **Statut** : à faire

## Contexte

Audit de couverture du 28 septembre 2026, volet iOS (submodule `foco/`, fork privé
`slider973/Foco`, lignes au pointeur `0ab920d`). Les stores sont partagés, donc une écriture
locale se voit partout, et le retour au premier plan relit la saisie, le planning et le centre.
Restent :

- `PlanningJourney.swift:107` : `readOnly` n'est posé qu'au `start` ; `becameActive()`
  (`AppStore.swift:290-294`) ne le resynchronise pas. Une caserne réactivée après paiement garde
  « Accepter » grisé jusqu'au redémarrage (et l'inverse pour une suspension).
- `AppStore.swift:381-383` : un push reçu au premier plan ne relit que le centre, pas le planning
  ni les propositions.
- `AppStore.swift:300, 307` : le `.task` de l'accueil est gardé par `isStarted` ; revenir sur
  l'accueil depuis un écran enfant ne relit rien.
- `AppStore.swift:224` : rôle et appartenances relus seulement à l'entrée.
- `StationPlanningView.swift:49` : le planning de la caserne s'ouvre sans `reloadCached`.
- `PlanningJourney.swift:319` (écran « Équipe ») jamais relu ; « Aujourd'hui » et le détail d'un
  jour ne forcent pas la relecture du mois (`TodayCrewView.swift:52`, `ShiftDetailView.swift:57`).
- Le câblage `scenePhase` (`HomeView.swift:132`) n'est pas testé : les tests appellent
  `becameActive()` à la main.

## À faire

Dans le fork, branche `fix/071-fraicheur`, PR vers `main` du fork.

1. `becameActive()` relit `station_access` et resynchronise `readOnly` partout (saisie, planning).
2. Push reçu au premier plan : relit planning, propositions et saisie en plus du centre.
3. Retour sur l'accueil depuis un écran enfant : relecture (au plus une fois toutes les 10 s).
4. Rôle et appartenances relus au retour au premier plan ; un rôle retiré sort des écrans admin
   (la base reste la seule autorité, `LocalWipe` inchangé).
5. Planning de la caserne, « Équipe », « Aujourd'hui » et détail d'un jour : relecture à
   l'ouverture.
6. Aucune relecture sous un geste ou une écriture en attente (même règle que la PWA au 068).

## Critères d'acceptation

- Tests de store : caserne réactivée puis `becameActive` → `readOnly` faux sur la saisie et le
  planning ; l'inverse pour une suspension.
- Test : push reçu au premier plan → propositions et planning relus.
- Test : retour sur l'accueil depuis un enfant → relecture ; deux retours en moins de 10 s → une
  seule.
- Test : rôle retiré en base → au retour, plus d'écran admin.
- Un test vérifie le câblage `scenePhase` → `becameActive` (XCUITest ou test de la vue).
- CI `iOS` du fork verte, zéro avertissement Swift ; pointeur `foco/` sur le commit de `main` du
  fork ; `docs/IOS.md` à jour.
- Un build TestFlight est publié.

## Hors périmètre

- La PWA (ticket 070).
- Plusieurs casernes (ticket 072).
