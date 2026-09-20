import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/app_divider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('AppDivider', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name} : les trois filets se rendent', (
        tester,
      ) async {
        await monter(
          tester,
          const Column(
            children: <Widget>[
              AppDivider(),
              AppDivider.enTete(),
              SizedBox(height: 48, child: AppDivider.vertical()),
            ],
          ),
          brightness: brightness,
        );

        expect(find.byType(AppDivider), findsNWidgets(3));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('le filet décoratif prend la réglure du thème', (tester) async {
      await monter(tester, const AppDivider());

      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.color, AppStatusColors.clair.filetDecoratif);
      expect(divider.thickness, 1);
      expect(divider.height, 1);
    });

    testWidgets('le filet porteur d\'état prend la couleur à 3:1', (
      tester,
    ) async {
      await monter(tester, const AppDivider(porteurEtat: true));

      expect(
        tester.widget<Divider>(find.byType(Divider)).color,
        AppStatusColors.clair.filetEtat,
      );
    });

    testWidgets('le filet d\'en-tête collant fait 2 dp et porte un état', (
      tester,
    ) async {
      await monter(tester, const AppDivider.enTete());

      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.thickness, 2);
      expect(divider.color, AppStatusColors.clair.filetEtat);
    });

    testWidgets('le filet vertical utilise VerticalDivider', (tester) async {
      await monter(
        tester,
        const SizedBox(height: 48, child: AppDivider.vertical()),
      );

      final divider = tester.widget<VerticalDivider>(
        find.byType(VerticalDivider),
      );
      expect(divider.width, 1);
      expect(divider.color, AppStatusColors.clair.filetDecoratif);
    });

    testWidgets('en sombre, la réglure suit le thème', (tester) async {
      await monter(tester, const AppDivider(), brightness: Brightness.dark);

      expect(
        tester.widget<Divider>(find.byType(Divider)).color,
        AppStatusColors.sombre.filetDecoratif,
      );
    });
  });
}
