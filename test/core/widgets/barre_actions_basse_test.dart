import 'package:astreinte_sp/core/theme/app_spacing.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/theme/app_theme.dart';
import 'package:astreinte_sp/core/widgets/app_divider.dart';
import 'package:astreinte_sp/core/widgets/barre_actions_basse.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const Key _action = Key('action');

Widget get _barre => const BarreActionsBasse(
  child: PrimaryButton(key: _action, libelle: 'Envoyer', onPressed: _rien),
);

void _rien() {}

void main() {
  group('BarreActionsBasse', () {
    testWidgets('sur poste admin, elle se borne à la colonne du corps', (
      tester,
    ) async {
      await monter(tester, _barre, taille: const Size(1280, 900));

      final action = tester.getRect(find.byKey(_action));
      expect(action.width, AppSpacing.colonneMax);
      // Centrée comme le corps : autant de vide à gauche qu'à droite.
      expect(action.center.dx, 1280 / 2);
    });

    testWidgets('sur téléphone, elle prend la largeur moins les marges', (
      tester,
    ) async {
      await monter(tester, _barre);

      final action = tester.getRect(find.byKey(_action));
      expect(action.width, 390 - 2 * AppSpacing.pageCompact);
      expect(action.left, AppSpacing.pageCompact);
    });

    testWidgets('la marge de page suit la classe de fenêtre', (tester) async {
      // 700 points : la colonne n'est pas encore bornée, c'est la marge de
      // page qui décide, et elle passe à 24 dès `medium`.
      await monter(tester, _barre, taille: const Size(700, 900));

      final action = tester.getRect(find.byKey(_action));
      expect(action.left, AppSpacing.pageMedium);
      expect(action.width, 700 - 2 * AppSpacing.pageMedium);
    });

    for (final brightness in Brightness.values) {
      testWidgets(
        '${brightness.name} : un filet et une surface tonale séparent du '
        'contenu, sans ombre',
        (tester) async {
          await monter(tester, _barre, brightness: brightness);

          final statuts = brightness == Brightness.dark
              ? AppStatusColors.sombre
              : AppStatusColors.clair;
          final schema =
              (brightness == Brightness.dark ? AppTheme.sombre : AppTheme.clair)
                  .colorScheme;

          // Niveau 1 de `DESIGN.md § Elevation & Depth` : surface tonale
          // `surfaceContainerLow` et filet de 1 dp.
          final fond = tester.widget<ColoredBox>(
            find
                .descendant(
                  of: find.byType(BarreActionsBasse),
                  matching: find.byType(ColoredBox),
                )
                .first,
          );
          expect(fond.color, schema.surfaceContainerLow);

          final filet = tester.widget<Divider>(
            find.descendant(
              of: find.byType(AppDivider),
              matching: find.byType(Divider),
            ),
          );
          expect(filet.thickness, 1);
          expect(filet.color, statuts.filetDecoratif);

          // « La profondeur n'est pas le matériau de ce système » : aucune
          // ombre ne doit s'être glissée sous la barre.
          for (final element
              in find
                  .descendant(
                    of: find.byType(BarreActionsBasse),
                    matching: find.byType(DecoratedBox),
                  )
                  .evaluate()) {
            final decoration = (element.widget as DecoratedBox).decoration;
            if (decoration is BoxDecoration) {
              expect(decoration.boxShadow ?? const <BoxShadow>[], isEmpty);
            }
          }
        },
      );
    }

    testWidgets('le filet est au-dessus des actions, pas en dessous', (
      tester,
    ) async {
      await monter(tester, _barre);

      expect(
        tester.getBottomLeft(find.byType(AppDivider)).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byKey(_action)).dy),
      );
    });

    testWidgets('la zone sûre basse reste sous les actions', (tester) async {
      const double barreAccueil = 34;
      await monter(
        tester,
        _barre,
        viewPadding: const EdgeInsets.only(bottom: barreAccueil),
      );

      final action = tester.getRect(find.byKey(_action));
      final barre = tester.getRect(find.byType(BarreActionsBasse));
      expect(
        barre.bottom - action.bottom,
        AppSpacing.pageCompact + barreAccueil,
      );
    });

    testWidgets('elle empile plusieurs actions sur toute la colonne', (
      tester,
    ) async {
      await monter(
        tester,
        const BarreActionsBasse(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PrimaryButton(
                key: Key('principale'),
                libelle: 'Envoyer',
                onPressed: _rien,
              ),
              SizedBox(height: AppSpacing.entreCibles),
              PrimaryButton(
                key: Key('secondaire'),
                libelle: 'Choisir un autre fichier',
                variante: PrimaryButtonVariante.secondaire,
                onPressed: _rien,
              ),
            ],
          ),
        ),
        taille: const Size(1280, 900),
      );

      expect(
        tester.getSize(find.byKey(const Key('principale'))).width,
        AppSpacing.colonneMax,
      );
      expect(
        tester.getSize(find.byKey(const Key('secondaire'))).width,
        AppSpacing.colonneMax,
      );
    });
  });
}
