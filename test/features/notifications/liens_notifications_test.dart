import 'dart:async';

import 'package:astreinte_sp/app.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/features/boite/domain/onglet_boite.dart';
import 'package:astreinte_sp/core/router/destination_initiale.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/demarrage/presentation/demarrage_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_periodes.dart';

const Appartenance _admin = Appartenance(
  id: 'm-3',
  stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Saint-Martin',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
);

void main() {
  group('Ouverture depuis une notification', () {
    testWidgets('chaque destination de WORKFLOWS § 8 mène au bon écran', (
      tester,
    ) async {
      final attendu = <String, String>{
        '/proposals': AppRoutes.boiteOnglet(OngletBoite.propositions),
        '/schedule/2026-10': AppRoutes.astreintes,
        '/availability/2026-10': '/calendrier?mois=2026-10',
        '/admin/schedule/2026-10': '/admin/suivi?mois=2026-10',
      };

      for (final lien in attendu.entries) {
        await monterApp(
          tester,
          session: sessionMembre,
          appartenances: const <Appartenance>[_admin],
          periodes: FauxPeriodesRepository(),
        );

        await ouvrirRoute(tester, lien.key);

        expect(emplacementCourant(tester), lien.value, reason: lien.key);
        await demonter(tester);
      }
    });

    testWidgets(
      'un lien admin reçu par un membre ramène à l\'accueil, sans reproche',
      (tester) async {
        await monterApp(
          tester,
          session: sessionMembre,
          appartenances: const <Appartenance>[appartenanceMembre],
        );

        await ouvrirRoute(tester, '/admin/schedule/2026-10');

        expect(emplacementCourant(tester), '/');
        expect(find.textContaining('refus'), findsNothing);
        expect(find.textContaining('Accès'), findsNothing);
      },
    );

    testWidgets('un mois forgé ne se promène pas dans l\'URL', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
      );

      await ouvrirRoute(tester, '/availability/2026-99');

      expect(emplacementCourant(tester), '/');
    });

    testWidgets(
      'la destination survit au démarrage à froid, session à restaurer '
      '(ticket 039)',
      (tester) async {
        // Démarrage à froid : la session est encore en cours de restauration,
        // l'application affiche son écran d'attente. C'est exactement ce que
        // vit un pompier qui touche une notification, application fermée.
        final faux = await monterApp(
          tester,
          sessionEnAttente: true,
          appartenances: const <Appartenance>[appartenanceMembre],
          stabiliser: false,
        );
        expect(find.byType(DemarrageScreen), findsOneWidget);

        await ouvrirRoute(tester, '/availability/2026-10', stabiliser: false);
        expect(emplacementCourant(tester), AppRoutes.demarrage);

        faux.auth.ouvrirSession(sessionMembre);
        await tester.pumpAndSettle();

        expect(emplacementCourant(tester), '/calendrier?mois=2026-10');
      },
    );

    testWidgets('sans lien profond, la restauration mène à l\'accueil', (
      tester,
    ) async {
      final faux = await monterApp(
        tester,
        sessionEnAttente: true,
        appartenances: const <Appartenance>[appartenanceMembre],
        stabiliser: false,
      );

      faux.auth.ouvrirSession(sessionMembre);
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), '/');
    });
  });

  group('La destination gardée ne fuit pas d\'une session à l\'autre', () {
    testWidgets(
      'un écran quitté à la déconnexion n\'attend pas la personne suivante',
      (tester) async {
        // Téléphone prêté, véhicule partagé : un chef de centre se déconnecte
        // depuis l'écran des périodes, un pompier se connecte derrière lui.
        // Aucune URL forgée dans ce scénario, seulement deux personnes et un
        // appareil.
        final faux = await monterApp(
          tester,
          session: sessionMembre,
          appartenances: const <Appartenance>[_admin],
          periodes: FauxPeriodesRepository(),
        );
        final conteneur = ProviderScope.containerOf(
          tester.element(find.byType(AstreinteApp)),
        );

        await ouvrirRoute(tester, AppRoutes.periodes);
        expect(emplacementCourant(tester), AppRoutes.periodes);

        unawaited(faux.auth.seDeconnecter());
        await tester.pumpAndSettle();
        expect(emplacementCourant(tester), AppRoutes.connexion);

        expect(
          conteneur
              .read(destinationInitialeProvider)
              .reprendre(AppRoutes.connexion),
          isNull,
          reason: 'l\'écran des périodes ne doit pas attendre le suivant',
        );
      },
    );

    testWidgets(
      'un lien ouvert alors que personne n\'est connecté n\'est pas rejoué',
      (tester) async {
        final faux = await monterApp(
          tester,
          appartenances: const <Appartenance>[appartenanceMembre],
        );

        await ouvrirRoute(tester, '/proposals');
        expect(emplacementCourant(tester), AppRoutes.connexion);

        faux.auth.ouvrirSession(sessionMembre);
        await tester.pumpAndSettle();

        expect(emplacementCourant(tester), AppRoutes.accueil);
      },
    );
  });

  group('Garde de rôle sur l\'administration', () {
    testWidgets('un membre n\'ouvre aucun écran d\'administration', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
      );

      for (final chemin in <String>[
        AppRoutes.membres,
        '${AppRoutes.membres}/${AppRoutes.inviterChemin}',
        AppRoutes.parametres,
        AppRoutes.periodes,
      ]) {
        await ouvrirRoute(tester, chemin);
        expect(emplacementCourant(tester), AppRoutes.accueil, reason: chemin);
      }
    });

    testWidgets('un admin, lui, les ouvre', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[_admin],
        periodes: FauxPeriodesRepository(),
      );

      await ouvrirRoute(tester, AppRoutes.periodes);

      expect(emplacementCourant(tester), AppRoutes.periodes);
    });
  });
}
