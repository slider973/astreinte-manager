import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accueil/presentation/accueil_screen.dart';
import '../../features/auth/presentation/aucune_caserne_screen.dart';
import '../../features/auth/presentation/code_screen.dart';
import '../../features/auth/presentation/connexion_screen.dart';
import '../../features/demarrage/presentation/configuration_absente_screen.dart';
import '../../features/demarrage/presentation/demarrage_screen.dart';
import '../../features/dev/presentation/dev_components_screen.dart';
import '../env.dart';
import '../session/etat_auth.dart';
import '../session/session_providers.dart';
import '../supabase/supabase_bootstrap.dart';
import 'auth_redirection.dart';

/// Chemins et noms de routes de l'application.
///
/// Les deep links des notifications (docs/WORKFLOWS.md, section 8) viendront
/// s'ajouter ici au fil des tickets. Toujours naviguer par nom
/// (`context.goNamed`) pour ne pas dupliquer les chemins.
abstract final class AppRoutes {
  /// L'accueil, une fois connecté et rattaché à une caserne.
  static const String accueil = '/';
  static const String accueilName = 'accueil';

  /// Écran d'attente : session en cours de restauration.
  static const String demarrage = '/demarrage';
  static const String demarrageName = 'demarrage';

  /// Saisie de l'adresse e-mail.
  static const String connexion = '/connexion';
  static const String connexionName = 'connexion';

  /// Saisie du code à six chiffres. L'adresse voyage en paramètre de requête
  /// [parametreEmail] : le retour du navigateur ramène à l'étape précédente
  /// sans état local perdu.
  static const String code = '/connexion/code';
  static const String codeName = 'connexionCode';
  static const String parametreEmail = 'email';

  /// Connecté, mais sans appartenance active à une caserne.
  static const String aucuneCaserne = '/aucune-caserne';
  static const String aucuneCaserneName = 'aucuneCaserne';

  /// L'app n'a pas reçu son URL Supabase à la compilation.
  static const String configuration = '/configuration';
  static const String configurationName = 'configuration';

  /// Catalogue des composants du système de design (ticket 004).
  ///
  /// **Absent des builds de production** : la route n'est pas déclarée quand
  /// `Env.appEnv` vaut `prod`, donc l'URL renvoie l'écran d'erreur du routeur
  /// au lieu d'exposer un outil interne.
  static const String devComponents = '/dev/components';
  static const String devComponentsName = 'devComponents';
}

/// Routeur de l'application.
///
/// La redirection est **réactive** : [_RafraichissementRouteur] écoute
/// [etatAuthProvider] et notifie `go_router` à chaque changement. Le routeur
/// lui-même n'est construit qu'une fois — le reconstruire à chaque connexion
/// remettrait la pile de navigation à zéro.
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  final env = ref.watch(envProvider);
  final demarrage = ref.watch(supabaseDemarrageProvider);

  final rafraichissement = _RafraichissementRouteur(ref);
  ref.onDispose(rafraichissement.dispose);

  final routeur = GoRouter(
    initialLocation: AppRoutes.demarrage,
    refreshListenable: rafraichissement,
    redirect: (context, state) {
      if (!demarrage.estPret) {
        return state.matchedLocation == AppRoutes.configuration
            ? null
            : AppRoutes.configuration;
      }
      return redirectionAuth(
        etat: ref.read(etatAuthProvider),
        chemin: state.matchedLocation,
        outilsDevAutorises: env.isDev,
      );
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.accueil,
        name: AppRoutes.accueilName,
        builder: (context, state) => const AccueilScreen(),
      ),
      GoRoute(
        path: AppRoutes.demarrage,
        name: AppRoutes.demarrageName,
        builder: (context, state) => const DemarrageScreen(),
      ),
      GoRoute(
        path: AppRoutes.connexion,
        name: AppRoutes.connexionName,
        builder: (context, state) => const ConnexionScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'code',
            name: AppRoutes.codeName,
            builder: (context, state) => CodeScreen(
              email: state.uri.queryParameters[AppRoutes.parametreEmail] ?? '',
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.aucuneCaserne,
        name: AppRoutes.aucuneCaserneName,
        builder: (context, state) => const AucuneCaserneScreen(),
      ),
      GoRoute(
        path: AppRoutes.configuration,
        name: AppRoutes.configurationName,
        builder: (context, state) => const ConfigurationAbsenteScreen(),
      ),
      if (env.isDev)
        GoRoute(
          path: AppRoutes.devComponents,
          name: AppRoutes.devComponentsName,
          builder: (context, state) => const DevComponentsScreen(),
        ),
    ],
  );

  ref.onDispose(routeur.dispose);
  return routeur;
});

/// Pont entre Riverpod et `go_router` : un [Listenable] qui se déclenche à
/// chaque changement de l'état d'authentification.
class _RafraichissementRouteur extends ChangeNotifier {
  _RafraichissementRouteur(Ref ref) {
    _abonnement = ref.listen<EtatAuth>(
      etatAuthProvider,
      (_, _) => notifyListeners(),
    );
  }

  late final ProviderSubscription<EtatAuth> _abonnement;

  @override
  void dispose() {
    _abonnement.close();
    super.dispose();
  }
}
