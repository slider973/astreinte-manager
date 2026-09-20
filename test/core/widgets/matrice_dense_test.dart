import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// La plage maximale du brief § 5 : 60 membres × 31 jours × 2 créneaux.
const int _membres = 60;
const int _colonnes = 62;
const int _cases = _membres * _colonnes; // 3 720

/// Garde-fou, **pas un budget**.
///
/// Les durées imprimées par ce fichier viennent d'un test de widgets en mode
/// debug : les assertions et l'absence de JIT chaud dominent, et la mesure
/// double quand la suite tourne en parallèle sur toutes les cœurs. Elles sont
/// consignées dans `DESIGN.md § Coût de la case dense` pour ce qu'elles
/// valent — un repère d'ordre de grandeur.
///
/// Le vrai budget du ticket 016 se mesurera sur un build `--profile` dans un
/// navigateur. Ici, le seuil ne sert qu'à faire échouer un blocage ou une
/// régression d'un facteur dix ; ce qui est réellement vérifié, c'est le
/// **coût structurel**, lui parfaitement déterministe.
const int _gardeFou = 10000;

/// Une ligne de la matrice : un membre, 62 créneaux.
Widget _ligne(int ligne, {required bool actionnable}) => Row(
  children: <Widget>[
    for (var colonne = 0; colonne < _colonnes; colonne++)
      Padding(
        padding: const EdgeInsets.only(right: 2),
        child: SlotChip(
          etat: DisponibiliteEtat.values[(ligne + colonne) % 3],
          creneau: CreneauType.values[colonne.isEven ? 0 : 1],
          densite: SlotChipDensite.dense,
          onTap: actionnable ? () {} : null,
          libelleSemantique: 'Membre $ligne, créneau $colonne',
        ),
      ),
  ],
);

/// La matrice **telle que le ticket 016 la construira** : lignes virtualisées.
/// Seules les lignes visibles sont construites.
Widget _matriceVirtualisee({required bool actionnable}) => ListView.builder(
  itemCount: _membres,
  itemExtent: SlotChipDensite.dense.taille + 2,
  itemBuilder: (context, ligne) => _ligne(ligne, actionnable: actionnable),
);

/// Le **pire cas absolu** : les 3 720 cases construites d'un coup, sans
/// virtualisation. Ce n'est pas ce que fera le ticket 016 ; c'est la borne
/// haute qui dit combien coûte une case.
Widget _matriceComplete({required bool actionnable}) => SingleChildScrollView(
  child: Column(
    children: <Widget>[
      for (var ligne = 0; ligne < _membres; ligne++)
        _ligne(ligne, actionnable: actionnable),
    ],
  ),
);

void main() {
  group('Matrice dense — budget du ticket 016', () {
    testWidgets('les $_cases cases se construisent sans exception', (
      tester,
    ) async {
      await monter(
        tester,
        _matriceComplete(actionnable: false),
        // Fenêtre de poste admin : la seule où la densité dense est servie.
        taille: const Size(1920, 1080),
      );

      expect(find.byType(SlotChip, skipOffstage: false), findsNWidgets(_cases));
      expect(tester.takeException(), isNull);
    });

    testWidgets('mesure : coût structurel d\'une case dense', (tester) async {
      Future<(int, int, int)> compter({required bool actionnable}) async {
        await monter(
          tester,
          Align(
            child: SlotChip(
              etat: DisponibiliteEtat.disponible,
              creneau: CreneauType.jour,
              densite: SlotChipDensite.dense,
              onTap: actionnable ? () {} : null,
              libelleSemantique: 'Membre 1, créneau 1',
            ),
          ),
          taille: const Size(1920, 1080),
        );

        var elements = 0;
        var rendus = 0;
        var etats = 0;
        void visiter(Element element) {
          elements++;
          if (element is RenderObjectElement) rendus++;
          if (element is StatefulElement) etats++;
          element.visitChildren(visiter);
        }

        visiter(tester.element(find.byType(SlotChip)));
        return (elements, rendus, etats);
      }

      final inerte = await compter(actionnable: false);
      final active = await compter(actionnable: true);

      // ignore: avoid_print
      print(
        'MESURE structure, case dense inerte : ${inerte.$1} éléments, '
        '${inerte.$2} objets de rendu, ${inerte.$3} States',
      );
      // ignore: avoid_print
      print(
        'MESURE structure, case dense actionnable : ${active.$1} éléments, '
        '${active.$2} objets de rendu, ${active.$3} States',
      );

      // Une case inerte est le cas de très loin le plus fréquent dans la
      // matrice : elle ne doit coûter aucun State.
      expect(
        inerte.$3,
        0,
        reason: 'Une case dense inerte ne doit créer aucun State.',
      );
    });

    testWidgets('la case dense en lecture seule est purement sans état', (
      tester,
    ) async {
      await monter(
        tester,
        const Align(
          child: SlotChip(
            etat: DisponibiliteEtat.disponible,
            creneau: CreneauType.jour,
            densite: SlotChipDensite.dense,
            libelleSemantique: 'Membre 1, créneau 1',
          ),
        ),
        taille: const Size(1920, 1080),
      );

      // Aucun State, aucun nœud de focus, aucun détecteur de geste, aucun
      // MetaData : il ne reste que la peinture et la sémantique.
      for (final type in <Type>[
        Focus,
        MouseRegion,
        GestureDetector,
        MetaData,
        TweenAnimationBuilder<double>,
      ]) {
        expect(
          find.descendant(
            of: find.byType(SlotChip),
            matching: find.byType(type),
          ),
          findsNothing,
          reason: '$type ne devrait pas exister dans une case dense inerte.',
        );
      }
      expect(
        find.descendant(
          of: find.byType(SlotChip),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
    });

    testWidgets('mesure : $_cases cases inertes construites d\'un coup', (
      tester,
    ) async {
      final chrono = Stopwatch()..start();
      await monter(
        tester,
        _matriceComplete(actionnable: false),
        taille: const Size(1920, 1080),
      );
      chrono.stop();

      // ignore: avoid_print
      print(
        'MESURE inerte, sans virtualisation : $_cases cases, première image '
        'en ${chrono.elapsedMilliseconds} ms '
        '(${(chrono.elapsedMicroseconds / _cases).toStringAsFixed(0)} µs/case)',
      );

      expect(tester.takeException(), isNull);
      expect(chrono.elapsedMilliseconds, lessThan(_gardeFou));
    });

    testWidgets('mesure : $_cases cases actionnables construites d\'un coup', (
      tester,
    ) async {
      // Borne haute, sans virtualisation. Consignée dans
      // `DESIGN.md § Écarts d'implémentation`. Le seuil est large exprès : il
      // détecte une régression d'un ordre de grandeur, il ne fige pas la
      // performance d'une machine de test.
      final chrono = Stopwatch()..start();
      await monter(
        tester,
        _matriceComplete(actionnable: true),
        taille: const Size(1920, 1080),
      );
      chrono.stop();

      final construites = find
          .byType(SlotChip, skipOffstage: false)
          .evaluate()
          .length;
      // ignore: avoid_print
      print(
        'MESURE actionnable, sans virtualisation : $construites cases, première '
        'image en ${chrono.elapsedMilliseconds} ms '
        '(${(chrono.elapsedMicroseconds / construites).toStringAsFixed(0)} µs/case)',
      );

      expect(construites, _cases);
      expect(tester.takeException(), isNull);
      expect(chrono.elapsedMilliseconds, lessThan(_gardeFou));
    });

    testWidgets('mesure : matrice virtualisée, comme au ticket 016', (
      tester,
    ) async {
      final chrono = Stopwatch()..start();
      await monter(
        tester,
        _matriceVirtualisee(actionnable: true),
        taille: const Size(1920, 1080),
      );
      chrono.stop();

      final construites = find
          .byType(SlotChip, skipOffstage: false)
          .evaluate()
          .length;
      // ignore: avoid_print
      print(
        'MESURE virtualisée : $construites cases construites sur $_cases, première '
        'image en ${chrono.elapsedMilliseconds} ms',
      );

      expect(tester.takeException(), isNull);
      expect(chrono.elapsedMilliseconds, lessThan(_gardeFou));
    });

    testWidgets('mesure : défilement d\'une matrice virtualisée', (
      tester,
    ) async {
      await monter(
        tester,
        _matriceVirtualisee(actionnable: true),
        taille: const Size(1920, 1080),
      );

      final chrono = Stopwatch()..start();
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      chrono.stop();

      // ignore: avoid_print
      print('MESURE défilement : ${chrono.elapsedMilliseconds} ms');

      expect(tester.takeException(), isNull);
      expect(chrono.elapsedMilliseconds, lessThan(_gardeFou));
    });
  });
}
