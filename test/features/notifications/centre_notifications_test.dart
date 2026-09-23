import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/features/notifications/domain/notification_interne.dart';
import 'package:astreinte_sp/features/notifications/presentation/notifications_screen.dart';
import 'package:astreinte_sp/features/notifications/presentation/widgets/ligne_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_notifications.dart';

const String _chemin = '/notifications';

/// Un écran haut : quelques lignes tiennent sans défiler, et la composition
/// reste celle du téléphone.
const Size _telephoneLong = Size(420, 1400);

Future<void> _ouvrirCentre(
  WidgetTester tester, {
  required FauxNotificationsRepository depot,
  Appartenance appartenance = appartenanceMembre,
  bool stabiliser = true,
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: <Appartenance>[appartenance],
    notifications: depot,
    taille: _telephoneLong,
  );
  await ouvrirRoute(tester, _chemin, stabiliser: stabiliser);
}

void main() {
  group('NotificationsScreen — rendu', () {
    testWidgets('liste les notifications, la plus récente en premier', (
      tester,
    ) async {
      await _ouvrirCentre(
        tester,
        depot: FauxNotificationsRepository(
          notifications: <NotificationInterne>[
            notification(
              id: 'n-ancienne',
              titre: 'Planning validé',
              corps: 'Ton mois d\'octobre est validé.',
              type: TypeNotification.planningValide,
              route: '/schedule/2026-10',
              creeLe: DateTime(2026, 9, 18, 8),
              lueLe: DateTime(2026, 9, 18, 9),
            ),
            notification(
              id: 'n-recente',
              creeLe: DateTime(2026, 9, 20, 9),
            ),
          ],
        ),
      );

      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.byType(LigneNotification), findsNWidgets(2));

      // L'ordre : la plus récente est au-dessus de l'autre.
      final recente = tester.getTopLeft(
        find.byKey(const ValueKey<String>('n-recente')),
      );
      final ancienne = tester.getTopLeft(
        find.byKey(const ValueKey<String>('n-ancienne')),
      );
      expect(recente.dy, lessThan(ancienne.dy));

      // Le compte de l'en-tête dit combien de lignes suivent, et combien
      // restent à lire.
      expect(find.text(AppStrings.centreCompte(2, 1)), findsOneWidget);
    });

    testWidgets('une non-lue se distingue autrement que par la couleur', (
      tester,
    ) async {
      await _ouvrirCentre(
        tester,
        depot: FauxNotificationsRepository(
          notifications: <NotificationInterne>[
            notification(id: 'n-1'),
            notification(
              id: 'n-2',
              titre: 'Planning validé',
              creeLe: DateTime(2026, 9, 19),
              lueLe: DateTime(2026, 9, 19, 12),
            ),
          ],
        ),
      );

      // Le mot « Non lue » est dans le libellé annoncé de la ligne non lue, et
      // dans celui-là seulement : la marque carrée est doublée d'un mot.
      final annoncees = tester
          .widgetList<Semantics>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('n-1')),
              matching: find.byType(Semantics),
            ),
          )
          .where((s) => s.properties.label?.startsWith(
                AppStrings.centreNonLue,
              ) ?? false);
      expect(annoncees, isNotEmpty);

      final lues = tester
          .widgetList<Semantics>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('n-2')),
              matching: find.byType(Semantics),
            ),
          )
          .where((s) => s.properties.label?.contains(
                AppStrings.centreNonLue,
              ) ?? false);
      expect(lues, isEmpty);
    });

    testWidgets('la liste vide explique et ne propose rien de faux', (
      tester,
    ) async {
      await _ouvrirCentre(tester, depot: FauxNotificationsRepository());

      expect(find.text(AppStrings.centreVideTitre), findsOneWidget);
      expect(find.text(AppStrings.centreVideTexte), findsOneWidget);
      expect(find.byType(LigneNotification), findsNothing);

      // Rien à marquer, donc pas de bouton.
      expect(find.text(AppStrings.centreToutMarquerLu), findsNothing);
    });

    testWidgets('une lecture en échec propose de réessayer', (tester) async {
      final depot = FauxNotificationsRepository(erreurLecture: true);
      await _ouvrirCentre(tester, depot: depot);

      expect(find.text(AppStrings.centreErreurTexte), findsOneWidget);
      expect(find.text(AppStrings.actionReessayer), findsOneWidget);

      depot.erreurLecture = false;
      depot.notifications = <NotificationInterne>[notification(id: 'n-1')];
      await tester.tap(find.text(AppStrings.actionReessayer));
      await tester.pumpAndSettle();

      expect(find.byType(LigneNotification), findsOneWidget);
    });

    testWidgets('le chargement montre un squelette, jamais une roue', (
      tester,
    ) async {
      await _ouvrirCentre(
        tester,
        depot: FauxNotificationsRepository(
          notifications: <NotificationInterne>[notification(id: 'n-1')],
        ),
        stabiliser: false,
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('la ligne touchée tient le plancher tactile', (tester) async {
      await _ouvrirCentre(
        tester,
        depot: FauxNotificationsRepository(
          notifications: <NotificationInterne>[notification(id: 'n-1')],
        ),
      );

      final taille = tester.getSize(find.byType(LigneNotification));
      expect(taille.height, greaterThanOrEqualTo(44));
    });
  });

  group('NotificationsScreen — marquage', () {
    testWidgets('une touche marque la ligne lue et ouvre la destination', (
      tester,
    ) async {
      final depot = FauxNotificationsRepository(
        notifications: <NotificationInterne>[
          notification(id: 'n-1', route: '/availability/2026-10'),
        ],
      );
      await _ouvrirCentre(tester, depot: depot);

      await tester.tap(find.byKey(const ValueKey<String>('n-1')));
      await tester.pumpAndSettle();

      expect(depot.marquages, <String>['n-1']);
      expect(depot.notifications.single.lue, isTrue);

      // `/availability/<mois>` est la seule des quatre destinations qui mène
      // déjà exactement où il faut (ticket 024).
      expect(
        emplacementCourant(tester),
        '${AppRoutes.calendrier}?mois=2026-10',
      );
    });

    testWidgets(
      'une destination refusée ramène à l\'accueil sans message d\'erreur',
      (tester) async {
        final depot = FauxNotificationsRepository(
          notifications: <NotificationInterne>[
            // Le suivi admin, chez un membre qui n'administre pas : le lien
            // peut dater d'avant une rétrogradation.
            notification(
              id: 'n-refusee',
              type: TypeNotification.retardataires,
              titre: 'Trois pompiers n\'ont pas répondu',
              route: '/admin/schedule/2026-10',
            ),
          ],
        );
        await _ouvrirCentre(tester, depot: depot);

        await tester.tap(find.byKey(const ValueKey<String>('n-refusee')));
        await tester.pumpAndSettle();

        expect(emplacementCourant(tester), '/');
        expect(find.byType(SnackBar), findsNothing);
        // La ligne est quand même lue : elle a bien été lue.
        expect(depot.notifications.single.lue, isTrue);
      },
    );

    testWidgets('un type et un lien inconnus ramènent aussi à l\'accueil', (
      tester,
    ) async {
      final depot = FauxNotificationsRepository(
        notifications: <NotificationInterne>[
          notification(
            id: 'n-inconnue',
            type: TypeNotification.inconnu,
            titre: 'Un événement que cette version ne connaît pas',
            route: '/quelque-chose-de-nouveau',
          ),
        ],
      );
      await _ouvrirCentre(tester, depot: depot);

      // Affichée malgré tout : une notification qu'on ne sait pas classer
      // reste une notification qu'il faut lire.
      expect(find.byType(LigneNotification), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('n-inconnue')));
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), '/');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('un marquage refusé remet la ligne non lue et le dit', (
      tester,
    ) async {
      final depot = FauxNotificationsRepository(
        notifications: <NotificationInterne>[notification(id: 'n-1')],
        erreurEcriture: true,
      );
      await _ouvrirCentre(tester, depot: depot);

      await tester.tap(find.byKey(const ValueKey<String>('n-1')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.centreEchecLecture), findsOneWidget);
      expect(depot.notifications.single.lue, isFalse);
    });

    testWidgets('« Tout marquer comme lu » vide le compte de non-lues', (
      tester,
    ) async {
      final depot = FauxNotificationsRepository(
        notifications: <NotificationInterne>[
          notification(id: 'n-1', creeLe: DateTime(2026, 9, 20, 9)),
          notification(id: 'n-2', creeLe: DateTime(2026, 9, 20, 8)),
          notification(
            id: 'n-3',
            creeLe: DateTime(2026, 9, 19),
            lueLe: DateTime(2026, 9, 19, 12),
          ),
        ],
      );
      await _ouvrirCentre(tester, depot: depot);

      expect(find.text(AppStrings.centreCompte(3, 2)), findsOneWidget);

      await tester.tap(find.text(AppStrings.centreToutMarquerLu));
      await tester.pumpAndSettle();

      expect(depot.marquagesGlobaux, 1);
      expect(depot.notifications.every((n) => n.lue), isTrue);
      expect(find.text(AppStrings.centreCompte(3, 0)), findsOneWidget);
      expect(find.text(AppStrings.centreToutMarqueLuConfirmation),
          findsOneWidget);

      // Plus rien à marquer : le bouton disparaît.
      expect(find.text(AppStrings.centreToutMarquerLu), findsNothing);
    });

    testWidgets('un « tout marquer » refusé rend les non-lues et le dit', (
      tester,
    ) async {
      final depot = FauxNotificationsRepository(
        notifications: <NotificationInterne>[notification(id: 'n-1')],
        erreurEcriture: true,
      );
      await _ouvrirCentre(tester, depot: depot);

      await tester.tap(find.text(AppStrings.centreToutMarquerLu));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.centreEchecLecture), findsOneWidget);
      expect(find.text(AppStrings.centreCompte(1, 1)), findsOneWidget);
    });
  });
}
