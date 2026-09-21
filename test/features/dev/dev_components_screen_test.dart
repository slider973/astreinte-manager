import 'package:astreinte_sp/core/env.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/core/theme/app_theme.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
import 'package:astreinte_sp/core/widgets/bouton_retour.dart';
import 'package:astreinte_sp/core/widgets/count_stat.dart';
import 'package:astreinte_sp/core/widgets/day_cell.dart';
import 'package:astreinte_sp/core/widgets/empty_state.dart';
import 'package:astreinte_sp/core/widgets/loading_skeleton.dart';
import 'package:astreinte_sp/core/widgets/primary_button.dart';
import 'package:astreinte_sp/core/widgets/save_indicator.dart';
import 'package:astreinte_sp/core/widgets/slot_chip.dart';
import 'package:astreinte_sp/core/widgets/status_badge.dart';
import 'package:astreinte_sp/features/dev/presentation/dev_components_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/faux_auth.dart';

/// Les dépôts faux évitent que la construction du routeur touche au client
/// Supabase, qui n'est pas initialisé dans un test.
List<Override> _overrides(Env env) => <Override>[
  envProvider.overrideWithValue(env),
  authRepositoryProvider.overrideWithValue(FauxAuthRepository()),
  membershipRepositoryProvider.overrideWithValue(FauxMembershipRepository()),
];

const Env _dev = Env.fromDefines;

const Env _prod = Env.sansPush(
  supabaseUrl: 'https://x.supabase.co',
  supabaseAnonKey: 'anon',
  appEnv: Env.prodEnv,
);

Future<void> _monter(
  WidgetTester tester, {
  Size taille = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = taille * tester.view.devicePixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.clair,
      home: MediaQuery(
        data: MediaQueryData(size: taille, disableAnimations: true),
        child: const DevComponentsScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('Route /dev/components', () {
    test('existe en développement, pas en production', () {
      final routesDev = ProviderContainer(overrides: _overrides(_dev))
          .read(appRouterProvider)
          .configuration
          .routes
          .whereType<GoRoute>()
          .map((route) => route.path)
          .toList();

      final routesProd = ProviderContainer(overrides: _overrides(_prod))
          .read(appRouterProvider)
          .configuration
          .routes
          .whereType<GoRoute>()
          .map((route) => route.path)
          .toList();

      expect(routesDev, contains(AppRoutes.devComponents));
      expect(routesProd, isNot(contains(AppRoutes.devComponents)));
      expect(routesProd, contains(AppRoutes.accueil));
    });
  });

  group('DevComponentsScreen', () {
    testWidgets('affiche le catalogue en clair et en sombre côte à côte', (
      tester,
    ) async {
      await _monter(tester);

      expect(find.text(AppStrings.devComposantsTitre), findsOneWidget);
      expect(find.text(AppStrings.devThemeClair), findsWidgets);
      expect(find.text(AppStrings.devThemeSombre), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('montre les onze composants du système', (tester) async {
      await _monter(tester);

      for (final type in <Type>[
        PrimaryButton,
        SlotChip,
        DayCell,
        StatusBadge,
        AppBanner,
        EmptyState,
        LoadingSkeleton,
        CountStat,
        SaveIndicator,
        BoutonRetour,
      ]) {
        expect(
          find.byType(type, skipOffstage: false),
          findsWidgets,
          reason: '$type absent du catalogue.',
        );
      }
    });

    testWidgets('le contrôle d\'apparence bascule sur un seul thème', (
      tester,
    ) async {
      await _monter(tester);

      await tester.tap(find.text(AppStrings.devThemeSombre).first);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    // **Les deux formes de la sortie, à côté l'une de l'autre** (ticket 052).
    // C'est le seul endroit du produit où on les voit ensemble : la pile
    // pleine et la pile vide n'arrivent jamais sur le même écran.
    testWidgets('montre les deux formes de BoutonRetour', (tester) async {
      await _monter(tester);

      // La pile pleine : la flèche seule, « Retour » annoncé.
      expect(find.byTooltip(AppStrings.actionRetour), findsWidgets);
      // La pile vide : le mot est écrit à côté de la flèche.
      expect(find.text(AppStrings.retourAccueil), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('les deux formes tiennent à l\'échelle 2.0', (tester) async {
      await _monter(tester);

      // `pumpAndSettle` ne rendrait jamais la main : le catalogue porte un
      // squelette de chargement dont le balayage tourne en boucle.
      await tester.tap(find.text(AppStrings.devEchelleValeur(2)));
      await tester.pump();

      // La sortie existe toujours, dans les deux spécimens et les deux
      // thèmes ; le mot, lui, a le droit de tomber.
      expect(find.byType(BoutonRetour, skipOffstage: false), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    // **Le catalogue n'écrit pas l'adresse** (ticket 052). Les spécimens de
    // `BoutonRetour` ont leur propre routeur ; s'il est monté sous une
    // application imbriquée, son `Router` rapporte l'adresse de sa pile à la
    // plateforme dès la première image et remplace « /dev/components » par
    // « / » ou « /detour ». Un seul `Router` écrit l'URL, celui de
    // l'application.
    testWidgets('aucun spécimen ne réécrit la barre d\'adresse', (
      tester,
    ) async {
      final ecritures = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        (MethodCall appel) async {
          if (appel.method == 'routeInformationUpdated') {
            final arguments = appel.arguments as Map<Object?, Object?>;
            ecritures.add('${arguments['uri'] ?? arguments['location']}');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.navigation,
          null,
        ),
      );

      // L'application réelle, avec son routeur : c'est lui, et lui seul, qui a
      // le droit d'écrire l'adresse.
      await monterApp(tester, taille: const Size(1400, 1000));
      ecritures.clear();

      // Le catalogue porte un squelette de chargement, dont le balayage
      // tourne en boucle : `pumpAndSettle` ne rendrait jamais la main.
      await ouvrirRoute(tester, AppRoutes.devComponents, stabiliser: false);
      // Le rapport d'adresse part dans un rappel d'après-image : sans ces
      // images de plus, le test passerait même avec l'application imbriquée.
      await tester.pump();
      await tester.pump();

      expect(find.byType(DevComponentsScreen), findsOneWidget);
      // Avant le correctif : « / » et « /detour », écrits par les routeurs des
      // spécimens, et un rechargement ne revenait plus ici.
      expect(ecritures, <String>[AppRoutes.devComponents]);

      // Et la flèche dépile toujours : un routeur privé de fournisseur reste
      // un routeur, `pop` parle directement à son délégué. Le spécimen à pile
      // pleine s'ouvre sur une page « Notifications » posée sur « Accueil » ;
      // après le dépilement, il en reste une de moins à l'écran.
      final detour = find.text('Notifications');
      final detoursAvant = tester.widgetList(detour).length;
      final fleche = find.byTooltip(AppStrings.actionRetour).first;
      await tester.ensureVisible(fleche);
      await tester.pump();
      await tester.tap(fleche);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.widgetList(detour).length, detoursAvant - 1);
      expect(ecritures, <String>[AppRoutes.devComponents]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('le contrôle d\'échelle passe à 2.0 sans exception', (
      tester,
    ) async {
      await _monter(tester);

      await tester.tap(find.text(AppStrings.devEchelleValeur(2)));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
