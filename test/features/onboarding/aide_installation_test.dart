import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/plateforme/contexte_plateforme.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/supabase/supabase_bootstrap.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/features/accueil/presentation/accueil_screen.dart';
import 'package:astreinte_sp/features/auth/presentation/connexion_screen.dart';
import 'package:astreinte_sp/features/demarrage/presentation/configuration_absente_screen.dart';
import 'package:astreinte_sp/features/onboarding/presentation/aide_installation_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';

const String _safariIphone =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const String _chromeAndroid =
    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like '
    'Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
const String _firefoxBureau =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:127.0) Gecko/20100101 '
    'Firefox/127.0';

ContextePlateforme _navigateur(String agent, {bool autonome = false}) =>
    ContextePlateforme.depuisAgent(
      userAgent: agent,
      affichageAutonome: autonome,
    );

void main() {
  group('/install — l\'aide à l\'installation, sans compte', () {
    testWidgets('s\'ouvre sans session : elle ne renvoie pas sur la connexion', (
      tester,
    ) async {
      await monterApp(tester, plateforme: _navigateur(_chromeAndroid));
      await ouvrirRoute(tester, '/install');

      expect(find.byType(AideInstallationScreen), findsOneWidget);
      expect(find.byType(ConnexionScreen), findsNothing);
      expect(emplacementCourant(tester), '/install');
    });

    // Le premier moment où la page sert : le jour de la mise en ligne, la
    // base n'est pas encore branchée (ticket 032).
    testWidgets('s\'ouvre même sans configuration Supabase', (tester) async {
      await monterApp(
        tester,
        demarrage: SupabaseDemarrage.configurationAbsente,
        plateforme: _navigateur(_chromeAndroid),
      );
      await ouvrirRoute(tester, '/install');

      expect(find.byType(AideInstallationScreen), findsOneWidget);
      expect(find.byType(ConfigurationAbsenteScreen), findsNothing);
    });

    testWidgets('sans configuration Supabase, le reste reste fermé', (
      tester,
    ) async {
      await monterApp(
        tester,
        demarrage: SupabaseDemarrage.configurationAbsente,
      );
      await ouvrirRoute(tester, '/bienvenue/guide');

      expect(find.byType(ConfigurationAbsenteScreen), findsOneWidget);
    });

    testWidgets('sur iPhone : la bannière, puis les trois gestes de Safari', (
      tester,
    ) async {
      await monterApp(tester, plateforme: _navigateur(_safariIphone));
      await ouvrirRoute(tester, '/install');

      expect(find.byType(AppBanner), findsOneWidget);
      expect(find.text(AppStrings.installAvertissementIos), findsOneWidget);
      expect(find.text(AppStrings.installIosEtape1), findsOneWidget);
      expect(find.text(AppStrings.installIosEtape3), findsOneWidget);
      expect(find.text(AppStrings.installAndroidEtape1), findsNothing);
    });

    testWidgets('sur Android : les trois gestes de Chrome, sans bannière', (
      tester,
    ) async {
      await monterApp(tester, plateforme: _navigateur(_chromeAndroid));
      await ouvrirRoute(tester, '/install');

      expect(find.byType(AppBanner), findsNothing);
      expect(find.text(AppStrings.installAndroidEtape1), findsOneWidget);
      expect(find.text(AppStrings.installAndroidEtape3), findsOneWidget);
      expect(find.text(AppStrings.installIosEtape1), findsNothing);
    });

    // Une page qu'on ouvre exprès n'a pas le droit de se taire, et n'a pas le
    // droit d'inventer trois gestes qu'elle ne connaît pas.
    testWidgets('sur un navigateur inconnu : où chercher, puis l\'aveu', (
      tester,
    ) async {
      await monterApp(tester, plateforme: _navigateur(_firefoxBureau));
      await ouvrirRoute(tester, '/install');

      expect(find.text(AppStrings.installAutreOu), findsOneWidget);
      expect(find.text(AppStrings.installAutreAveu), findsOneWidget);
      expect(find.text(AppStrings.installEtapesTitre), findsNothing);
      expect(find.text(AppStrings.installAndroidEtape1), findsNothing);
      expect(find.text(AppStrings.installIosEtape1), findsNothing);
    });

    testWidgets('déjà installée : elle le dit au lieu d\'expliquer', (
      tester,
    ) async {
      await monterApp(
        tester,
        plateforme: _navigateur(_safariIphone, autonome: true),
      );
      await ouvrirRoute(tester, '/install');

      expect(find.text(AppStrings.installDejaFaitTitre), findsOneWidget);
      expect(find.text(AppStrings.installEtapesTitre), findsNothing);
      expect(find.byType(AppBanner), findsNothing);
    });

    testWidgets('la seule action ouvre l\'application', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
        plateforme: _navigateur(_chromeAndroid),
      );
      await ouvrirRoute(tester, '/install');

      await tester.tap(find.text(AppStrings.installOuvrir));
      await tester.pumpAndSettle();

      expect(find.byType(AccueilScreen), findsOneWidget);
    });
  });
}
