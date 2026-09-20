import 'dart:async';

import 'package:astreinte_sp/app.dart';
import 'package:astreinte_sp/core/env.dart';
import 'package:astreinte_sp/core/firebase/firebase_bootstrap.dart';
import 'package:astreinte_sp/core/plateforme/contexte_plateforme.dart';
import 'package:astreinte_sp/core/preferences/reperes_locaux.dart';
import 'package:astreinte_sp/core/reseau/connectivite.dart';
import 'package:astreinte_sp/core/router/app_router.dart';
import 'package:astreinte_sp/core/session/appartenance.dart';
import 'package:astreinte_sp/core/session/auth_erreur.dart';
import 'package:astreinte_sp/core/session/auth_repository.dart';
import 'package:astreinte_sp/core/session/membership_repository.dart';
import 'package:astreinte_sp/core/session/session_providers.dart';
import 'package:astreinte_sp/core/session/session_utilisateur.dart';
import 'package:astreinte_sp/core/supabase/supabase_bootstrap.dart';
import 'package:astreinte_sp/features/dispos/data/dispos_repository.dart';
import 'package:astreinte_sp/features/dispos/data/file_locale.dart';
import 'package:astreinte_sp/features/dispos/domain/dispos_providers.dart';
import 'package:astreinte_sp/features/invitation/data/invitation_repository.dart';
import 'package:astreinte_sp/features/invitation/domain/invitation_providers.dart';
import 'package:astreinte_sp/features/membres/data/membres_repository.dart';
import 'package:astreinte_sp/features/membres/domain/membres_providers.dart';
import 'package:astreinte_sp/features/notifications/data/jeton_local.dart';
import 'package:astreinte_sp/features/notifications/domain/notifications_providers.dart';
import 'package:astreinte_sp/features/onboarding/data/profil_repository.dart';
import 'package:astreinte_sp/features/onboarding/domain/profil_providers.dart';
import 'package:astreinte_sp/features/parametres/data/parametres_repository.dart';
import 'package:astreinte_sp/features/parametres/domain/parametres_providers.dart';
import 'package:astreinte_sp/features/periodes/data/periodes_repository.dart';
import 'package:astreinte_sp/features/periodes/domain/periodes_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'faux_dispos.dart';
import 'faux_invitations.dart';
import 'faux_push.dart';

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
  }) : _session = session;

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
    yield _session;
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
  });

  List<Appartenance> appartenances;

  /// Erreur levée à la lecture, ou `null`.
  AuthErreur? erreur;

  int lectures = 0;

  @override
  Future<List<Appartenance>> mesAppartenances(String userId) async {
    lectures++;
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
  MembresRepository? membres,
  InvitationRepository? invitations,
  ProfilRepository? profils,
  ParametresRepository? parametres,
  PeriodesRepository? periodes,
  DisposRepository? dispos,
  FileLocale? fileLocale,
  Connectivite? reseau,
  ReperesLocaux? reperes,
  ContextePlateforme? plateforme,
  FirebaseDemarrage firebase = FirebaseDemarrage.configurationAbsente,
  FauxMessageriePush? messagerie,
  FauxPushTokensRepository? jetons,
  JetonLocal? jetonLocal,
  Size taille = const Size(390, 844),
  bool stabiliser = true,
}) async {
  tester.view.physicalSize = taille * tester.view.devicePixelRatio;
  addTearDown(tester.view.reset);

  final auth = FauxAuthRepository(
    session: session,
    erreurEnvoi: erreurEnvoi,
    erreurVerification: erreurVerification,
  );
  addTearDown(auth.fermer);
  final memberships = FauxMembershipRepository(
    appartenances: appartenances,
    erreur: erreurAppartenances,
  );
  final push = messagerie ?? FauxMessageriePush();
  addTearDown(push.fermer);
  final depotJetons = jetons ?? FauxPushTokensRepository();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        envProvider.overrideWithValue(envDeTest),
        supabaseDemarrageProvider.overrideWithValue(SupabaseDemarrage.pret),
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
        if (parametres != null)
          parametresRepositoryProvider.overrideWithValue(parametres),
        if (periodes != null)
          periodesRepositoryProvider.overrideWithValue(periodes),
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
        contextePlateformeProvider.overrideWithValue(
          plateforme ?? ContextePlateforme.natif,
        ),
        // Notifications (ticket 024). Par défaut : aucune configuration
        // Firebase, exactement l'état du projet tant qu'il n'y en a pas.
        firebaseDemarrageProvider.overrideWithValue(firebase),
        messageriePushProvider.overrideWithValue(push),
        pushTokensRepositoryProvider.overrideWithValue(depotJetons),
        jetonLocalProvider.overrideWithValue(jetonLocal ?? JetonLocalMemoire()),
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
Future<void> ouvrirRoute(WidgetTester tester, String chemin) async {
  final conteneur = ProviderScope.containerOf(
    tester.element(find.byType(AstreinteApp)),
  );
  conteneur.read(appRouterProvider).go(chemin);
  await tester.pumpAndSettle();
}

/// Démonte l'arbre pour libérer les minuteries des contrôleurs.
Future<void> demonter(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());
