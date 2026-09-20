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

/// Une date courte pour une ligne d'état : « 15 sept. ».
String formaterDateCourte(DateTime date) {
  final locale = date.toLocal();
  return AppStrings.dateCourte(jour: locale.day, mois: locale.month);
}

/// Le nom abrégé du jour de la semaine : « sam. ».
///
/// `DateTime.weekday` vaut 1 pour lundi et 7 pour dimanche, ce qui est
/// exactement l'ordre des listes de [AppStrings] : la semaine française
/// commence le lundi, dans la grille comme dans le calendrier.
String nomJourCourt(DateTime date) =>
    AppStrings.grilleJoursCourts[date.toLocal().weekday - 1];

/// Le nom complet du jour de la semaine : « samedi ».
String nomJourLong(DateTime date) =>
    AppStrings.grilleJoursLongs[date.toLocal().weekday - 1];

/// La date annoncée par une case du registre : « samedi 4 octobre ».
///
/// Sans l'année : la grille n'affiche qu'un mois à la fois, et l'année est
/// déjà dans le sélecteur de mois. Une phrase de lecteur d'écran répétée
/// soixante-deux fois n'a pas à porter un mot inutile.
String dateAvecJourSemaine(DateTime date) {
  final locale = date.toLocal();
  return '${nomJourLong(locale)} '
      '${locale.day == 1 ? '1er' : locale.day} '
      '${AppStrings.moisLongs[locale.month - 1]}';
}

/// La date telle que Postgres l'attend pour une colonne `date` : `2026-10-04`.
///
/// Un créneau est « le 12 octobre, nuit » : jamais un horodatage, jamais un
/// fuseau (`docs/SCHEMA.md § Conventions`).
String isoJour(DateTime date) {
  final locale = date.toLocal();
  final mois = locale.month.toString().padLeft(2, '0');
  final jour = locale.day.toString().padLeft(2, '0');
  return '${locale.year}-$mois-$jour';
}

/// Lit une colonne `date` de Postgres. Le résultat est un jour **local** à
/// minuit : jamais un instant UTC, qui reculerait d'un jour à l'affichage.
DateTime depuisIsoJour(String valeur) {
  final brut = DateTime.parse(valeur);
  return DateTime(brut.year, brut.month, brut.day);
}
