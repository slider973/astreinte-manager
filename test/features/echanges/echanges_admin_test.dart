/// **L'administrateur — la file des échanges** (ticket 073, `design/073 § 8`).
///
/// Deux touches pour valider : la ligne, puis la confirmation. La charge de
/// chacun après l'échange est sous les yeux, et un plafond d'astreintes
/// dépassé grise « Valider » avec sa raison.
library;

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/features/echanges/data/echanges_repository.dart';
import 'package:astreinte_sp/features/echanges/domain/echange.dart';
import 'package:astreinte_sp/features/echanges/domain/filtre_echanges.dart';
import 'package:astreinte_sp/features/echanges/presentation/echanges_admin_screen.dart';
import 'package:astreinte_sp/features/echanges/presentation/widgets/ligne_echange_admin.dart';
import 'package:astreinte_sp/features/echanges/presentation/widgets/panneau_decision_echange.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_echanges.dart';
import '../../support/faux_matrice.dart';

final DateTime _aujourdhui = DateTime(2026, 10, 4, 10);

const Appartenance _admin = Appartenance(
  id: 'm-admin',
  stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Saint-Martin',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
  nomAffiche: 'Marie D.',
);

Echange _acceptee() => echange(
  statut: StatutEchange.accepteParPair,
  repreneurId: 'u-chloe',
  repreneurNom: 'Chloé C.',
  accepteLe: DateTime(2026, 10, 4, 9, 50),
);

/// Chloé est disponible la nuit du 24, Antoine a trois astreintes.
FauxMatriceRepository _matrice({int chargeChloe = 2, int? maxChloe = 4}) =>
    FauxMatriceRepository(
      lignes: <LigneMatrice>[
        ligneMatrice(
          userId: 'u-chloe',
          nom: 'Chloé C.',
          jours: moisUniforme('.'),
          nuits: '${'.' * 23}D${'.' * 7}',
          astreintes: chargeChloe,
          maxAstreintes: maxChloe,
          maxWeekends: 2,
        ),
        ligneMatrice(
          userId: 'u-antoine',
          nom: 'Antoine C.',
          jours: moisUniforme('.'),
          nuits: moisUniforme('.'),
          astreintes: 3,
        ),
      ],
    );

Future<FauxEchangesRepository> _monter(
  WidgetTester tester,
  List<Echange> echanges, {
  FauxMatriceRepository? matrice,
  Appartenance appartenance = _admin,
  Size taille = const Size(390, 844),
  String? chemin,
}) async {
  final depot = FauxEchangesRepository(echanges: echanges);
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    echanges: depot,
    matrice: matrice ?? _matrice(),
    horloge: () => _aujourdhui,
    taille: taille,
  );
  await ouvrirRoute(
    tester,
    chemin ?? AppRoutes.echangesAdminFiltre(FiltreEchanges.aValider),
  );
  return depot;
}

Finder _bouton(String libelle) => find.widgetWithText(PrimaryButton, libelle);

Future<void> _toucher(WidgetTester tester, Finder quoi) async {
  await tester.ensureVisible(quoi);
  await tester.pumpAndSettle();
  await tester.tap(quoi);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('le lien /admin/exchanges ouvre la file à valider', (
    tester,
  ) async {
    final depot = await _monter(tester, <Echange>[
      _acceptee(),
    ], chemin: AppRoutes.lienEchangesAdmin);
    expect(find.byType(EchangesAdminScreen), findsOneWidget);
    expect(
      emplacementCourant(tester),
      AppRoutes.echangesAdminFiltre(FiltreEchanges.aValider),
    );
    // La lecture dit à la base qui lit, pour trier les demandes « à la
    // caserne » qui ne lui sont pas envoyées.
    expect(depot.derniereLecture?.admin, isTrue);
    expect(depot.derniereLecture?.moi, sessionMembre.userId);
    expect(find.text(AppStrings.echangesFiltreAValider(1)), findsOneWidget);
    expect(
      find.text(AppStrings.echangesLigneCede('Antoine C.', 'Chloé C.')),
      findsOneWidget,
    );
  });

  testWidgets('valider une cession : la ligne, puis la confirmation', (
    tester,
  ) async {
    final depot = await _monter(tester, <Echange>[_acceptee()]);
    await _toucher(tester, find.byType(LigneEchangeAdmin));

    expect(find.byType(PanneauDecisionEchange), findsOneWidget);
    expect(find.text(AppStrings.echangesChargeTitre), findsOneWidget);
    // Chloé passe à 3/4 astreintes en octobre ; Antoine libère sa garde.
    expect(find.textContaining('3/4 astr.'), findsOneWidget);
    expect(find.text(AppStrings.echangesLibere), findsOneWidget);
    expect(
      find.textContaining(AppStrings.echangesDispoDeclaree),
      findsOneWidget,
    );

    await _toucher(tester, _bouton(AppStrings.echangesValiderCession));
    expect(
      find.text(AppStrings.echangesConfirmerValiderCession),
      findsOneWidget,
    );
    expect(
      find.text(
        AppStrings.echangesConfirmerCession(
          'nuit du samedi 24 octobre',
          'Antoine C.',
          'Chloé C.',
        ),
      ),
      findsOneWidget,
    );
    depot.apres = (_, _) => depot.definir(<Echange>[
      echange(
        statut: StatutEchange.valide,
        repreneurId: 'u-chloe',
        repreneurNom: 'Chloé C.',
        decideLe: _aujourdhui,
      ),
    ]);
    await _toucher(tester, _bouton(AppStrings.echangesValiderEtPrevenir));

    expect(depot.appels.single.$1, 'decide_exchange');
    expect(depot.appels.single.$2, <String, dynamic>{
      'p_exchange': 'ech-1',
      'p_approve': true,
      'p_reason': null,
    });
    expect(
      find.text(AppStrings.echangesValide('Antoine C.', 'Chloé C.')),
      findsOneWidget,
    );
    expect(find.text(AppStrings.echangesVideAValiderTitre), findsOneWidget);
  });

  testWidgets('refuser avec un motif', (tester) async {
    final depot = await _monter(tester, <Echange>[_acceptee()]);
    await _toucher(tester, find.byType(LigneEchangeAdmin));
    await _toucher(tester, _bouton(AppStrings.echangesRefuser));

    expect(find.text(AppStrings.echangesRefuserTitre), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Équipe déjà complète');
    await _toucher(tester, _bouton(AppStrings.echangesRefuserEtPrevenir));

    expect(depot.appels.single.$2, <String, dynamic>{
      'p_exchange': 'ech-1',
      'p_approve': false,
      'p_reason': 'Équipe déjà complète',
    });
    expect(
      find.text(AppStrings.echangesRefuse('Antoine C.', 'Chloé C.')),
      findsOneWidget,
    );
  });

  testWidgets('un plafond d\'astreintes dépassé grise « Valider »', (
    tester,
  ) async {
    await _monter(tester, <Echange>[
      _acceptee(),
    ], matrice: _matrice(chargeChloe: 4));
    await _toucher(tester, find.byType(LigneEchangeAdmin));

    final valider = tester.widget<PrimaryButton>(
      _bouton(AppStrings.echangesValiderCession),
    );
    expect(valider.onPressed, isNull);
    expect(
      valider.raisonDesactivation,
      AppStrings.echangesDepasseAstreintes(4),
    );
    // « Refuser » reste.
    expect(
      tester
          .widget<PrimaryButton>(_bouton(AppStrings.echangesRefuser))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('un échec à la validation nomme la cause, rien n\'a changé', (
    tester,
  ) async {
    final depot = await _monter(tester, <Echange>[_acceptee()]);
    depot.prochaineReponse = const ResultatEchange(
      ok: false,
      code: 'exchange_failed',
      codeMotif: 'peer_already_assigned',
      detail: 'peer_taken_elsewhere',
    );
    await _toucher(tester, find.byType(LigneEchangeAdmin));
    await _toucher(tester, _bouton(AppStrings.echangesValiderCession));
    await _toucher(tester, _bouton(AppStrings.echangesValiderEtPrevenir));

    final banniere = tester.widget<AppBanner>(
      find.descendant(
        of: find.byType(PanneauDecisionEchange),
        matching: find.byType(AppBanner),
      ),
    );
    expect(banniere.variante, AppBannerVariante.erreur);
    expect(
      banniere.texte,
      AppStrings.echangesEchec(AppStrings.echangeCauseAilleurs),
    );
  });

  testWidgets('sa propre demande ne se tranche pas', (tester) async {
    final depot = await _monter(tester, <Echange>[_acceptee()]);
    depot.prochaineReponse = const ResultatEchange(
      ok: false,
      code: 'cannot_decide_own_exchange',
    );
    await _toucher(tester, find.byType(LigneEchangeAdmin));
    await _toucher(tester, _bouton(AppStrings.echangesValiderCession));
    await _toucher(tester, _bouton(AppStrings.echangesValiderEtPrevenir));
    expect(find.text(AppStrings.echangesPasSaDecision), findsOneWidget);
  });

  testWidgets('en large : le panneau à droite, la première ouverte d\'office', (
    tester,
  ) async {
    await _monter(tester, <Echange>[
      _acceptee(),
    ], taille: const Size(1440, 900));
    expect(find.byType(PanneauDecisionEchange), findsOneWidget);
    expect(_bouton(AppStrings.echangesValiderCession), findsOneWidget);
  });

  testWidgets('les filtres sont dans l\'adresse', (tester) async {
    await _monter(tester, <Echange>[
      _acceptee(),
      echange(id: 'ech-2', attributionId: 'att-2'),
      echange(
        id: 'ech-3',
        attributionId: 'att-3',
        statut: StatutEchange.expire,
        decideLe: _aujourdhui,
      ),
    ]);
    await _toucher(tester, find.text(AppStrings.echangesFiltreEnAttente(1)));
    expect(
      emplacementCourant(tester),
      AppRoutes.echangesAdminFiltre(FiltreEchanges.enAttente),
    );
    expect(find.byType(LigneEchangeAdmin), findsOneWidget);

    await _toucher(tester, find.text(AppStrings.echangesFiltreTermines));
    expect(find.text(AppStrings.echangeEtatExpire), findsOneWidget);
  });

  testWidgets('la file vide le dit', (tester) async {
    await _monter(tester, const <Echange>[]);
    expect(find.text(AppStrings.echangesVideAValiderTitre), findsOneWidget);
  });

  testWidgets('un membre ordinaire ne l\'ouvre pas', (tester) async {
    await _monter(tester, <Echange>[
      _acceptee(),
    ], appartenance: appartenanceMembre);
    expect(find.byType(EchangesAdminScreen), findsNothing);
    expect(emplacementCourant(tester), AppRoutes.accueil);
  });

  testWidgets('le Suivi annonce les échanges à valider', (tester) async {
    await _monter(tester, <Echange>[_acceptee()], chemin: AppRoutes.suivi);
    expect(find.text(AppStrings.echangesBlocSuivi(1)), findsOneWidget);
    await _toucher(tester, find.text(AppStrings.echangesBlocSuiviAction));
    expect(find.byType(EchangesAdminScreen), findsOneWidget);
  });
}
