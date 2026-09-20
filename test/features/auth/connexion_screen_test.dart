import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/features/auth/domain/auth_erreur.dart';
import 'package:astreinte_sp/features/auth/presentation/code_screen.dart';
import 'package:astreinte_sp/features/auth/presentation/connexion_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';

void main() {
  group('ConnexionScreen', () {
    testWidgets('est l\'écran d\'un visiteur non connecté', (tester) async {
      await monterApp(tester);

      expect(find.byType(ConnexionScreen), findsOneWidget);
      expect(find.text(AppStrings.connexionTitre), findsOneWidget);
      expect(find.text(AppStrings.connexionEmailLabel), findsOneWidget);
      expect(find.text(AppStrings.connexionEnvoyer), findsOneWidget);
    });

    testWidgets('le bouton principal respecte le plancher tactile', (
      tester,
    ) async {
      await monterApp(tester);

      final bouton = find.widgetWithText(FilledButton, AppStrings.connexionEnvoyer);
      expect(tester.getSize(bouton).height, greaterThanOrEqualTo(44));
    });

    testWidgets('une adresse incomplète est refusée sans appel réseau', (
      tester,
    ) async {
      final faux = await monterApp(tester);

      await tester.enterText(find.byType(TextField), 'membre1');
      await tester.tap(find.text(AppStrings.connexionEnvoyer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.authEmailInvalide), findsOneWidget);
      expect(faux.auth.emailsAppeles, isEmpty);
      expect(find.byType(ConnexionScreen), findsOneWidget);
    });

    testWidgets('l\'erreur disparaît dès que la saisie est corrigée', (
      tester,
    ) async {
      await monterApp(tester);

      await tester.enterText(find.byType(TextField), 'membre1');
      await tester.tap(find.text(AppStrings.connexionEnvoyer));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.authEmailInvalide), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'membre1@caserne-a.test');
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.authEmailInvalide), findsNothing);
    });

    testWidgets('une adresse valide envoie le code et mène à la saisie', (
      tester,
    ) async {
      final faux = await monterApp(tester);

      await tester.enterText(find.byType(TextField), 'Membre1@Caserne-A.test ');
      await tester.tap(find.text(AppStrings.connexionEnvoyer));
      await tester.pumpAndSettle();

      // L'adresse part normalisée : le clavier d'un téléphone met souvent une
      // majuscule au premier caractère.
      expect(faux.auth.emailsAppeles, <String>['membre1@caserne-a.test']);
      expect(find.byType(CodeScreen), findsOneWidget);

      await demonter(tester);
    });

    testWidgets('une adresse sans compte reçoit la marche à suivre', (
      tester,
    ) async {
      await monterApp(tester, erreurEnvoi: AuthErreur.compteInconnu);

      await tester.enterText(find.byType(TextField), 'inconnu@caserne-a.test');
      await tester.tap(find.text(AppStrings.connexionEnvoyer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.authCompteInconnu), findsOneWidget);
      expect(find.byType(ConnexionScreen), findsOneWidget);
    });

    testWidgets('sans réseau, une bannière propose de réessayer', (
      tester,
    ) async {
      await monterApp(tester, erreurEnvoi: AuthErreur.reseau);

      await tester.enterText(find.byType(TextField), 'membre1@caserne-a.test');
      await tester.tap(find.text(AppStrings.connexionEnvoyer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.erreurReseauTexte), findsOneWidget);
      expect(find.text(AppStrings.actionReessayer), findsOneWidget);
    });

    testWidgets('trop d\'envois : le message dit quoi faire', (tester) async {
      await monterApp(tester, erreurEnvoi: AuthErreur.tropDeTentatives);

      await tester.enterText(find.byType(TextField), 'membre1@caserne-a.test');
      await tester.tap(find.text(AppStrings.connexionEnvoyer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.authTropDeTentatives), findsOneWidget);
    });
  });
}
