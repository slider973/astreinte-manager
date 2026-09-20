import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/auth_erreur.dart';
import 'package:astreinte_sp/features/accueil/presentation/accueil_screen.dart';
import 'package:astreinte_sp/features/auth/presentation/aucune_caserne_screen.dart';
import 'package:astreinte_sp/features/auth/presentation/connexion_screen.dart';
import 'package:astreinte_sp/features/demarrage/presentation/demarrage_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';

const Appartenance _adminCaserneA = Appartenance(
  id: 'm-3',
  stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Saint-Martin',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
);

/// Ouvre l'onglet « Profil », qui porte l'identité et la sortie depuis que
/// l'onglet 0 est devenu l'écran « Mon mois » (ticket 011).
Future<void> ouvrirProfil(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.navProfil));
  await tester.pumpAndSettle();
}

void main() {
  group('AccueilScreen', () {
    testWidgets('une session existante mène directement à l\'accueil', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
      );

      expect(find.byType(AccueilScreen), findsOneWidget);
      expect(find.byType(ConnexionScreen), findsNothing);
    });

    testWidgets('affiche le nom de la caserne et le rôle', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
      );
      await ouvrirProfil(tester);

      expect(find.text('CIS Saint-Martin'), findsOneWidget);
      expect(find.text(AppStrings.roleMembre), findsOneWidget);
      expect(find.text(AppStrings.accueilCaserneLabel), findsOneWidget);
    });

    testWidgets('un admin voit la destination Admin, pas un membre', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[_adminCaserneA],
      );
      expect(find.text(AppStrings.navAdmin), findsOneWidget);

      await ouvrirProfil(tester);
      expect(find.text(AppStrings.roleAdmin), findsOneWidget);

      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
      );
      expect(find.text(AppStrings.navAdmin), findsNothing);
    });

    testWidgets('la déconnexion ramène à l\'écran de connexion', (
      tester,
    ) async {
      final faux = await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
      );
      await ouvrirProfil(tester);

      await tester.tap(find.text(AppStrings.seDeconnecter));
      await tester.pumpAndSettle();

      expect(faux.auth.deconnexions, 1);
      expect(find.byType(ConnexionScreen), findsOneWidget);
    });

    testWidgets('une déconnexion qui échoue le dit, au lieu de faire croire '
        'que la session est fermée', (tester) async {
      final faux = await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
      );
      await ouvrirProfil(tester);
      faux.auth.erreurDeconnexion = AuthErreur.reseau;

      await tester.tap(find.text(AppStrings.seDeconnecter));
      await tester.pumpAndSettle();

      expect(find.text(AuthErreur.reseau.message), findsOneWidget);
      expect(find.byType(AccueilScreen), findsOneWidget);
    });
  });

  group('AucuneCaserneScreen', () {
    testWidgets('un compte sans appartenance voit la marche à suivre', (
      tester,
    ) async {
      await monterApp(tester, session: sessionMembre);

      expect(find.byType(AucuneCaserneScreen), findsOneWidget);
      expect(find.text(AppStrings.aucuneCaserneTitre), findsOneWidget);
      expect(find.text(AppStrings.aucuneCaserneTexte), findsOneWidget);
    });

    testWidgets('un compte désactivé voit son état, pas « aucune caserne »', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceDesactivee],
      );

      expect(find.text(AppStrings.caserneDesactiveeTitre), findsOneWidget);
      expect(
        find.text(AppStrings.caserneDesactiveeTexte('CIS Saint-Martin')),
        findsOneWidget,
      );
    });

    testWidgets('la déconnexion y est possible', (tester) async {
      final faux = await monterApp(tester, session: sessionMembre);

      await tester.tap(find.text(AppStrings.seDeconnecter));
      await tester.pumpAndSettle();

      expect(faux.auth.deconnexions, 1);
      expect(find.byType(ConnexionScreen), findsOneWidget);
    });
  });

  group('DemarrageScreen', () {
    testWidgets('une lecture d\'appartenances en échec n\'annonce pas « aucune '
        'caserne »', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        erreurAppartenances: AuthErreur.reseau,
      );

      expect(find.byType(DemarrageScreen), findsOneWidget);
      expect(find.byType(AucuneCaserneScreen), findsNothing);
      expect(find.text(AppStrings.erreurReseauTitre), findsOneWidget);
      expect(find.text(AppStrings.actionReessayer), findsOneWidget);
    });
  });
}
