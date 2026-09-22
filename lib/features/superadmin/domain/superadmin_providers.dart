import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/appartenance.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../membres/domain/invitation.dart';
import '../../membres/domain/membres_providers.dart';
import '../data/superadmin_repository.dart';
import 'caserne_supervisee.dart';

/// Le dépôt de l'éditeur. Surchargé par un faux dans les tests.
final Provider<SuperAdminRepository> superAdminRepositoryProvider =
    Provider<SuperAdminRepository>(
      (ref) => SupabaseSuperAdminRepository(ref.watch(supabaseClientProvider)),
    );

/// Le compte connecté est-il l'éditeur du produit ?
///
/// **C'est ce provider qui ouvre la route `/superadmin`**, et le routeur
/// l'écoute (`core/router/app_router.dart`). Tant qu'il n'a pas répondu, la
/// garde ne tranche pas : rediriger sur un statut non résolu perdrait l'URL
/// tapée à froid, et l'écran ne peut rien montrer sans droits de toute façon —
/// toutes ses données viennent de fonctions qui refusent.
///
/// Il dépend de la session : une déconnexion le recalcule, et il rend `false`
/// sans aller au serveur quand personne n'est connecté.
final FutureProvider<bool> estSuperAdminProvider = FutureProvider<bool>((
  ref,
) async {
  final session = ref.watch(sessionProvider).value;
  if (session == null) return false;
  return ref.watch(superAdminRepositoryProvider).estSuperAdmin();
});

/// Ce que l'écran de l'éditeur affiche.
@immutable
class VueSuperAdmin {
  const VueSuperAdmin({
    this.casernes = const <CaserneSupervisee>[],
    this.actionEnCours,
    this.echec,
  });

  final List<CaserneSupervisee> casernes;

  /// L'identifiant de la caserne dont une action est en train de s'exécuter, ou
  /// `null`. Un seul geste à la fois : deux suspensions simultanées sur deux
  /// lignes différentes n'ont aucun sens et masqueraient le résultat de l'une.
  final String? actionEnCours;

  /// La phrase du dernier refus, ou `null`. Elle reste à l'écran jusqu'au geste
  /// suivant : un `SnackBar` disparaît, une raison de refus doit rester
  /// lisible.
  final String? echec;

  bool get vide => casernes.isEmpty;

  bool enCours(String stationId) => actionEnCours == stationId;

  VueSuperAdmin copyWith({
    List<CaserneSupervisee>? casernes,
    String? Function()? actionEnCours,
    String? Function()? echec,
  }) => VueSuperAdmin(
    casernes: casernes ?? this.casernes,
    actionEnCours: actionEnCours == null ? this.actionEnCours : actionEnCours(),
    echec: echec == null ? this.echec : echec(),
  );
}

/// Le verdict d'une action de l'éditeur, prêt à annoncer.
///
/// `ui-ux-pro-max --domain ux` : « ne jamais réussir en silence ». Chaque
/// action rend donc une phrase, y compris quand elle a marché.
@immutable
class ResultatSuperAdmin {
  const ResultatSuperAdmin({required this.reussi, required this.message});

  final bool reussi;
  final String message;
}

/// L'écran `/superadmin`.
class SuperAdminController extends AsyncNotifier<VueSuperAdmin> {
  @override
  Future<VueSuperAdmin> build() async {
    // Sans le droit, on ne va pas au serveur pour se le faire dire : la
    // fonction rendrait une liste vide, indistinguable d'un parc sans caserne.
    final autorise = await ref.watch(estSuperAdminProvider.future);
    if (!autorise) return const VueSuperAdmin();

    final casernes = await ref.read(superAdminRepositoryProvider).casernes();
    return VueSuperAdmin(casernes: casernes);
  }

  /// Relit la liste. Appelée par « Réessayer » et après chaque action.
  Future<void> relire() async {
    state = const AsyncValue<VueSuperAdmin>.loading();
    state = await AsyncValue.guard(() async {
      final casernes = await ref.read(superAdminRepositoryProvider).casernes();
      return VueSuperAdmin(casernes: casernes);
    });
  }

  /// Crée une caserne et rend sa ligne, pour que la feuille puisse enchaîner
  /// sur l'invitation du premier administrateur sans repasser par la liste.
  ///
  /// Rend `null` si la création a échoué ; la raison est alors dans [state].
  Future<CaserneSupervisee?> creerCaserne({
    required String nom,
    required String fuseau,
  }) async {
    final vue = state.value;
    if (vue == null) return null;

    state = AsyncValue<VueSuperAdmin>.data(
      vue.copyWith(actionEnCours: () => _creation, echec: () => null),
    );

    try {
      final creee = await ref
          .read(superAdminRepositoryProvider)
          .creerCaserne(nom: nom, fuseau: fuseau);

      // La ligne est insérée à sa place dans la liste triée par nom : la
      // caserne créée ne saute pas en haut puis ailleurs à la relecture.
      final casernes = <CaserneSupervisee>[...vue.casernes, creee]
        ..sort(
          (CaserneSupervisee a, CaserneSupervisee b) =>
              a.nom.toLowerCase().compareTo(b.nom.toLowerCase()),
        );

      state = AsyncValue<VueSuperAdmin>.data(
        vue.copyWith(casernes: casernes, actionEnCours: () => null),
      );
      return creee;
    } on EchecSuperAdmin catch (echec) {
      _echouer(vue, echec.message);
      return null;
    } on Object {
      _echouer(vue, AppStrings.superAdminEchecGenerique);
      return null;
    }
  }

  /// Invite le premier administrateur d'une caserne.
  ///
  /// **Par le chemin du ticket 006 et par aucun autre** : c'est
  /// `MembresRepository.inviter` qui part, donc l'Edge Function
  /// `invite-member`, donc `create_invitation` — laquelle reconnaît l'éditeur
  /// depuis la migration `0025`.
  ///
  /// **Et le compte rendu est celui des écrans de caserne**, à une adresse
  /// près : [ResultatInvitation.libelle] et [ResultatInvitation.detail] disent
  /// le sort de l'invitation et celui de son courriel, l'écran ne fait que les
  /// mettre en phrase. Cet écran annonçait « Invitation envoyée » dès que le
  /// rapport ne comptait aucun échec, sans regarder si un courriel était
  /// sorti : le mensonge du ticket 048, au même endroit logique, sur l'écran
  /// qu'il n'avait pas ouvert (ticket 050).
  Future<ResultatSuperAdmin> inviterAdministrateur({
    required String stationId,
    required String email,
  }) async {
    final vue = state.value;
    if (vue == null) {
      return const ResultatSuperAdmin(
        reussi: false,
        message: AppStrings.superAdminEchecGenerique,
      );
    }

    state = AsyncValue<VueSuperAdmin>.data(
      vue.copyWith(actionEnCours: () => stationId, echec: () => null),
    );

    try {
      final rapport = await ref
          .read(membresRepositoryProvider)
          .inviter(
            stationId: stationId,
            emails: <String>[email],
            role: RoleMembre.admin,
          );

      // Une adresse, donc un résultat. **Et c'est lui qu'on annonce, pas
      // l'absence d'échec** : le rapport d'un envoi sans fournisseur de
      // courriel configuré ne compte aucun échec et n'a pourtant rien envoyé.
      // Un corps sans résultat n'est pas une réussite non plus : personne
      // n'est invité, et l'annoncer serait le même mensonge en plus gros.
      final resultat = rapport.resultats.firstOrNull;
      if (!rapport.toutEstPasse || resultat == null) {
        final refus = rapport.refus
            .map((ResultatInvitation r) => r.detail)
            .whereType<String>()
            .firstOrNull;
        return _refuser(vue, refus ?? AppStrings.superAdminEchecInvitation);
      }

      await relire();
      return ResultatSuperAdmin(
        // L'invitation existe : l'action a abouti, même si le courriel est
        // resté à quai — c'est un renvoi à faire, pas un refus à corriger.
        // La phrase, elle, ne dit que ce qui est vrai.
        reussi: true,
        message: AppStrings.superAdminResultatInvitation(
          // Le serveur normalise l'adresse ; c'est la sienne qu'on relit à la
          // personne, et la saisie ne sert que s'il ne l'a pas rendue.
          email: resultat.email.isEmpty ? email : resultat.email,
          libelle: resultat.libelle,
          detail: resultat.detail,
        ),
      );
    } on EchecInvitation catch (echec) {
      return _refuser(vue, echec.message);
    } on Object {
      return _refuser(vue, AppStrings.superAdminEchecInvitation);
    }
  }

  /// Suspend ou réactive une caserne.
  Future<ResultatSuperAdmin> definirSuspension({
    required String stationId,
    required bool suspendue,
    required String raison,
  }) async {
    final vue = state.value;
    if (vue == null) {
      return const ResultatSuperAdmin(
        reussi: false,
        message: AppStrings.superAdminEchecGenerique,
      );
    }

    final nom = vue.casernes
        .where((CaserneSupervisee c) => c.id == stationId)
        .map((CaserneSupervisee c) => c.nom)
        .firstOrNull;

    state = AsyncValue<VueSuperAdmin>.data(
      vue.copyWith(actionEnCours: () => stationId, echec: () => null),
    );

    try {
      await ref
          .read(superAdminRepositoryProvider)
          .definirSuspension(
            stationId: stationId,
            suspendue: suspendue,
            raison: raison,
          );
      await relire();
      return ResultatSuperAdmin(
        reussi: true,
        message: suspendue
            ? AppStrings.superAdminSuspendue(nom ?? '')
            : AppStrings.superAdminReactivee(nom ?? ''),
      );
    } on EchecSuperAdmin catch (echec) {
      return _refuser(vue, echec.message);
    } on Object {
      return _refuser(vue, AppStrings.superAdminEchecGenerique);
    }
  }

  /// La consultation de support. Rend `null` en cas de refus, la raison étant
  /// alors dans [state].
  Future<List<PlanningSupervise>?> consulterPlannings({
    required String stationId,
    required String raison,
  }) async {
    final vue = state.value;
    if (vue == null) return null;

    state = AsyncValue<VueSuperAdmin>.data(
      vue.copyWith(actionEnCours: () => stationId, echec: () => null),
    );

    try {
      final plannings = await ref
          .read(superAdminRepositoryProvider)
          .plannings(stationId: stationId, raison: raison);
      state = AsyncValue<VueSuperAdmin>.data(
        vue.copyWith(actionEnCours: () => null),
      );
      return plannings;
    } on EchecSuperAdmin catch (echec) {
      _echouer(vue, echec.message);
      return null;
    } on Object {
      _echouer(vue, AppStrings.superAdminEchecGenerique);
      return null;
    }
  }

  void _echouer(VueSuperAdmin vue, String message) {
    state = AsyncValue<VueSuperAdmin>.data(
      vue.copyWith(actionEnCours: () => null, echec: () => message),
    );
  }

  ResultatSuperAdmin _refuser(VueSuperAdmin vue, String message) {
    _echouer(vue, message);
    return ResultatSuperAdmin(reussi: false, message: message);
  }

  /// La création n'appartient à aucune ligne : elle occupe l'en-tête.
  static const String _creation = 'creation';

  /// Ce que [VueSuperAdmin.actionEnCours] vaut pendant une création.
  static const String creationEnCours = _creation;
}

final AsyncNotifierProvider<SuperAdminController, VueSuperAdmin>
superAdminControllerProvider =
    AsyncNotifierProvider<SuperAdminController, VueSuperAdmin>(
      SuperAdminController.new,
      isAutoDispose: true,
    );
