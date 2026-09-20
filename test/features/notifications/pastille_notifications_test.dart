import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/notifications/domain/message_push.dart';
import 'package:astreinte_sp/features/notifications/domain/notification_interne.dart';
import 'package:astreinte_sp/features/notifications/presentation/widgets/bouton_notifications.dart';
import 'package:astreinte_sp/features/notifications/presentation/widgets/ligne_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_notifications.dart';
import '../../support/faux_push.dart';

const Size _telephoneLong = Size(420, 1400);

void main() {
  group('Pastille de la cloche', () {
    testWidgets('porte le nombre de non-lues sur la coquille d\'accueil', (
      tester,
    ) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
        notifications: FauxNotificationsRepository(
          notifications: <NotificationInterne>[
            notification(id: 'n-1', creeLe: DateTime(2026, 9, 20, 9)),
            notification(id: 'n-2', creeLe: DateTime(2026, 9, 20, 8)),
            notification(
              id: 'n-3',
              creeLe: DateTime(2026, 9, 19),
              lueLe: DateTime(2026, 9, 19, 12),
            ),
          ],
        ),
        taille: _telephoneLong,
      );

      expect(find.byType(BoutonNotifications), findsOneWidget);
      final badge = tester.widget<Badge>(
        find.descendant(
          of: find.byType(BoutonNotifications),
          matching: find.byType(Badge),
        ),
      );
      expect((badge.label! as Text).data, '2');

      // Le chiffre est doublé d'un libellé annoncé, comme la pastille des
      // propositions.
      expect(
        find.byTooltip(AppStrings.centreNonLuesBadge(2)),
        findsOneWidget,
      );
    });

    testWidgets('disparaît quand tout est lu', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
        notifications: FauxNotificationsRepository(
          notifications: <NotificationInterne>[notification(id: 'n-1')],
        ),
        taille: _telephoneLong,
      );

      expect(
        find.descendant(
          of: find.byType(BoutonNotifications),
          matching: find.byType(Badge),
        ),
        findsOneWidget,
      );

      // La cloche ouvre le centre, et « Tout marquer comme lu » l'éteint.
      await tester.tap(find.byType(BoutonNotifications));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.centreToutMarquerLu));
      await tester.pumpAndSettle();

      await ouvrirRoute(tester, '/');
      expect(
        find.descendant(
          of: find.byType(BoutonNotifications),
          matching: find.byType(Badge),
        ),
        findsNothing,
      );
      expect(find.byTooltip(AppStrings.centreOuvrir), findsOneWidget);
    });

    testWidgets('aucune pastille quand il n\'y a rien', (tester) async {
      await monterApp(
        tester,
        session: sessionMembre,
        appartenances: const <Appartenance>[appartenanceMembre],
        notifications: FauxNotificationsRepository(),
        taille: _telephoneLong,
      );

      expect(
        find.descendant(
          of: find.byType(BoutonNotifications),
          matching: find.byType(Badge),
        ),
        findsNothing,
      );
    });
  });

  group('Mise à jour sans relancer l\'application', () {
    testWidgets(
      'un push reçu au premier plan fait apparaître la ligne dans la liste',
      (tester) async {
        // La ligne interne est écrite **avant** l'envoi (ticket 025) : quand
        // le message arrive, elle est déjà en base. Le faux dépôt la publie au
        // même moment, comme le ferait la base.
        final depot = FauxNotificationsRepository();
        final push = FauxMessageriePush();

        await monterApp(
          tester,
          session: sessionMembre,
          appartenances: const <Appartenance>[appartenanceMembre],
          notifications: depot,
          messagerie: push,
          taille: _telephoneLong,
        );

        await ouvrirRoute(tester, '/notifications');
        expect(find.text(AppStrings.centreVideTitre), findsOneWidget);

        depot.notifications = <NotificationInterne>[
          notification(id: 'n-neuve'),
        ];
        push.messages.add(
          const MessagePush(
            titre: 'Une astreinte t\'est proposée',
            corps: 'Samedi 4 octobre, nuit.',
            route: '/proposals',
          ),
        );
        await tester.pumpAndSettle();

        // Sans relancer l'application, et sans Realtime : le message est le
        // signal (`design/026 § 6`).
        expect(find.byType(LigneNotification), findsOneWidget);
        expect(depot.lectures, greaterThan(1));
      },
    );
  });
}
