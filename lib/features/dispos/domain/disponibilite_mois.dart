import 'package:flutter/foundation.dart';

import '../../../core/l10n/jours_feries.dart';
import '../../../core/theme/app_status.dart';
import 'creneau_cle.dart';

/// Les trois compteurs de la barre du bas.
///
/// Ils comptent les créneaux **disponibles** — jamais les absents, jamais les
/// non saisis (brief 011 § 6.4). Un mois entièrement marqué « absent » affiche
/// donc trois zéros, et c'est exact : le membre n'a rien donné.
@immutable
class CompteursMois {
  const CompteursMois({
    required this.jours,
    required this.nuits,
    required this.weekends,
  });

  static const CompteursMois zero = CompteursMois(
    jours: 0,
    nuits: 0,
    weekends: 0,
  );

  final int jours;
  final int nuits;

  /// Le nombre d'**unités de weekend** portant au moins un créneau
  /// disponible. Voir [uniteWeekend] pour la définition de l'unité.
  final int weekends;

  /// Le total d'**astreintes** : jours et nuits confondus. C'est ce que
  /// plafonne `max_shifts` (ticket 013), et c'est le seul nombre de l'écran
  /// qu'aucun des trois compteurs ne porte seul.
  int get astreintes => jours + nuits;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompteursMois &&
          other.jours == jours &&
          other.nuits == nuits &&
          other.weekends == weekends;

  @override
  int get hashCode => Object.hash(jours, nuits, weekends);

  @override
  String toString() => 'CompteursMois($jours j, $nuits n, $weekends we)';
}

/// L'unité de weekend à laquelle appartient [jour], ou `null` s'il n'en fait
/// partie d'aucune.
///
/// Trois règles, tranchées au brief § 6.4 depuis `PRD § 6.3` :
///
/// 1. **Samedi et dimanche d'une même semaine forment une seule unité.** Une
///    astreinte sur l'un des quatre créneaux compte pour un weekend. L'unité
///    est désignée par la date de **son samedi**, ce qui la rend unique même
///    quand le dimanche appartient à un autre mois.
/// 2. **Un jour férié du lundi au vendredi forme à lui seul une unité**, parce
///    que le PRD compte les fériés comme des weekends.
/// 3. **Un férié tombant un samedi ou un dimanche se fond dans l'unité de ce
///    weekend** : il ne compte pas deux fois. La règle 1 l'emporte, et c'est
///    exactement ce que fait l'ordre des tests ci-dessous.
///
/// Au bord du mois, un samedi seul ou un dimanche seul forme l'unité du mois
/// à lui tout seul — c'est une hypothèse de conception, le PRD ne tranche pas
/// (brief § 7.6), et le ticket 013 devra utiliser ce même calcul côté quota.
DateTime? uniteWeekend(DateTime jour) {
  final nu = DateTime(jour.year, jour.month, jour.day);
  return switch (nu.weekday) {
    DateTime.saturday => nu,
    DateTime.sunday => nu.subtract(const Duration(days: 1)),
    _ => estJourFerie(nu) ? nu : null,
  };
}

/// Le nombre d'unités de weekend que contient un mois, quel que soit ce qui
/// y est coché.
///
/// C'est la borne du plafond de weekends (ticket 013) : proposer « 6
/// weekends » dans un mois qui n'en compte que 5 serait un chiffre faux. Le
/// calcul est **exactement** celui du compteur — [uniteWeekend] —, jamais un
/// second, ce que le brief du 011 § 7.6 laissait à trancher.
int unitesWeekendDuMois(Iterable<DateTime> jours) {
  final unites = <DateTime>{};
  for (final jour in jours) {
    final unite = uniteWeekend(jour);
    if (unite != null) unites.add(unite);
  }
  return unites.length;
}

/// Ce qu'un membre a saisi pour un mois, plus ce que ça donne au compteur.
///
/// « Non saisi » n'est **jamais** une valeur stockée : c'est l'absence de clé
/// dans [valeurs] (`docs/SCHEMA.md § 2.6`). Une carte qui contiendrait
/// `nonSaisi` mentirait sur ce qu'il y a en base, et c'est ce mensonge qui
/// ferait écrire une ligne au lieu de la supprimer.
@immutable
class DisponibiliteMois {
  DisponibiliteMois({
    required this.annee,
    required this.mois,
    required Map<CreneauCle, DisponibiliteEtat> valeurs,
  }) : valeurs = Map<CreneauCle, DisponibiliteEtat>.unmodifiable(
         <CreneauCle, DisponibiliteEtat>{
           for (final entree in valeurs.entries)
             if (entree.value != DisponibiliteEtat.nonSaisi)
               entree.key: entree.value,
         },
       );

  const DisponibiliteMois.vide({required this.annee, required this.mois})
    : valeurs = const <CreneauCle, DisponibiliteEtat>{};

  final int annee;
  final int mois;

  /// Les seules cases saisies, `disponible` ou `absent`.
  final Map<CreneauCle, DisponibiliteEtat> valeurs;

  bool get estVierge => valeurs.isEmpty;

  /// L'état **affiché** d'une case : l'absence de ligne vaut « non saisi ».
  DisponibiliteEtat etat(CreneauCle cle) =>
      valeurs[cle] ?? DisponibiliteEtat.nonSaisi;

  /// Une copie avec [modifications] appliquées. Une valeur `nonSaisi` retire
  /// la clé au lieu de l'écrire.
  DisponibiliteMois avec(Map<CreneauCle, DisponibiliteEtat> modifications) =>
      DisponibiliteMois(
        annee: annee,
        mois: mois,
        valeurs: <CreneauCle, DisponibiliteEtat>{...valeurs, ...modifications},
      );

  /// Les trois compteurs, recalculés à la demande.
  ///
  /// Le coût est celui d'un parcours des seules cases saisies — au pire 62 —
  /// et il est payé une fois par image de la barre du bas, pas une fois par
  /// case peinte.
  CompteursMois get compteurs {
    var jours = 0;
    var nuits = 0;
    final weekends = <DateTime>{};

    for (final entree in valeurs.entries) {
      if (entree.value != DisponibiliteEtat.disponible) continue;

      if (entree.key.creneau == CreneauType.jour) {
        jours++;
      } else {
        nuits++;
      }

      final unite = uniteWeekend(entree.key.date);
      if (unite != null) weekends.add(unite);
    }

    return CompteursMois(jours: jours, nuits: nuits, weekends: weekends.length);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisponibiliteMois &&
          other.annee == annee &&
          other.mois == mois &&
          mapEquals(other.valeurs, valeurs);

  @override
  int get hashCode => Object.hash(
    annee,
    mois,
    Object.hashAllUnordered(
      valeurs.entries.map((entree) => Object.hash(entree.key, entree.value)),
    ),
  );
}

/// Le cran suivant du cycle de la case : `non saisi → disponible → absent →
/// non saisi`.
///
/// L'ordre n'est pas arbitraire (brief § 6.1) : il place « disponible » à une
/// touche du repos, « absent » à deux, « effacer » à trois — l'ordre
/// décroissant des fréquences réelles.
DisponibiliteEtat cranSuivant(DisponibiliteEtat etat) => switch (etat) {
  DisponibiliteEtat.nonSaisi => DisponibiliteEtat.disponible,
  DisponibiliteEtat.disponible => DisponibiliteEtat.absent,
  DisponibiliteEtat.absent => DisponibiliteEtat.nonSaisi,
};
