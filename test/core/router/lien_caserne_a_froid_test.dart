import 'dart:async';

import 'package:astreinte_sp/app.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_superadmin.dart';

/// **Un lien d'une autre caserne, application fermée** (ticket 072).
///
/// C'est le cas principal : le service worker ouvre une fenêtre sur
/// `/proposals?station=<uuid>` quand on touche une notification alors que la
/// PWA est fermée, et un courriel porte la même forme. L'adresse est gardée
/// par la destination initiale pendant la restauration de session ; elle doit
/// finir sur la bonne route, **dans la bonne caserne**, avec le bandeau.
///
/// Même décor que `destination_a_froid_test.dart` : la session et le droit de
/// l'éditeur arrivent dans la même image, et une seconde passe de redirection
/// repart du `/demarrage` périmé.
const Appartenance _nord = appartenanceMembre;

const Appartenance _sud = Appartenance(
  id: 'm-sud',
  stationId: 'bbbbbbbb-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Val-de-Loue',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
);

Future<ProviderContainer> _demarrageAFroid(
  WidgetTester tester, {
  required String cible,
}) async {
  final porte = Completer<void>();
  final faux = await monterApp(
    tester,
    sessionEnAttente: true,
    appartenances: const <Appartenance>[_nord, _sud],
    superAdmin: FauxSuperAdminRepository(autorise: false, porte: porte),
    stabiliser: false,
  );

  await ouvrirRoute(tester, cible, stabiliser: false);
  expect(emplacementCourant(tester), AppRoutes.demarrage);

  faux.auth.ouvrirSession(sessionMembre);
  porte.complete();
  await tester.idle();

  final conteneur = ProviderScope.containerOf(
    tester.element(find.byType(AstreinteApp)),
  );
  conteneur.read(appRouterProvider).refresh();

  await tester.pumpAndSettle();
  return conteneur;
}

void main() {
  testWidgets('un lien de membre d\'une autre caserne : la bonne route, la '
      'bonne caserne, le bandeau', (tester) async {
    final conteneur = await _demarrageAFroid(
      tester,
      cible: '${AppRoutes.lienPropositions}?station=${_sud.stationId}',
    );

    expect(emplacementCourant(tester), '/boite?onglet=propositions');
    expect(
      conteneur.read(appartenanceCouranteProvider)?.stationId,
      _sud.stationId,
    );
    expect(
      find.text(AppStrings.bandeauRaisonLien(_nord.nomCaserne)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('un lien d\'administration d\'une caserne où l\'on est admin : '
      'le rôle de cette caserne-là ouvre le suivi', (tester) async {
    // Membre à Nord, ouverte par défaut ; administrateur à Sud. Une garde qui
    // lirait le rôle de Nord renverrait sur l'accueil.
    final conteneur = await _demarrageAFroid(
      tester,
      cible: '/admin/schedule/2026-11?station=${_sud.stationId}',
    );

    expect(emplacementCourant(tester), '/admin/suivi?mois=2026-11');
    expect(
      conteneur.read(appartenanceCouranteProvider)?.stationId,
      _sud.stationId,
    );
    expect(
      find.text(AppStrings.bandeauRaisonLien(_nord.nomCaserne)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('un lien d\'une caserne étrangère : l\'accueil, dans la caserne '
      'ouverte, sans bandeau', (tester) async {
    final conteneur = await _demarrageAFroid(
      tester,
      cible:
          '${AppRoutes.lienPropositions}'
          '?station=cccccccc-0000-4000-8000-000000000001',
    );

    expect(emplacementCourant(tester), AppRoutes.accueil);
    expect(
      conteneur.read(appartenanceCouranteProvider)?.stationId,
      _nord.stationId,
    );
    expect(find.textContaining(' est ouverte.'), findsNothing);
  });
}
