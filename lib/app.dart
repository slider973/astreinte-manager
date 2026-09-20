import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/app_strings.dart';
import 'core/router/app_router.dart';

/// Racine de l'application : thème Material 3 par défaut (le thème métier
/// arrive au ticket 004) et navigation go_router.
class AstreinteApp extends ConsumerWidget {
  const AstreinteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: AppStrings.appTitle,
      routerConfig: router,
    );
  }
}
