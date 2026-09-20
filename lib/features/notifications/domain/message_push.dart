import 'package:flutter/foundation.dart';

/// Une notification reçue, réduite à ce que l'application en affiche.
///
/// Volontairement découplé de `RemoteMessage` de `firebase_messaging` : les
/// écrans et les tests n'ont pas besoin du SDK pour exister, et le jour où le
/// canal change (ticket 036), seul l'adaptateur bouge.
@immutable
class MessagePush {
  const MessagePush({this.titre, this.corps, this.route});

  /// Le titre, tel que l'Edge Function l'a écrit (ticket 025).
  final String? titre;

  /// Le corps. Une phrase, affichée sur deux lignes au plus.
  final String? corps;

  /// `notifications.data.route` : la destination à ouvrir
  /// (`docs/WORKFLOWS.md § 8`). Absente pour une notification purement
  /// informative.
  final String? route;

  /// Vrai si le message a de quoi être montré. Une notification sans titre ni
  /// corps n'est pas une bannière vide : elle n'est rien, et on se tait.
  bool get affichable =>
      (titre?.trim().isNotEmpty ?? false) || (corps?.trim().isNotEmpty ?? false);

  @override
  bool operator ==(Object other) =>
      other is MessagePush &&
      other.titre == titre &&
      other.corps == corps &&
      other.route == route;

  @override
  int get hashCode => Object.hash(titre, corps, route);

  @override
  String toString() => 'MessagePush($titre, $corps, $route)';
}
