/// Plusieurs casernes (ticket 072) : après une bascule, **aucune demande
/// d'échange de l'ancienne caserne n'est peinte** avant la première réponse
/// de la nouvelle.
library;

import 'dart:async';

import 'package:astreinte_sp/app.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/bascule_caserne.dart';
import 'package:astreinte_sp/features/echanges/domain/echange.dart';
import 'package:astreinte_sp/features/echanges/presentation/widgets/carte_demande_recue.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_echanges.dart';

const Appartenance _sud = Appartenance(
  id: 'm-sud',
  stationId: 'bbbbbbbb-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Val-de-Loue',
  role: RoleMembre.membre,
  statut: StatutMembre.actif,
);

void main() {
  testWidgets('après une bascule, aucune demande de l\'ancienne caserne '
      'n\'est peinte avant la première réponse', (tester) async {
    final moi = sessionMembre.userId;
    final depot = FauxEchangesRepository(
      echanges: <Echange>[echange(cibleId: moi, demandeurNom: 'Antoine Nord')],
    );
    depot.parCaserne[_sud.stationId] = <Echange>[
      echange(id: 'ech-sud', cibleId: moi, demandeurNom: 'Bruno Sud'),
    ];
    final retenue = Completer<void>();
    depot.retenues[_sud.stationId] = retenue;

    await monterApp(
      tester,
      session: sessionMembre,
      appartenances: const <Appartenance>[appartenanceMembre, _sud],
      echanges: depot,
      horloge: () => DateTime(2026, 10, 4, 10),
    );
    await ouvrirRoute(tester, AppRoutes.lienEchanges);
    expect(find.textContaining('Antoine Nord'), findsWidgets);

    unawaited(
      ProviderScope.containerOf(
        tester.element(find.byType(AstreinteApp)),
      ).read(basculeCaserneProvider.notifier).choisir(_sud.stationId),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Nord a disparu, Sud n'est pas encore là.
    expect(find.textContaining('Antoine Nord'), findsNothing);
    expect(find.textContaining('Bruno Sud'), findsNothing);
    expect(find.byType(CarteDemandeRecue), findsNothing);

    retenue.complete();
    await tester.pumpAndSettle();

    expect(find.textContaining('Bruno Sud'), findsWidgets);
    expect(find.textContaining('Antoine Nord'), findsNothing);
    tester.takeException();
  });
}
