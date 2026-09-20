import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../data/membres_repository.dart';
import 'invitation.dart';
import 'membre_caserne.dart';

/// Le dépôt des membres. Surchargé par un faux dans les tests.
final Provider<MembresRepository> membresRepositoryProvider =
    Provider<MembresRepository>(
      (ref) => SupabaseMembresRepository(ref.watch(supabaseClientProvider)),
    );

/// Ce que l'écran « Membres » affiche : deux listes, lues ensemble.
@immutable
class EtatMembres {
  const EtatMembres({
    this.membres = const <MembreCaserne>[],
    this.invitations = const <Invitation>[],
  });

  final List<MembreCaserne> membres;
  final List<Invitation> invitations;

  bool get vide => membres.isEmpty && invitations.isEmpty;
}

/// Le résultat d'une action d'administration, prêt à annoncer.
@immutable
class ResultatAction {
  const ResultatAction({required this.reussi, required this.message});

  final bool reussi;
  final String message;
}

/// Les membres et les invitations de la caserne courante.
///
/// **Pas de temps réel sur les invitations** : `docs/SCHEMA.md § 9` les tient
/// hors de la réplication, parce que le canal ne saurait pas masquer le jeton.
/// Chaque action relit donc les deux listes.
class MembresController extends AsyncNotifier<EtatMembres> {
  @override
  Future<EtatMembres> build() async {
    final appartenance = ref.watch(appartenanceCouranteProvider);
    if (appartenance == null || !appartenance.estAdmin) {
      return const EtatMembres();
    }
    return _lire(appartenance.stationId);
  }

  Future<EtatMembres> _lire(String stationId) async {
    final depot = ref.read(membresRepositoryProvider);
    final (List<MembreCaserne> membres, List<Invitation> invitations) = await (
      depot.membres(stationId),
      depot.invitationsEnAttente(stationId),
    ).wait;

    return EtatMembres(membres: membres, invitations: invitations);
  }

  /// Relit les deux listes en gardant l'ancienne à l'écran : un rafraîchissement
  /// ne doit pas vider la page sous les yeux de qui l'utilise.
  Future<void> rafraichir() async {
    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    if (stationId == null) return;

    // L'ancienne liste reste à l'écran pendant la relecture : vider la page
    // pour la remplir aussitôt est un clignotement, pas une information.
    state = await AsyncValue.guard(() => _lire(stationId));
  }

  /// Renvoie une invitation : le même appel que l'invitation initiale, qui
  /// réutilise la ligne, repousse l'échéance et **conserve le jeton** — le
  /// lien déjà reçu continue de marcher.
  Future<ResultatAction> renvoyer(Invitation invitation) async {
    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    if (stationId == null) {
      return const ResultatAction(
        reussi: false,
        message: AppStrings.invitationRenvoiEchec,
      );
    }

    try {
      final rapport = await ref
          .read(membresRepositoryProvider)
          .inviter(
            stationId: stationId,
            emails: <String>[invitation.email],
            role: invitation.role,
          );
      await rafraichir();

      final premier = rapport.resultats.isEmpty
          ? null
          : rapport.resultats.first;
      if (premier == null || premier.enEchec) {
        return ResultatAction(
          reussi: false,
          message: premier?.motif?.message ?? AppStrings.invitationRenvoiEchec,
        );
      }
      return ResultatAction(
        reussi: true,
        message: premier.courrielEnvoye
            ? AppStrings.invitationRenvoyee
            : AppStrings.resultatCourrielNonParti,
      );
    } on EchecInvitation catch (echec) {
      return ResultatAction(reussi: false, message: echec.message);
    } on Object {
      return const ResultatAction(
        reussi: false,
        message: AppStrings.invitationRenvoiEchec,
      );
    }
  }

  /// Annule une invitation en attente, par suppression de la ligne.
  Future<ResultatAction> annuler(Invitation invitation) async {
    try {
      await ref.read(membresRepositoryProvider).annuler(invitation.id);
      await rafraichir();
      return const ResultatAction(
        reussi: true,
        message: AppStrings.invitationAnnulee,
      );
    } on Object {
      return const ResultatAction(
        reussi: false,
        message: AppStrings.invitationAnnulationEchec,
      );
    }
  }
}

final AsyncNotifierProvider<MembresController, EtatMembres>
membresControllerProvider =
    AsyncNotifierProvider<MembresController, EtatMembres>(
      MembresController.new,
    );

/// Vrai si l'utilisateur courant administre une caserne. L'écran « Membres »
/// n'a rien à montrer autrement, et la base le refuserait de toute façon.
final Provider<bool> estAdminCaserneProvider = Provider<bool>((ref) {
  final appartenance = ref.watch(appartenanceCouranteProvider);
  return appartenance?.estAdmin ?? false;
});
