import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/planning/data/planning_repository.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_matrice.dart';
import '../../support/faux_planning.dart';
import '../../support/faux_suivi.dart';

const String _chemin = '/admin/planning';

/// Un poste d'administration : la proposition automatique se lance de là.
const Size _poste = Size(1440, 900);

final DateTime _maintenant = DateTime.now();
final DateTime _moisAffiche = DateTime(_maintenant.year, _maintenant.month);

int get _joursDuMois =>
    DateTime(_moisAffiche.year, _moisAffiche.month + 1, 0).day;

PeriodeSaisie _periode() =>
    periodeOuverte(annee: _moisAffiche.year, mois: _moisAffiche.month);

/// Deux pompiers disponibles le 1er, un troisième qui n'a rien saisi.
List<LigneMatrice> _membres() {
  final reste = '.' * (_joursDuMois - 1);
  return <LigneMatrice>[
    ligneMatrice(
      userId: 'aubry',
      nom: 'Aubry I.',
      jours: 'D$reste',
      nuits: 'D$reste',
      maxAstreintes: 5,
    ),
    ligneMatrice(
      userId: 'camus',
      nom: 'Camus A.',
      jours: 'D$reste',
      nuits: 'D$reste',
      maxAstreintes: 5,
    ),
    ligneMatrice(
      userId: 'dupuis',
      nom: 'Dupuis T.',
      jours: '.$reste',
      nuits: '.$reste',
    ),
  ];
}

/// Un brouillon de quatre créneaux : deux le 1er, que quelqu'un peut tenir, et
/// deux le 2, où personne ne s'est déclaré.
FauxPlanningRepository _brouillon() => FauxPlanningRepository(
  planning: planningBrouillon,
  creneaux: <CreneauPlanning>[
    creneau(id: 'c-1-j', jour: 1),
    creneau(id: 'c-1-n', jour: 1, creneau: CreneauType.nuit),
    creneau(id: 'c-2-j', jour: 2),
    creneau(id: 'c-2-n', jour: 2, creneau: CreneauType.nuit),
  ],
);

Future<FauxPlanningRepository> _ouvrir(
  WidgetTester tester, {
  FauxPlanningRepository? depot,
  Appartenance appartenance = appartenanceAdmin,
}) async {
  final planning = depot ?? _brouillon();
  final suivi = FauxSuiviRepository();
  addTearDown(planning.fermer);
  addTearDown(suivi.fermer);

  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    dispos: FauxDisposRepository(periodes: <PeriodeSaisie>[_periode()]),
    matrice: FauxMatriceRepository(lignes: _membres()),
    planning: planning,
    suivi: suivi,
    taille: _poste,
  );
  await ouvrirRoute(tester, _chemin);
  return planning;
}

Future<void> _ouvrirProposition(WidgetTester tester) async {
  await tester.ensureVisible(find.text(AppStrings.proposerAction));
  await tester.tap(find.text(AppStrings.proposerAction));
  await tester.pumpAndSettle();
}

void main() {
  group('Proposer automatiquement — le bouton', () {
    testWidgets('il est là tant qu\'un créneau reste à pourvoir', (
      tester,
    ) async {
      await _ouvrir(tester);
      expect(find.text(AppStrings.proposerAction), findsOneWidget);
    });

    testWidgets('sur un mois complet, il disparaît : un bouton qui ne fait '
        'rien est un bouton qui ment', (tester) async {
      await _ouvrir(
        tester,
        depot: FauxPlanningRepository(
          planning: planningBrouillon,
          creneaux: <CreneauPlanning>[creneau(id: 'c-1-j', jour: 1)],
          attributions: const <Attribution>[
            Attribution(id: 'a1', creneauId: 'c-1-j', userId: 'aubry'),
          ],
        ),
      );

      expect(find.text(AppStrings.proposerAction), findsNothing);
    });

    testWidgets('sans planning créé, il n\'y a rien à remplir', (tester) async {
      await _ouvrir(
        tester,
        depot: FauxPlanningRepository(joursDuMoisACreer: _joursDuMois),
      );

      expect(find.text(AppStrings.proposerAction), findsNothing);
    });

    testWidgets('sur un planning publié, il disparaît', (tester) async {
      await _ouvrir(
        tester,
        depot: FauxPlanningRepository(
          planning: const PlanningBrouillon(
            id: 'plan-1',
            etat: PlanningEtat.publie,
          ),
          creneaux: <CreneauPlanning>[creneau(id: 'c-1-j', jour: 1)],
        ),
      );

      expect(find.text(AppStrings.proposerAction), findsNothing);
    });
  });

  group('Proposer automatiquement — le récapitulatif', () {
    testWidgets('il chiffre ce qui se remplit et nomme ce qui reste vide', (
      tester,
    ) async {
      await _ouvrir(tester);
      await _ouvrirProposition(tester);

      // Deux créneaux du 1er remplis, deux astreintes posées, deux créneaux du
      // 2 sans candidat : les trois nombres du ticket.
      expect(find.text(AppStrings.proposerCreneauxRemplis), findsOneWidget);
      expect(find.text(AppStrings.proposerAstreintes), findsOneWidget);
      expect(find.text(AppStrings.proposerDecouverts), findsOneWidget);
      expect(find.text(AppStrings.proposerSansCandidat(2)), findsOneWidget);
      // La promesse du ticket, écrite avant qu'on la croie.
      expect(find.text(AppStrings.proposerPromesse), findsOneWidget);
      // Le bouton porte le compte.
      expect(find.text(AppStrings.proposerConfirmer(2)), findsOneWidget);
    });

    testWidgets('« Annuler » n\'applique rien', (tester) async {
      final planning = await _ouvrir(tester);
      await _ouvrirProposition(tester);

      await tester.tap(find.text(AppStrings.proposerAnnuler));
      await tester.pumpAndSettle();

      expect(planning.propositions, isEmpty);
      expect(find.text(AppStrings.proposerAction), findsOneWidget);
    });

    testWidgets('quand personne n\'est disponible, une phrase suffit : pas de '
        'feuille vide', (tester) async {
      await _ouvrir(
        tester,
        depot: FauxPlanningRepository(
          planning: planningBrouillon,
          creneaux: <CreneauPlanning>[creneau(id: 'c-2-j', jour: 2)],
        ),
      );

      await tester.tap(find.text(AppStrings.proposerAction));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.proposerRienATrouver), findsOneWidget);
      expect(find.text(AppStrings.proposerCreneauxRemplis), findsNothing);
    });
  });

  group('Proposer automatiquement — l\'application', () {
    testWidgets('elle envoie le plan calculé, dans l\'ordre du mois', (
      tester,
    ) async {
      final planning = await _ouvrir(tester);
      await _ouvrirProposition(tester);

      await tester.tap(find.text(AppStrings.proposerConfirmer(2)));
      await tester.pumpAndSettle();

      expect(planning.propositions, hasLength(1));
      expect(
        planning.propositions.single.map(
          (Map<String, String> ligne) => ligne['shift_id'],
        ),
        <String>['c-1-j', 'c-1-n'],
        reason: 'le jour avant la nuit, et rien du 2 où personne n\'a saisi',
      );
      // **Deux pompiers différents**, parce que la charge du mois départage
      // deux plafonds égaux.
      expect(
        planning.propositions.single
            .map((Map<String, String> ligne) => ligne['user_id'])
            .toSet(),
        <String>{'aubry', 'camus'},
      );
    });

    testWidgets('elle annonce ce que la base a fait, pas ce qui était prévu', (
      tester,
    ) async {
      final planning = await _ouvrir(tester);
      await _ouvrirProposition(tester);

      await tester.tap(find.text(AppStrings.proposerConfirmer(2)));
      await tester.pumpAndSettle();

      // Deux posées, deux créneaux du 2 encore à découvert.
      expect(find.text(AppStrings.proposerFait(2, 2)), findsOneWidget);
      expect(planning.attributionsPosees, hasLength(2));
    });

    testWidgets('une ligne écartée par la base se dit, sans l\'annoncer '
        'comme une panne', (tester) async {
      // L'adjoint a rempli le créneau de jour pendant qu'on regardait.
      final depot = _brouillon()..propositionEcartees = <int>{0};
      final planning = await _ouvrir(tester, depot: depot);
      await _ouvrirProposition(tester);

      await tester.tap(find.text(AppStrings.proposerConfirmer(2)));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.proposerFaitPartiel(1, 1)), findsOneWidget);
      expect(planning.attributionsPosees, hasLength(1));
    });

    testWidgets('un échec du serveur laisse la feuille ouverte et le planning '
        'intact', (tester) async {
      final depot = _brouillon()..erreurEcriture = ErreurPlanning.reseau;
      final planning = await _ouvrir(tester, depot: depot);
      await _ouvrirProposition(tester);

      await tester.tap(find.text(AppStrings.proposerConfirmer(2)));
      await tester.pumpAndSettle();

      // Rien n'a été posé, et la feuille reste là : le chef peut réessayer où
      // il est.
      expect(planning.attributionsPosees, isEmpty);
      expect(find.text(AppStrings.proposerConfirmer(2)), findsOneWidget);
    });
  });
}
