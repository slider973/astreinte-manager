import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/widgets/bouton_retour.dart';
import 'package:astreinte_sp/features/accueil/presentation/accueil_screen.dart';
import 'package:astreinte_sp/features/astreintes/presentation/astreintes_screen.dart';
import 'package:astreinte_sp/features/dispos/presentation/mois_screen.dart';
import 'package:astreinte_sp/features/legal/presentation/document_legal_screen.dart';
import 'package:astreinte_sp/features/notifications/domain/notification_interne.dart';
import 'package:astreinte_sp/features/notifications/presentation/notifications_screen.dart';
import 'package:astreinte_sp/features/notifications/presentation/widgets/bouton_notifications.dart';
import 'package:astreinte_sp/features/notifications/presentation/widgets/ligne_notification.dart';
import 'package:astreinte_sp/features/profil/presentation/profil_screen.dart';
import 'package:astreinte_sp/features/propositions/presentation/propositions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_notifications.dart';

/// Un écran haut : les quatre onglets tiennent sans défiler.
const Size _telephoneLong = Size(420, 1400);

/// Les quatre onglets que la coquille sert réellement, et l'écran de chacun.
///
/// Ce sont eux qui portent la cloche, par `AppScaffold.actions` — un seul et
/// même widget, donc une seule correction (`design/052 § 8.1`). La cinquième
/// occurrence de `BoutonNotifications` est l'état « à venir » de la coquille,
/// qu'aucune destination n'atteint aujourd'hui.
const Map<int, Type> _onglets = <int, Type>{
  0: MoisScreen,
  1: PropositionsScreen,
  2: AstreintesScreen,
  3: ProfilScreen,
};

Future<void> _monterMembre(
  WidgetTester tester, {
  FauxNotificationsRepository? depot,
}) => monterApp(
  tester,
  session: sessionMembre,
  appartenances: const <Appartenance>[appartenanceMembre],
  notifications: depot ?? FauxNotificationsRepository(),
  taille: _telephoneLong,
);

/// La sortie du centre, dans sa forme « il y a une pile à dépiler ».
final Finder _fleche = find.byTooltip(AppStrings.actionRetour);

/// La même, dans sa forme « pile vide » : le mot est écrit à côté.
final Finder _flecheAccueil = find.text(AppStrings.retourAccueil);

void main() {
  group('Le centre s\'empile et se dépile', () {
    for (final onglet in _onglets.entries) {
      testWidgets(
        'onglet ${onglet.key} : la cloche ouvre le centre, la flèche y ramène',
        (tester) async {
          await _monterMembre(tester);
          await ouvrirRoute(
            tester,
            '${AppRoutes.accueil}?${AppRoutes.parametreOnglet}=${onglet.key}',
          );
          expect(find.byType(onglet.value), findsOneWidget);

          // L'état de l'écran d'origine, tel qu'il est avant le détour. La
          // coquille ne doit pas être reconstruite : c'est elle qui tient
          // l'onglet, le mois affiché et la position de défilement.
          final avant = tester.state<State<AccueilScreen>>(
            find.byType(AccueilScreen),
          );

          await tester.tap(find.byType(BoutonNotifications));
          await tester.pumpAndSettle();

          expect(find.byType(NotificationsScreen), findsOneWidget);
          // **L'écran d'origine est toujours monté**, sous la pile : c'est la
          // preuve que la cloche a empilé au lieu de remplacer.
          expect(
            find.byType(onglet.value, skipOffstage: false),
            findsOneWidget,
          );

          await tester.tap(_fleche);
          await tester.pumpAndSettle();

          expect(find.byType(NotificationsScreen), findsNothing);
          expect(find.byType(onglet.value), findsOneWidget);
          expect(emplacementCourant(tester), startsWith(AppRoutes.accueil));
          // Le même `State`, pas un nouveau : rien n'a été resérialisé.
          expect(
            identical(
              tester.state<State<AccueilScreen>>(find.byType(AccueilScreen)),
              avant,
            ),
            isTrue,
            reason: 'la coquille a été reconstruite : l\'onglet est perdu',
          );
          expect(
            tester.widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            onglet.key,
          );
        },
      );
    }

    testWidgets('l\'adresse dit « /notifications » pendant l\'affichage', (
      tester,
    ) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.accueil);

      await tester.tap(find.byType(BoutonNotifications));
      await tester.pumpAndSettle();

      // Sans `GoRouter.optionURLReflectsImperativeAPIs`, l'adresse resterait
      // sur `/` pendant que le centre s'affiche, et un rechargement rendrait
      // l'accueil (`design/052 § 3.3`).
      expect(emplacementCourant(tester), AppRoutes.notifications);
    });

    testWidgets('deux touches rapprochées n\'empilent qu\'un seul centre', (
      tester,
    ) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.accueil);

      // Sans attendre d'image entre les deux : la seconde touche part avant
      // que le centre ne soit peint.
      await tester.tap(find.byType(BoutonNotifications));
      await tester.tap(find.byType(BoutonNotifications));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);

      // **Une seule flèche à presser pour sortir.** Deux centres empilés
      // reproduiraient la plainte d'origine, en pire.
      await tester.tap(_fleche);
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsNothing);
      expect(find.byType(MoisScreen), findsOneWidget);
    });

    testWidgets('le retour système fait la même chose que la flèche', (
      tester,
    ) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.accueil);

      await tester.tap(find.byType(BoutonNotifications));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);

      // C'est le chemin du bouton précédent du navigateur et du geste retour
      // iOS : un seul cran d'historique, le même résultat.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsNothing);
      expect(find.byType(MoisScreen), findsOneWidget);
      expect(emplacementCourant(tester), startsWith(AppRoutes.accueil));
    });
  });

  group('La pile vide — lien profond, URL collée, rechargement', () {
    testWidgets('la sortie porte le mot « Accueil » et mène à « / »', (
      tester,
    ) async {
      await _monterMembre(tester);
      // Aucune pile : c'est exactement ce que fait la reprise du ticket 045,
      // qui rejoue la destination mémorisée avec un `go`.
      await ouvrirRoute(tester, AppRoutes.notifications);

      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(_flecheAccueil, findsOneWidget);
      // Rien ne parle d'erreur : il n'y a pas d'erreur, il y a un autre
      // chemin d'arrivée.
      expect(_fleche, findsNothing);

      await tester.tap(_flecheAccueil);
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), AppRoutes.accueil);
      expect(find.byType(MoisScreen), findsOneWidget);
    });

    testWidgets('le mot est annoncé « Aller à l\'accueil »', (tester) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.notifications);

      expect(
        tester.getSemantics(_flecheAccueil).label,
        AppStrings.retourAccueilSemantique,
      );
    });

    testWidgets('la pile pleine n\'affiche pas le mot', (tester) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.accueil);
      await tester.tap(find.byType(BoutonNotifications));
      await tester.pumpAndSettle();

      expect(_flecheAccueil, findsNothing);
      expect(_fleche, findsOneWidget);
    });
  });

  group('BoutonRetour — la place réservée au mot', () {
    testWidgets('la sortie tient la cible de 48 dp dans les deux formes', (
      tester,
    ) async {
      await _monterMembre(tester);

      await ouvrirRoute(tester, AppRoutes.notifications);
      expect(
        tester.getSize(find.byType(BoutonRetour)).height,
        greaterThanOrEqualTo(48),
      );

      await ouvrirRoute(tester, AppRoutes.accueil);
      await tester.tap(find.byType(BoutonNotifications));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(BoutonRetour)).height,
        greaterThanOrEqualTo(48),
      );
    });

    // La police de `flutter test` dessine chaque caractère dans un carré d'un
    // cadratin : « Accueil » y est bien plus large qu'avec la police du
    // produit. Le seuil est donc atteint plus tôt qu'à l'écran — ce que ce
    // test vérifie est **la règle**, pas l'échelle exacte à laquelle elle
    // mord.
    testWidgets('à grande échelle de texte, le mot tombe et la flèche reste', (
      tester,
    ) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.notifications);

      // À l'échelle normale, le mot est là.
      expect(_flecheAccueil, findsOneWidget);

      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      // **La sortie ne disparaît jamais, son commentaire peut.** Le libellé
      // annoncé, lui, reste complet.
      expect(_flecheAccueil, findsNothing);
      final sortie = find.byTooltip(AppStrings.retourAccueilSemantique);
      expect(sortie, findsOneWidget);
      expect(
        tester.getSize(sortie).width,
        lessThanOrEqualTo(_telephoneLong.width * 0.45),
      );
    });
  });

  group('Non-régression du ticket 026', () {
    testWidgets('toucher une ligne quitte le centre au lieu de l\'empiler', (
      tester,
    ) async {
      await _monterMembre(
        tester,
        depot: FauxNotificationsRepository(
          notifications: <NotificationInterne>[notification(id: 'n-1')],
        ),
      );
      await ouvrirRoute(tester, AppRoutes.accueil);
      await tester.tap(find.byType(BoutonNotifications));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(LigneNotification));
      await tester.pumpAndSettle();

      // `/proposals` traduit par `destinationInterne` : l'onglet des
      // propositions, et la pile redevient celle de la destination. On ne
      // revient pas au journal après avoir ouvert ce qu'il annonçait.
      expect(find.byType(NotificationsScreen), findsNothing);
      expect(find.byType(PropositionsScreen), findsOneWidget);
      expect(
        emplacementCourant(tester),
        contains('${AppRoutes.parametreOnglet}=1'),
      );
    });
  });

  group('Les pages légales reviennent à leur provenance', () {
    testWidgets('lues depuis « Profil », la flèche ramène sur « Profil »', (
      tester,
    ) async {
      await _monterMembre(tester);
      await ouvrirRoute(
        tester,
        '${AppRoutes.accueil}?${AppRoutes.parametreOnglet}=3',
      );
      expect(find.byType(ProfilScreen), findsOneWidget);

      await defilerJusqua(
        tester,
        find.text(AppStrings.legalConfidentialiteLien),
      );
      await tester.tap(find.text(AppStrings.legalConfidentialiteLien));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentLegalScreen), findsOneWidget);

      await tester.tap(_fleche);
      await tester.pumpAndSettle();

      // Avant le ticket 052, `go` remettait la pile à plat et renvoyait sur
      // « Mon mois ».
      expect(find.byType(ProfilScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
    });

    testWidgets('passer à l\'autre document ne creuse pas la pile', (
      tester,
    ) async {
      await _monterMembre(tester);
      await ouvrirRoute(
        tester,
        '${AppRoutes.accueil}?${AppRoutes.parametreOnglet}=3',
      );

      await defilerJusqua(
        tester,
        find.text(AppStrings.legalConfidentialiteLien),
      );
      await tester.tap(find.text(AppStrings.legalConfidentialiteLien));
      await tester.pumpAndSettle();

      // Le pied de page renvoie vers les mentions légales : un mouvement
      // latéral, pas un détour dans le détour.
      await defilerJusqua(tester, find.text(AppStrings.legalMentionsLien));
      await tester.tap(find.text(AppStrings.legalMentionsLien));
      await tester.pumpAndSettle();
      expect(emplacementCourant(tester), AppRoutes.mentions);

      // Une seule flèche, et on est revenu à « Profil ».
      await tester.tap(_fleche);
      await tester.pumpAndSettle();
      expect(find.byType(ProfilScreen), findsOneWidget);
    });

    testWidgets('ouverte par une URL seule, la page mène à l\'accueil', (
      tester,
    ) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.mentions);

      expect(_flecheAccueil, findsOneWidget);
      await tester.tap(_flecheAccueil);
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), AppRoutes.accueil);
    });
  });
}
