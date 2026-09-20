import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/widgets/loading_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('LoadingSkeleton — rendu', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name} : les trois ossatures se rendent', (
        tester,
      ) async {
        await monter(
          tester,
          const SingleChildScrollView(
            child: Column(
              children: <Widget>[
                LoadingSkeleton(child: SkeletonLigne(largeur: 200)),
                LoadingSkeleton(child: SkeletonBloc()),
                LoadingSkeleton(child: SkeletonGrilleMois(jours: 14)),
              ],
            ),
          ),
          brightness: brightness,
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(LoadingSkeleton), findsNWidgets(3));
        expect(find.byType(SkeletonLigne), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('la grille du mois produit une case par jour', (tester) async {
      await monter(
        tester,
        const SizedBox(
          height: 600,
          child: LoadingSkeleton(child: SkeletonGrilleMois(jours: 7)),
        ),
      );

      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('aucune roue de chargement au milieu de l\'écran', (
      tester,
    ) async {
      await monter(tester, const LoadingSkeleton(child: SkeletonBloc()));

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('LoadingSkeleton — mouvement', () {
    testWidgets('balaie par défaut', (tester) async {
      await monter(tester, const LoadingSkeleton(child: SkeletonBloc()));

      expect(find.byType(ShaderMask), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      // La boucle tourne : on la coupe pour que le test se termine.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('sous Reduce Motion, l\'aplat est statique', (tester) async {
      await monter(
        tester,
        const LoadingSkeleton(child: SkeletonBloc()),
        animationsDesactivees: true,
      );

      expect(find.byType(ShaderMask), findsNothing);
      // pumpAndSettle rendrait la main en échec si le balayage tournait.
      await tester.pumpAndSettle();
    });
  });

  group('LoadingSkeleton — accessibilité', () {
    testWidgets('annonce que le contenu charge et exclut le focus', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        const LoadingSkeleton(child: SkeletonBloc()),
        animationsDesactivees: true,
      );

      final noeud = tester.getSemantics(find.byType(LoadingSkeleton));
      expect(noeud.label, AppStrings.chargementSemantique);
      expect(noeud.flagsCollection.isLiveRegion, isTrue);
      expect(find.byType(ExcludeFocus), findsOneWidget);

      handle.dispose();
    });
  });
}
