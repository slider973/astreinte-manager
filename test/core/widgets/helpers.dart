import 'package:astreinte_sp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Monte un composant sous le vrai thème de l'application.
///
/// Aucun test du système ne monte un widget sous `ThemeData()` : l'extension
/// `AppStatusColors` serait absente et le test ne prouverait rien de ce que
/// l'utilisateur verra.
Future<void> monter(
  WidgetTester tester,
  Widget composant, {
  Brightness brightness = Brightness.light,
  double echelleTexte = 1,
  bool animationsDesactivees = false,
  Size taille = const Size(390, 844),
  EdgeInsets viewPadding = EdgeInsets.zero,
}) async {
  tester.view
    ..physicalSize = taille * tester.view.devicePixelRatio
    ..devicePixelRatio = tester.view.devicePixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.sombre : AppTheme.clair,
      home: MediaQuery(
        data: MediaQueryData(
          size: taille,
          viewPadding: viewPadding,
          padding: viewPadding,
          textScaler: TextScaler.linear(echelleTexte),
          disableAnimations: animationsDesactivees,
        ),
        child: Scaffold(body: composant),
      ),
    ),
  );
}

/// Monte un composant tel quel, sans `Scaffold` (pour `AppScaffold`).
Future<void> monterEcran(
  WidgetTester tester,
  Widget ecran, {
  Brightness brightness = Brightness.light,
  double echelleTexte = 1,
  Size taille = const Size(390, 844),
  EdgeInsets viewPadding = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = taille * tester.view.devicePixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.sombre : AppTheme.clair,
      home: MediaQuery(
        data: MediaQueryData(
          size: taille,
          viewPadding: viewPadding,
          padding: viewPadding,
          textScaler: TextScaler.linear(echelleTexte),
        ),
        child: ecran,
      ),
    ),
  );
}

/// Toutes les tailles de cible tactile d'un type de widget respectent le
/// plancher de 44 dp de `DESIGN.md § Cibles tactiles`.
void verifierCiblesTactiles(
  WidgetTester tester,
  Finder finder, {
  double plancher = 44,
}) {
  final elements = finder.evaluate();
  expect(elements, isNotEmpty, reason: 'Aucune cible trouvée pour $finder.');

  for (var index = 0; index < elements.length; index++) {
    final taille = tester.getSize(finder.at(index));
    expect(
      taille.height,
      greaterThanOrEqualTo(plancher),
      reason: 'Cible $index trop basse : ${taille.height} dp.',
    );
    expect(
      taille.width,
      greaterThanOrEqualTo(plancher),
      reason: 'Cible $index trop étroite : ${taille.width} dp.',
    );
  }
}
