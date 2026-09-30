import 'package:astreinte_sp/core/env.dart';
import 'package:astreinte_sp/features/notifications/data/jeton_local.dart';
import 'package:astreinte_sp/features/notifications/data/messagerie_push.dart';
import 'package:astreinte_sp/features/notifications/domain/etat_notifications.dart';
import 'package:astreinte_sp/features/notifications/domain/notifications_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_push.dart';

const Env _env = Env(
  supabaseUrl: 'https://x.supabase.co',
  supabaseAnonKey: 'anon',
  appEnv: Env.prodEnv,
  firebaseProjectId: 'astreinte-sp',
  firebaseApiKey: 'AIza-cle/publique',
  firebaseAppId: '1:123:web:abc',
  firebaseMessagingSenderId: '123',
  firebaseVapidKey: 'BP-vapid',
);

void main() {
  // Ticket 074 : à la racine, le worker partageait la portée `/` avec celui de
  // Flutter et restait en attente derrière lui. Rangé dans `push/`, il prend
  // cette portée-là par défaut.
  group('Chemin du service worker des push', () {
    final chemin = cheminServiceWorkerPush(_env);
    final uri = Uri.parse(chemin);

    test('vit dans le dossier push/, relatif au base href', () {
      expect(chemin, startsWith('push/firebase-messaging-sw.js?'));
      expect(
        chemin,
        isNot(startsWith('/')),
        reason:
            'un / initial viserait la racine du domaine, pas celle de la '
            'PWA servie sous un sous-chemin',
      );
      expect(uri.path, 'push/firebase-messaging-sw.js');
    });

    test('porte les quatre paramètres, et eux seuls', () {
      expect(uri.queryParameters, <String, String>{
        'apiKey': 'AIza-cle/publique',
        'appId': '1:123:web:abc',
        'messagingSenderId': '123',
        'projectId': 'astreinte-sp',
      });
      expect(
        uri.queryParameters.containsKey('vapidKey'),
        isFalse,
        reason: 'la clé VAPID sert au jeton, pas au worker',
      );
    });
  });

  // Ticket 074 : `deleteToken()` sans `getToken()` préalable fait enregistrer
  // au SDK un worker sans configuration. Le SDK n'est donc appelé que s'il a
  // quelque chose à supprimer ; le désabonnement local, lui, part toujours.
  group('Désenregistrement : quand appeler le SDK', () {
    Future<FauxMessageriePush> desenregistrer({
      required PermissionPush permission,
      String? jetonConnu,
    }) async {
      final messagerie = FauxMessageriePush(etatPermission: permission);
      final conteneur = ProviderContainer(
        overrides: [
          messageriePushProvider.overrideWithValue(messagerie),
          pushTokensRepositoryProvider.overrideWithValue(
            FauxPushTokensRepository(),
          ),
          jetonLocalProvider.overrideWithValue(JetonLocalMemoire(jetonConnu)),
        ],
      );
      addTearDown(conteneur.dispose);

      await conteneur.read(jetonPushProvider.notifier).desenregistrer();
      return messagerie;
    }

    test('sans autorisation ni jeton : pas d\'appel au SDK', () async {
      final messagerie = await desenregistrer(
        permission: PermissionPush.aDemander,
      );

      expect(messagerie.jetonsOublies, 0);
      expect(messagerie.desabonnements, 1, reason: 'le local part toujours');
    });

    test(
      'autorisation accordée mais aucun jeton connu : pas d\'appel au SDK',
      () async {
        final messagerie = await desenregistrer(
          permission: PermissionPush.accordee,
        );

        expect(messagerie.jetonsOublies, 0);
        expect(messagerie.desabonnements, 1);
      },
    );

    test('un jeton connu sans autorisation : pas d\'appel au SDK', () async {
      final messagerie = await desenregistrer(
        permission: PermissionPush.refusee,
        jetonConnu: 'jeton-ancien',
      );

      expect(messagerie.jetonsOublies, 0);
      expect(messagerie.desabonnements, 1);
    });

    test('autorisation accordée et jeton connu : le SDK est appelé', () async {
      final messagerie = await desenregistrer(
        permission: PermissionPush.accordee,
        jetonConnu: 'jeton-de-test',
      );

      expect(messagerie.jetonsOublies, 1);
      expect(messagerie.desabonnements, 1);
    });
  });
}
