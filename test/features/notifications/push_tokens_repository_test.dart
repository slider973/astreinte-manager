import 'dart:convert';

import 'package:astreinte_sp/features/notifications/data/push_tokens_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// **Le transport est remplacé, le dépôt reste le vrai** (ticket 057).
///
/// Ce qui se verrouille ici : le jeton s'enregistre par `register_push_token`,
/// jamais par un `upsert` direct sur `push_tokens`. Un `upsert` direct est
/// refusé par la RLS dès que la ligne du jeton est restée au nom de quelqu'un
/// d'autre — le téléphone de caserne prêté, déconnecté hors ligne.
class _FauxTransport {
  final List<http.Request> appels = <http.Request>[];

  late final SupabaseClient client = SupabaseClient(
    'https://caserne.exemple.test',
    'cle-anon-de-test',
    httpClient: MockClient(_repondre),
  );

  http.Request get dernier => appels.last;

  Future<http.Response> _repondre(http.Request requete) async {
    appels.add(requete);
    // Une fonction `returns void` : PostgREST rend `null`, une suppression
    // `return=minimal` ne rend rien.
    return http.Response(
      requete.method == 'DELETE' ? '' : 'null',
      requete.method == 'DELETE' ? 204 : 200,
      request: requete,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}

void main() {
  late _FauxTransport transport;
  late SupabasePushTokensRepository depot;

  setUp(() {
    transport = _FauxTransport();
    depot = SupabasePushTokensRepository(transport.client);
  });

  tearDown(() => transport.client.dispose());

  group('enregistrer', () {
    test('passe par rpc/register_push_token, jamais par la table', () async {
      await depot.enregistrer(
        token: 'jeton-T',
        plateforme: PlateformePush.web,
        libelleAppareil: '  Pixel 7 · Chrome  ',
      );

      expect(transport.appels, hasLength(1));
      final appel = transport.dernier;
      expect(appel.method, 'POST');
      expect(appel.url.path, endsWith('/rest/v1/rpc/register_push_token'));
      expect(
        transport.appels.where(
          (http.Request r) => r.url.pathSegments.last == 'push_tokens',
        ),
        isEmpty,
        reason: 'un upsert direct serait refusé sur un téléphone prêté',
      );
      expect(jsonDecode(appel.body), <String, dynamic>{
        'p_token': 'jeton-T',
        'p_platform': 'web',
        'p_device_label': 'Pixel 7 · Chrome',
      });
    });

    test(
      'aucun identifiant de membre ne part : la base lit la session',
      () async {
        await depot.enregistrer(
          token: 'jeton-T',
          plateforme: PlateformePush.web,
        );

        final corps =
            jsonDecode(transport.dernier.body) as Map<String, dynamic>;
        expect(corps.keys, <String>['p_token', 'p_platform', 'p_device_label']);
        expect(corps['p_device_label'], isNull);
      },
    );

    test('un libellé vide s\'écrit null, jamais la chaîne vide', () async {
      await depot.enregistrer(
        token: 'jeton-T',
        plateforme: PlateformePush.web,
        libelleAppareil: '   ',
      );

      final corps = jsonDecode(transport.dernier.body) as Map<String, dynamic>;
      expect(corps['p_device_label'], isNull);
    });

    test('le nom de la fonction est celui du contrat de l\'app iOS', () {
      expect(
        SupabasePushTokensRepository.fonctionEnregistrement,
        'register_push_token',
      );
    });
  });

  group('oublier', () {
    test('supprime la ligne du jeton, sous RLS', () async {
      await depot.oublier('jeton-T');

      final appel = transport.dernier;
      expect(appel.method, 'DELETE');
      expect(appel.url.pathSegments.last, 'push_tokens');
      expect(appel.url.queryParameters['token'], 'eq.jeton-T');
    });
  });
}
