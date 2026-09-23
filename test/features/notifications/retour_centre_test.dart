import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_spacing.dart';
import 'package:astreinte_sp/core/widgets/barre_actions_basse.dart';
import 'package:astreinte_sp/core/widgets/bouton_retour.dart';
import 'package:astreinte_sp/core/widgets/day_cell.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/features/accueil/presentation/accueil_screen.dart';
import 'package:astreinte_sp/features/astreintes/presentation/astreintes_screen.dart';
import 'package:astreinte_sp/features/boite/domain/onglet_boite.dart';
import 'package:astreinte_sp/features/boite/presentation/boite_screen.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/dispos/presentation/mois_screen.dart';
import 'package:astreinte_sp/features/legal/presentation/document_legal_screen.dart';
import 'package:astreinte_sp/features/notifications/domain/notification_interne.dart';
import 'package:astreinte_sp/features/notifications/presentation/widgets/bouton_notifications.dart';
import 'package:astreinte_sp/features/notifications/presentation/widgets/ligne_notification.dart';
import 'package:astreinte_sp/features/profil/presentation/profil_screen.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';
import 'package:astreinte_sp/features/propositions/presentation/widgets/carte_proposition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_dispos.dart';
import '../../support/faux_notifications.dart';
import '../../support/faux_propositions.dart';

/// Un écran haut : les quatre destinations tiennent sans défiler.
const Size _telephoneLong = Size(420, 1400);

/// Les trois destinations qui portent la cloche, et l'écran de chacune.
///
/// Elles la portent par `AppScaffold.actions` ou par l'en-tête du tableau de
/// bord — un seul et même widget, donc une seule correction
/// (`design/052 § 8.1`). La Boîte, elle, ne se montre pas le chemin vers
/// elle-même.
const Map<String, Type> _destinations = <String, Type>{
  AppRoutes.accueil: AccueilScreen,
  AppRoutes.calendrier: MoisScreen,
  AppRoutes.astreintes: AstreintesScreen,
};

Future<void> _monterMembre(
  WidgetTester tester, {
  FauxNotificationsRepository? depot,
  FauxDisposRepository? dispos,
  FauxPropositionsRepository? propositions,
}) => monterApp(
  tester,
  session: sessionMembre,
  appartenances: const <Appartenance>[appartenanceMembre],
  notifications: depot ?? FauxNotificationsRepository(),
  dispos: dispos,
  propositions: propositions,
  taille: _telephoneLong,
);

/// La sortie d'un écran poussé, dans sa forme « il y a une pile à dépiler ».
final Finder _fleche = find.byTooltip(AppStrings.actionRetour);

/// La même, dans sa forme « pile vide » : le mot est écrit à côté.
final Finder _flecheAccueil = find.text(AppStrings.retourAccueil);

/// L'index de la destination choisie dans la barre du bas.
int _destinationChoisie(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

void main() {
  group('La Boîte est une destination, pas un écran poussé', () {
    for (final destination in _destinations.entries) {
      testWidgets(
        '${destination.key} : la cloche mène à la Boîte, et la barre y reste',
        (tester) async {
          await _monterMembre(tester);
          await ouvrirRoute(tester, destination.key);
          expect(find.byType(destination.value), findsOneWidget);

          await tester.tap(find.byType(BoutonNotifications));
          await tester.pumpAndSettle();

          expect(find.byType(BoiteScreen), findsOneWidget);
          expect(emplacementCourant(tester), AppRoutes.boite);

          // **Personne n'est enfermé** : c'est l'invariant du ticket 052, et
          // il tient autrement depuis le 064. Le centre n'a plus de flèche
          // parce qu'il n'a plus de pile au-dessus de laquelle il flotte : il
          // a la barre de navigation, et ses quatre sorties.
          expect(_fleche, findsNothing);
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(
            _destinationChoisie(tester),
            3,
            reason: 'la Boîte est la quatrième destination',
          );

          // Et on en revient par où l'on veut : la barre est une sortie.
          await tester.tap(find.text(AppStrings.navAccueil));
          await tester.pumpAndSettle();
          expect(find.byType(AccueilScreen), findsOneWidget);
          expect(emplacementCourant(tester), AppRoutes.accueil);
        },
      );
    }

    // **La preuve 2 du brief du 052, transposée sur un écran poussé.** Le
    // Calendrier sur novembre, un détour par le profil, le retour — novembre,
    // pas octobre. Le mois ne vit que dans `?mois=`, et c'est ce qui se
    // perdait quand une flèche faisait un `go` vers « / ».
    testWidgets('le mois affiché survit à un détour poussé', (tester) async {
      await _monterMembre(
        tester,
        dispos: FauxDisposRepository(
          periodes: <PeriodeSaisie>[
            periodeOuverte(annee: 2026, mois: 10),
            periodeOuverte(annee: 2026, mois: 11),
          ],
        ),
      );
      const depart =
          '${AppRoutes.calendrier}?${AppRoutes.parametreMois}=2026-11';
      await ouvrirRoute(tester, depart);
      expect(
        tester.widgetList<DayCell>(find.byType(DayCell)).first.nomJour,
        'dim.',
        reason: 'le 1er novembre 2026 est un dimanche',
      );

      await ouvrirProfil(tester);
      expect(find.byType(ProfilScreen), findsOneWidget);

      await tester.tap(_fleche);
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), depart);
      expect(
        tester.widgetList<DayCell>(find.byType(DayCell)).first.nomJour,
        'dim.',
        reason: 'le mois est retombé sur octobre',
      );
    });

    testWidgets('l\'adresse dit « /boite » pendant l\'affichage', (
      tester,
    ) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.accueil);

      await tester.tap(find.byType(BoutonNotifications));
      await tester.pumpAndSettle();

      // Un rechargement doit rendre la Boîte, pas l'accueil
      // (`design/052 § 3.3`).
      expect(emplacementCourant(tester), AppRoutes.boite);
    });

    testWidgets('deux touches rapprochées n\'ouvrent qu\'une Boîte', (
      tester,
    ) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.accueil);

      // Sans attendre d'image entre les deux : la seconde touche part avant
      // que la Boîte ne soit peinte.
      await tester.tap(find.byType(BoutonNotifications));
      await tester.tap(find.byType(BoutonNotifications));
      await tester.pumpAndSettle();

      expect(find.byType(BoiteScreen), findsOneWidget);

      // **Rien n'a été empilé.** Une Boîte posée au-dessus de l'accueil
      // porterait une flèche de retour, et deux touches en poseraient deux :
      // la plainte d'origine, en pire.
      expect(find.byType(BoutonRetour), findsNothing);
      expect(find.byType(AccueilScreen, skipOffstage: false), findsNothing);
    });

    testWidgets('l\'ancienne adresse « /notifications » mène à la Boîte', (
      tester,
    ) async {
      await _monterMembre(tester);
      // Elle a été poussée par la cloche pendant six tickets : elle dort dans
      // des historiques de navigateur et dans des onglets restaurés.
      await ouvrirRoute(tester, AppRoutes.notifications);

      expect(find.byType(BoiteScreen), findsOneWidget);
      expect(emplacementCourant(tester), AppRoutes.boite);
    });
  });

  group('Les écrans poussés gardent leur flèche', () {
    testWidgets('le profil s\'ouvre par l\'avatar et se referme', (
      tester,
    ) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.accueil);

      await ouvrirProfil(tester);
      expect(find.byType(ProfilScreen), findsOneWidget);
      expect(emplacementCourant(tester), AppRoutes.profil);
      expect(_fleche, findsOneWidget);

      await tester.tap(_fleche);
      await tester.pumpAndSettle();
      expect(find.byType(ProfilScreen), findsNothing);
      expect(find.byType(AccueilScreen), findsOneWidget);
      expect(emplacementCourant(tester), AppRoutes.accueil);
    });

    testWidgets('le retour système fait la même chose que la flèche', (
      tester,
    ) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.accueil);
      await ouvrirProfil(tester);
      expect(find.byType(ProfilScreen), findsOneWidget);

      // C'est le chemin du bouton précédent du navigateur et du geste retour
      // iOS : un seul cran d'historique, le même résultat.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(ProfilScreen), findsNothing);
      expect(find.byType(AccueilScreen), findsOneWidget);
      expect(emplacementCourant(tester), AppRoutes.accueil);
    });
  });

  group('La pile vide — lien profond, URL collée, rechargement', () {
    testWidgets('la sortie porte le mot « Accueil » et mène à « / »', (
      tester,
    ) async {
      await _monterMembre(tester);
      // Aucune pile : c'est exactement ce que fait la reprise du ticket 045,
      // qui rejoue la destination mémorisée avec un `go`.
      await ouvrirRoute(tester, AppRoutes.profil);

      expect(find.byType(ProfilScreen), findsOneWidget);
      expect(_flecheAccueil, findsOneWidget);
      // Rien ne parle d'erreur : il n'y a pas d'erreur, il y a un autre
      // chemin d'arrivée.
      expect(_fleche, findsNothing);

      await tester.tap(_flecheAccueil);
      await tester.pumpAndSettle();

      expect(emplacementCourant(tester), AppRoutes.accueil);
      expect(find.byType(AccueilScreen), findsOneWidget);
    });

    testWidgets('le mot est annoncé « Aller à l\'accueil »', (tester) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.profil);

      expect(
        tester.getSemantics(_flecheAccueil).label,
        AppStrings.retourAccueilSemantique,
      );
    });

    testWidgets('la pile pleine n\'affiche pas le mot', (tester) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.accueil);
      await ouvrirProfil(tester);

      expect(_flecheAccueil, findsNothing);
      expect(_fleche, findsOneWidget);
    });
  });

  group('BoutonRetour — la place réservée au mot', () {
    testWidgets('la sortie tient la cible de 48 dp dans les deux formes', (
      tester,
    ) async {
      await _monterMembre(tester);

      await ouvrirRoute(tester, AppRoutes.profil);
      expect(
        tester.getSize(find.byType(BoutonRetour)).height,
        greaterThanOrEqualTo(48),
      );

      await ouvrirRoute(tester, AppRoutes.accueil);
      await ouvrirProfil(tester);
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
      await ouvrirRoute(tester, AppRoutes.profil);

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
    testWidgets('toucher un rappel ouvre sa cible au lieu de l\'empiler', (
      tester,
    ) async {
      await _monterMembre(
        tester,
        depot: FauxNotificationsRepository(
          notifications: <NotificationInterne>[
            notification(id: 'n-1', route: '/schedule/2026-10'),
          ],
        ),
      );
      await ouvrirRoute(tester, AppRoutes.boite);

      await tester.tap(find.byType(LigneNotification));
      await tester.pumpAndSettle();

      // `/schedule/<mois>` traduit par `destinationInterne` : la destination
      // « Astreintes ». On ne revient pas au journal après avoir ouvert ce
      // qu'il annonçait, et rien n'est empilé — c'est un `go`.
      expect(find.byType(BoiteScreen), findsNothing);
      expect(find.byType(AstreintesScreen), findsOneWidget);
      expect(emplacementCourant(tester), AppRoutes.astreintes);
      expect(_fleche, findsNothing);
    });

    testWidgets('un rappel qui mène aux propositions change d\'onglet', (
      tester,
    ) async {
      await _monterMembre(
        tester,
        depot: FauxNotificationsRepository(
          notifications: <NotificationInterne>[notification(id: 'n-1')],
        ),
        propositions: FauxPropositionsRepository(
          propositions: <Proposition>[
            proposition(id: 'a-12', creneauId: 'c-12', jour: DateTime(2026, 10, 12)),
          ],
        ),
      );
      await ouvrirRoute(tester, AppRoutes.boite);

      await tester.tap(find.byType(LigneNotification));
      await tester.pumpAndSettle();

      // Le lien public `/proposals` n'a pas bougé ; ce qu'il désigne est
      // maintenant un onglet, et non plus un écran (chantier 064b). On reste
      // donc dans la Boîte, sans rien empiler.
      expect(find.byType(BoiteScreen), findsOneWidget);
      expect(
        emplacementCourant(tester),
        AppRoutes.boiteOnglet(OngletBoite.propositions),
      );
      expect(find.byType(CarteProposition), findsOneWidget);
      expect(_fleche, findsNothing);
    });
  });

  group('Les pages légales reviennent à leur provenance', () {
    testWidgets('lues depuis « Profil », la flèche ramène sur « Profil »', (
      tester,
    ) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.accueil);
      await ouvrirProfil(tester);
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
      expect(emplacementCourant(tester), AppRoutes.profil);
    });

    testWidgets('passer à l\'autre document ne creuse pas la pile', (
      tester,
    ) async {
      await _monterMembre(tester);
      await ouvrirRoute(tester, AppRoutes.accueil);
      await ouvrirProfil(tester);

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

  // La zone sûre basse de la Boîte : la barre d'accueil de l'iPhone en PWA
  // installée mange les 34 derniers points de l'écran. Depuis le ticket 064,
  // c'est la barre de navigation qui les réserve — elle ajoute
  // `viewPadding.bottom` à sa propre hauteur (`AppScaffold`).
  group('La zone sûre basse', () {
    /// La hauteur de la barre d'accueil d'un iPhone récent, en points.
    const double barreAccueil = 34;

    /// La réserve posée sous la dernière ligne de la liste.
    EdgeInsets reserveListe(WidgetTester tester) =>
        tester
                .widget<SliverPadding>(
                  find.ancestor(
                    of: find.byType(SliverList),
                    matching: find.byType(SliverPadding),
                  ),
                )
                .padding
            as EdgeInsets;

    Future<void> ouvrirBoite(
      WidgetTester tester, {
      required bool toutLu,
    }) async {
      // Deux propriétés, deux lecteurs : `viewPadding` nourrit
      // `MediaQuery.viewPaddingOf`, que lit la barre de navigation, et
      // `padding` nourrit `SafeArea`, dont se sert `BarreActionsBasse`. Les
      // fixer toutes les deux, c'est l'iPhone en PWA installée, clavier fermé.
      final reserve = FakeViewPadding(
        bottom: barreAccueil * tester.view.devicePixelRatio,
      );
      tester.view
        ..viewPadding = reserve
        ..padding = reserve;
      await _monterMembre(
        tester,
        depot: FauxNotificationsRepository(
          notifications: <NotificationInterne>[
            // Assez de lignes pour que la liste déborde de l'écran : sans
            // défilement possible, la vérification à l'écran ne prouverait
            // rien.
            for (var index = 0; index < 40; index++)
              notification(
                id: 'n-$index',
                lueLe: toutLu ? DateTime(2026, 9, 20, 10) : null,
              ),
          ],
        ),
      );
      await ouvrirRoute(tester, AppRoutes.boite);
    }

    testWidgets('tout lu : la barre de navigation porte les 34 points', (
      tester,
    ) async {
      await ouvrirBoite(tester, toutLu: true);

      // La liste ne double pas la réserve : la barre l'a déjà posée.
      expect(find.byType(BarreActionsBasse), findsNothing);
      expect(reserveListe(tester).bottom, AppSpacing.xl);

      // Et à l'écran, une fois la liste défilée jusqu'au bout : la dernière
      // ligne s'arrête au-dessus de la barre d'accueil.
      final defilement = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      defilement.jumpTo(defilement.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        defilement.maxScrollExtent,
        greaterThan(0),
        reason: 'la liste tient dans l\'écran : le bas n\'est pas éprouvé',
      );
      expect(
        _telephoneLong.height -
            tester.getBottomLeft(find.byType(LigneNotification).last).dy,
        greaterThanOrEqualTo(barreAccueil),
      );
    });

    testWidgets('des non-lus : la barre d\'actions reste au-dessus', (
      tester,
    ) async {
      await ouvrirBoite(tester, toutLu: false);

      expect(reserveListe(tester).bottom, AppSpacing.xl);
      expect(find.byType(BarreActionsBasse), findsOneWidget);
      expect(
        _telephoneLong.height -
            tester.getBottomLeft(find.byType(PrimaryButton)).dy,
        greaterThanOrEqualTo(barreAccueil),
      );
    });
  });

  // **Les deux écrans devenus poussés au ticket 064.** Ils vivaient dans
  // `AppScaffold`, dont la barre de navigation ajoute `viewPadding.bottom` à
  // sa hauteur. Poussés, ils n'ont plus rien sous eux : sans réserve, les
  // 34 points de la barre d'accueil d'un iPhone en PWA installée mangent la
  // fin du contenu — « Se déconnecter » et « Supprimer mon compte ».
  group('La zone sûre basse des écrans poussés', () {
    const double barreAccueil = 34;

    Future<void> ouvrirAvecBarre(WidgetTester tester, String route) async {
      final reserve = FakeViewPadding(
        bottom: barreAccueil * tester.view.devicePixelRatio,
      );
      tester.view
        ..viewPadding = reserve
        ..padding = reserve;
      await _monterMembre(
        tester,
        propositions: FauxPropositionsRepository(
          propositions: <Proposition>[
            for (var index = 0; index < 28; index++)
              proposition(
                id: 'a-$index',
                creneauId: 'c-$index',
                jour: DateTime(2026, 10, index + 1),
              ),
          ],
        ),
      );
      await ouvrirRoute(tester, route);
    }

    /// Ce qui reste sous le bas de [cible].
    double sousLeBas(WidgetTester tester, Finder cible) =>
        _telephoneLong.height - tester.getBottomLeft(cible.last).dy;

    /// Amène la liste à son extrémité : c'est là, et nulle part ailleurs, que
    /// la réserve basse se voit.
    Future<void> aLaFin(WidgetTester tester) async {
      final defilement = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      defilement.jumpTo(defilement.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        defilement.maxScrollExtent,
        greaterThan(0),
        reason: 'la liste tient dans l\'écran : le bas n\'est pas éprouvé',
      );
    }

    testWidgets('le profil garde ses deux sorties au-dessus de la barre', (
      tester,
    ) async {
      await ouvrirAvecBarre(tester, AppRoutes.profil);
      await aLaFin(tester);

      // La liste elle-même s'arrête au-dessus de la barre d'accueil…
      expect(
        sousLeBas(tester, find.byType(ListView)),
        greaterThanOrEqualTo(barreAccueil),
        reason: 'la liste du profil descend sous la barre d\'accueil',
      );
      // …et donc la dernière chose qu'on y lit aussi.
      expect(
        sousLeBas(tester, find.text(AppStrings.legalMentionsLien)),
        greaterThanOrEqualTo(barreAccueil),
        reason: 'le dernier lien passe sous la barre d\'accueil',
      );
    });

    // **La Boîte, elle, est une destination.** Sa réserve basse n'est plus la
    // sienne : la barre de navigation ajoute `viewPadding.bottom` à sa propre
    // hauteur, et la liste s'arrête au-dessus de la barre.
    testWidgets('la Boîte garde sa dernière ligne au-dessus de la barre', (
      tester,
    ) async {
      await ouvrirAvecBarre(
        tester,
        AppRoutes.boiteOnglet(OngletBoite.propositions),
      );
      await aLaFin(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        sousLeBas(tester, find.byType(ListView)),
        greaterThanOrEqualTo(barreAccueil),
        reason: 'la liste de la Boîte descend sous la barre d\'accueil',
      );
      expect(
        sousLeBas(tester, find.byType(CarteProposition)),
        greaterThanOrEqualTo(barreAccueil),
        reason: 'la dernière carte passe sous la barre d\'accueil',
      );
    });
  });
}
