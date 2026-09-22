import 'dart:convert';

import 'package:astreinte_sp/features/invitation/data/invitation_repository.dart';
import 'package:astreinte_sp/features/invitation/domain/acceptation.dart';
import 'package:astreinte_sp/features/invitation/domain/invitation_recue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// **Le transport est remplacé, le dépôt reste le vrai.**
///
/// C'est la seule façon de verrouiller ce qui part vraiment sur le réseau :
/// l'URL appelée, et surtout le corps de la requête d'acceptation, qui doit
/// porter un jeton **ou** un identifiant, jamais les deux.
class _FauxTransport {
  final List<http.Request> appels = <http.Request>[];

  /// Ce que le serveur rend. Un objet pour l'Edge Function, un tableau pour la
  /// fonction SQL, comme PostgREST.
  Object? reponse = const <String, dynamic>{};

  late final SupabaseClient client = SupabaseClient(
    'https://caserne.exemple.test',
    'cle-anon-de-test',
    httpClient: MockClient(_repondre),
  );

  http.Request get dernier => appels.last;

  Map<String, dynamic> get corpsEnvoye =>
      jsonDecode(dernier.body) as Map<String, dynamic>;

  Future<http.Response> _repondre(http.Request requete) async {
    appels.add(requete);
    return http.Response(
      jsonEncode(reponse),
      200,
      request: requete,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}

void main() {
  late _FauxTransport transport;
  late SupabaseInvitationRepository depot;

  setUp(() {
    transport = _FauxTransport();
    depot = SupabaseInvitationRepository(transport.client);
  });

  tearDown(() => transport.client.dispose());

  group('accept-invitation', () {
    test('par identifiant : invitation_id seul, jamais de jeton', () async {
      transport.reponse = const <String, dynamic>{
        'ok': true,
        'already_accepted': false,
        'membership': <String, dynamic>{'role': 'member'},
        'station': <String, dynamic>{'name': 'CS Maurepas'},
      };

      final resultat = await depot.accepter(
        const EntreeInvitation.identifiant('  inv-1  '),
      );

      expect(
        transport.dernier.url.path,
        endsWith('/functions/v1/accept-invitation'),
      );
      expect(transport.corpsEnvoye, <String, dynamic>{
        'invitation_id': 'inv-1',
      });
      expect(transport.corpsEnvoye.containsKey('token'), isFalse);
      expect(resultat.caserne?.nom, 'CS Maurepas');
    });

    test('par jeton : le corps du ticket 006, inchangé', () async {
      transport.reponse = const <String, dynamic>{
        'ok': true,
        'already_accepted': false,
        'membership': <String, dynamic>{'role': 'member'},
      };

      await depot.accepter(const EntreeInvitation.jeton('a1b2c3'));

      expect(transport.corpsEnvoye, <String, dynamic>{'token': 'a1b2c3'});
      expect(transport.corpsEnvoye.containsKey('invitation_id'), isFalse);
    });

    test('une entrée vide ne part pas sur le réseau', () async {
      await expectLater(
        depot.accepter(const EntreeInvitation.identifiant('   ')),
        throwsA(
          isA<EchecAcceptation>().having(
            (EchecAcceptation e) => e.erreur,
            'erreur',
            ErreurAcceptation.jetonManquant,
          ),
        ),
      );
      expect(transport.appels, isEmpty);
    });
  });

  group('my_pending_invitations', () {
    test('appelée sans aucun argument', () async {
      transport.reponse = const <Map<String, dynamic>>[];

      final recues = await depot.mesInvitations();

      expect(
        transport.dernier.url.path,
        endsWith('/rest/v1/rpc/my_pending_invitations'),
      );
      // **Sans paramètre, et c'est la contrainte principale** : l'adresse vient
      // du jeton de la session. Une fonction qui accepterait une adresse serait
      // un oracle d'énumération.
      expect(
        jsonDecode(transport.dernier.body),
        anyOf(isNull, equals(<String, dynamic>{})),
      );
      expect(transport.dernier.url.queryParameters, isEmpty);
      expect(recues, isEmpty);
    });

    test('lit les cinq champs, et ignore une ligne inexploitable', () async {
      transport.reponse = const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'inv-1',
          'station_name': 'CS Maurepas',
          'invited_by_name': 'Marc Dubois',
          'expires_at': '2026-10-05T12:00:00+02:00',
          'status': 'pending',
        },
        // Sans nom de caserne, la ligne ne dit rien : elle est ignorée, et ne
        // fait pas basculer l'écran entier sur un échec.
        <String, dynamic>{
          'id': 'inv-9',
          'station_name': '',
          'expires_at': '2026-10-06T12:00:00+02:00',
          'status': 'pending',
        },
      ];

      final recues = await depot.mesInvitations();

      expect(recues.length, 1);
      expect(recues.single.id, 'inv-1');
      expect(recues.single.caserne, 'CS Maurepas');
      expect(recues.single.inviteur, 'Marc Dubois');
      expect(recues.single.expiree, isFalse);
      expect(recues.single.echeance.toUtc().day, 5);
    });
  });

  group('InvitationRecue', () {
    test('c\'est le serveur qui tranche l\'expiration, pas l\'horloge', () {
      // Une échéance passée **avec** `status: pending` reste en attente : la
      // frontière est celle du serveur, et l'horloge d'un téléphone de caserne
      // prêté dérive.
      final lues = InvitationRecue.depuisListe(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'inv-1',
          'station_name': 'CS Maurepas',
          'expires_at': '2020-01-01T12:00:00+01:00',
          'status': 'pending',
        },
      ]);

      expect(lues.single.expiree, isFalse);
    });

    test('un nom d\'invitant absent n\'est jamais remplacé', () {
      final lues = InvitationRecue.depuisListe(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'inv-1',
          'station_name': 'CS Maurepas',
          'invited_by_name': null,
          'expires_at': '2026-10-05T12:00:00+02:00',
          'status': 'pending',
        },
      ]);

      expect(lues.single.inviteur, isNull);
    });

    test('les valables d\'abord, la plus proche en tête, les expirées en '
        'dernier', () {
      final lues = InvitationRecue.depuisListe(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'loin',
          'station_name': 'CS Trappes',
          'expires_at': '2026-10-20T12:00:00+02:00',
          'status': 'pending',
        },
        <String, dynamic>{
          'id': 'expiree',
          'station_name': 'CS Rambouillet',
          'expires_at': '2026-08-01T12:00:00+02:00',
          'status': 'expired',
        },
        <String, dynamic>{
          'id': 'proche',
          'station_name': 'CS Maurepas',
          'expires_at': '2026-10-05T12:00:00+02:00',
          'status': 'pending',
        },
      ]);

      expect(lues.map((InvitationRecue i) => i.id), <String>[
        'proche',
        'loin',
        'expiree',
      ]);
    });

    test('un statut inconnu n\'est pas un statut deviné', () {
      final lues = InvitationRecue.depuisListe(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'inv-1',
          'station_name': 'CS Maurepas',
          'expires_at': '2026-10-05T12:00:00+02:00',
          'status': 'revoked',
        },
      ]);

      expect(lues, isEmpty);
    });
  });
}
