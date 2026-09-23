import 'dart:async';

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/loading_skeleton.dart';
import 'package:astreinte_sp/features/accueil/domain/tableau_bord.dart';
import 'package:astreinte_sp/features/accueil/presentation/widgets/bande_semaine.dart';
import 'package:astreinte_sp/features/accueil/presentation/widgets/bloc_dispos.dart';
import 'package:astreinte_sp/features/accueil/presentation/widgets/carte_jour.dart';
import 'package:astreinte_sp/features/accueil/presentation/widgets/ligne_proposition_accueil.dart';
import 'package:astreinte_sp/features/astreintes/data/astreintes_repository.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/propositions/data/propositions_repository.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';
import 'package:astreinte_sp/features/propositions/presentation/propositions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_astreintes.dart';
import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_propositions.dart';

/// Un mercredi matin d'octobre : la fenêtre de sept jours traverse un weekend,
/// et la salutation est celle du matin.
final DateTime _matin = DateTime(2026, 10, 14, 9);
final DateTime _soir = DateTime(2026, 10, 14, 20);

/// Un téléphone : la composition de référence de cet écran.
const Size _telephone = Size(390, 844);

/// La période de novembre, ouverte jusqu'au 17 octobre — trois jours après
/// l'horloge du test.
PeriodeSaisie _novembreOuvert() => periodeOuverte(
  annee: 2026,
  mois: 11,
  dateLimite: DateTime(2026, 10, 17, 23, 59, 59),
);

Future<void> _ouvrir(
  WidgetTester tester, {
  List<Astreinte> astreintes = const <Astreinte>[],
  List<Proposition> propositions = const <Proposition>[],
  List<PeriodeSaisie>? periodes,
  DateTime? horloge,
  Size taille = _telephone,
  bool stabiliser = true,
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    astreintes: FauxAstreintesRepository(astreintes: astreintes),
    propositions: FauxPropositionsRepository(propositions: propositions),
    dispos: FauxDisposRepository(
      periodes: periodes ?? <PeriodeSaisie>[_novembreOuvert()],
    ),
    horloge: () => horloge ?? _matin,
    taille: taille,
    stabiliser: stabiliser,
  );
}

Astreinte _demain() => astreinte(
  id: 'g-1',
  jour: DateTime(2026, 10, 15),
);

Proposition _proposition(String id, int jour) => proposition(
  id: id,
  jour: DateTime(2026, 10, jour),
  creneau: CreneauType.jour,
  proposeeLe: _matin.subtract(const Duration(hours: 2)),
);

void main() {
  group('L\'en-tête', () {
    testWidgets('le matin, « Bonjour » et le prénom en dessous', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(find.text(AppStrings.accueilBonjour), findsOneWidget);
      expect(find.text('Marie'), findsOneWidget);
      expect(find.text(AppStrings.accueilBonsoir), findsNothing);
    });

    testWidgets('le soir, « Bonsoir »', (tester) async {
      await _ouvrir(tester, horloge: _soir);

      expect(find.text(AppStrings.accueilBonsoir), findsOneWidget);
      expect(find.text(AppStrings.accueilBonjour), findsNothing);
    });

    testWidgets('la salutation est annoncée d\'un seul tenant', (tester) async {
      final handle = tester.ensureSemantics();
      await _ouvrir(tester);

      expect(
        find.bySemanticsLabel(
          AppStrings.accueilSalutation(AppStrings.accueilBonjour, 'Marie'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('aucune barre d\'application ne redit « Accueil »', (
      tester,
    ) async {
      await _ouvrir(tester);

      // Le mot « Accueil » n'existe qu'une fois à l'écran : dans la barre du
      // bas, comme nom de destination.
      expect(find.byType(AppBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(AppStrings.navAccueil),
        ),
        findsOneWidget,
      );
    });
  });

  group('La rangée « Mes astreintes »', () {
    testWidgets('sans astreinte, un état vide qui mène au Calendrier', (
      tester,
    ) async {
      await _ouvrir(tester, periodes: <PeriodeSaisie>[]);

      expect(
        find.text(AppStrings.accueilVideAstreintesTitre),
        findsOneWidget,
      );
      await tester.tap(find.text(AppStrings.accueilVideAstreintesAction));
      await tester.pumpAndSettle();
      expect(emplacementCourant(tester), AppRoutes.calendrier);
    });

    testWidgets('la prochaine acceptée ouvre la rangée, avec ses heures', (
      tester,
    ) async {
      await _ouvrir(tester, astreintes: <Astreinte>[_demain()]);

      expect(find.byType(CarteJourVue), findsWidgets);
      final premiere = tester.widget<CarteJourVue>(
        find.byType(CarteJourVue).first,
      );
      expect(premiere.carte.jour, DateTime(2026, 10, 15));
      expect(premiere.carte.creneau, CreneauType.nuit);

      // Les heures viennent des réglages de la caserne, pas d'une constante.
      expect(
        find.text(HeuresAffichage.defaut.intervalle(CreneauType.nuit)),
        findsWidgets,
      );
      // Le compte est écrit à côté du titre.
      expect(
        find.text(
          AppStrings.accueilSectionCompte(AppStrings.accueilMesAstreintes, 1),
        ),
        findsOneWidget,
      );
    });

    testWidgets('chaque carte s\'annonce par sa date, son créneau, son état', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _ouvrir(tester, astreintes: <Astreinte>[_demain()]);

      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(AppStrings.creneauNuit))),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(RegExp.escape(AppStrings.accueilEtatAcceptee)),
        ),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(RegExp.escape(AppStrings.accueilEtatLibre)),
        ),
        findsWidgets,
      );

      handle.dispose();
    });

    testWidgets('la carte d\'aujourd\'hui le dit en toutes lettres', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        astreintes: <Astreinte>[
          astreinte(id: 'g-0', jour: DateTime(2026, 10, 14)),
        ],
      );

      expect(find.text(AppStrings.accueilAujourdhui), findsOneWidget);
    });

    testWidgets('une proposition porte « Répondre », qui ouvre la réponse', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        propositions: <Proposition>[_proposition('a-1', 16)],
      );

      final repondre = find.text(AppStrings.accueilRepondre).first;
      await tester.ensureVisible(repondre);
      await tester.pumpAndSettle();
      await tester.tap(repondre);
      await tester.pumpAndSettle();

      // Le même écran qu'aujourd'hui, avec ses deux boutons : la réponse ne
      // se dédouble pas.
      expect(find.byType(PropositionsScreen), findsOneWidget);
      expect(emplacementCourant(tester), AppRoutes.propositions);
    });

    testWidgets('« Tout voir » mène aux astreintes, et se nomme', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _ouvrir(tester, astreintes: <Astreinte>[_demain()]);

      // Deux boutons « Tout voir » sur un écran ne se distinguent pas à
      // l'oreille : chacun annonce sa destination.
      expect(
        find.bySemanticsLabel(AppStrings.accueilToutVoirAstreintes),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(AppStrings.accueilToutVoirPropositions),
        findsOneWidget,
      );

      await tester.tap(find.text(AppStrings.accueilToutVoir).first);
      await tester.pumpAndSettle();
      expect(emplacementCourant(tester), AppRoutes.astreintes);

      handle.dispose();
    });
  });

  group('La section « Propositions »', () {
    testWidgets('sans rien, un état vide qui ne promet aucune action', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(
        find.text(AppStrings.accueilVidePropositionsTitre),
        findsOneWidget,
      );
      expect(find.byType(LignePropositionAccueil), findsNothing);
    });

    testWidgets('trois au plus, dans l\'ordre du calendrier', (tester) async {
      await _ouvrir(
        tester,
        propositions: <Proposition>[
          _proposition('a-4', 19),
          _proposition('a-1', 15),
          _proposition('a-3', 18),
          _proposition('a-2', 16),
        ],
      );

      final lignes = tester
          .widgetList<LignePropositionAccueil>(
            find.byType(LignePropositionAccueil),
          )
          .toList(growable: false);
      expect(lignes, hasLength(3));
      expect(
        lignes.map((LignePropositionAccueil l) => l.proposition.id).toList(),
        <String>['a-1', 'a-2', 'a-3'],
      );
      // Le compte, lui, les compte toutes.
      expect(
        find.text(
          AppStrings.accueilSectionCompte(
            AppStrings.accueilPropositionsSection,
            4,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('un appui sur une ligne ouvre la réponse', (tester) async {
      await _ouvrir(
        tester,
        propositions: <Proposition>[_proposition('a-1', 16)],
      );

      await tester.tap(find.byType(LignePropositionAccueil));
      await tester.pumpAndSettle();
      expect(find.byType(PropositionsScreen), findsOneWidget);
    });

    testWidgets('la bande de semaine montre sept jours et leurs points', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        astreintes: <Astreinte>[_demain()],
        propositions: <Proposition>[_proposition('a-1', 17)],
      );

      final bande = tester.widget<BandeSemaine>(find.byType(BandeSemaine));
      expect(bande.jours, hasLength(7));
      expect(bande.jours.first.aujourdhui, isTrue);
      expect(
        bande.jours
            .firstWhere((PointJour j) => j.jour == DateTime(2026, 10, 15))
            .astreinte,
        isTrue,
      );
      expect(
        bande.jours
            .firstWhere((PointJour j) => j.jour == DateTime(2026, 10, 17))
            .proposition,
        isTrue,
      );
    });

    testWidgets('chaque jour de la bande porte sa phrase, pas ses points', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _ouvrir(
        tester,
        propositions: <Proposition>[_proposition('a-1', 17)],
      );

      expect(
        find.bySemanticsLabel(
          RegExp(
            RegExp.escape(
              AppStrings.accueilJourSemantique(
                date: 'sam. 17',
                aujourdhui: false,
                astreinte: false,
                proposition: true,
              ),
            ),
          ),
        ),
        findsOneWidget,
      );

      handle.dispose();
    });
  });

  group('La section « Disponibilités »', () {
    testWidgets('un mois ouvert appelle à saisir, avec son délai', (
      tester,
    ) async {
      await _ouvrir(tester);
      await defilerJusqua(tester, find.byType(BlocDispos));

      expect(find.byType(BlocDispos), findsOneWidget);
      expect(
        find.text(AppStrings.accueilSaisirMois('novembre')),
        findsOneWidget,
      );
      expect(find.text(AppStrings.accueilResteJours(3)), findsOneWidget);

      await tester.tap(find.byType(BlocDispos));
      await tester.pumpAndSettle();
      expect(
        emplacementCourant(tester),
        '${AppRoutes.calendrier}?mois=2026-11',
      );
    });

    testWidgets('aucun mois ouvert : la section n\'existe pas', (tester) async {
      await _ouvrir(
        tester,
        periodes: <PeriodeSaisie>[periodeVerrouillee(annee: 2026, mois: 9)],
      );

      expect(find.byType(BlocDispos), findsNothing);
      expect(find.text(AppStrings.accueilDisponibilites), findsNothing);
    });
  });

  group('Chargement et erreur', () {
    testWidgets('un squelette, jamais une roue', (tester) async {
      final astreintes = _AstreintesLentes();
      final propositions = _PropositionsLentes();
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
        astreintes: astreintes,
        propositions: propositions,
        horloge: () => _matin,
        stabiliser: false,
      );

      expect(find.byType(LoadingSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      astreintes.liberer();
      propositions.liberer();
      await tester.pumpAndSettle();
      expect(find.byType(LoadingSkeleton), findsNothing);
    });

    testWidgets('une lecture en échec nomme la sortie', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
        astreintes: FauxAstreintesRepository(erreur: ErreurAstreintes.reseau),
        propositions: FauxPropositionsRepository(
          erreurLecture: ErreurProposition.reseau,
        ),
        horloge: () => _matin,
      );

      expect(find.text(AppStrings.accueilErreurTexte), findsOneWidget);
      expect(find.text(AppStrings.actionReessayer), findsOneWidget);
    });
  });

  group('Cibles et débordement', () {
    testWidgets('rien ne déborde, de 320 à ×1.6 d\'échelle de texte', (
      tester,
    ) async {
      for (final taille in <Size>[
        const Size(320, 720),
        const Size(390, 844),
        const Size(430, 932),
      ]) {
        await _ouvrir(
          tester,
          astreintes: <Astreinte>[_demain()],
          propositions: <Proposition>[_proposition('a-1', 16)],
          taille: taille,
        );
        expect(tester.takeException(), isNull, reason: '$taille');
        await demonter(tester);
      }

      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _ouvrir(
        tester,
        astreintes: <Astreinte>[_demain()],
        propositions: <Proposition>[_proposition('a-1', 16)],
      );
      expect(tester.takeException(), isNull, reason: 'échelle ×1.6');
    });

    testWidgets('le bouton « Répondre » tient le plancher tactile', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        propositions: <Proposition>[_proposition('a-1', 16)],
      );

      final bouton = find.widgetWithText(
        OutlinedButton,
        AppStrings.accueilRepondre,
      );
      expect(tester.getSize(bouton.first).height, greaterThanOrEqualTo(44));
    });
  });

  group('Sur grand écran', () {
    testWidgets('l\'en-tête de travail porte la cloche et le compte, une '
        'seule fois', (tester) async {
      await _ouvrir(
        tester,
        astreintes: <Astreinte>[_demain()],
        taille: const Size(1280, 900),
      );

      // La salutation reste ; l'avatar et la cloche vivent dans l'en-tête de
      // travail du ticket 061, et ne sont pas doublés dans le contenu.
      expect(find.text(AppStrings.accueilBonjour), findsOneWidget);
      expect(find.byTooltip(AppStrings.centreOuvrir), findsOneWidget);
      expect(
        find.byTooltip(AppStrings.compteOuvrirNomme('Marie L.')),
        findsOneWidget,
      );
    });
  });
}

/// Deux lectures qui ne rendent jamais la main : le squelette reste à l'écran.
///
/// Les **deux** sont nécessaires : l'accueil n'attend que tant qu'aucune de
/// ses deux sources n'a répondu — une panne d'un côté n'efface pas ce que
/// l'autre a lu.
class _AstreintesLentes extends FauxAstreintesRepository {
  final Completer<MesAstreintes> _attente = Completer<MesAstreintes>();

  void liberer() => _attente.complete(const MesAstreintes());

  @override
  Future<MesAstreintes> lire({
    required String userId,
    required String stationId,
    required DateTime depuis,
  }) => _attente.future;
}

class _PropositionsLentes extends FauxPropositionsRepository {
  final Completer<List<Proposition>> _attente = Completer<List<Proposition>>();

  void liberer() => _attente.complete(const <Proposition>[]);

  @override
  Future<List<Proposition>> lister({
    required String userId,
    required String stationId,
  }) => _attente.future;
}
