import 'package:astreinte_sp/core/plateforme/contexte_plateforme.dart';
import 'package:astreinte_sp/features/notifications/domain/etat_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

const String _safariIphone =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const String _chromeAndroid =
    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like '
    'Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

final ContextePlateforme _iphoneSafari = ContextePlateforme.depuisAgent(
  userAgent: _safariIphone,
);
final ContextePlateforme _iphoneInstalle = ContextePlateforme.depuisAgent(
  userAgent: _safariIphone,
  autonomeIos: true,
);
final ContextePlateforme _android = ContextePlateforme.depuisAgent(
  userAgent: _chromeAndroid,
);

void main() {
  group('État des notifications', () {
    test('sans configuration Firebase, rien n\'est proposé', () {
      expect(
        deciderEtatNotifications(
          configure: false,
          supporte: true,
          plateforme: _android,
          permission: PermissionPush.accordee,
        ),
        EtatNotifications.nonConfigure,
      );
    });

    test('hors du web, c\'est le ticket 036', () {
      expect(
        deciderEtatNotifications(
          configure: true,
          supporte: true,
          plateforme: ContextePlateforme.natif,
          permission: PermissionPush.aDemander,
        ),
        EtatNotifications.horsWeb,
      );
    });

    test(
      'sur iPhone hors écran d\'accueil, on demande l\'installation, pas '
      'l\'autorisation',
      () {
        final etat = deciderEtatNotifications(
          configure: true,
          // Le navigateur répond « je ne sais pas faire » : c'est exact, et
          // c'est la mauvaise phrase à dire.
          supporte: false,
          plateforme: _iphoneSafari,
          permission: PermissionPush.aDemander,
        );

        expect(etat, EtatNotifications.installationRequise);
        expect(etat.peutDemander, isFalse);
      },
    );

    test('la même application installée peut, elle, demander', () {
      expect(
        deciderEtatNotifications(
          configure: true,
          supporte: true,
          plateforme: _iphoneInstalle,
          permission: PermissionPush.aDemander,
        ),
        EtatNotifications.aDemander,
      );
    });

    test('un navigateur qui ne sait pas faire le dit', () {
      expect(
        deciderEtatNotifications(
          configure: true,
          supporte: false,
          plateforme: _android,
          permission: PermissionPush.aDemander,
        ),
        EtatNotifications.nonSupporte,
      );
    });

    test('un refus ne redevient jamais une demande', () {
      final etat = deciderEtatNotifications(
        configure: true,
        supporte: true,
        plateforme: _android,
        permission: PermissionPush.refusee,
      );

      expect(etat, EtatNotifications.refusee);
      expect(etat.peutDemander, isFalse);
      expect(etat.estActive, isFalse);
    });

    test('autorisation accordée : les notifications arrivent', () {
      final etat = deciderEtatNotifications(
        configure: true,
        supporte: true,
        plateforme: _android,
        permission: PermissionPush.accordee,
      );

      expect(etat, EtatNotifications.active);
      expect(etat.estActive, isTrue);
    });
  });
}
