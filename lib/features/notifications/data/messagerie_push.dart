import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../../core/env.dart';
import '../domain/etat_notifications.dart';
import '../domain/message_push.dart';
import 'pont_service_worker.dart';

/// Le canal de notifications, vu par l'application.
///
/// Toute la dépendance à `firebase_messaging` tient derrière cette interface :
/// les contrôleurs, les écrans et leurs tests n'importent jamais le SDK.
abstract interface class MessageriePush {
  /// Vrai si ce navigateur sait recevoir des push.
  Future<bool> estSupportee();

  /// L'autorisation actuelle, **lue sans rien demander**.
  Future<PermissionPush> permission();

  /// Ouvre la fenêtre d'autorisation du navigateur. À n'appeler que sur un
  /// geste explicite : un refus ne se rattrape pas depuis l'application.
  Future<PermissionPush> demanderPermission();

  /// Le jeton FCM de cet appareil, ou `null` si le navigateur le refuse.
  Future<String?> jeton();

  /// **À la déconnexion** : demande au SDK de supprimer le jeton chez FCM.
  ///
  /// C'est un appel réseau, et il n'a de sens que si un jeton existe : le
  /// contrôleur ne l'appelle que si l'autorisation est accordée **et** qu'un
  /// jeton est connu (`JetonPushController.desenregistrer`, ticket 074).
  /// Ne lève jamais.
  Future<void> oublierJeton();

  /// **À la déconnexion** : cet appareil cesse de recevoir des push, même
  /// hors ligne. Sans cela, après une déconnexion sans réseau, le service
  /// worker continuerait d'afficher les push du compte sorti tant que
  /// personne ne se reconnecte (ticket 057). Local, sans réseau, appelé
  /// **toujours**. Ne lève jamais.
  Future<void> desabonner();

  /// **Au lancement**, avant de demander un jeton : oublie ce que les
  /// versions d'avant le ticket 074 ont laissé hors de la portée `push/` — un
  /// abonnement push sur `/`, que le worker de Flutter reçoit et perd, et les
  /// enregistrements Firebase restés sans configuration. Le `getToken` qui
  /// suit recrée l'abonnement au bon endroit. Ne lève jamais.
  Future<void> nettoyerAnciennesPortees();

  /// Les messages reçus **pendant que l'application est au premier plan**. Le
  /// système n'affiche rien dans ce cas : c'est l'application qui montre.
  Stream<MessagePush> get messagesPremierPlan;
}

/// Le dossier du service worker des push, **relatif au base href**.
///
/// Un dossier à lui, pour une portée à lui : à la racine, le worker partageait
/// la portée `/` avec `flutter_service_worker.js` et restait en attente
/// derrière lui — les push arrivaient au worker de Flutter et se perdaient
/// (ticket 074). `navigator.serviceWorker.register()`, appelé sans portée par
/// `firebase_messaging_web`, donne au worker le dossier de son script :
/// `push/`. Sans `/` initial, le chemin se résout contre le base href, et la
/// PWA servie sous un sous-chemin garde un worker à côté d'elle.
const String dossierServiceWorkerPush = 'push/';

/// L'adresse d'enregistrement du service worker, avec sa configuration.
///
/// **Pourquoi une chaîne de requête.** Un service worker s'exécute hors de
/// l'application : il ne voit ni les `--dart-define`, ni le `main.dart`. La
/// seule façon de lui transmettre une configuration sans l'écrire en dur dans
/// le dépôt est de la lui passer dans son URL d'enregistrement. Ces quatre
/// valeurs sont publiques (`Env.hasFirebaseConfig`).
String cheminServiceWorkerPush(Env env) => Uri(
  path: '${dossierServiceWorkerPush}firebase-messaging-sw.js',
  queryParameters: <String, String>{
    'apiKey': env.firebaseApiKey,
    'appId': env.firebaseAppId,
    'messagingSenderId': env.firebaseMessagingSenderId,
    'projectId': env.firebaseProjectId,
  },
).toString();

/// L'implémentation Firebase Cloud Messaging, pour le web.
///
/// Elle n'est construite que si `demarrerFirebase` a réussi
/// (`core/firebase/firebase_bootstrap.dart`) : sans projet Firebase, c'est
/// [MessageriePushIndisponible] qui prend la place et rien n'est appelé.
class MessageriePushFirebase implements MessageriePush {
  MessageriePushFirebase(this._env);

  final Env _env;

  /// Vrai dès qu'un `getToken` a abouti **dans cette page**.
  ///
  /// C'est lui qui donne au SDK son enregistrement de service worker. Sans
  /// lui, `deleteToken()` en enregistre un de lui-même — `/firebase-messaging-sw.js`,
  /// sans configuration, sur `/firebase-cloud-messaging-push-scope` — rien que
  /// pour le supprimer : du bruit que le ticket 074 retire.
  bool _jetonObtenu = false;

  @override
  Future<bool> estSupportee() async {
    try {
      return await FirebaseMessaging.instance.isSupported();
    } on Object catch (erreur) {
      if (kDebugMode) debugPrint('Push non supporté : $erreur');
      return false;
    }
  }

  @override
  Future<PermissionPush> permission() async {
    try {
      final reglages = await FirebaseMessaging.instance
          .getNotificationSettings();
      return _depuisStatut(reglages.authorizationStatus);
    } on Object catch (erreur) {
      if (kDebugMode) debugPrint('Autorisation illisible : $erreur');
      return PermissionPush.aDemander;
    }
  }

  @override
  Future<PermissionPush> demanderPermission() async {
    try {
      final reglages = await FirebaseMessaging.instance.requestPermission();
      return _depuisStatut(reglages.authorizationStatus);
    } on Object catch (erreur) {
      if (kDebugMode) debugPrint('Demande d\'autorisation impossible : $erreur');
      return PermissionPush.refusee;
    }
  }

  @override
  Future<String?> jeton() async {
    try {
      final jeton = await FirebaseMessaging.instance.getToken(
        vapidKey: _env.firebaseVapidKey,
        serviceWorkerScriptPath: cheminServiceWorkerPush(_env),
      );
      _jetonObtenu = true;
      return jeton;
    } on Object catch (erreur) {
      // Un jeton refusé n'est pas une panne à montrer : l'état des
      // notifications, lui, reste juste. On réessaiera au prochain lancement.
      // Mais il se dit **dans la console, en production aussi** : c'est le
      // seul endroit où le lire quand aucune ligne n'arrive dans
      // `push_tokens` (ticket 074). L'erreur ne porte pas de jeton.
      avertirConsole('Jeton push indisponible : $erreur');
      return null;
    }
  }

  /// Le `deleteToken` du SDK prévient FCM **puis** désabonne le navigateur ;
  /// hors ligne, il échoue au premier temps et ne fait pas le second. C'est
  /// pourquoi [desabonner] suit toujours, dans le contrôleur.
  @override
  Future<void> oublierJeton() async {
    if (!_jetonObtenu) return;
    try {
      await FirebaseMessaging.instance.deleteToken().timeout(
        const Duration(seconds: 5),
      );
      _jetonObtenu = false;
    } on Object catch (erreur) {
      if (kDebugMode) debugPrint('Jeton FCM non supprimé : $erreur');
    }
  }

  @override
  Future<void> desabonner() async {
    try {
      await nettoyerServiceWorkers(garderPush: false);
    } on Object catch (erreur) {
      if (kDebugMode) debugPrint('Abonnement push non oublié : $erreur');
    }
  }

  @override
  Future<void> nettoyerAnciennesPortees() async {
    try {
      await nettoyerServiceWorkers(garderPush: true);
    } on Object catch (erreur) {
      avertirConsole('Anciens service workers non nettoyés : $erreur');
    }
  }

  @override
  Stream<MessagePush> get messagesPremierPlan =>
      FirebaseMessaging.onMessage.map(
        (RemoteMessage message) => MessagePush(
          titre: message.notification?.title,
          corps: message.notification?.body,
          route: message.data['route'] as String?,
          stationId: message.data['station_id'] as String?,
        ),
      );

  static PermissionPush _depuisStatut(AuthorizationStatus statut) =>
      switch (statut) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PermissionPush.accordee,
        AuthorizationStatus.denied ||
        AuthorizationStatus.deniedPermanently => PermissionPush.refusee,
        AuthorizationStatus.notDetermined => PermissionPush.aDemander,
      };
}

/// Pas de projet Firebase, pas de web, ou initialisation échouée.
///
/// Elle répond « non » à tout, sans jamais lever : c'est ce qui permet à
/// l'application de démarrer et de fonctionner **normalement** sans clés.
class MessageriePushIndisponible implements MessageriePush {
  const MessageriePushIndisponible();

  @override
  Future<bool> estSupportee() async => false;

  @override
  Future<PermissionPush> permission() async => PermissionPush.aDemander;

  @override
  Future<PermissionPush> demanderPermission() async => PermissionPush.refusee;

  @override
  Future<String?> jeton() async => null;

  /// Rien n'a été abonné : rien à oublier, et surtout aucun appel à Google.
  @override
  Future<void> oublierJeton() async {}

  @override
  Future<void> desabonner() async {}

  @override
  Future<void> nettoyerAnciennesPortees() async {}

  @override
  Stream<MessagePush> get messagesPremierPlan => const Stream<MessagePush>.empty();
}
