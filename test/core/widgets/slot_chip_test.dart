import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:flutter/gestures.dart';
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

    testWidgets('dense mesure 28 px et est actionnable au pointeur fin', (
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
        // Fenêtre large : c'est le contexte de la matrice du ticket 016,
        // celui où l'admin clique ses cellules.
        taille: const Size(1400, 900),
      );

      expect(tester.getSize(find.byType(SlotChip)), const Size(28, 28));
      await tester.tap(find.byType(SlotChip));
      expect(appels, 1);
    });

    testWidgets('dense annoncée comme un bouton actif au pointeur fin', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await monter(
        tester,
        Align(
          child: _case(
            DisponibiliteEtat.disponible,
            densite: SlotChipDensite.dense,
            onTap: () {},
          ),
        ),
        taille: const Size(1400, 900),
      );

      expect(
        tester.getSemantics(find.byType(SlotChip)),
        containsSemantics(isButton: true, isEnabled: true),
      );
      // Et le focus clavier existe : la matrice se parcourt au clavier.
      expect(
        find.descendant(
          of: find.byType(SlotChip),
          matching: find.byType(Focus),
        ),
        findsWidgets,
      );

      handle.dispose();
    });

    testWidgets('dense reste inerte au tactile', (tester) async {
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
        // Fenêtre compacte par défaut : pointeur grossier, la densité dense
        // est interdite.
      );
      // L'assertion de debug prévient le développeur…
      expect(tester.takeException(), isAssertionError);
      // …et en production, la case refuse quand même l'appui du doigt.
      await tester.tap(find.byType(SlotChip), warnIfMissed: false);
      expect(appels, 0);
    });
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

  group('SlotChip — mois verrouillé', () {
    testWidgets('le contour d\'« absent » devient gris, jamais rouge', (
      tester,
    ) async {
      Color filetDe(WidgetTester tester) {
        final peinture = tester.widget<CustomPaint>(
          find
              .descendant(
                of: find.byType(SlotChip),
                matching: find.byType(CustomPaint),
              )
              .first,
        );
        final couleurs = <Color>[];
        peinture.painter!.paint(_CanvasEspion(couleurs), const Size(104, 48));
        // Le premier trait est le fond, le second le contour.
        return couleurs[1];
      }

      await monter(
        tester,
        SizedBox(height: 48, child: _case(DisponibiliteEtat.absent)),
      );
      final libre = filetDe(tester);

      await monter(
        tester,
        SizedBox(
          height: 48,
          child: _case(DisponibiliteEtat.absent, verrouille: true),
        ),
      );
      final verrouille = filetDe(tester);

      expect(verrouille, isNot(libre));
      // Gris : les trois canaux se tiennent, contrairement au vermillon.
      final ecart =
          <int>[
            verrouille.r.toInt(),
            verrouille.g.toInt(),
            verrouille.b.toInt(),
          ].reduce((a, b) => a > b ? a : b) -
          <int>[
            verrouille.r.toInt(),
            verrouille.g.toInt(),
            verrouille.b.toInt(),
          ].reduce((a, b) => a < b ? a : b);
      expect(ecart, lessThan(40), reason: 'un fait gris, pas une alarme');
    });

    testWidgets('la valeur reste lisible : chaque état garde son glyphe', (
      tester,
    ) async {
      for (final etat in DisponibiliteEtat.values) {
        await monter(
          tester,
          SizedBox(height: 48, child: _case(etat, verrouille: true)),
        );
        expect(
          find.byIcon(AppStatusColors.clair.disponibilite(etat).iconeCase),
          findsOneWidget,
          reason: 'l\'état ${etat.name} doit rester reconnaissable',
        );
      }
    });
  });

  group('SlotChip — état pressé (brief 011 § 6.1)', () {
    /// La peinture de fond de la case, telle que le `CustomPaint` la porte.
    Color fond(WidgetTester tester) {
      final peinture = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byType(SlotChip),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      final couleurs = <Color>[];
      peinture.painter!.paint(_CanvasEspion(couleurs), const Size(104, 48));
      return couleurs.first;
    }

    testWidgets('le fond s\'assombrit au contact et revient au relâchement', (
      tester,
    ) async {
      await monter(
        tester,
        SizedBox(
          height: 48,
          child: _case(DisponibiliteEtat.nonSaisi, onTap: () {}),
        ),
      );

      final repos = fond(tester);
      final geste = await tester.startGesture(
        tester.getCenter(find.byType(SlotChip)),
      );
      await tester.pump();
      final presse = fond(tester);
      expect(presse, isNot(repos));

      await geste.up();
      await tester.pump();
      expect(fond(tester), repos);
    });

    testWidgets('rien ne bouge sous le doigt : ni taille, ni bordure', (
      tester,
    ) async {
      await monter(
        tester,
        SizedBox(
          height: 48,
          child: _case(DisponibiliteEtat.disponible, onTap: () {}),
        ),
      );

      final avant = tester.getRect(find.byType(SlotChip));
      final geste = await tester.startGesture(
        tester.getCenter(find.byType(SlotChip)),
      );
      await tester.pump();

      expect(tester.getRect(find.byType(SlotChip)), avant);
      await geste.up();
      await tester.pump();
    });

    testWidgets('un défilement annule l\'appui au lieu de le laisser posé', (
      tester,
    ) async {
      await monter(
        tester,
        ListView(
          children: <Widget>[
            for (var index = 0; index < 40; index++)
              SizedBox(
                height: 48,
                child: _case(DisponibiliteEtat.nonSaisi, onTap: () {}),
              ),
          ],
        ),
      );

      final repos = fond(tester);
      final geste = await tester.startGesture(
        tester.getCenter(find.byType(SlotChip).first),
      );
      // Dans un défilant, `onTapDown` attend le délai d'appui : la case ne
      // s'assombrit pas sous un doigt qui passe.
      await tester.pump(kPressTimeout + const Duration(milliseconds: 20));
      expect(fond(tester), isNot(repos));

      // Le doigt part : le Scrollable gagne l'arène, la case se rend.
      await geste.moveBy(const Offset(0, -200));
      await tester.pump();
      expect(fond(tester), repos);

      await geste.up();
      await tester.pump();
    });

    testWidgets('une case verrouillée ne crée aucun état d\'appui', (
      tester,
    ) async {
      await monter(
        tester,
        SizedBox(
          height: 48,
          child: _case(
            DisponibiliteEtat.disponible,
            onTap: () {},
            verrouille: true,
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(SlotChip),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });
  });
}

/// Un `Canvas` qui ne dessine rien et retient les couleurs demandées.
///
/// Le seul moyen honnête de vérifier le fond d'une case : il est peint, pas
/// posé dans une `BoxDecoration` qu'un test pourrait lire.
class _CanvasEspion implements Canvas {
  _CanvasEspion(this.couleurs);

  final List<Color> couleurs;

  @override
  void drawRRect(RRect rrect, Paint paint) => couleurs.add(paint.color);

  @override
  void drawPath(Path path, Paint paint) => couleurs.add(paint.color);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
