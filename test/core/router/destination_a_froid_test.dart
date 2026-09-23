import 'dart:async';

import 'package:astreinte_sp/app.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/router/destination_initiale.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_superadmin.dart';

/// **La destination perdue au chargement à froid** (ticket 045).
///
/// Ouvrir l'application sur une adresse précise, application fermée, tombait
/// une fois sur trois sur l'accueil. Dans Chrome, pour une destination
/// d'administration **comme pour une destination de membre** : le rôle n'y
/// était pour rien, contrairement à ce que le ticket supposait.
///
/// Ce que la trace de la redirection a montré : `go_router` recalcule sa
/// redirection à chaque notification de son `refreshListenable`, et il la
/// recalcule **à partir de l'emplacement que le navigateur affiche**, lequel
/// n'apprend la décision de la passe précédente qu'à la fin de l'image. Le
/// droit de l'éditeur et l'état d'authentification arrivent souvent dans la
/// même image : deux passes partent alors du même `/demarrage` périmé. La
/// première menait à la destination et vidait la mémoire ; la seconde, sans
/// rien à rejouer, renvoyait à l'accueil. C'est la seconde qui gagne.
///
/// Ces tests font arriver les deux réponses dans la même image, avec une seule
/// barrière pour les deux. Sans le correctif, ils finissent sur `/`.
void main() {
  group('Deux passes de redirection dans la même image', () {
    testWidgets('une destination d\'administration est tenue', (tester) async {
      await _demarrageAFroid(
        tester,
        cible: AppRoutes.membres,
        appartenance: appartenanceAdmin,
      );

      expect(emplacementCourant(tester), AppRoutes.membres);
    });

    testWidgets('une destination de membre est tenue', (tester) async {
      await _demarrageAFroid(
        tester,
        cible: '${AppRoutes.calendrier}?mois=2026-10',
        appartenance: appartenanceMembre,
      );

      expect(
        emplacementCourant(tester),
        '${AppRoutes.calendrier}?mois=2026-10',
      );
    });

    // Le correctif ne doit pas rouvrir la boucle fermée au ticket 031 : une
    // destination que la garde refuse laisse toujours sur l'accueil, et
    // l'application garde un écran.
    testWidgets('une destination refusée laisse sur l\'accueil', (
      tester,
    ) async {
      await _demarrageAFroid(
        tester,
        cible: AppRoutes.membres,
        appartenance: appartenanceMembre,
      );

      expect(emplacementCourant(tester), AppRoutes.accueil);
    });
  });

  group('DestinationInitiale', () {
    test('la destination survit à une seconde passe de la même image', () {
      final differe = <void Function()>[];
      final destination = DestinationInitiale(aLaProchaineImage: differe.add)
        ..memoriser(AppRoutes.membres);

      // Première passe : l'écran d'attente, puis l'accueil, puis la
      // destination.
      destination.repartDeLAttente();
      expect(destination.reprendre(AppRoutes.accueil), AppRoutes.membres);
      expect(destination.reprendre(AppRoutes.membres), isNull);

      // Seconde passe de la même image, repartie du même `/demarrage` périmé.
      destination.repartDeLAttente();
      expect(destination.reprendre(AppRoutes.accueil), AppRoutes.membres);

      // L'image se termine : la destination est relâchée, et une passe plus
      // tardive ne ramène plus personne en arrière.
      for (final oubli in differe) {
        oubli();
      }
      destination.repartDeLAttente();
      expect(destination.reprendre(AppRoutes.accueil), isNull);
    });

    // Les quatre liens publics des notifications n'ont pas d'écran à eux : ils
    // redirigent. La destination ne doit pas les ramener en boucle dans la
    // **même** chaîne de redirection.
    test('un lien qui redirige ne revient pas en boucle', () {
      final destination = DestinationInitiale(aLaProchaineImage: (_) {})
        ..memoriser(AppRoutes.lienPropositions);

      destination.repartDeLAttente();
      expect(
        destination.reprendre(AppRoutes.accueil),
        AppRoutes.lienPropositions,
      );
      // La chaîne passe par le lien, qui redirige ailleurs : on n'y retourne
      // pas.
      expect(destination.reprendre(AppRoutes.lienPropositions), isNull);
      expect(destination.reprendre('/?onglet=1'), isNull);
    });

    test('y être déjà rend la reprise inutile', () {
      final destination = DestinationInitiale(aLaProchaineImage: (_) {})
        ..memoriser(AppRoutes.membres);

      expect(destination.reprendre(AppRoutes.membres), isNull);
    });
  });
}

/// Un démarrage à froid sur [cible] où le droit de l'éditeur et les
/// appartenances arrivent **dans la même image**, comme dans le navigateur.
Future<void> _demarrageAFroid(
  WidgetTester tester, {
  required String cible,
  required Appartenance appartenance,
}) async {
  final porte = Completer<void>();
  final faux = await monterApp(
    tester,
    sessionEnAttente: true,
    appartenances: <Appartenance>[appartenance],
    membres: FauxMembresRepository(),
    superAdmin: FauxSuperAdminRepository(autorise: false, porte: porte),
    stabiliser: false,
  );

  // L'adresse demandée au lancement : le routeur la met de côté et affiche
  // l'écran d'attente.
  await ouvrirRoute(tester, cible, stabiliser: false);
  expect(emplacementCourant(tester), AppRoutes.demarrage);

  // La session s'ouvre et le droit de l'éditeur se débloque. Les microtâches
  // tournent, la redirection retombe — mais **aucune image** n'a encore eu
  // lieu, donc le navigateur affiche toujours `/demarrage`.
  faux.auth.ouvrirSession(sessionMembre);
  porte.complete();
  await tester.idle();

  // La seconde notification de la même image. `GoRouter.refresh` est
  // exactement ce que `refreshListenable` déclenche, et elle repart de
  // l'emplacement que le navigateur affiche : le `/demarrage` périmé.
  final conteneur = ProviderScope.containerOf(
    tester.element(find.byType(AstreinteApp)),
  );
  conteneur.read(appRouterProvider).refresh();

  await tester.pumpAndSettle();
}
