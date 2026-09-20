import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/theme/app_typography.dart';
import 'package:astreinte_sp/core/widgets/count_stat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('CountStat — rendu', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name} : les quatre cas se rendent', (
        tester,
      ) async {
        await monter(
          tester,
          const Column(
            children: <Widget>[
              CountStat(
                libelle: AppStrings.compteurJours,
                valeur: 2,
                plafond: 3,
              ),
              CountStat(libelle: AppStrings.compteurNuits, valeur: 0),
              CountStat(libelle: AppStrings.compteurWeekends, valeur: 1),
              CountStat(
                libelle: AppStrings.compteurJours,
                valeur: 11,
                plafond: 31,
                grand: true,
              ),
            ],
          ),
          brightness: brightness,
        );

        expect(find.byType(CountStat), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('valeur et plafond sont affichés séparément', (tester) async {
      await monter(
        tester,
        const CountStat(
          libelle: AppStrings.compteurJours,
          valeur: 2,
          plafond: 3,
        ),
      );

      expect(find.text(AppStrings.compteurJours), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text(' / '), findsOneWidget);
    });

    testWidgets('sans plafond, « illimité » est écrit en toutes lettres', (
      tester,
    ) async {
      await monter(
        tester,
        const CountStat(libelle: AppStrings.compteurNuits, valeur: 4),
      );

      expect(find.text(AppStrings.compteurIllimite), findsOneWidget);
      expect(find.text('∞'), findsNothing);
    });

    testWidgets('une valeur à zéro s\'affiche comme les autres', (
      tester,
    ) async {
      await monter(
        tester,
        const CountStat(
          libelle: AppStrings.compteurWeekends,
          valeur: 0,
          plafond: 2,
        ),
      );

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('le nombre est en chasse fixe avec chiffres tabulaires', (
      tester,
    ) async {
      await monter(
        tester,
        const CountStat(
          libelle: AppStrings.compteurJours,
          valeur: 11,
          plafond: 31,
        ),
      );

      final texte = tester.widget<Text>(find.text('11'));
      expect(texte.style?.fontFamily, AppFonts.nombre);
      expect(texte.style?.fontFeatures, AppTextStyles.chiffresTabulaires);
    });
  });

  group('CountStat — logique', () {
    test('atteint est vrai dès que la valeur touche le plafond', () {
      expect(
        const CountStat(libelle: 'Jours', valeur: 3, plafond: 3).atteint,
        isTrue,
      );
      expect(
        const CountStat(libelle: 'Jours', valeur: 2, plafond: 3).atteint,
        isFalse,
      );
      expect(const CountStat(libelle: 'Jours', valeur: 99).atteint, isFalse);
    });
  });

  group('CountStat — accessibilité', () {
    testWidgets('annonce le libellé et la valeur en une phrase', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        const CountStat(
          libelle: AppStrings.compteurJours,
          valeur: 2,
          plafond: 3,
        ),
      );

      final noeud = tester.getSemantics(find.byType(CountStat));
      expect(noeud.label, AppStrings.compteurJours);
      expect(noeud.value, AppStrings.compteurSurPlafond(2, 3));

      handle.dispose();
    });

    testWidgets('tient une échelle de texte de 2.0', (tester) async {
      await monter(
        tester,
        const CountStat(
          libelle: AppStrings.compteurWeekends,
          valeur: 11,
          plafond: 31,
          grand: true,
        ),
        echelleTexte: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
