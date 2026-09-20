import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/router/destination_initiale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Destination initiale (ticket 039)', () {
    test('une destination demandée survit à la restauration de session', () {
      final destination = DestinationInitiale();

      expect(destination.memoriser('/availability/2026-10'), isTrue);
      expect(destination.reprendre(AppRoutes.accueil), '/availability/2026-10');
    });

    test('elle ne se reprend qu\'une fois', () {
      final destination = DestinationInitiale()
        ..memoriser('/proposals');

      expect(destination.reprendre(AppRoutes.accueil), '/proposals');
      expect(destination.reprendre(AppRoutes.accueil), isNull);
    });

    test('la première demandée gagne : les suivantes sont des conséquences', () {
      final destination = DestinationInitiale()..memoriser('/proposals');

      expect(destination.memoriser('/schedule/2026-10'), isFalse);
      expect(destination.reprendre(AppRoutes.accueil), '/proposals');
    });

    test('y être déjà rend la reprise inutile', () {
      final destination = DestinationInitiale()..memoriser('/proposals');

      expect(destination.reprendre('/proposals'), isNull);
    });

    test('les étapes traversées ne sont jamais des destinations', () {
      for (final etape in <String>[
        AppRoutes.demarrage,
        AppRoutes.connexion,
        '${AppRoutes.code}?email=x@y.fr',
        AppRoutes.configuration,
        AppRoutes.aucuneCaserne,
        AppRoutes.guide,
        AppRoutes.installation,
        AppRoutes.cheminInvitation('jeton'),
        AppRoutes.accueil,
      ]) {
        expect(
          DestinationInitiale().memoriser(etape),
          isFalse,
          reason: etape,
        );
      }
    });

    test('l\'accueil avec un onglet ou un mois, lui, est une destination', () {
      expect(
        DestinationInitiale().memoriser('/?onglet=0&mois=2026-10'),
        isTrue,
      );
    });

    test('oublier remet tout à zéro', () {
      final destination = DestinationInitiale()
        ..memoriser('/proposals')
        ..oublier();

      expect(destination.reprendre(AppRoutes.accueil), isNull);
    });
  });
}
