import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/router/destination_initiale.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/demarrage/presentation/demarrage_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_superadmin.dart';

/// Une destination gardée que la garde de navigation **refuse**.
///
/// Le piège, vu dans Chrome sur `/superadmin` ouvert à froid par un compte
/// ordinaire : la session se restaure, `DestinationInitiale` rejoue l'adresse
/// demandée, la garde la refuse et renvoie à l'accueil, la reprise l'y ramène…
/// jusqu'à la limite de redirections de `go_router`, qui laisse alors
/// l'application sur l'écran refusé — exactement ce que la garde voulait
/// éviter.
///
/// Le même piège attendait `/admin/membres` ouvert à froid par un simple
/// membre : ce n'est pas un défaut du ticket 031, c'est un défaut que le
/// ticket 031 a fait apparaître.
void main() {
  group('Une destination refusée ne boucle pas', () {
    testWidgets('/superadmin ouvert à froid par un compte ordinaire', (
      tester,
    ) async {
      final faux = await monterApp(
        tester,
        sessionEnAttente: true,
        appartenances: const <Appartenance>[appartenanceMembre],
        superAdmin: FauxSuperAdminRepository(autorise: false),
        stabiliser: false,
      );
      expect(find.byType(DemarrageScreen), findsOneWidget);

      await ouvrirRoute(tester, AppRoutes.superAdmin, stabiliser: false);
      expect(emplacementCourant(tester), AppRoutes.demarrage);

      faux.auth.ouvrirSession(sessionMembre);
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), AppRoutes.accueil);
    });

    testWidgets('/admin/membres ouvert à froid par un simple membre', (
      tester,
    ) async {
      final faux = await monterApp(
        tester,
        sessionEnAttente: true,
        appartenances: const <Appartenance>[appartenanceMembre],
        stabiliser: false,
      );

      await ouvrirRoute(tester, AppRoutes.membres, stabiliser: false);
      expect(emplacementCourant(tester), AppRoutes.demarrage);

      faux.auth.ouvrirSession(sessionMembre);
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), AppRoutes.accueil);
    });

    // Le correctif ne doit pas coûter les liens profonds qui, eux, sont
    // légitimes (ticket 039) : la reprise continue de fonctionner.
    testWidgets('une destination acceptée est toujours reprise', (
      tester,
    ) async {
      final faux = await monterApp(
        tester,
        sessionEnAttente: true,
        appartenances: const <Appartenance>[appartenanceAdmin],
        superAdmin: FauxSuperAdminRepository(),
        stabiliser: false,
      );

      await ouvrirRoute(tester, AppRoutes.superAdmin, stabiliser: false);
      faux.auth.ouvrirSession(sessionMembre);
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), AppRoutes.superAdmin);
    });
  });

  group('DestinationInitiale', () {
    // La reprise **consomme** la destination, qu'on la rejoue ou non : c'est
    // ce qui garantit qu'une destination refusée ne revient pas au tour
    // suivant.
    test('une destination n\'est reprise qu\'une fois', () {
      final destination = DestinationInitiale()..memoriser('/admin/membres');

      expect(destination.reprendre('/'), '/admin/membres');
      expect(destination.reprendre('/'), isNull);
    });

    test('y être déjà rend la reprise inutile', () {
      final destination = DestinationInitiale()..memoriser('/admin/membres');

      expect(destination.reprendre('/admin/membres'), isNull);
    });
  });
}
