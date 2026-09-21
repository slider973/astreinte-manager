import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../data/astreintes_repository.dart';
import '../data/cache_astreintes.dart';
import 'astreinte.dart';

/// Le dépôt des astreintes. Surchargé par un faux dans les tests.
final Provider<AstreintesRepository> astreintesRepositoryProvider =
    Provider<AstreintesRepository>(
      (ref) => SupabaseAstreintesRepository(ref.watch(supabaseClientProvider)),
    );

/// L'horloge de l'écran, injectable : « à venir » et « passé » se décident par
/// rapport à aujourd'hui, et un test qui dépendrait de la date du jour
/// échouerait le mois suivant.
final Provider<DateTime Function()> horlogeAstreintesProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// Combien d'historique est téléchargé.
///
/// L'historique n'est **jamais supprimé** (`docs/PRD.md § 7.6`), mais au-delà
/// d'un an une astreinte n'intéresse plus personne, et ce sont des centaines
/// de lignes que le cache porterait à chaque ouverture.
const Duration historiqueAstreintes = Duration(days: 365);

/// Ce que l'écran « Mes astreintes » affiche.
@immutable
class EtatAstreintes {
  const EtatAstreintes({
    this.donnees = const MesAstreintes(),
    this.depuisCache = false,
    this.echec,
  });

  final MesAstreintes donnees;

  /// Vrai quand ce qui est à l'écran vient du **stockage local** et n'a pas
  /// encore été confirmé par une lecture réussie. C'est ce qui déclenche le
  /// bandeau de fraîcheur.
  final bool depuisCache;

  /// La phrase de la dernière lecture qui a échoué **alors qu'il y avait déjà
  /// quelque chose à l'écran**. Une lecture qui échoue sur un écran vide lève
  /// à la place : c'est le seul cas où l'écran n'a rien à dire.
  final String? echec;

  bool get vide => donnees.astreintes.isEmpty;

  EtatAstreintes copie({
    MesAstreintes? donnees,
    bool? depuisCache,
    String? Function()? echec,
  }) => EtatAstreintes(
    donnees: donnees ?? this.donnees,
    depuisCache: depuisCache ?? this.depuisCache,
    echec: echec == null ? this.echec : echec(),
  );
}

/// Les astreintes du membre connecté.
///
/// **Le cache est la première source, la requête la seconde** : `build` rend
/// ce qui est gardé sans attendre le réseau, et l'écran demande le
/// rafraîchissement dès sa première image. C'est la règle d'architecture de cet
/// écran (`design/027 § 3`), pas une optimisation.
///
/// **Non auto-disposé** : passer sur « Mon mois » et revenir ne doit pas
/// rejouer un squelette sur l'écran le plus consulté du produit.
class AstreintesController extends AsyncNotifier<EtatAstreintes> {
  @override
  Future<EtatAstreintes> build() async {
    final session = ref.watch(sessionProvider).value;
    final appartenance = ref.watch(appartenanceCouranteProvider);
    if (session == null || appartenance == null) {
      return const EtatAstreintes();
    }

    final garde = await ref
        .read(cacheAstreintesProvider)
        .lire(stationId: appartenance.stationId, userId: session.userId);
    if (garde != null) {
      // L'écran est déjà lisible. C'est lui qui demandera mieux, à sa première
      // image : poser la requête ici, avant que `state` existe, serait courir
      // contre la fin de `build`.
      return EtatAstreintes(donnees: garde, depuisCache: true);
    }

    final donnees = await _lire(
      userId: session.userId,
      stationId: appartenance.stationId,
    );
    await _garder(donnees);
    return EtatAstreintes(donnees: donnees);
  }

  Future<MesAstreintes> _lire({
    required String userId,
    required String stationId,
  }) {
    final maintenant = ref.read(horlogeAstreintesProvider)();
    return ref
        .read(astreintesRepositoryProvider)
        .lire(
          userId: userId,
          stationId: stationId,
          depuis: maintenant.subtract(historiqueAstreintes),
        );
  }

  Future<void> _garder(MesAstreintes donnees) async {
    final session = ref.read(sessionProvider).value;
    final appartenance = ref.read(appartenanceCouranteProvider);
    if (session == null || appartenance == null) return;
    await ref
        .read(cacheAstreintesProvider)
        .ecrire(
          stationId: appartenance.stationId,
          userId: session.userId,
          donnees: donnees,
        );
  }

  /// Relit **en gardant l'écran à l'écran**.
  ///
  /// Un rafraîchissement ne vide jamais la page sous les yeux de qui la lit :
  /// il remplace ou il pose un bandeau, jamais les deux, jamais rien d'autre.
  Future<void> rafraichir() async {
    final session = ref.read(sessionProvider).value;
    final appartenance = ref.read(appartenanceCouranteProvider);
    if (session == null || appartenance == null) return;

    final courant = state.value ?? const EtatAstreintes();
    try {
      final donnees = await _lire(
        userId: session.userId,
        stationId: appartenance.stationId,
      );
      if (!ref.mounted) return;
      await _garder(donnees);
      if (!ref.mounted) return;
      state = AsyncValue<EtatAstreintes>.data(
        EtatAstreintes(donnees: donnees),
      );
    } on EchecAstreintes catch (echec) {
      if (!ref.mounted) return;
      // `jamaisLu` distingue « je n'ai rien » de « je n'ai rien lu » : une
      // liste vide **lue** est un état vide légitime, pas une erreur.
      if (courant.donnees.jamaisLu) {
        state = AsyncValue<EtatAstreintes>.error(echec, StackTrace.current);
        return;
      }
      state = AsyncValue<EtatAstreintes>.data(
        courant.copie(depuisCache: true, echec: () => echec.message),
      );
    }
  }
}

final AsyncNotifierProvider<AstreintesController, EtatAstreintes>
astreintesControllerProvider =
    AsyncNotifierProvider<AstreintesController, EtatAstreintes>(
      AstreintesController.new,
    );

/// L'état du repli des passées. Un provider plutôt qu'un `setState` : la
/// liste aplatie en dépend, et elle est mémorisée.
final NotifierProvider<PasseesOuvertes, bool> passeesOuvertesProvider =
    NotifierProvider<PasseesOuvertes, bool>(PasseesOuvertes.new);

/// Le repli des passées est **fermé à chaque ouverture de l'application** :
/// l'écran s'ouvre sur l'avenir, le passé est une consultation délibérée.
class PasseesOuvertes extends Notifier<bool> {
  @override
  bool build() => false;

  void basculer() => state = !state;
}

/// Les éléments réellement affichés — en-têtes de mois et repli compris —
/// construits **une fois par état** et mémorisés.
final Provider<List<ElementAstreintes>> elementsAstreintesProvider =
    Provider<List<ElementAstreintes>>((ref) {
      final etat = ref.watch(astreintesControllerProvider).value;
      if (etat == null) return const <ElementAstreintes>[];
      return aplatirAstreintes(
        donnees: etat.donnees,
        aujourdhui: ref.watch(horlogeAstreintesProvider)(),
        passeesOuvertes: ref.watch(passeesOuvertesProvider),
      );
    });
