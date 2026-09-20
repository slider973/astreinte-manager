import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  const EtatPeriodes({this.periodes = const <PeriodeSaisie>[], this.taux});

  final List<PeriodeSaisie> periodes;

  /// Le taux de saisie par identifiant de période, lu en **une** requête
  /// (`v_period_completion`). `null` quand le comptage n'a pas pu être lu :
  /// la liste reste utilisable, chaque ligne dit que son compte manque.
  final Map<String, TauxSaisie>? taux;

  bool get vide => periodes.isEmpty;

  /// Le taux d'une période, ou `null` s'il n'a pas pu être lu.
  TauxSaisie? tauxDe(PeriodeSaisie periode) => taux?[periode.id];

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
    return EtatPeriodes(
      periodes: List<PeriodeSaisie>.unmodifiable(autres),
      taux: taux,
    );
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

  /// Deux requêtes, lancées ensemble : la liste des mois, et leurs taux de
  /// saisie.
  ///
  /// Le coût ne dépend plus de l'effectif de la caserne — deux nombres par
  /// période, comptés en base — mais du seul nombre de mois. Le chargement
  /// ligne par ligne du premier jet n'a donc plus lieu d'être.
  Future<EtatPeriodes> _lire(String stationId) async {
    final depot = ref.read(periodesRepositoryProvider);

    // Le comptage part en même temps que la liste, mais son échec ne fait pas
    // tomber l'écran : sans les mois il n'y a rien à montrer, sans les taux il
    // reste tout le reste.
    final tauxEnVol = _taux(depot, stationId);
    final periodes = await depot.lister(stationId);

    return EtatPeriodes(
      periodes: List<PeriodeSaisie>.unmodifiable(periodes),
      taux: await tauxEnVol,
    );
  }

  Future<Map<String, TauxSaisie>?> _taux(
    PeriodesRepository depot,
    String stationId,
  ) async {
    try {
      return await depot.tauxParPeriode(stationId);
    } on Object {
      return null;
    }
  }

  /// Relit la liste **en la gardant à l'écran** : un rafraîchissement ne vide
  /// pas la page sous les yeux de qui l'utilise. Les taux repartent avec elle,
  /// sans quoi « Relire » mentirait sur la moitié de l'écran.
  Future<void> rafraichir() async {
    final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
    if (stationId == null) return;

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
  Future<ResultatPeriode> rouvrir(PeriodeSaisie periode, DateTime dateLimite) =>
      _agir(
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

      // Ouvrir un mois ajoute une période, donc un taux qui n'était pas dans
      // la carte. Une requête de plus après une action rare, contre une ligne
      // qui afficherait « comptage indisponible » sur un mois qui vient de
      // naître.
      final stationId = ref.read(appartenanceCouranteProvider)?.stationId;
      final courant = state.value;
      if (stationId != null && courant != null) {
        final taux = await _taux(
          ref.read(periodesRepositoryProvider),
          stationId,
        );
        if (taux != null && ref.mounted) {
          state = AsyncValue<EtatPeriodes>.data(
            EtatPeriodes(periodes: courant.periodes, taux: taux),
          );
        }
      }

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
