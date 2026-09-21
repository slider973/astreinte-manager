import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/abonnement/domain/abonnement_providers.dart';
import '../../features/abonnement/presentation/abonnement_screen.dart';
import '../../features/accueil/presentation/accueil_screen.dart';
import '../../features/auth/presentation/aucune_caserne_screen.dart';
import '../../features/auth/presentation/code_screen.dart';
import '../../features/auth/presentation/connexion_screen.dart';
import '../../features/demarrage/presentation/configuration_absente_screen.dart';
import '../../features/demarrage/presentation/demarrage_screen.dart';
import '../../features/dev/presentation/dev_components_screen.dart';
import '../../features/invitation/presentation/invitation_screen.dart';
import '../../features/legal/presentation/document_legal_screen.dart';
import '../../features/membres/presentation/inviter_screen.dart';
import '../../features/membres/presentation/membres_screen.dart';
import '../../features/notifications/domain/destination_push.dart';
import '../../features/notifications/presentation/activation_notifications_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/onboarding/presentation/aide_installation_screen.dart';
import '../../features/onboarding/presentation/guide_screen.dart';
import '../../features/onboarding/presentation/installation_screen.dart';
import '../../features/onboarding/presentation/profil_accueil_screen.dart';
import '../../features/parametres/presentation/parametres_screen.dart';
import '../../features/periodes/presentation/periodes_screen.dart';
import '../../features/planning/presentation/matrice_screen.dart';
import '../../features/planning/presentation/suivi_screen.dart';
import '../../features/superadmin/domain/superadmin_providers.dart';
import '../../features/superadmin/presentation/superadmin_screen.dart';
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

  /// **La vue centrale de l'admin** : la matrice des disponibilités du mois
  /// (ticket 016). C'est l'écran d'atterrissage de la destination « Admin » —
  /// écart assumé à `DESIGN.md § Navigation`, qui la faisait tomber sur
  /// l'annuaire : la destination doit tomber sur le travail. Les trois autres
  /// écrans restent à un clic dans la barre d'application.
  ///
  /// Le mois voyage en `?mois=AAAA-MM` ([parametreMois]).
  static const String planningAdmin = '/admin/planning';
  static const String planningAdminName = 'planningAdmin';

  /// **Le suivi d'un planning publié** (ticket 019) : progression, réponses,
  /// retardataires. Cinquième écran de la destination « Admin », au même
  /// niveau que les autres — aucune destination de navigation ne s'ajoute.
  ///
  /// C'est la cible interne du lien public [lienSuiviAdmin]. Le mois voyage en
  /// `?mois=AAAA-MM` ([parametreMois]).
  static const String suivi = '/admin/suivi';
  static const String suiviName = 'suiviPlanning';

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

  /// L'abonnement de la caserne (ticket 029). Écran de la destination
  /// « Admin », au même niveau que « Membres », « Paramètres » et
  /// « Périodes » : **aucune destination de navigation ne s'ajoute**
  /// (`DESIGN.md § Navigation` en fixe cinq, un admin les a toutes).
  ///
  /// C'est aussi l'adresse de retour du prestataire de paiement, qui y ajoute
  /// `?paiement=ok` ou `?paiement=annule` ([parametrePaiement]). Le paramètre
  /// déclenche une **relecture**, jamais un changement d'état : c'est le
  /// webhook qui écrit, et il peut arriver après le navigateur.
  static const String abonnement = '/admin/abonnement';
  static const String abonnementName = 'abonnementCaserne';
  static const String parametrePaiement = 'paiement';
  static const String paiementReussi = 'ok';
  static const String paiementAnnule = 'annule';

  /// Les mois de saisie de la caserne (ticket 014). Troisième écran de la
  /// destination « Admin », au même niveau que « Membres » et « Paramètres » :
  /// on y va et on en revient par la barre d'application, sans empiler.
  static const String periodes = '/admin/periodes';
  static const String periodesName = 'periodesCaserne';

  /// L'écran de l'éditeur du produit (ticket 031) : la liste des casernes.
  ///
  /// **Pas une destination de navigation**, et pas un préfixe d'administration
  /// de caserne : l'éditeur n'est membre d'aucune caserne, il n'a pas de barre
  /// de navigation, il a une URL. La garde est dans `redirectionAuth`, comme
  /// pour `/admin` — mais elle laisse passer un compte **sans caserne**, ce qui
  /// est le cas nominal de l'éditeur.
  static const String superAdmin = '/superadmin';
  static const String superAdminName = 'superAdmin';

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

  /// `/install` — l'aide à l'ajout à l'écran d'accueil (ticket 032).
  ///
  /// **Joignable sans compte, et même sans configuration Supabase.** C'est
  /// l'adresse qu'un chef de centre donne au téléphone ou punaise dans la
  /// salle de garde : elle doit rendre trois gestes à quelqu'un qui n'a encore
  /// rien. Elle est courte exprès — `/bienvenue/installation` est l'étape du
  /// parcours d'accueil, pas une adresse qu'on dicte.
  static const String aideInstallation = '/install';
  static const String aideInstallationName = 'aideInstallation';

  // --- Les deux pages légales (ticket 034) ---------------------------------

  /// Politique de confidentialité et mentions légales.
  ///
  /// **Joignables dans tous les états d'authentification**, comme le lien
  /// d'invitation : une politique de confidentialité doit se lire sans compte —
  /// par une mairie, par un candidat à l'invitation, par qui a reçu un
  /// courriel — et elle doit avoir une URL qu'on colle dans une délibération
  /// (`design/034-rgpd-export.md § 5.3`). La garde est dans `redirectionAuth`,
  /// et ce préfixe **est** la règle.
  static const String prefixeLegal = '/legal';
  static const String confidentialite = '$prefixeLegal/confidentialite';
  static const String confidentialiteName = 'confidentialite';
  static const String mentions = '$prefixeLegal/mentions';
  static const String mentionsName = 'mentionsLegales';

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
        // `/install` n'a besoin d'aucune donnée : elle explique un geste du
        // navigateur. Elle reste donc joignable sur un déploiement dont la
        // base n'est pas encore branchée — c'est même le premier moment où
        // elle sert (ticket 032).
        return state.matchedLocation == AppRoutes.configuration ||
                state.matchedLocation == AppRoutes.aideInstallation
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

      // La garde, pour un chemin donné. Elle sert deux fois : sur
      // l'emplacement courant, et sur la destination qu'on s'apprête à
      // rejouer — c'est la seconde qui compte, voir plus bas.
      String? garde(String chemin) => redirectionAuth(
        etat: etat,
        chemin: chemin,
        outilsDevAutorises: env.isDev,
        estAdmin: ref.read(appartenanceCouranteProvider)?.estAdmin ?? false,
        // `null` tant que la réponse n'est pas là : la garde attend plutôt que
        // de rediriger sur une supposition (`auth_redirection.dart`).
        estSuperAdmin: ref.read(estSuperAdminProvider).value,
        cheminInvitationEnAttente: jeton == null
            ? null
            : AppRoutes.cheminInvitation(jeton),
      );

      final redirection = garde(state.matchedLocation);
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
        // **On ne rejoue que ce que la garde accepte.** Une destination
        // refusée y mènerait, la garde en reviendrait aussitôt, et
        // `go_router` verrait passer deux fois le même emplacement dans une
        // même résolution : c'est une boucle de redirection, et elle laisse
        // l'application sans écran du tout — écran blanc, pas écran d'accueil.
        //
        // Vu dans Chrome sur `/superadmin` ouvert à froid par un compte
        // ordinaire (ticket 031). Le même piège attendait `/admin/membres`
        // ouvert à froid par un simple membre : ce n'est pas un défaut de ce
        // ticket, c'est un défaut qu'il a fait apparaître.
        if (reprise != null && garde(Uri.parse(reprise).path) == null) {
          return reprise;
        }
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
        path: AppRoutes.planningAdmin,
        name: AppRoutes.planningAdminName,
        builder: (context, state) => MatriceScreen(
          mois: state.uri.queryParameters[AppRoutes.parametreMois],
        ),
      ),
      GoRoute(
        path: AppRoutes.suivi,
        name: AppRoutes.suiviName,
        builder: (context, state) => SuiviScreen(
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
        path: AppRoutes.abonnement,
        name: AppRoutes.abonnementName,
        builder: (context, state) => AbonnementScreen(
          retour: retourPaiement(
            state.uri.queryParameters[AppRoutes.parametrePaiement],
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.superAdmin,
        name: AppRoutes.superAdminName,
        builder: (context, state) => const SuperAdminScreen(),
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
                admin:
                    ref.read(appartenanceCouranteProvider)?.estAdmin ?? false,
              ) ??
              AppRoutes.accueil,
        ),
      GoRoute(
        path: AppRoutes.aideInstallation,
        name: AppRoutes.aideInstallationName,
        builder: (context, state) => const AideInstallationScreen(),
      ),
      GoRoute(
        path: AppRoutes.confidentialite,
        name: AppRoutes.confidentialiteName,
        builder: (context, state) =>
            const DocumentLegalScreen.confidentialite(),
      ),
      GoRoute(
        path: AppRoutes.mentions,
        name: AppRoutes.mentionsName,
        builder: (context, state) => const DocumentLegalScreen.mentions(),
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

/// Le retour du prestataire de paiement, lu dans `?paiement=`.
///
/// Toute autre valeur vaut « pas de retour » : le paramètre vient du dehors et
/// n'a aucune autorité. Il ne fait que demander une relecture.
RetourPaiement? retourPaiement(String? valeur) => switch (valeur) {
  AppRoutes.paiementReussi => RetourPaiement.reussi,
  AppRoutes.paiementAnnule => RetourPaiement.annule,
  _ => null,
};

/// Pont entre Riverpod et `go_router` : un [Listenable] qui se déclenche à
/// chaque changement de l'état d'authentification, **et** à l'arrivée du droit
/// de l'éditeur du produit.
///
/// Le second abonnement n'est pas décoratif : `estSuperAdminProvider` répond
/// après coup, et sans personne pour l'écouter la redirection resterait sur la
/// décision prise avec un statut inconnu.
class _RafraichissementRouteur extends ChangeNotifier {
  _RafraichissementRouteur(Ref ref) {
    _abonnement = ref.listen<EtatAuth>(
      etatAuthProvider,
      (_, _) => notifyListeners(),
    );
    _editeur = ref.listen<AsyncValue<bool>>(
      estSuperAdminProvider,
      (_, _) => notifyListeners(),
    );
  }

  late final ProviderSubscription<EtatAuth> _abonnement;
  late final ProviderSubscription<AsyncValue<bool>> _editeur;

  @override
  void dispose() {
    _abonnement.close();
    _editeur.close();
    super.dispose();
  }
}
