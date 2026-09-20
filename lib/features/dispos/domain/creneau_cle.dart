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

  /// Relit une clé écrite par [toString] : `2026-10-04/nuit`.
  ///
  /// Rend `null` sur tout ce qui ne se relit pas. Une file gardée sur
  /// l'appareil traverse les mises à jour de l'application : elle doit
  /// pouvoir ignorer une entrée qu'elle ne comprend plus, jamais lever au
  /// démarrage.
  static CreneauCle? depuisTexte(String texte) {
    final morceaux = texte.split('/');
    if (morceaux.length != 2) return null;

    final date = DateTime.tryParse(morceaux.first);
    if (date == null) return null;

    for (final creneau in CreneauType.values) {
      if (creneau.name == morceaux.last) return CreneauCle(date, creneau);
    }
    return null;
  }

  /// La date telle que Postgres l'attend : `2026-10-04`.
  String get dateIso => isoJour(date);

  /// Le mois auquel la case appartient : `2026-10`. C'est la clé de la
  /// période, et celle du rangement de la file sur l'appareil.
  String get cleMois => '${date.year}-${date.month.toString().padLeft(2, '0')}';

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
