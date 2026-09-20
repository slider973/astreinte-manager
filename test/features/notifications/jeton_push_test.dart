import 'package:astreinte_sp/core/firebase/firebase_bootstrap.dart';
import 'package:astreinte_sp/core/plateforme/contexte_plateforme.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/notifications/data/jeton_local.dart';
import 'package:astreinte_sp/features/notifications/data/push_tokens_repository.dart';
import 'package:astreinte_sp/features/notifications/domain/etat_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

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
        messagerie: FauxMessageriePush(
          etatPermission: PermissionPush.accordee,
        ),
      );

      expect(faux.jetons.ecritures, hasLength(1));
      final ecriture = faux.jetons.ecritures.single;
      expect(ecriture.token, 'jeton-de-test');
      expect(ecriture.userId, sessionMembre.userId);
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
        messagerie: FauxMessageriePush(
          etatPermission: PermissionPush.accordee,
        ),
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
        messagerie: FauxMessageriePush(
          etatPermission: PermissionPush.accordee,
        ),
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
        messagerie: FauxMessageriePush(
          etatPermission: PermissionPush.accordee,
        ),
        jetons: FauxPushTokensRepository(echoue: true),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
