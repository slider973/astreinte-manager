# 078 — Les notifications n'arrivent qu'à une partie des pompiers

- **Épopée** : E6 Notifications
- **Priorité** : P0
- **Dépend de** : 074
- **Branche** : `feat/078-rotation-jeton-push`
- **Statut** : à faire

## Contexte

Signalé par le propriétaire le 10 octobre 2026, après ses tests : les notifications ne sont
« pas reçues par tout le monde ». Pas une panne générale — une partie des pompiers seulement.

Diagnostic (lu dans le code, le 10 octobre) :

1. **Personne n'écoute la rotation des jetons.** `onTokenRefresh` n'apparaît nulle part dans
   `lib/` : `MessageriePush` (`messagerie_push.dart:15-53`) n'expose que `jeton()`, un appel
   ponctuel. `JetonPushController.publier()` n'est appelé qu'en trois points
   (`notifications_providers.dart:88` à l'octroi de la permission,
   `couche_notifications.dart:203` et `:206` au lancement et au changement de session).

   Or FCM renouvelle un jeton de sa propre initiative : mise à jour du navigateur, nettoyage
   du stockage, réinstallation de la PWA, ou longue inactivité. Entre deux lancements de
   l'app, la rotation passe donc inaperçue : `push_tokens` garde l'ancien jeton, FCM le
   rejette, et ce pompier ne reçoit plus rien.

   **Rien ne le signale** : ni au pompier (son écran affiche toujours « notifications
   activées »), ni à l'administrateur qui croit avoir prévenu sa garde.

2. **La purge des jetons morts ne reconstruit rien.** `send-notification/index.ts:192`
   supprime bien les jetons rejetés par FCM, ce qui évite d'accumuler des lignes mortes,
   mais l'appareil ne republie son nouveau jeton qu'au prochain lancement de l'app.

Pistes écartées : `profiles.push_enabled` vaut `true` par défaut
(`0002_profiles_memberships_invitations.sql:13`) et n'est forcé à `false` qu'à la suppression
de compte ; la sélection des destinataires dans `send-notification` (`lireProfils`,
`lireJetons`) est correcte.

## À faire

1. **`MessageriePush` expose la rotation** : ajouter `Stream<String> get jetonsRenouveles`,
   branché sur `FirebaseMessaging.instance.onTokenRefresh` dans `MessageriePushFirebase`, et
   un flux vide dans `MessageriePushIndisponible`.
2. **`CoucheNotifications` s'y abonne** et appelle `publier()` à chaque jeton reçu, avec la
   même protection de génération que `publier()` (un désenregistrement concurrent ne doit pas
   réécrire la ligne).
3. **`publier()` accepte un jeton déjà connu** en paramètre optionnel, pour éviter un
   `getToken()` superflu quand la rotation vient de le fournir.
4. **Rendre l'échec visible** : si la publication échoue hors debug, journaliser côté serveur
   (table `notifications` ou journal applicatif existant) — un jeton qu'on n'arrive pas à
   écrire est un pompier injoignable, pas un détail.
5. **Vérifier la fraîcheur** : `push_tokens.last_seen_at` est déjà tenu à jour par
   `publier()`. Ajouter une vue ou une requête admin listant les membres dont le jeton a plus
   de 30 jours, pour que l'administrateur puisse constater le problème au lieu de le subir.

## Critères d'acceptation

- `onTokenRefresh` déclenche une republication, prouvée par un test avec une messagerie
  fausse qui émet un jeton après le lancement.
- Un désenregistrement concurrent à une rotation n'écrit ni la ligne ni la clé locale.
- `flutter analyze` sans avertissement, `flutter test` verts, `flutter build web` passe.
- La règle des caches locaux reste respectée : aucun nouveau cache non branché à
  `lib/core/session/deconnexion.dart`.

## Hors périmètre

- Les notifications natives iOS/Android (ticket 036).
- Le choix par type de notification (`push_enabled` reste un interrupteur global).
