/// À 390 points et ×1,6 d'échelle de texte, **rien ne déborde** : les
/// rangées de garde passent sur deux lignes, les filtres s'enroulent, les
/// boutons s'empilent (`design/073 § 13`). Un débordement lève une erreur de
/// rendu, et le test tombe.
library;

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/echanges/domain/echange.dart';
import 'package:astreinte_sp/features/echanges/domain/filtre_echanges.dart';
import 'package:astreinte_sp/features/echanges/presentation/widgets/carte_demande_recue.dart';
import 'package:astreinte_sp/features/echanges/presentation/widgets/carte_echange.dart';
import 'package:astreinte_sp/features/echanges/presentation/widgets/ligne_echange_admin.dart';
import 'package:astreinte_sp/features/echanges/presentation/widgets/panneau_echange.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_echanges.dart';
import '../../support/faux_matrice.dart';

final DateTime _aujourdhui = DateTime(2026, 10, 4, 10);

Echange _echangeAMoi({StatutEchange statut = StatutEchange.ouvert}) => echange(
  forme: FormeEchange.echange,
  statut: statut,
  cibleId: sessionMembre.userId,
  cibleNom: 'Marie L.',
  repreneurId: statut == StatutEchange.ouvert ? null : sessionMembre.userId,
  repreneurNom: statut == StatutEchange.ouvert ? null : 'Marie L.',
  demandeurNom: 'Antoine-Christophe de La Tour du Pin',
  gardeRendue: GardeEchange(
    jour: DateTime(2026, 10, 27),
    creneau: CreneauType.jour,
    attributionId: 'att-b',
  ),
);

Future<void> _agrandir(WidgetTester tester) async {
  tester.platformDispatcher.textScaleFactorTestValue = 1.6;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('le panneau de réponse d\'un échange, à ×1,6', (tester) async {
    await monterApp(
      tester,
      session: sessionMembre,
      appartenances: const <Appartenance>[appartenanceMembre],
      echanges: FauxEchangesRepository(echanges: <Echange>[_echangeAMoi()]),
      horloge: () => _aujourdhui,
    );
    await ouvrirRoute(tester, AppRoutes.lienEchanges);
    await _agrandir(tester);
    await tester.ensureVisible(find.byType(CarteDemandeRecue));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CarteDemandeRecue));
    await tester.pumpAndSettle();
    expect(find.byType(PanneauEchange), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la carte d\'échange dans Astreintes, à ×1,6', (tester) async {
    await monterApp(
      tester,
      session: sessionMembre,
      appartenances: const <Appartenance>[appartenanceMembre],
      echanges: FauxEchangesRepository(
        echanges: <Echange>[_echangeAMoi(statut: StatutEchange.accepteParPair)],
      ),
      horloge: () => _aujourdhui,
    );
    await ouvrirRoute(tester, AppRoutes.astreintes);
    await _agrandir(tester);
    expect(find.byType(CarteEchange), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la file et le panneau de décision, à ×1,6', (tester) async {
    await monterApp(
      tester,
      session: sessionMembre,
      appartenances: const <Appartenance>[
        Appartenance(
          id: 'm-admin',
          stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
          nomCaserne: 'CIS Saint-Martin',
          role: RoleMembre.admin,
          statut: StatutMembre.actif,
        ),
      ],
      echanges: FauxEchangesRepository(
        echanges: <Echange>[
          echange(
            forme: FormeEchange.echange,
            statut: StatutEchange.accepteParPair,
            repreneurId: 'u-chloe',
            repreneurNom: 'Chloé C.',
            gardeRendue: GardeEchange(
              jour: DateTime(2026, 10, 27),
              creneau: CreneauType.jour,
            ),
          ),
          for (var i = 0; i < 12; i++)
            echange(id: 'o-$i', attributionId: 'att-o-$i'),
        ],
      ),
      matrice: FauxMatriceRepository(
        lignes: <LigneMatrice>[
          ligneMatrice(
            userId: 'u-chloe',
            nom: 'Chloé C.',
            jours: moisUniforme('.'),
            nuits: moisUniforme('D'),
            astreintes: 2,
            maxAstreintes: 8,
            maxWeekends: 2,
          ),
          ligneMatrice(
            userId: 'u-antoine',
            nom: 'Antoine C.',
            jours: moisUniforme('A'),
            nuits: moisUniforme('.'),
            astreintes: 5,
            maxAstreintes: 8,
          ),
        ],
      ),
      horloge: () => _aujourdhui,
    );
    await ouvrirRoute(
      tester,
      AppRoutes.echangesAdminFiltre(FiltreEchanges.aValider),
    );
    await _agrandir(tester);
    expect(find.text(AppStrings.echangesFiltreEnAttente(12)), findsOneWidget);
    await tester.tap(find.byType(LigneEchangeAdmin).first);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.echangesChargeTitre), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
