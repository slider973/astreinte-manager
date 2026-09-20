import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/l10n/jours_feries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Pâques — comput grégorien de Meeus/Butcher', () {
    // Références : Bureau des longitudes. Les bords volontairement choisis :
    // une Pâques de mars (2027, 2029) et une Pâques tardive (2038, 25 avril).
    const attendus = <int, (int, int)>{
      2026: (4, 5),
      2027: (3, 28),
      2028: (4, 16),
      2029: (4, 1),
      2030: (4, 21),
      2038: (4, 25),
    };

    for (final entree in attendus.entries) {
      test('Pâques ${entree.key}', () {
        expect(
          paquesGregorien(entree.key),
          DateTime(entree.key, entree.value.$1, entree.value.$2),
        );
      });
    }
  });

  group('Jours fériés — les onze, chaque année', () {
    test('2026 en compte onze', () {
      expect(joursFeriesDeLAnnee(2026), hasLength(11));
    });

    test('mai 2026 : quatre fériés, Ascension et Pentecôte comprises', () {
      // Le brief § 5.1 annonce « 3 (mai, années à Ascension + Pentecôte) » :
      // c'est le calcul qui a raison, et mai 2026 en porte bien quatre.
      // Pâques 2026 = 5 avril, + 39 = 14 mai, + 50 = 25 mai.
      final mai = joursFeriesDuMois(2026, 5);

      expect(mai, hasLength(4));
      expect(mai[DateTime(2026, 5)], AppStrings.ferieFeteTravail);
      expect(mai[DateTime(2026, 5, 8)], AppStrings.ferieVictoire1945);
      expect(mai[DateTime(2026, 5, 14)], AppStrings.ferieAscension);
      expect(mai[DateTime(2026, 5, 25)], AppStrings.feriePentecote);
    });

    test('2027 : lundi de Pâques en mars, pas en avril', () {
      // Pâques 2027 = 28 mars, donc le lundi de Pâques est le 29 mars.
      expect(joursFeriesDuMois(2027, 3), <DateTime, String>{
        DateTime(2027, 3, 29): AppStrings.feriePaques,
      });
      expect(nomJourFerie(DateTime(2027, 4, 29)), isNull);
    });

    test('2029 : Pentecôte le 21 mai', () {
      // Pâques 2029 = 1er avril, + 50 jours = 21 mai. Le changement d'heure du
      // 25 mars est traversé : la date doit rester le 21, pas le 20 à 23 h.
      expect(nomJourFerie(DateTime(2029, 5, 21)), AppStrings.feriePentecote);
      expect(nomJourFerie(DateTime(2029, 5, 20)), isNull);
    });

    test('2026 à 2030 : onze fériés distincts chaque année', () {
      for (var annee = 2026; annee <= 2030; annee++) {
        final feries = joursFeriesDeLAnnee(annee);
        expect(feries, hasLength(11), reason: 'année $annee');
        expect(
          feries.keys.map((jour) => jour.year).toSet(),
          <int>{annee},
          reason: 'année $annee : un férié a débordé sur une autre année',
        );
        for (final jour in feries.keys) {
          expect(jour.hour, 0, reason: 'année $annee : $jour n\'est pas nu');
        }
      }
    });

    test('les huit fériés fixes sont aux bonnes dates', () {
      expect(nomJourFerie(DateTime(2027)), AppStrings.feriePremierJanvier);
      expect(nomJourFerie(DateTime(2027, 5)), AppStrings.ferieFeteTravail);
      expect(nomJourFerie(DateTime(2027, 5, 8)), AppStrings.ferieVictoire1945);
      expect(
        nomJourFerie(DateTime(2027, 7, 14)),
        AppStrings.ferieFeteNationale,
      );
      expect(nomJourFerie(DateTime(2027, 8, 15)), AppStrings.ferieAssomption);
      expect(nomJourFerie(DateTime(2027, 11)), AppStrings.ferieToussaint);
      expect(nomJourFerie(DateTime(2027, 11, 11)), AppStrings.ferieArmistice);
      expect(nomJourFerie(DateTime(2027, 12, 25)), AppStrings.ferieNoel);
    });

    test('un jour ordinaire n\'est pas férié', () {
      expect(estJourFerie(DateTime(2026, 10, 14)), isFalse);
      expect(nomJourFerie(DateTime(2026, 10, 14)), isNull);
    });

    test('l\'heure de la date passée n\'entre pas dans la clé', () {
      expect(
        nomJourFerie(DateTime(2026, 12, 25, 23, 59)),
        AppStrings.ferieNoel,
      );
    });

    test(
      'Alsace-Moselle n\'est pas traitée : ni Vendredi saint ni 26 décembre',
      () {
        // Vendredi saint 2026 = 3 avril (Pâques − 2).
        expect(nomJourFerie(DateTime(2026, 4, 3)), isNull);
        expect(nomJourFerie(DateTime(2026, 12, 26)), isNull);
      },
    );
  });
}
