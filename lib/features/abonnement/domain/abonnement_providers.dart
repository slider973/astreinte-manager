import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/plateforme/ouverture_externe.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../data/abonnement_repository.dart';
import 'abonnement.dart';

/// Le dépôt de l'abonnement. Surchargé par un faux dans les tests.
final Provider<AbonnementRepository> abonnementRepositoryProvider =
    Provider<AbonnementRepository>(
      (ref) => SupabaseAbonnementRepository(ref.watch(supabaseClientProvider)),
    );

/// L'horloge de l'écran, pour que « il reste 12 jours » se teste sans attendre.
final Provider<DateTime Function()> horlogeAbonnementProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// Ce qui se passe après un retour du prestataire de paiement.
enum RetourPaiement {
  /// `?paiement=ok` : la session a abouti. **Rien n'est cru sur parole** —
  /// c'est le webhook qui écrit, et il peut arriver deux secondes plus tard.
  reussi,

  /// `?paiement=annule` : quelqu'un a regardé le prix et fermé l'onglet. Ce
  /// n'est pas une erreur, et rien n'est affiché (`design/029 § 4`).
  annule,
}

/// Ce que l'écran « Abonnement » affiche.
@immutable
class VueAbonnement {
  const VueAbonnement({
    required this.etat,
    this.formuleEnCours,
    this.portailEnCours = false,
    this.echec,
    this.retour,
    this.statutEnAttente = false,
  });

  final EtatAbonnement etat;

  /// La formule dont la session de paiement est en train de s'ouvrir, ou
  /// `null`. Le bouton correspondant passe en chargement, libellé conservé.
  final FormuleAbonnement? formuleEnCours;

  /// Le portail de gestion est en train de s'ouvrir.
  final bool portailEnCours;

  /// La phrase du dernier refus, ou `null`. Elle reste à l'écran tant qu'une
  /// autre action n'a pas eu lieu : un `SnackBar` disparaît, une raison de
  /// refus doit rester lisible.
  final String? echec;

  /// Le retour du prestataire, lu dans l'URL.
  final RetourPaiement? retour;

  /// Vrai quand le paiement est annoncé réussi mais que la base montre encore
  /// l'ancien statut : le webhook n'est pas encore passé. L'écran le dit et
  /// relit une fois de plus, au lieu de tourner indéfiniment.
  final bool statutEnAttente;

  bool get enCours => formuleEnCours != null || portailEnCours;

  VueAbonnement copyWith({
    EtatAbonnement? etat,
    FormuleAbonnement? Function()? formuleEnCours,
    bool? portailEnCours,
    String? Function()? echec,
    RetourPaiement? Function()? retour,
    bool? statutEnAttente,
  }) => VueAbonnement(
    etat: etat ?? this.etat,
    formuleEnCours: formuleEnCours == null
        ? this.formuleEnCours
        : formuleEnCours(),
    portailEnCours: portailEnCours ?? this.portailEnCours,
    echec: echec == null ? this.echec : echec(),
    retour: retour == null ? this.retour : retour(),
    statutEnAttente: statutEnAttente ?? this.statutEnAttente,
  );
}

/// L'abonnement de la caserne courante.
///
/// Auto-disposé : l'écran est rare et deux adjoints peuvent le regarder en même
/// temps. Rouvrir relit, plutôt que de rejouer un état d'il y a dix minutes.
class AbonnementController extends AsyncNotifier<VueAbonnement?> {
  /// Le délai avant la seconde relecture, quand le webhook n'est pas encore
  /// passé. Assez long pour qu'il ait eu le temps d'arriver, assez court pour
  /// qu'on ne quitte pas l'écran avant.
  static const Duration delaiRelecture = Duration(seconds: 10);

  Timer? _relecture;

  @override
  Future<VueAbonnement?> build() async {
    ref.onDispose(() => _relecture?.cancel());

    final appartenance = ref.watch(appartenanceCouranteProvider);
    if (appartenance == null || !appartenance.estAdmin) return null;

    final etat = await ref
        .read(abonnementRepositoryProvider)
        .lire(appartenance.stationId);
    return VueAbonnement(etat: etat);
  }

  /// Relit l'état. Appelée par « Réessayer », par le bouton de relecture et au
  /// retour du prestataire.
  Future<void> relire() async {
    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    if (stationId == null) return;

    final precedent = state.value;
    state = const AsyncValue<VueAbonnement?>.loading();
    state = await AsyncValue.guard(() async {
      final etat = await ref.read(abonnementRepositoryProvider).lire(stationId);
      return VueAbonnement(etat: etat, retour: precedent?.retour);
    });
  }

  /// Prend en compte le paramètre `?paiement=` de l'URL au retour du
  /// prestataire.
  ///
  /// **Le paramètre n'est jamais cru sur parole** : il déclenche une relecture,
  /// pas un changement d'état. C'est le webhook qui écrit, et il peut arriver
  /// après le navigateur.
  Future<void> prendreEnCompteRetour(RetourPaiement retour) async {
    final vue = state.value;
    if (vue == null) return;

    state = AsyncValue<VueAbonnement?>.data(
      vue.copyWith(retour: () => retour, echec: () => null),
    );

    if (retour == RetourPaiement.annule) return;

    await relire();

    final apres = state.value;
    if (apres == null) return;

    // Toujours pas abonnée : le webhook n'est pas encore passé. On le dit, et
    // on relit une fois de plus — jamais de sablier infini.
    if (apres.etat.abonnement.statut != StatutAbonnement.actif) {
      state = AsyncValue<VueAbonnement?>.data(
        apres.copyWith(statutEnAttente: true),
      );
      _relecture?.cancel();
      _relecture = Timer(delaiRelecture, () => unawaited(relire()));
    }
  }

  /// Ouvre la page de paiement pour une formule.
  Future<ResultatAbonnement> souscrire(FormuleAbonnement formule) => _ouvrir(
    marquer: (VueAbonnement vue) => vue.copyWith(formuleEnCours: () => formule),
    action: (AbonnementRepository depot, String stationId) =>
        depot.ouvrirPaiement(stationId: stationId, formule: formule),
  );

  /// Ouvre le portail de gestion.
  Future<ResultatAbonnement> gerer() => _ouvrir(
    marquer: (VueAbonnement vue) => vue.copyWith(portailEnCours: true),
    action: (AbonnementRepository depot, String stationId) =>
        depot.ouvrirPortail(stationId),
  );

  Future<ResultatAbonnement> _ouvrir({
    required VueAbonnement Function(VueAbonnement) marquer,
    required Future<String> Function(AbonnementRepository, String) action,
  }) async {
    final vue = state.value;
    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    if (vue == null || stationId == null) {
      return const ResultatAbonnement(
        reussi: false,
        message: AppStrings.abonnementEchecGenerique,
      );
    }

    state = AsyncValue<VueAbonnement?>.data(
      marquer(vue).copyWith(echec: () => null, retour: () => null),
    );

    try {
      final adresse = await action(
        ref.read(abonnementRepositoryProvider),
        stationId,
      );

      final ouverte = ref.read(ouvertureExterneProvider)(adresse);
      state = AsyncValue<VueAbonnement?>.data(_repos(vue));

      // Un onglet bloqué en silence laisserait un chef de centre devant un
      // bouton qui ne fait rien : on le dit, et le message nomme la sortie.
      return ouverte
          ? const ResultatAbonnement(
              reussi: true,
              message: AppStrings.abonnementRedirection,
            )
          : _echouer(vue, AppStrings.abonnementOngletBloque);
    } on EchecAbonnement catch (echec) {
      return _echouer(vue, echec.message);
    } on Object {
      return _echouer(vue, AppStrings.abonnementEchecGenerique);
    }
  }

  ResultatAbonnement _echouer(VueAbonnement vue, String message) {
    state = AsyncValue<VueAbonnement?>.data(
      _repos(vue).copyWith(echec: () => message),
    );
    return ResultatAbonnement(reussi: false, message: message);
  }

  static VueAbonnement _repos(VueAbonnement vue) =>
      vue.copyWith(formuleEnCours: () => null, portailEnCours: false);
}

/// Le verdict d'une action d'abonnement, prêt à annoncer.
@immutable
class ResultatAbonnement {
  const ResultatAbonnement({required this.reussi, required this.message});

  final bool reussi;
  final String message;
}

final AsyncNotifierProvider<AbonnementController, VueAbonnement?>
abonnementControllerProvider =
    AsyncNotifierProvider<AbonnementController, VueAbonnement?>(
      AbonnementController.new,
      isAutoDispose: true,
    );
