import 'package:astreinte_sp/core/firebase/firebase_bootstrap.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/plateforme/contexte_plateforme.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/features/boite/domain/onglet_boite.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/notifications/domain/etat_notifications.dart';
import 'package:astreinte_sp/features/notifications/domain/message_push.dart';
import 'package:astreinte_sp/features/notifications/presentation/couche_notifications.dart';
import 'package:flutter/material.dart';
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

Future<AppMontee> _lancer(WidgetTester tester) => monterApp(
  tester,
  session: sessionMembre,
  appartenances: const <Appartenance>[appartenanceMembre],
  firebase: FirebaseDemarrage.pret,
  plateforme: _androidInstalle,
  messagerie: FauxMessageriePush(etatPermission: PermissionPush.accordee),
);

Future<void> _recevoir(
  WidgetTester tester,
  AppMontee faux,
  MessagePush message,
) async {
  faux.push.messages.add(message);
  await tester.pump();
  await tester.pump();
}

void main() {
  group('Bannière d\'un message reçu au premier plan', () {
    testWidgets('le titre et le corps s\'affichent, avec « Voir »', (
      tester,
    ) async {
      final faux = await _lancer(tester);

      await _recevoir(
        tester,
        faux,
        const MessagePush(
          titre: 'Astreinte proposée',
          corps: 'Samedi 4 octobre, nuit',
          route: '/proposals',
        ),
      );

      expect(find.text('Astreinte proposée'), findsOneWidget);
      expect(find.text('Samedi 4 octobre, nuit'), findsOneWidget);
      expect(find.text(AppStrings.notifBanniereVoir), findsOneWidget);

      await tester.pump(CoucheNotifications.duree);
    });

    testWidgets('« Voir » ouvre la destination du lien', (tester) async {
      final faux = await _lancer(tester);

      await _recevoir(
        tester,
        faux,
        const MessagePush(titre: 'Astreinte proposée', route: '/proposals'),
      );
      await tester.tap(find.text(AppStrings.notifBanniereVoir));
      await tester.pumpAndSettle();

      expect(
        emplacementCourant(tester),
        AppRoutes.boiteOnglet(OngletBoite.propositions),
      );
      expect(find.text('Astreinte proposée'), findsNothing);
    });

    testWidgets('elle se ferme à la main : c\'est un événement, pas un état', (
      tester,
    ) async {
      final semantique = tester.ensureSemantics();
      final faux = await _lancer(tester);

      await _recevoir(
        tester,
        faux,
        const MessagePush(titre: 'Planning validé'),
      );

      // Le bouton porte un nom : une croix muette n'est pas une sortie.
      final fermer = find.bySemanticsLabel(AppStrings.notifBanniereFermer);
      expect(fermer, findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Planning validé'), findsNothing);
      semantique.dispose();
    });

    testWidgets('elle s\'efface d\'elle-même : rien ne se perd', (tester) async {
      final faux = await _lancer(tester);

      await _recevoir(
        tester,
        faux,
        const MessagePush(titre: 'Planning validé'),
      );
      expect(find.text('Planning validé'), findsOneWidget);

      await tester.pump(CoucheNotifications.duree);
      await tester.pumpAndSettle();

      expect(find.text('Planning validé'), findsNothing);
    });

    testWidgets('un message vide ne devient pas une bannière vide', (
      tester,
    ) async {
      final faux = await _lancer(tester);

      await _recevoir(tester, faux, const MessagePush(route: '/proposals'));

      expect(find.text(AppStrings.notifBanniereVoir), findsNothing);
      expect(find.text(AppStrings.notifBanniereSansTitre), findsNothing);
    });

    testWidgets('un lien inconnu ramène à l\'accueil, sans reproche', (
      tester,
    ) async {
      final faux = await _lancer(tester);

      await _recevoir(
        tester,
        faux,
        const MessagePush(titre: 'Message', route: '/inconnu'),
      );
      await tester.tap(find.text(AppStrings.notifBanniereVoir));
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), '/');
    });
  });
}
