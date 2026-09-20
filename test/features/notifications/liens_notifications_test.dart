import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_periodes.dart';

const Appartenance _admin = Appartenance(
  id: 'm-3',
  stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Saint-Martin',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
);

void main() {
  group('Ouverture depuis une notification', () {
    testWidgets('chaque destination de WORKFLOWS § 8 mène au bon écran', (
      tester,
    ) async {
      const attendu = <String, String>{
        '/proposals': '/?onglet=1',
        '/schedule/2026-10': '/?onglet=2',
        '/availability/2026-10': '/?onglet=0&mois=2026-10',
        '/admin/schedule/2026-10': '/admin/periodes',
      };

      for (final lien in attendu.entries) {
        await monterApp(
          tester,
          session: sessionMembre,
          appartenances: const <Appartenance>[_admin],
          periodes: FauxPeriodesRepository(),
        );

        await ouvrirRoute(tester, lien.key);

        expect(emplacementCourant(tester), lien.value, reason: lien.key);
        await demonter(tester);
      }
    });

    testWidgets(
      'un lien admin reçu par un membre ramène à l\'accueil, sans reproche',
      (tester) async {
        await monterApp(
          tester,
          session: sessionMembre,
          appartenances: const <Appartenance>[appartenanceMembre],
        );

        await ouvrirRoute(tester, '/admin/schedule/2026-10');

        expect(emplacementCourant(tester), '/');
        expect(find.textContaining('refus'), findsNothing);
        expect(find.textContaining('Accès'), findsNothing);
      },
    );

    testWidgets('un mois forgé ne se promène pas dans l\'URL', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
      );

      await ouvrirRoute(tester, '/availability/2026-99');

      expect(emplacementCourant(tester), '/');
    });

    testWidgets(
      'la destination survit au démarrage à froid, session à restaurer '
      '(ticket 039)',
      (tester) async {
        final faux = await monterApp(
          tester,
          appartenances: const <Appartenance>[appartenanceMembre],
        );

        // Le lien arrive alors que personne n'est encore connecté : c'est
        // exactement le chemin d'une notification touchée application fermée.
        await ouvrirRoute(tester, '/availability/2026-10');
        expect(emplacementCourant(tester), isNot('/availability/2026-10'));

        faux.auth.ouvrirSession(sessionMembre);
        await tester.pumpAndSettle();

        expect(emplacementCourant(tester), '/?onglet=0&mois=2026-10');
      },
    );

    testWidgets('sans lien profond, la connexion mène à l\'accueil', (
      tester,
    ) async {
      final faux = await monterApp(
        tester,
        appartenances: const <Appartenance>[appartenanceMembre],
      );

      faux.auth.ouvrirSession(sessionMembre);
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), '/');
    });
  });
}
