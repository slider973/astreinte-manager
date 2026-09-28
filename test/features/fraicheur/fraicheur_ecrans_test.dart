// Ticket 070 — les écrans de la PWA ne restent plus sur des données périmées.
//
// Chaque test change la base **pendant que l'application tourne**, puis joue
// ce que fait le pompier : ranger la PWA et la rouvrir, répondre dans la
// Boîte puis revenir à l'accueil, recevoir un push. L'horloge des relectures
// est avancée à la main au-delà du délai minimal : c'est elle qui sépare un
// retour au premier plan d'une grappe de retours.

import 'dart:async';

import 'package:astreinte_sp/core/caserne/caserne_providers.dart';
import 'package:astreinte_sp/core/firebase/firebase_bootstrap.dart';
import 'package:astreinte_sp/core/fraicheur/fraicheur.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/l10n/format_date.dart';
import 'package:astreinte_sp/core/plateforme/contexte_plateforme.dart';
import 'package:astreinte_sp/core/preferences/reperes_locaux.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/auth_erreur.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/loading_skeleton.dart';
import 'package:astreinte_sp/core/widgets/peinture_grille.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:astreinte_sp/features/astreintes/data/astreintes_repository.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/astreintes/presentation/widgets/ligne_astreinte.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/dispos/presentation/controllers/saisie_controller.dart';
import 'package:astreinte_sp/features/notifications/domain/etat_notifications.dart';
import 'package:astreinte_sp/features/notifications/domain/message_push.dart';
import 'package:astreinte_sp/features/notifications/presentation/couche_notifications.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:astreinte_sp/features/propositions/data/propositions_repository.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';
import 'package:astreinte_sp/features/propositions/presentation/widgets/carte_proposition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_abonnement.dart';
import '../../support/faux_astreintes.dart';
import '../../support/faux_auth.dart';
import '../../support/faux_caserne.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_matrice.dart';
import '../../support/faux_propositions.dart';
import '../../support/faux_push.dart';

/// Une horloge qu'on avance à la main.
class Horloge {
  DateTime maintenant = DateTime(2026, 9, 21, 10);

  void avancer([Duration duree = const Duration(seconds: 11)]) =>
      maintenant = maintenant.add(duree);
}

/// Un rangement de la PWA puis son retour, dans l'ordre exact où la
/// plateforme l'envoie. Sur le web, c'est `visibilitychange`.
Future<void> rangerPuisRevenir(
  WidgetTester tester, {
  bool stabiliser = true,
}) async {
  for (final etat in <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(etat);
  }
  if (stabiliser) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Un écran haut : l'accueil tient sans défiler.
const Size _telephoneLong = Size(420, 1800);

final DateTime _jourAstreinte = DateTime(2026, 9, 26);

ProviderContainer _conteneur(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

String _compteAstreintes(int compte) =>
    AppStrings.accueilSectionCompte(AppStrings.accueilMesAstreintes, compte);

String _comptePropositions(int compte) => AppStrings.accueilSectionCompte(
  AppStrings.accueilPropositionsSection,
  compte,
);

Proposition _proposition(String id, int jour) => proposition(
  id: id,
  creneauId: 'c-$id',
  jour: DateTime(2026, 9, jour),
);

/// Les propositions d'une caserne qui **range ses astreintes** : accepter une
/// ligne l'ajoute aux astreintes acceptées, comme la base le fait par
/// construction (`assignments.status = accepted`).
class _PropositionsLiees extends FauxPropositionsRepository {
  _PropositionsLiees(this._astreintes, {super.propositions});

  final FauxAstreintesRepository _astreintes;
  final Map<String, Proposition> _parId = <String, Proposition>{};

  @override
  Future<List<Proposition>> lister({
    required String userId,
    required String stationId,
  }) async {
    final liste = await super.lister(userId: userId, stationId: stationId);
    for (final ligne in liste) {
      _parId[ligne.id] = ligne;
    }
    return liste;
  }

  final List<Astreinte> acceptees = <Astreinte>[];

  @override
  Future<ResultatReponse> repondre({
    required String attributionId,
    required bool accepte,
    String? motif,
  }) async {
    final resultat = await super.repondre(
      attributionId: attributionId,
      accepte: accepte,
      motif: motif,
    );
    final ligne = _parId[attributionId];
    if (accepte && ligne != null) {
      acceptees.add(
        astreinte(
          id: ligne.id,
          jour: ligne.jour,
          creneau: ligne.creneau,
          creneauId: ligne.creneauId,
          planningId: ligne.planningId,
          planningEtat: PlanningEtat.publie,
        ),
      );
      _astreintes.definir(acceptees);
    }
    return resultat;
  }
}

/// Des astreintes dont la lecture attend que le test la libère : le réseau
/// d'une remise, pendant lequel l'écran doit rester lisible.
class _AstreintesLentes extends FauxAstreintesRepository {
  _AstreintesLentes({super.astreintes});

  Completer<void>? retenue;

  @override
  Future<MesAstreintes> lire({
    required String userId,
    required String stationId,
    required DateTime depuis,
  }) async {
    final attente = retenue;
    if (attente != null) await attente.future;
    return super.lire(userId: userId, stationId: stationId, depuis: depuis);
  }
}

Future<AppMontee> _monter(
  WidgetTester tester, {
  required Horloge horloge,
  FauxAstreintesRepository? astreintes,
  FauxPropositionsRepository? propositions,
  FauxCaserneRepository? caserne,
  FauxMatriceRepository? matrice,
  FauxDisposRepository? dispos,
  List<Appartenance> appartenances = const <Appartenance>[appartenanceMembre],
  FirebaseDemarrage firebase = FirebaseDemarrage.configurationAbsente,
  ContextePlateforme? plateforme,
  FauxMessageriePush? messagerie,
  Size taille = _telephoneLong,
}) => monterApp(
  tester,
  session: sessionMembre,
  appartenances: appartenances,
  astreintes: astreintes ?? FauxAstreintesRepository(),
  propositions: propositions ?? FauxPropositionsRepository(),
  caserne: caserne,
  matrice: matrice,
  dispos: dispos,
  horloge: () => maintenantTest,
  horlogeRafraichissement: () => horloge.maintenant,
  firebase: firebase,
  plateforme: plateforme,
  messagerie: messagerie,
  reperes: ReperesLocauxMemoire(<RepereAccueil>{
    RepereAccueil.peintureDispos,
    RepereAccueil.saisieProcuration,
  }),
  taille: taille,
);

void main() {
  // -------------------------------------------------------------------
  // Le retour au premier plan, écran par écran
  // -------------------------------------------------------------------

  group('Au retour au premier plan', () {
    testWidgets('l\'accueil montre une astreinte ajoutée en base', (
      tester,
    ) async {
      final horloge = Horloge();
      final astreintes = FauxAstreintesRepository();
      await _monter(tester, horloge: horloge, astreintes: astreintes);
      expect(find.text(_compteAstreintes(0)), findsOneWidget);

      astreintes.definir(<Astreinte>[
        astreinte(id: 'g-1', jour: _jourAstreinte),
      ]);
      horloge.avancer();
      await rangerPuisRevenir(tester);

      expect(find.text(_compteAstreintes(1)), findsOneWidget);
    });

    testWidgets('l\'accueil montre une proposition arrivée en base', (
      tester,
    ) async {
      final horloge = Horloge();
      final propositions = FauxPropositionsRepository();
      await _monter(tester, horloge: horloge, propositions: propositions);
      expect(find.text(_comptePropositions(0)), findsOneWidget);

      propositions.definir(<Proposition>[_proposition('a-1', 28)]);
      horloge.avancer();
      await rangerPuisRevenir(tester);

      expect(find.text(_comptePropositions(1)), findsOneWidget);
      expect(find.byType(CarteProposition), findsOneWidget);
    });

    testWidgets('pas de rafale : un retour dans les dix secondes ne relit '
        'rien', (tester) async {
      final horloge = Horloge();
      final astreintes = FauxAstreintesRepository();
      final propositions = FauxPropositionsRepository();
      await _monter(
        tester,
        horloge: horloge,
        astreintes: astreintes,
        propositions: propositions,
      );
      horloge.avancer();
      await rangerPuisRevenir(tester);
      final lecturesAstreintes = astreintes.lectures;
      final lecturesPropositions = propositions.lectures;

      horloge.avancer(const Duration(seconds: 3));
      await rangerPuisRevenir(tester);

      expect(astreintes.lectures, lecturesAstreintes);
      expect(propositions.lectures, lecturesPropositions);
    });

    testWidgets('« Astreintes » montre une astreinte ajoutée en base', (
      tester,
    ) async {
      final horloge = Horloge();
      final astreintes = FauxAstreintesRepository(
        astreintes: <Astreinte>[astreinte(id: 'g-1', jour: _jourAstreinte)],
      );
      await _monter(tester, horloge: horloge, astreintes: astreintes);
      await ouvrirRoute(tester, AppRoutes.astreintes);
      expect(find.byType(LigneDAstreinte), findsOneWidget);

      astreintes.definir(<Astreinte>[
        astreinte(id: 'g-1', jour: _jourAstreinte),
        astreinte(
          id: 'g-2',
          jour: _jourAstreinte.add(const Duration(days: 1)),
          creneauId: 'c-2',
        ),
      ]);
      horloge.avancer();
      await rangerPuisRevenir(tester);

      expect(find.byType(LigneDAstreinte), findsNWidgets(2));
    });

    testWidgets('la Boîte montre une proposition arrivée en base', (
      tester,
    ) async {
      final horloge = Horloge();
      final propositions = FauxPropositionsRepository(
        propositions: <Proposition>[_proposition('a-1', 28)],
      );
      await _monter(tester, horloge: horloge, propositions: propositions);
      await ouvrirRoute(tester, AppRoutes.boite);
      expect(find.byType(CarteProposition), findsOneWidget);

      propositions.definir(<Proposition>[
        _proposition('a-1', 28),
        _proposition('a-2', 29),
      ]);
      horloge.avancer();
      await rangerPuisRevenir(tester);

      expect(find.byType(CarteProposition), findsNWidgets(2));
    });

    testWidgets('la matrice montre une saisie faite pendant que le poste '
        'dormait', (tester) async {
      final horloge = Horloge();
      final mois = DateTime(DateTime.now().year, DateTime.now().month);
      final jours = DateTime(mois.year, mois.month + 1, 0).day;
      final matrice = FauxMatriceRepository(
        lignes: <LigneMatrice>[
          ligneMatrice(
            userId: 'u2',
            nom: 'Martin Alice',
            jours: '.' * jours,
            nuits: '.' * jours,
          ),
        ],
      );
      await _monter(
        tester,
        horloge: horloge,
        appartenances: const <Appartenance>[appartenanceAdmin],
        matrice: matrice,
        dispos: FauxDisposRepository(
          periodes: <PeriodeSaisie>[
            periodeOuverte(
              annee: mois.year,
              mois: mois.month,
              dateLimite: mois.add(const Duration(days: 20)),
            ),
          ],
        ),
        taille: const Size(1440, 900),
      );
      await ouvrirRoute(tester, AppRoutes.planningAdmin);

      Finder premiereCase() => find.byWidgetPredicate(
        (Widget widget) =>
            widget is SlotChip &&
            widget.libelleSemantique.startsWith(
              'Martin Alice, ${dateAvecJourSemaine(mois)}, jour',
            ),
      );
      expect(
        tester.widget<SlotChip>(premiereCase()).etat,
        DisponibiliteEtat.nonSaisi,
      );
      final lectures = matrice.lectures;

      matrice.lignes = <LigneMatrice>[
        ligneMatrice(
          userId: 'u2',
          nom: 'Martin Alice',
          jours: 'D${'.' * (jours - 1)}',
          nuits: '.' * jours,
        ),
      ];
      horloge.avancer();
      await rangerPuisRevenir(tester);

      expect(matrice.lectures, greaterThan(lectures));
      expect(
        tester.widget<SlotChip>(premiereCase()).etat,
        DisponibiliteEtat.disponible,
      );
    });

    testWidgets('la bannière de suspension disparaît quand la caserne est '
        'réactivée, et les boutons se réactivent', (tester) async {
      final horloge = Horloge();
      final caserne = FauxCaserneRepository(caserneSuspendue);
      await _monter(
        tester,
        horloge: horloge,
        caserne: caserne,
        propositions: FauxPropositionsRepository(
          propositions: <Proposition>[_proposition('a-1', 28)],
        ),
      );
      Finder banniereSuspendue() => find.byWidgetPredicate(
        (Widget w) =>
            w is AppBanner && w.variante == AppBannerVariante.lectureSeule,
      );
      expect(banniereSuspendue(), findsOneWidget);

      await ouvrirRoute(tester, AppRoutes.boite);
      await tester.tap(find.byType(CarteProposition).first);
      await tester.pumpAndSettle();
      final accepter = find.widgetWithText(
        PrimaryButton,
        AppStrings.propositionsAccepter,
      );
      expect(tester.widget<PrimaryButton>(accepter).onPressed, isNull);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Le chef de centre a payé dans l'onglet de Stripe.
      caserne.etat = caserneEnEssai;
      horloge.avancer();
      await rangerPuisRevenir(tester);

      expect(banniereSuspendue(), findsNothing);
      await tester.tap(find.byType(CarteProposition).first);
      await tester.pumpAndSettle();
      expect(tester.widget<PrimaryButton>(accepter).onPressed, isNotNull);

      await ouvrirRoute(tester, AppRoutes.accueil);
      expect(banniereSuspendue(), findsNothing);
    });

    testWidgets('une caserne suspendue pendant la session grise les boutons '
        'au retour', (tester) async {
      final horloge = Horloge();
      final caserne = FauxCaserneRepository();
      await _monter(tester, horloge: horloge, caserne: caserne);
      expect(_conteneur(tester).read(lectureSeuleCaserneProvider), isFalse);

      caserne.etat = caserneSuspendue;
      horloge.avancer();
      await rangerPuisRevenir(tester);

      expect(_conteneur(tester).read(lectureSeuleCaserneProvider), isTrue);
    });

    testWidgets('une lecture de station_access qui échoue garde la '
        'suspension connue', (tester) async {
      final horloge = Horloge();
      final caserne = FauxCaserneRepository(caserneSuspendue);
      await _monter(tester, horloge: horloge, caserne: caserne);

      caserne.injoignable = true;
      horloge.avancer();
      await rangerPuisRevenir(tester);

      expect(_conteneur(tester).read(lectureSeuleCaserneProvider), isTrue);
    });
  });

  // -------------------------------------------------------------------
  // Le rôle
  // -------------------------------------------------------------------

  group('Le rôle, relu en cours de session', () {
    testWidgets('un rôle admin retiré en base fait disparaître l\'onglet '
        'Admin et sort de l\'écran d\'administration', (tester) async {
      final horloge = Horloge();
      final faux = await _monter(
        tester,
        horloge: horloge,
        appartenances: const <Appartenance>[appartenanceAdmin],
        taille: const Size(1440, 900),
      );
      await ouvrirRoute(tester, AppRoutes.planningAdmin);
      expect(find.text(AppStrings.navAdmin), findsWidgets);

      faux.memberships.appartenances = <Appartenance>[
        const Appartenance(
          id: 'm-admin',
          stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
          nomCaserne: 'CIS Saint-Martin',
          role: RoleMembre.membre,
          statut: StatutMembre.actif,
          nomAffiche: 'Jean D.',
        ),
      ];
      horloge.avancer();
      await rangerPuisRevenir(tester);

      expect(find.text(AppStrings.navAdmin), findsNothing);
      expect(emplacementCourant(tester), AppRoutes.accueil);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un rôle admin donné en base fait apparaître l\'onglet', (
      tester,
    ) async {
      final horloge = Horloge();
      final faux = await _monter(tester, horloge: horloge);
      expect(find.text(AppStrings.navAdmin), findsNothing);

      faux.memberships.appartenances = <Appartenance>[
        const Appartenance(
          id: 'm-1',
          stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
          nomCaserne: 'CIS Saint-Martin',
          role: RoleMembre.admin,
          statut: StatutMembre.actif,
          nomAffiche: 'Marie L.',
        ),
      ];
      horloge.avancer();
      await rangerPuisRevenir(tester);

      expect(find.text(AppStrings.navAdmin), findsWidgets);
    });

    testWidgets('un retour au premier plan hors ligne ne rétrograde pas un '
        'admin confirmé', (tester) async {
      final horloge = Horloge();
      final faux = await _monter(
        tester,
        horloge: horloge,
        appartenances: const <Appartenance>[appartenanceAdmin],
      );
      expect(find.text(AppStrings.navAdmin), findsWidgets);

      faux.memberships.erreur = AuthErreur.reseau;
      horloge.avancer();
      await rangerPuisRevenir(tester);

      expect(find.text(AppStrings.navAdmin), findsWidgets);
    });
  });

  // -------------------------------------------------------------------
  // Les événements
  // -------------------------------------------------------------------

  group('Les événements', () {
    testWidgets('accepter dans la Boîte puis revenir à l\'accueil : '
        'l\'astreinte y est', (tester) async {
      final horloge = Horloge();
      final astreintes = FauxAstreintesRepository();
      final propositions = _PropositionsLiees(
        astreintes,
        propositions: <Proposition>[_proposition('a-1', 28)],
      );
      await _monter(
        tester,
        horloge: horloge,
        astreintes: astreintes,
        propositions: propositions,
      );
      expect(find.text(_compteAstreintes(0)), findsOneWidget);

      await ouvrirRoute(tester, AppRoutes.boite);
      await tester.tap(find.byType(CarteProposition).first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(PrimaryButton, AppStrings.propositionsAccepter),
      );
      await tester.pumpAndSettle();

      // **Sans avancer l'horloge** : c'est la réponse elle-même qui relit les
      // astreintes, pas un retour au premier plan.
      await ouvrirRoute(tester, AppRoutes.accueil);
      expect(find.text(_compteAstreintes(1)), findsOneWidget);
      expect(find.text(_comptePropositions(0)), findsOneWidget);
    });

    testWidgets('un push reçu au premier plan met à jour « Propositions » sur '
        'l\'accueil', (tester) async {
      final horloge = Horloge();
      final propositions = FauxPropositionsRepository();
      final faux = await _monter(
        tester,
        horloge: horloge,
        propositions: propositions,
        firebase: FirebaseDemarrage.pret,
        plateforme: ContextePlateforme.depuisAgent(
          userAgent:
              'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
          affichageAutonome: true,
        ),
        messagerie: FauxMessageriePush(etatPermission: PermissionPush.accordee),
      );
      expect(find.text(_comptePropositions(0)), findsOneWidget);

      // L'attribution est proposée **avant** l'envoi du push, et l'horloge
      // n'avance pas : c'est l'événement qui relit.
      propositions.definir(<Proposition>[_proposition('a-1', 28)]);
      faux.push.messages.add(
        const MessagePush(titre: 'Astreinte proposée', route: '/proposals'),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text(_comptePropositions(1)), findsOneWidget);
      await tester.pump(CoucheNotifications.duree);
      await tester.pumpAndSettle();
    });
  });

  // -------------------------------------------------------------------
  // Rien ne se vide, rien ne se reconstruit sous le doigt
  // -------------------------------------------------------------------

  group('Aucune relecture ne vide l\'écran', () {
    testWidgets('pendant la relecture, l\'accueil garde ses astreintes', (
      tester,
    ) async {
      final horloge = Horloge();
      final astreintes = _AstreintesLentes(
        astreintes: <Astreinte>[astreinte(id: 'g-1', jour: _jourAstreinte)],
      );
      await _monter(tester, horloge: horloge, astreintes: astreintes);
      expect(find.text(_compteAstreintes(1)), findsOneWidget);

      final retenue = astreintes.retenue = Completer<void>();
      horloge.avancer();
      await rangerPuisRevenir(tester, stabiliser: false);
      await tester.pump(const Duration(milliseconds: 300));

      // La lecture est en vol : l'écran est toujours là, sans squelette.
      expect(find.text(_compteAstreintes(1)), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsNothing);

      astreintes.retenue = null;
      retenue.complete();
      await tester.pumpAndSettle();
      expect(find.text(_compteAstreintes(1)), findsOneWidget);
    });

    testWidgets('une relecture qui échoue garde la liste', (tester) async {
      final horloge = Horloge();
      final astreintes = FauxAstreintesRepository(
        astreintes: <Astreinte>[astreinte(id: 'g-1', jour: _jourAstreinte)],
      );
      await _monter(tester, horloge: horloge, astreintes: astreintes);

      astreintes.erreur = ErreurAstreintes.reseau;
      horloge.avancer();
      await rangerPuisRevenir(tester);

      expect(find.text(_compteAstreintes(1)), findsOneWidget);
    });

    testWidgets('un changement de rôle attend la fin d\'une saisie en cours, '
        'et la saisie n\'est pas reconstruite', (tester) async {
      final horloge = Horloge();
      final dispos = FauxDisposRepository();
      final faux = await _monter(tester, horloge: horloge, dispos: dispos);
      await ouvrirRoute(tester, AppRoutes.calendrier);

      // Un doigt posé qui peint : le geste est en cours.
      final geste = await tester.startGesture(
        tester.getCenter(find.byType(SlotChip).at(1)),
      );
      await tester.pump(PeintureGrille.delaiAppuiLong * 2);
      await geste.moveTo(tester.getCenter(find.byType(SlotChip).at(5)));
      await tester.pump();
      final conteneur = _conteneur(tester);
      final saisie = conteneur.read(saisieControllerProvider.notifier);
      expect(saisie.ecritureEnAttente, isTrue);
      final etatAvant = conteneur.read(saisieControllerProvider).value;

      // Le nom affiché change en base : publier la nouvelle appartenance
      // reconstruirait **toute** l'application, saisie comprise.
      faux.memberships.appartenances = <Appartenance>[
        const Appartenance(
          id: 'm-1',
          stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
          nomCaserne: 'CIS Saint-Martin',
          role: RoleMembre.membre,
          statut: StatutMembre.actif,
          nomAffiche: 'Marie Lefebvre',
        ),
      ];
      // Sur un ordinateur, rendre le focus à la fenêtre suffit à un retour
      // au premier plan — le doigt (ici la souris) peut être encore posé.
      horloge.avancer();
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      final fraicheur = conteneur.read(fraicheurProvider);
      expect(fraicheur.retenue(Donnee.appartenances), isTrue);
      // Le même état, pas un état reconstruit : la case peinte est là.
      expect(
        identical(conteneur.read(saisieControllerProvider).value, etatAvant),
        isTrue,
      );

      expect(
        conteneur.read(appartenanceCouranteProvider)?.nomAffiche,
        'Marie L.',
      );

      // Le doigt se lève, l'envoi part, la file se vide : la relecture
      // retenue repart d'elle-même.
      await geste.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(saisie.ecritureEnAttente, isFalse);
      expect(fraicheur.retenue(Donnee.appartenances), isFalse);
      expect(
        conteneur.read(appartenanceCouranteProvider)?.nomAffiche,
        'Marie Lefebvre',
      );
    });
  });
}
