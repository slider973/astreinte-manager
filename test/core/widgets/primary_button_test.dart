import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('PrimaryButton — rendu', () {
    for (final brightness in Brightness.values) {
      for (final variante in PrimaryButtonVariante.values) {
        testWidgets(
          '${brightness.name} / ${variante.name} affiche le libellé',
          (tester) async {
            await monter(
              tester,
              PrimaryButton(
                libelle: 'Enregistrer le mois',
                variante: variante,
                onPressed: () {},
              ),
              brightness: brightness,
            );

            expect(find.text('Enregistrer le mois'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('affiche l\'icône quand elle est fournie', (tester) async {
      await monter(
        tester,
        PrimaryButton(
          libelle: 'Enregistrer le mois',
          icone: Icons.check,
          onPressed: () {},
        ),
      );

      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('en chargement, le libellé reste et un indicateur le précède', (
      tester,
    ) async {
      await monter(
        tester,
        PrimaryButton(
          libelle: 'Enregistrer le mois',
          icone: Icons.check,
          chargement: true,
          onPressed: () {},
        ),
      );

      expect(find.text('Enregistrer le mois'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // L'icône a cédé sa place à l'indicateur : la largeur ne bouge pas.
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('la largeur ne change pas en passant en chargement', (
      tester,
    ) async {
      await monter(
        tester,
        Align(
          child: PrimaryButton(
            libelle: 'Enregistrer le mois',
            icone: Icons.check,
            pleineLargeur: false,
            onPressed: () {},
          ),
        ),
      );
      final avant = tester.getSize(find.byType(PrimaryButton)).width;

      await monter(
        tester,
        Align(
          child: PrimaryButton(
            libelle: 'Enregistrer le mois',
            icone: Icons.check,
            chargement: true,
            pleineLargeur: false,
            onPressed: () {},
          ),
        ),
      );

      expect(tester.getSize(find.byType(PrimaryButton)).width, avant);
    });
  });

  group('PrimaryButton — désactivation', () {
    testWidgets('affiche la raison à côté du contrôle', (tester) async {
      await monter(
        tester,
        const PrimaryButton(
          libelle: 'Enregistrer le mois',
          onPressed: null,
          raisonDesactivation: 'Le mois est verrouillé depuis le 15 septembre.',
        ),
      );

      expect(
        find.text('Le mois est verrouillé depuis le 15 septembre.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('un bouton grisé sans raison est une erreur de programmation', (
      tester,
    ) async {
      await monter(
        tester,
        const PrimaryButton(libelle: 'Enregistrer', onPressed: null),
      );

      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('n\'appelle rien quand il est désactivé', (tester) async {
      const appels = 0;
      await monter(
        tester,
        const PrimaryButton(
          libelle: 'Enregistrer le mois',
          onPressed: null,
          raisonDesactivation: 'Mois verrouillé.',
        ),
      );
      await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
      expect(appels, 0);
    });
  });

  group('PrimaryButton — interaction et accessibilité', () {
    testWidgets('appelle onPressed', (tester) async {
      var appels = 0;
      await monter(
        tester,
        PrimaryButton(libelle: 'Continuer', onPressed: () => appels++),
      );

      await tester.tap(find.byType(PrimaryButton));
      expect(appels, 1);
    });

    testWidgets('est annoncé comme un bouton, avec sa raison en indice', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        const PrimaryButton(
          libelle: 'Enregistrer le mois',
          onPressed: null,
          raisonDesactivation: 'Mois verrouillé.',
        ),
      );

      final noeud = tester.getSemantics(
        find.bySemanticsLabel('Enregistrer le mois'),
      );
      expect(noeud.label, 'Enregistrer le mois');
      expect(noeud.hint, 'Mois verrouillé.');
      expect(noeud.flagsCollection.isButton, isTrue);

      handle.dispose();
    });

    testWidgets('mesure au moins 48 dp de haut', (tester) async {
      await monter(
        tester,
        PrimaryButton(libelle: 'Continuer', onPressed: () {}),
      );

      expect(
        tester.getSize(find.byType(PrimaryButton)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('tient une échelle de texte de 2.0', (tester) async {
      await monter(
        tester,
        PrimaryButton(
          libelle: 'Enregistrer le mois',
          icone: Icons.check,
          onPressed: () {},
        ),
        echelleTexte: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
