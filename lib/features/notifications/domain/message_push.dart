import 'package:flutter/foundation.dart';

/// Une notification reçue, réduite à ce que l'application en affiche.
///
/// Volontairement découplé de `RemoteMessage` de `firebase_messaging` : les
/// écrans et les tests n'ont pas besoin du SDK pour exister, et le jour où le
/// canal change (ticket 036), seul l'adaptateur bouge.
@immutable
class MessagePush {
  const MessagePush({this.titre, this.corps, this.route, this.stationId});

  /// Le titre, tel que l'Edge Function l'a écrit (ticket 025).
  final String? titre;

  /// Le corps. Une phrase, affichée sur deux lignes au plus.
  final String? corps;

  /// `notifications.data.route` : la destination à ouvrir
  /// (`docs/WORKFLOWS.md § 8`). Absente pour une notification purement
  /// informative.
  final String? route;

  /// `data.station_id` : la caserne de la notification (ticket 072). Absente
  /// pour une notification rattachée au compte. C'est elle qui décide de la
  /// bascule avant d'ouvrir [route] (`docs/WORKFLOWS.md § 8`).
  final String? stationId;

  /// Vrai si le message a de quoi être montré. Une notification sans titre ni
  /// corps n'est pas une bannière vide : elle n'est rien, et on se tait.
  bool get affichable =>
      (titre?.trim().isNotEmpty ?? false) || (corps?.trim().isNotEmpty ?? false);

  @override
  bool operator ==(Object other) =>
      other is MessagePush &&
      other.titre == titre &&
      other.corps == corps &&
      other.route == route &&
      other.stationId == stationId;

  @override
  int get hashCode => Object.hash(titre, corps, route, stationId);

  @override
  String toString() => 'MessagePush($titre, $corps, $route, $stationId)';
}

/// Une notification touchée alors que l'application tournait en arrière-plan,
/// telle que le service worker la poste (`web/push/firebase-messaging-sw.js`).
@immutable
class OuverturePush {
  const OuverturePush({required this.route, this.stationId});

  /// Le lien public à ouvrir.
  final String route;

  /// La caserne de la notification, quand elle en a une (ticket 072).
  final String? stationId;

  @override
  bool operator ==(Object other) =>
      other is OuverturePush &&
      other.route == route &&
      other.stationId == stationId;

  @override
  int get hashCode => Object.hash(route, stationId);

  @override
  String toString() => 'OuverturePush($route, $stationId)';
}
