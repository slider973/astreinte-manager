# 057 — Le jeton d'appareil des notifications n'est pas branché sur l'oubli

- **Épopée** : E6 Notifications
- **Priorité** : P2
- **Dépend de** : 024, 053
- **Branche** : `feat/057-jeton-appareil-hors-oubli`
- **PR** : —
- **Statut** : terminé le 2026-09-26 (PR créée)

## Contexte

Relevé par la revue du ticket 053, le 22 septembre 2026, en vérifiant la règle des caches locaux
de `CLAUDE.md` : « Tout ce qui est écrit sur l'appareil doit disparaître à la déconnexion. La
règle vit à un seul endroit, la méthode qui oublie les caches dans
`lib/core/session/deconnexion.dart`. Tout nouveau cache local doit y être branché. »

`lib/features/notifications/data/jeton_local.dart` écrit la clé `notifications.jeton.appareil`
dans le stockage du navigateur, et cette clé n'est pas citée dans `OubliLocal`. C'est une clé
d'appareil et non de compte, ce qui explique qu'elle ait échappé à la règle, mais un téléphone de
caserne est prêté : le jeton de push enregistré par la personne précédente reste sur l'appareil
après sa déconnexion, et la personne suivante peut l'hériter, ou le serveur peut continuer de
pousser vers un appareil dont le compte a changé.

Le filet large de `test/core/session/deconnexion_caches_test.dart` ne l'attrape pas parce qu'il
ne connaît que les préfixes déclarés.

## À faire

- Décider ce que le jeton d'appareil doit devenir à la déconnexion : oublié localement et
  désenregistré côté serveur (`push_tokens`) pour ce compte, ou conservé comme identité d'appareil
  et seulement dissocié du compte. Écrire la décision dans `docs/WORKFLOWS.md § notifications`.
- Brancher le résultat dans `OubliLocal`, au seul endroit prévu, et faire en sorte que le filet
  large des tests de déconnexion découvre les clés au lieu de les lister, pour que le prochain
  cache oublié soit attrapé.
- Vérifier qu'après déconnexion sur un appareil, un push destiné à l'ancien compte ne peut plus y
  arriver : test de base sur `push_tokens`, sous identité.

## Critères d'acceptation

- Après déconnexion, `notifications.jeton.appareil` a disparu du stockage, ou est dissocié du
  compte selon la décision écrite, et un test le prouve.
- Le test de déconnexion échoue si une nouvelle clé locale apparaît sans être branchée sur l'oubli.
- Un push destiné au compte déconnecté n'atteint plus l'appareil, vérifié côté base.
- `flutter analyze` sans avertissement, `flutter test` verts, tests de base verts.
