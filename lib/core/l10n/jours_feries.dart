/// Les jours fériés français, **calculés** et non tabulés.
///
/// Le brief du ticket 011 (§ 7.2) tranche contre une table en dur sur trois
/// ans : l'application ouvre des mois deux mois à l'avance, indéfiniment, et
/// une table qui périme en silence produirait un weekend manquant au compteur
/// sans que personne ne s'en aperçoive.
///
/// Onze fériés métropolitains : huit à date fixe, trois adossés à Pâques.
/// **Les fériés d'Alsace-Moselle (Vendredi saint, 26 décembre) ne sont pas
/// traités** : ce serait un paramètre de caserne, il n'existe pas au schéma.
library;

import 'app_strings.dart';

/// Dimanche de Pâques de [annee], par l'algorithme de Meeus/Butcher
/// (comput grégorien, valable de 1583 à 4099).
///
/// Ce n'est pas un jour férié en France — il tombe un dimanche — mais les
/// trois fériés mobiles s'en déduisent : lundi de Pâques = +1, Ascension =
/// +39, lundi de Pentecôte = +50.
DateTime paquesGregorien(int annee) {
  final a = annee % 19;
  final b = annee ~/ 100;
  final c = annee % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final numerateur = h + l - 7 * m + 114;
  return DateTime(annee, numerateur ~/ 31, numerateur % 31 + 1);
}

/// Normalise une date à minuit, heure locale : la clé d'un jour férié est un
/// jour, jamais un instant.
DateTime jourNu(DateTime date) {
  final locale = date.toLocal();
  return DateTime(locale.year, locale.month, locale.day);
}

/// Les onze jours fériés de [annee], du 1er janvier au 25 décembre.
///
/// Le résultat est mémorisé : la grille interroge le calendrier soixante-deux
/// fois par mois, et le comput de Pâques n'a pas à être refait à chaque case.
Map<DateTime, String> joursFeriesDeLAnnee(int annee) =>
    _cache.putIfAbsent(annee, () => _calculer(annee));

final Map<int, Map<DateTime, String>> _cache = <int, Map<DateTime, String>>{};

Map<DateTime, String> _calculer(int annee) {
  final paques = paquesGregorien(annee);

  final feries = <DateTime, String>{
    DateTime(annee): AppStrings.feriePremierJanvier,
    paques.add(const Duration(days: 1)): AppStrings.feriePaques,
    DateTime(annee, 5): AppStrings.ferieFeteTravail,
    DateTime(annee, 5, 8): AppStrings.ferieVictoire1945,
    paques.add(const Duration(days: 39)): AppStrings.ferieAscension,
    paques.add(const Duration(days: 50)): AppStrings.feriePentecote,
    DateTime(annee, 7, 14): AppStrings.ferieFeteNationale,
    DateTime(annee, 8, 15): AppStrings.ferieAssomption,
    DateTime(annee, 11): AppStrings.ferieToussaint,
    DateTime(annee, 11, 11): AppStrings.ferieArmistice,
    DateTime(annee, 12, 25): AppStrings.ferieNoel,
  };

  // `DateTime.add` traverse les changements d'heure : un « +39 jours » depuis
  // Pâques peut retomber à 23 h la veille. On renormalise chaque clé.
  return Map<DateTime, String>.unmodifiable(<DateTime, String>{
    for (final entree in feries.entries) jourNu(entree.key): entree.value,
  });
}

/// Les jours fériés du mois [mois] de [annee], avec leur nom en clair.
Map<DateTime, String> joursFeriesDuMois(int annee, int mois) =>
    Map<DateTime, String>.unmodifiable(<DateTime, String>{
      for (final entree in joursFeriesDeLAnnee(annee).entries)
        if (entree.key.month == mois) entree.key: entree.value,
    });

/// Le nom du jour férié de [jour], ou `null` si ce jour n'en est pas un.
String? nomJourFerie(DateTime jour) {
  final nu = jourNu(jour);
  return joursFeriesDeLAnnee(nu.year)[nu];
}

/// Vrai si [jour] est un jour férié français métropolitain.
bool estJourFerie(DateTime jour) => nomJourFerie(jour) != null;
