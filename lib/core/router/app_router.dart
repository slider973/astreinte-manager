import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/hello/presentation/hello_screen.dart';

/// Chemins et noms de routes de l'application.
///
/// Les deep links des notifications (docs/WORKFLOWS.md, section 8) viendront
/// s'ajouter ici au fil des tickets. Toujours naviguer par nom
/// (`context.goNamed`) pour ne pas dupliquer les chemins.
abstract final class AppRoutes {
  static const String home = '/';
  static const String homeName = 'home';
}

/// Routeur de l'application, exposé via Riverpod pour pouvoir dépendre
/// plus tard de l'état d'authentification (redirections).
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        name: AppRoutes.homeName,
        builder: (context, state) => const HelloScreen(),
      ),
    ],
  ),
);
