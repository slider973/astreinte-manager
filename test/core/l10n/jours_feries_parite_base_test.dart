import 'package:astreinte_sp/core/l10n/format_date.dart';
import 'package:astreinte_sp/core/l10n/jours_feries.dart';
import 'package:astreinte_sp/features/dispos/domain/disponibilite_mois.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le calendrier français existe **deux fois** : ici, pour le compteur de
/// weekends du pompier (ticket 011), et en base, pour le quota restant que le
/// chef de centre lit dans la matrice (`supabase/migrations/0017_matrice_admin.sql`,
/// ticket 016). Le chef de centre ne rapatrie pas les attributions de ses
/// soixante membres pour les compter dans le navigateur ; le pompier ne fait pas
/// un aller-retour réseau pour animer un compteur. Les deux calculs sont donc
/// justifiés — et c'est précisément pour ça qu'ils doivent être surveillés.
///
/// Deux chiffres différents pour la même chose ne lèvent aucune exception, ne
/// cassent aucun écran, et font construire un planning sur un quota faux.
///
/// Ce fichier et `supabase/tests/matrice_admin_test.sql § 1` portent **le même
/// corpus**, caractère pour caractère : quinze années de jours fériés. Ce n'est
/// pas une copie de l'un des deux codes, c'est la référence des deux. Si l'un
/// des deux calculs bouge, l'un des deux tests rougit.
///
/// Si ce test échoue et que le corpus est juste, c'est le Dart qui a tort. S'il
/// échoue des deux côtés, c'est le corpus qu'il faut discuter — pas contourner.
const Map<int, String> feriesAttendus = <int, String>{
  2026:
      '2026-01-01 2026-04-06 2026-05-01 2026-05-08 2026-05-14 2026-05-25 '
      '2026-07-14 2026-08-15 2026-11-01 2026-11-11 2026-12-25',
  2027:
      '2027-01-01 2027-03-29 2027-05-01 2027-05-06 2027-05-08 2027-05-17 '
      '2027-07-14 2027-08-15 2027-11-01 2027-11-11 2027-12-25',
  2028:
      '2028-01-01 2028-04-17 2028-05-01 2028-05-08 2028-05-25 2028-06-05 '
      '2028-07-14 2028-08-15 2028-11-01 2028-11-11 2028-12-25',
  2029:
      '2029-01-01 2029-04-02 2029-05-01 2029-05-08 2029-05-10 2029-05-21 '
      '2029-07-14 2029-08-15 2029-11-01 2029-11-11 2029-12-25',
  2030:
      '2030-01-01 2030-04-22 2030-05-01 2030-05-08 2030-05-30 2030-06-10 '
      '2030-07-14 2030-08-15 2030-11-01 2030-11-11 2030-12-25',
  2031:
      '2031-01-01 2031-04-14 2031-05-01 2031-05-08 2031-05-22 2031-06-02 '
      '2031-07-14 2031-08-15 2031-11-01 2031-11-11 2031-12-25',
  2032:
      '2032-01-01 2032-03-29 2032-05-01 2032-05-06 2032-05-08 2032-05-17 '
      '2032-07-14 2032-08-15 2032-11-01 2032-11-11 2032-12-25',
  2033:
      '2033-01-01 2033-04-18 2033-05-01 2033-05-08 2033-05-26 2033-06-06 '
      '2033-07-14 2033-08-15 2033-11-01 2033-11-11 2033-12-25',
  2034:
      '2034-01-01 2034-04-10 2034-05-01 2034-05-08 2034-05-18 2034-05-29 '
      '2034-07-14 2034-08-15 2034-11-01 2034-11-11 2034-12-25',
  2035:
      '2035-01-01 2035-03-26 2035-05-01 2035-05-03 2035-05-08 2035-05-14 '
      '2035-07-14 2035-08-15 2035-11-01 2035-11-11 2035-12-25',
  2036:
      '2036-01-01 2036-04-14 2036-05-01 2036-05-08 2036-05-22 2036-06-02 '
      '2036-07-14 2036-08-15 2036-11-01 2036-11-11 2036-12-25',
  2037:
      '2037-01-01 2037-04-06 2037-05-01 2037-05-08 2037-05-14 2037-05-25 '
      '2037-07-14 2037-08-15 2037-11-01 2037-11-11 2037-12-25',
  2038:
      '2038-01-01 2038-04-26 2038-05-01 2038-05-08 2038-06-03 2038-06-14 '
      '2038-07-14 2038-08-15 2038-11-01 2038-11-11 2038-12-25',
  2039:
      '2039-01-01 2039-04-11 2039-05-01 2039-05-08 2039-05-19 2039-05-30 '
      '2039-07-14 2039-08-15 2039-11-01 2039-11-11 2039-12-25',
  2040:
      '2040-01-01 2040-04-02 2040-05-01 2040-05-08 2040-05-10 2040-05-21 '
      '2040-07-14 2040-08-15 2040-11-01 2040-11-11 2040-12-25',
};

void main() {
  group('Jours fériés — parité avec la base (migration 0017)', () {
    for (final entree in feriesAttendus.entries) {
      test('${entree.key} : les onze dates du corpus', () {
        final dates = joursFeriesDeLAnnee(entree.key).keys.toList()..sort();
        expect(dates.map(isoJour).join(' '), entree.value);
      });
    }
  });

  group('Unité de weekend — parité avec unite_weekend(date) en base', () {
    // Mai 2027 est le mois d'épreuve des deux côtés : le 1er mai tombe un
    // samedi, le 6 un jeudi, le 8 un samedi, le 17 un lundi. Les quatre cas de
    // la règle dans un seul mois. Mêmes assertions que
    // `supabase/tests/matrice_admin_test.sql § 2`.
    const cas = <String, String?>{
      // Samedi et dimanche font une seule unité, désignée par le samedi.
      '2027-05-15': '2027-05-15',
      '2027-05-16': '2027-05-15',
      // Un férié du lundi au vendredi forme son unité.
      '2027-05-06': '2027-05-06',
      '2027-05-17': '2027-05-17',
      // Un férié le samedi ou le dimanche ne double pas l'unité.
      '2027-05-01': '2027-05-01',
      '2027-05-02': '2027-05-01',
      '2027-05-08': '2027-05-08',
      '2027-05-09': '2027-05-08',
      // Un jour ordinaire n'appartient à aucune unité.
      '2027-05-12': null,
      // L'unité traverse le mois : c'est ce qui la rend unique.
      '2027-08-01': '2027-07-31',
    };

    for (final entree in cas.entries) {
      test('unité de ${entree.key}', () {
        final unite = uniteWeekend(DateTime.parse(entree.key));
        expect(unite == null ? null : isoJour(unite), entree.value);
      });
    }

    test('mai 2027 compte sept unités, pas neuf', () {
      // Quatre fériés dans le mois et pourtant sept unités : les 1er et 8 mai
      // sont des samedis. Même nombre que le test SQL.
      final jours = <DateTime>[
        for (var j = 1; j <= 31; j++) DateTime(2027, 5, j),
      ];
      expect(unitesWeekendDuMois(jours), 7);
    });
  });
}
