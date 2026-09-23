import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/l10n/format_date.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/theme/app_theme.dart';
import 'package:astreinte_sp/core/widgets/case_attribution.dart';
import 'package:astreinte_sp/core/widgets/legende_etats.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:astreinte_sp/features/planning/domain/cle_cellule.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/planning/domain/matrice_mois.dart';
import 'package:astreinte_sp/features/planning/domain/planning_mois.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/grille_matrice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/widgets/helpers.dart';
import '../../support/faux_matrice.dart';
import '../../support/faux_planning.dart';

/// Un mois court, pour que la grille entière tienne dans la fenêtre du test.
const int _jours = 3;

/// Octobre 2026 : le 1er est un jeudi, le mois ne compte pas de férié.
final DateTime _aujourdhui = DateTime(2026, 10, 2);

/// Deux membres, deux déclarations différentes sur le 1er : l'un disponible,
/// l'autre absent. C'est la paire qui rend le cas intéressant — une astreinte
/// posée contre une absence doit se lire.
final List<LigneMatrice> _lignes = <LigneMatrice>[
  ligneMatrice(
    userId: 'u1',
    nom: 'Dubois Jean-Marc',
    jours: moisUniforme('D', jours: _jours),
    nuits: moisUniforme('D', jours: _jours),
  ),
  ligneMatrice(
    userId: 'u2',
    nom: 'Martin Sophie',
    jours: moisUniforme('A', jours: _jours),
    nuits: moisUniforme('.', jours: _jours),
  ),
];

PlanningMois _planning(List<Attribution> attributions) => PlanningMois(
  planning: planningBrouillon,
  creneaux: creneauxDuMois(_jours),
  attributions: attributions,
);

Attribution _attribution({
  required String id,
  required String creneauId,
  required String userId,
  AttributionEtat etat = AttributionEtat.propose,
}) => Attribution(id: id, creneauId: creneauId, userId: userId, etat: etat);

/// Ce qui s'est passé pendant le test : les cases cyclées, les créneaux
/// ouverts. Deux listes et non deux drapeaux — un appui qui déclenche les deux
/// est un défaut, et il faut le voir.
class _Journal {
  final List<CleCellule> cases = <CleCellule>[];
  final List<String> creneaux = <String>[];
}

Future<_Journal> _monterLaGrille(
  WidgetTester tester, {
  required PlanningMois planning,
  bool saisieActive = false,
  Set<CleCellule> erreurs = const <CleCellule>{},
}) async {
  final journal = _Journal();
  await monter(
    tester,
    GrilleMatrice(
      matrice: MatriceMois(lignes: _lignes, nombreDeJours: _jours),
      lignes: _lignes,
      annee: 2026,
      mois: 10,
      commentaires: false,
      aujourdhui: _aujourdhui,
      erreurs: erreurs,
      saisieActive: saisieActive,
      onCase: journal.cases.add,
      planning: planning,
      creneauSelectionne: null,
      onCreneau: journal.creneaux.add,
    ),
    // Au moins `expanded` : la densité dense n'est actionnable qu'au pointeur
    // fin, et c'est la largeur qui en tient lieu.
    taille: const Size(1440, 900),
  );
  await tester.pumpAndSettle();
  return journal;
}

/// La case d'un membre sur un jour et un créneau, par sa sémantique — la seule
/// désignation qui ne dépende pas de l'ordre de construction de la grille.
Finder _caseDe({
  required String membre,
  required int jour,
  required CreneauType creneau,
  required AttributionEtat etat,
  required DisponibiliteEtat disponibilite,
}) {
  const statuts = AppStatusColors.clair;
  return find.bySemanticsLabel(
    AppStrings.matriceCaseAttributionSemantique(
      membre: membre,
      jourEtDate: dateAvecJourSemaine(DateTime(2026, 10, jour)),
      creneau: statuts.creneau(creneau).libelle,
      etat: statuts.attribution(etat).libelle,
      disponibilite: statuts.disponibilite(disponibilite).libelle,
    ),
  );
}

BoxDecoration _decoration(WidgetTester tester, Finder caseAttribution) =>
    tester
            .widget<DecoratedBox>(
              find
                  .descendant(
                    of: caseAttribution,
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

void main() {
  group('CaseAttribution — l\'attribution se lit dans la case du membre', () {
    testWidgets('les trois états portent le fond, l\'encre et l\'icône de '
        'leur famille', (tester) async {
      await _monterLaGrille(
        tester,
        planning: _planning(<Attribution>[
          _attribution(id: 'a1', creneauId: 'c-1-j', userId: 'u1'),
          _attribution(
            id: 'a2',
            creneauId: 'c-2-j',
            userId: 'u1',
            etat: AttributionEtat.accepte,
          ),
          _attribution(
            id: 'a3',
            creneauId: 'c-3-j',
            userId: 'u1',
            etat: AttributionEtat.refuse,
          ),
        ]),
      );

      const statuts = AppStatusColors.clair;
      expect(find.byType(CaseAttribution), findsNWidgets(3));

      for (final (int jour, AttributionEtat etat) in <(int, AttributionEtat)>[
        (1, AttributionEtat.propose),
        (2, AttributionEtat.accepte),
        (3, AttributionEtat.refuse),
      ]) {
        final cible = _caseDe(
          membre: 'Dubois Jean-Marc',
          jour: jour,
          creneau: CreneauType.jour,
          etat: etat,
          disponibilite: DisponibiliteEtat.disponible,
        );
        final descripteur = statuts.attribution(etat);

        expect(cible, findsOneWidget, reason: 'État $etat absent.');
        expect(_decoration(tester, cible).color, descripteur.fond);

        // **Jamais la couleur seule** : l'icône de la famille est dans la
        // case, et les trois familles n'en partagent aucune.
        final glyphe = tester.widget<Icon>(
          find.descendant(of: cible, matching: find.byType(Icon)),
        );
        expect(glyphe.icon, descripteur.icone);
        expect(glyphe.color, descripteur.encre);

        // La case garde la mesure de la case dense du registre.
        expect(
          tester.getSize(cible),
          const Size(CaseAttribution.cote, CaseAttribution.cote),
        );
      }
    });

    testWidgets('« proposé » garde son contour ocre, « accepté » est plein', (
      tester,
    ) async {
      await _monterLaGrille(
        tester,
        planning: _planning(<Attribution>[
          _attribution(id: 'a1', creneauId: 'c-1-j', userId: 'u1'),
          _attribution(
            id: 'a2',
            creneauId: 'c-2-j',
            userId: 'u1',
            etat: AttributionEtat.accepte,
          ),
        ]),
      );

      final propose = _decoration(
        tester,
        _caseDe(
          membre: 'Dubois Jean-Marc',
          jour: 1,
          creneau: CreneauType.jour,
          etat: AttributionEtat.propose,
          disponibilite: DisponibiliteEtat.disponible,
        ),
      );
      expect(propose.border, isNotNull);

      final accepte = _decoration(
        tester,
        _caseDe(
          membre: 'Dubois Jean-Marc',
          jour: 2,
          creneau: CreneauType.jour,
          etat: AttributionEtat.accepte,
          disponibilite: DisponibiliteEtat.disponible,
        ),
      );
      expect(accepte.border, isNull);
    });

    testWidgets('la sémantique dit le membre, le jour, le créneau, l\'état et '
        'la disponibilité déclarée entre parenthèses', (tester) async {
      await _monterLaGrille(
        tester,
        // Sophie s'est déclarée **absente** le 1er : l'astreinte est posée
        // contre sa déclaration, et c'est exactement ce qu'un chef doit
        // entendre avant de décrocher son téléphone.
        planning: _planning(<Attribution>[
          _attribution(id: 'a1', creneauId: 'c-1-j', userId: 'u2'),
        ]),
      );

      expect(
        find.bySemanticsLabel(
          'Martin Sophie, jeudi 1er octobre, jour, en attente '
          '(disponibilité déclarée : absent)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('hors saisie, l\'appui ouvre le panneau du créneau', (
      tester,
    ) async {
      final journal = await _monterLaGrille(
        tester,
        planning: _planning(<Attribution>[
          _attribution(id: 'a1', creneauId: 'c-2-n', userId: 'u1'),
        ]),
      );

      await tester.tap(
        _caseDe(
          membre: 'Dubois Jean-Marc',
          jour: 2,
          creneau: CreneauType.nuit,
          etat: AttributionEtat.propose,
          disponibilite: DisponibiliteEtat.disponible,
        ),
      );
      await tester.pump();

      expect(journal.creneaux, <String>['c-2-n']);
      expect(journal.cases, isEmpty);
    });

    testWidgets('en mode de saisie armé, l\'appui cycle la disponibilité et '
        'le bloc reste affiché', (tester) async {
      final journal = await _monterLaGrille(
        tester,
        saisieActive: true,
        planning: _planning(<Attribution>[
          _attribution(id: 'a1', creneauId: 'c-2-n', userId: 'u1'),
        ]),
      );

      await tester.tap(
        _caseDe(
          membre: 'Dubois Jean-Marc',
          jour: 2,
          creneau: CreneauType.nuit,
          etat: AttributionEtat.propose,
          disponibilite: DisponibiliteEtat.disponible,
        ),
      );
      await tester.pump();

      expect(journal.cases, <CleCellule>[
        const CleCellule(userId: 'u1', jour: 2, creneau: CreneauType.nuit),
      ]);
      expect(journal.creneaux, isEmpty);
      expect(find.byType(CaseAttribution), findsOneWidget);
    });

    testWidgets('sans attribution, la case reste le SlotChip du registre', (
      tester,
    ) async {
      await _monterLaGrille(tester, planning: _planning(const <Attribution>[]));

      expect(find.byType(CaseAttribution), findsNothing);
      // Deux membres, trois jours, deux créneaux.
      expect(find.byType(SlotChip), findsNWidgets(_jours * 2 * 2));
    });

    testWidgets('une attribution annulée ou remplacée n\'occupe aucune case', (
      tester,
    ) async {
      await _monterLaGrille(
        tester,
        planning: _planning(<Attribution>[
          _attribution(
            id: 'a1',
            creneauId: 'c-1-j',
            userId: 'u1',
            etat: AttributionEtat.annule,
          ),
          _attribution(
            id: 'a2',
            creneauId: 'c-1-n',
            userId: 'u1',
            etat: AttributionEtat.remplace,
          ),
        ]),
      );

      expect(find.byType(CaseAttribution), findsNothing);
      expect(find.byType(SlotChip), findsNWidgets(_jours * 2 * 2));
    });

    testWidgets('un enregistrement en échec garde son contour d\'erreur sous '
        'le bloc', (tester) async {
      const cle = CleCellule(userId: 'u1', jour: 1, creneau: CreneauType.jour);
      await _monterLaGrille(
        tester,
        erreurs: <CleCellule>{cle},
        planning: _planning(<Attribution>[
          _attribution(id: 'a1', creneauId: 'c-1-j', userId: 'u1'),
        ]),
      );

      final bordure =
          _decoration(
                tester,
                _caseDe(
                  membre: 'Dubois Jean-Marc',
                  jour: 1,
                  creneau: CreneauType.jour,
                  etat: AttributionEtat.propose,
                  disponibilite: DisponibiliteEtat.disponible,
                ),
              ).border!
              as Border;
      expect(bordure.top.color, AppTheme.clair.colorScheme.error);
    });
  });

  group('LegendeEtats — les deux familles ne se mélangent pas', () {
    testWidgets('la légende des attributions nomme les trois états, marque '
        'décorative et libellé seul annoncé', (tester) async {
      await monter(
        tester,
        const LegendeEtats.attributions(),
        taille: const Size(1440, 900),
      );

      expect(find.byType(CaseAttribution), findsNWidgets(3));
      expect(find.byType(SlotChip), findsNothing);
      for (final etat in LegendeEtats.etatsAttribution) {
        final libelle = AppStatusColors.clair.attribution(etat).libelle;
        expect(find.text(libelle), findsOneWidget);
        // Une entrée, un nœud : la marque est exclue, le mot reste.
        expect(find.bySemanticsLabel(libelle), findsOneWidget);
      }
    });

    testWidgets('la légende des disponibilités ne change pas', (tester) async {
      await monter(tester, const LegendeEtats());

      expect(find.byType(SlotChip), findsNWidgets(3));
      expect(find.byType(CaseAttribution), findsNothing);
    });
  });
}
