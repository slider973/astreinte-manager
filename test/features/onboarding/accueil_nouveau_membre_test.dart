import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/plateforme/contexte_plateforme.dart';
import 'package:astreinte_sp/core/preferences/reperes_locaux.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/accueil/presentation/accueil_screen.dart';
import 'package:astreinte_sp/features/onboarding/presentation/guide_screen.dart';
import 'package:astreinte_sp/features/onboarding/presentation/installation_screen.dart';
import 'package:astreinte_sp/features/onboarding/presentation/profil_accueil_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_invitations.dart';

const String _safariIphone =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const String _chromeAndroid =
    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like '
    'Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

Future<void> _ouvrir(
  WidgetTester tester,
  String chemin, {
  FauxProfilRepository? profils,
  ReperesLocaux? reperes,
  ContextePlateforme? plateforme,
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    profils: profils,
    reperes: reperes,
    plateforme: plateforme,
  );
  await ouvrirRoute(tester, chemin);
}

Future<void> _remplirLeProfil(WidgetTester tester) async {
  final champs = find.byType(TextField);
  await tester.enterText(champs.at(0), 'Camille');
  await tester.enterText(champs.at(1), 'Girard');
  await tester.tap(find.text(AppStrings.profilEnregistrer));
  await tester.pumpAndSettle();
}

void main() {
  group('Complément de profil', () {
    testWidgets('refuse un prénom ou un nom vide, et le dit', (tester) async {
      final profils = FauxProfilRepository();
      await _ouvrir(tester, '/bienvenue/profil', profils: profils);

      await tester.tap(find.text(AppStrings.profilEnregistrer));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.profilPrenomManquant), findsOneWidget);
      expect(find.text(AppStrings.profilNomManquant), findsOneWidget);
      expect(profils.ecritures, isEmpty);
    });

    testWidgets('le téléphone est facultatif', (tester) async {
      final profils = FauxProfilRepository();
      await _ouvrir(tester, '/bienvenue/profil', profils: profils);

      await _remplirLeProfil(tester);

      expect(profils.ecritures.single.prenom, 'Camille');
      expect(profils.ecritures.single.nom, 'Girard');
      expect(profils.ecritures.single.telephone, '');
    });

    testWidgets('une écriture en échec propose de réessayer', (tester) async {
      final profils = FauxProfilRepository(echoue: true);
      await _ouvrir(tester, '/bienvenue/profil', profils: profils);

      await _remplirLeProfil(tester);

      expect(find.text(AppStrings.profilEchec), findsOneWidget);
      expect(find.byType(ProfilAccueilScreen), findsOneWidget);
    });

    testWidgets('le profil enregistré ouvre le guide', (tester) async {
      await _ouvrir(
        tester,
        '/bienvenue/profil',
        profils: FauxProfilRepository(),
      );

      await _remplirLeProfil(tester);

      expect(find.byType(GuideScreen), findsOneWidget);
      expect(find.text(AppStrings.guideEtape(1, 3)), findsOneWidget);
    });

    testWidgets('un guide déjà vu ne se rouvre pas', (tester) async {
      await _ouvrir(
        tester,
        '/bienvenue/profil',
        profils: FauxProfilRepository(),
        reperes: ReperesLocauxMemoire(<RepereAccueil>{RepereAccueil.guide}),
      );

      await _remplirLeProfil(tester);

      expect(find.byType(GuideScreen), findsNothing);
      expect(find.byType(AccueilScreen), findsOneWidget);
    });
  });

  group('Guide d\'accueil', () {
    testWidgets('trois étapes, et la dernière mène à l\'accueil', (
      tester,
    ) async {
      await _ouvrir(tester, '/bienvenue/guide');

      expect(find.text(AppStrings.guideDisposTitre), findsOneWidget);
      await tester.tap(find.text(AppStrings.guideSuivant));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.guideEtape(2, 3)), findsOneWidget);

      await tester.tap(find.text(AppStrings.guideSuivant));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.guideEtape(3, 3)), findsOneWidget);
      expect(find.text(AppStrings.guideSuivant), findsNothing);

      await tester.tap(find.text(AppStrings.guideTerminer));
      await tester.pumpAndSettle();
      expect(find.byType(AccueilScreen), findsOneWidget);
    });

    testWidgets('le guide se passe, et ne revient pas', (tester) async {
      final reperes = ReperesLocauxMemoire();
      await _ouvrir(tester, '/bienvenue/guide', reperes: reperes);

      await tester.tap(find.text(AppStrings.guidePasser));
      await tester.pumpAndSettle();

      expect(find.byType(AccueilScreen), findsOneWidget);
      expect(await reperes.dejaVu(RepereAccueil.guide), isTrue);
    });

    testWidgets('sur iPhone, le guide mène à l\'aide à l\'installation', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        '/bienvenue/guide',
        plateforme: ContextePlateforme.depuisAgent(userAgent: _safariIphone),
      );

      await tester.tap(find.text(AppStrings.guidePasser));
      await tester.pumpAndSettle();

      expect(find.byType(InstallationScreen), findsOneWidget);
    });

    testWidgets('en mode autonome, l\'aide à l\'installation est sautée', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        '/bienvenue/guide',
        plateforme: ContextePlateforme.depuisAgent(
          userAgent: _safariIphone,
          affichageAutonome: true,
        ),
      );

      await tester.tap(find.text(AppStrings.guidePasser));
      await tester.pumpAndSettle();

      expect(find.byType(InstallationScreen), findsNothing);
      expect(find.byType(AccueilScreen), findsOneWidget);
    });
  });

  group('Ajouter à l\'écran d\'accueil', () {
    testWidgets('sur iPhone, les gestes de Safari et l\'enjeu réel', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        '/bienvenue/installation',
        plateforme: ContextePlateforme.depuisAgent(userAgent: _safariIphone),
      );

      expect(find.text(AppStrings.installAvertissementIos), findsOneWidget);
      expect(find.text(AppStrings.installIosEtape1), findsOneWidget);
      expect(find.text(AppStrings.installIosEtape3), findsOneWidget);
      expect(find.text(AppStrings.installAndroidEtape1), findsNothing);
    });

    testWidgets('sur Android, les gestes de Chrome, sans l\'avertissement', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        '/bienvenue/installation',
        plateforme: ContextePlateforme.depuisAgent(userAgent: _chromeAndroid),
      );

      expect(find.text(AppStrings.installAndroidEtape2), findsOneWidget);
      expect(find.text(AppStrings.installAvertissementIos), findsNothing);
      expect(find.text(AppStrings.installIosEtape1), findsNothing);
    });

    testWidgets('« Plus tard » pose le repère : l\'écran ne revient pas', (
      tester,
    ) async {
      final reperes = ReperesLocauxMemoire(<RepereAccueil>{
        RepereAccueil.guide,
      });
      await _ouvrir(
        tester,
        '/bienvenue/installation',
        reperes: reperes,
        plateforme: ContextePlateforme.depuisAgent(userAgent: _chromeAndroid),
      );

      await tester.tap(find.text(AppStrings.installPlusTard));
      await tester.pumpAndSettle();

      expect(find.byType(AccueilScreen), findsOneWidget);
      expect(await reperes.dejaVu(RepereAccueil.aideInstallation), isTrue);
    });
  });
}
