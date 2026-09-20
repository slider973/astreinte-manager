import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dev/presentation/dev_components_screen.dart';
import '../../features/hello/presentation/hello_screen.dart';
import '../env.dart';

/// Chemins et noms de routes de l'application.
///
/// Les deep links des notifications (docs/WORKFLOWS.md, section 8) viendront
/// s'ajouter ici au fil des tickets. Toujours naviguer par nom
/// (`context.goNamed`) pour ne pas dupliquer les chemins.
abstract final class AppRoutes {
  static const String home = '/';
  static const String homeName = 'home';

  /// Catalogue des composants du système de design (ticket 004).
  ///
  /// **Absent des builds de production** : la route n'est pas déclarée quand
  /// `Env.appEnv` vaut `prod`, donc l'URL renvoie l'écran d'erreur du routeur
  /// au lieu d'exposer un outil interne.
  static const String devComponents = '/dev/components';
  static const String devComponentsName = 'devComponents';
}

/// Routeur de l'application, exposé via Riverpod pour pouvoir dépendre
/// plus tard de l'état d'authentification (redirections) et, dès maintenant,
/// de l'environnement de compilation.
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  final env = ref.watch(envProvider);

  return GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        name: AppRoutes.homeName,
        builder: (context, state) => const HelloScreen(),
      ),
      if (env.isDev)
        GoRoute(
          path: AppRoutes.devComponents,
          name: AppRoutes.devComponentsName,
          builder: (context, state) => const DevComponentsScreen(),
        ),
    ],
  );
});
