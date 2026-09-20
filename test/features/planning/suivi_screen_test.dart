import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/empty_state.dart';
import 'package:astreinte_sp/core/widgets/loading_skeleton.dart';
import 'package:astreinte_sp/core/widgets/status_badge.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/planning/data/suivi_repository.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/suivi_planning.dart';
import 'package:astreinte_sp/features/planning/domain/suivi_providers.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/bloc_progression.dart';
import 'package:astreinte_sp/features/planning/presentation/widgets/bloc_retardataires.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_planning.dart';
import '../../support/faux_suivi.dart';

const String _chemin = '/admin/suivi';

/// Un poste d'administration : la composition de référence.
const Size _poste = Size(1440, 900);

final DateTime _maintenant = DateTime.now();
final DateTime _moisAffiche = DateTime(_maintenant.year, _maintenant.month);

PeriodeSaisie _periode() =>
    periodeOuverte(annee: _moisAffiche.year, mois: _moisAffiche.month);

/// Un planning minuscule et lisible : quatre créneaux, quatre réponses, dont
/// une acceptée, une refusée et deux en attente — l'une d'elles en retard.
FauxSuiviRepository _depot({
  PlanningBrouillon? planning,
  List<AttributionSuivi>? attributions,
  int delaiRetardHeures = 72,
}) => FauxSuiviRepository(
  planning: planning ?? planningPublie(),
  delaiRetardHeures: delaiRetardHeures,
  creneaux: <CreneauPlanning>[
    creneau(id: 'c-1-j', jour: 1),
    creneau(id: 'c-1-n', jour: 1, creneau: CreneauType.nuit),
    creneau(id: 'c-2-j', jour: 2),
    creneau(id: 'c-2-n', jour: 2, creneau: CreneauType.nuit),
  ],
  attributions:
      attributions ??
      <AttributionSuivi>[
        attributionSuivi(
          id: 'a1',
          creneauId: 'c-1-j',
          userId: 'lefebvre',
          nom: 'Marie L.',
          etat: AttributionEtat.accepte,
          proposeeLe: _maintenant.subtract(const Duration(days: 5)),
          repondueLe: _maintenant.subtract(const Duration(days: 4)),
        ),
        attributionSuivi(
          id: 'a2',
          creneauId: 'c-1-n',
          userId: 'moreau',
          nom: 'Thomas M.',
          etat: AttributionEtat.refuse,
          proposeeLe: _maintenant.subtract(const Duration(days: 5)),
          repondueLe: _maintenant.subtract(const Duration(days: 3)),
          motifRefus: 'en formation',
        ),
        attributionSuivi(
          id: 'a3',
          creneauId: 'c-2-j',
          userId: 'girard',
          nom: 'Camille G.',
          proposeeLe: _maintenant.subtract(const Duration(days: 5)),
        ),
        attributionSuivi(
          id: 'a4',
          creneauId: 'c-2-n',
          userId: 'bernard',
          nom: 'Lucas B.',
          proposeeLe: _maintenant.subtract(const Duration(hours: 2)),
        ),
      ],
);

Future<FauxSuiviRepository> _ouvrir(
  WidgetTester tester, {
  FauxSuiviRepository? depot,
  Size taille = _poste,
  Appartenance appartenance = appartenanceAdmin,
}) async {
  final suivi = depot ?? _depot();
  addTearDown(suivi.fermer);

  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    dispos: FauxDisposRepository(periodes: <PeriodeSaisie>[_periode()]),
    suivi: suivi,
    taille: taille,
  );
  await ouvrirRoute(tester, _chemin);
  return suivi;
}

void main() {
  group('Le suivi du planning — son rendu', () {
    testWidgets('la progression vient de la vue, jamais d\'un recomptage', (
      tester,
    ) async {
      await _ouvrir(tester);

      final bloc = tester.widget<BlocProgression>(
        find.byType(BlocProgression),
      );
      expect(bloc.progression.enAttente, 2);
      expect(bloc.progression.acceptees, 1);
      expect(bloc.progression.refusees, 1);
      // Le créneau refusé n'est plus couvert : trois sur quatre.
      expect(bloc.progression.creneauxPourvus, 3);
      expect(bloc.progression.creneauxTotal, 4);

      // **La barre ne dit rien que la phrase ne dise déjà.**
      expect(find.text(AppStrings.suiviReponses(2, 4)), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('chaque réponse porte son état et le motif d\'un refus', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(find.text('Marie L.'), findsOneWidget);
      expect(find.text('Thomas M.'), findsOneWidget);
      // Le motif est l'information la plus utile de l'écran.
      expect(
        find.text(AppStrings.suiviMotifRefus('en formation')),
        findsOneWidget,
      );
    });

    testWidgets('le planning porte son état en badge', (tester) async {
      await _ouvrir(tester);

      final badge = tester.widget<StatusBadge>(
        find.byType(StatusBadge).first,
      );
      expect(badge.tampon, isFalse);
      expect(find.text(AppStrings.planningPublie), findsWidgets);
    });

    testWidgets('le chargement montre un squelette, jamais une roue', (
      tester,
    ) async {
      final depot = _depot();
      addTearDown(depot.fermer);

      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceAdmin],
        dispos: FauxDisposRepository(periodes: <PeriodeSaisie>[_periode()]),
        suivi: depot,
        taille: _poste,
        stabiliser: false,
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(LoadingSkeleton), findsNothing);
    });
  });

  group('Le suivi du planning — les états vides', () {
    testWidgets('sans planning, il propose d\'aller le construire', (
      tester,
    ) async {
      await _ouvrir(tester, depot: FauxSuiviRepository());

      expect(find.text(AppStrings.suiviAbsentTitre), findsOneWidget);
      expect(find.text(AppStrings.suiviAbsentAction), findsOneWidget);
    });

    testWidgets('un brouillon n\'a rien à suivre, et le dit', (tester) async {
      await _ouvrir(
        tester,
        depot: _depot(planning: planningBrouillon),
      );

      expect(find.text(AppStrings.suiviBrouillonTitre), findsOneWidget);
      expect(find.byType(BlocProgression), findsNothing);
    });

    testWidgets('une lecture en échec propose de réessayer', (tester) async {
      await _ouvrir(
        tester,
        depot: FauxSuiviRepository(erreurLecture: ErreurSuivi.inconnue),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text(AppStrings.actionReessayer), findsOneWidget);
    });

    testWidgets('un membre n\'ouvre pas le suivi', (tester) async {
      await _ouvrir(tester, appartenance: appartenanceMembre);

      // La garde du routeur ferme `/admin` : on n'y arrive même pas.
      expect(find.byType(BlocProgression), findsNothing);
    });
  });

  group('Le suivi du planning — les retardataires', () {
    testWidgets('le bloc n\'existe pas quand il n\'y a personne', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        depot: _depot(
          attributions: <AttributionSuivi>[
            attributionSuivi(
              id: 'a1',
              creneauId: 'c-1-j',
              userId: 'lefebvre',
              nom: 'Marie L.',
              proposeeLe: _maintenant.subtract(const Duration(hours: 1)),
            ),
          ],
        ),
      );

      expect(find.byType(BlocRetardataires), findsNothing);
    });

    testWidgets('il liste les membres et annonce le délai de la caserne', (
      tester,
    ) async {
      await _ouvrir(tester, depot: _depot(delaiRetardHeures: 24));

      expect(find.byType(BlocRetardataires), findsOneWidget);
      // Le délai réel, pas un 72 écrit en dur.
      expect(find.text(AppStrings.suiviRetardatairesDetail(24)), findsOneWidget);
      expect(find.text(AppStrings.suiviRetardatairesTitre(1)), findsOneWidget);
    });

    testWidgets('« Relancer maintenant » relance, et le dit', (tester) async {
      final depot = _depot();
      depot.membresRelances = 2;
      await _ouvrir(tester, depot: depot);

      await tester.ensureVisible(find.text(AppStrings.suiviRelancer));
      await tester.tap(find.text(AppStrings.suiviRelancer));
      await tester.pumpAndSettle();

      expect(depot.relances, <String>['plan-1']);
      expect(find.text(AppStrings.suiviRelanceFaite(2)), findsOneWidget);
    });

    testWidgets('une relance écartée par le dédoublonnage le dit au lieu de '
        'feindre un envoi', (tester) async {
      final depot = _depot();
      depot
        ..membresRelances = 2
        ..relanceNouvelle = false;
      await _ouvrir(tester, depot: depot);

      await tester.ensureVisible(find.text(AppStrings.suiviRelancer));
      await tester.tap(find.text(AppStrings.suiviRelancer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.suiviRelanceDejaFaite), findsOneWidget);
    });
  });

  group('Le suivi du planning — le temps réel', () {
    testWidgets('une réponse reçue change les chiffres sans rechargement', (
      tester,
    ) async {
      final depot = _depot();
      await _ouvrir(tester, depot: depot);

      expect(find.text(AppStrings.suiviReponses(2, 4)), findsOneWidget);

      // Le canal **ne diffuse pas la jointure** : la ligne arrive sans le nom.
      depot.diffuser(
        ReponseRecue(
          attributionSuivi(
            id: 'a3',
            creneauId: 'c-2-j',
            userId: 'girard',
            nom: '',
            etat: AttributionEtat.accepte,
            proposeeLe: _maintenant.subtract(const Duration(days: 5)),
            repondueLe: _maintenant,
          ),
        ),
      );
      await tester.pumpAndSettle(
        SuiviController.fenetreAvancement + const Duration(milliseconds: 100),
      );

      // Le nom connu survit à un événement qui ne le porte pas.
      expect(find.text('Camille G.'), findsOneWidget);
      // Et l'avancement a été relu dans la vue, pas recompté.
      expect(depot.lecturesAvancement, greaterThan(0));
    });

    testWidgets('la validation automatique se voit, avec son tampon', (
      tester,
    ) async {
      final depot = _depot();
      await _ouvrir(tester, depot: depot);

      expect(find.text(AppStrings.planningValide), findsNothing);

      final valideLe = DateTime.now();
      depot.diffuser(
        PlanningRecu(
          PlanningBrouillon(
            id: 'plan-1',
            etat: PlanningEtat.valide,
            publieLe: _maintenant.subtract(const Duration(days: 5)),
            valideLe: valideLe,
          ),
        ),
      );
      await tester.pumpAndSettle(
        SuiviController.fenetreAvancement + const Duration(milliseconds: 100),
      );

      expect(find.text(AppStrings.planningValide), findsWidgets);
      final badge = tester.widget<StatusBadge>(find.byType(StatusBadge).first);
      // Le seul moment chorégraphié de l'application.
      expect(badge.tampon, isTrue);
    });

    testWidgets('un canal tombé se dit, au lieu de mentir sur la fraîcheur', (
      tester,
    ) async {
      final depot = _depot();
      await _ouvrir(tester, depot: depot);

      expect(find.text(AppStrings.planningDirect), findsOneWidget);

      depot.diffuser(const EtatCanalSuivi(branche: false));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.planningDirectInterrompu), findsOneWidget);
    });
  });

  group('Le suivi du planning — les filtres', () {
    testWidgets('une puce filtre la liste et garde sa place', (tester) async {
      await _ouvrir(tester);

      expect(find.text('Marie L.'), findsOneWidget);

      await tester.ensureVisible(find.text(AppStrings.suiviFiltreRefuses));
      await tester.tap(find.text(AppStrings.suiviFiltreRefuses));
      await tester.pumpAndSettle();

      expect(find.text('Thomas M.'), findsOneWidget);
      expect(find.text('Marie L.'), findsNothing);
      // Les puces restent : aucune ne disparaît sous le doigt.
      expect(find.text(AppStrings.suiviFiltreTous), findsOneWidget);
    });

    testWidgets('« Tous » lève les filtres', (tester) async {
      await _ouvrir(tester);

      await tester.ensureVisible(find.text(AppStrings.suiviFiltreRefuses));
      await tester.tap(find.text(AppStrings.suiviFiltreRefuses));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.suiviFiltreTous));
      await tester.pumpAndSettle();

      expect(find.text('Marie L.'), findsOneWidget);
      expect(find.text('Thomas M.'), findsOneWidget);
    });
  });
}
