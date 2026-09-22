# 053 — L'écran super-admin n'offre aucune déconnexion

- **Épopée** : E9 Release
- **Priorité** : P2
- **Dépend de** : 031
- **Branche** : `feat/053-superadmin-sans-deconnexion`
- **PR** : —
- **Statut** : en cours depuis 2026-09-22

## Contexte

Relevé par le brief de design du ticket 052, le 21 septembre 2026, pendant l'inventaire des
écrans sans issue. `/superadmin` n'est pas une impasse de route, c'est l'accueil de l'éditeur.
Mais il ne porte aucune déconnexion : la personne qui gère les casernes et les abonnements ne
peut pas quitter son compte depuis l'application.

C'est le compte le plus sensible du produit, et c'est le seul dont on ne peut pas sortir. La règle
des caches locaux de `CLAUDE.md` vaut ici plus qu'ailleurs : « un téléphone de caserne est prêté,
un véhicule est partagé ». Un éditeur qui ferme l'onglet sans se déconnecter laisse une session
super-admin sur l'appareil.

## À faire

- Donner à l'écran super-admin une déconnexion, au même endroit et de la même forme que sur les
  autres écrans qui en ont une (« Aucune caserne », le profil), via `BoutonDeconnexion` et la
  méthode qui oublie les caches dans `lib/core/session/deconnexion.dart`.
- Vérifier qu'après déconnexion, aucune donnée super-admin ne reste lisible sur l'appareil, et que
  la destination mémorisée ne ramène pas la personne suivante sur cet écran.
- Relire le brief `design/031-super-admin.md` : s'il avait écarté la déconnexion pour une raison,
  la raison doit être réexaminée à la lumière du 052, pas contournée.

## Critères d'acceptation

- L'écran super-admin porte une déconnexion, visible sans défilement, cible de 44 pt au moins.
- Après déconnexion, un test vérifie que les caches super-admin sont vidés et qu'un rechargement
  mène à la connexion, pas à `/superadmin`.
- `flutter analyze` sans avertissement, `flutter test` verts, `flutter build web` qui passe.
