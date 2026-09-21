import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/astreintes/data/planning_caserne_repository.dart';
import 'package:astreinte_sp/features/astreintes/domain/planning_caserne.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_rest.dart';

/// Les lignes d'une caserne, telles que PostgREST les rend.
const String _station = 'st-1';
const String _moi = 'u-moi';

/// Août 2026, archivé le 1er septembre par `cron_archive_schedules`.
const MoisPlanning _moisArchive = MoisPlanning(
  planningId: 'p-08',
  annee: 2026,
  mois: 8,
  etat: PlanningEtat.archive,
);

Map<String, dynamic> _planning(
  String id,
  int annee,
  int mois,
  String statut,
) => <String, dynamic>{
  'id': id,
  'status': statut,
  'periods': <String, dynamic>{'year': annee, 'month': mois},
};

void main() {
  group('les mois atteignables', () {
    test(
      'un mois archivé reste dans le sélecteur : la requête le demande, et '
      'la réponse le garde',
      () async {
        // **La régression que le ticket 044 existe pour éviter.** La tâche
        // `archive_schedules` archive chaque mois écoulé le 1er du mois
        // suivant : un filtre à deux états ferait disparaître un mois de plus
        // du sélecteur tous les mois.
        final rest = FauxRest(<String, List<Map<String, dynamic>>>{
          'schedules': <Map<String, dynamic>>[
            _planning('p-08', 2026, 8, 'archived'),
            _planning('p-09', 2026, 9, 'archived'),
            _planning('p-10', 2026, 10, 'validated'),
            _planning('p-11', 2026, 11, 'published'),
          ],
        });
        addTearDown(rest.fermer);

        final mois = await SupabasePlanningCaserneRepository(
          rest.client,
        ).moisLisibles(stationId: _station);

        expect(
          rest.requete('schedules').queryParameters['status'],
          'in.("published","validated","archived")',
        );
        expect(
          mois.map((MoisPlanning m) => m.cle),
          <String>['2026-08', '2026-09', '2026-10', '2026-11'],
        );
        expect(mois.first.etat, PlanningEtat.archive);
      },
    );

    test('un brouillon n\'est pas demandé : ce n\'est pas un mois du membre', () {
      expect(MoisPlanning.etatsLisibles, isNot(contains('draft')));
    });
  });

  group('le planning d\'un mois archivé', () {
    test(
      'rend ses créneaux et les gardes tenues par les autres : le tableau '
      'du mois écoulé',
      () async {
        final rest = FauxRest(<String, List<Map<String, dynamic>>>{
          'shifts': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'c-3-nuit',
              'date': '2026-08-03',
              'slot': 'night',
              'required_count': 2,
            },
            <String, dynamic>{
              'id': 'c-4-jour',
              'date': '2026-08-04',
              'slot': 'day',
              'required_count': 2,
            },
          ],
          // Ce que rend `assignments_select_station_archived` : les `accepted`
          // de toute la caserne, et rien d'autre.
          'assignments': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'a-1',
              'user_id': _moi,
              'shift_id': 'c-3-nuit',
            },
            <String, dynamic>{
              'id': 'a-2',
              'user_id': 'u-thomas',
              'shift_id': 'c-3-nuit',
            },
          ],
          'memberships': <Map<String, dynamic>>[
            <String, dynamic>{
              'user_id': 'u-thomas',
              'display_name': 'Thomas M.',
              'profiles': <String, dynamic>{
                'first_name': 'Thomas',
                'last_name': 'Martin',
              },
            },
          ],
          'stations': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': _station,
              'name': 'Caserne',
              'timezone': 'Europe/Paris',
              'settings': <String, dynamic>{},
            },
          ],
        });
        addTearDown(rest.fermer);

        final planning = await SupabasePlanningCaserneRepository(rest.client)
            .lireMois(
              stationId: _station,
              userId: _moi,
              mois: _moisArchive,
            );

        expect(planning, isNotNull);
        // Les deux journées sont là, y compris celle que personne n'a tenue :
        // sur un mois archivé la base rend tout, donc un trou est un fait.
        expect(planning!.complet, isTrue);
        expect(planning.journees, hasLength(2));

        final nuit = planning.journees.first.creneaux.single;
        expect(nuit.moi, isTrue);
        expect(nuit.noms, <String>['Thomas M.']);

        final jour = planning.journees.last.creneaux.single;
        expect(jour.personne, isTrue);
      },
    );
  });
}
