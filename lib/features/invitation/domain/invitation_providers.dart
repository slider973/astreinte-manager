import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/jeton_invitation.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../data/invitation_repository.dart';
import 'acceptation.dart';
import 'invitation_recue.dart';

/// Le dépôt d'acceptation. Surchargé par un faux dans les tests.
final Provider<InvitationRepository> invitationRepositoryProvider =
    Provider<InvitationRepository>(
      (ref) => SupabaseInvitationRepository(ref.watch(supabaseClientProvider)),
    );

/// Les invitations en attente adressées à l'adresse de la session.
///
/// **Rien n'est écrit sur l'appareil, et c'est volontaire** : cette liste
/// décide d'un droit d'entrée, et un cache ne décide jamais d'un droit
/// (`CLAUDE.md § Règle des caches locaux`). Il n'y a donc rien à brancher dans
/// `core/session/deconnexion.dart` — inutile de chercher. Hors ligne, l'écran
/// le dit plutôt que de deviner.
///
/// Auto-disposé : son état meurt avec le dernier écran qui l'observe, donc
/// l'ouverture d'« Aucune caserne » **et le retour depuis `/rejoindre`**
/// reposent la question. Entre-temps l'invitation a pu expirer ou être
/// annulée, et une liste restituée de mémoire le cacherait.
final FutureProvider<List<InvitationRecue>> invitationsRecuesProvider =
    FutureProvider<List<InvitationRecue>>(
      (ref) async {
        final session = ref.watch(sessionProvider).value;
        if (session == null) return const <InvitationRecue>[];

        return ref.read(invitationRepositoryProvider).mesInvitations();
      },
      isAutoDispose: true,
      // **Pas de relecture silencieuse en boucle.** Un échec est dit en
      // bannière, avec « Réessayer » : c'est un geste, et il appartient à la
      // personne. Une reprise automatique ferait clignoter la bannière sur un
      // écran qui n'a rien d'autre à montrer, et continuerait de frapper un
      // serveur qui vient de refuser.
      retry: (int tentatives, Object erreur) => null,
    );

/// Où en est l'échange du jeton contre une place dans la caserne.
@immutable
class EtatAcceptation {
  const EtatAcceptation({this.enCours = false, this.acceptee, this.echec});

  final bool enCours;
  final AcceptationInvitation? acceptee;
  final EchecAcceptation? echec;

  /// Vrai tant que rien n'a été tenté.
  bool get auRepos => !enCours && acceptee == null && echec == null;
}

/// Échange une invitation contre une `memberships` active.
///
/// Deux entrées, un seul contrôleur : le jeton du lien reçu par courriel, ou
/// l'identifiant lu sur « Aucune caserne » (ticket 051). La suite ne sait pas
/// par où l'on est entré, et n'a pas à le savoir — mêmes états, même page de
/// bienvenue, mêmes fins de parcours.
///
/// L'ordre compte : on n'annonce la bienvenue qu'une fois les appartenances
/// relues. Sans cela, le routeur verrait encore un compte sans caserne et
/// renverrait l'invité sur « aucune caserne » au moment précis où il vient de
/// rejoindre la sienne.
class AcceptationController extends Notifier<EtatAcceptation> {
  @override
  EtatAcceptation build() => const EtatAcceptation();

  Future<void> accepter(EntreeInvitation entree) async {
    if (state.enCours) return;

    state = const EtatAcceptation(enCours: true);
    try {
      final resultat = await ref
          .read(invitationRepositoryProvider)
          .accepter(entree);
      await _relireLesAppartenances();
      ref.read(jetonInvitationProvider.notifier).oublier();
      state = EtatAcceptation(acceptee: resultat);
    } on EchecAcceptation catch (echec) {
      // Un lien mort ne sert plus à rien : l'oublier évite que le routeur y
      // ramène en boucle après la prochaine connexion.
      if (!echec.erreur.reessayable) {
        ref.read(jetonInvitationProvider.notifier).oublier();
      }
      state = EtatAcceptation(echec: echec);
    } on Object {
      state = const EtatAcceptation(
        echec: EchecAcceptation(ErreurAcceptation.inconnue),
      );
    }
  }

  /// Rejoue la tentative après un incident réseau.
  void reinitialiser() => state = const EtatAcceptation();

  Future<void> _relireLesAppartenances() async {
    try {
      ref.invalidate(appartenancesProvider);
      await ref.read(appartenancesProvider.future);
    } on Object {
      // La caserne est rejointe, c'est la relecture qui a échoué : l'écran de
      // démarrage propose déjà de réessayer. Rien à dire de plus ici.
    }
  }
}

final NotifierProvider<AcceptationController, EtatAcceptation>
acceptationControllerProvider =
    NotifierProvider<AcceptationController, EtatAcceptation>(
      AcceptationController.new,
      isAutoDispose: true,
    );
