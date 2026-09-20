import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/widgets/empty_state.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('EmptyState — rendu', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name} : vide sans action', (tester) async {
        await monter(
          tester,
          const EmptyState(
            titre: AppStrings.videPropositionsTitre,
            texte: AppStrings.videPropositionsTexte,
          ),
          brightness: brightness,
        );

        expect(find.text(AppStrings.videPropositionsTitre), findsOneWidget);
        expect(find.text(AppStrings.videPropositionsTexte), findsOneWidget);
        expect(find.byType(PrimaryButton), findsNothing);
      });
    }

    testWidgets('vide avec action affiche le bouton', (tester) async {
      var appels = 0;
      await monter(
        tester,
        EmptyState(
          titre: AppStrings.videTitreGenerique,
          texte: AppStrings.videTexteGenerique,
          libelleAction: 'Saisir octobre',
          onAction: () => appels++,
        ),
      );

      expect(find.byType(PrimaryButton), findsOneWidget);
      await tester.tap(find.text('Saisir octobre'));
      expect(appels, 1);
    });

    testWidgets('erreur nomme le problème et propose « Réessayer »', (
      tester,
    ) async {
      await monter(tester, EmptyState.erreur(onAction: () {}));

      expect(find.text(AppStrings.erreurTitre), findsOneWidget);
      expect(find.text(AppStrings.erreurTexteGenerique), findsOneWidget);
      expect(find.text(AppStrings.actionReessayer), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('hors ligne nomme la connexion et propose « Réessayer »', (
      tester,
    ) async {
      await monter(tester, EmptyState.horsLigne(onAction: () {}));

      expect(find.text(AppStrings.erreurReseauTitre), findsOneWidget);
      expect(find.text(AppStrings.erreurReseauTexte), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });

    testWidgets('aucun état vide n\'est muet', (tester) async {
      // Un titre et une explication sont exigés par le type : il n'existe pas
      // de constructeur qui produise un « Aucune donnée » nu.
      await monter(
        tester,
        const EmptyState(
          titre: AppStrings.videTitreGenerique,
          texte: AppStrings.videTexteGenerique,
        ),
      );

      expect(find.text(AppStrings.videTitreGenerique), findsOneWidget);
      expect(find.text(AppStrings.videTexteGenerique), findsOneWidget);
    });
  });

  group('EmptyState — accessibilité', () {
    testWidgets('l\'erreur est annoncée', (tester) async {
      final handle = tester.ensureSemantics();
      await monter(tester, EmptyState.erreur(onAction: () {}));

      expect(
        tester
            .getSemantics(find.byType(EmptyState))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );

      handle.dispose();
    });

    testWidgets('un état vide ordinaire n\'interrompt pas', (tester) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        const EmptyState(
          titre: AppStrings.videTitreGenerique,
          texte: AppStrings.videTexteGenerique,
        ),
      );

      expect(
        tester
            .getSemantics(find.byType(EmptyState))
            .flagsCollection
            .isLiveRegion,
        isFalse,
      );

      handle.dispose();
    });

    testWidgets('tient une échelle de texte de 2.0', (tester) async {
      await monter(
        tester,
        SingleChildScrollView(child: EmptyState.horsLigne(onAction: () {})),
        echelleTexte: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
