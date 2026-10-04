import 'dart:math';

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/theme/app_theme.dart';
import 'package:astreinte_sp/core/widgets/case_attribution.dart';
import 'package:astreinte_sp/core/widgets/coin_ailleurs.dart';
import 'package:astreinte_sp/core/widgets/legende_etats.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:astreinte_sp/features/planning/domain/candidat.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/domain/planning_mois.dart';
import 'package:astreinte_sp/features/planning/domain/proposition_automatique.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/ligne_candidat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/widgets/helpers.dart';
import '../../support/faux_matrice.dart';
import '../../support/faux_planning.dart';

/// Ticket 072, décision 1 du propriétaire, côté admin : « Astreinte
/// ailleurs », lue dans `availability_matrix` (migration `0040`).

/// Octobre 2026, 31 jours : `X` les jours nommés, `.` ailleurs.
String _ailleurs(Iterable<int> jours) {
  final cases = List<String>.filled(31, '.');
  for (final jour in jours) {
    cases[jour - 1] = 'X';
  }
  return cases.join();
}

LigneMatrice _membre(
  String id,
  String nom, {
  String ailleursJours = '',
  int accepteesPrecedentes = 0,
}) => ligneMatrice(
  userId: id,
  nom: nom,
  jours: moisUniforme('D'),
  nuits: moisUniforme('D'),
  ailleursJours: ailleursJours,
  accepteesPrecedentes: accepteesPrecedentes,
);

PlanningMois _planning(List<CreneauPlanning> creneaux) => PlanningMois(
  planning: planningBrouillon,
  creneaux: creneaux,
  attributions: const <Attribution>[],
);

double _luminance(Color couleur) {
  double canal(double v) =>
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * canal(couleur.r) +
      0.7152 * canal(couleur.g) +
      0.0722 * canal(couleur.b);
}

double _ratio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  group('La lecture de availability_matrix', () {
    test('day_taken_elsewhere et night_taken_elsewhere se lisent par jour', () {
      final ligne = LigneMatrice.depuisJson(<String, dynamic>{
        'user_id': 'u-1',
        'display_name': 'Marie L.',
        'day_slots': moisUniforme('D'),
        'night_slots': moisUniforme('.'),
        'day_taken_elsewhere': _ailleurs(<int>[4]),
        'night_taken_elsewhere': _ailleurs(<int>[31]),
      });

      expect(ligne.ailleurs(4, CreneauType.jour), isTrue);
      expect(ligne.ailleurs(4, CreneauType.nuit), isFalse);
      expect(ligne.ailleurs(31, CreneauType.nuit), isTrue);
      expect(ligne.ailleurs(32, CreneauType.nuit), isFalse);
      expect(ligne.aUneAstreinteAilleurs, isTrue);

      // Une écriture optimiste ou une charge recomptée ne perd pas la marque.
      final apres = ligne
          .avec(4, CreneauType.jour, CelluleMatrice.absentParAdmin)
          .avecCharge(astreintes: 3, unitesWeekend: 1);
      expect(apres.ailleurs(4, CreneauType.jour), isTrue);
    });

    test('une base sans la migration 0040 : rien n\'est pris ailleurs', () {
      final ligne = LigneMatrice.depuisJson(<String, dynamic>{
        'user_id': 'u-1',
        'day_slots': moisUniforme('D'),
        'night_slots': moisUniforme('D'),
      });
      expect(ligne.aUneAstreinteAilleurs, isFalse);
      expect(ligne.ailleurs(1, CreneauType.jour), isFalse);
    });
  });

  group('Le panneau des candidats', () {
    test('pris ailleurs : en fin des disponibles, jamais retiré', () {
      final panneau = PanneauCandidats.construire(
        creneau: creneau(id: 'c-4-j', jour: 4),
        jour: DateTime(2026, 10, 4),
        membres: <LigneMatrice>[
          // Le mieux classé par le tri du 017 (aucune astreinte récente)…
          _membre('u-a', 'Anne', ailleursJours: _ailleurs(<int>[4])),
          _membre('u-b', 'Bruno', accepteesPrecedentes: 5),
        ],
        planning: _planning(<CreneauPlanning>[creneau(id: 'c-4-j', jour: 4)]),
        modifiable: true,
      );

      expect(panneau.disponibles.map((Candidat c) => c.userId), <String>[
        'u-b',
        'u-a',
      ]);
      expect(panneau.disponibles.last.ailleurs, isTrue);
      expect(panneau.disponibles.first.ailleurs, isFalse);
    });

    testWidgets('la ligne le dit, et propose « Attribuer quand même »', (
      tester,
    ) async {
      final candidat = Candidat(
        membre: _membre('u-a', 'Anne'),
        disponibilite: DisponibiliteEtat.disponible,
        ailleurs: true,
      );
      var appuis = 0;
      await monter(
        tester,
        LigneCandidat(
          candidat: candidat,
          action: ActionCandidat.attribuer,
          onAction: () => appuis++,
        ),
      );

      expect(find.text(AppStrings.candidatAilleurs), findsOneWidget);
      expect(find.text(AppStrings.planningAttribuerQuandMeme), findsOneWidget);
      // Sans dialogue : l'information est sur la ligne avant le geste.
      await tester.tap(find.text(AppStrings.planningAttribuerQuandMeme));
      await tester.pump();
      expect(appuis, 1);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('La proposition automatique', () {
    test('ne désigne pas qui a une astreinte ailleurs sur ce créneau', () {
      final proposition = PropositionAutomatique.construire(
        planning: _planning(<CreneauPlanning>[
          creneau(id: 'c-4-j', jour: 4),
          creneau(id: 'c-5-j', jour: 5),
        ]),
        lignes: <LigneMatrice>[
          _membre('u-a', 'Anne', ailleursJours: _ailleurs(<int>[4, 5])),
        ],
        annee: 2026,
        mois: 10,
      );

      // Seule candidate des deux créneaux, et prise ailleurs sur les deux :
      // ils restent à découvert, comme la base les laisserait.
      expect(proposition.choix, isEmpty);
      expect(proposition.decouverts, hasLength(2));
    });

    test('la garantie le dit', () {
      expect(AppStrings.proposerPromesse, contains('autre caserne'));
    });
  });

  group('La marque', () {
    testWidgets('coin rabattu et phrase sur la case de disponibilité', (
      tester,
    ) async {
      final semantique = tester.ensureSemantics();
      await monter(
        tester,
        const SlotChip(
          etat: DisponibiliteEtat.disponible,
          creneau: CreneauType.nuit,
          densite: SlotChipDensite.compacte,
          ailleurs: true,
          libelleSemantique:
              'Marie Lefebvre, samedi 4 octobre, nuit, '
              'disponible',
        ),
      );

      expect(find.byType(CoinAilleurs), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Marie Lefebvre, samedi 4 octobre, nuit, disponible, '
          '${AppStrings.matriceCaseAilleursSemantique}',
        ),
        findsOneWidget,
      );
      semantique.dispose();
    });

    testWidgets('et sur le bloc d\'attribution ; rien sans la marque', (
      tester,
    ) async {
      await monter(
        tester,
        const Row(
          children: <Widget>[
            CaseAttribution(
              etat: AttributionEtat.propose,
              ailleurs: true,
              libelleSemantique: 'Marie',
            ),
            CaseAttribution(
              etat: AttributionEtat.accepte,
              libelleSemantique: 'Paul',
            ),
          ],
        ),
      );
      expect(find.byType(CoinAilleurs), findsOneWidget);
    });

    testWidgets('la légende a son entrée', (tester) async {
      await monter(tester, const LegendeAilleurs());
      expect(find.text(AppStrings.matriceLegendeAilleurs), findsOneWidget);
      expect(find.byType(CoinAilleurs), findsOneWidget);
    });

    test('le coin se lit sur les six fonds, en clair et en sombre', () {
      for (final theme in <ThemeData>[AppTheme.clair, AppTheme.sombre]) {
        final statuts = theme.extension<AppStatusColors>()!;
        final fonds = <String, Color>{
          for (final etat in DisponibiliteEtat.values)
            'disponibilité ${etat.name}': statuts.disponibilite(etat).fond,
          for (final etat in <AttributionEtat>[
            AttributionEtat.propose,
            AttributionEtat.accepte,
            AttributionEtat.refuse,
          ])
            'attribution ${etat.name}': statuts.attribution(etat).blocFond,
        };
        for (final MapEntry<String, Color>(:key, :value) in fonds.entries) {
          final (encre, lisere) = CoinAilleurs.encres(theme.colorScheme, value);
          expect(
            _ratio(encre, value),
            greaterThanOrEqualTo(3),
            reason: '${theme.brightness.name}, $key',
          );
          // Le liseré détache le coin du fond : il est l'autre encre.
          expect(lisere, isNot(encre));
        }
      }
    });
  });
}
