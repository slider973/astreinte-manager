import 'package:flutter/foundation.dart';

import '../../../core/theme/app_status.dart';

/// Une case de la matrice : un membre, un jour du mois, un créneau.
///
/// Sert de clé aux écritures en vol et aux cases en erreur. Le mois n'y est
/// pas : une clé ne survit jamais au changement de mois, qui recharge tout.
@immutable
class CleCellule {
  const CleCellule({
    required this.userId,
    required this.jour,
    required this.creneau,
  });

  final String userId;

  /// 1 pour le premier du mois.
  final int jour;

  final CreneauType creneau;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CleCellule &&
          other.userId == userId &&
          other.jour == jour &&
          other.creneau == creneau;

  @override
  int get hashCode => Object.hash(userId, jour, creneau);

  @override
  String toString() => 'CleCellule($userId, $jour, ${creneau.name})';
}
