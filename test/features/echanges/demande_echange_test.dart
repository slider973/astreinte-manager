/// **Pompier A — proposer, suivre, annuler** (ticket 073, `design/073 § 6`).
///
/// Le parcours part de la feuille d'astreinte, comme le pompier : la ligne,
/// « Proposer un échange », puis les étapes dans l'adresse.
library;

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_astreintes.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/astreintes/presentation/widgets/ligne_astreinte.dart';
import 'package:astreinte_sp/features/echanges/data/echanges_repository.dart';
import 'package:astreinte_sp/features/echanges/domain/demande_echange.dart';
import 'package:astreinte_sp/features/echanges/domain/echange.dart';
import 'package:astreinte_sp/features/echanges/presentation/demande_echange_screen.dart';
import 'package:astreinte_sp/features/echanges/presentation/widgets/carte_echange.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_astreintes.dart';
import '../../support/faux_auth.dart';
import '../../support/faux_echanges.dart';

final DateTime _aujourdhui = DateTime(2026, 10, 4, 10);

/// Moi, Antoine : la session du membre de test.
final String _moi = sessionMembre.userId;

const Collegue _chloe = Collegue(userId: 'u-chloe', nom: 'Chloé C.');
const Collegue _bruno = Collegue(userId: 'u-bruno', nom: 'Bruno D.');

/// La nuit du samedi 24 octobre, acceptée, planning publié.
final _nuit = astreinte(
  id: 'att-a',
  jour: DateTime(2026, 10, 24),
  planningEtat: PlanningEtat.publie,
);

final GardeProposable _jourDeChloe = GardeProposable(
  attributionId: 'att-b',
  creneauId: 'c-27',
  stationId: appartenanceMembre.stationId,
  jour: DateTime(2026, 10, 27),
  creneau: CreneauType.jour,
);

Future<FauxEchangesRepository> _monter(
  WidgetTester tester, {
  FauxEchangesRepository? echanges,
  Size taille = const Size(390, 844),
}) async {
  final depot =
      echanges ??
      FauxEchangesRepository(
        collegues: const <Collegue>[_chloe, _bruno],
        gardes: <String, List<GardeProposable>>{
          'u-chloe': <GardeProposable>[_jourDeChloe],
        },
      );
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    astreintes: FauxAstreintesRepository(astreintes: <Astreinte>[_nuit]),
    cacheAstreintes: CacheAstreintesMemoire(),
    echanges: depot,
    horloge: () => _aujourdhui,
    taille: taille,
  );
  await ouvrirRoute(tester, AppRoutes.astreintes);
  return depot;
}

Future<void> _toucher(WidgetTester tester, Finder quoi) async {
  await tester.ensureVisible(quoi);
  await tester.pumpAndSettle();
  await tester.tap(quoi);
  await tester.pumpAndSettle();
}

Finder _bouton(String libelle) => find.widgetWithText(PrimaryButton, libelle);

Future<void> _ouvrirParcours(WidgetTester tester) async {
  await _toucher(tester, find.byType(LigneDAstreinte));
  await _toucher(tester, _bouton(AppStrings.echangeProposer));
}

void main() {
  testWidgets('la feuille d\'astreinte propose un échange', (tester) async {
    await _monter(tester);
    await _toucher(tester, find.byType(LigneDAstreinte));
    expect(_bouton(AppStrings.echangeProposer), findsOneWidget);

    await _toucher(tester, _bouton(AppStrings.echangeProposer));
    expect(find.byType(DemandeEchangeScreen), findsOneWidget);
    expect(find.text(AppStrings.echangeQuiTitre), findsOneWidget);
    expect(find.text(AppStrings.echangeEtape(1, 3)), findsOneWidget);
    expect(
      emplacementCourant(tester),
      contains('etape=${EtapeDemande.qui.valeurUrl}'),
    );
  });

  testWidgets('cession à toute la caserne : quatre touches', (tester) async {
    final depot = await _monter(tester);
    await _ouvrirParcours(tester);

    // « Continuer » attend un choix, et le dit.
    expect(find.text(AppStrings.echangeChoisirQui), findsOneWidget);

    await _toucher(tester, find.text(AppStrings.echangeCaserne));
    await _toucher(tester, _bouton(AppStrings.echangeContinuer));

    // L'étape 2 est sautée : une demande à la caserne est une cession.
    expect(find.text(AppStrings.echangeVerifierTitre), findsOneWidget);
    expect(find.text(AppStrings.echangeEtape(2, 2)), findsOneWidget);
    expect(find.text(AppStrings.echangeLesDisponibles), findsOneWidget);
    expect(emplacementCourant(tester), contains('cible=caserne'));

    await _toucher(tester, _bouton(AppStrings.echangeEnvoyer));

    expect(depot.appels.single.$1, 'request_exchange');
    expect(depot.appels.single.$2, <String, dynamic>{
      'p_assignment': 'att-a',
      'p_target': null,
      'p_return_assignment': null,
    });
    expect(find.text(AppStrings.echangeEnvoyeeCaserne), findsOneWidget);
    expect(emplacementCourant(tester), AppRoutes.astreintes);
  });

  testWidgets('échange avec un collègue : sa garde en retour', (tester) async {
    final depot = await _monter(tester);
    await _ouvrirParcours(tester);

    await _toucher(tester, find.text(AppStrings.echangeCollegue));
    await _toucher(tester, find.text('Chloé C.'));
    await _toucher(tester, _bouton(AppStrings.echangeContinuer));

    expect(find.text(AppStrings.echangeQuoiTitre), findsOneWidget);
    await _toucher(tester, find.text(AppStrings.echangeEchanger));
    // Pas encore de garde choisie : « Continuer » le dit.
    expect(find.text(AppStrings.echangeChoisirGarde), findsOneWidget);
    await _toucher(tester, find.textContaining('27 oct.'));
    await _toucher(tester, _bouton(AppStrings.echangeContinuer));

    // Le récapitulatif : « Tu donnes », « Tu prends », et à qui.
    expect(find.text(AppStrings.echangeTuDonnes), findsOneWidget);
    expect(find.text(AppStrings.echangeTuPrends), findsOneWidget);
    expect(find.text('Chloé C.'), findsOneWidget);
    expect(
      find.textContaining(AppStrings.echangeInfoValidation('Chloé C.')),
      findsOneWidget,
    );

    await _toucher(tester, _bouton(AppStrings.echangeEnvoyer));
    expect(depot.appels.single.$2, <String, dynamic>{
      'p_assignment': 'att-a',
      'p_target': 'u-chloe',
      'p_return_assignment': 'att-b',
    });
    expect(find.text(AppStrings.echangeEnvoyeeA('Chloé C.')), findsOneWidget);
  });

  testWidgets('un collègue sans garde à venir : « Échanger » grisé, raison '
      'écrite', (tester) async {
    await _monter(tester);
    await _ouvrirParcours(tester);
    await _toucher(tester, find.text(AppStrings.echangeCollegue));
    await _toucher(tester, find.text('Bruno D.'));
    await _toucher(tester, _bouton(AppStrings.echangeContinuer));

    expect(find.text(AppStrings.echangeAucuneGarde('Bruno D.')), findsOneWidget);
  });

  testWidgets('un refus de la base garde le récapitulatif, avec la cause', (
    tester,
  ) async {
    final depot = await _monter(tester);
    depot.prochaineReponse = const ResultatEchange(
      ok: false,
      code: 'weekend_quota_reached',
      qui: 'target',
    );
    await _ouvrirParcours(tester);
    await _toucher(tester, find.text(AppStrings.echangeCollegue));
    await _toucher(tester, find.text('Chloé C.'));
    await _toucher(tester, _bouton(AppStrings.echangeContinuer));
    await _toucher(tester, _bouton(AppStrings.echangeContinuer));
    await _toucher(tester, _bouton(AppStrings.echangeEnvoyer));

    expect(find.byType(DemandeEchangeScreen), findsOneWidget);
    final banniere = tester.widget<AppBanner>(find.byType(AppBanner));
    expect(banniere.variante, AppBannerVariante.erreur);
    expect(
      banniere.texte,
      AppStrings.echangeEnvoiRefuse(
        AppStrings.echangeCausePlafondWeekends('Chloé C.'),
      ),
    );
    expect(banniere.detail, AppStrings.echangeEnvoiRefuseAide);
  });

  testWidgets('personne de prévenu : l\'écran le dit (notified = 0)', (
    tester,
  ) async {
    final depot = await _monter(tester);
    depot.prochaineReponse = const ResultatEchange(ok: true, notifies: 0);
    await _ouvrirParcours(tester);
    await _toucher(tester, find.text(AppStrings.echangeCaserne));
    await _toucher(tester, _bouton(AppStrings.echangeContinuer));
    await _toucher(tester, _bouton(AppStrings.echangeEnvoyer));

    expect(find.text(AppStrings.echangeEnvoyeePersonne), findsOneWidget);
  });

  testWidgets('trop tard : le bouton est grisé et dit jusqu\'à quand', (
    tester,
  ) async {
    await _monter(
      tester,
      echanges: FauxEchangesRepository(
        reglagesServis: const ReglagesEchange(echeanceHeures: 168 * 4),
      ),
    );
    await _toucher(tester, find.byType(LigneDAstreinte));
    final bouton = tester.widget<PrimaryButton>(
      _bouton(AppStrings.echangeProposer),
    );
    expect(bouton.onPressed, isNull);
    expect(bouton.raisonDesactivation, startsWith('Trop tard'));
  });

  testWidgets('une demande en cours : section, mention, détail, annulation', (
    tester,
  ) async {
    final depot = FauxEchangesRepository(
      echanges: <Echange>[echange(demandeurId: _moi, demandeurNom: 'Marie L.')],
    );
    depot.apres = (String fonction, Map<String, dynamic> _) {
      depot.definir(<Echange>[
        echange(
          demandeurId: _moi,
          demandeurNom: 'Marie L.',
          statut: StatutEchange.annule,
          decideLe: _aujourdhui,
        ),
      ]);
    };
    await _monter(tester, echanges: depot);

    expect(find.text(AppStrings.echangeSection(1)), findsOneWidget);
    expect(find.byType(CarteEchange), findsOneWidget);
    expect(
      find.text(AppStrings.echangeEtatAttenteDe('Chloé C.')),
      findsOneWidget,
    );
    // La ligne d'astreinte porte la mention, pas un badge.
    expect(find.text(AppStrings.echangeEnCoursMention), findsOneWidget);

    await _toucher(tester, find.byType(CarteEchange));
    expect(
      find.text(AppStrings.echangeDetailTitreCession('nuit du samedi 24 octobre')),
      findsOneWidget,
    );
    await _toucher(tester, _bouton(AppStrings.echangeAnnuler));
    // La confirmation dit qui sera prévenu.
    expect(find.text(AppStrings.echangeAnnulerTitre), findsOneWidget);
    expect(
      find.text(
        AppStrings.echangeAnnulerTexteCollegue(
          'Chloé C.',
          'nuit du samedi 24 octobre',
        ),
      ),
      findsOneWidget,
    );
    await _toucher(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: _bouton(AppStrings.echangeAnnuler),
      ),
    );

    expect(depot.appels.single.$1, 'cancel_exchange');
    expect(find.text(AppStrings.echangeAnnulee), findsOneWidget);
    expect(find.text(AppStrings.echangeEtatAnnule), findsWidgets);
  });

  testWidgets('une adresse dont la garde n\'est plus proposable ramène aux '
      'astreintes', (tester) async {
    await _monter(tester);
    await ouvrirRoute(
      tester,
      Uri(
        path: AppRoutes.demandeEchange,
        queryParameters: AppRoutes.parametresDemandeEchange(
          attribution: 'att-inconnue',
          etape: EtapeDemande.verifier,
        ),
      ).toString(),
    );
    expect(emplacementCourant(tester), AppRoutes.astreintes);
    expect(find.text(AppStrings.echangeIntrouvable), findsOneWidget);
  });
}
