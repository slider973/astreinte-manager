import 'package:astreinte_sp/core/widgets/peinture_grille.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Une fausse grille : vingt « cases » de 48 dp, chacune publiant son rappel
/// dans un `MetaData` comme le fait `SlotChip`.
class _Damier extends StatelessWidget {
  const _Damier({
    required this.touchees,
    required this.evenements,
    this.controleur,
    this.actif = true,
    this.margeGauche = 0,
    this.cases = 20,
    this.inertes = const <int>{},
  });

  final List<int> touchees;
  final List<String> evenements;
  final ScrollController? controleur;
  final bool actif;
  final double margeGauche;
  final int cases;

  /// Les cases qui ne publient aucun rappel : mois verrouillé, hors du mois.
  final Set<int> inertes;

  @override
  Widget build(BuildContext context) {
    return PeintureGrille(
      actif: actif,
      margeGaucheInerte: margeGauche,
      controleurDefilement: controleur,
      onDebut: () => evenements.add('debut'),
      onFin: () => evenements.add('fin'),
      onAnnulation: () => evenements.add('annulation'),
      child: ListView.builder(
        controller: controleur,
        itemCount: cases,
        itemExtent: 48,
        itemBuilder: (context, index) => inertes.contains(index)
            ? const SizedBox(height: 48)
            : MetaData(
                metaData: () => touchees.add(index),
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(height: 48),
              ),
      ),
    );
  }
}

void main() {
  /// Le centre vertical de la case [index] dans un damier non défilé.
  Offset centre(int index) => Offset(200, index * 48 + 24);

  group('PeintureGrille — ce que le geste ne vole jamais', () {
    testWidgets('un glissement vertical sans appui long fait défiler', (
      tester,
    ) async {
      final touchees = <int>[];
      final evenements = <String>[];
      final controleur = ScrollController();
      addTearDown(controleur.dispose);

      await monter(
        tester,
        _Damier(
          touchees: touchees,
          evenements: evenements,
          controleur: controleur,
          cases: 60,
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(evenements, isEmpty, reason: 'aucune peinture ne doit démarrer');
      expect(touchees, isEmpty);
      expect(controleur.offset, greaterThan(0), reason: 'la page a défilé');
    });

    testWidgets('un appui long ouvre la peinture et fige le défilement', (
      tester,
    ) async {
      final touchees = <int>[];
      final evenements = <String>[];
      final controleur = ScrollController();
      addTearDown(controleur.dispose);

      await monter(
        tester,
        _Damier(
          touchees: touchees,
          evenements: evenements,
          controleur: controleur,
          cases: 60,
        ),
      );

      final geste = await tester.startGesture(centre(2));
      await tester.pump(PeintureGrille.delaiAppuiLong * 1.5);

      expect(evenements, <String>['debut']);
      expect(touchees, <int>[2]);

      await geste.moveTo(centre(5));
      await tester.pump();
      await geste.up();
      await tester.pumpAndSettle();

      expect(touchees, containsAllInOrder(<int>[2, 3, 4, 5]));
      expect(evenements.last, 'fin');
      expect(controleur.offset, 0, reason: 'la peinture ne défile pas');
    });

    testWidgets('une peinture ne démarre pas dans la bande du bord gauche', (
      tester,
    ) async {
      final touchees = <int>[];
      final evenements = <String>[];

      await monter(
        tester,
        _Damier(touchees: touchees, evenements: evenements, margeGauche: 24),
      );

      final geste = await tester.startGesture(const Offset(10, 120));
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);
      await geste.moveBy(const Offset(0, 96));
      await tester.pump();
      await geste.up();
      await tester.pumpAndSettle();

      expect(evenements, isEmpty);
      expect(touchees, isEmpty);
    });

    testWidgets('au-delà de la bande, la peinture démarre normalement', (
      tester,
    ) async {
      final touchees = <int>[];
      final evenements = <String>[];

      await monter(
        tester,
        _Damier(touchees: touchees, evenements: evenements, margeGauche: 24),
      );

      final geste = await tester.startGesture(const Offset(30, 120));
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);
      await geste.up();
      await tester.pumpAndSettle();

      expect(evenements, <String>['debut', 'fin']);
    });
  });

  group('PeintureGrille — ce que le geste pose', () {
    testWidgets('aucune case n\'est sautée par un glissement rapide', (
      tester,
    ) async {
      final touchees = <int>[];
      final evenements = <String>[];

      await monter(tester, _Damier(touchees: touchees, evenements: evenements));

      final geste = await tester.startGesture(centre(0));
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);
      // Un seul événement de pointeur qui traverse dix cases : c'est
      // l'échantillonnage du segment qui doit toutes les trouver.
      await geste.moveTo(centre(9));
      await tester.pump();
      await geste.up();
      await tester.pumpAndSettle();

      expect(touchees.toSet(), <int>{0, 1, 2, 3, 4, 5, 6, 7, 8, 9});
    });

    testWidgets('les cases inertes sont traversées sans effet', (tester) async {
      final touchees = <int>[];
      final evenements = <String>[];

      await monter(
        tester,
        _Damier(
          touchees: touchees,
          evenements: evenements,
          inertes: const <int>{2, 3},
        ),
      );

      final geste = await tester.startGesture(centre(0));
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);
      await geste.moveTo(centre(5));
      await tester.pump();
      await geste.up();
      await tester.pumpAndSettle();

      expect(touchees, isNot(contains(2)));
      expect(touchees, isNot(contains(3)));
      expect(touchees.toSet(), containsAll(<int>{0, 1, 4, 5}));
    });

    testWidgets('sortir de la grille ne peint rien, y rentrer reprend', (
      tester,
    ) async {
      final touchees = <int>[];
      final evenements = <String>[];

      await monter(
        tester,
        _Damier(touchees: touchees, evenements: evenements, cases: 6),
      );

      final geste = await tester.startGesture(centre(5));
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);
      touchees.clear();

      // Sous la dernière case : plus aucun MetaData.
      await geste.moveTo(const Offset(200, 400));
      await tester.pump();
      touchees.clear();
      await geste.moveTo(const Offset(200, 700));
      await tester.pump();
      expect(touchees, isEmpty);

      // Rentrer dans la grille reprend la peinture au même pinceau.
      await geste.moveTo(centre(4));
      await tester.pump();
      expect(touchees, contains(4));

      await geste.up();
      await tester.pumpAndSettle();
    });
  });

  group('PeintureGrille — annulation', () {
    testWidgets('un second doigt annule le geste', (tester) async {
      final touchees = <int>[];
      final evenements = <String>[];

      await monter(tester, _Damier(touchees: touchees, evenements: evenements));

      final premier = await tester.startGesture(centre(1));
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);
      await premier.moveTo(centre(3));
      await tester.pump();

      final second = await tester.startGesture(centre(8));
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);

      expect(evenements, contains('annulation'));

      touchees.clear();
      await premier.moveTo(centre(6));
      await tester.pump();
      expect(touchees, isEmpty, reason: 'un geste annulé ne peint plus');

      await premier.up();
      await second.up();
      await tester.pumpAndSettle();

      expect(
        evenements.where((nom) => nom == 'fin'),
        isEmpty,
        reason: 'un geste annulé ne se termine pas normalement',
      );
    });

    testWidgets('un pincement annule, même si le second doigt bouge tout de '
        'suite', (tester) async {
      final touchees = <int>[];
      final evenements = <String>[];

      await monter(tester, _Damier(touchees: touchees, evenements: evenements));

      final premier = await tester.startGesture(centre(1));
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);
      expect(evenements, <String>['debut']);

      // Un vrai pincement : le second doigt se pose **et part** aussitôt. Le
      // reconnaisseur d'appui long ne le verrait jamais.
      final second = await tester.startGesture(centre(8));
      await second.moveBy(const Offset(0, -40));
      await tester.pump();

      expect(evenements, contains('annulation'));

      touchees.clear();
      await premier.moveTo(centre(5));
      await tester.pump();
      expect(touchees, isEmpty, reason: 'un geste annulé ne peint plus');

      await premier.up();
      await second.up();
      await tester.pumpAndSettle();
    });

    testWidgets('aucune nouvelle peinture ne s\'ouvre tant que deux doigts '
        'sont posés', (tester) async {
      final touchees = <int>[];
      final evenements = <String>[];

      await monter(tester, _Damier(touchees: touchees, evenements: evenements));

      final premier = await tester.startGesture(centre(1));
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);
      final second = await tester.startGesture(centre(8));
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);

      expect(
        evenements.where((nom) => nom == 'debut'),
        hasLength(1),
        reason: 'le second doigt annule, il n\'ouvre pas un second geste',
      );

      await premier.up();
      await second.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Échap annule le geste', (tester) async {
      final touchees = <int>[];
      final evenements = <String>[];

      await monter(tester, _Damier(touchees: touchees, evenements: evenements));

      final geste = await tester.startGesture(centre(1));
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(evenements, contains('annulation'));

      await geste.up();
      await tester.pumpAndSettle();
    });

    testWidgets('inactive, la grille ne peint rien du tout', (tester) async {
      final touchees = <int>[];
      final evenements = <String>[];

      await monter(
        tester,
        _Damier(touchees: touchees, evenements: evenements, actif: false),
      );

      final geste = await tester.startGesture(centre(1));
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);
      await geste.moveTo(centre(4));
      await tester.pump();
      await geste.up();
      await tester.pumpAndSettle();

      expect(evenements, isEmpty);
      expect(touchees, isEmpty);
    });
  });

  group('PeintureGrille — défilement automatique aux bords', () {
    testWidgets('le doigt au bas de la grille fait défiler et peint', (
      tester,
    ) async {
      final touchees = <int>[];
      final evenements = <String>[];
      final controleur = ScrollController();
      addTearDown(controleur.dispose);

      await monter(
        tester,
        _Damier(
          touchees: touchees,
          evenements: evenements,
          controleur: controleur,
          cases: 120,
        ),
      );

      final geste = await tester.startGesture(centre(2));
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);

      // Tout en bas de la fenêtre de 844 dp : vitesse maximale.
      await geste.moveTo(const Offset(200, 840));
      for (var image = 0; image < 30; image++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(controleur.offset, greaterThan(0));
      expect(
        touchees.toSet().length,
        greaterThan(17),
        reason: 'les cases passées sous le doigt sont peintes',
      );

      await geste.up();
      await tester.pumpAndSettle();
    });

    testWidgets('le défilement automatique s\'arrête au bout du mois', (
      tester,
    ) async {
      final touchees = <int>[];
      final evenements = <String>[];
      final controleur = ScrollController();
      addTearDown(controleur.dispose);

      await monter(
        tester,
        _Damier(
          touchees: touchees,
          evenements: evenements,
          controleur: controleur,
        ),
      );

      final geste = await tester.startGesture(centre(2));
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);
      await geste.moveTo(const Offset(200, 840));
      for (var image = 0; image < 60; image++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(controleur.offset, controleur.position.maxScrollExtent);
      expect(tester.takeException(), isNull);

      await geste.up();
      await tester.pumpAndSettle();
    });
  });
}
