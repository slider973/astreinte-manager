import 'package:astreinte_sp/core/firebase/firebase_bootstrap.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/plateforme/contexte_plateforme.dart';
import 'package:astreinte_sp/core/preferences/reperes_locaux.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/notifications/domain/etat_notifications.dart';
import 'package:astreinte_sp/features/onboarding/domain/parcours_accueil.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_push.dart';

const String _safariIphone =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
const String _chromeAndroid =
    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like '
    'Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

final ContextePlateforme _androidInstalle = ContextePlateforme.depuisAgent(
  userAgent: _chromeAndroid,
  affichageAutonome: true,
);
final ContextePlateforme _iphoneSafari = ContextePlateforme.depuisAgent(
  userAgent: _safariIphone,
);

ParcoursAccueil _parcours({
  required EtatNotifications etat,
  ContextePlateforme? plateforme,
  Set<RepereAccueil>? vus,
}) => ParcoursAccueil(
  ReperesLocauxMemoire(vus ?? <RepereAccueil>{RepereAccueil.guide}),
  plateforme ?? _androidInstalle,
  () async => etat,
);

Future<void> _ouvrirEcran(
  WidgetTester tester, {
  required ContextePlateforme plateforme,
  required FauxMessageriePush messagerie,
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    firebase: FirebaseDemarrage.pret,
    plateforme: plateforme,
    messagerie: messagerie,
  );
  await ouvrirRoute(tester, AppRoutes.activationNotifications);
}

void main() {
  group('Parcours d\'accueil : la place de la demande', () {
    test('sans configuration Firebase, l\'étape est sautée', () async {
      final suite = await _parcours(
        etat: EtatNotifications.nonConfigure,
      ).apresLeGuide();

      expect(suite, AppRoutes.accueilName);
    });

    test('un navigateur incapable ne voit pas non plus l\'étape', () async {
      final suite = await _parcours(
        etat: EtatNotifications.nonSupporte,
      ).apresLeGuide();

      expect(suite, AppRoutes.accueilName);
    });

    test('la demande arrive après l\'aide à l\'installation, pas avant', () async {
      final parcours = _parcours(
        etat: EtatNotifications.aDemander,
        plateforme: _iphoneSafari,
      );

      // Le guide passé, l'installation vient d'abord : sur iPhone, elle
      // conditionne tout le reste.
      expect(await parcours.apresLeGuide(), AppRoutes.installationName);
      expect(
        await parcours.apresLInstallation(),
        AppRoutes.activationNotificationsName,
      );
    });

    test('vue une fois, elle ne revient pas d\'elle-même', () async {
      final suite = await _parcours(
        etat: EtatNotifications.aDemander,
        vus: <RepereAccueil>{
          RepereAccueil.guide,
          RepereAccueil.activationNotifications,
        },
      ).apresLeGuide();

      expect(suite, AppRoutes.accueilName);
    });

    test('après l\'étape, on rejoint l\'accueil', () async {
      expect(
        await _parcours(
          etat: EtatNotifications.aDemander,
        ).apresLesNotifications(),
        AppRoutes.accueilName,
      );
    });
  });

  group('Écran « Reçois les propositions »', () {
    testWidgets('annonce la fenêtre du navigateur avant de l\'ouvrir', (
      tester,
    ) async {
      await _ouvrirEcran(
        tester,
        plateforme: _androidInstalle,
        messagerie: FauxMessageriePush(),
      );

      expect(find.text(AppStrings.notifAccueilTitre), findsOneWidget);
      expect(find.text(AppStrings.notifAccueilAvantDemande), findsOneWidget);
      expect(find.text(AppStrings.notifAccueilItemProposition), findsOneWidget);
      expect(find.text(AppStrings.notifActiver), findsOneWidget);
      expect(find.text(AppStrings.notifPlusTard), findsOneWidget);
    });

    testWidgets('« Activer » demande l\'autorisation, puis rejoint l\'accueil', (
      tester,
    ) async {
      final messagerie = FauxMessageriePush();
      await _ouvrirEcran(
        tester,
        plateforme: _androidInstalle,
        messagerie: messagerie,
      );

      await tester.tap(find.text(AppStrings.notifActiver));
      await tester.pumpAndSettle();

      expect(messagerie.demandes, 1);
      expect(emplacementCourant(tester), AppRoutes.accueil);
    });

    testWidgets('« Plus tard » n\'ouvre aucune fenêtre', (tester) async {
      final messagerie = FauxMessageriePush();
      await _ouvrirEcran(
        tester,
        plateforme: _androidInstalle,
        messagerie: messagerie,
      );

      await tester.tap(find.text(AppStrings.notifPlusTard));
      await tester.pumpAndSettle();

      expect(messagerie.demandes, 0);
      expect(emplacementCourant(tester), AppRoutes.accueil);
    });

    testWidgets('un refus ne bloque pas l\'accueil et ne s\'affiche pas en '
        'erreur', (tester) async {
      final messagerie = FauxMessageriePush(
        reponseDemande: PermissionPush.refusee,
      );
      await _ouvrirEcran(
        tester,
        plateforme: _androidInstalle,
        messagerie: messagerie,
      );

      await tester.tap(find.text(AppStrings.notifActiver));
      await tester.pumpAndSettle();

      expect(messagerie.demandes, 1);
      expect(emplacementCourant(tester), AppRoutes.accueil);
    });

    testWidgets(
      'sur iPhone hors écran d\'accueil, aucun bouton ne demande '
      'l\'autorisation',
      (tester) async {
        final messagerie = FauxMessageriePush(supportee: false);
        await _ouvrirEcran(
          tester,
          plateforme: _iphoneSafari,
          messagerie: messagerie,
        );

        expect(find.text(AppStrings.notifIosBanniere), findsOneWidget);
        expect(find.text(AppStrings.notifIosAction), findsOneWidget);
        expect(find.text(AppStrings.notifActiver), findsNothing);

        await tester.tap(find.text(AppStrings.notifIosAction));
        await tester.pumpAndSettle();

        expect(messagerie.demandes, 0);
        expect(find.text(AppStrings.installTitre), findsOneWidget);
      },
    );
  });
}
