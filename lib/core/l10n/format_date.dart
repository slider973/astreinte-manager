import 'app_strings.dart';

/// Une date en toutes lettres : « 4 octobre 2026 ».
///
/// L'application n'embarque pas `intl` : une date longue en français tient en
/// trois mots, et la liste des mois vit dans [AppStrings] comme tout le reste
/// des textes. Le formatage est fait sur l'heure **locale** : une invitation
/// qui expire le 4 à 1 h du matin n'expire pas « le 3 » parce que le serveur
/// pense en UTC.
String formaterDateLongue(DateTime date) {
  final locale = date.toLocal();
  return AppStrings.dateLongue(
    jour: locale.day,
    mois: locale.month,
    annee: locale.year,
  );
}
