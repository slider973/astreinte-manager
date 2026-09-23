import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/router/destinations.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/widgets/app_scaffold.dart';
import 'package:astreinte_sp/core/widgets/bouton_retour.dart';
import 'package:astreinte_sp/features/accueil/presentation/accueil_screen.dart';
import 'package:astreinte_sp/features/astreintes/presentation/astreintes_screen.dart';
import 'package:astreinte_sp/features/boite/domain/onglet_boite.dart';
import 'package:astreinte_sp/features/boite/presentation/boite_screen.dart';
import 'package:astreinte_sp/features/dispos/presentation/mois_screen.dart';
import 'package:astreinte_sp/features/planning/presentation/matrice_screen.dart';
import 'package:astreinte_sp/features/profil/presentation/profil_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';
import '../../support/faux_matrice.dart';
import '../../support/faux_profil.dart';

const Appartenance _admin = Appartenance(
  id: 'm-a',
  stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Saint-Martin',
  role: RoleMembre.admin,
  statut: StatutMembre.actif,
  nomAffiche: 'Jean C.',
);

/// Un écran haut : les cinq destinations tiennent sans défiler.
const Size _telephoneLong = Size(420, 1400);

Future<void> _monter(
  WidgetTester tester, {
  Appartenance appartenance = appartenanceMembre,
}) => monterApp(
  tester,
  session: sessionMembre,
  appartenances: <Appartenance>[appartenance],
  matrice: FauxMatriceRepository(),
  membres: FauxMembresRepository(),
  profils: FauxProfilRepository(),
  taille: _telephoneLong,
);

List<String> _libelles(WidgetTester tester) => tester
    .widget<AppScaffold>(find.byType(AppScaffold))
    .destinations
    .map((AppDestination d) => d.libelle)
    .toList(growable: false);

/// L'onglet « Propositions » de la Boîte, où mènent les anciennes adresses
/// des propositions depuis le chantier 064b.
final String _ongletPropositions = AppRoutes.boiteOnglet(
  OngletBoite.propositions,
);

void main() {
  group('La barre du pompier', () {
    testWidgets('quatre entrées pour un membre, dans l\'ordre du brief', (
      tester,
    ) async {
      await _monter(tester);

      expect(_libelles(tester), <String>[
        AppStrings.navAccueil,
        AppStrings.navCalendrier,
        AppStrings.navAstreintes,
        AppStrings.navBoite,
      ]);
      expect(find.text(AppStrings.navProfil), findsNothing);
    });

    testWidgets('cinq pour un admin : « Admin » vient en dernier', (
      tester,
    ) async {
      await _monter(tester, appartenance: _admin);

      expect(_libelles(tester), <String>[
        AppStrings.navAccueil,
        AppStrings.navCalendrier,
        AppStrings.navAstreintes,
        AppStrings.navBoite,
        AppStrings.navAdmin,
      ]);
    });

    testWidgets('chaque entrée mène à sa route, et la barre suit', (
      tester,
    ) async {
      await _monter(tester, appartenance: _admin);

      const attendu = <String, (String, Type)>{
        AppStrings.navCalendrier: (AppRoutes.calendrier, MoisScreen),
        AppStrings.navAstreintes: (AppRoutes.astreintes, AstreintesScreen),
        AppStrings.navBoite: (AppRoutes.boite, BoiteScreen),
        AppStrings.navAdmin: (AppRoutes.planningAdmin, MatriceScreen),
        AppStrings.navAccueil: (AppRoutes.accueil, AccueilScreen),
      };

      for (final entree in attendu.entries) {
        await tester.tap(find.text(entree.key).last);
        await tester.pumpAndSettle();

        expect(emplacementCourant(tester), entree.value.$1, reason: entree.key);
        expect(
          find.byType(entree.value.$2),
          findsOneWidget,
          reason: entree.key,
        );
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          _libelles(tester).indexOf(entree.key),
          reason: entree.key,
        );
      }
    });

    testWidgets('la Boîte porte le compte de non-lues', (tester) async {
      await _monter(tester);

      final boite = tester
          .widget<AppScaffold>(find.byType(AppScaffold))
          .destinations
          .firstWhere((AppDestination d) => d.route == AppRoutes.boiteName);
      expect(boite.pastilleLibelle, isNotNull);
    });
  });

  group('Le profil derrière l\'avatar', () {
    testWidgets('il se pousse, et « Retour » ramène d\'où l\'on vient', (
      tester,
    ) async {
      await _monter(tester);
      await ouvrirRoute(tester, AppRoutes.astreintes);

      await ouvrirProfil(tester);
      expect(find.byType(ProfilScreen), findsOneWidget);
      expect(emplacementCourant(tester), AppRoutes.profil);
      // Un écran poussé n'a plus de barre de navigation : c'est la flèche qui
      // en sort (`core/widgets/README.md`).
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BoutonRetour), findsOneWidget);

      await tester.tap(find.byTooltip(AppStrings.actionRetour));
      await tester.pumpAndSettle();

      expect(find.byType(AstreintesScreen), findsOneWidget);
      expect(emplacementCourant(tester), AppRoutes.astreintes);
    });

    testWidgets('l\'avatar est présent sur les quatre destinations', (
      tester,
    ) async {
      await _monter(tester);

      for (final route in <String>[
        AppRoutes.accueil,
        AppRoutes.calendrier,
        AppRoutes.astreintes,
        AppRoutes.boite,
      ]) {
        await ouvrirRoute(tester, route);
        await ouvrirProfil(tester);
        expect(find.byType(ProfilScreen), findsOneWidget, reason: route);
        await tester.tap(find.byTooltip(AppStrings.actionRetour));
        await tester.pumpAndSettle();
      }
    });
  });

  group('Les anciennes adresses ne tombent nulle part', () {
    testWidgets('les onglets de la coquille d\'avant le ticket 064', (
      tester,
    ) async {
      // Elles sont parties dans des notifications et dorment dans des
      // historiques de navigateur : aucune ne doit rendre un 404.
      final heritage = <String, (String, Type)>{
        '/?onglet=0': (AppRoutes.calendrier, MoisScreen),
        '/?onglet=1': (_ongletPropositions, BoiteScreen),
        '/?onglet=2': (AppRoutes.astreintes, AstreintesScreen),
        '/?onglet=3': (AppRoutes.profil, ProfilScreen),
        '/notifications': (AppRoutes.boite, BoiteScreen),
        '/propositions': (_ongletPropositions, BoiteScreen),
      };

      for (final lien in heritage.entries) {
        await _monter(tester);
        await ouvrirRoute(tester, lien.key);

        expect(emplacementCourant(tester), lien.value.$1, reason: lien.key);
        expect(find.byType(lien.value.$2), findsOneWidget, reason: lien.key);
        await demonter(tester);
      }
    });

    testWidgets('un mois demandé à l\'ancienne ouvre le Calendrier dessus', (
      tester,
    ) async {
      await _monter(tester);
      await ouvrirRoute(tester, '/?onglet=0&mois=2026-10');

      expect(
        emplacementCourant(tester),
        '${AppRoutes.calendrier}?mois=2026-10',
      );
    });

    testWidgets('un `?mois=` sans onglet visait « Mon mois » lui aussi', (
      tester,
    ) async {
      await _monter(tester);
      await ouvrirRoute(tester, '/?mois=2026-10');

      expect(
        emplacementCourant(tester),
        '${AppRoutes.calendrier}?mois=2026-10',
      );
    });

    testWidgets('un onglet inconnu ramène à l\'accueil, sans reproche', (
      tester,
    ) async {
      await _monter(tester);
      await ouvrirRoute(tester, '/?onglet=9');

      expect(emplacementCourant(tester), AppRoutes.accueil);
      expect(find.textContaining('rreur'), findsNothing);
    });

    testWidgets('l\'accueil nu n\'est jamais redirigé', (tester) async {
      await _monter(tester);
      await ouvrirRoute(tester, AppRoutes.accueil);

      expect(emplacementCourant(tester), AppRoutes.accueil);
      expect(find.byType(AccueilScreen), findsOneWidget);
    });
  });

  group('La traduction des onglets hérités', () {
    test(
      'elle est pure, et ne touche que ce qui vient de l\'ancienne forme',
      () {
        expect(ongletHerite(Uri.parse('/')), isNull);
        expect(ongletHerite(Uri.parse('/?onglet=1')), _ongletPropositions);
        expect(ongletHerite(Uri.parse('/?onglet=2')), AppRoutes.astreintes);
        expect(ongletHerite(Uri.parse('/?onglet=3')), AppRoutes.profil);
        expect(
          ongletHerite(Uri.parse('/?onglet=0&mois=2026-10')),
          '${AppRoutes.calendrier}?mois=2026-10',
        );
        expect(ongletHerite(Uri.parse('/?onglet=42')), AppRoutes.accueil);
      },
    );
  });
}
