import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `FutureProviderFamily` n'est pas dans l'export principal de Riverpod 3 : il
// vit dans `misc.dart`. Il est nommé ici parce que tous les providers du
// projet portent leur type, et qu'une famille inférée `dynamic` casse le
// typage de `ref.watch` chez l'appelant.
import 'package:flutter_riverpod/misc.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../dispos/domain/dispos_providers.dart';
import '../../dispos/domain/periode_saisie.dart';
import '../data/periodes_repository.dart';
import 'taux_saisie.dart';

/// Le dépôt des périodes. Surchargé par un faux dans les tests.
final Provider<PeriodesRepository> periodesRepositoryProvider =
    Provider<PeriodesRepository>(
      (ref) => SupabasePeriodesRepository(ref.watch(supabaseClientProvider)),
    );

/// Ce que l'écran « Périodes » affiche : les mois de la caserne, du plus
/// ancien au plus récent.
@immutable
class EtatPeriodes {
  const EtatPeriodes({this.periodes = const <PeriodeSaisie>[]});

  final List<PeriodeSaisie> periodes;

  bool get vide => periodes.isEmpty;

  /// Les mois qui restent à vivre, **du plus proche au plus lointain** :
  /// c'est là que l'admin agit.
  ///
  /// Le mois courant en fait partie : il n'est pas écoulé tant qu'il n'est pas
  /// fini, et son planning peut encore bouger.
  List<PeriodeSaisie> aVenir(DateTime maintenant) => <PeriodeSaisie>[
    for (final periode in periodes)
      if (!_estEcoule(periode, maintenant)) periode,
  ];

  /// Les mois finis, **du plus récent au plus ancien** : on remonte le
  /// registre, on ne le relit pas depuis le début.
  List<PeriodeSaisie> ecoulees(DateTime maintenant) => <PeriodeSaisie>[
    for (final periode in periodes.reversed)
      if (_estEcoule(periode, maintenant)) periode,
  ];

  /// La période d'un mois donné, ou `null` s'il n'est pas encore ouvert.
  PeriodeSaisie? pour(int annee, int mois) {
    for (final periode in periodes) {
      if (periode.annee == annee && periode.mois == mois) return periode;
    }
    return null;
  }

  static bool _estEcoule(PeriodeSaisie periode, DateTime maintenant) =>
      periode.annee < maintenant.year ||
      (periode.annee == maintenant.year && periode.mois < maintenant.month);

  EtatPeriodes avec(PeriodeSaisie periode) {
    final autres = <PeriodeSaisie>[
      for (final existante in periodes)
        if (existante.id != periode.id) existante,
      periode,
    ]..sort((a, b) => a.cle.compareTo(b.cle));
    return EtatPeriodes(periodes: List<PeriodeSaisie>.unmodifiable(autres));
  }
}

/// Le verdict d'une action sur une période, prêt à annoncer.
@immutable
class ResultatPeriode {
  const ResultatPeriode({required this.reussi, required this.message});

  final bool reussi;
  final String message;
}

/// Les mois de la caserne courante.
///
/// Auto-disposé : deux adjoints peuvent administrer la même caserne, et un
/// écran rouvert doit lire l'état réel plutôt que celui d'il y a dix minutes.
class PeriodesController extends AsyncNotifier<EtatPeriodes> {
  @override
  Future<EtatPeriodes> build() async {
    final appartenance = ref.watch(appartenanceCouranteProvider);
    if (appartenance == null || !appartenance.estAdmin) {
      return const EtatPeriodes();
    }
    return _lire(appartenance.stationId);
  }

  Future<EtatPeriodes> _lire(String stationId) async {
    final periodes = await ref.read(periodesRepositoryProvider).lister(stationId);
    return EtatPeriodes(periodes: List<PeriodeSaisie>.unmodifiable(periodes));
  }

  /// Relit la liste **en la gardant à l'écran** : un rafraîchissement ne vide
  /// pas la page sous les yeux de qui l'utilise. Les comptes de saisie sont
  /// jetés en même temps, sans quoi « Relire » mentirait sur la moitié de
  /// l'écran.
  Future<void> rafraichir() async {
    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    if (stationId == null) return;

    ref.invalidate(membresActifsProvider);
    ref.invalidate(tauxSaisieProvider);
    state = await AsyncValue.guard(() => _lire(stationId));
  }

  /// Verrouille le mois maintenant. La date de verrouillage n'est **jamais**
  /// envoyée : la base la pose.
  Future<ResultatPeriode> verrouiller(PeriodeSaisie periode) => _agir(
    () => ref.read(periodesRepositoryProvider).verrouiller(periode.id),
    (PeriodeSaisie ecrite) =>
        AppStrings.periodeVerrouilleeConfirmation(ecrite.libelle),
  );

  /// Rouvre le mois **en repoussant sa date limite dans le même geste**.
  Future<ResultatPeriode> rouvrir(
    PeriodeSaisie periode,
    DateTime dateLimite,
  ) => _agir(
    () => ref
        .read(periodesRepositoryProvider)
        .rouvrir(periodeId: periode.id, dateLimite: dateLimite),
    (PeriodeSaisie ecrite) => AppStrings.periodeRouverteConfirmation(
      ecrite.libelle,
      formaterDateLongue(ecrite.dateLimite),
    ),
  );

  /// Ouvre un mois à la saisie. La fonction `create_period` est idempotente :
  /// un mois déjà ouvert est rendu tel quel, et l'écran le dit au lieu de
  /// feindre une création.
  Future<ResultatPeriode> creer(int annee, int mois) {
    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    if (stationId == null) {
      return Future<ResultatPeriode>.value(
        const ResultatPeriode(
          reussi: false,
          message: AppStrings.periodeRefusDroits,
        ),
      );
    }

    final deja = state.value?.pour(annee, mois) != null;
    return _agir(
      () => ref
          .read(periodesRepositoryProvider)
          .creer(stationId: stationId, annee: annee, mois: mois),
      (PeriodeSaisie ecrite) => deja
          ? AppStrings.periodeDejaOuverteConfirmation(ecrite.libelle)
          : AppStrings.periodeCreeeConfirmation(ecrite.libelle),
    );
  }

  /// Le seul chemin d'écriture : jouer l'action, remplacer la période dans la
  /// liste par **celle que la base a rendue**, annoncer.
  ///
  /// Rien n'est deviné de ce que la base a écrit : `locked_at` est posé par un
  /// déclencheur, et l'écran affiche la valeur relue, pas la valeur espérée.
  Future<ResultatPeriode> _agir(
    Future<PeriodeSaisie> Function() action,
    String Function(PeriodeSaisie) annonce,
  ) async {
    final etat = state.value;
    if (etat == null) {
      return const ResultatPeriode(
        reussi: false,
        message: AppStrings.periodeEchecGenerique,
      );
    }

    try {
      final ecrite = await action();
      state = AsyncValue<EtatPeriodes>.data(etat.avec(ecrite));

      // L'écran « Mon mois » lit sa propre liste de périodes, et il la garde
      // pour la session. Sans cette invalidation, l'admin qui vient de rouvrir
      // un mois retrouve son sélecteur en disant « Verrouillé ». Vu en vrai
      // dans Chrome.
      ref.invalidate(periodesProvider);

      return ResultatPeriode(reussi: true, message: annonce(ecrite));
    } on EchecPeriodes catch (echec) {
      return ResultatPeriode(reussi: false, message: echec.message);
    } on Object {
      return const ResultatPeriode(
        reussi: false,
        message: AppStrings.periodeEchecGenerique,
      );
    }
  }
}

final AsyncNotifierProvider<PeriodesController, EtatPeriodes>
periodesControllerProvider =
    AsyncNotifierProvider<PeriodesController, EtatPeriodes>(
      PeriodesController.new,
      isAutoDispose: true,
    );

/// Les membres actifs de la caserne, lus **une fois** pour toute la liste :
/// c'est le dénominateur commun de tous les taux de saisie.
final FutureProvider<Set<String>> membresActifsProvider =
    FutureProvider<Set<String>>((ref) async {
      final appartenance = ref.watch(appartenanceCouranteProvider);
      if (appartenance == null || !appartenance.estAdmin) {
        return const <String>{};
      }
      return ref
          .watch(periodesRepositoryProvider)
          .membresActifs(appartenance.stationId);
    }, isAutoDispose: true);

/// Le taux de saisie d'un mois, **compté à la demande**.
///
/// Une instance par mois affiché, et une seule requête chacune. C'est ce qui
/// rend l'écran tenable : `SliverList.builder` ne construit que les lignes
/// visibles, donc un admin qui ne défile pas ne paie que les mois qu'il voit
/// (`design/014 § 7`).
final FutureProviderFamily<TauxSaisie, CleMois> tauxSaisieProvider =
    FutureProvider.family<TauxSaisie, CleMois>((ref, cle) async {
      final appartenance = ref.watch(appartenanceCouranteProvider);
      if (appartenance == null || !appartenance.estAdmin) {
        return const TauxSaisie(saisis: 0, effectif: 0);
      }

      final actifs = await ref.watch(membresActifsProvider.future);
      final saisis = await ref
          .read(periodesRepositoryProvider)
          .membresAyantSaisi(
            stationId: appartenance.stationId,
            annee: cle.annee,
            mois: cle.mois,
          );

      // Le comptage ne se refait pas quand la ligne sort de l'écran et y
      // revient : il est gardé tant que l'écran vit.
      ref.keepAlive();
      return TauxSaisie(
        saisis: saisis.intersection(actifs).length,
        effectif: actifs.length,
      );
    }, isAutoDispose: true);
