/// **La Boîte à trois onglets** (chantier 064b) : la structure, l'adresse, les
/// trois états vides, l'erreur d'une seule source et le grand écran.
///
/// Les deux parcours qu'elle réunit sont éprouvés ailleurs, dans les fichiers
/// qu'ils habitaient déjà : `reponse_propositions_test.dart` pour la réponse
/// du ticket 021, `rappels_test.dart` pour le marquage du ticket 026.
library;

import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/widgets/empty_state.dart';
import 'package:astreinte_sp/features/boite/domain/onglet_boite.dart';
import 'package:astreinte_sp/features/boite/presentation/widgets/panneau_reponse.dart';
import 'package:astreinte_sp/features/boite/presentation/widgets/squelette_boite.dart';
import 'package:astreinte_sp/features/notifications/domain/notification_interne.dart';
import 'package:astreinte_sp/features/notifications/presentation/widgets/ligne_notification.dart';
import 'package:astreinte_sp/features/propositions/data/propositions_repository.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';
import 'package:astreinte_sp/features/propositions/presentation/widgets/carte_proposition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth.dart';
import '../../support/faux_notifications.dart';
import '../../support/faux_propositions.dart';

/// Un téléphone haut : les trois onglets et leurs lignes tiennent sans
/// défiler.
const Size _telephone = Size(390, 1000);

/// Un poste : la colonne de navigation du 061 et le volet latéral.
const Size _poste = Size(1440, 900);

/// La barre d'accueil d'un iPhone en PWA installée.
const double _barreAccueil = 34;

/// Deux propositions en attente, dont une de nuit.
List<Proposition> _propositions() => <Proposition>[
  proposition(
    id: 'a-12',
    creneauId: 'c-12',
    jour: DateTime(2026, 10, 12),
    proposeeLe: DateTime(2026, 9, 20, 7),
  ),
  proposition(
    id: 'a-19',
    creneauId: 'c-19',
    jour: DateTime(2026, 10, 19),
    creneau: CreneauType.jour,
    proposeeLe: DateTime(2026, 9, 19, 9),
  ),
];

/// Trois rappels, dont deux non lus.
List<NotificationInterne> _rappels() => <NotificationInterne>[
  notification(
    id: 'n-publie',
    type: TypeNotification.planningValide,
    titre: 'Planning d\'octobre validé',
    route: '/schedule/2026-10',
    creeLe: DateTime(2026, 9, 20, 8),
  ),
  notification(
    id: 'n-saisie',
    type: TypeNotification.rappelSaisie,
    titre: 'Saisis tes disponibilités d\'octobre',
    route: '/availability/2026-10',
    creeLe: DateTime(2026, 9, 19, 8),
  ),
  notification(
    id: 'n-lue',
    type: TypeNotification.creneauAnnule,
    titre: 'Ton créneau du 5 est annulé',
    route: '/schedule/2026-10',
    creeLe: DateTime(2026, 9, 18, 8),
    lueLe: DateTime(2026, 9, 18, 9),
  ),
];

Future<void> _ouvrir(
  WidgetTester tester, {
  OngletBoite onglet = OngletBoite.tout,
  List<Proposition>? propositions,
  List<NotificationInterne>? rappels,
  bool erreurPropositions = false,
  bool erreurRappels = false,
  Size taille = _telephone,
  bool stabiliser = true,
}) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    propositions: FauxPropositionsRepository(
      propositions: propositions ?? _propositions(),
      erreurLecture: erreurPropositions ? ErreurProposition.reseau : null,
    ),
    notifications: FauxNotificationsRepository(
      notifications: rappels ?? _rappels(),
      erreurLecture: erreurRappels,
    ),
    taille: taille,
    stabiliser: stabiliser,
  );
  await ouvrirRoute(
    tester,
    AppRoutes.boiteOnglet(onglet),
    stabiliser: stabiliser,
  );
}

/// Le titre de la barre d'application. « Boîte » tout court s'écrit aussi
/// dans la barre du bas : `find.text` en trouverait deux.
String _titre(WidgetTester tester) => tester
    .widget<Text>(
      find
          .descendant(of: find.byType(AppBar), matching: find.byType(Text))
          .first,
    )
    .data!;

Finder _onglet(OngletBoite onglet) =>
    find.widgetWithText(Tab, onglet.libelle);

void main() {
  group('Les trois onglets et l\'adresse', () {
    testWidgets('la barre porte les trois, dans l\'ordre du brief', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(find.byType(TabBar), findsOneWidget);
      for (final onglet in OngletBoite.values) {
        expect(_onglet(onglet), findsOneWidget, reason: onglet.libelle);
      }
      expect(
        tester.widget<TabBar>(find.byType(TabBar)).tabs,
        hasLength(3),
      );
    });

    testWidgets('l\'adresse ouvre l\'onglet qu\'elle nomme', (tester) async {
      for (final onglet in OngletBoite.values) {
        await _ouvrir(tester, onglet: onglet);
        expect(
          tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
          onglet.index,
          reason: onglet.valeurUrl,
        );
        await demonter(tester);
      }
    });

    testWidgets('toucher un onglet écrit l\'adresse', (tester) async {
      await _ouvrir(tester);
      expect(
        emplacementCourant(tester),
        AppRoutes.boiteOnglet(OngletBoite.tout),
      );

      await tester.tap(_onglet(OngletBoite.rappels));
      await tester.pumpAndSettle();

      expect(
        emplacementCourant(tester),
        AppRoutes.boiteOnglet(OngletBoite.rappels),
      );
      // Et le contenu a suivi : les propositions ne sont plus là.
      expect(find.byType(CarteProposition), findsNothing);
      expect(find.byType(LigneNotification), findsNWidgets(3));
    });

    testWidgets('l\'onglet ne quitte jamais l\'URL pour un cache', (
      tester,
    ) async {
      // La règle des caches locaux de `CLAUDE.md` : un onglet retenu sur
      // l'appareil aurait survécu à une déconnexion et fait ouvrir la Boîte
      // ailleurs que là où le lien promettait. Ici, remonter l'application
      // sans adresse rouvre « Tout ».
      await _ouvrir(tester, onglet: OngletBoite.rappels);
      await demonter(tester);

      await _ouvrir(tester);
      expect(
        tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
        OngletBoite.tout.index,
      );
    });

    testWidgets('« /propositions » renvoie sur l\'onglet', (tester) async {
      await _ouvrir(tester);
      // L'adresse de l'écran du chantier 064a : elle dort dans des
      // historiques de navigateur et dans des onglets restaurés.
      await ouvrirRoute(tester, AppRoutes.propositions);

      expect(
        emplacementCourant(tester),
        AppRoutes.boiteOnglet(OngletBoite.propositions),
      );
      expect(find.byType(CarteProposition), findsNWidgets(2));
    });

    testWidgets('chaque onglet dit ce qu\'il contient', (tester) async {
      final semantique = tester.ensureSemantics();
      await _ouvrir(tester);

      // « Tout » tout seul ne dit pas de quoi. La `TabBar` ajoute « Onglet 1
      // sur 3 » autour du libellé : on cherche la phrase, pas l'égalité.
      for (final onglet in OngletBoite.values) {
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(onglet.annonce))),
          findsWidgets,
          reason: onglet.libelle,
        );
      }
      semantique.dispose();
    });

    testWidgets('chaque onglet tient la cible tactile', (tester) async {
      await _ouvrir(tester);

      for (final onglet in OngletBoite.values) {
        expect(
          tester.getSize(_onglet(onglet)).height,
          greaterThanOrEqualTo(44),
          reason: onglet.libelle,
        );
      }
    });

    testWidgets('à grande échelle de texte, rien ne déborde', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _ouvrir(tester);

      // Trois onglets côte à côte sur un téléphone de 390, c'est le cas le
      // plus serré de l'écran : `flutter test` dessine chaque caractère dans
      // un carré d'un cadratin, donc la mesure est plus dure qu'à l'écran.
      expect(tester.takeException(), isNull);
      for (final onglet in OngletBoite.values) {
        expect(_onglet(onglet), findsOneWidget, reason: onglet.libelle);
      }
    });
  });

  group('« Tout marquer comme lu »', () {
    testWidgets('il est là où il était : en fin de liste', (tester) async {
      await _ouvrir(tester, onglet: OngletBoite.rappels);
      expect(find.text(AppStrings.centreToutMarquerLu), findsOneWidget);
    });

    testWidgets('il n\'est pas sur « Propositions »', (tester) async {
      // Il n'y marquerait rien de ce qui est à l'écran.
      await _ouvrir(tester, onglet: OngletBoite.propositions);
      expect(find.text(AppStrings.centreToutMarquerLu), findsNothing);
    });

    testWidgets('il disparaît quand tout est lu', (tester) async {
      await _ouvrir(
        tester,
        onglet: OngletBoite.rappels,
        rappels: <NotificationInterne>[
          notification(
            id: 'n-lue',
            type: TypeNotification.planningValide,
            lueLe: DateTime(2026, 9, 18, 9),
          ),
        ],
      );

      // Un bouton désactivé qu'il faudrait expliquer à côté vaut moins qu'un
      // bouton absent (`design/026 § 3`).
      expect(find.text(AppStrings.centreToutMarquerLu), findsNothing);
      expect(_titre(tester), AppStrings.boiteTitre(0));
    });
  });

  group('Ce que chaque onglet montre', () {
    testWidgets('« Tout » fusionne les deux, la plus récente en premier', (
      tester,
    ) async {
      await _ouvrir(tester);

      expect(find.byType(CarteProposition), findsNWidgets(2));
      expect(find.byType(LigneNotification), findsNWidgets(3));

      // La proposition du 20 à 7 h est sous le rappel du 20 à 8 h, et
      // au-dessus du rappel du 19.
      final proposition = tester.getTopLeft(
        find.byKey(const ValueKey<String>('a-12')),
      );
      final publie = tester.getTopLeft(
        find.byKey(const ValueKey<String>('n-publie')),
      );
      final saisie = tester.getTopLeft(
        find.byKey(const ValueKey<String>('n-saisie')),
      );
      expect(publie.dy, lessThan(proposition.dy));
      expect(proposition.dy, lessThan(saisie.dy));
    });

    testWidgets('« Propositions » ne montre que les propositions', (
      tester,
    ) async {
      await _ouvrir(tester, onglet: OngletBoite.propositions);

      expect(find.byType(CarteProposition), findsNWidgets(2));
      expect(find.byType(LigneNotification), findsNothing);
      // Groupées par mois, comme au ticket 021.
      expect(find.text('Octobre 2026'), findsOneWidget);
    });

    testWidgets('« Rappels » ne montre que les rappels', (tester) async {
      await _ouvrir(tester, onglet: OngletBoite.rappels);

      expect(find.byType(LigneNotification), findsNWidgets(3));
      expect(find.byType(CarteProposition), findsNothing);
    });

    testWidgets(
      'une notification de proposition n\'est ni un rappel ni un compte',
      (tester) async {
        await _ouvrir(
          tester,
          onglet: OngletBoite.rappels,
          rappels: <NotificationInterne>[
            notification(
              id: 'n-proposee',
              type: TypeNotification.astreinteProposee,
              titre: 'Une astreinte t\'est proposée',
            ),
          ],
        );

        // Elle pose la même question que la ligne de proposition, qui, elle,
        // porte la réponse. Et elle ne gonfle pas une pastille que plus aucun
        // écran ne saurait vider.
        expect(find.byType(LigneNotification), findsNothing);
        expect(find.text(AppStrings.boiteVideRappelsTitre), findsOneWidget);
        expect(_titre(tester), AppStrings.boiteTitre(0));
      },
    );

    testWidgets('le titre compte les rappels non lus', (tester) async {
      await _ouvrir(tester);
      expect(_titre(tester), AppStrings.boiteTitre(2));
    });

    testWidgets('la pastille de la barre porte le même nombre', (
      tester,
    ) async {
      await _ouvrir(tester);

      // Deux nombres qui divergeraient seraient deux vérités : ils lisent la
      // même source.
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    });
  });

  group('Les états vides, un par onglet', () {
    testWidgets('« Tout » : rien pour l\'instant', (tester) async {
      await _ouvrir(
        tester,
        propositions: const <Proposition>[],
        rappels: const <NotificationInterne>[],
      );

      expect(find.text(AppStrings.centreVideTitre), findsOneWidget);
      expect(find.text(AppStrings.centreVideTexte), findsOneWidget);
    });

    testWidgets('« Propositions » : aucune proposition en attente', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        onglet: OngletBoite.propositions,
        propositions: const <Proposition>[],
      );

      expect(find.text(AppStrings.videPropositionsTitre), findsOneWidget);
      // Et sa sortie : il y a quelque chose à faire ailleurs.
      expect(find.text(AppStrings.propositionsVideAction), findsOneWidget);
    });

    testWidgets('« Rappels » : aucun rappel, et rien à promettre', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        onglet: OngletBoite.rappels,
        rappels: const <NotificationInterne>[],
      );

      expect(find.text(AppStrings.boiteVideRappelsTitre), findsOneWidget);
      expect(find.text(AppStrings.boiteVideRappelsTexte), findsOneWidget);
      // Rien à faire : le dire est plus honnête qu'un bouton qui n'irait
      // nulle part.
      expect(find.text(AppStrings.actionReessayer), findsNothing);
    });

    testWidgets('le chargement montre un squelette, jamais une roue', (
      tester,
    ) async {
      await _ouvrir(tester, stabiliser: false);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(SqueletteBoite), findsNothing);
    });

    testWidgets('le squelette a la forme de quatre cartes de liste', (
      tester,
    ) async {
      // Éprouvé à part : les faux dépôts répondent en une micro-tâche, et
      // l'écran ne passe donc jamais assez longtemps par son squelette pour
      // qu'un test d'écran l'y attrape.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SqueletteBoite()),
        ),
      );
      await tester.pump();

      expect(find.byType(SqueletteBoite), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Une source en panne n\'efface pas l\'autre', () {
    testWidgets('les propositions tombent : les rappels restent, dans Tout', (
      tester,
    ) async {
      await _ouvrir(tester, erreurPropositions: true);

      expect(find.text(AppStrings.propositionsErreurTexte), findsOneWidget);
      expect(find.text(AppStrings.actionReessayer), findsOneWidget);
      // **Jamais « Rien pour l'instant » sur une lecture en panne** : c'est
      // faux, et ça se croit.
      expect(find.text(AppStrings.centreVideTitre), findsNothing);
      expect(find.byType(LigneNotification), findsNWidgets(3));
    });

    testWidgets('les rappels tombent : les propositions restent, dans Tout', (
      tester,
    ) async {
      await _ouvrir(tester, erreurRappels: true);

      expect(find.text(AppStrings.centreErreurTexte), findsOneWidget);
      expect(find.byType(CarteProposition), findsNWidgets(2));
      expect(find.text(AppStrings.centreVideTitre), findsNothing);
    });

    testWidgets('chaque onglet ne dit que l\'échec qui le concerne', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        onglet: OngletBoite.propositions,
        erreurRappels: true,
      );

      expect(find.byType(EmptyState), findsNothing);
      expect(find.byType(CarteProposition), findsNWidgets(2));

      await tester.tap(_onglet(OngletBoite.rappels));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.centreErreurTexte), findsOneWidget);
    });
  });

  group('La Boîte est une destination', () {
    testWidgets('pas de flèche, la barre du bas reste', (tester) async {
      await _ouvrir(tester);

      expect(find.byTooltip(AppStrings.actionRetour), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
        reason: 'la Boîte est la quatrième destination',
      );
    });

    testWidgets('la liste s\'arrête au-dessus de la barre d\'accueil', (
      tester,
    ) async {
      const reserve = FakeViewPadding(bottom: _barreAccueil);
      tester.view
        ..viewPadding = reserve
        ..padding = reserve;
      addTearDown(tester.view.reset);

      await _ouvrir(tester, onglet: OngletBoite.rappels);

      final bas = tester.getBottomLeft(find.byType(ListView)).dy;
      expect(_telephone.height - bas, greaterThanOrEqualTo(_barreAccueil));
    });
  });

  group('Le grand écran', () {
    testWidgets('la réponse s\'ouvre dans le volet, pas dans une feuille', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        onglet: OngletBoite.propositions,
        taille: _poste,
      );

      expect(find.byType(PanneauReponse), findsNothing);

      await tester.tap(find.byType(CarteProposition).first);
      await tester.pumpAndSettle();

      // Jamais une modale pour une tâche qui ne demande ni interruption ni
      // protection (`DESIGN.md § Don't`).
      expect(find.byType(PanneauReponse), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      // La liste est toujours là, à gauche : le volet ne la recouvre pas.
      expect(find.byType(CarteProposition), findsNWidgets(2));
    });

    testWidgets('le volet se referme et la liste reste', (tester) async {
      await _ouvrir(
        tester,
        onglet: OngletBoite.propositions,
        taille: _poste,
      );

      await tester.tap(find.byType(CarteProposition).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(AppStrings.boiteReponseFermer));
      await tester.pumpAndSettle();

      expect(find.byType(PanneauReponse), findsNothing);
      expect(find.byType(CarteProposition), findsNWidgets(2));
    });

    testWidgets('les onglets sont là, et la colonne du 061 avec', (
      tester,
    ) async {
      await _ouvrir(tester, taille: _poste);

      expect(find.byType(TabBar), findsOneWidget);
      // La barre du bas a laissé la place à la colonne (ticket 061b).
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text(AppStrings.navBoite), findsWidgets);
    });
  });

  group('Sur téléphone, la réponse est une feuille', () {
    testWidgets('elle s\'ouvre, puis le geste retour la referme', (
      tester,
    ) async {
      await _ouvrir(tester, onglet: OngletBoite.propositions);

      await tester.tap(find.byType(CarteProposition).first);
      await tester.pumpAndSettle();
      expect(find.byType(PanneauReponse), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(PanneauReponse), findsNothing);
      // On est resté dans la Boîte : la feuille n'était pas une page.
      expect(
        emplacementCourant(tester),
        AppRoutes.boiteOnglet(OngletBoite.propositions),
      );
    });

    testWidgets('elle s\'ouvre aussi depuis « Tout »', (tester) async {
      await _ouvrir(tester);

      await tester.tap(find.byType(CarteProposition).first);
      await tester.pumpAndSettle();

      expect(find.byType(PanneauReponse), findsOneWidget);
      expect(find.text(AppStrings.propositionsAccepter), findsOneWidget);
    });
  });
}
