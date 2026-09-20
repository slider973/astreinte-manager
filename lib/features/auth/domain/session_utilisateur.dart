import 'package:flutter/foundation.dart';

/// L'utilisateur connecté, réduit à ce dont l'app a besoin.
///
/// Volontairement découplé de `Session` de supabase_flutter : les écrans et
/// les tests ne dépendent pas du SDK, et un faux dépôt suffit à les monter.
@immutable
class SessionUtilisateur {
  const SessionUtilisateur({required this.userId, required this.email});

  /// `auth.users.id`, qui est aussi `profiles.id` (`docs/SCHEMA.md § 2.2`).
  final String userId;

  final String email;

  @override
  bool operator ==(Object other) =>
      other is SessionUtilisateur &&
      other.userId == userId &&
      other.email == email;

  @override
  int get hashCode => Object.hash(userId, email);

  @override
  String toString() => 'SessionUtilisateur($userId, $email)';
}
