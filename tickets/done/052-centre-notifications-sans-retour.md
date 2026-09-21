# 052 — Le centre de notifications n'a pas de retour

- **Épopée** : E6 Notifications
- **Priorité** : P1
- **Dépend de** : 026
- **Branche** : `feat/052-centre-notifications-sans-retour`
- **PR** : https://github.com/slider973/astreinte-manager/pull/47
- **Statut** : terminé le 2026-09-21 (PR créée)

## Contexte

Signalé par le propriétaire le 21 septembre 2026, sur son téléphone, avec la PWA installée :
« quand je vais dans les notifications je ne peux pas retourner en arrière ».

C'est exact, et c'est structurel. La route `/notifications` est déclarée **au premier niveau** du
routeur, sans parent, et le centre est un `Scaffold` nu, sans l'ossature de navigation. On y arrive
par la cloche de cinq écrans, via `context.goNamed`, qui remplace la destination au lieu de
l'empiler. Résultat : ni flèche de retour dans la barre, ni navigation en bas, ni pile à dépiler.
Sur un ordinateur, le bouton précédent du navigateur sauve la mise. Sur un iPhone en PWA plein
écran, il n'y a rien : la personne est enfermée.

L'écran d'import, lui, obtient sa flèche parce qu'il est **enfant** de la route des membres. Le
centre de notifications n'est l'enfant de personne alors qu'il s'ouvre depuis cinq endroits.

Le brief `PRODUCT.md` est explicite : « Sur iPhone en PWA, respecter les zones sûres, le geste
retour ». Un écran sans issue viole la règle la plus élémentaire du mode Operate.

## À faire

- Donner au centre un retour qui ramène **là d'où la cloche a été pressée**, pas à l'accueil par
  défaut. Cinq écrans l'ouvrent, et un pompier qui consultait ses propositions doit y revenir.
- Décider la forme : route enfant, empilement, ou destination de l'ossature avec navigation. La
  décision doit tenir pour les liens profonds des notifications (`docs/WORKFLOWS.md § 8`), qui
  ouvrent le centre application fermée, sans écran précédent : dans ce cas le retour mène à
  l'accueil du rôle, et il le dit.
- Vérifier le geste retour iOS et le bouton précédent du navigateur : les deux doivent faire la
  même chose que la flèche.
- Passer en revue les autres routes de premier niveau ouvertes par `goNamed` depuis un écran, avec
  un `Scaffold` nu : le défaut a une cause de structure, il a probablement des frères.

## Critères d'acceptation

- Depuis chacun des cinq écrans qui portent la cloche, ouvrir le centre puis revenir ramène à cet
  écran, avec son état.
- Ouvert par un lien profond, application fermée, le centre a un retour vers l'accueil du rôle.
- Le geste retour et le bouton précédent du navigateur produisent le même résultat que la flèche.
- Aucun autre écran de l'application n'est une impasse sur iPhone en PWA ; la revue le liste.
- `flutter analyze` sans avertissement, `flutter test` verts, `flutter build web` qui passe.
