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
  DaySlot? creneauJour,
  DaySlot? creneauNuit,
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
    jour: creneauJour ?? const DaySlot(etat: DisponibiliteEtat.disponible),
    nuit: creneauNuit ?? const DaySlot(etat: DisponibiliteEtat.nonSaisi),
  );
}

SlotChip _chip(WidgetTester tester, int index) =>
    tester.widget<SlotChip>(find.byType(SlotChip).at(index));

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
      expect(_chip(tester, 0).creneau, CreneauType.jour);
      expect(_chip(tester, 1).creneau, CreneauType.nuit);
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

  group('DayCell — rappels et états par créneau', () {
    testWidgets('transmet l\'appui sur chaque créneau séparément', (
      tester,
    ) async {
      var jour = 0;
      var nuit = 0;
      await monter(
        tester,
        SizedBox(
          width: 132,
          child: _jour(
            creneauJour: DaySlot(
              etat: DisponibiliteEtat.nonSaisi,
              onTap: () => jour++,
            ),
            creneauNuit: DaySlot(
              etat: DisponibiliteEtat.nonSaisi,
              onTap: () => nuit++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SlotChip).first);
      expect(<int>[jour, nuit], <int>[1, 0]);
      await tester.tap(find.byType(SlotChip).last);
      expect(<int>[jour, nuit], <int>[1, 1]);
    });

    testWidgets('fait descendre onDragEnter jusqu\'à la case (ticket 011)', (
      tester,
    ) async {
      void glisseJour() {}
      void glisseNuit() {}

      await monter(
        tester,
        SizedBox(
          width: 132,
          child: _jour(
            creneauJour: DaySlot(
              etat: DisponibiliteEtat.nonSaisi,
              onDragEnter: glisseJour,
            ),
            creneauNuit: DaySlot(
              etat: DisponibiliteEtat.nonSaisi,
              onDragEnter: glisseNuit,
            ),
          ),
        ),
      );

      expect(_chip(tester, 0).onDragEnter, same(glisseJour));
      expect(_chip(tester, 1).onDragEnter, same(glisseNuit));
      // Le rappel est publié dans un MetaData, que la grille retrouvera en
      // testant le point sous le doigt.
      expect(find.byType(MetaData), findsNWidgets(2));
    });

    testWidgets('fait descendre la sélection créneau par créneau', (
      tester,
    ) async {
      await monter(
        tester,
        SizedBox(
          width: 132,
          child: _jour(
            creneauJour: const DaySlot(
              etat: DisponibiliteEtat.disponible,
              selectionne: true,
            ),
            creneauNuit: const DaySlot(etat: DisponibiliteEtat.disponible),
          ),
        ),
      );

      expect(_chip(tester, 0).selectionne, isTrue);
      expect(_chip(tester, 1).selectionne, isFalse);
    });

    testWidgets('fait descendre l\'erreur et l\'enregistrement', (
      tester,
    ) async {
      await monter(
        tester,
        SizedBox(
          width: 132,
          child: _jour(
            creneauJour: const DaySlot(
              etat: DisponibiliteEtat.absent,
              erreur: true,
            ),
            creneauNuit: const DaySlot(
              etat: DisponibiliteEtat.disponible,
              enEnregistrement: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(_chip(tester, 0).erreur, isTrue);
      expect(_chip(tester, 0).enEnregistrement, isFalse);
      expect(_chip(tester, 1).erreur, isFalse);
      expect(_chip(tester, 1).enEnregistrement, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un mois verrouillé coupe appui et glissement', (tester) async {
      var appels = 0;
      await monter(
        tester,
        SizedBox(
          width: 132,
          child: _jour(
            verrouille: true,
            creneauJour: DaySlot(
              etat: DisponibiliteEtat.disponible,
              onTap: () => appels++,
              onDragEnter: () => appels++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SlotChip).first, warnIfMissed: false);
      expect(appels, 0);
      expect(_chip(tester, 0).onTap, isNull);
      expect(_chip(tester, 0).onDragEnter, isNull);
    });

    testWidgets('un jour hors du mois coupe appui et glissement', (
      tester,
    ) async {
      var appels = 0;
      await monter(
        tester,
        SizedBox(
          width: 132,
          child: _jour(
            horsMois: true,
            creneauJour: DaySlot(
              etat: DisponibiliteEtat.disponible,
              onTap: () => appels++,
              onDragEnter: () => appels++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SlotChip).first, warnIfMissed: false);
      expect(appels, 0);
      expect(_chip(tester, 0).onDragEnter, isNull);
    });
  });

  group('DaySlot', () {
    test('deux créneaux de même contenu sont égaux', () {
      expect(
        const DaySlot(etat: DisponibiliteEtat.absent, selectionne: true),
        const DaySlot(etat: DisponibiliteEtat.absent, selectionne: true),
      );
      expect(
        const DaySlot(etat: DisponibiliteEtat.absent),
        isNot(const DaySlot(etat: DisponibiliteEtat.disponible)),
      );
    });

    test('copyWith conserve les rappels et les drapeaux', () {
      void glisse() {}
      final source = DaySlot(
        etat: DisponibiliteEtat.nonSaisi,
        onDragEnter: glisse,
        selectionne: true,
        erreur: true,
        enEnregistrement: true,
      );
      final copie = source.copyWith(etat: DisponibiliteEtat.disponible);

      expect(copie.etat, DisponibiliteEtat.disponible);
      expect(copie.onDragEnter, same(glisse));
      expect(copie.selectionne, isTrue);
      expect(copie.erreur, isTrue);
      expect(copie.enEnregistrement, isTrue);
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

  group('DayCell — orientation ligne (registre, ticket 011)', () {
    DayCell ligne({
      bool weekend = false,
      String? ferie,
      bool aujourdhui = false,
      bool verrouille = false,
      bool deuxNiveaux = false,
    }) => DayCell(
      numero: 4,
      nomJour: 'sam.',
      dateLongue: 'Samedi 4 octobre',
      orientation: DayCellOrientation.ligne,
      weekend: weekend,
      nomJourFerie: ferie,
      aujourdhui: aujourdhui,
      verrouille: verrouille,
      deuxNiveaux: deuxNiveaux,
      jour: const DaySlot(etat: DisponibiliteEtat.disponible),
      nuit: const DaySlot(etat: DisponibiliteEtat.nonSaisi),
    );

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name} : la ligne se rend', (tester) async {
        await monter(
          tester,
          SizedBox(width: 358, child: ligne(weekend: true, ferie: 'Toussaint')),
          brightness: brightness,
        );

        expect(find.byType(SlotChip), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('pose les trois colonnes de gauche à droite', (tester) async {
      await monter(tester, SizedBox(width: 358, child: ligne()));

      final date = tester.getRect(find.text('4'));
      final jour = tester.getRect(find.byType(SlotChip).first);
      final nuit = tester.getRect(find.byType(SlotChip).last);

      expect(date.left, lessThan(jour.left));
      expect(jour.right, lessThanOrEqualTo(nuit.left));
      // Les deux cases se partagent la même largeur, à 1 dp près.
      expect((jour.width - nuit.width).abs(), lessThan(1));
    });

    testWidgets('ne répète pas l\'icône du créneau dans chaque cellule', (
      tester,
    ) async {
      await monter(tester, SizedBox(width: 358, child: ligne()));

      // L'icône vit dans l'en-tête de colonnes épinglé (brief § 6.5).
      expect(find.byIcon(Icons.light_mode), findsNothing);
      expect(find.byIcon(Icons.bedtime), findsNothing);
    });

    testWidgets('affiche le nom du férié en clair, pas en info-bulle', (
      tester,
    ) async {
      await monter(
        tester,
        SizedBox(width: 358, child: ligne(weekend: true, ferie: 'Toussaint')),
      );

      expect(find.text('Toussaint'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('la case garde ses 48 dp et sa cible tactile', (tester) async {
      await monter(
        tester,
        SizedBox(
          width: 358,
          child: DayCell(
            numero: 4,
            nomJour: 'sam.',
            dateLongue: 'Samedi 4 octobre',
            orientation: DayCellOrientation.ligne,
            jour: DaySlot(etat: DisponibiliteEtat.nonSaisi, onTap: () {}),
            nuit: DaySlot(etat: DisponibiliteEtat.nonSaisi, onTap: () {}),
          ),
        ),
      );

      verifierCiblesTactiles(tester, find.byType(SlotChip));
      for (var index = 0; index < 2; index++) {
        // ~104 dp de large sur un téléphone de 360 : un couloir de peinture
        // large comme un pouce ganté (brief § 3).
        expect(
          tester.getSize(find.byType(SlotChip).at(index)).width,
          greaterThan(100),
        );
      }
    });

    testWidgets('la sémantique de la case dit toujours « nuit »', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await monter(tester, SizedBox(width: 358, child: ligne()));

      expect(
        _chip(tester, 1).libelleSemantique,
        contains(AppStrings.creneauNuit.toLowerCase()),
      );

      handle.dispose();
    });

    testWidgets('à deux niveaux, les cases passent pleine largeur', (
      tester,
    ) async {
      await monter(
        tester,
        SizedBox(width: 358, child: ligne(deuxNiveaux: true)),
        echelleTexte: 2,
      );

      final jour = tester.getRect(find.byType(SlotChip).first);
      final nuit = tester.getRect(find.byType(SlotChip).last);
      expect(jour.bottom, lessThanOrEqualTo(nuit.top));
      expect(jour.width, greaterThan(300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('verrouillée, la ligne n\'est ni actionnable ni focalisable', (
      tester,
    ) async {
      await monter(
        tester,
        SizedBox(width: 358, child: ligne(verrouille: true)),
      );

      expect(_chip(tester, 0).onTap, isNull);
      expect(_chip(tester, 0).verrouille, isTrue);
      expect(
        find.descendant(of: find.byType(DayCell), matching: find.byType(Focus)),
        findsNothing,
      );
    });
  });
}
