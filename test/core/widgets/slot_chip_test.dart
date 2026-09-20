import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

SlotChip _case(
  DisponibiliteEtat etat, {
  CreneauType creneau = CreneauType.jour,
  SlotChipDensite densite = SlotChipDensite.confortable,
  VoidCallback? onTap,
  bool selectionne = false,
  bool verrouille = false,
  bool erreur = false,
  bool enEnregistrement = false,
}) {
  return SlotChip(
    etat: etat,
    creneau: creneau,
    densite: densite,
    selectionne: selectionne,
    verrouille: verrouille,
    erreur: erreur,
    enEnregistrement: enEnregistrement,
    onTap: onTap,
    libelleSemantique:
        'Samedi 4 octobre, jour, '
        '${etat.name}',
    actionSemantique: AppStrings.slotActionMarquerAbsent,
  );
}

void main() {
  group('SlotChip — rendu', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name} : les trois états se rendent', (
        tester,
      ) async {
        await monter(
          tester,
          Column(
            children: <Widget>[
              for (final etat in DisponibiliteEtat.values)
                SizedBox(height: 48, child: _case(etat)),
            ],
          ),
          brightness: brightness,
        );

        expect(find.byType(SlotChip), findsNWidgets(3));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('chaque état porte son propre glyphe de case', (tester) async {
      await monter(
        tester,
        Column(
          children: <Widget>[
            for (final etat in DisponibiliteEtat.values)
              SizedBox(height: 48, child: _case(etat)),
          ],
        ),
      );

      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
    });

    testWidgets('les états visuels supplémentaires se rendent sans exception', (
      tester,
    ) async {
      await monter(
        tester,
        Column(
          children: <Widget>[
            SizedBox(
              height: 48,
              child: _case(
                DisponibiliteEtat.disponible,
                selectionne: true,
                onTap: () {},
              ),
            ),
            SizedBox(
              height: 48,
              child: _case(DisponibiliteEtat.disponible, verrouille: true),
            ),
            SizedBox(
              height: 48,
              child: _case(
                DisponibiliteEtat.absent,
                erreur: true,
                onTap: () {},
              ),
            ),
            SizedBox(
              height: 48,
              child: _case(
                DisponibiliteEtat.absent,
                enEnregistrement: true,
                onTap: () {},
              ),
            ),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(SlotChip), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  });

  group('SlotChip — interaction', () {
    testWidgets('appelle onTap quand elle est actionnable', (tester) async {
      var appels = 0;
      await monter(
        tester,
        SizedBox(
          height: 48,
          child: _case(DisponibiliteEtat.nonSaisi, onTap: () => appels++),
        ),
      );

      await tester.tap(find.byType(SlotChip));
      expect(appels, 1);
    });

    testWidgets('n\'appelle rien quand le mois est verrouillé', (tester) async {
      var appels = 0;
      await monter(
        tester,
        SizedBox(
          height: 48,
          child: _case(
            DisponibiliteEtat.disponible,
            verrouille: true,
            onTap: () => appels++,
          ),
        ),
      );

      await tester.tap(find.byType(SlotChip), warnIfMissed: false);
      expect(appels, 0);
    });
  });

  group('SlotChip — cibles tactiles', () {
    testWidgets('confortable mesure 48 dp', (tester) async {
      await monter(
        tester,
        Align(
          child: SizedBox.square(
            dimension: 48,
            child: _case(DisponibiliteEtat.nonSaisi, onTap: () {}),
          ),
        ),
      );

      verifierCiblesTactiles(tester, find.byType(SlotChip), plancher: 48);
    });

    testWidgets('compacte actionnable est remontée au plancher de 44 dp', (
      tester,
    ) async {
      await monter(
        tester,
        Align(
          child: SizedBox(
            width: 44,
            child: _case(
              DisponibiliteEtat.nonSaisi,
              densite: SlotChipDensite.compacte,
              onTap: () {},
            ),
          ),
        ),
      );

      verifierCiblesTactiles(tester, find.byType(SlotChip));
    });

    testWidgets('compacte en lecture seule reste à 40 dp', (tester) async {
      await monter(
        tester,
        Align(
          child: SizedBox(
            width: 40,
            child: _case(
              DisponibiliteEtat.nonSaisi,
              densite: SlotChipDensite.compacte,
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(SlotChip)).height, 40);
    });

    testWidgets('dense mesure 28 px et n\'est jamais actionnable', (
      tester,
    ) async {
      var appels = 0;
      await monter(
        tester,
        Align(
          child: _case(
            DisponibiliteEtat.disponible,
            densite: SlotChipDensite.dense,
            onTap: () => appels++,
          ),
        ),
        // Fenêtre large : la densité dense n'est autorisée qu'au pointeur fin,
        // l'assertion du widget le vérifie.
        taille: const Size(1400, 900),
      );

      expect(tester.getSize(find.byType(SlotChip)), const Size(28, 28));
      await tester.tap(find.byType(SlotChip), warnIfMissed: false);
      expect(appels, 0);
    });

    testWidgets(
      'dense actionnable sur une fenêtre tactile déclenche une assertion',
      (tester) async {
        await monter(
          tester,
          Align(
            child: _case(
              DisponibiliteEtat.disponible,
              densite: SlotChipDensite.dense,
              onTap: () {},
            ),
          ),
        );

        expect(tester.takeException(), isAssertionError);
      },
    );
  });

  group('SlotChip — accessibilité', () {
    testWidgets('annonce une phrase complète et l\'action à venir', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        SizedBox(
          height: 48,
          child: _case(DisponibiliteEtat.disponible, onTap: () {}),
        ),
      );

      expect(
        tester.getSemantics(find.byType(SlotChip)),
        containsSemantics(
          hint: AppStrings.slotActionMarquerAbsent,
          isButton: true,
          isToggled: true,
          isEnabled: true,
        ),
      );
      expect(
        tester.getSemantics(find.byType(SlotChip)).label,
        contains('Samedi 4 octobre'),
      );

      handle.dispose();
    });

    testWidgets('une case verrouillée annonce son verrouillage', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        SizedBox(
          height: 48,
          child: _case(DisponibiliteEtat.disponible, verrouille: true),
        ),
      );

      expect(
        tester.getSemantics(find.byType(SlotChip)).hint,
        AppStrings.slotVerrouille,
      );

      handle.dispose();
    });
  });

  testWidgets('tient une échelle de texte de 2.0 sans déborder', (
    tester,
  ) async {
    await monter(
      tester,
      Column(
        children: <Widget>[
          for (final etat in DisponibiliteEtat.values)
            SizedBox(height: 48, child: _case(etat, onTap: () {})),
        ],
      ),
      echelleTexte: 2,
    );

    expect(tester.takeException(), isNull);
  });
}
