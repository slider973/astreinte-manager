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

/// L'ancienneté d'un événement, dite comme on la dit : « il y a 20 min »,
/// « hier », puis « 15 sept. » au-delà d'une semaine.
///
/// Entre deux activités, on ne compte pas des jours : le relatif est ce qui se
/// lit sans réfléchir. Mais il ment passé quelques jours — « il y a 23 j » ne
/// dit plus rien à personne — donc on repasse à la date, et à la date avec
/// l'année dès qu'on change d'année.
///
/// [maintenant] n'existe que pour les tests : une horloge injectée évite un
/// test qui échoue à minuit.
String formaterInstantRelatif(DateTime instant, {DateTime? maintenant}) {
  final reference = (maintenant ?? DateTime.now()).toLocal();
  final locale = instant.toLocal();
  final ecart = reference.difference(locale);

  // Une date future — horloge du téléphone en retard sur le serveur — se dit
  // « à l'instant » plutôt que « il y a -3 min ».
  if (ecart.inMinutes < 1) return AppStrings.instantMaintenant;
  if (ecart.inMinutes < 60) return AppStrings.instantMinutes(ecart.inMinutes);

  final jour = DateTime(reference.year, reference.month, reference.day);
  final jourDeLInstant = DateTime(locale.year, locale.month, locale.day);
  final jours = jour.difference(jourDeLInstant).inDays;

  if (jours == 0) return AppStrings.instantHeures(ecart.inHours);
  if (jours == 1) return AppStrings.instantHier;
  if (jours < 7) return AppStrings.instantJours(jours);
  if (locale.year == reference.year) return formaterDateCourte(locale);
  return formaterDateLongue(locale);
}

/// L'heure du jour : « 15 h 12 ».
///
/// Sur l'heure **locale** : le moment où le plafond d'invitations se rouvre est
/// une heure qu'on lit sur sa montre, pas un horodatage UTC.
String formaterHeureDuJour(DateTime instant) {
  final locale = instant.toLocal();
  return AppStrings.heureDuJour(heures: locale.hour, minutes: locale.minute);
}
