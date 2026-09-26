import 'dart:async';

import 'package:astreinte_sp/core/firebase/firebase_bootstrap.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/plateforme/contexte_plateforme.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/auth/presentation/connexion_screen.dart';
import 'package:astreinte_sp/features/notifications/data/jeton_local.dart';
import 'package:astreinte_sp/features/notifications/data/push_tokens_repository.dart';
import 'package:astreinte_sp/features/notifications/domain/etat_notifications.dart';
import 'package:astreinte_sp/features/notifications/domain/notifications_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_push.dart';

const String _chromeAndroid =
    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like '
    'Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

final ContextePlateforme _androidInstalle = ContextePlateforme.depuisAgent(
  userAgent: _chromeAndroid,
  affichageAutonome: true,
);

Future<AppMontee> _lancer(
  WidgetTester tester, {
  required FauxMessageriePush messagerie,
  FirebaseDemarrage firebase = FirebaseDemarrage.pret,
  JetonLocal? jetonLocal,
  FauxPushTokensRepository? jetons,
}) => monterApp(
  tester,
  session: sessionMembre,
  appartenances: const <Appartenance>[appartenanceMembre],
  firebase: firebase,
  plateforme: _androidInstalle,
  messagerie: messagerie,
  jetonLocal: jetonLocal,
  jetons: jetons,
);

void main() {
  group('Enregistrement du jeton', () {
    testWidgets('au lancement, une autorisation accordée publie le jeton', (
      tester,
    ) async {
      final faux = await _lancer(
        tester,
        messagerie: FauxMessageriePush(etatPermission: PermissionPush.accordee),
      );

      expect(faux.jetons.ecritures, hasLength(1));
      final ecriture = faux.jetons.ecritures.single;
      expect(ecriture.token, 'jeton-de-test');
      expect(ecriture.plateforme, PlateformePush.web);
      expect(ecriture.libelleAppareil, 'Pixel 7 · Chrome');
    });

    testWidgets('un jeton périmé est remplacé, pas dupliqué', (tester) async {
      final faux = await _lancer(
        tester,
        messagerie: FauxMessageriePush(
          etatPermission: PermissionPush.accordee,
          jetonRendu: 'jeton-neuf',
        ),
        jetonLocal: JetonLocalMemoire('jeton-perime'),
      );

      expect(faux.jetons.ecritures.map((e) => e.token), <String>['jeton-neuf']);
      expect(faux.jetons.oublies, <String>['jeton-perime']);
    });

    testWidgets('le même jeton ne supprime rien : il est seulement rafraîchi', (
      tester,
    ) async {
      final faux = await _lancer(
        tester,
        messagerie: FauxMessageriePush(etatPermission: PermissionPush.accordee),
        jetonLocal: JetonLocalMemoire('jeton-de-test'),
      );

      expect(faux.jetons.ecritures, hasLength(1));
      expect(faux.jetons.oublies, isEmpty);
    });

    testWidgets('une autorisation refusée n\'écrit rien', (tester) async {
      final faux = await _lancer(
        tester,
        messagerie: FauxMessageriePush(etatPermission: PermissionPush.refusee),
      );

      expect(faux.jetons.ecritures, isEmpty);
      expect(faux.push.jetonsDemandes, 0);
    });

    testWidgets('sans configuration Firebase, rien n\'est demandé ni écrit', (
      tester,
    ) async {
      final faux = await _lancer(
        tester,
        firebase: FirebaseDemarrage.configurationAbsente,
        messagerie: FauxMessageriePush(etatPermission: PermissionPush.accordee),
      );

      expect(faux.jetons.ecritures, isEmpty);
      expect(faux.push.jetonsDemandes, 0);
    });

    testWidgets('un navigateur qui refuse le jeton ne fait pas tomber l\'app', (
      tester,
    ) async {
      final faux = await _lancer(
        tester,
        messagerie: FauxMessageriePush(
          etatPermission: PermissionPush.accordee,
          jetonRendu: null,
        ),
      );

      expect(faux.jetons.ecritures, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('une écriture refusée par la base reste silencieuse', (
      tester,
    ) async {
      await _lancer(
        tester,
        messagerie: FauxMessageriePush(etatPermission: PermissionPush.accordee),
        jetons: FauxPushTokensRepository(echoue: true),
      );

      expect(tester.takeException(), isNull);
    });
  });

  // Ticket 057 : un téléphone de caserne est prêté. À la déconnexion, la ligne
  // de `push_tokens` part côté serveur, **puis** la clé locale, et les deux
  // avant la fermeture de session. Le stockage est le vrai
  // (`JetonLocalPartage`) : c'est lui qui reste sur le téléphone.
  group('Déconnexion', () {
    Future<void> seDeconnecter(WidgetTester tester) async {
      await ouvrirProfil(tester);
      await defilerJusqua(tester, find.text(AppStrings.seDeconnecter));
      await tester.tap(find.text(AppStrings.seDeconnecter));
    }

    Future<String?> cleLocale() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getString(JetonLocalPartage.cle);
    }

    testWidgets('la ligne part côté serveur, puis la clé locale, avant la '
        'fermeture de session', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final jetons = FauxPushTokensRepository();
      final faux = await _lancer(
        tester,
        messagerie: FauxMessageriePush(etatPermission: PermissionPush.accordee),
        jetonLocal: const JetonLocalPartage(),
        jetons: jetons,
      );
      expect(
        await cleLocale(),
        'jeton-de-test',
        reason: 'le lancement a bien écrit la clé sur l\'appareil',
      );

      String? cleAuMomentDeLOubli;
      int? deconnexionsAuMomentDeLOubli;
      jetons.auMomentDeLOubli = (_) async {
        cleAuMomentDeLOubli = await cleLocale();
        deconnexionsAuMomentDeLOubli = faux.auth.deconnexions;
      };
      List<String>? oubliesAuMomentFcm;
      String? cleAuMomentFcm;
      faux.push.auMomentDeLOubliFcm = () async {
        oubliesAuMomentFcm = List<String>.of(jetons.oublies);
        cleAuMomentFcm = await cleLocale();
      };

      await seDeconnecter(tester);
      await tester.pumpAndSettle();

      expect(jetons.oublies, <String>['jeton-de-test']);
      expect(
        cleAuMomentDeLOubli,
        'jeton-de-test',
        reason: 'la ligne part d\'abord : la clé dit encore quel jeton viser',
      );
      expect(
        deconnexionsAuMomentDeLOubli,
        0,
        reason: 'avant la fermeture de session : après, la RLS refuse',
      );
      expect(faux.push.jetonsOublies, 1, reason: 'FCM oublie le jeton');
      expect(
        oubliesAuMomentFcm,
        <String>['jeton-de-test'],
        reason: 'après la tentative de suppression côté serveur',
      );
      expect(
        cleAuMomentFcm,
        'jeton-de-test',
        reason: 'et avant l\'effacement de la clé',
      );
      expect(await cleLocale(), isNull, reason: 'puis la clé part');
      expect(faux.auth.deconnexions, 1);
      expect(find.byType(ConnexionScreen), findsOneWidget);
    });

    testWidgets('une suppression refusée par le réseau oublie quand même la '
        'clé locale', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final jetons = FauxPushTokensRepository();
      final faux = await _lancer(
        tester,
        messagerie: FauxMessageriePush(etatPermission: PermissionPush.accordee),
        jetonLocal: const JetonLocalPartage(),
        jetons: jetons,
      );
      expect(await cleLocale(), 'jeton-de-test');

      // Hors ligne : la ligne reste au nom du compte sorti. C'est
      // `register_push_token` qui la fera passer au compte suivant.
      jetons.echoue = true;
      await seDeconnecter(tester);
      await tester.pumpAndSettle();

      expect(jetons.oublies, isEmpty);
      expect(
        faux.push.jetonsOublies,
        1,
        reason: 'le navigateur se désabonne quand même : il marche hors ligne',
      );
      expect(await cleLocale(), isNull);
      expect(faux.auth.deconnexions, 1, reason: 'personne n\'est retenu');
      expect(find.byType(ConnexionScreen), findsOneWidget);
    });

    testWidgets('un désabonnement FCM qui échoue ne retient rien', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final jetons = FauxPushTokensRepository();
      final faux = await _lancer(
        tester,
        messagerie: FauxMessageriePush(
          etatPermission: PermissionPush.accordee,
        ),
        jetonLocal: const JetonLocalPartage(),
        jetons: jetons,
      );
      faux.push.oubliEchoue = true;

      await seDeconnecter(tester);
      await tester.pumpAndSettle();

      expect(faux.push.jetonsOublies, 1);
      expect(jetons.oublies, <String>['jeton-de-test']);
      expect(await cleLocale(), isNull);
      expect(faux.auth.deconnexions, 1);
      expect(find.byType(ConnexionScreen), findsOneWidget);
    });

    testWidgets('un jeton rendu par FCM après la déconnexion n\'écrit ni '
        'ligne ni clé', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final jetons = FauxPushTokensRepository();
      final messagerie = FauxMessageriePush(
        etatPermission: PermissionPush.accordee,
      )..jetonEnAttente = Completer<String?>();
      final faux = await _lancer(
        tester,
        messagerie: messagerie,
        jetonLocal: const JetonLocalPartage(),
        jetons: jetons,
      );
      // `publier` est parti au lancement, sans attente, et attend FCM.
      expect(messagerie.jetonsDemandes, 1);

      await seDeconnecter(tester);
      await tester.pumpAndSettle();
      expect(faux.auth.deconnexions, 1);

      // FCM répond enfin, sur un appareil déjà rendu.
      messagerie.jetonEnAttente!.complete('jeton-tardif');
      await tester.pumpAndSettle();

      expect(jetons.ecritures, isEmpty, reason: 'aucune ligne');
      expect(await cleLocale(), isNull, reason: 'aucune clé');
    });

    testWidgets('un enregistrement en vol est attendu, puis son jeton '
        'supprimé', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final jetons = FauxPushTokensRepository()
        ..enregistrementEnAttente = Completer<void>();
      final faux = await _lancer(
        tester,
        messagerie: FauxMessageriePush(
          etatPermission: PermissionPush.accordee,
        ),
        jetonLocal: const JetonLocalPartage(),
        jetons: jetons,
      );

      await seDeconnecter(tester);
      await tester.pump();
      expect(
        jetons.oublies,
        isEmpty,
        reason: 'la suppression attend l\'enregistrement parti avant elle',
      );

      // La base répond : la ligne existe, et c'est elle que la déconnexion
      // supprime ensuite.
      jetons.enregistrementEnAttente!.complete();
      await tester.pumpAndSettle();

      expect(jetons.ecritures.map((e) => e.token), <String>['jeton-de-test']);
      expect(jetons.oublies, <String>['jeton-de-test']);
      expect(await cleLocale(), isNull, reason: 'publier n\'a pas écrit la clé');
      expect(faux.auth.deconnexions, 1);
    });

    testWidgets('un réseau qui se tait ne retient pas la déconnexion', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final jetons = FauxPushTokensRepository();
      final faux = await _lancer(
        tester,
        messagerie: FauxMessageriePush(etatPermission: PermissionPush.accordee),
        jetonLocal: const JetonLocalPartage(),
        jetons: jetons,
      );

      jetons.suppressionSuspendue = true;
      await seDeconnecter(tester);
      await tester.pump();
      expect(faux.auth.deconnexions, 0, reason: 'la suppression attend');

      await tester.pump(JetonPushController.delaiDesenregistrement);
      await tester.pumpAndSettle();

      expect(await cleLocale(), isNull);
      expect(faux.auth.deconnexions, 1);
      expect(find.byType(ConnexionScreen), findsOneWidget);
    });

    testWidgets('sans jeton publié, rien ne part vers la base', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final jetons = FauxPushTokensRepository();
      final faux = await _lancer(
        tester,
        messagerie: FauxMessageriePush(etatPermission: PermissionPush.refusee),
        jetonLocal: const JetonLocalPartage(),
        jetons: jetons,
      );

      await seDeconnecter(tester);
      await tester.pumpAndSettle();

      expect(jetons.oublies, isEmpty);
      expect(faux.auth.deconnexions, 1);
    });
  });
}
