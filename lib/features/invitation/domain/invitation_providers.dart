import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/jeton_invitation.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../data/invitation_repository.dart';
import 'acceptation.dart';

/// Le dépôt d'acceptation. Surchargé par un faux dans les tests.
final Provider<InvitationRepository> invitationRepositoryProvider =
    Provider<InvitationRepository>(
      (ref) => SupabaseInvitationRepository(ref.watch(supabaseClientProvider)),
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

/// Échange le jeton du lien contre une `memberships` active.
///
/// L'ordre compte : on n'annonce la bienvenue qu'une fois les appartenances
/// relues. Sans cela, le routeur verrait encore un compte sans caserne et
/// renverrait l'invité sur « aucune caserne » au moment précis où il vient de
/// rejoindre la sienne.
class AcceptationController extends Notifier<EtatAcceptation> {
  @override
  EtatAcceptation build() => const EtatAcceptation();

  Future<void> accepter(String jeton) async {
    if (state.enCours) return;

    state = const EtatAcceptation(enCours: true);
    try {
      final resultat = await ref
          .read(invitationRepositoryProvider)
          .accepter(jeton);
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
