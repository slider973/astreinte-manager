# 068 — La saisie iOS refusée en « lecture seule » sur un mois ouvert

- **Épopée** : E9 Release
- **Priorité** : P0
- **Dépend de** : 066, 067
- **Branche** : `feat/068-saisie-ios-refusee-lecture-seule`

## Contexte

Bug de production signalé par le propriétaire le 28 septembre 2026, sur son iPhone, avec l'app iOS
**Astreinte SP** en TestFlight 1.0 (102) (submodule `foco/`, fork privé `slider973/Foco`).

Constats en production (projet `axvflcgwsmrjrnjheoly`, heure UTC) :

- Utilisateur `4c75c3e7-078e-4844-b4b2-6e159de141f5` (membre actif), caserne
  `c1ad75e2-e6be-4f81-a562-bae2238b9975` : abonnement `trialing` jusqu'au 2026-11-20,
  `station_writable` vrai. Périodes : 2026-09 et 2026-10 `locked`, 2026-11 `open` (ouverte par
  l'admin à 10:12:30), date limite 2026-10-15.
- Journaux PostgREST de l'iPhone : de 10:17:03 à 10:17:30, navigation répétée entre septembre,
  octobre et novembre (GET `periods`, `availabilities`, `availability_preferences`) ; 10:17:37
  POST `availabilities` upsert → **201** ; 10:17:38 DELETE (2026-11-03, nuit) → 200 ; 10:17:49 puis
  10:17:58 POST upsert → **403** (« new row violates row-level security policy for table
  "availabilities" »).
- Après coup, aucune ligne de novembre en base pour cet utilisateur. Un INSERT manuel sous son
  identité, dans une transaction annulée, pour `2026-11-02` jour `available`, **passe** : la base
  n'a rien contre novembre, c'est le **contenu du lot** envoyé par l'app qui portait au moins une
  ligne refusée.
- À l'écran : « Ta caserne est passée en lecture seule. Tes dernières modifications n'ont pas été
  enregistrées. » avec « Recharger », puis la bannière « Caserne suspendue : la saisie est
  fermée ». **Les deux messages sont faux** : la caserne n'est ni suspendue ni en lecture seule.
- Le mois de novembre, ouvert par l'admin pendant que l'app tournait, n'est apparu **qu'après un
  redémarrage**.

## À faire

Dans le fork, branche `fix/068-saisie`, PR vers `main` du fork.

1. **Reproduire avant de corriger** : un test du contrôleur contre le faux backend, sur le scénario
   exact (septembre et octobre verrouillés, navigation septembre → octobre → novembre, coups de
   pinceau et un effacement en novembre). Le faux backend lève `42501` dès qu'un lot porte une
   ligne d'un mois fermé, comme PostgREST. Le test échoue sur l'ancien code (course de CI rouge à
   l'appui), la cause exacte est écrite dans `docs/IOS.md`.
2. **Corriger la cause** : un lot ne contient que des lignes d'un seul mois **ouvert** ; une ligne
   d'un mois verrouillé n'est jamais envoyée, elle est retirée de la file et l'écran le dit
   (`staleQueueDropped`). Dates en date civile, sans conversion UTC qui décale d'un jour, vérifiées
   pour chaque case.
3. **Ne plus mentir sur la cause d'un refus** : un `42501` relit `station_access` ; `writable =
   false` → « lecture seule / suspendue » ; sinon relecture des périodes : mois fermé entre-temps →
   « Le mois vient d'être verrouillé… » ; sinon erreur neutre avec « Réessayer », sans jamais parler
   de suspension. Phrases de la PWA (`AppStrings`).
4. **Nouveau mois visible sans redémarrer** : relire les périodes (et l'écran) au retour au premier
   plan, à l'ouverture des Disponibilités et de l'accueil, et par tirer-pour-actualiser dans les
   Disponibilités.
5. **Aucune écriture en production** : toute vérification d'un lot se fait contre le Supabase local.

## Critères d'acceptation

- Un test reproduit le scénario de production et échouait sur l'ancien code (course rouge liée).
- Aucun lot envoyé ne mélange plusieurs mois ni ne porte de ligne d'un mois verrouillé ; une
  ligne devenue inenvoyable est retirée de la file et annoncée.
- Chaque case d'un mois a la bonne date ISO (test sur septembre, octobre et novembre 2026).
- Un refus avec caserne accessible en écriture n'affiche jamais « lecture seule » ni
  « suspendue » : trois tests (caserne suspendue, mois verrouillé entre-temps, refus neutre).
- Une période ajoutée pendant que l'app tourne apparaît après le retour au premier plan (test) ;
  tirer-pour-actualiser dans les Disponibilités.
- CI `iOS` du fork verte, zéro avertissement Swift ; pointeur `foco/` sur le commit de `main` du
  fork ; `docs/IOS.md` décrit la cause et la correction.
- Un nouveau build TestFlight est publié, et le propriétaire vérifie la saisie de novembre sur
  son iPhone.
