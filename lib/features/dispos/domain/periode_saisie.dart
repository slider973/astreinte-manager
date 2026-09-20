import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/supabase/enums.dart';
import '../../../core/theme/app_status.dart';

/// Un mois de saisie d'une caserne — une ligne de `periods`
/// (`docs/SCHEMA.md § 2.5`).
///
/// L'écran **subit** le verrouillage, il ne le pilote pas : la réouverture et
/// la saisie par l'admin sont le ticket 014.
@immutable
class PeriodeSaisie {
  const PeriodeSaisie({
    required this.id,
    required this.stationId,
    required this.annee,
    required this.mois,
    required this.statut,
    required this.dateLimite,
    this.verrouilleeLe,
  });

  /// Construit depuis la réponse PostgREST. Aucune colonne inventée.
  factory PeriodeSaisie.depuisJson(Map<String, dynamic> ligne) {
    final verrouillee = ligne['locked_at'] as String?;
    return PeriodeSaisie(
      id: ligne['id']! as String,
      stationId: ligne['station_id']! as String,
      annee: ligne['year']! as int,
      mois: ligne['month']! as int,
      statut: PeriodeSql.depuisSql(ligne['status'] as String?),
      dateLimite: DateTime.parse(ligne['deadline_at']! as String).toLocal(),
      verrouilleeLe: verrouillee == null
          ? null
          : DateTime.parse(verrouillee).toLocal(),
    );
  }

  final String id;
  final String stationId;
  final int annee;
  final int mois;
  final PeriodeEtat statut;

  /// Le jour limite du mois **précédent**, à 23:59:59 dans le fuseau de la
  /// caserne, converti en heure locale.
  final DateTime dateLimite;

  final DateTime? verrouilleeLe;

  /// La clé qui voyage dans l'URL : `2026-10`.
  String get cle => '$annee-${mois.toString().padLeft(2, '0')}';

  /// La clé d'un couple année/mois, sans passer par une période.
  static String cleDe(int annee, int mois) =>
      '$annee-${mois.toString().padLeft(2, '0')}';

  bool get ouverte => statut == PeriodeEtat.ouverte;

  /// « Octobre 2026 ».
  String get libelle => AppStrings.moisNomEtAnnee(mois, annee);

  DateTime get premierJour => DateTime(annee, mois);

  /// Le nombre de jours du mois. `DateTime(annee, mois + 1, 0)` désigne le
  /// dernier jour du mois, décembre compris : Dart normalise le mois 13.
  int get nombreDeJours => DateTime(annee, mois + 1, 0).day;

  /// Les jours du mois, du 1er au dernier, dans l'ordre.
  List<DateTime> get jours => <DateTime>[
    for (var jour = 1; jour <= nombreDeJours; jour++)
      DateTime(annee, mois, jour),
  ];

  /// Le nombre de jours entiers restants avant la date limite, ou `null` si
  /// la période n'est pas ouverte. Sert à la bannière de rappel à J-3.
  int? joursAvantLimite(DateTime maintenant) {
    if (!ouverte) return null;
    final restant = dateLimite.difference(maintenant);
    return restant.isNegative ? 0 : restant.inDays;
  }

  /// La ligne d'état du bouton du sélecteur : « Ouvert jusqu'au 15 sept. » ou
  /// « Verrouillé ».
  String get ligneEtat => ouverte
      ? AppStrings.moisOuvertJusquAuCourt(formaterDateCourte(dateLimite))
      : AppStrings.moisVerrouilleCourt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeriodeSaisie &&
          other.id == id &&
          other.stationId == stationId &&
          other.annee == annee &&
          other.mois == mois &&
          other.statut == statut &&
          other.dateLimite == dateLimite &&
          other.verrouilleeLe == verrouilleeLe;

  @override
  int get hashCode => Object.hash(
    id,
    stationId,
    annee,
    mois,
    statut,
    dateLimite,
    verrouilleeLe,
  );
}

/// La période à ouvrir par défaut : **la première période `open` par ordre
/// chronologique**. À défaut, la période verrouillée la plus récente.
///
/// Le membre vient saisir, pas consulter : on lui ouvre le mois qu'il peut
/// remplir. Et s'il n'y en a aucun, on lui montre le dernier qu'il a rempli
/// plutôt qu'un écran vide.
PeriodeSaisie? periodeParDefaut(List<PeriodeSaisie> periodes) {
  if (periodes.isEmpty) return null;

  final triees = <PeriodeSaisie>[...periodes]
    ..sort((a, b) => a.cle.compareTo(b.cle));

  for (final periode in triees) {
    if (periode.ouverte) return periode;
  }
  return triees.last;
}
