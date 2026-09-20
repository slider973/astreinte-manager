import 'package:astreinte_sp/core/env.dart';
import 'package:astreinte_sp/core/l10n/app_strings.dart';
import 'package:astreinte_sp/features/hello/presentation/hello_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildSubject({required Env env}) {
  return ProviderScope(
    overrides: [envProvider.overrideWithValue(env)],
    child: const MaterialApp(home: HelloScreen()),
  );
}

const Env _configuredEnv = Env(
  supabaseUrl: 'https://test.supabase.co',
  supabaseAnonKey: 'anon',
  firebaseProjectId: 'astreinte-test',
  appEnv: 'dev',
);

const Env _emptyEnv = Env(
  supabaseUrl: '',
  supabaseAnonKey: '',
  firebaseProjectId: '',
  appEnv: 'prod',
);

void main() {
  group('HelloScreen', () {
    testWidgets('affiche le titre, les libellés et les valeurs de Env', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSubject(env: _configuredEnv));

      expect(find.text(AppStrings.appTitle), findsOneWidget);
      expect(find.text(AppStrings.helloTitle), findsOneWidget);
      expect(find.text(AppStrings.appEnvLabel), findsOneWidget);
      expect(find.text(AppStrings.supabaseUrlLabel), findsOneWidget);
      expect(find.text('dev'), findsOneWidget);
      expect(find.text('https://test.supabase.co'), findsOneWidget);
    });

    testWidgets('signale une valeur non définie plutôt qu\'un vide', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSubject(env: _emptyEnv));

      expect(find.text('prod'), findsOneWidget);
      expect(find.text(AppStrings.valueUndefined), findsOneWidget);
    });

    testWidgets('expose les valeurs aux lecteurs d\'écran', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_buildSubject(env: _configuredEnv));

      expect(
        tester.getSemantics(find.bySemanticsLabel(AppStrings.supabaseUrlLabel)),
        matchesSemantics(
          label: AppStrings.supabaseUrlLabel,
          value: 'https://test.supabase.co',
        ),
      );

      handle.dispose();
    });

    testWidgets('reste lisible avec une grande taille de police', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _buildSubject(env: _configuredEnv),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('https://test.supabase.co'), findsOneWidget);
    });
  });
}
