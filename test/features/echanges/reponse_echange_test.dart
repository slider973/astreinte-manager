/// **Pompier B — recevoir, reprendre, répondre** (ticket 073,
/// `design/073 § 7`).
///
/// Trois touches depuis la notification : le lien `/exchanges`, la carte, la
/// réponse. Pas de confirmation : le panneau en est une.
library;

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/features/boite/domain/onglet_boite.dart';
import 'package:astreinte_sp/features/echanges/data/echanges_repository.dart';
import 'package:astreinte_sp/features/echanges/domain/echange.dart';
import 'package:astreinte_sp/features/echanges/presentation/widgets/carte_demande_recue.dart';
import 'package:astreinte_sp/features/echanges/presentation/widgets/panneau_echange.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_echanges.dart';

final DateTime _aujourdhui = DateTime(2026, 10, 4, 10);
final String _moi = sessionMembre.userId;

Future<FauxEchangesRepository> _monter(
  WidgetTester tester,
  List<Echange> echanges, {
  Size taille = const Size(390, 844),
}) async {
  final depot = FauxEchangesRepository(echanges: echanges);
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    echanges: depot,
    horloge: () => _aujourdhui,
    taille: taille,
  );
  await ouvrirRoute(tester, AppRoutes.lienEchanges);
  return depot;
}

Finder _bouton(String libelle) => find.widgetWithText(PrimaryButton, libelle);

Future<void> _toucher(WidgetTester tester, Finder quoi) async {
  await tester.ensureVisible(quoi);
  await tester.pumpAndSettle();
  await tester.tap(quoi);
  await tester.pumpAndSettle();
}

Echange _cessionAMoi() => echange(cibleId: _moi, cibleNom: 'Marie L.');

void main() {
  testWidgets('/exchanges ouvre les propositions de la Boîte, demandes en '
      'tête', (tester) async {
    await _monter(tester, <Echange>[_cessionAMoi()]);
    expect(
      emplacementCourant(tester),
      AppRoutes.boiteOnglet(OngletBoite.propositions),
    );
    expect(find.text(AppStrings.echangeGroupeRecues(1)), findsOneWidget);
    expect(find.byType(CarteDemandeRecue), findsOneWidget);
    expect(
      find.text(AppStrings.echangeLigneCession('Antoine C.')),
      findsOneWidget,
    );
  });

  testWidgets('accepter une cession : une touche, l\'accord part', (
    tester,
  ) async {
    final depot = await _monter(tester, <Echange>[_cessionAMoi()]);
    await _toucher(tester, find.byType(CarteDemandeRecue));

    expect(find.byType(PanneauEchange), findsOneWidget);
    expect(
      find.text(AppStrings.echangePanneauTitreCession('Antoine C.')),
      findsOneWidget,
    );
    // Une cession : une seule rangée, « Tu prends ».
    expect(find.text(AppStrings.echangeTuPrends), findsOneWidget);
    expect(find.text(AppStrings.echangeTuDonnes), findsNothing);

    depot.apres = (_, _) => depot.definir(<Echange>[]);
    await _toucher(tester, _bouton(AppStrings.echangeAccepterGarde));

    expect(depot.appels.single.$1, 'respond_exchange');
    expect(depot.appels.single.$2, <String, dynamic>{
      'p_exchange': 'ech-1',
      'p_accept': true,
    });
    expect(find.text(AppStrings.echangeAccordEnvoye), findsOneWidget);
    expect(find.byType(CarteDemandeRecue), findsNothing);
  });

  testWidgets('un échange se lit « Tu donnes » d\'abord', (tester) async {
    await _monter(tester, <Echange>[
      echange(
        forme: FormeEchange.echange,
        cibleId: _moi,
        gardeRendue: GardeEchange(
          jour: DateTime(2026, 10, 27),
          creneau: CreneauType.jour,
          attributionId: 'att-b',
        ),
      ),
    ]);
    await _toucher(tester, find.byType(CarteDemandeRecue));

    final donnes = tester.getTopLeft(find.text(AppStrings.echangeTuDonnes));
    final prends = tester.getTopLeft(find.text(AppStrings.echangeTuPrends));
    expect(donnes.dy, lessThan(prends.dy));
    expect(_bouton(AppStrings.echangeAccepterEchange), findsOneWidget);
  });

  testWidgets('refuser : sans motif, sans confirmation', (tester) async {
    final depot = await _monter(tester, <Echange>[_cessionAMoi()]);
    await _toucher(tester, find.byType(CarteDemandeRecue));
    await _toucher(tester, _bouton(AppStrings.echangeRefuser));

    expect(depot.appels.single.$2['p_accept'], isFalse);
    expect(find.text(AppStrings.echangeRefusEnvoye('Antoine C.')), findsOneWidget);
  });

  testWidgets('à reprendre : « Je la prends », et rien pour refuser', (
    tester,
  ) async {
    await _monter(tester, <Echange>[echange(cibleId: null, cibleNom: null)]);
    expect(
      find.text(AppStrings.echangeLigneReprendre('Antoine C.')),
      findsOneWidget,
    );
    await _toucher(tester, find.byType(CarteDemandeRecue));
    expect(_bouton(AppStrings.echangeJeLaPrends), findsOneWidget);
    expect(_bouton(AppStrings.echangeRefuser), findsNothing);
    expect(find.text(AppStrings.echangePanneauInfoReprendre), findsOneWidget);
  });

  testWidgets('la course perdue : une information, jamais un rouge', (
    tester,
  ) async {
    final depot = await _monter(tester, <Echange>[
      echange(cibleId: null, cibleNom: null),
    ]);
    depot.prochaineReponse = const ResultatEchange(
      ok: false,
      code: 'exchange_not_open',
      statut: StatutEchange.accepteParPair,
    );
    await _toucher(tester, find.byType(CarteDemandeRecue));
    await _toucher(tester, _bouton(AppStrings.echangeJeLaPrends));

    final banniere = tester.widget<AppBanner>(
      find.descendant(
        of: find.byType(PanneauEchange),
        matching: find.byType(AppBanner),
      ),
    );
    expect(banniere.variante, AppBannerVariante.information);
    expect(banniere.texte, AppStrings.echangeDejaReprise);
    // Boutons inertes : la demande n'est plus ouverte.
    expect(
      tester
          .widget<PrimaryButton>(_bouton(AppStrings.echangeJeLaPrends))
          .onPressed,
      isNull,
    );
  });

  testWidgets('une règle refuse : erreur dans le panneau, la carte reste', (
    tester,
  ) async {
    final depot = await _monter(tester, <Echange>[_cessionAMoi()]);
    depot.prochaineReponse = const ResultatEchange(
      ok: false,
      code: 'weekend_quota_reached',
    );
    await _toucher(tester, find.byType(CarteDemandeRecue));
    await _toucher(tester, _bouton(AppStrings.echangeAccepterGarde));

    final banniere = tester.widget<AppBanner>(
      find.descendant(
        of: find.byType(PanneauEchange),
        matching: find.byType(AppBanner),
      ),
    );
    expect(banniere.variante, AppBannerVariante.erreur);
    expect(banniere.texte, AppStrings.echangeTonPlafondWeekends);
  });

  testWidgets('validation automatique : la garde est à toi tout de suite', (
    tester,
  ) async {
    final depot = await _monter(tester, <Echange>[_cessionAMoi()]);
    depot.prochaineReponse = const ResultatEchange(
      ok: true,
      statut: StatutEchange.valide,
      autoValide: true,
    );
    await _toucher(tester, find.byType(CarteDemandeRecue));
    await _toucher(tester, _bouton(AppStrings.echangeAccepterGarde));

    expect(
      find.text(AppStrings.echangeAccordValide('nuit du samedi 24 octobre')),
      findsOneWidget,
    );
  });

  testWidgets('l\'accueil compte la demande parmi ce qu\'on te demande', (
    tester,
  ) async {
    await _monter(tester, <Echange>[_cessionAMoi()]);
    await ouvrirRoute(tester, AppRoutes.accueil);
    expect(find.byType(CarteDemandeRecue), findsOneWidget);
  });

  testWidgets('« Tout » range la demande à son arrivée', (tester) async {
    await _monter(tester, <Echange>[_cessionAMoi()]);
    await ouvrirRoute(tester, AppRoutes.boiteOnglet(OngletBoite.tout));
    expect(find.byType(CarteDemandeRecue), findsOneWidget);
  });

  testWidgets('en large, la réponse vit dans le volet latéral', (tester) async {
    await _monter(tester, <Echange>[
      _cessionAMoi(),
    ], taille: const Size(1440, 900));
    await _toucher(tester, find.byType(CarteDemandeRecue));
    expect(find.byType(PanneauEchange), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await _toucher(tester, find.byTooltip(AppStrings.echangeFermer));
    expect(find.byType(PanneauEchange), findsNothing);
  });
}
