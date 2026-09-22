/// Les enums Postgres de `docs/SCHEMA.md § 1`, traduits dans les deux sens.
///
/// Le thème porte déjà les énumérations d'affichage ([CreneauType],
/// [DisponibiliteEtat], [PeriodeEtat]) : leur donner ici leur valeur SQL
/// évite un second jeu d'enums qu'il faudrait garder synchronisé. Une valeur
/// inconnue n'est jamais devinée — elle lève, parce qu'un créneau de nuit lu
/// comme un créneau de jour est une garde non couverte.
library;

import '../theme/app_status.dart';

/// `slot_type` : `day` / `night`.
extension CreneauSql on CreneauType {
  String get valeurSql => switch (this) {
    CreneauType.jour => 'day',
    CreneauType.nuit => 'night',
  };

  static CreneauType depuisSql(String valeur) => switch (valeur) {
    'day' => CreneauType.jour,
    'night' => CreneauType.nuit,
    _ => throw ArgumentError.value(valeur, 'slot', 'slot_type inconnu'),
  };
}

/// `availability_status` : `available` / `absent`.
///
/// **Il n'y a pas de valeur SQL pour « non saisi »** : l'absence de ligne
/// *est* le non-saisi (`docs/SCHEMA.md § 2.6`). Demander la valeur SQL de
/// [DisponibiliteEtat.nonSaisi] est une erreur de programmation, pas un cas à
/// traiter : l'écran doit supprimer la ligne, pas en écrire une.
extension DisponibiliteSql on DisponibiliteEtat {
  String get valeurSql => switch (this) {
    DisponibiliteEtat.disponible => 'available',
    DisponibiliteEtat.absent => 'absent',
    DisponibiliteEtat.nonSaisi => throw StateError(
      '« Non saisi » ne s\'écrit pas : la ligne se supprime.',
    ),
  };

  static DisponibiliteEtat depuisSql(String valeur) => switch (valeur) {
    'available' => DisponibiliteEtat.disponible,
    'absent' => DisponibiliteEtat.absent,
    _ => throw ArgumentError.value(
      valeur,
      'status',
      'availability_status inconnu',
    ),
  };
}

/// `schedule_status` : `draft` / `published` / `validated` / `archived`.
///
/// Un statut inconnu est lu comme **publié** : c'est le côté sûr. Un planning
/// qu'on ne comprend pas ne se laisse pas modifier comme un brouillon, et il
/// ne se donne pas non plus pour validé.
extension PlanningSql on PlanningEtat {
  String get valeurSql => switch (this) {
    PlanningEtat.brouillon => 'draft',
    PlanningEtat.publie => 'published',
    PlanningEtat.valide => 'validated',
    PlanningEtat.archive => 'archived',
  };

  static PlanningEtat depuisSql(String? valeur) => switch (valeur) {
    'draft' => PlanningEtat.brouillon,
    'published' => PlanningEtat.publie,
    'validated' => PlanningEtat.valide,
    'archived' => PlanningEtat.archive,
    _ => PlanningEtat.publie,
  };
}

/// `assignment_status` : `proposed` / `accepted` / `declined` / `replaced` /
/// `cancelled`.
///
/// Un statut inconnu se lit comme **annulé** : le côté sûr est celui qui ne
/// compte pas dans la couverture. La règle vient du ticket 019, où elle est
/// née dans le suivi ; elle vit ici depuis le 061b, le planning en brouillon
/// ayant lui aussi besoin de distinguer une proposition d'une acceptation.
extension AttributionSql on AttributionEtat {
  String get valeurSql => switch (this) {
    AttributionEtat.propose => 'proposed',
    AttributionEtat.accepte => 'accepted',
    AttributionEtat.refuse => 'declined',
    AttributionEtat.remplace => 'replaced',
    AttributionEtat.annule => 'cancelled',
  };

  static AttributionEtat depuisSql(String? valeur) => switch (valeur) {
    'proposed' => AttributionEtat.propose,
    'accepted' => AttributionEtat.accepte,
    'declined' => AttributionEtat.refuse,
    'replaced' => AttributionEtat.remplace,
    _ => AttributionEtat.annule,
  };
}

/// `period_status` : `open` / `locked`.
extension PeriodeSql on PeriodeEtat {
  String get valeurSql => switch (this) {
    PeriodeEtat.ouverte => 'open',
    PeriodeEtat.verrouillee => 'locked',
  };

  /// Un statut inconnu est lu comme **verrouillé** : le refus est le côté sûr.
  /// Une période qu'on ne comprend pas ne s'ouvre pas à l'écriture.
  static PeriodeEtat depuisSql(String? valeur) =>
      valeur == 'open' ? PeriodeEtat.ouverte : PeriodeEtat.verrouillee;
}
