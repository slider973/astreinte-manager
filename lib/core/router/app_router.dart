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
import '../../features/invitation/presentation/invitation_screen.dart';
import '../../features/membres/presentation/inviter_screen.dart';
import '../../features/membres/presentation/membres_screen.dart';
import '../../features/notifications/domain/destination_push.dart';
import '../../features/notifications/presentation/activation_notifications_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/onboarding/presentation/guide_screen.dart';
import '../../features/onboarding/presentation/installation_screen.dart';
import '../../features/onboarding/presentation/profil_accueil_screen.dart';
import '../../features/parametres/presentation/parametres_screen.dart';
import '../../features/periodes/presentation/periodes_screen.dart';
import '../env.dart';
import '../session/email.dart';
import '../session/etat_auth.dart';
import '../session/jeton_invitation.dart';
import '../session/session_providers.dart';
import '../supabase/supabase_bootstrap.dart';
import 'auth_redirection.dart';
import 'destination_initiale.dart';

/// Chemins et noms de routes de l'application.
///
/// Les deep links des notifications (`docs/WORKFLOWS.md § 8`) sont déclarés
/// ici depuis le ticket 024 : ce sont des **liens publics**, ils partent dans
/// des notifications et doivent s'ouvrir même si l'écran qu'ils visent n'a pas
/// encore sa route à lui. Chacun se contente de rediriger vers l'écran qui
/// existe, via `destinationInterne` (`features/notifications/domain`).
/// Toujours naviguer par nom (`context.goNamed`) pour ne pas dupliquer les
/// chemins.
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

  /// L'onglet à ouvrir sur l'accueil, quand on y revient depuis un écran de
  /// premier niveau qui a sa propre route (« Admin »).
  static const String parametreOnglet = 'onglet';

  /// Le mois affiché par « Mon mois », au format `AAAA-MM` (ticket 011).
  ///
  /// L'URL porte l'état : le retour du navigateur et le geste retour iOS
  /// ramènent au mois précédemment consulté, jamais à un état perdu. La route
  /// dédiée `/mois` annoncée dans `DESIGN.md § Navigation` attend que la
  /// coquille d'accueil éclate en routes.
  static const String parametreMois = 'mois';

  /// Tout ce qui est réservé aux administrateurs de la caserne. La garde est
  /// dans `redirectionAuth` : ce préfixe **est** la règle.
  static const String prefixeAdmin = '/admin';

  /// Administration de la caserne : les membres et les invitations
  /// (ticket 006).
  static const String membres = '/admin/membres';
  static const String membresName = 'membres';

  /// Le formulaire d'invitation, enfant de l'écran des membres : le retour du
  /// navigateur ramène à la liste.
  static const String inviterChemin = 'inviter';
  static const String inviterName = 'inviterMembres';

  /// Les réglages de la caserne (ticket 010). Second écran de la destination
  /// « Admin », pas un enfant de « Membres » : on y va et on en revient par la
  /// barre d'application, sans empiler.
  static const String parametres = '/admin/parametres';
  static const String parametresName = 'parametresCaserne';

  /// Les mois de saisie de la caserne (ticket 014). Troisième écran de la
  /// destination « Admin », au même niveau que « Membres » et « Paramètres » :
  /// on y va et on en revient par la barre d'application, sans empiler.
  static const String periodes = '/admin/periodes';
  static const String periodesName = 'periodesCaserne';

  /// Le lien reçu par courriel. **Il ne porte que le jeton** : ni l'adresse
  /// invitée, ni le nom de la caserne (`supabase/functions/README.md`).
  static const String invitation = '/invite/:$parametreJeton';
  static const String invitationName = 'invitation';
  static const String parametreJeton = 'jeton';
  static const String prefixeInvitation = '/invite/';

  /// Le chemin d'un jeton donné, tel que le construit l'Edge Function.
  static String cheminInvitation(String jeton) => '$prefixeInvitation$jeton';

  /// L'accueil d'un nouveau membre : profil, guide, aide à l'installation,
  /// puis la proposition d'activer les notifications (ticket 024). Dans cet
  /// ordre, et jamais au premier lancement.
  static const String prefixeBienvenue = '/bienvenue';
  static const String profilAccueil = '$prefixeBienvenue/profil';
  static const String profilAccueilName = 'profilAccueil';
  static const String guide = '$prefixeBienvenue/guide';
  static const String guideName = 'guideAccueil';
  static const String installation = '$prefixeBienvenue/installation';
  static const String installationName = 'installation';
  static const String activationNotifications =
      '$prefixeBienvenue/notifications';
  static const String activationNotificationsName = 'activationNotifications';

  /// Le centre de notifications (ticket 026).
  ///
  /// **Pas une destination de navigation** : `DESIGN.md § Navigation` en fixe
  /// cinq au maximum et un admin les a toutes. On y va par la cloche de la
  /// barre d'application, et le retour du navigateur ramène d'où l'on vient.
  static const String notifications = '/notifications';
  static const String notificationsName = 'notifications';

  // --- Liens publics des notifications (docs/WORKFLOWS.md § 8) -------------

  /// Le mois visé par un lien de notification, au format `AAAA-MM`.
  static const String parametrePeriode = 'periode';

  /// `/proposals` — les propositions en attente.
  static const String lienPropositions = '/proposals';
  static const String lienPropositionsName = 'lienPropositions';

  /// `/schedule/<period>` — le planning de la caserne.
  static const String lienPlanning = '/schedule/:$parametrePeriode';
  static const String lienPlanningName = 'lienPlanning';

  /// `/admin/schedule/<period>` — le suivi côté admin.
  static const String lienSuiviAdmin = '/admin/schedule/:$parametrePeriode';
  static const String lienSuiviAdminName = 'lienSuiviAdmin';

  /// `/availability/<period>` — la saisie du mois.
  static const String lienSaisie = '/availability/:$parametrePeriode';
  static const String lienSaisieName = 'lienSaisie';

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

  final destinationInitiale = ref.watch(destinationInitialeProvider);

  final routeur = GoRouter(
    initialLocation: AppRoutes.demarrage,
    refreshListenable: rafraichissement,
    redirect: (context, state) {
      if (!demarrage.estPret) {
        return state.matchedLocation == AppRoutes.configuration
            ? null
            : AppRoutes.configuration;
      }
      final jeton = ref.read(jetonInvitationProvider);
      final etat = ref.read(etatAuthProvider);

      // Une session qui se ferme efface la destination en attente. Le cas
      // n'est pas théorique : sur un téléphone prêté ou dans un véhicule
      // partagé (`core/session/deconnexion.dart`), la personne suivante
      // atterrirait sur l'écran que la précédente venait de quitter.
      if (etat == EtatAuth.deconnecte) destinationInitiale.oublier();

      final redirection = redirectionAuth(
        etat: etat,
        chemin: state.matchedLocation,
        outilsDevAutorises: env.isDev,
        estAdmin: ref.read(appartenanceCouranteProvider)?.estAdmin ?? false,
        cheminInvitationEnAttente: jeton == null
            ? null
            : AppRoutes.cheminInvitation(jeton),
      );
      if (redirection != null) {
        // **Uniquement pendant la restauration à froid.** C'est le seul moment
        // où l'emplacement demandé vient du dehors — une URL ouverte, une
        // notification touchée — et non d'un écran que l'application affichait
        // déjà. Mémoriser à la déconnexion rejouerait l'écran de la personne
        // précédente pour la suivante.
        if (etat == EtatAuth.chargement) {
          destinationInitiale.memoriser(state.uri.toString());
        }
        return redirection;
      }

      // L'écran du code n'existe que pour une adresse : sans elle, il annonce
      // « un code part vers  » et vérifie dans le vide. Le contrôle est ici et
      // non dans `redirectionAuth`, qui ne voit que le chemin : l'adresse est
      // dans la chaîne de requête.
      if (state.matchedLocation == AppRoutes.code &&
          !emailValide(
            state.uri.queryParameters[AppRoutes.parametreEmail] ?? '',
          )) {
        return AppRoutes.connexion;
      }

      // La session est prête et l'emplacement courant est permis : si une
      // destination attendait, c'est le moment d'y aller.
      if (etat == EtatAuth.connecte) {
        final reprise = destinationInitiale.reprendre(state.uri.toString());
        if (reprise != null) return reprise;
      }

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.accueil,
        name: AppRoutes.accueilName,
        builder: (context, state) => AccueilScreen(
          ongletInitial:
              int.tryParse(
                state.uri.queryParameters[AppRoutes.parametreOnglet] ?? '',
              ) ??
              0,
          mois: state.uri.queryParameters[AppRoutes.parametreMois],
        ),
      ),
      GoRoute(
        path: AppRoutes.membres,
        name: AppRoutes.membresName,
        builder: (context, state) => const MembresScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.inviterChemin,
            name: AppRoutes.inviterName,
            builder: (context, state) => const InviterScreen(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.parametres,
        name: AppRoutes.parametresName,
        builder: (context, state) => const ParametresScreen(),
      ),
      GoRoute(
        path: AppRoutes.periodes,
        name: AppRoutes.periodesName,
        builder: (context, state) => const PeriodesScreen(),
      ),
      GoRoute(
        path: AppRoutes.invitation,
        name: AppRoutes.invitationName,
        builder: (context, state) => InvitationScreen(
          jeton: state.pathParameters[AppRoutes.parametreJeton] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.profilAccueil,
        name: AppRoutes.profilAccueilName,
        builder: (context, state) => const ProfilAccueilScreen(),
      ),
      GoRoute(
        path: AppRoutes.guide,
        name: AppRoutes.guideName,
        builder: (context, state) => const GuideScreen(),
      ),
      GoRoute(
        path: AppRoutes.installation,
        name: AppRoutes.installationName,
        builder: (context, state) => const InstallationScreen(),
      ),
      GoRoute(
        path: AppRoutes.activationNotifications,
        name: AppRoutes.activationNotificationsName,
        builder: (context, state) => const ActivationNotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        name: AppRoutes.notificationsName,
        builder: (context, state) => const NotificationsScreen(),
      ),

      // Les quatre liens publics des notifications. Ils n'ont pas d'écran à
      // eux : ils traduisent et redirigent. Le lien reste stable quand les
      // écrans bougent (tickets 019, 021, 023).
      for (final chemin in <String, String>{
        AppRoutes.lienPropositions: AppRoutes.lienPropositionsName,
        AppRoutes.lienPlanning: AppRoutes.lienPlanningName,
        AppRoutes.lienSuiviAdmin: AppRoutes.lienSuiviAdminName,
        AppRoutes.lienSaisie: AppRoutes.lienSaisieName,
      }.entries)
        GoRoute(
          path: chemin.key,
          name: chemin.value,
          redirect: (context, state) =>
              destinationInterne(
                state.uri.path,
                admin: ref.read(appartenanceCouranteProvider)?.estAdmin ??
                    false,
              ) ??
              AppRoutes.accueil,
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
