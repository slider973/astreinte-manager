import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/appartenance.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../data/membres_repository.dart';
import 'administration_membre.dart';
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

  /// Les membres de la caserne, actifs **et** désactivés, triés par nom.
  final List<MembreCaserne> membres;

  final List<Invitation> invitations;

  bool get vide => membres.isEmpty && invitations.isEmpty;

  int get actifs => membres.where((MembreCaserne m) => m.estActif).length;

  int get desactives =>
      membres.where((MembreCaserne m) => m.estDesactive).length;

  /// Le même compte que celui du déclencheur `memberships_guard_admin` : c'est
  /// lui qui décide si la caserne peut encore perdre un administrateur.
  int get adminsActifs =>
      membres.where((MembreCaserne m) => m.estAdminActif).length;

  /// Les membres qui répondent à la recherche, dans l'ordre de la liste.
  List<MembreCaserne> filtres(String requete) {
    final normalisee = normaliserRecherche(requete);
    if (normalisee.isEmpty) return membres;
    return membres
        .where((MembreCaserne m) => m.correspondA(normalisee))
        .toList(growable: false);
  }
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
/// La fraîcheur est donc portée par trois relectures, et non par un
/// abonnement :
///
/// 1. **à l'ouverture de l'écran** — le provider est auto-disposé, donc son
///    état meurt avec le dernier écran qui l'observe et [build] rejoue la
///    lecture au retour. C'est le point qui compte : personne côté admin
///    n'est prévenu quand un invité accepte ;
/// 2. **au retour de l'application au premier plan** (`MembresScreen`) ;
/// 3. **après chaque action** — envoi, renvoi, annulation.
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
    final (
      List<MembreCaserne> membres,
      List<Invitation> invitations,
      Map<String, DateTime> saisies,
    ) = await (
      depot.membres(stationId),
      depot.invitationsEnAttente(stationId),
      depot.dernieresSaisies(stationId),
    ).wait;

    // Deux tables, deux politiques, deux lectures : les dates de dernière
    // saisie sont recollées ici plutôt que jointes côté serveur.
    return EtatMembres(
      membres: List<MembreCaserne>.unmodifiable(
        membres.map(
          (MembreCaserne m) => m.avecDerniereSaisie(saisies[m.userId]),
        ),
      ),
      invitations: invitations,
    );
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

  /// Promeut un membre en administrateur de la caserne.
  Future<ResultatAction> promouvoir(MembreCaserne membre) => _administrer(
    () => ref
        .read(membresRepositoryProvider)
        .changerRole(membershipId: membre.id, role: RoleMembre.admin),
    AppStrings.membreVerdictPromu(membre.libelle),
  );

  /// Rend un administrateur au rang de membre.
  Future<ResultatAction> retrograder(MembreCaserne membre) => _administrer(
    () => ref
        .read(membresRepositoryProvider)
        .changerRole(membershipId: membre.id, role: RoleMembre.membre),
    AppStrings.membreVerdictRetrograde(membre.libelle),
  );

  /// Coupe l'accès d'un membre à la caserne. Sa ligne et son historique
  /// restent : rien n'est supprimé (`docs/PRD.md § 8`).
  Future<ResultatAction> desactiver(MembreCaserne membre) => _administrer(
    () => ref
        .read(membresRepositoryProvider)
        .changerStatut(membershipId: membre.id, statut: StatutMembre.desactive),
    AppStrings.membreVerdictDesactive(membre.libelle),
  );

  /// Rend l'accès à un membre désactivé.
  Future<ResultatAction> reactiver(MembreCaserne membre) => _administrer(
    () => ref
        .read(membresRepositoryProvider)
        .changerStatut(membershipId: membre.id, statut: StatutMembre.actif),
    AppStrings.membreVerdictReactive(membre.libelle),
  );

  /// Change le nom affiché dans la caserne. Un texte vide efface le surnom et
  /// rend au membre le nom de son profil.
  Future<ResultatAction> renommer(MembreCaserne membre, String? nomAffiche) {
    final propre = nomAffiche?.trim();
    return _administrer(
      () => ref
          .read(membresRepositoryProvider)
          .renommer(
            membershipId: membre.id,
            nomAffiche: propre == null || propre.isEmpty ? null : propre,
          ),
      AppStrings.membreVerdictRenomme,
    );
  }

  /// Le corps commun des cinq écritures : agir, relire, rendre un verdict.
  ///
  /// La relecture n'est pas optionnelle. Les garde-fous vivent dans la base
  /// (`memberships_guard_admin`, migration `0010`) : ce que l'écran croit
  /// savoir de la caserne ne fait pas foi, et un refus doit repartir de l'état
  /// réel.
  Future<ResultatAction> _administrer(
    Future<void> Function() ecriture,
    String verdict,
  ) async {
    try {
      await ecriture();
      await rafraichir();
      return ResultatAction(reussi: true, message: verdict);
    } on EchecAdministration catch (echec) {
      await rafraichir();
      return ResultatAction(reussi: false, message: echec.message);
    } on Object {
      return const ResultatAction(
        reussi: false,
        message: AppStrings.membreEchecGenerique,
      );
    }
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

/// Auto-disposé : sans cela, l'état survivrait à la navigation et l'écran
/// rouvert montrerait la liste d'il y a dix minutes — avec l'invitation d'une
/// personne déjà entrée dans la caserne.
final AsyncNotifierProvider<MembresController, EtatMembres>
membresControllerProvider =
    AsyncNotifierProvider<MembresController, EtatMembres>(
      MembresController.new,
      isAutoDispose: true,
    );

/// Vrai si l'utilisateur courant administre une caserne. L'écran « Membres »
/// n'a rien à montrer autrement, et la base le refuserait de toute façon.
final Provider<bool> estAdminCaserneProvider = Provider<bool>((ref) {
  final appartenance = ref.watch(appartenanceCouranteProvider);
  return appartenance?.estAdmin ?? false;
});

/// Ce qu'il faut savoir pour arbitrer une action sur un membre : combien
/// d'administrateurs actifs compte la caserne, et qui est l'utilisateur
/// connecté.
///
/// Le même calcul que celui du déclencheur `memberships_guard_admin`, fait ici
/// pour **montrer** le refus avant le geste. La base reste l'autorité : un
/// écran ouvert depuis dix minutes peut se tromper, elle non.
final Provider<ContexteAdministration> contexteAdministrationProvider =
    Provider<ContexteAdministration>((ref) {
      final etat = ref.watch(membresControllerProvider).value;
      return ContexteAdministration(
        adminsActifs: etat?.adminsActifs ?? 0,
        userIdCourant: ref.watch(sessionProvider).value?.userId,
      );
    });
