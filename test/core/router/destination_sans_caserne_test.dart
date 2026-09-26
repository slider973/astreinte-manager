import 'dart:async';

import 'package:astreinte_sp/app.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/router/destination_initiale.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/features/auth/presentation/aucune_caserne_screen.dart';
import 'package:astreinte_sp/features/superadmin/presentation/superadmin_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_superadmin.dart';

/// **La destination d'un compte sans caserne** (ticket 056).
///
/// La reprise de la destination mémorisée n'avait lieu qu'en
/// `EtatAuth.connecte`. L'éditeur du produit, membre d'aucune caserne, est en
/// `EtatAuth.sansCaserne` : `/superadmin` ouvert à froid finissait sur
/// « Aucune caserne », et la destination restait gardée sans jamais être
/// consommée — prête à ressortir plus tard, ailleurs.
///
/// Cet état n'a qu'une destination légitime, `/superadmin`, et seulement pour
/// l'éditeur. Toute autre est refusée, et **consommée** quand même.
void main() {
  testWidgets('un éditeur sans caserne arrive sur /superadmin à froid', (
    tester,
  ) async {
    final conteneur = await _demarrageAFroid(
      tester,
      cible: AppRoutes.superAdmin,
      editeur: true,
    );

    expect(emplacementCourant(tester), AppRoutes.superAdmin);
    expect(find.byType(SuperAdminScreen), findsOneWidget);
    expect(conteneur.read(destinationInitialeProvider).gardee, isNull);
  });

  // Le droit de l'éditeur arrive **après** l'état sans caserne : la
  // destination attend la réponse de la base au lieu d'être condamnée sur un
  // statut inconnu.
  testWidgets('la destination attend le droit de l\'éditeur', (tester) async {
    final porte = Completer<void>();
    final faux = await monterApp(
      tester,
      sessionEnAttente: true,
      membres: FauxMembresRepository(),
      superAdmin: FauxSuperAdminRepository(porte: porte),
      stabiliser: false,
    );

    await ouvrirRoute(tester, AppRoutes.superAdmin, stabiliser: false);
    faux.auth.ouvrirSession(sessionMembre);
    await tester.pumpAndSettle();
    expect(emplacementCourant(tester), AppRoutes.aucuneCaserne);

    porte.complete();
    await tester.pumpAndSettle();

    expect(emplacementCourant(tester), AppRoutes.superAdmin);
  });

  testWidgets(
    'un compte sans caserne non éditeur reste sur « Aucune caserne », '
    'et sa destination est oubliée',
    (tester) async {
      final conteneur = await _demarrageAFroid(
        tester,
        cible: AppRoutes.membres,
        editeur: false,
      );

      expect(emplacementCourant(tester), AppRoutes.aucuneCaserne);
      expect(find.byType(AucuneCaserneScreen), findsOneWidget);
      expect(conteneur.read(destinationInitialeProvider).gardee, isNull);
    },
  );

  // Le lancement suivant, sans déconnexion entre les deux : le compte relit
  // ses appartenances et se découvre administrateur d'une caserne — une
  // invitation acceptée ailleurs, un rôle rendu. La destination refusée ne
  // doit pas ressortir à ce moment-là : ce n'était plus une intention, c'était
  // un reste.
  testWidgets('la destination refusée ne ressort pas au lancement suivant', (
    tester,
  ) async {
    final faux = await monterApp(
      tester,
      sessionEnAttente: true,
      membres: FauxMembresRepository(),
      superAdmin: FauxSuperAdminRepository(autorise: false),
      stabiliser: false,
    );

    await ouvrirRoute(tester, AppRoutes.membres, stabiliser: false);
    expect(emplacementCourant(tester), AppRoutes.demarrage);

    faux.auth.ouvrirSession(sessionMembre);
    await tester.pumpAndSettle();
    expect(emplacementCourant(tester), AppRoutes.aucuneCaserne);

    faux.memberships.appartenances = const <Appartenance>[appartenanceAdmin];
    ProviderScope.containerOf(
      tester.element(find.byType(AstreinteApp)),
    ).invalidate(appartenancesProvider);
    await tester.pumpAndSettle();

    expect(emplacementCourant(tester), AppRoutes.accueil);
  });
}

/// Un démarrage à froid sur [cible], sans aucune caserne, où le droit de
/// l'éditeur et la session arrivent **dans la même image**, suivis d'une
/// seconde notification repartie du `/demarrage` périmé : la danse du
/// ticket 045.
Future<ProviderContainer> _demarrageAFroid(
  WidgetTester tester, {
  required String cible,
  required bool editeur,
}) async {
  final porte = Completer<void>();
  final faux = await monterApp(
    tester,
    sessionEnAttente: true,
    membres: FauxMembresRepository(),
    superAdmin: FauxSuperAdminRepository(autorise: editeur, porte: porte),
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
