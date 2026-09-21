import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/astreintes/domain/ics_astreinte.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_astreintes.dart';

/// Un fichier calendrier mal formé **ne se voit pas** : l'agenda n'affiche rien
/// et ne dit rien. Les erreurs qui coûtent le plus cher ici sont muettes — une
/// virgule non échappée qui coupe un intitulé, une ligne de plus de 75 octets
/// tranchée au milieu d'un accent, une nuit qui finit le jour même. D'où des
/// assertions sur le **texte produit**, caractère par caractère.
///
/// Le pendant serveur de ces mêmes règles est vérifié par
/// `supabase/functions/tests/calendrier_ics_test.ts`.
void main() {
  final genereLe = DateTime.utc(2026, 10, 15, 9, 30);

  // Les valeurs par défaut de `stations.settings` : 07:00 – 19:00.
  const heures = HeuresAffichage.defaut;

  IcsAstreinte fichier({
    CreneauType creneau = CreneauType.nuit,
    String caserne = 'CIS Saint-Martin',
    HeuresAffichage reglages = heures,
  }) => IcsAstreinte(
    astreinte: astreinte(
      id: 'a-17',
      creneauId: 'c-17',
      jour: DateTime(2026, 10, 17),
      creneau: creneau,
    ),
    heures: reglages,
    nomCaserne: caserne,
  );

  /// Les lignes du fichier, dépliées : une continuation commence par une
  /// espace et appartient à la ligne précédente (RFC 5545 § 3.1).
  List<String> lignes(String ics) {
    final depliees = <String>[];
    for (final ligne in ics.split('\r\n')) {
      if (ligne.isEmpty) continue;
      if (ligne.startsWith(' ') && depliees.isNotEmpty) {
        depliees[depliees.length - 1] += ligne.substring(1);
      } else {
        depliees.add(ligne);
      }
    }
    return depliees;
  }

  String propriete(String ics, String nom) => lignes(
    ics,
  ).firstWhere((String ligne) => ligne.startsWith('$nom:'), orElse: () => '');

  group('l\'enveloppe', () {
    test('est un VCALENDAR complet, en CRLF', () {
      final ics = fichier().composer(genereLe: genereLe);

      expect(ics.startsWith('BEGIN:VCALENDAR\r\n'), isTrue);
      expect(ics.endsWith('END:VCALENDAR\r\n'), isTrue);
      expect(ics, contains('VERSION:2.0'));
      expect(ics, contains('METHOD:PUBLISH'));
      // Aucun saut de ligne seul : la RFC n'en connaît pas, et plusieurs
      // clients refusent le fichier entier.
      expect(ics.replaceAll('\r\n', ''), isNot(contains('\n')));
    });

    test('porte un seul événement', () {
      final ics = fichier().composer(genereLe: genereLe);
      expect('BEGIN:VEVENT'.allMatches(ics).length, 1);
    });

    /// L'identifiant est celui de l'attribution, comme côté serveur : qui a
    /// installé l'abonnement **et** téléchargé ce fichier n'a pas deux lignes
    /// dans son agenda.
    test('identifie l\'événement par l\'attribution', () {
      final ics = fichier().composer(genereLe: genereLe);
      expect(propriete(ics, 'UID'), 'UID:a-17@astreinte-sp');
    });
  });

  group('le contenu de l\'événement', () {
    test('la nuit dit la nuit, et déborde sur le lendemain', () {
      final ics = fichier().composer(genereLe: genereLe);

      expect(
        propriete(ics, 'SUMMARY'),
        'SUMMARY:Astreinte nuit — CIS Saint-Martin',
      );
      expect(
        propriete(ics, 'DESCRIPTION'),
        'DESCRIPTION:Créneau de nuit\\, de 19:00 à 07:00. Astreinte acceptée.',
      );
      expect(propriete(ics, 'LOCATION'), 'LOCATION:CIS Saint-Martin');
      expect(propriete(ics, 'STATUS'), 'STATUS:CONFIRMED');

      // Le 17 à 19:00 locale, fin le 18 à 07:00 locale. L'heure exacte dépend
      // du fuseau de la machine de test : ce qui est vérifié est la durée et le
      // franchissement de minuit, qui n'en dépendent pas.
      final debut = _instantDe(propriete(ics, 'DTSTART'));
      final fin = _instantDe(propriete(ics, 'DTEND'));
      expect(fin.difference(debut), const Duration(hours: 12));
      expect(debut.toLocal().day, 17);
      expect(fin.toLocal().day, 18);
      expect(debut.toLocal().hour, 19);
      expect(fin.toLocal().hour, 7);
    });

    test('le jour reste dans sa journée', () {
      final ics = fichier(
        creneau: CreneauType.jour,
      ).composer(genereLe: genereLe);

      expect(
        propriete(ics, 'SUMMARY'),
        'SUMMARY:Astreinte jour — CIS Saint-Martin',
      );
      expect(
        propriete(ics, 'DESCRIPTION'),
        'DESCRIPTION:Créneau de jour\\, de 07:00 à 19:00. Astreinte acceptée.',
      );

      final debut = _instantDe(propriete(ics, 'DTSTART'));
      final fin = _instantDe(propriete(ics, 'DTEND'));
      expect(debut.toLocal().hour, 7);
      expect(fin.toLocal().hour, 19);
      expect(fin.toLocal().day, 17);
    });

    /// Les heures viennent des paramètres de la caserne, jamais d'un
    /// 7 h – 19 h écrit en dur (`docs/SCHEMA.md § 2.1`).
    test('suit les heures de la caserne', () {
      final ics = fichier(
        creneau: CreneauType.jour,
        reglages: const HeuresAffichage(debutJour: '06:30', finJour: '20:15'),
      ).composer(genereLe: genereLe);

      expect(propriete(ics, 'DESCRIPTION'), contains('de 06:30 à 20:15'));
      expect(_instantDe(propriete(ics, 'DTSTART')).toLocal().minute, 30);
      expect(_instantDe(propriete(ics, 'DTEND')).toLocal().hour, 20);
    });

    test('sans caserne lisible, pas de tiret orphelin ni de lieu vide', () {
      final ics = fichier(caserne: '').composer(genereLe: genereLe);

      expect(propriete(ics, 'SUMMARY'), 'SUMMARY:Astreinte nuit');
      expect(propriete(ics, 'LOCATION'), '');
    });

    /// Une alarme que personne n'a demandée se règle dans un troisième outil.
    /// L'application a déjà ses rappels (ticket 022).
    test('n\'ajoute aucune alarme', () {
      expect(fichier().composer(genereLe: genereLe), isNot(contains('VALARM')));
    });

    /// Le fichier voyage dans un dossier de téléchargements, puis dans un
    /// agenda partagé : rien de personne d'autre n'y entre.
    test('ne porte aucune identité', () {
      final ics = fichier().composer(genereLe: genereLe);
      expect(ics, isNot(contains('ATTENDEE')));
      expect(ics, isNot(contains('ORGANIZER')));
    });
  });

  group('le nom du fichier', () {
    test('porte la date en ISO et le créneau', () {
      expect(fichier().nomFichier, 'astreinte-2026-10-17-nuit.ics');
      expect(
        fichier(creneau: CreneauType.jour).nomFichier,
        'astreinte-2026-10-17-jour.ics',
      );
    });
  });

  group('l\'échappement et le pliage — les pannes muettes', () {
    test('les caractères de structure sont échappés', () {
      expect(
        echapperIcs('CIS Saint-Martin, annexe'),
        'CIS Saint-Martin\\, annexe',
      );
      expect(echapperIcs('a;b'), 'a\\;b');
      expect(echapperIcs(r'a\b'), r'a\\b');
      expect(echapperIcs('deux\nlignes'), 'deux\\nlignes');
      // La barre oblique inverse d'abord : sinon on échapperait ses ajouts.
      expect(echapperIcs(r'a\,b'), r'a\\\,b');
    });

    test('une virgule dans le nom d\'une caserne ne coupe pas l\'intitulé', () {
      final ics = fichier(
        caserne: 'CIS Saint-Martin, annexe des Prés',
      ).composer(genereLe: genereLe);

      expect(
        propriete(ics, 'SUMMARY'),
        'SUMMARY:Astreinte nuit — CIS Saint-Martin\\, annexe des Prés',
      );
    });

    test('aucune ligne ne dépasse 75 octets', () {
      final ics = fichier(
        caserne: 'Centre d\'incendie et de secours de Saint-Étienne-du-Rouvray',
      ).composer(genereLe: genereLe);

      for (final ligne in ics.split('\r\n')) {
        expect(
          _octets(ligne),
          lessThanOrEqualTo(75),
          reason: 'ligne de ${_octets(ligne)} octets : $ligne',
        );
      }
    });

    test('le pliage ne coupe jamais un caractère accentué en deux', () {
      // Que des « é » : chaque caractère pèse deux octets, donc une coupe naïve
      // à 75 octets tomberait au milieu de l'un d'eux.
      final plie = plierIcs('X:${'é' * 80}');
      final morceaux = plie.split('\r\n ');

      expect(morceaux.length, greaterThan(1));
      expect(morceaux.join(), 'X:${'é' * 80}');
      expect(plie, isNot(contains('�')));
    });

    test('une ligne courte n\'est pas pliée', () {
      expect(plierIcs('SUMMARY:Astreinte jour'), 'SUMMARY:Astreinte jour');
    });

    test('l\'horodatage est toujours en UTC, à la seconde', () {
      expect(
        horodatageIcs(DateTime.utc(2026, 1, 2, 3, 4, 5)),
        '20260102T030405Z',
      );
    });
  });
}

/// Relit un `DTSTART:20261017T170000Z`.
DateTime _instantDe(String propriete) {
  final valeur = propriete.split(':').last;
  return DateTime.utc(
    int.parse(valeur.substring(0, 4)),
    int.parse(valeur.substring(4, 6)),
    int.parse(valeur.substring(6, 8)),
    int.parse(valeur.substring(9, 11)),
    int.parse(valeur.substring(11, 13)),
    int.parse(valeur.substring(13, 15)),
  );
}

/// La taille d'une chaîne en octets UTF-8.
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
