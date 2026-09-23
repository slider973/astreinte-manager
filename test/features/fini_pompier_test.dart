import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/boite/domain/onglet_boite.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/dispos/domain/preferences_mois.dart';
import 'package:astreinte_sp/features/notifications/domain/notification_interne.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';
import 'package:astreinte_sp/features/propositions/presentation/widgets/carte_proposition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/faux_astreintes.dart';
import '../support/faux_auth.dart';
import '../support/faux_dispos.dart';
import '../support/faux_notifications.dart';
import '../support/faux_propositions.dart';
import '../support/polices.dart';

/// **La passe de fini du ticket 064d.**
///
/// Une seule question, posée à chaque écran du pompier et aux quatre écrans
/// d'entrée : est-ce que quelque chose déborde, ou descend sous la cible
/// tactile, quand le téléphone est réglé sur des gros caractères ?
///
/// ×1,6 n'est pas un chiffre rond choisi au hasard : c'est le réglage que
/// donne « Grande » dans les préférences d'accessibilité d'iOS, et c'est le
/// seuil au-delà duquel le Calendrier change de composition
/// (`MoisScreen.seuilDeuxNiveaux`). Un pompier de soixante ans l'a.
///
/// Les mesures se font avec les **vraies coupes du produit** : la police
/// d'essai de `flutter test` dessine chaque glyphe dans un carré d'un cadratin
/// et condamnerait des phrases qui tiennent (`test/support/polices.dart`).
const double _echelle = 1.6;

/// Le téléphone de référence, le plus étroit qu'on sert — celui de
/// `monterApp` par défaut, 390 × 844.

final DateTime _horloge = DateTime(2026, 10, 14, 9);

List<Astreinte> _astreintes() => <Astreinte>[
  for (var index = 0; index < 4; index++)
    astreinte(
      id: 'a-$index',
      jour: DateTime(2026, 10, 15 + index),
      creneau: index.isEven ? CreneauType.jour : CreneauType.nuit,
    ),
];

List<Proposition> _propositions() => <Proposition>[
  for (var index = 0; index < 3; index++)
    proposition(
      id: 'p-$index',
      creneauId: 'c-$index',
      jour: DateTime(2026, 10, 20 + index),
      creneau: index.isEven ? CreneauType.nuit : CreneauType.jour,
    ),
];

FauxDisposRepository _dispos() => FauxDisposRepository(
  periodes: <PeriodeSaisie>[
    periodeOuverte(
      annee: 2026,
      mois: 11,
      dateLimite: DateTime(2026, 10, 17, 23, 59, 59),
    ),
  ],
  disponibilites: <CreneauCle, DisponibiliteEtat>{
    CreneauCle(DateTime(2026, 11, 7), CreneauType.jour):
        DisponibiliteEtat.disponible,
    CreneauCle(DateTime(2026, 11, 8), CreneauType.nuit):
        DisponibiliteEtat.absent,
  },
  preferences: <String, PreferencesMois>{
    'periode-2026-11': const PreferencesMois(
      maxAstreintes: 12,
      maxWeekends: 4,
      commentaire: 'Pas plus d\'un weekend, garde des enfants.',
    ),
  },
);

Future<void> _ouvrirPompier(WidgetTester tester, String route) async {
  await monterApp(
    tester,
    session: sessionMembre,
    appartenances: const <Appartenance>[appartenanceMembre],
    astreintes: FauxAstreintesRepository(astreintes: _astreintes()),
    propositions: FauxPropositionsRepository(propositions: _propositions()),
    dispos: _dispos(),
    notifications: FauxNotificationsRepository(
      notifications: <NotificationInterne>[
        notification(id: 'n-1'),
        notification(
          id: 'n-2',
          type: TypeNotification.planningValide,
          titre: 'Le planning de novembre est publié',
          route: '/astreintes',
          lueLe: DateTime(2026, 10, 13, 8),
        ),
      ],
    ),
    horloge: () => _horloge,
  );
  await ouvrirRoute(tester, route);
}

/// Fait défiler la liste principale jusqu'au bout : un débordement ne se
/// signale que sur la ligne qui se peint.
Future<void> _parcourir(WidgetTester tester) async {
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) return;
  final position = tester.state<ScrollableState>(scrollables.first).position;
  if (position.maxScrollExtent <= 0) return;

  for (var pas = 1; pas <= 6; pas++) {
    position.jumpTo(
      (position.maxScrollExtent * pas / 6).clamp(0, position.maxScrollExtent),
    );
    await tester.pump();
  }
}

void main() {
  setUpAll(chargerPolicesDuProduit);

  setUp(() {
    // L'échelle vient du système, pas d'un `MediaQuery` posé sur un widget :
    // c'est la seule façon de la faire traverser les routes du routeur et les
    // feuilles de bas d'écran, qui ont leur propre `MediaQuery`.
    TestWidgetsFlutterBinding
            .instance
            .platformDispatcher
            .textScaleFactorTestValue =
        _echelle;
    addTearDown(
      TestWidgetsFlutterBinding
          .instance
          .platformDispatcher
          .clearTextScaleFactorTestValue,
    );
  });

  group('Le monde du pompier tient à ×1,6', () {
    const routes = <String, String>{
      'Accueil': AppRoutes.accueil,
      'Calendrier': AppRoutes.calendrier,
      'Astreintes': AppRoutes.astreintes,
      'Profil': AppRoutes.profil,
    };

    for (final ecran in routes.entries) {
      testWidgets('${ecran.key} : rien ne déborde', (tester) async {
        await _ouvrirPompier(tester, ecran.value);
        await _parcourir(tester);

        expect(
          tester.takeException(),
          isNull,
          reason: '${ecran.key} déborde à ×$_echelle sur un téléphone de 390',
        );
      });
    }

    for (final onglet in OngletBoite.values) {
      testWidgets('Boîte, onglet « ${onglet.name} » : rien ne déborde', (
        tester,
      ) async {
        await _ouvrirPompier(tester, AppRoutes.boiteOnglet(onglet));
        await _parcourir(tester);

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('la feuille de réponse : rien ne déborde', (tester) async {
      await _ouvrirPompier(
        tester,
        AppRoutes.boiteOnglet(OngletBoite.propositions),
      );

      await tester.tap(find.byType(CarteProposition).first);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.propositionsAccepter), findsOneWidget);
      expect(find.text(AppStrings.propositionsRefuser), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Astreintes, vue « Mois » : rien ne déborde', (tester) async {
      await _ouvrirPompier(tester, AppRoutes.astreintes);

      await tester.tap(find.text(AppStrings.astreintesVueCalendrier));
      await tester.pumpAndSettle();
      await _parcourir(tester);

      expect(tester.takeException(), isNull);
    });
  });

  // Les quatre écrans d'entrée ne sont pas restylés par ce chantier : ils sont
  // seulement éprouvés, parce qu'ils sont les premiers que voit quelqu'un et
  // qu'on n'y revient jamais pour vérifier.
  group('Les écrans d\'entrée tiennent à ×1,6', () {
    testWidgets('Connexion : rien ne déborde', (tester) async {
      await monterApp(tester);
      await ouvrirRoute(tester, AppRoutes.connexion);

      expect(find.text(AppStrings.connexionTitre), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Invitation : rien ne déborde', (tester) async {
      await monterApp(tester);
      await ouvrirRoute(tester, AppRoutes.cheminInvitation('jeton-de-test'));
      await _parcourir(tester);

      expect(tester.takeException(), isNull);
    });

    for (final ecran in <String, String>{
      'Bienvenue, profil': AppRoutes.profilAccueil,
      'Bienvenue, guide': AppRoutes.guide,
      'Aide à l\'installation': AppRoutes.installation,
    }.entries) {
      testWidgets('${ecran.key} : rien ne déborde', (tester) async {
        await monterApp(
          tester,
          session: sessionMembre,
          appartenances: const <Appartenance>[appartenanceMembre],
        );
        await ouvrirRoute(tester, ecran.value);
        await _parcourir(tester);

        expect(tester.takeException(), isNull);
      });
    }
  });
}
