import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fraicheur/relecture.dart';
import '../supabase/supabase_bootstrap.dart';
import 'appartenance.dart';
import 'appartenances_locales.dart';
import 'auth_erreur.dart';
import 'auth_repository.dart';
import 'caserne_choisie.dart';
import 'etat_auth.dart';
import 'membership_repository.dart';
import 'oubli_local.dart';
import 'session_utilisateur.dart';

/// Le dépôt d'authentification. Surchargé par un faux dans les tests.
final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)),
    );

/// Le dépôt des appartenances. Surchargé par un faux dans les tests.
final Provider<MembershipRepository> membershipRepositoryProvider =
    Provider<MembershipRepository>(
      (ref) => SupabaseMembershipRepository(ref.watch(supabaseClientProvider)),
    );

/// La session courante et chacun de ses changements.
///
/// Le rafraîchissement du jeton est fait par le SDK ; sa perte se traduit par
/// un `null` dans ce flux, donc par un retour à l'écran de connexion.
final StreamProvider<SessionUtilisateur?> sessionProvider =
    StreamProvider<SessionUtilisateur?>(
      (ref) => ref.watch(authRepositoryProvider).sessions,
    );

/// Les appartenances de l'utilisateur connecté, relues à chaque changement de
/// session. Liste vide si personne n'est connecté.
///
/// **Un échec de transport retombe sur ce qui est gardé sur l'appareil**
/// (ticket 027). Sans ce repli, un démarrage à froid sans réseau s'arrête sur
/// « Pas de connexion » : la session se restaure toute seule, mais la caserne
/// manque, et aucun écran de consultation n'est atteint. Le cache d'astreintes
/// ne servirait alors jamais dans la seule scène qui le justifie — une remise
/// sans couverture. Ce qui revient du stockage est **toujours un simple
/// membre** (`AppartenancesLocalesPartagees.relire`).
///
/// **Le repli ne couvre que [AuthErreur.reseau].** Un refus, un jeton périmé,
/// une réponse illisible remontent tels quels : masquer une révocation
/// derrière un instantané périmé ferait croire à quelqu'un qu'il appartient
/// encore à une caserne qui l'a retiré. Un échec de transport est la seule
/// panne dont on sait qu'elle ne dit rien sur les droits.
///
/// La rétrogradation est appliquée **ici**, et pas seulement à la relecture du
/// document : la garantie ne doit pas dépendre de l'implémentation de stockage
/// qu'on a branchée.
///
/// Si rien n'est gardé non plus, l'échec est relancé tel quel : l'écran de
/// démarrage propose de réessayer, il n'annonce jamais « aucune caserne ».
final FutureProvider<List<Appartenance>> appartenancesProvider =
    FutureProvider<List<Appartenance>>((ref) async {
      final session = ref.watch(sessionProvider).value;
      if (session == null) return const <Appartenance>[];

      final local = ref.watch(appartenancesLocalesProvider);

      // Une relecture vient d'aboutir (ticket 070) : sa réponse est celle de la
      // base, confirmée à l'instant, et la redemander doublerait la requête —
      // avec le risque qu'un second aller-retour tombe dans un tunnel et
      // rétrograde un admin qu'on venait de confirmer.
      final relues = ref
          .read(appartenancesReluesProvider)
          .prendre(session.userId);
      if (relues != null) {
        await _garderEtOublierLesQuittees(ref, session.userId, relues);
        return relues;
      }

      try {
        final appartenances = await ref
            .watch(membershipRepositoryProvider)
            .mesAppartenances(session.userId);
        await _garderEtOublierLesQuittees(ref, session.userId, appartenances);
        return appartenances;
      } on AuthEchec catch (echec) {
        if (echec.erreur != AuthErreur.reseau) rethrow;
        final gardees = await local.lire(session.userId);
        if (gardees.isEmpty) rethrow;
        return <Appartenance>[
          for (final gardee in gardees) gardee.commeMembre,
        ];
      }
    });

/// Range la liste lue **en base**, et efface les caches des casernes que le
/// compte a quittées (ticket 072).
///
/// Une caserne est quittée quand son appartenance est désactivée, ou quand elle
/// était gardée sur l'appareil et que la base ne la rend plus active. Ses
/// astreintes, son planning et sa file de saisie partent alors de l'appareil,
/// comme à la déconnexion (`oubli_local.dart`). Jamais sur le repli hors
/// ligne : seule une lecture réussie dit qu'un accès a pris fin.
Future<void> _garderEtOublierLesQuittees(
  Ref ref,
  String userId,
  List<Appartenance> lues,
) async {
  final local = ref.read(appartenancesLocalesProvider);
  final avant = await local.lire(userId);
  await local.ecrire(userId, lues);

  final actives = <String>{
    for (final appartenance in lues)
      if (appartenance.estActive) appartenance.stationId,
  };
  final quittees = <String>{
    for (final appartenance in <Appartenance>[...avant, ...lues])
      if (!actives.contains(appartenance.stationId)) appartenance.stationId,
  };
  if (quittees.isEmpty) return;
  await ref
      .read(oubliLocalProvider)
      .casernesQuittees(userId: userId, stations: quittees);
}

/// La réponse d'une relecture des appartenances, en attente d'être reprise
/// par [appartenancesProvider].
///
/// **Mémoire vive seulement**, et consommée à la première lecture : ce n'est
/// pas un cache, rien n'en survit à la page, et la règle des caches de
/// `deconnexion.dart` n'a rien à y oublier.
class AppartenancesRelues {
  String? _userId;
  List<Appartenance>? _liste;

  void deposer(String userId, List<Appartenance> liste) {
    _userId = userId;
    _liste = List<Appartenance>.unmodifiable(liste);
  }

  /// Rend la liste déposée pour [userId], une fois, puis l'oublie. Une liste
  /// déposée pour quelqu'un d'autre est oubliée aussi.
  List<Appartenance>? prendre(String userId) {
    final liste = _userId == userId ? _liste : null;
    _userId = null;
    _liste = null;
    return liste;
  }
}

final Provider<AppartenancesRelues> appartenancesReluesProvider =
    Provider<AppartenancesRelues>((ref) => AppartenancesRelues());

/// **Relit les appartenances en cours de session** (ticket 070).
///
/// Avant ce ticket, `memberships` n'était relu qu'au changement de session : un
/// rôle retiré ou donné n'apparaissait qu'au redémarrage, et un démarrage hors
/// ligne laissait un chef de centre en simple membre sans nouvelle tentative.
/// Le coordinateur `core/fraicheur` l'appelle au retour au premier plan et au
/// retour du réseau.
///
/// Trois règles, les mêmes que [appartenancesProvider] :
///
/// - **la base est la seule autorité** : ce qui est publié vient d'une lecture
///   réussie, jamais du stockage ;
/// - **un échec de transport ne change rien** : l'écran garde ce qu'il sait, et
///   surtout ne rétrograde pas un admin confirmé parce qu'un tunnel a coupé le
///   retour au premier plan ;
/// - **un refus n'est pas masqué** : il relance [appartenancesProvider], qui le
///   remonte tel quel — une révocation ne se cache pas derrière l'écran d'avant.
///
/// Rien n'est publié si la liste n'a pas changé : tout ce que l'application
/// affiche dépend de la caserne courante, et la republier à l'identique
/// reconstruirait chaque écran. [publierSi] est consulté après la lecture,
/// juste avant de publier, pour ne jamais reconstruire une saisie sous le
/// doigt.
Future<Relecture> relireAppartenances(
  Ref ref, {
  bool Function()? publierSi,
}) async {
  final session = ref.read(sessionProvider).value;
  if (session == null) return Relecture.inchangee;
  if (ref.read(appartenancesProvider).isLoading) return Relecture.inchangee;

  final List<Appartenance> lues;
  try {
    lues = await ref
        .read(membershipRepositoryProvider)
        .mesAppartenances(session.userId);
  } on AuthEchec catch (echec) {
    if (echec.erreur == AuthErreur.reseau) return Relecture.echouee;
    ref.invalidate(appartenancesProvider);
    return Relecture.publiee;
  } on Object {
    return Relecture.echouee;
  }

  final courant = ref.read(appartenancesProvider);
  if (ref.read(sessionProvider).value?.userId != session.userId ||
      courant.isLoading) {
    return Relecture.inchangee;
  }
  if (courant.hasValue &&
      !courant.hasError &&
      listEquals(courant.value, lues)) {
    return Relecture.inchangee;
  }
  if (publierSi != null && !publierSi()) return Relecture.retenue;

  ref.read(appartenancesReluesProvider).deposer(session.userId, lues);
  ref.invalidate(appartenancesProvider);
  return Relecture.publiee;
}

/// La caserne dans laquelle l'utilisateur travaille.
///
/// **Le choix du membre gagne** depuis le ticket 007 : quelqu'un qui appartient
/// à deux casernes en désigne une dans son profil, et tout ce que l'application
/// affiche ensuite — son mois, ses astreintes, le planning, les droits d'admin
/// lus par le routeur — suit ce choix, parce que tout passe par ce provider.
///
/// À défaut, la première appartenance active dans un ordre stable, comme avant.
/// C'est aussi ce qui arrive quand le choix gardé **ne correspond plus à aucune
/// appartenance active** — on a été retiré de cette caserne entre deux
/// ouvertures : l'application ne se bloque pas sur un souvenir, elle affiche la
/// caserne qui reste.
final Provider<Appartenance?> appartenanceCouranteProvider =
    Provider<Appartenance?>((ref) {
      final actives = ref.watch(appartenancesActivesProvider);
      if (actives.isEmpty) return null;

      final choisie = ref.watch(caserneChoisieProvider);
      if (choisie == null) return actives.first;

      return actives.firstWhere(
        (Appartenance a) => a.stationId == choisie,
        orElse: () => actives.first,
      );
    });

/// Les appartenances actives, triées par nom de caserne.
final Provider<List<Appartenance>> appartenancesActivesProvider =
    Provider<List<Appartenance>>((ref) {
      final toutes =
          ref.watch(appartenancesProvider).value ?? const <Appartenance>[];
      final actives = toutes.where((Appartenance a) => a.estActive).toList()
        ..sort(
          (Appartenance a, Appartenance b) =>
              a.nomCaserne.compareTo(b.nomCaserne),
        );
      return List<Appartenance>.unmodifiable(actives);
    });

/// L'état qui décide de la route (`core/router/auth_redirection.dart`).
///
/// Une lecture d'appartenances en échec **ne bascule pas** vers « aucune
/// caserne » : dire « tu n'as pas de caserne » parce que le réseau est tombé
/// serait un mensonge. L'état reste [EtatAuth.chargement] et l'écran de
/// démarrage propose de réessayer.
final Provider<EtatAuth> etatAuthProvider = Provider<EtatAuth>((ref) {
  final session = ref.watch(sessionProvider);
  if (!session.hasValue && !session.hasError) return EtatAuth.chargement;
  if (session.value == null) return EtatAuth.deconnecte;

  final appartenances = ref.watch(appartenancesProvider);
  if (appartenances.hasError) return EtatAuth.chargement;
  if (!appartenances.hasValue) return EtatAuth.chargement;

  final actives = ref.watch(appartenancesActivesProvider);

  // **Une liste vide encore en chargement ne décide rien.**
  //
  // `appartenancesProvider` observe `sessionProvider` : au démarrage à froid il
  // est d'abord calculé sans session — il rend alors la liste vide — puis
  // recalculé dès que la session est restaurée. Riverpod **garde la valeur
  // précédente** pendant ce recalcul (`AsyncLoading` avec `hasValue`), donc
  // cette liste vide reste lisible tant que la requête n'a pas répondu. Sans
  // réseau, elle ne répond jamais, et décider dessus envoyait un membre
  // parfaitement rattaché sur « Aucune caserne » — écran qui ne propose que la
  // déconnexion. Vu dans Chrome, API coupée (`design/023 § 10`).
  //
  // La condition porte sur la **liste vide**, pas sur le chargement seul : un
  // rafraîchissement de jeton en cours de session recalcule ce provider toutes
  // les heures, et renvoyer l'écran de démarrage à chaque fois ferait clignoter
  // l'application sous les yeux de quelqu'un qui ne demandait rien.
  if (actives.isEmpty && appartenances.isLoading) return EtatAuth.chargement;

  return actives.isEmpty ? EtatAuth.sansCaserne : EtatAuth.connecte;
});
