import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/app_strings.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// Racine de l'application : les deux thèmes du système de design (ticket 004)
/// et la navigation go_router.
///
/// Le mode de thème suit le système : `MaterialApp.themeMode` vaut déjà
/// `ThemeMode.system` par défaut, et l'écrire serait un argument redondant que
/// `flutter analyze` refuse. Le choix manuel du thème arrive au ticket 007.
/// Le thème clair reste celui par défaut du système d'exploitation, parce que
/// la scène d'usage dominante est le plein soleil (`DESIGN.md § Overview`).
class AstreinteApp extends ConsumerWidget {
  const AstreinteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: AppStrings.appTitle,
      theme: AppTheme.clair,
      darkTheme: AppTheme.sombre,
      routerConfig: router,
    );
  }
}
