import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/dispos/domain/disponibilite_mois.dart';
import 'package:flutter_test/flutter_test.dart';

/// Octobre 2026 : le 1er est un jeudi, les samedis sont les 3, 10, 17, 24, 31.
DisponibiliteMois mois(Map<(int, CreneauType), DisponibiliteEtat> saisies) =>
    DisponibiliteMois(
      annee: 2026,
      mois: 10,
      valeurs: <CreneauCle, DisponibiliteEtat>{
        for (final entree in saisies.entries)
          CreneauCle(DateTime(2026, 10, entree.key.$1), entree.key.$2):
              entree.value,
      },
    );

/// Les jours d'un mois, du 1er au dernier.
List<DateTime> joursDe(int annee, int mois) => <DateTime>[
  for (var j = 1; j <= DateTime(annee, mois + 1, 0).day; j++)
    DateTime(annee, mois, j),
];

void main() {
  group('Les unités de weekend du mois', () {
    // Ce chiffre est celui que le membre plafonne au ticket 013 et que l'admin
    // lit au ticket 016 : une erreur ici fausse le planning de toutes les
    // casernes. Les cas sont vérifiés à la main sur le calendrier français.
    test('un mois qui commence un dimanche compte le samedi de la veille', () {
      // Mars 2026 : le 1er est un dimanche, samedis les 7, 14, 21, 28.
      expect(unitesWeekendDuMois(joursDe(2026, 3)), 5);
    });

    test('un mois qui finit un samedi compte ce samedi seul', () {
      // Février 2026 : samedis les 7, 14, 21, 28, le 28 clôt le mois.
      expect(unitesWeekendDuMois(joursDe(2026, 2)), 5);
    });

    test('les fériés en semaine ajoutent chacun une unité', () {
      // Mai 2026 : 5 samedis, plus le 1er et le 8 (vendredis), l'Ascension
      // le 14 (jeudi) et la Pentecôte le 25 (lundi).
      expect(unitesWeekendDuMois(joursDe(2026, 5)), 9);
    });

    test('un férié tombant un samedi ne double pas son weekend', () {
      // Août 2026 : le 15 est un samedi, il se fond dans son unité.
      expect(unitesWeekendDuMois(joursDe(2026, 8)), 5);
    });
  });

  group('Le cycle de la case', () {
    test('non saisi → disponible → absent → non saisi', () {
      expect(
        cranSuivant(DisponibiliteEtat.nonSaisi),
        DisponibiliteEtat.disponible,
      );
      expect(
        cranSuivant(DisponibiliteEtat.disponible),
        DisponibiliteEtat.absent,
      );
      expect(cranSuivant(DisponibiliteEtat.absent), DisponibiliteEtat.nonSaisi);
    });

    test('trois crans ramènent au point de départ', () {
      for (final depart in DisponibiliteEtat.values) {
        expect(
          cranSuivant(cranSuivant(cranSuivant(depart))),
          depart,
          reason: 'le cycle doit boucler depuis ${depart.name}',
        );
      }
    });

    test('« disponible » est à une touche du repos', () {
      // L'ordre n'est pas décoratif : c'est celui des fréquences réelles.
      expect(
        cranSuivant(DisponibiliteEtat.nonSaisi),
        DisponibiliteEtat.disponible,
      );
    });
  });

  group('« Non saisi » n\'est jamais stocké', () {
    test('une valeur nonSaisi ne rentre pas dans la carte', () {
      final carte = mois(<(int, CreneauType), DisponibiliteEtat>{
        (1, CreneauType.jour): DisponibiliteEtat.nonSaisi,
        (1, CreneauType.nuit): DisponibiliteEtat.disponible,
      });

      expect(carte.valeurs, hasLength(1));
      expect(
        carte.etat(CreneauCle(DateTime(2026, 10), CreneauType.jour)),
        DisponibiliteEtat.nonSaisi,
      );
    });

    test('« avec » retire la clé au lieu d\'écrire nonSaisi', () {
      final cle = CreneauCle(DateTime(2026, 10, 5), CreneauType.nuit);
      final depart = mois(<(int, CreneauType), DisponibiliteEtat>{
        (5, CreneauType.nuit): DisponibiliteEtat.absent,
      });

      final apres = depart.avec(<CreneauCle, DisponibiliteEtat>{
        cle: DisponibiliteEtat.nonSaisi,
      });

      expect(apres.valeurs.containsKey(cle), isFalse);
      expect(apres.estVierge, isTrue);
    });

    test('un mois vierge n\'a aucune valeur', () {
      expect(
        const DisponibiliteMois.vide(annee: 2026, mois: 10).estVierge,
        isTrue,
      );
    });
  });

  group('Les compteurs — jours et nuits', () {
    test('comptent les disponibles, jamais les absents ni les vides', () {
      final carte = mois(<(int, CreneauType), DisponibiliteEtat>{
        (1, CreneauType.jour): DisponibiliteEtat.disponible,
        (2, CreneauType.jour): DisponibiliteEtat.absent,
        (2, CreneauType.nuit): DisponibiliteEtat.disponible,
        (5, CreneauType.nuit): DisponibiliteEtat.disponible,
        (6, CreneauType.nuit): DisponibiliteEtat.absent,
      });

      expect(carte.compteurs.jours, 1);
      expect(carte.compteurs.nuits, 2);
    });

    test('un mois entièrement absent affiche trois zéros', () {
      final carte = mois(<(int, CreneauType), DisponibiliteEtat>{
        for (
          var jour = 1;
          jour <= 31;
          jour++
        ) ...<(int, CreneauType), DisponibiliteEtat>{
          (jour, CreneauType.jour): DisponibiliteEtat.absent,
          (jour, CreneauType.nuit): DisponibiliteEtat.absent,
        },
      });

      expect(carte.compteurs, CompteursMois.zero);
    });
  });

  group('Les compteurs — l\'unité de weekend', () {
    test('un seul créneau coché sur un samedi vaut un weekend', () {
      // Samedi 3 octobre 2026.
      final carte = mois(<(int, CreneauType), DisponibiliteEtat>{
        (3, CreneauType.nuit): DisponibiliteEtat.disponible,
      });

      expect(carte.compteurs.weekends, 1);
    });

    test('samedi et dimanche de la même semaine ne comptent qu\'une fois', () {
      // Samedi 3 et dimanche 4 octobre 2026 : quatre créneaux, un weekend.
      final carte = mois(<(int, CreneauType), DisponibiliteEtat>{
        (3, CreneauType.jour): DisponibiliteEtat.disponible,
        (3, CreneauType.nuit): DisponibiliteEtat.disponible,
        (4, CreneauType.jour): DisponibiliteEtat.disponible,
        (4, CreneauType.nuit): DisponibiliteEtat.disponible,
      });

      expect(carte.compteurs.weekends, 1);
      expect(carte.compteurs.jours, 2);
      expect(carte.compteurs.nuits, 2);
    });

    test('deux weekends distincts comptent deux', () {
      final carte = mois(<(int, CreneauType), DisponibiliteEtat>{
        (3, CreneauType.jour): DisponibiliteEtat.disponible,
        (10, CreneauType.jour): DisponibiliteEtat.disponible,
      });

      expect(carte.compteurs.weekends, 2);
    });

    test('un weekend entièrement absent ne compte pas', () {
      final carte = mois(<(int, CreneauType), DisponibiliteEtat>{
        (3, CreneauType.jour): DisponibiliteEtat.absent,
        (4, CreneauType.nuit): DisponibiliteEtat.absent,
      });

      expect(carte.compteurs.weekends, 0);
    });

    test('un férié du mardi forme à lui seul une unité', () {
      // 11 novembre 2026 est un mercredi : Armistice.
      final novembre = DisponibiliteMois(
        annee: 2026,
        mois: 11,
        valeurs: <CreneauCle, DisponibiliteEtat>{
          CreneauCle(DateTime(2026, 11, 11), CreneauType.jour):
              DisponibiliteEtat.disponible,
        },
      );

      expect(DateTime(2026, 11, 11).weekday, DateTime.wednesday);
      expect(novembre.compteurs.weekends, 1);
    });

    test('un férié tombant un samedi ne double pas le weekend', () {
      // 15 août 2026 est un samedi : Assomption. Le férié se fond dans
      // l'unité du weekend du 15–16, il ne crée pas une seconde unité.
      final aout = DisponibiliteMois(
        annee: 2026,
        mois: 8,
        valeurs: <CreneauCle, DisponibiliteEtat>{
          CreneauCle(DateTime(2026, 8, 15), CreneauType.jour):
              DisponibiliteEtat.disponible,
          CreneauCle(DateTime(2026, 8, 16), CreneauType.nuit):
              DisponibiliteEtat.disponible,
        },
      );

      expect(DateTime(2026, 8, 15).weekday, DateTime.saturday);
      expect(aout.compteurs.weekends, 1);
    });

    test('un jour ouvré non férié n\'appartient à aucune unité', () {
      expect(uniteWeekend(DateTime(2026, 10, 6)), isNull);
    });

    test('au bord du mois, un dimanche seul forme son unité', () {
      // 1er novembre 2026 est un dimanche (et la Toussaint) : son samedi est
      // le 31 octobre, qui n'appartient pas au mois affiché. L'unité existe
      // quand même, désignée par ce samedi.
      expect(uniteWeekend(DateTime(2026, 11)), DateTime(2026, 10, 31));

      final novembre = DisponibiliteMois(
        annee: 2026,
        mois: 11,
        valeurs: <CreneauCle, DisponibiliteEtat>{
          CreneauCle(DateTime(2026, 11), CreneauType.jour):
              DisponibiliteEtat.disponible,
        },
      );
      expect(novembre.compteurs.weekends, 1);
    });

    test('le samedi 31 et le dimanche 1er restent une seule unité', () {
      // Cas limite du chevauchement de mois, vu depuis octobre.
      expect(
        uniteWeekend(DateTime(2026, 10, 31)),
        uniteWeekend(DateTime(2026, 11)),
      );
    });
  });

  group('CreneauCle', () {
    test('deux clés du même jour et du même créneau sont égales', () {
      expect(
        CreneauCle(DateTime(2026, 10, 4, 23, 30), CreneauType.nuit),
        CreneauCle(DateTime(2026, 10, 4), CreneauType.nuit),
      );
    });

    test('l\'heure ne rentre pas dans la clé', () {
      expect(
        CreneauCle(DateTime(2026, 10, 4, 23), CreneauType.jour).date,
        DateTime(2026, 10, 4),
      );
    });

    test('le jour et la nuit du même jour sont deux clés', () {
      expect(
        CreneauCle(DateTime(2026, 10, 4), CreneauType.jour),
        isNot(CreneauCle(DateTime(2026, 10, 4), CreneauType.nuit)),
      );
    });

    test('l\'ordre est celui du registre : par jour, jour avant nuit', () {
      final cles = <CreneauCle>[
        CreneauCle(DateTime(2026, 10, 5), CreneauType.jour),
        CreneauCle(DateTime(2026, 10, 4), CreneauType.nuit),
        CreneauCle(DateTime(2026, 10, 4), CreneauType.jour),
      ]..sort();

      expect(cles.map((cle) => cle.toString()), <String>[
        '2026-10-04/jour',
        '2026-10-04/nuit',
        '2026-10-05/jour',
      ]);
    });

    test('une carte coalesce par construction', () {
      final file = <CreneauCle, DisponibiliteEtat>{};
      final cle = CreneauCle(DateTime(2026, 10, 4), CreneauType.jour);

      for (var essai = 0; essai < 40; essai++) {
        file[CreneauCle(DateTime(2026, 10, 4), CreneauType.jour)] =
            DisponibiliteEtat.values[essai % 3];
      }

      expect(file, hasLength(1));
      expect(file[cle], DisponibiliteEtat.values[39 % 3]);
    });
  });
}
