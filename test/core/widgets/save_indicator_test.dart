import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/save_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('SaveIndicator — rendu', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name} : les cinq états se rendent', (
        tester,
      ) async {
        await monter(
          tester,
          Column(
            children: <Widget>[
              const SaveIndicator(etat: SyncEtat.repos),
              const SaveIndicator(etat: SyncEtat.enregistre),
              const SaveIndicator(etat: SyncEtat.horsLigne),
              SaveIndicator(etat: SyncEtat.echec, onReessayer: () {}),
            ],
          ),
          brightness: brightness,
          animationsDesactivees: true,
        );

        expect(find.byType(SaveIndicator), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('chaque état porte son icône propre', (tester) async {
      await monter(
        tester,
        Column(
          children: <Widget>[
            const SaveIndicator(etat: SyncEtat.enregistrement),
            const SaveIndicator(etat: SyncEtat.enregistre),
            const SaveIndicator(etat: SyncEtat.horsLigne),
            SaveIndicator(etat: SyncEtat.echec, onReessayer: () {}),
          ],
        ),
        animationsDesactivees: true,
      );

      expect(find.byIcon(Icons.sync), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('l\'échec nomme le problème et propose « Réessayer »', (
      tester,
    ) async {
      var appels = 0;
      await monter(
        tester,
        SaveIndicator(etat: SyncEtat.echec, onReessayer: () => appels++),
      );

      expect(find.text(AppStrings.saveEchecDetail), findsOneWidget);
      await tester.tap(find.text(AppStrings.actionReessayer));
      expect(appels, 1);
    });

    testWidgets('un échec sans sortie est une erreur de programmation', (
      tester,
    ) async {
      await monter(tester, const SaveIndicator(etat: SyncEtat.echec));

      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('la version compacte garde le libellé en info-bulle', (
      tester,
    ) async {
      await monter(
        tester,
        const SaveIndicator(etat: SyncEtat.enregistre, compact: true),
      );

      expect(find.text(AppStrings.saveTermine), findsNothing);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        AppStrings.saveTermine,
      );
    });
  });

  group('SaveIndicator — mouvement', () {
    testWidgets('l\'icône tourne pendant l\'enregistrement', (tester) async {
      await monter(tester, const SaveIndicator(etat: SyncEtat.enregistrement));

      expect(
        find.descendant(
          of: find.byType(SaveIndicator),
          matching: find.byType(RotationTransition),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('sous Reduce Motion, l\'icône reste fixe', (tester) async {
      await monter(
        tester,
        const SaveIndicator(etat: SyncEtat.enregistrement),
        animationsDesactivees: true,
      );

      expect(
        find.descendant(
          of: find.byType(SaveIndicator),
          matching: find.byType(RotationTransition),
        ),
        findsNothing,
      );
      expect(find.text(AppStrings.saveEnCours), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('SaveIndicator — accessibilité', () {
    testWidgets('l\'échec et le hors-ligne sont annoncés', (tester) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        SaveIndicator(etat: SyncEtat.echec, onReessayer: () {}),
      );

      expect(
        tester
            .getSemantics(find.byType(SaveIndicator))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );

      handle.dispose();
    });

    testWidgets('« Enregistré » n\'interrompt pas la lecture', (tester) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        const SaveIndicator(etat: SyncEtat.enregistre),
        animationsDesactivees: true,
      );

      expect(
        tester
            .getSemantics(find.byType(SaveIndicator))
            .flagsCollection
            .isLiveRegion,
        isFalse,
      );

      handle.dispose();
    });
  });
}
