import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/day_cell.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

DayCell _jour({
  bool weekend = false,
  String? ferie,
  bool aujourdhui = false,
  bool horsMois = false,
  bool verrouille = false,
  VoidCallback? onTapJour,
}) {
  return DayCell(
    numero: 4,
    nomJour: 'sam.',
    dateLongue: 'Samedi 4 octobre',
    weekend: weekend,
    nomJourFerie: ferie,
    aujourdhui: aujourdhui,
    horsMois: horsMois,
    verrouille: verrouille,
    etatJour: DisponibiliteEtat.disponible,
    etatNuit: DisponibiliteEtat.nonSaisi,
    onTapJour: onTapJour,
  );
}

void main() {
  group('DayCell — rendu', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name} : les six variantes se rendent', (
        tester,
      ) async {
        await monter(
          tester,
          SingleChildScrollView(
            child: Column(
              children: <Widget>[
                SizedBox(width: 132, child: _jour()),
                SizedBox(width: 132, child: _jour(weekend: true)),
                SizedBox(
                  width: 132,
                  child: _jour(weekend: true, ferie: 'Toussaint'),
                ),
                SizedBox(width: 132, child: _jour(aujourdhui: true)),
                SizedBox(width: 132, child: _jour(verrouille: true)),
                SizedBox(width: 132, child: _jour(horsMois: true)),
              ],
            ),
          ),
          brightness: brightness,
        );

        expect(find.byType(DayCell), findsNWidgets(6));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('affiche le numéro et le nom du jour', (tester) async {
      await monter(tester, SizedBox(width: 132, child: _jour()));

      expect(find.text('4'), findsOneWidget);
      expect(find.text('sam.'), findsOneWidget);
    });

    testWidgets('empile deux cases, jour au-dessus et nuit en dessous', (
      tester,
    ) async {
      await monter(tester, SizedBox(width: 132, child: _jour()));

      expect(find.byType(SlotChip), findsNWidgets(2));
      final premier = tester.widget<SlotChip>(find.byType(SlotChip).first);
      final second = tester.widget<SlotChip>(find.byType(SlotChip).last);
      expect(premier.creneau, CreneauType.jour);
      expect(second.creneau, CreneauType.nuit);
      expect(
        tester.getTopLeft(find.byType(SlotChip).first).dy,
        lessThan(tester.getTopLeft(find.byType(SlotChip).last).dy),
      );
    });

    testWidgets('signe le jour et la nuit par leurs icônes', (tester) async {
      await monter(tester, SizedBox(width: 132, child: _jour()));

      expect(find.byIcon(Icons.light_mode), findsOneWidget);
      expect(find.byIcon(Icons.bedtime), findsOneWidget);
    });

    testWidgets('un jour férié porte une étoile et son nom en info-bulle', (
      tester,
    ) async {
      await monter(
        tester,
        SizedBox(width: 132, child: _jour(weekend: true, ferie: 'Toussaint')),
      );

      expect(find.byIcon(Icons.star), findsOneWidget);
      final infoBulle = tester.widget<Tooltip>(find.byType(Tooltip).first);
      expect(infoBulle.message, AppStrings.jourFerieNomme('Toussaint'));
    });
  });

  group('DayCell — interaction', () {
    testWidgets('transmet l\'appui sur la case de jour', (tester) async {
      var appels = 0;
      await monter(
        tester,
        SizedBox(width: 132, child: _jour(onTapJour: () => appels++)),
      );

      await tester.tap(find.byType(SlotChip).first);
      expect(appels, 1);
    });

    testWidgets('un mois verrouillé rend les cases inertes', (tester) async {
      var appels = 0;
      await monter(
        tester,
        SizedBox(
          width: 132,
          child: _jour(verrouille: true, onTapJour: () => appels++),
        ),
      );

      await tester.tap(find.byType(SlotChip).first, warnIfMissed: false);
      expect(appels, 0);
    });

    testWidgets('un jour hors du mois rend les cases inertes', (tester) async {
      var appels = 0;
      await monter(
        tester,
        SizedBox(
          width: 132,
          child: _jour(horsMois: true, onTapJour: () => appels++),
        ),
      );

      await tester.tap(find.byType(SlotChip).first, warnIfMissed: false);
      expect(appels, 0);
    });
  });

  group('DayCell — accessibilité', () {
    testWidgets('annonce la date, « Aujourd\'hui » et le weekend', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        SizedBox(width: 132, child: _jour(weekend: true, aujourdhui: true)),
      );

      final noeud = tester.getSemantics(find.byType(DayCell));
      expect(noeud.label, contains('Samedi 4 octobre'));
      expect(noeud.label, contains(AppStrings.jourAujourdhui));
      expect(noeud.label, contains(AppStrings.jourWeekend));

      handle.dispose();
    });

    testWidgets('annonce le verrouillage du mois', (tester) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        SizedBox(width: 132, child: _jour(verrouille: true)),
      );

      expect(
        tester.getSemantics(find.byType(DayCell)).label,
        contains(AppStrings.periodeVerrouillee),
      );

      handle.dispose();
    });

    testWidgets('tient une échelle de texte de 2.0', (tester) async {
      await monter(
        tester,
        SizedBox(width: 180, child: _jour(weekend: true, ferie: 'Toussaint')),
        echelleTexte: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
