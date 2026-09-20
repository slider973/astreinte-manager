import 'package:astreinte_sp/core/env.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/core/theme/app_theme.dart';
import 'package:astreinte_sp/core/widgets/app_banner.dart';
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

const Env _prod = Env(
  supabaseUrl: 'https://x.supabase.co',
  supabaseAnonKey: 'anon',
  firebaseProjectId: '',
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
