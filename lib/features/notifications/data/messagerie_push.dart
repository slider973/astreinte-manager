import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../../core/env.dart';
import '../domain/etat_notifications.dart';
import '../domain/message_push.dart';

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

  /// Les messages reçus **pendant que l'application est au premier plan**. Le
  /// système n'affiche rien dans ce cas : c'est l'application qui montre.
  Stream<MessagePush> get messagesPremierPlan;
}

/// L'implémentation Firebase Cloud Messaging, pour le web.
///
/// Elle n'est construite que si `demarrerFirebase` a réussi
/// (`core/firebase/firebase_bootstrap.dart`) : sans projet Firebase, c'est
/// [MessageriePushIndisponible] qui prend la place et rien n'est appelé.
class MessageriePushFirebase implements MessageriePush {
  MessageriePushFirebase(this._env);

  final Env _env;

  /// Le service worker qui reçoit les push quand l'onglet est fermé.
  ///
  /// **Pourquoi une chaîne de requête.** Un service worker s'exécute hors de
  /// l'application : il ne voit ni les `--dart-define`, ni le `main.dart`. La
  /// seule façon de lui transmettre une configuration sans l'écrire en dur
  /// dans le dépôt est de la lui passer dans son URL d'enregistrement. Ces
  /// quatre valeurs sont publiques (`Env.hasFirebaseConfig`).
  String get _cheminServiceWorker {
    final parametres = <String, String>{
      'apiKey': _env.firebaseApiKey,
      'appId': _env.firebaseAppId,
      'messagingSenderId': _env.firebaseMessagingSenderId,
      'projectId': _env.firebaseProjectId,
    };
    return Uri(
      path: 'firebase-messaging-sw.js',
      queryParameters: parametres,
    ).toString();
  }

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
      return await FirebaseMessaging.instance.getToken(
        vapidKey: _env.firebaseVapidKey,
        serviceWorkerScriptPath: _cheminServiceWorker,
      );
    } on Object catch (erreur) {
      // Un jeton refusé n'est pas une panne à montrer : l'état des
      // notifications, lui, reste juste. On réessaiera au prochain lancement.
      if (kDebugMode) debugPrint('Jeton push indisponible : $erreur');
      return null;
    }
  }

  @override
  Stream<MessagePush> get messagesPremierPlan =>
      FirebaseMessaging.onMessage.map(
        (RemoteMessage message) => MessagePush(
          titre: message.notification?.title,
          corps: message.notification?.body,
          route: message.data['route'] as String?,
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

  @override
  Stream<MessagePush> get messagesPremierPlan => const Stream<MessagePush>.empty();
}
