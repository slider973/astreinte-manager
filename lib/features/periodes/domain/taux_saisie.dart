import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_strings.dart';

/// Un mois, réduit à ce qui l'identifie. La clé du taux de saisie.
///
/// **Pas la période elle-même** : verrouiller un mois produit une nouvelle
/// `PeriodeSaisie`, et une clé qui changerait à chaque action relancerait le
/// comptage des saisies alors qu'aucune disponibilité n'a bougé.
typedef CleMois = ({int annee, int mois});

/// Combien de membres ont rempli ce mois, sur combien de membres actifs.
///
/// Compté côté client (`design/014 § 7`) : une requête par mois affiché, qui
/// ne demande que les identifiants. Le numérateur est **intersecté** avec les
/// membres actifs : un pompier désactivé depuis qu'il a saisi ne doit pas
/// produire « 10 membres sur 9 ».
@immutable
class TauxSaisie {
  const TauxSaisie({required this.saisis, required this.effectif});

  final int saisis;
  final int effectif;

  /// Faux quand la caserne n'a aucun membre actif : il n'y a pas de taux, et
  /// « 0 % » serait un mensonge poli.
  bool get mesurable => effectif > 0;

  /// La part remplie, entre 0 et 1. Sert à la jauge, jamais au texte.
  double get part => mesurable ? (saisis / effectif).clamp(0, 1) : 0;

  int get pourcentage => (part * 100).round();

  bool get complet => mesurable && saisis >= effectif;

  /// La phrase, qui porte l'information : « 7 membres sur 9 ont saisi ».
  String get libelle => mesurable
      ? AppStrings.periodeTauxSaisie(saisis, effectif)
      : AppStrings.periodeTauxAucunMembre;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TauxSaisie && other.saisis == saisis && other.effectif == effectif;

  @override
  int get hashCode => Object.hash(saisis, effectif);
}
