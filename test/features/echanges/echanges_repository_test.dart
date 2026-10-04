/// Le dépôt Supabase des échanges : **ce qui part vraiment sur le fil**.
///
/// Les arguments des quatre fonctions sont construits à la main, clé par clé :
/// ce test échoue si une clé de trop s'y glissait, ou si un motif partait
/// avec une validation.
library;

import 'dart:convert';

import 'package:astreinte_sp/features/echanges/data/echanges_repository.dart';
import 'package:astreinte_sp/features/echanges/domain/echange.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Fil {
  final List<http.Request> requetes = <http.Request>[];
  Object? Function(http.Request requete) reponse = (_) => <String, dynamic>{
    'ok': true,
  };

  late final SupabaseClient client = SupabaseClient(
    'https://caserne.exemple.test',
    'cle-anon-de-test',
    httpClient: MockClient((http.Request requete) async {
      requetes.add(requete);
      return http.Response(
        jsonEncode(reponse(requete)),
        200,
        headers: <String, String>{'content-type': 'application/json'},
        request: requete,
      );
    }),
  );

  Map<String, dynamic> corps(int i) =>
      jsonDecode(requetes[i].body) as Map<String, dynamic>;
}

void main() {
  late _Fil fil;
  late SupabaseEchangesRepository depot;

  setUp(() {
    fil = _Fil();
    depot = SupabaseEchangesRepository(
      fil.client,
      horloge: () => DateTime.utc(2026, 10, 4, 12),
    );
  });
  tearDown(() => fil.client.dispose());

  test('request_exchange : trois arguments, et rien d\'autre', () async {
    fil.reponse = (_) => <String, dynamic>{
      'ok': true,
      'exchange_id': 'e-1',
      'status': 'open',
      'kind': 'give',
      'broadcast': true,
      'expires_at': '2026-10-23T17:00:00Z',
      'notified': 0,
    };
    final r = await depot.demander(attributionId: 'att-a');
    expect(fil.requetes.single.url.path, endsWith('/rpc/request_exchange'));
    expect(fil.corps(0), <String, dynamic>{
      'p_assignment': 'att-a',
      'p_target': null,
      'p_return_assignment': null,
    });
    expect(r.ok, isTrue);
    expect(r.notifies, 0);
    expect(r.statut, StatutEchange.ouvert);
  });

  test('respond_exchange et cancel_exchange', () async {
    await depot.repondre(echangeId: 'e-1', accepte: false);
    await depot.annuler(echangeId: 'e-1');
    expect(fil.corps(0), <String, dynamic>{
      'p_exchange': 'e-1',
      'p_accept': false,
    });
    expect(fil.corps(1), <String, dynamic>{'p_exchange': 'e-1'});
  });

  test('decide_exchange : le motif ne part qu\'avec un refus', () async {
    await depot.decider(echangeId: 'e-1', valide: true, motif: 'ignoré');
    await depot.decider(echangeId: 'e-1', valide: false, motif: '  complet ');
    expect(fil.corps(0), <String, dynamic>{
      'p_exchange': 'e-1',
      'p_approve': true,
      'p_reason': null,
    });
    expect(fil.corps(1)['p_reason'], 'complet');
  });

  test('un refus métier revient en réponse, pas en exception', () async {
    fil.reponse = (_) => <String, dynamic>{
      'ok': false,
      'code': 'exchange_failed',
      'reason_code': 'peer_already_assigned',
      'detail': 'peer_taken_elsewhere',
      'status': 'failed',
    };
    final r = await depot.decider(echangeId: 'e-1', valide: true);
    expect(r.ok, isFalse);
    expect(r.code, 'exchange_failed');
    expect(r.codeMotif, 'peer_already_assigned');
    expect(r.detail, 'peer_taken_elsewhere');
  });

  test('exchangeable_shifts_of : seulement la caserne courante', () async {
    fil.reponse = (_) => <Map<String, dynamic>>[
      <String, dynamic>{
        'assignment_id': 'att-b2',
        'shift_id': 'c-2',
        'station_id': 'autre',
        'date': '2026-10-20',
        'slot': 'day',
        'expires_at': null,
      },
      <String, dynamic>{
        'assignment_id': 'att-b1',
        'shift_id': 'c-1',
        'station_id': 'st-1',
        'date': '2026-10-27',
        'slot': 'day',
        'expires_at': '2026-10-26T05:00:00Z',
      },
    ];
    final gardes = await depot.gardesDe(pairId: 'u-b', stationId: 'st-1');
    expect(fil.corps(0), <String, dynamic>{'p_peer': 'u-b'});
    expect(gardes.single.attributionId, 'att-b1');
  });

  test(
    'lister : la caserne, les en cours, et trente jours de closes',
    () async {
      fil.reponse = (http.Request r) => r.url.path.endsWith('shift_exchanges')
          ? <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'e-1',
                'station_id': 'st-1',
                'kind': 'give',
                'status': 'open',
                'requester_id': 'u-a',
                'assignment_id': 'att-a',
                'shift_id': 'c-a',
                'target_id': null,
                'expires_at': '2026-10-23T17:00:00Z',
                'created_at': '2026-10-04T08:00:00Z',
                'garde': <String, dynamic>{
                  'date': '2026-10-24',
                  'slot': 'night',
                },
                'rendue': null,
              },
            ]
          : <Map<String, dynamic>>[
              <String, dynamic>{
                'user_id': 'u-a',
                'display_name': 'Antoine C.',
                'profiles': <String, dynamic>{
                  'first_name': 'A',
                  'last_name': 'C',
                },
              },
            ];
      final echanges = await depot.lister(stationId: 'st-1');
      final url = fil.requetes.first.url;
      expect(url.queryParameters['station_id'], 'eq.st-1');
      expect(
        url.queryParameters['or'],
        '(status.in.(open,accepted_by_peer),'
        'updated_at.gte.2026-09-04T12:00:00.000Z)',
      );
      expect(echanges.single.demandeurNom, 'Antoine C.');
      expect(echanges.single.aLaCaserne, isTrue);
    },
  );

  test('un admin demande exchange_open_to_me pour chaque demande à la '
      'caserne qui n\'est pas la sienne', () async {
    Map<String, dynamic> ligne(String id, String demandeur) =>
        <String, dynamic>{
          'id': id,
          'station_id': 'st-1',
          'kind': 'give',
          'status': 'open',
          'requester_id': demandeur,
          'assignment_id': 'att-$id',
          'shift_id': 'c-$id',
          'target_id': null,
          'expires_at': '2026-10-23T17:00:00Z',
          'created_at': '2026-10-04T08:00:00Z',
          'garde': <String, dynamic>{'date': '2026-10-24', 'slot': 'night'},
          'rendue': null,
        };
    fil.reponse = (http.Request r) {
      if (r.url.path.endsWith('shift_exchanges')) {
        return <Map<String, dynamic>>[
          ligne('e-1', 'u-a'),
          ligne('e-2', 'u-admin'),
        ];
      }
      if (r.url.path.endsWith('exchange_open_to_me')) return false;
      return <Map<String, dynamic>>[];
    };
    final echanges = await depot.lister(
      stationId: 'st-1',
      moi: 'u-admin',
      admin: true,
    );
    final appels = fil.requetes
        .where((http.Request r) => r.url.path.endsWith('exchange_open_to_me'))
        .toList();
    expect(appels, hasLength(1));
    expect(jsonDecode(appels.single.body), <String, dynamic>{
      'p_station': 'st-1',
      'p_shift': 'c-e-1',
      'p_requester': 'u-a',
    });
    expect(
      echanges.firstWhere((Echange e) => e.id == 'e-1').ouverteAMoi,
      isFalse,
    );

    // Un pompier ne la demande jamais : la RLS a déjà trié.
    fil.requetes.clear();
    await depot.lister(stationId: 'st-1', moi: 'u-b');
    expect(
      fil.requetes.where(
        (http.Request r) => r.url.path.endsWith('exchange_open_to_me'),
      ),
      isEmpty,
    );
  });

  test('une réponse qui n\'arrive pas est une panne de réseau', () async {
    final panne = SupabaseEchangesRepository(
      SupabaseClient(
        'https://caserne.exemple.test',
        'cle',
        httpClient: MockClient((_) async => throw http.ClientException('x')),
      ),
    );
    expect(
      () => panne.annuler(echangeId: 'e-1'),
      throwsA(
        isA<EchecEchange>().having(
          (EchecEchange e) => e.erreur,
          'erreur',
          ErreurEchange.reseau,
        ),
      ),
    );
  });
}
