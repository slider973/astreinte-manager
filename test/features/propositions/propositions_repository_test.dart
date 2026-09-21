import 'package:astreinte_sp/features/propositions/data/propositions_repository.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_rest.dart';

const String _station = 'st-1';
const String _moi = 'u-moi';

/// Une ligne d'`assignments` telle que PostgREST la rend, planning compris.
Map<String, dynamic> _ligne({
  required String id,
  required String date,
  required String planningId,
  required String etatPlanning,
}) => <String, dynamic>{
  'id': id,
  'status': 'proposed',
  'proposed_at': '2026-07-20T18:00:00Z',
  'reminder_count': 1,
  'last_reminder_at': '2026-07-27T18:00:00Z',
  'shifts': <String, dynamic>{
    'id': 'c-$id',
    'date': date,
    'slot': 'night',
    'schedule_id': planningId,
    'schedules': <String, dynamic>{'id': planningId, 'status': etatPlanning},
  },
};

void main() {
  group('la liste des propositions', () {
    test(
      'une proposition d\'un mois archivé n\'est plus proposée à la réponse',
      () async {
        // Le cas : août s'est terminé sans que ce pompier réponde. La ligne
        // est toujours `proposed`, et `assignments_select_own_published` la
        // rend toujours — c'est son histoire. Mais
        // `assignments_update_member_response` n'écrit plus sur un planning
        // archivé : la carte afficherait un bouton « Accepter » qui ne fait
        // rien (ticket 044).
        final rest = FauxRest(<String, List<Map<String, dynamic>>>{
          'assignments': <Map<String, dynamic>>[
            _ligne(
              id: 'a-aout',
              date: '2026-08-14',
              planningId: 'p-08',
              etatPlanning: 'archived',
            ),
            _ligne(
              id: 'a-octobre',
              date: '2026-10-17',
              planningId: 'p-10',
              etatPlanning: 'published',
            ),
            _ligne(
              id: 'a-novembre',
              date: '2026-11-03',
              planningId: 'p-11',
              etatPlanning: 'validated',
            ),
          ],
        });
        addTearDown(rest.fermer);

        final propositions = await SupabasePropositionsRepository(
          rest.client,
        ).lister(userId: _moi, stationId: _station);

        expect(
          propositions.map((Proposition p) => p.id),
          <String>['a-octobre', 'a-novembre'],
        );
        // Une seule requête, comme le promet l'interface : le filtre est un
        // tri de la réponse, pas un aller-retour de plus.
        expect(rest.compte('assignments'), 1);
      },
    );

    test('les filtres de la requête ne bougent pas', () async {
      final rest = FauxRest();
      addTearDown(rest.fermer);

      await SupabasePropositionsRepository(
        rest.client,
      ).lister(userId: _moi, stationId: _station);

      final requete = rest.requete('assignments').queryParameters;
      expect(requete['user_id'], 'eq.$_moi');
      expect(requete['station_id'], 'eq.$_station');
      expect(requete['status'], 'eq.proposed');
      expect(requete['proposed_at'], 'not.is.null');
    });
  });
}
