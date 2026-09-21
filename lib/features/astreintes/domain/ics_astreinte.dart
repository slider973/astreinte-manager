import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/theme/app_status.dart';
import 'astreinte.dart';

/// Un fichier iCalendar (RFC 5545) portant **une** astreinte.
///
/// Le pendant local du flux d'abonnement (`supabase/functions/ics-feed`). Deux
/// producteurs pour un même format : c'est une duplication, et elle est
/// délibérée (`design/028-export-ics.md § 8`). La feuille de détail du ticket
/// 027 **ne charge rien** — c'est ce qui la rend aussi rapide hors ligne qu'en
/// ligne — et lui faire demander un fichier au serveur casserait cette promesse
/// pour la seule action qu'on déclenche en regardant une date.
///
/// **L'identifiant est celui de l'attribution**, comme côté serveur : qui a
/// installé l'abonnement *et* téléchargé ce fichier n'a pas deux lignes dans
/// son agenda, il a la même, deux fois décrite.
class IcsAstreinte {
  const IcsAstreinte({
    required this.astreinte,
    required this.heures,
    required this.nomCaserne,
  });

  final Astreinte astreinte;
  final HeuresAffichage heures;

  /// Le nom de la caserne, pour l'intitulé et le lieu. Vide quand la caserne
  /// n'a pas pu être lue : l'intitulé se replie alors sur « Astreinte nuit »
  /// plutôt que de finir par un tiret orphelin.
  final String nomCaserne;

  /// Les octets d'une ligne pliée, continuation comprise (RFC 5545 § 3.1).
  static const int _ligneMax = 75;

  /// Le nom du fichier remis : `astreinte-2026-11-14-nuit.ics`.
  ///
  /// La date en tête, en ISO : dans un dossier de téléchargements, c'est le
  /// seul ordre qui range les fichiers dans l'ordre des gardes.
  String get nomFichier => AppStrings.icsNomFichier(
    jourIso: isoJour(astreinte.jour),
    nuit: astreinte.creneau == CreneauType.nuit,
  );

  /// Le type de contenu du fichier, pour la feuille de partage du système.
  static const String typeMime = 'text/calendar';

  /// Le fichier, prêt à être remis.
  ///
  /// [genereLe] est injectable pour les tests : un `DTSTAMP` tiré de l'horloge
  /// rend toute comparaison de fichier impossible.
  String composer({DateTime? genereLe}) {
    final maintenant = (genereLe ?? DateTime.now()).toUtc();
    final nuit = astreinte.creneau == CreneauType.nuit;

    final debut = nuit ? heures.finJour : heures.debutJour;
    final fin = nuit ? heures.debutJour : heures.finJour;

    final depart = _instant(astreinte.jour, debut);
    // Un créneau qui franchit minuit finit le lendemain : toujours vrai de la
    // nuit, vrai aussi d'une caserne qui aurait réglé un « jour » débordant.
    final arrivee = _instant(
      _minutes(fin) <= _minutes(debut)
          ? astreinte.jour.add(const Duration(days: 1))
          : astreinte.jour,
      fin,
    );

    final lignes = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:$_prodid',
      'CALSCALE:GREGORIAN',
      // `PUBLISH` : le fichier se lit, il ne demande pas de réponse. Sans lui,
      // certains agendas proposent « Accepter / Refuser » — la réponse se donne
      // dans l'application (ticket 021), pas dans un agenda.
      'METHOD:PUBLISH',
      'BEGIN:VEVENT',
      'UID:${astreinte.id}@astreinte-sp',
      'DTSTAMP:${horodatageIcs(maintenant)}',
      'DTSTART:${horodatageIcs(depart)}',
      'DTEND:${horodatageIcs(arrivee)}',
      _intitule(nuit: nuit, caserne: nomCaserne),
      _description(nuit: nuit, debut: debut, fin: fin),
      if (nomCaserne.isNotEmpty) 'LOCATION:${echapperIcs(nomCaserne)}',
      // Une astreinte acceptée occupe : elle doit rendre son porteur « occupé »
      // dans les agendas partagés, pas « disponible ».
      'STATUS:CONFIRMED',
      'TRANSP:OPAQUE',
      'END:VEVENT',
      'END:VCALENDAR',
    ];

    // CRLF, et un CRLF final : la RFC ne connaît pas le saut de ligne seul, et
    // plusieurs clients refusent un fichier qui ne se termine pas par là.
    return '${lignes.map(plierIcs).join('\r\n')}\r\n';
  }

  static const String _prodid = '-//Astreinte SP//Astreinte//FR';

  /// Hors de la liste, comme [_intitule] : deux littéraux collés y seraient
  /// illisibles, et la règle `no_adjacent_strings_in_list` a raison — dans une
  /// liste, deux chaînes côte à côte ressemblent à une virgule oubliée.
  static String _intitule({required bool nuit, required String caserne}) =>
      'SUMMARY:'
      '${echapperIcs(AppStrings.icsIntitule(nuit: nuit, caserne: caserne))}';

  static String _description({
    required bool nuit,
    required String debut,
    required String fin,
  }) =>
      'DESCRIPTION:'
      '${echapperIcs(AppStrings.icsDescription(nuit: nuit, debut: debut, fin: fin))}';

  /// L'instant UTC d'une heure `HH:MM` un jour donné, **dans le fuseau de
  /// l'appareil**.
  ///
  /// C'est la seule hypothèse de ce fichier, et elle est assumée : un pompier
  /// qui télécharge sa propre garde est, à ce moment-là, dans le fuseau de sa
  /// caserne. Dart n'embarque pas de base de fuseaux, et en embarquer une pour
  /// ce seul bouton pèserait plus que la fonctionnalité. Le flux d'abonnement,
  /// lui, résout l'instant dans le fuseau de la caserne (`stations.timezone`,
  /// `ics-feed/calendrier.ts`) et reste juste quel que soit l'appareil.
  static DateTime _instant(DateTime jour, String heure) {
    final parties = heure.split(':');
    final heures = int.tryParse(parties.first) ?? 0;
    final minutes = parties.length > 1 ? int.tryParse(parties[1]) ?? 0 : 0;
    return DateTime(jour.year, jour.month, jour.day, heures, minutes).toUtc();
  }

  /// `HH:MM` en minutes depuis minuit.
  static int _minutes(String heure) {
    final parties = heure.split(':');
    final heures = int.tryParse(parties.first) ?? 0;
    final minutes = parties.length > 1 ? int.tryParse(parties[1]) ?? 0 : 0;
    return heures * 60 + minutes;
  }
}

/// `YYYYMMDDTHHMMSSZ` — la seule forme d'horodatage d'un fichier iCalendar.
String horodatageIcs(DateTime instant) {
  final utc = instant.toUtc();
  String deux(int valeur) => valeur.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}${deux(utc.month)}'
      '${deux(utc.day)}T${deux(utc.hour)}${deux(utc.minute)}'
      '${deux(utc.second)}Z';
}

/// Échappe une valeur de type TEXT (RFC 5545 § 3.3.11).
///
/// L'ordre compte : la barre oblique inverse d'abord, sans quoi on échapperait
/// les barres qu'on vient d'ajouter. Le nom d'une caserne peut porter une
/// virgule — « CIS Saint-Martin, annexe » — et sans échappement elle couperait
/// la propriété en deux valeurs, l'intitulé arrivant tronqué dans l'agenda.
String echapperIcs(String valeur) => valeur
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\r\n', '\\n')
    .replaceAll('\n', '\\n')
    .replaceAll('\r', '\\n');

/// Plie une ligne à 75 **octets** (RFC 5545 § 3.1), continuation préfixée d'une
/// espace.
///
/// Le compte est en octets, pas en caractères : « Saint-Étienne » pèse plus que
/// sa longueur. Et la coupe ne tombe jamais au milieu d'un caractère — un « É »
/// coupé en deux donne deux octets invalides, et l'agenda affiche un losange
/// noir au milieu du nom d'une caserne.
String plierIcs(String ligne) {
  if (_octets(ligne) <= IcsAstreinte._ligneMax) return ligne;

  final morceaux = <String>[];
  final courant = StringBuffer();
  var octets = 0;
  // La continuation commence par une espace, qui compte dans ses 75 octets.
  var plafond = IcsAstreinte._ligneMax;

  for (final rune in ligne.runes) {
    final caractere = String.fromCharCode(rune);
    final taille = _octets(caractere);
    if (octets + taille > plafond) {
      morceaux.add(courant.toString());
      courant.clear();
      octets = 0;
      plafond = IcsAstreinte._ligneMax - 1;
    }
    courant.write(caractere);
    octets += taille;
  }
  if (courant.isNotEmpty) morceaux.add(courant.toString());

  return morceaux.join('\r\n ');
}

/// La taille d'une chaîne en octets UTF-8, sans passer par `dart:convert` :
/// trois bornes suffisent, et c'est la seule chose dont le pliage a besoin.
int _octets(String valeur) {
  var total = 0;
  for (final rune in valeur.runes) {
    if (rune <= 0x7F) {
      total += 1;
    } else if (rune <= 0x7FF) {
      total += 2;
    } else if (rune <= 0xFFFF) {
      total += 3;
    } else {
      total += 4;
    }
  }
  return total;
}
