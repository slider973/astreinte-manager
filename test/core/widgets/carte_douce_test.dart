import 'package:astreinte_sp/core/theme/app_spacing.dart';
import 'package:astreinte_sp/core/theme/app_theme.dart';
import 'package:astreinte_sp/core/widgets/carte_douce.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// La forme de la carte, telle que `Material` la porte.
RoundedRectangleBorder _forme(WidgetTester tester) =>
    tester
            .widget<Material>(
              find.descendant(
                of: find.byType(CarteDouce),
                matching: find.byType(Material),
              ),
            )
            .shape!
        as RoundedRectangleBorder;

void main() {
  group('CarteDouce', () {
    for (final brightness in Brightness.values) {
      final scheme = brightness == Brightness.dark
          ? AppTheme.sombre.colorScheme
          : AppTheme.clair.colorScheme;

      testWidgets('${brightness.name} : papier, filet, rayon, aucune ombre', (
        tester,
      ) async {
        await monter(
          tester,
          const CarteDouce(child: Text('Octobre saisi')),
          brightness: brightness,
        );

        final materiau = tester.widget<Material>(
          find.descendant(
            of: find.byType(CarteDouce),
            matching: find.byType(Material),
          ),
        );
        expect(materiau.color, scheme.surface);
        expect(
          materiau.elevation,
          0,
          reason: 'La profondeur n\'est pas le matériau de ce système.',
        );
        expect(materiau.shadowColor, isNull);

        final forme = _forme(tester);
        expect(forme.borderRadius, AppRadius.carteRadius);
        expect(forme.side.color, scheme.outlineVariant);
        expect(forme.side.width, AppStroke.filet);
      });
    }

    testWidgets('en erreur : le filet passe à «error», 2 dp', (tester) async {
      await monter(
        tester,
        const CarteDouce(enErreur: true, child: Text('Trop d\'astreintes')),
      );

      final forme = _forme(tester);
      expect(forme.side.color, AppTheme.clair.colorScheme.error);
      expect(forme.side.width, AppStroke.etat);
    });

    testWidgets('actionnable : la carte entière répond, à la cible', (
      tester,
    ) async {
      var appuis = 0;
      await monter(
        tester,
        CarteDouce(
          onTap: () => appuis++,
          hauteurMin: AppTouch.cible,
          child: const Text('samedi 17 octobre'),
        ),
      );

      verifierCiblesTactiles(tester, find.byType(CarteDouce));
      await tester.tap(find.byType(CarteDouce));
      expect(appuis, 1);
    });

    testWidgets('inerte : aucun InkWell, rien à toucher', (tester) async {
      await monter(tester, const CarteDouce(child: Text('Rien à faire')));

      expect(
        find.descendant(
          of: find.byType(CarteDouce),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });

    testWidgets('nue : aucun rembourrage, l\'enfant décide', (tester) async {
      await monter(
        tester,
        const CarteDouce.nue(child: SizedBox(height: 40, width: 200)),
      );

      final padding = tester.widget<Padding>(
        find.descendant(
          of: find.byType(CarteDouce),
          matching: find.byType(Padding),
        ),
      );
      expect(padding.padding, EdgeInsets.zero);
    });

    testWidgets('le groupe de slivers porte la même carte', (tester) async {
      await monter(
        tester,
        CustomScrollView(
          slivers: <Widget>[
            CarteDouceSliver(
              slivers: <Widget>[
                SliverList.builder(
                  itemCount: 3,
                  itemBuilder: (context, index) =>
                      SizedBox(height: 48, child: Text('ligne $index')),
                ),
              ],
            ),
          ],
        ),
      );

      // Le papier derrière, le filet devant : deux décorations, jamais une.
      final decorations = tester
          .widgetList<DecoratedSliver>(find.byType(DecoratedSliver))
          .toList();
      expect(decorations, hasLength(2));

      final papier = decorations.first.decoration as BoxDecoration;
      expect(decorations.first.position, DecorationPosition.background);
      expect(papier.color, AppTheme.clair.colorScheme.surface);
      expect(papier.borderRadius, AppRadius.carteRadius);

      final trait = decorations.last.decoration as BoxDecoration;
      expect(decorations.last.position, DecorationPosition.foreground);
      expect(trait.color, isNull, reason: 'le filet ne repeint pas le papier');
      expect(
        trait.border!.top.color,
        AppTheme.clair.colorScheme.outlineVariant,
      );
      expect(trait.border!.top.width, AppStroke.filet);

      expect(find.text('ligne 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
