import 'package:flutter/foundation.dart';

import '../../../core/l10n/format_date.dart';
import '../../../core/theme/app_status.dart';

/// **L'unité de saisie** : une date et un créneau.
///
/// C'est la clé de l'unicité `(station_id, user_id, date, slot)` de
/// `docs/SCHEMA.md § 2.6`, la clé de la carte du mois affichée, et la clé de
/// la file d'écriture — **c'est elle qui rend la coalescence gratuite** :
/// une `Map<CreneauCle, …>` ne peut pas contenir deux écritures pour la même
/// case, donc quarante touches sur la même case ne produisent qu'une ligne.
@immutable
class CreneauCle implements Comparable<CreneauCle> {
  CreneauCle(DateTime date, this.creneau)
    : date = DateTime(date.year, date.month, date.day);

  /// Le jour, **nu** : minuit, heure locale, sans fuseau. Un créneau est
  /// « le 12 octobre, nuit », jamais un horodatage.
  final DateTime date;

  final CreneauType creneau;

  /// La date telle que Postgres l'attend : `2026-10-04`.
  String get dateIso => isoJour(date);

  /// L'ordre de lecture du registre : par jour, puis jour avant nuit.
  @override
  int compareTo(CreneauCle autre) {
    final parDate = date.compareTo(autre.date);
    return parDate != 0 ? parDate : creneau.index - autre.creneau.index;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreneauCle && other.date == date && other.creneau == creneau;

  @override
  int get hashCode => Object.hash(date, creneau);

  @override
  String toString() => '$dateIso/${creneau.name}';
}
