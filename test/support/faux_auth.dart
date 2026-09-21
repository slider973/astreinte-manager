import 'dart:async';

import 'package:astreinte_sp/app.dart';
import 'package:astreinte_sp/core/caserne/caserne_providers.dart';
import 'package:astreinte_sp/core/caserne/caserne_repository.dart';
import 'package:astreinte_sp/core/env.dart';
import 'package:astreinte_sp/core/firebase/firebase_bootstrap.dart';
import 'package:astreinte_sp/core/plateforme/contexte_plateforme.dart';
import 'package:astreinte_sp/core/plateforme/ouverture_externe.dart';
import 'package:astreinte_sp/core/plateforme/selection_fichier.dart';
import 'package:astreinte_sp/core/plateforme/telechargement.dart';
import 'package:astreinte_sp/core/preferences/reperes_locaux.dart';
import 'package:astreinte_sp/core/reseau/connectivite.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/appartenances_locales.dart';
import 'package:astreinte_sp/core/session/auth_erreur.dart';
import 'package:astreinte_sp/core/session/auth_repository.dart';
import 'package:astreinte_sp/core/session/caserne_choisie.dart';
import 'package:astreinte_sp/core/session/membership_repository.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/core/session/session_utilisateur.dart';
import 'package:astreinte_sp/core/supabase/supabase_bootstrap.dart';
import 'package:astreinte_sp/features/abonnement/data/abonnement_repository.dart';
import 'package:astreinte_sp/features/abonnement/domain/abonnement_providers.dart';
import 'package:astreinte_sp/features/astreintes/data/astreintes_repository.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_astreintes.dart';
import 'package:astreinte_sp/features/astreintes/data/cache_planning_caserne.dart';
import 'package:astreinte_sp/features/astreintes/data/planning_caserne_repository.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreintes_providers.dart';
import 'package:astreinte_sp/features/astreintes/domain/planning_caserne_providers.dart';
import 'package:astreinte_sp/features/dispos/data/dispos_repository.dart';
import 'package:astreinte_sp/features/dispos/data/file_locale.dart';
import 'package:astreinte_sp/features/dispos/domain/dispos_providers.dart';
import 'package:astreinte_sp/features/invitation/data/invitation_repository.dart';
import 'package:astreinte_sp/features/invitation/domain/invitation_providers.dart';
import 'package:astreinte_sp/features/membres/data/membres_repository.dart';
import 'package:astreinte_sp/features/membres/domain/membres_providers.dart';
import 'package:astreinte_sp/features/notifications/data/jeton_local.dart';
import 'package:astreinte_sp/features/notifications/data/notifications_repository.dart';
import 'package:astreinte_sp/features/notifications/domain/centre_providers.dart';
import 'package:astreinte_sp/features/notifications/domain/notifications_providers.dart';
import 'package:astreinte_sp/features/parametres/data/parametres_repository.dart';
import 'package:astreinte_sp/features/parametres/domain/parametres_providers.dart';
import 'package:astreinte_sp/features/periodes/data/periodes_repository.dart';
import 'package:astreinte_sp/features/periodes/domain/periodes_providers.dart';
import 'package:astreinte_sp/features/planning/data/matrice_repository.dart';
import 'package:astreinte_sp/features/planning/data/planning_repository.dart';
import 'package:astreinte_sp/features/planning/data/suivi_repository.dart';
import 'package:astreinte_sp/features/planning/domain/matrice_providers.dart';
import 'package:astreinte_sp/features/planning/domain/planning_providers.dart';
import 'package:astreinte_sp/features/planning/domain/suivi_providers.dart';
import 'package:astreinte_sp/features/profil/data/profil_repository.dart';
import 'package:astreinte_sp/features/profil/domain/calendrier_providers.dart';
import 'package:astreinte_sp/features/profil/domain/export_providers.dart';
import 'package:astreinte_sp/features/profil/domain/profil_providers.dart';
import 'package:astreinte_sp/features/propositions/data/propositions_repository.dart';
import 'package:astreinte_sp/features/propositions/domain/propositions_providers.dart';
import 'package:astreinte_sp/features/superadmin/data/superadmin_repository.dart';
import 'package:astreinte_sp/features/superadmin/domain/superadmin_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'faux_abonnement.dart';
import 'faux_astreintes.dart';
import 'faux_calendrier.dart';
import 'faux_caserne.dart';
import 'faux_dispos.dart';
import 'faux_export.dart';
import 'faux_fichier.dart';
import 'faux_notifications.dart';
import 'faux_planning.dart';
import 'faux_planning_caserne.dart';
import 'faux_profil.dart';
import 'faux_propositions.dart';
import 'faux_push.dart';
import 'faux_suivi.dart';
import 'faux_superadmin.dart';

/// Environnement de test : configuration Supabase présente, mais aucun réseau
/// n'est jamais joint — les dépôts sont faux.
const Env envDeTest = Env.sansPush(
  supabaseUrl: 'http://127.0.0.1:54321',
  supabaseAnonKey: 'cle-anon-de-test',
  appEnv: Env.devEnv,
);

const SessionUtilisateur sessionMembre = SessionUtilisateur(
  userId: 'aaaaaaaa-0000-4000-8000-000000000101',
  email: 'membre1@caserne-a.test',
);

const Appartenance appartenanceMembre = Appartenance(
  id: 'm-1',
  stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Saint-Martin',
  role: RoleMembre.membre,
  statut: StatutMembre.actif,
  nomAffiche: 'Marie L.',
);

const Appartenance appartenanceDesactivee = Appartenance(
  id: 'm-2',
  stationId: 'aaaaaaaa-0000-4000-8000-000000000001',
  nomCaserne: 'CIS Saint-Martin',
  role: RoleMembre.membre,
  statut: StatutMembre.desactive,
);

/// Un [AuthRepository] sans réseau : il compte les appels et rend ce qu'on lui
/// a demandé de rendre.
class FauxAuthRepository implements AuthRepository {
  FauxAuthRepository({
    SessionUtilisateur? session,
    this.erreurEnvoi,
    this.erreurVerification,
    this.enAttente = false,
  }) : _session = session;

  /// Le flux ne dit rien tant que [ouvrirSession] n'a pas été appelée.
  ///
  /// C'est le **démarrage à froid** : le SDK Supabase relit son stockage local
  /// et l'application reste en `EtatAuth.chargement` quelques instants. Sans
  /// cette attente, un faux répond tout de suite et aucun test ne peut voir
  /// l'écran de restauration ni ce qui s'y joue (ticket 039).
  bool enAttente;

  /// Erreur levée par [envoyerCode], ou `null` pour réussir.
  AuthErreur? erreurEnvoi;

  /// Erreur levée par [verifierCode], ou `null` pour ouvrir une session.
  AuthErreur? erreurVerification;

  /// Erreur levée par [seDeconnecter], ou `null` pour fermer la session.
  AuthErreur? erreurDeconnexion;

  final StreamController<SessionUtilisateur?> _controleur =
      StreamController<SessionUtilisateur?>.broadcast();

  SessionUtilisateur? _session;

  final List<String> emailsAppeles = <String>[];
  final List<String> codesAppeles = <String>[];
  int deconnexions = 0;

  @override
  Stream<SessionUtilisateur?> get sessions async* {
    if (!enAttente) yield _session;
    yield* _controleur.stream;
  }

  @override
  SessionUtilisateur? get sessionCourante => _session;

  @override
  Future<void> envoyerCode(String email) async {
    emailsAppeles.add(email);
    final erreur = erreurEnvoi;
    if (erreur != null) throw AuthEchec(erreur);
  }

  @override
  Future<void> verifierCode({
    required String email,
    required String code,
  }) async {
    codesAppeles.add(code);
    final erreur = erreurVerification;
    if (erreur != null) throw AuthEchec(erreur);
    ouvrirSession(
      SessionUtilisateur(userId: sessionMembre.userId, email: email),
    );
  }

  @override
  Future<void> seDeconnecter() async {
    final erreur = erreurDeconnexion;
    if (erreur != null) throw AuthEchec(erreur);
    deconnexions++;
    _session = null;
    _controleur.add(null);
  }

  void ouvrirSession(SessionUtilisateur session) {
    _session = session;
    _controleur.add(session);
  }

  void fermer() => _controleur.close();
}

/// Un [MembershipRepository] sans réseau.
class FauxMembershipRepository implements MembershipRepository {
  FauxMembershipRepository({
    this.appartenances = const <Appartenance>[],
    this.erreur,
    this.suspendue = false,
  });

  List<Appartenance> appartenances;

  /// Erreur levée à la lecture, ou `null`.
  AuthErreur? erreur;

  /// **Une lecture qui ne rend jamais la main.** C'est le réseau des zones
  /// rurales : pas un refus, pas une coupure franche, un trou noir. Elle
  /// distingue « je ne sais pas encore » de « il n'y a rien », et c'est
  /// exactement ce que l'écran doit distinguer aussi.
  final bool suspendue;

  int lectures = 0;

  @override
  Future<List<Appartenance>> mesAppartenances(String userId) async {
    lectures++;
    if (suspendue) return Completer<List<Appartenance>>().future;
    final echec = erreur;
    if (echec != null) throw AuthEchec(echec);
    return appartenances;
  }
}

/// Ce que [monterApp] rend : les faux dépôts de la session.
typedef AppMontee = ({
  FauxAuthRepository auth,
  FauxMembershipRepository memberships,
  FauxMessageriePush push,
  FauxPushTokensRepository jetons,
});

/// Monte l'application entière avec des dépôts faux.
///
/// C'est le routeur réel qui décide de l'écran : les tests vérifient donc la
/// redirection telle qu'elle sera vécue, sans toucher au réseau.
///
/// Les dépôts des fonctionnalités sont facultatifs : un écran qui ne les
/// touche pas n'a pas à les fournir. Le type `Override` de Riverpod 3 n'étant
/// pas exporté, ils sont nommés un par un plutôt que passés en liste.
Future<AppMontee> monterApp(
  WidgetTester tester, {
  SessionUtilisateur? session,
  List<Appartenance> appartenances = const <Appartenance>[],
  AuthErreur? erreurEnvoi,
  AuthErreur? erreurVerification,
  AuthErreur? erreurAppartenances,

  /// La lecture des appartenances ne rend jamais la main : un réseau qui
  /// n'échoue pas, il se tait.
  bool appartenancesSuspendues = false,

  /// Simule un démarrage à froid : la session n'arrive qu'à l'appel de
  /// `faux.auth.ouvrirSession(...)`.
  bool sessionEnAttente = false,
  MembresRepository? membres,
  InvitationRepository? invitations,
  ProfilRepository? profils,
  FauxExportRepository? export,
  FauxTelechargement? telechargement,
  FauxSelecteurFichier? selecteurFichier,
  FauxCalendrierRepository? calendrier,
  FauxPressePapiers? pressePapiers,
  ParametresRepository? parametres,
  AbonnementRepository? abonnement,
  CaserneRepository? caserne,
  FauxOuvertureExterne? ouverture,
  PeriodesRepository? periodes,
  MatriceRepository? matrice,
  PlanningRepository? planning,
  SuiviRepository? suivi,
  PropositionsRepository? propositions,
  AstreintesRepository? astreintes,
  CacheAstreintes? cacheAstreintes,
  PlanningCaserneRepository? planningCaserne,
  CachePlanningCaserne? cachePlanningCaserne,
  DateTime Function()? horloge,
  DisposRepository? dispos,
  FileLocale? fileLocale,
  Connectivite? reseau,
  ReperesLocaux? reperes,
  AppartenancesLocales? appartenancesLocales,
  CaserneChoisieLocale? caserneChoisie,
  ContextePlateforme? plateforme,
  FirebaseDemarrage firebase = FirebaseDemarrage.configurationAbsente,
  FauxMessageriePush? messagerie,
  FauxPushTokensRepository? jetons,
  NotificationsRepository? notifications,
  SuperAdminRepository? superAdmin,
  JetonLocal? jetonLocal,
  Size taille = const Size(390, 844),
  bool stabiliser = true,

  /// L'état du démarrage Supabase. `configurationAbsente` reproduit un
  /// déploiement dont la base n'est pas encore branchée (ticket 032) : le
  /// routeur n'ouvre alors que `/configuration` et `/install`.
  SupabaseDemarrage demarrage = SupabaseDemarrage.pret,
}) async {
  tester.view.physicalSize = taille * tester.view.devicePixelRatio;
  addTearDown(tester.view.reset);

  final auth = FauxAuthRepository(
    session: session,
    erreurEnvoi: erreurEnvoi,
    erreurVerification: erreurVerification,
    enAttente: sessionEnAttente,
  );
  addTearDown(auth.fermer);
  final memberships = FauxMembershipRepository(
    appartenances: appartenances,
    erreur: erreurAppartenances,
    suspendue: appartenancesSuspendues,
  );
  final push = messagerie ?? FauxMessageriePush();
  addTearDown(push.fermer);
  final depotJetons = jetons ?? FauxPushTokensRepository();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        envProvider.overrideWithValue(envDeTest),
        supabaseDemarrageProvider.overrideWithValue(demarrage),
        authRepositoryProvider.overrideWithValue(auth),
        membershipRepositoryProvider.overrideWithValue(memberships),
        if (membres != null)
          membresRepositoryProvider.overrideWithValue(membres),
        if (invitations != null)
          invitationRepositoryProvider.overrideWithValue(invitations),
        // Le profil est lu par le réglage des notifications, présent sur
        // l'onglet « Profil » : sans faux, il toucherait un client Supabase
        // qui n'existe pas en test.
        profilRepositoryProvider.overrideWithValue(
          profils ?? FauxProfilRepository(),
        ),
        // L'export RGPD (ticket 034) est posé sur l'onglet « Profil » et dans
        // la feuille de suppression : sans faux, une touche sur le bouton
        // toucherait un client Supabase qui n'existe pas en test. Et sans faux
        // téléchargement, elle appellerait le navigateur.
        exportRepositoryProvider.overrideWithValue(
          export ?? FauxExportRepository(),
        ),
        telechargementProvider.overrideWithValue(
          (telechargement ?? FauxTelechargement()).call,
        ),
        // L'import d'un fichier de membres (ticket 047) : sans faux, le bouton
        // « Choisir un fichier » appellerait un navigateur qui n'existe pas
        // sous `flutter test`.
        selectionFichierProvider.overrideWithValue(
          (selecteurFichier ?? FauxSelecteurFichier()).call,
        ),
        // L'abonnement calendrier (ticket 028) est posé sur l'onglet
        // « Profil », et son bloc **lit dès qu'il se construit** : sans faux,
        // chaque test de cet onglet toucherait un client Supabase qui n'existe
        // pas. Le presse-papiers, lui, est un canal de plateforme absent sous
        // `flutter test`.
        calendrierRepositoryProvider.overrideWithValue(
          calendrier ?? FauxCalendrierRepository(),
        ),
        pressePapiersProvider.overrideWithValue(
          (pressePapiers ?? FauxPressePapiers()).call,
        ),
        if (parametres != null)
          parametresRepositoryProvider.overrideWithValue(parametres),
        // L'abonnement (ticket 029). Par défaut : aucun compte chez le
        // prestataire de paiement, exactement l'état du projet tant qu'il n'y
        // en a pas — et l'application doit tourner ainsi.
        abonnementRepositoryProvider.overrideWithValue(
          abonnement ?? FauxAbonnementRepository(),
        ),
        // L'état d'abonnement vu par **tous** les écrans qui écrivent
        // (ticket 030). Par défaut : une caserne en essai qui écrit, comme le
        // seed. Sans faux, chaque test toucherait un client Supabase qui
        // n'existe pas en test.
        caserneRepositoryProvider.overrideWithValue(
          caserne ?? FauxCaserneRepository(),
        ),
        // Les deux paliers du bandeau d'essai se comptent en jours : sans
        // horloge figée, « il reste 3 jours » dépendrait du jour du test.
        horlogeCaserneProvider.overrideWithValue(
          horloge ?? () => maintenantTest,
        ),
        ouvertureExterneProvider.overrideWithValue(
          (ouverture ?? FauxOuvertureExterne()).call,
        ),
        // L'écran d'abonnement compte des jours d'essai : sans horloge figée,
        // « il reste 12 jours » dépendrait du jour où le test tourne.
        horlogeAbonnementProvider.overrideWithValue(
          horloge ?? () => maintenantTest,
        ),
        if (periodes != null)
          periodesRepositoryProvider.overrideWithValue(periodes),
        if (matrice != null)
          matriceRepositoryProvider.overrideWithValue(matrice),
        // L'écran d'administration lit toujours le planning du mois : sans
        // faux, il toucherait un client Supabase qui n'existe pas en test.
        planningRepositoryProvider.overrideWithValue(
          planning ?? FauxPlanningRepository(),
        ),
        // Le suivi (ticket 019) est lu par l'écran de suivi et par le bouton
        // « Publier » de la matrice : sans faux, les deux toucheraient un
        // client Supabase qui n'existe pas en test.
        suiviRepositoryProvider.overrideWithValue(
          suivi ?? FauxSuiviRepository(),
        ),
        // La pastille des propositions (ticket 021) est construite par la
        // coquille d'accueil, donc lue par **tous** les écrans : sans faux,
        // chaque test toucherait un client Supabase qui n'existe pas en test.
        propositionsRepositoryProvider.overrideWithValue(
          propositions ?? FauxPropositionsRepository(),
        ),
        // « Mes astreintes » (ticket 027) vit sur l'onglet 2, et son
        // contrôleur n'est pas auto-disposé : sans faux, tout test qui passe
        // par la coquille toucherait un client Supabase qui n'existe pas.
        astreintesRepositoryProvider.overrideWithValue(
          astreintes ?? FauxAstreintesRepository(),
        ),
        // Le cache local passe par `shared_preferences` : sans faux, chaque
        // test attendrait un canal de plateforme qui ne répond jamais.
        cacheAstreintesProvider.overrideWithValue(
          cacheAstreintes ?? CacheAstreintesMemoire(),
        ),
        // « La caserne » (ticket 023) est la seconde portée du même écran, et
        // son cache est effacé par **toute** déconnexion : sans faux, chaque
        // test de déconnexion attendrait un canal de plateforme qui ne répond
        // jamais.
        planningCaserneRepositoryProvider.overrideWithValue(
          planningCaserne ?? FauxPlanningCaserneRepository(),
        ),
        cachePlanningCaserneProvider.overrideWithValue(
          cachePlanningCaserne ?? CachePlanningCaserneMemoire(),
        ),
        if (horloge != null)
          horlogeAstreintesProvider.overrideWithValue(horloge),
        // L'onglet 0 est désormais « Mon mois » : sans faux dépôt, il
        // toucherait un client Supabase qui n'existe pas en test.
        disposRepositoryProvider.overrideWithValue(
          dispos ?? FauxDisposRepository(),
        ),
        // La file gardée sur l'appareil passe par `shared_preferences` :
        // sans faux, chaque test attendrait un canal de plateforme qui ne
        // répond jamais.
        fileLocaleProvider.overrideWithValue(fileLocale ?? FileLocaleMemoire()),
        if (reseau != null) connectiviteProvider.overrideWithValue(reseau),
        reperesLocauxProvider.overrideWithValue(
          reperes ?? ReperesLocauxMemoire(),
        ),
        // La caserne gardée sur l'appareil (ticket 027) passe par
        // `shared_preferences` : sans faux, chaque test attendrait un canal de
        // plateforme qui ne répond jamais.
        appartenancesLocalesProvider.overrideWithValue(
          appartenancesLocales ?? AppartenancesLocalesMemoire(),
        ),
        // La caserne choisie (ticket 007) passe par `shared_preferences` :
        // sans faux, chaque test attendrait un canal de plateforme qui ne
        // répond jamais.
        caserneChoisieLocaleProvider.overrideWithValue(
          caserneChoisie ?? CaserneChoisieLocaleMemoire(),
        ),
        contextePlateformeProvider.overrideWithValue(
          plateforme ?? ContextePlateforme.natif,
        ),
        // Notifications (ticket 024). Par défaut : aucune configuration
        // Firebase, exactement l'état du projet tant qu'il n'y en a pas.
        firebaseDemarrageProvider.overrideWithValue(firebase),
        messageriePushProvider.overrideWithValue(push),
        pushTokensRepositoryProvider.overrideWithValue(depotJetons),
        jetonLocalProvider.overrideWithValue(jetonLocal ?? JetonLocalMemoire()),
        // Le centre de notifications (ticket 026) est lu par la cloche de la
        // barre d'application, donc par **tous** les écrans de la coquille :
        // sans faux, chaque test toucherait un client Supabase inexistant.
        notificationsRepositoryProvider.overrideWithValue(
          notifications ?? FauxNotificationsRepository(),
        ),
        // L'éditeur du produit (ticket 031). **Par défaut, personne ne l'est** :
        // `estSuperAdminProvider` est lu par le routeur à chaque redirection,
        // donc par tous les tests, et la porte doit rester fermée sans qu'un
        // client Supabase inexistant soit touché.
        superAdminRepositoryProvider.overrideWithValue(
          superAdmin ?? FauxSuperAdminRepository(autorise: false),
        ),
      ],
      child: const AstreinteApp(),
    ),
  );
  // `pumpAndSettle` ne rend jamais la main sur un écran qui porte un
  // squelette de chargement : son balayage tourne en boucle. Les tests qui
  // veulent observer ce squelette passent `stabiliser: false`.
  if (stabiliser) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }

  return (
    auth: auth,
    memberships: memberships,
    push: push,
    jetons: depotJetons,
  );
}

/// Ouvre un chemin comme le ferait un lien reçu par courriel ou une barre
/// d'adresse : c'est le routeur réel de l'application qui décide de la suite.
Future<void> ouvrirRoute(
  WidgetTester tester,
  String chemin, {

  /// À passer à faux quand l'écran d'arrivée porte un squelette de
  /// chargement : son balayage tourne en boucle et `pumpAndSettle` ne rend
  /// jamais la main.
  bool stabiliser = true,
}) async {
  final conteneur = ProviderScope.containerOf(
    tester.element(find.byType(AstreinteApp)),
  );
  conteneur.read(appRouterProvider).go(chemin);
  if (stabiliser) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

/// Fait défiler jusqu'à [cible], **dans la liste de l'écran**.
///
/// `scrollUntilVisible` cherche un `Scrollable` unique quand on ne lui en
/// désigne aucun — et un écran qui porte un champ de saisie en a plusieurs :
/// `EditableText` en range un dans chaque `TextField`. L'écran de profil du
/// ticket 007 en a trois, et tous les tests qui défilaient sur cet onglet se
/// sont mis à échouer sur « Bad state: Too many elements ».
///
/// `.first` est la liste de l'écran : elle précède ses champs dans l'ordre de
/// l'arbre.
Future<void> defilerJusqua(
  WidgetTester tester,
  Finder cible, {
  double pas = 200,
}) async {
  await tester.scrollUntilVisible(
    cible,
    pas,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// Démonte l'arbre pour libérer les minuteries des contrôleurs.
Future<void> demonter(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

/// L'emplacement servi par le routeur, chaîne de requête comprise.
///
/// C'est ce que la barre d'adresse affiche : les tests de liens profonds
/// vérifient la destination réelle, pas l'écran qui se trouve dessus.
String emplacementCourant(WidgetTester tester) {
  final conteneur = ProviderScope.containerOf(
    tester.element(find.byType(AstreinteApp)),
  );
  return conteneur.read(appRouterProvider).state.uri.toString();
}
