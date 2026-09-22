import 'dart:async';

import 'package:astreinte_sp/app.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/appartenances_locales.dart';
import 'package:astreinte_sp/core/session/caserne_choisie.dart';
import 'package:astreinte_sp/core/session/session_utilisateur.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/features/auth/presentation/connexion_screen.dart';
import 'package:astreinte_sp/features/superadmin/data/superadmin_repository.dart';
import 'package:astreinte_sp/features/superadmin/presentation/superadmin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_superadmin.dart';

/// La personne suivante sur le même appareil : ni l'éditeur, ni le même
/// compte. C'est elle qui prouve que rien ne lui est rendu.
const SessionUtilisateur _personneSuivante = SessionUtilisateur(
  userId: 'aaaaaaaa-0000-4000-8000-000000000102',
  email: 'membre2@caserne-a.test',
);

Finder get _boutonDeconnexion =>
    find.widgetWithText(PrimaryButton, AppStrings.seDeconnecter);

/// Les clés que l'appareil garde du compte connecté.
Set<String> _clesDuCompte(SharedPreferences prefs) => prefs
    .getKeys()
    .where(
      (String cle) =>
          cle.startsWith(AppartenancesLocalesPartagees.prefixe) ||
          cle.startsWith(CaserneChoisieLocalePartagee.prefixe),
    )
    .toSet();

void main() {
  group('La sortie de l\'écran de l\'éditeur', () {
    testWidgets('elle est à l\'écran, sans défilement, sur un téléphone', (
      WidgetTester tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        membres: FauxMembresRepository(),
        superAdmin: FauxSuperAdminRepository(),
      );
      await ouvrirRoute(tester, AppRoutes.superAdmin);
      expect(find.byType(SuperAdminScreen), findsOneWidget);

      // Rien n'a été fait défiler entre l'ouverture et cette mesure, et la
      // fenêtre de `monterApp` est celle d'un téléphone : c'est là que la
      // hauteur manque.
      expect(_boutonDeconnexion, findsOneWidget);
      final fenetre = tester.getSize(find.byType(SuperAdminScreen));
      final cible = tester.getRect(_boutonDeconnexion);
      expect(cible.top, greaterThanOrEqualTo(0));
      expect(cible.bottom, lessThanOrEqualTo(fenetre.height));
      expect(
        cible.height,
        greaterThanOrEqualTo(44),
        reason: 'Cible tactile minimale du produit.',
      );

      // Hors de la liste : c'est ce qui la rend indépendante du défilement.
      expect(
        find.descendant(of: find.byType(ListView), matching: _boutonDeconnexion),
        findsNothing,
      );
    });

    // Les quatre états de l'écran partagent le même pied : un éditeur dont la
    // liste échoue doit pouvoir partir, pas seulement réessayer.
    testWidgets('elle reste là quand la liste échoue', (
      WidgetTester tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        membres: FauxMembresRepository(),
        superAdmin: FauxSuperAdminRepository(
          echecLecture: ErreurSuperAdmin.reseau,
        ),
      );
      await ouvrirRoute(tester, AppRoutes.superAdmin);

      expect(find.text(AppStrings.superAdminErreurTexte), findsOneWidget);
      expect(_boutonDeconnexion, findsOneWidget);
    });
  });

  group('Ce que la déconnexion de l\'éditeur laisse sur l\'appareil', () {
    testWidgets('rien : les clés du compte partent avec la session', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      // **Les vrais dépôts** : c'est le stockage du navigateur qu'on vérifie,
      // celui qui reste sur un téléphone prêté.
      const appartenancesLocales = AppartenancesLocalesPartagees();
      const caserneChoisie = CaserneChoisieLocalePartagee();
      await appartenancesLocales.ecrire(sessionMembre.userId, <Appartenance>[
        appartenanceMembre,
      ]);
      await caserneChoisie.ecrire(
        sessionMembre.userId,
        appartenanceMembre.stationId,
      );

      final faux = await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
        membres: FauxMembresRepository(),
        superAdmin: FauxSuperAdminRepository(),
        appartenancesLocales: appartenancesLocales,
        caserneChoisie: caserneChoisie,
      );
      await ouvrirRoute(tester, AppRoutes.superAdmin);

      final avant = await SharedPreferences.getInstance();
      await avant.reload();
      expect(
        _clesDuCompte(avant),
        hasLength(2),
        reason: 'Le décor doit vraiment avoir écrit sur l\'appareil.',
      );

      await tester.tap(_boutonDeconnexion);
      await tester.pumpAndSettle();

      expect(faux.auth.deconnexions, 1);
      expect(find.byType(ConnexionScreen), findsOneWidget);
      expect(emplacementCourant(tester), AppRoutes.connexion);

      final apres = await SharedPreferences.getInstance();
      await apres.reload();
      expect(
        _clesDuCompte(apres),
        isEmpty,
        reason:
            'Le compte le plus sensible du produit ne laisse pas de trace '
            'lisible derrière lui.',
      );
    });

    testWidgets('et un rechargement mène à la connexion, pas à /superadmin', (
      WidgetTester tester,
    ) async {
      // Un vrai démarrage à froid sur `/superadmin`, adresse **mémorisée** le
      // temps que la session revienne : c'est la seule façon d'avoir quelque
      // chose à oublier à la déconnexion. Le droit de l'éditeur et la session
      // arrivent dans la même image, comme dans le navigateur (ticket 045).
      final porte = Completer<void>();
      final depot = FauxSuperAdminRepository(porte: porte);
      final faux = await monterApp(
        tester,
        sessionEnAttente: true,
        appartenances: const <Appartenance>[appartenanceMembre],
        membres: FauxMembresRepository(),
        superAdmin: depot,
        stabiliser: false,
      );

      await ouvrirRoute(tester, AppRoutes.superAdmin, stabiliser: false);
      expect(emplacementCourant(tester), AppRoutes.demarrage);

      faux.auth.ouvrirSession(sessionMembre);
      porte.complete();
      await tester.idle();
      final conteneur = ProviderScope.containerOf(
        tester.element(find.byType(AstreinteApp)),
      );
      conteneur.read(appRouterProvider).refresh();
      await tester.pumpAndSettle();
      expect(emplacementCourant(tester), AppRoutes.superAdmin);

      await tester.tap(_boutonDeconnexion);
      await tester.pumpAndSettle();
      expect(emplacementCourant(tester), AppRoutes.connexion);

      // Le rechargement : l'adresse que la barre du navigateur gardait, rouverte
      // par la personne suivante. La porte est fermée avant même que le droit
      // soit demandé.
      await ouvrirRoute(tester, AppRoutes.superAdmin);
      expect(emplacementCourant(tester), AppRoutes.connexion);
      expect(find.byType(ConnexionScreen), findsOneWidget);
      expect(find.byType(SuperAdminScreen), findsNothing);

      // Et la session suivante ne rejoue pas la destination du lancement : même
      // si le droit d'éditeur lui était rendu, elle arrive sur l'accueil.
      faux.auth.ouvrirSession(_personneSuivante);
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), AppRoutes.accueil);
      expect(find.byType(SuperAdminScreen), findsNothing);
    });
  });
}
