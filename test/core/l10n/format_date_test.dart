import 'package:astreinte_sp/core/l10n/format_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Formats de date de la grille', () {
    test('nomJourCourt suit la semaine française, du lundi au dimanche', () {
      // 5 octobre 2026 est un lundi.
      expect(nomJourCourt(DateTime(2026, 10, 5)), 'lun.');
      expect(nomJourCourt(DateTime(2026, 10, 10)), 'sam.');
      expect(nomJourCourt(DateTime(2026, 10, 11)), 'dim.');
    });

    test('nomJourLong donne le nom entier', () {
      expect(nomJourLong(DateTime(2026, 10, 10)), 'samedi');
    });

    test('dateAvecJourSemaine compose la phrase annoncée', () {
      expect(
        dateAvecJourSemaine(DateTime(2026, 10, 10)),
        'samedi 10 octobre',
      );
    });

    test('le premier du mois se dit « 1er »', () {
      expect(dateAvecJourSemaine(DateTime(2026, 11)), 'dimanche 1er novembre');
    });

    test('isoJour rend la colonne `date` de Postgres', () {
      expect(isoJour(DateTime(2026, 10, 4)), '2026-10-04');
      expect(isoJour(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('depuisIsoJour rend un jour local à minuit', () {
      final jour = depuisIsoJour('2026-10-04');
      expect(jour, DateTime(2026, 10, 4));
      expect(jour.isUtc, isFalse);
    });

    test('un aller-retour ISO ne décale jamais le jour', () {
      for (var offset = 0; offset < 400; offset++) {
        final jour = DateTime(2026).add(Duration(days: offset));
        final nu = DateTime(jour.year, jour.month, jour.day);
        expect(depuisIsoJour(isoJour(nu)), nu);
      }
    });

    test('formaterDateCourte abrège le mois', () {
      expect(formaterDateCourte(DateTime(2026, 9, 15)), '15 sept.');
      expect(formaterDateCourte(DateTime(2026, 5)), '1er mai');
    });
  });
}
