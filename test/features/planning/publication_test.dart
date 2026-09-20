import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/planning/data/suivi_repository.dart';
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

/// Un poste d'administration : c'est là que le chef publie.
const Size _poste = Size(1440, 900);

final DateTime _maintenant = DateTime.now();
final DateTime _moisAffiche = DateTime(_maintenant.year, _maintenant.month);

int get _joursDuMois =>
    DateTime(_moisAffiche.year, _moisAffiche.month + 1, 0).day;

PeriodeSaisie _periode() =>
    periodeOuverte(annee: _moisAffiche.year, mois: _moisAffiche.month);

/// Trois membres : l'un au-delà de son quota, l'autre absent le 1er.
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
      // Un plafond de 1 : deux attributions le dépassent.
      maxAstreintes: 1,
    ),
    ligneMatrice(
      userId: 'dupuis',
      nom: 'Dupuis T.',
      jours: 'A$reste',
      nuits: '.$reste',
      maxAstreintes: 5,
    ),
  ];
}

Future<({FauxPlanningRepository planning, FauxSuiviRepository suivi})> _ouvrir(
  WidgetTester tester, {
  FauxPlanningRepository? depot,
  FauxSuiviRepository? suivi,
  Appartenance appartenance = appartenanceAdmin,
}) async {
  final planning = depot ?? _brouillonPourvu();
  final fauxSuivi = suivi ?? FauxSuiviRepository();
  addTearDown(planning.fermer);
  addTearDown(fauxSuivi.fermer);

  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    dispos: FauxDisposRepository(periodes: <PeriodeSaisie>[_periode()]),
    matrice: FauxMatriceRepository(lignes: _membres()),
    planning: planning,
    suivi: fauxSuivi,
    taille: _poste,
  );
  await ouvrirRoute(tester, _chemin);
  return (planning: planning, suivi: fauxSuivi);
}

/// Un brouillon complet : chaque créneau est pourvu, aucun quota dépassé,
/// aucune attribution forcée.
FauxPlanningRepository _brouillonPourvu() => FauxPlanningRepository(
  planning: planningBrouillon,
  creneaux: <CreneauPlanning>[
    creneau(id: 'c-1-j', jour: 1),
    creneau(id: 'c-1-n', jour: 1, creneau: CreneauType.nuit),
  ],
  attributions: const <Attribution>[
    Attribution(id: 'a1', creneauId: 'c-1-j', userId: 'aubry'),
    Attribution(id: 'a2', creneauId: 'c-1-n', userId: 'aubry'),
  ],
);

/// Un brouillon avec les trois réserves : un trou, un quota dépassé, une
/// attribution forcée.
FauxPlanningRepository _brouillonAReserves() => FauxPlanningRepository(
  planning: planningBrouillon,
  creneaux: <CreneauPlanning>[
    creneau(id: 'c-1-j', jour: 1),
    creneau(id: 'c-1-n', jour: 1, creneau: CreneauType.nuit),
    creneau(id: 'c-2-j', jour: 2),
    // Personne sur celui-ci : c'est la première réserve.
    creneau(id: 'c-2-n', jour: 2, creneau: CreneauType.nuit),
  ],
  attributions: const <Attribution>[
    Attribution(id: 'a1', creneauId: 'c-1-j', userId: 'camus'),
    Attribution(id: 'a2', creneauId: 'c-1-n', userId: 'camus'),
    // `etaitDisponible` est posé par la base : le faux le rejoue.
    Attribution(
      id: 'a3',
      creneauId: 'c-2-j',
      userId: 'dupuis',
      etaitDisponible: false,
    ),
  ],
);

Future<void> _ouvrirRecapitulatif(WidgetTester tester) async {
  await tester.ensureVisible(find.text(AppStrings.publierAction));
  await tester.tap(find.text(AppStrings.publierAction));
  await tester.pumpAndSettle();
}

void main() {
  group('Publier le planning — le bouton', () {
    testWidgets('il annonce le nombre de pompiers, pas d\'attributions', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(find.text(AppStrings.publierAction), findsOneWidget);
      // Deux attributions, un seul pompier : c'est le nombre de téléphones
      // qui vont sonner.
      expect(find.text(AppStrings.publierDetail(1)), findsOneWidget);
    });

    testWidgets('sans planning, il n\'y a rien à publier', (tester) async {
      await _ouvrir(
        tester,
        depot: FauxPlanningRepository(joursDuMoisACreer: _joursDuMois),
      );

      expect(find.text(AppStrings.publierAction), findsNothing);
    });

    testWidgets('sur un planning déjà publié, le bouton disparaît', (
      tester,
    ) async {
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

      expect(find.text(AppStrings.publierAction), findsNothing);
    });
  });

  group('Publier le planning — le récapitulatif', () {
    testWidgets('sans réserve, il le dit au lieu de se taire', (tester) async {
      await _ouvrir(tester);
      await _ouvrirRecapitulatif(tester);

      expect(find.text(AppStrings.publierSansReserve), findsOneWidget);
      expect(find.text(AppStrings.publierAVerifier), findsNothing);
      // La promesse du ticket, écrite avant qu'on la croie.
      expect(find.text(AppStrings.publierPromesse), findsOneWidget);
    });

    testWidgets('il montre les trois réserves, et n\'en bloque aucune', (
      tester,
    ) async {
      await _ouvrir(tester, depot: _brouillonAReserves());
      await _ouvrirRecapitulatif(tester);

      expect(find.text(AppStrings.publierAVerifier), findsOneWidget);
      // 1. le créneau que personne ne couvre
      expect(find.text(AppStrings.publierNonPourvus(1)), findsOneWidget);
      // 2. le membre au-delà de son quota (plafond 1, deux attributions)
      expect(find.text(AppStrings.publierHorsQuota(1)), findsOneWidget);
      expect(
        find.text(
          AppStrings.publierQuotaLigne(
            membre: 'Camus A.',
            astreintes: 2,
            plafond: 1,
          ),
        ),
        findsOneWidget,
      );
      // 3. le membre attribué hors de ses disponibilités
      expect(find.text(AppStrings.publierHorsDispo(1)), findsOneWidget);

      // **Aucune réserve ne bloque** : le bouton reste actionnable.
      final bouton = tester.widget<PrimaryButton>(
        find.ancestor(
          of: find.text(AppStrings.publierConfirmer),
          matching: find.byType(PrimaryButton),
        ),
      );
      expect(bouton.onPressed, isNotNull);
    });

    testWidgets('« Annuler » ne publie rien', (tester) async {
      final faux = await _ouvrir(tester);
      await _ouvrirRecapitulatif(tester);

      await tester.tap(find.text(AppStrings.publierAnnuler));
      await tester.pumpAndSettle();

      expect(faux.suivi.publications, isEmpty);
      expect(find.text(AppStrings.publierAction), findsOneWidget);
    });
  });

  group('Publier le planning — l\'envoi', () {
    testWidgets('« Publier et notifier » publie et annonce les membres '
        'notifiés', (tester) async {
      final suivi = FauxSuiviRepository()..membresPublies = 3;
      final faux = await _ouvrir(tester, suivi: suivi);
      await _ouvrirRecapitulatif(tester);

      await tester.tap(find.text(AppStrings.publierConfirmer));
      await tester.pumpAndSettle();

      expect(faux.suivi.publications, <String>['plan-1']);
      expect(
        find.text(
          AppStrings.publiePourMois(
            AppStrings.moisLongs[_moisAffiche.month - 1],
            3,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('un envoi manqué se dit, et ouvre le rattrapage sur le suivi', (
      tester,
    ) async {
      // **La publication est acquise, l'envoi ne l'est pas.** C'est le seul cas
      // où le chef doit savoir qu'il lui reste quelque chose à faire.
      final suivi = FauxSuiviRepository()
        ..membresPublies = 3
        ..envoiComplet = false
        ..membresRelances = 3;
      await _ouvrir(tester, suivi: suivi);
      await _ouvrirRecapitulatif(tester);

      await tester.tap(find.text(AppStrings.publierConfirmer));
      await tester.pumpAndSettle();

      // Pas « 3 pompiers notifiés » : personne ne l'a été.
      expect(
        find.text(
          AppStrings.publiePourMois(
            AppStrings.moisLongs[_moisAffiche.month - 1],
            3,
          ),
        ),
        findsNothing,
      );
      expect(
        find.text(
          AppStrings.publiePourMoisSansEnvoi(
            AppStrings.moisLongs[_moisAffiche.month - 1],
          ),
        ),
        findsOneWidget,
      );

      // L'écran de suivi porte le bandeau, et l'action qui le lève.
      expect(find.text(AppStrings.suiviEnvoiManque), findsOneWidget);
      expect(find.text(AppStrings.suiviPrevenir), findsOneWidget);

      await tester.tap(find.text(AppStrings.suiviPrevenir));
      await tester.pumpAndSettle();

      // Le rattrapage vise **toutes** les attributions, pas les seuls
      // retardataires : les pompiers qui n'ont rien reçu ne sont pas en retard.
      expect(suivi.relances.single.tout, isTrue);
      expect(find.text(AppStrings.suiviRattrapageFait(3)), findsOneWidget);
      expect(find.text(AppStrings.suiviEnvoiManque), findsNothing);
    });

    testWidgets('un rattrapage dédoublonné laisse le bandeau : personne de '
        'plus n\'a été prévenu', (tester) async {
      final suivi = FauxSuiviRepository()
        ..membresPublies = 3
        ..envoiComplet = false
        ..membresRelances = 3
        ..relanceNouvelle = false;
      await _ouvrir(tester, suivi: suivi);
      await _ouvrirRecapitulatif(tester);

      await tester.tap(find.text(AppStrings.publierConfirmer));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.suiviPrevenir));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.suiviRelanceDejaFaite), findsOneWidget);
      expect(find.text(AppStrings.suiviEnvoiManque), findsOneWidget);
    });

    testWidgets('un échec laisse le récapitulatif ouvert : rien n\'est perdu',
        (tester) async {
      final suivi = FauxSuiviRepository()
        ..erreurPublication = ErreurSuivi.inconnue;
      await _ouvrir(tester, suivi: suivi);
      await _ouvrirRecapitulatif(tester);

      await tester.tap(find.text(AppStrings.publierConfirmer));
      await tester.pumpAndSettle();

      // La feuille est toujours là, avec son bouton.
      expect(find.text(AppStrings.publierConfirmer), findsOneWidget);
    });

    testWidgets('« déjà publié » n\'est pas une panne : c\'est l\'adjoint', (
      tester,
    ) async {
      final suivi = FauxSuiviRepository()
        ..erreurPublication = ErreurSuivi.dejaPublie;
      await _ouvrir(tester, suivi: suivi);
      await _ouvrirRecapitulatif(tester);

      await tester.tap(find.text(AppStrings.publierConfirmer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.publierDejaFait), findsOneWidget);
    });
  });
}
