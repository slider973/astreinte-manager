import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/supabase_bootstrap.dart';
import 'appartenance.dart';
import 'appartenances_locales.dart';
import 'auth_repository.dart';
import 'etat_auth.dart';
import 'membership_repository.dart';
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
/// **Une lecture qui échoue retombe sur ce qui est gardé sur l'appareil**
/// (ticket 027). Sans ce repli, un démarrage à froid sans réseau s'arrête sur
/// « Pas de connexion » : la session se restaure toute seule, mais la caserne
/// manque, et aucun écran de consultation n'est atteint. Le cache d'astreintes
/// ne servirait alors jamais dans la seule scène qui le justifie — une remise
/// sans couverture. Ce qui revient du stockage est **toujours un simple
/// membre** (`AppartenancesLocalesPartagees.relire`).
///
/// Si rien n'est gardé non plus, l'échec est relancé tel quel : l'écran de
/// démarrage propose de réessayer, il n'annonce jamais « aucune caserne ».
final FutureProvider<List<Appartenance>> appartenancesProvider =
    FutureProvider<List<Appartenance>>((ref) async {
      final session = ref.watch(sessionProvider).value;
      if (session == null) return const <Appartenance>[];

      final local = ref.watch(appartenancesLocalesProvider);
      try {
        final appartenances = await ref
            .watch(membershipRepositoryProvider)
            .mesAppartenances(session.userId);
        await local.ecrire(session.userId, appartenances);
        return appartenances;
      } on Object {
        final gardees = await local.lire(session.userId);
        if (gardees.isEmpty) rethrow;
        return gardees;
      }
    });

/// La caserne dans laquelle l'utilisateur travaille.
///
/// Le cas multi-caserne existe (`docs/PRD.md § 6.1`) mais son sélecteur n'est
/// pas au périmètre de ce ticket : on prend la première appartenance active,
/// dans un ordre stable, pour que l'app affiche toujours la même.
final Provider<Appartenance?> appartenanceCouranteProvider =
    Provider<Appartenance?>((ref) {
      final actives = ref.watch(appartenancesActivesProvider);
      return actives.isEmpty ? null : actives.first;
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

  return ref.watch(appartenancesActivesProvider).isEmpty
      ? EtatAuth.sansCaserne
      : EtatAuth.connecte;
});
