import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/auth_erreur.dart';
import 'package:astreinte_sp/features/accueil/presentation/accueil_screen.dart';
import 'package:astreinte_sp/features/auth/presentation/code_screen.dart';
import 'package:astreinte_sp/features/auth/presentation/connexion_screen.dart';
import 'package:astreinte_sp/features/auth/presentation/controllers/code_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/promesse_envoi.dart';

/// Va jusqu'à l'écran du code en passant par la saisie de l'adresse, comme un
/// utilisateur.
Future<AppMontee> allerAuCode(
  WidgetTester tester, {
  AuthErreur? erreurVerification,
  AuthErreur? erreurEnvoi,
  List<Appartenance> appartenances = const <Appartenance>[appartenanceMembre],
}) async {
  final faux = await monterApp(
    tester,
    appartenances: appartenances,
    erreurVerification: erreurVerification,
  );

  await tester.enterText(find.byType(TextField), 'membre1@caserne-a.test');
  await tester.tap(find.text(AppStrings.connexionEnvoyer));
  await tester.pumpAndSettle();
  expect(find.byType(CodeScreen), findsOneWidget);

  faux.auth.erreurEnvoi = erreurEnvoi;
  return faux;
}

void main() {
  group('CodeScreen', () {
    testWidgets('rappelle l\'adresse, le lien et le compte à rebours', (
      tester,
    ) async {
      await allerAuCode(tester);

      expect(
        find.text(AppStrings.codeIntro('membre1@caserne-a.test')),
        findsOneWidget,
      );
      expect(find.text(AppStrings.codeLabel), findsOneWidget);
      expect(find.text(AppStrings.codeLienAlternative), findsOneWidget);
      expect(
        find.text(AppStrings.codeRenvoiDans(delaiRenvoiSecondes)),
        findsOneWidget,
      );

      await demonter(tester);
    });

    testWidgets('un code complet ouvre la session et mène à l\'accueil', (
      tester,
    ) async {
      final faux = await allerAuCode(tester);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();

      expect(faux.auth.codesAppeles, <String>['123456']);
      expect(find.byType(AccueilScreen), findsOneWidget);

      await demonter(tester);
    });

    testWidgets('un code incorrect nomme le problème et la sortie', (
      tester,
    ) async {
      await allerAuCode(tester, erreurVerification: AuthErreur.codeInvalide);

      await tester.enterText(find.byType(TextField), '000000');
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.authCodeInvalide), findsOneWidget);
      expect(find.byType(CodeScreen), findsOneWidget);

      await demonter(tester);
    });

    testWidgets('un code périmé le dit et renvoie vers un nouveau code', (
      tester,
    ) async {
      await allerAuCode(tester, erreurVerification: AuthErreur.codeExpire);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.authCodeExpire), findsOneWidget);

      await demonter(tester);
    });

    testWidgets('trop de tentatives passe par une bannière', (tester) async {
      await allerAuCode(
        tester,
        erreurVerification: AuthErreur.tropDeTentatives,
      );

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.authTropDeTentatives), findsOneWidget);

      await demonter(tester);
    });

    testWidgets('sans réseau, la vérification le dit', (tester) async {
      await allerAuCode(tester, erreurVerification: AuthErreur.reseau);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.erreurReseauTexte), findsOneWidget);

      await demonter(tester);
    });

    testWidgets('le renvoi n\'est possible qu\'après le compte à rebours', (
      tester,
    ) async {
      final faux = await allerAuCode(tester);
      expect(faux.auth.emailsAppeles, hasLength(1));

      await tester.tap(find.text(AppStrings.codeRenvoyer));
      await tester.pump();
      expect(faux.auth.emailsAppeles, hasLength(1));

      await tester.pump(const Duration(seconds: delaiRenvoiSecondes));
      await tester.pumpAndSettle();
      // Le compte à rebours a disparu : un bouton actif n'a pas de raison à
      // donner.
      expect(find.textContaining('Nouveau code possible'), findsNothing);

      await tester.tap(find.text(AppStrings.codeRenvoyer));
      await tester.pumpAndSettle();
      expect(faux.auth.emailsAppeles, hasLength(2));
      expect(find.text(AppStrings.codeRenvoye), findsOneWidget);
      // « Demandé », pas « envoyé » : rien ne dit au client que le courriel
      // est sorti (ticket 055).
      aucunEnvoiPromis(tester);

      await demonter(tester);
    });

    testWidgets(
      'la route du code sans adresse renvoie à la connexion, elle ne montre '
      'pas un écran vide',
      (tester) async {
        await monterApp(tester);
        final routeur = ProviderScope.containerOf(
          tester.element(find.byType(ConnexionScreen)),
        ).read(appRouterProvider);

        routeur.go(AppRoutes.code);
        await tester.pumpAndSettle();
        expect(find.byType(ConnexionScreen), findsOneWidget);
        expect(find.byType(CodeScreen), findsNothing);

        // Une adresse présente mais tronquée ne vaut pas mieux qu'une absence.
        routeur.go('${AppRoutes.code}?${AppRoutes.parametreEmail}=membre1');
        await tester.pumpAndSettle();
        expect(find.byType(ConnexionScreen), findsOneWidget);
        expect(find.byType(CodeScreen), findsNothing);

        routeur.go(
          '${AppRoutes.code}?${AppRoutes.parametreEmail}='
          'membre1@caserne-a.test',
        );
        await tester.pumpAndSettle();
        expect(find.byType(CodeScreen), findsOneWidget);

        await demonter(tester);
      },
    );

    testWidgets('« Changer d\'adresse » revient à l\'étape précédente', (
      tester,
    ) async {
      await allerAuCode(tester);

      await tester.tap(find.text(AppStrings.codeChangerEmail));
      await tester.pumpAndSettle();

      expect(find.byType(ConnexionScreen), findsOneWidget);

      await demonter(tester);
    });
  });
}
