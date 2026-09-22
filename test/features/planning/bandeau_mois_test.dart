import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/theme/app_colors.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/theme/app_theme.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/planning_mois.dart';
import 'package:astreinte_sp/features/planning/domain/resume_mois.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/bandeau_mois.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/barre_repartition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/widgets/helpers.dart';
import '../../support/faux_planning.dart';

/// Un mois de deux jours : quatre créneaux, assez pour exercer les quatre
/// familles sans écrire soixante-deux lignes.
const int _jours = 2;

PlanningMois _planning({
  List<CreneauPlanning>? creneaux,
  List<Attribution> attributions = const <Attribution>[],
  PlanningEtat etat = PlanningEtat.brouillon,
}) => PlanningMois(
  planning: PlanningBrouillon(id: 'plan-1', etat: etat),
  creneaux: creneaux ?? creneauxDuMois(_jours),
  attributions: attributions,
);

Attribution _attribution(
  String creneauId, {
  String userId = 'u1',
  AttributionEtat etat = AttributionEtat.propose,
}) => Attribution(
  id: 'a-$creneauId-$userId',
  creneauId: creneauId,
  userId: userId,
  etat: etat,
);

void main() {
  group('ResumeMois — les comptes du mois', () {
    test('sans planning, tout le mois est non saisi', () {
      final resume = ResumeMois.construire(
        planning: PlanningMois.vide(),
        nombreDeJours: 31,
      );

      expect(resume.nonSaisis, 62);
      expect(resume.couverts, 0);
      expect(resume.manquants, 0);
      expect(resume.enAttente, 0);
      expect(resume.total, 62);
    });

    test('un créneau attribué est couvert, les autres sont à pourvoir', () {
      final resume = ResumeMois.construire(
        planning: _planning(
          attributions: <Attribution>[_attribution('c-1-j')],
        ),
        nombreDeJours: _jours,
      );

      expect(resume.couverts, 1);
      expect(resume.aPourvoir, 3);
      expect(resume.manquants, 3);
      expect(resume.nonSaisis, 0);
      expect(resume.total, _jours * 2);
    });

    test('un effectif requis à zéro n\'est pas un trou', () {
      final resume = ResumeMois.construire(
        planning: _planning(creneaux: creneauxDuMois(_jours, effectifRequis: 0)),
        nombreDeJours: _jours,
      );

      expect(resume.nonSaisis, 4);
      expect(resume.manquants, 0);
    });

    test('un créneau à deux requis n\'est couvert qu\'à deux', () {
      final creneaux = <CreneauPlanning>[
        creneau(id: 'c-1-j', jour: 1, effectifRequis: 2),
        creneau(
          id: 'c-1-n',
          jour: 1,
          creneau: CreneauType.nuit,
          effectifRequis: 2,
        ),
      ];
      final unSeul = ResumeMois.construire(
        planning: _planning(
          creneaux: creneaux,
          attributions: <Attribution>[_attribution('c-1-j')],
        ),
        nombreDeJours: 1,
      );
      expect(unSeul.couverts, 0);
      expect(unSeul.aPourvoir, 2);

      final lesDeux = ResumeMois.construire(
        planning: _planning(
          creneaux: creneaux,
          attributions: <Attribution>[
            _attribution('c-1-j'),
            _attribution('c-1-j', userId: 'u2'),
          ],
        ),
        nombreDeJours: 1,
      );
      expect(lesDeux.couverts, 1);
      expect(lesDeux.aPourvoir, 1);
    });

    test('en brouillon, personne n\'attend de réponse', () {
      final resume = ResumeMois.construire(
        planning: _planning(
          attributions: <Attribution>[
            _attribution('c-1-j'),
            _attribution('c-1-n'),
          ],
        ),
        nombreDeJours: _jours,
      );

      expect(resume.enAttente, 0);
      expect(resume.couverts, 2);
    });

    test('publié, une proposition sans réponse est une réponse en attente', () {
      final resume = ResumeMois.construire(
        planning: _planning(
          etat: PlanningEtat.publie,
          attributions: <Attribution>[
            _attribution('c-1-j'),
            _attribution('c-1-n', etat: AttributionEtat.accepte),
          ],
        ),
        nombreDeJours: _jours,
      );

      expect(resume.enAttente, 1);
      expect(resume.couverts, 2);
    });

    test('un refus laisse le créneau à réattribuer, pas à pourvoir', () {
      final resume = ResumeMois.construire(
        planning: _planning(
          etat: PlanningEtat.publie,
          attributions: <Attribution>[
            _attribution('c-1-j', etat: AttributionEtat.refuse),
          ],
        ),
        nombreDeJours: _jours,
      );

      expect(resume.refuses, 1);
      expect(resume.aPourvoir, 3);
      expect(resume.manquants, 4);
      expect(resume.couverts, 0);
    });

    test('les quatre familles couvrent le mois entier, sans recoupement', () {
      final resume = ResumeMois.construire(
        planning: _planning(
          etat: PlanningEtat.publie,
          creneaux: <CreneauPlanning>[
            creneau(id: 'c-1-j', jour: 1),
            creneau(id: 'c-1-n', jour: 1, creneau: CreneauType.nuit),
            creneau(id: 'c-2-j', jour: 2, effectifRequis: 0),
            creneau(
              id: 'c-2-n',
              jour: 2,
              creneau: CreneauType.nuit,
            ),
          ],
          attributions: <Attribution>[
            _attribution('c-1-j', etat: AttributionEtat.accepte),
            _attribution('c-1-n', etat: AttributionEtat.refuse),
          ],
        ),
        nombreDeJours: _jours,
      );

      expect(resume.couverts, 1);
      expect(resume.refuses, 1);
      expect(resume.nonSaisis, 1);
      expect(resume.aPourvoir, 1);
      expect(resume.total, 4);
    });
  });

  group('BandeauMois — ce que le chef lit avant de défiler', () {
    const resume = ResumeMois(
      couverts: 40,
      aPourvoir: 15,
      refuses: 5,
      nonSaisis: 2,
      enAttente: 7,
    );

    testWidgets('trois chiffres, leur libellé, et le mois en titre', (
      tester,
    ) async {
      await monter(
        tester,
        const BandeauMois(resume: resume, mois: 10, annee: 2026),
        taille: const Size(1280, 900),
      );

      expect(find.text(AppStrings.moisNomEtAnnee(10, 2026)), findsOneWidget);
      expect(find.text(AppStrings.bandeauCouverts), findsOneWidget);
      expect(find.text(AppStrings.bandeauAPourvoir), findsOneWidget);
      expect(find.text(AppStrings.bandeauEnAttente), findsOneWidget);

      expect(find.text('40'), findsWidgets);
      // « À pourvoir » compte les refus avec ce qui manque : 15 + 5.
      expect(find.text('20'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('la barre a quatre parts proportionnelles, chacune avec sa '
        'ligne de légende', (tester) async {
      await monter(
        tester,
        const BandeauMois(resume: resume, mois: 10, annee: 2026),
        taille: const Size(1280, 900),
      );

      final parts = tester
          .widget<BarreRepartition>(find.byType(BarreRepartition))
          .parts;
      expect(parts.map((PartDuMois p) => p.valeur).toList(), <int>[
        40,
        15,
        5,
        2,
      ]);

      // Les teintes vives de la charte, en remplissage seulement.
      expect(parts[0].couleur, AppTheme.clair.colorScheme.secondary);
      expect(parts[1].couleur, AppColors.orangeVif);
      expect(parts[2].couleur, AppColors.roseVif);
      expect(parts[3].couleur, AppColors.etatNonSaisi);

      // La proportion est portée par la largeur peinte : 40 contre 2.
      final flexs = tester
          .widgetList<Expanded>(
            find.descendant(
              of: find.byType(BarreRepartition),
              matching: find.byType(Expanded),
            ),
          )
          .map((Expanded e) => e.flex)
          .toList();
      expect(flexs, <int>[40, 15, 5, 2]);

      // La légende double la couleur d'une icône, d'un libellé et du nombre.
      for (final libelle in <String>[
        AppStrings.bandeauPartCouverts,
        AppStrings.bandeauPartARemplir,
        AppStrings.bandeauPartAReattribuer,
        AppStrings.bandeauPartNonSaisis,
      ]) {
        expect(find.text(libelle), findsOneWidget);
      }
      expect(find.byIcon(Icons.done_all), findsOneWidget);
      expect(find.byIcon(Icons.person_search), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    });

    testWidgets('une part nulle ne prend ni pixel ni ligne de légende', (
      tester,
    ) async {
      await monter(
        tester,
        const BandeauMois(
          resume: ResumeMois(
            couverts: 10,
            aPourvoir: 0,
            refuses: 0,
            nonSaisis: 0,
            enAttente: 0,
          ),
          mois: 10,
          annee: 2026,
        ),
        taille: const Size(1280, 900),
      );

      expect(find.text(AppStrings.bandeauPartCouverts), findsOneWidget);
      expect(find.text(AppStrings.bandeauPartAReattribuer), findsNothing);
      expect(find.byIcon(Icons.swap_horiz), findsNothing);
    });

    testWidgets('en compact, une ligne de trois chiffres et rien d\'autre', (
      tester,
    ) async {
      await monter(
        tester,
        const BandeauMois(
          resume: resume,
          mois: 10,
          annee: 2026,
          compact: true,
        ),
      );

      expect(find.text(AppStrings.bandeauCouverts), findsOneWidget);
      expect(find.byType(BarreRepartition), findsNothing);
      expect(find.text(AppStrings.moisNomEtAnnee(10, 2026)), findsNothing);
    });

    testWidgets('sombre : le bandeau tient sans exception', (tester) async {
      await monter(
        tester,
        const BandeauMois(resume: resume, mois: 10, annee: 2026),
        taille: const Size(1280, 900),
        brightness: Brightness.dark,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(BarreRepartition), findsOneWidget);
    });
  });
}
