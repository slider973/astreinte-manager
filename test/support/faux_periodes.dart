import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/periodes/data/periodes_repository.dart';
import 'package:astreinte_sp/features/periodes/domain/taux_saisie.dart';

import 'faux_invitations.dart';

/// Un [PeriodesRepository] sans réseau, qui **rejoue les règles de la base**.
///
/// Les deux règles qui comptent sont reproduites ici, sinon le faux
/// mentirait : une réouverture dont la date limite est déjà passée est
/// refusée (`period_reopen_deadline_passed`), et `create_period` est
/// idempotente.
class FauxPeriodesRepository implements PeriodesRepository {
  FauxPeriodesRepository({
    List<PeriodeSaisie>? periodes,
    Set<String>? actifs,
    Map<String, Set<String>>? saisies,
    this.erreurLecture = false,
    this.erreurTaux = false,
    this.erreurEcriture,
  }) : periodes = <PeriodeSaisie>[...?periodes],
       actifs = actifs ?? const <String>{'u1', 'u2', 'u3', 'u4'},
       saisies = saisies ?? const <String, Set<String>>{};

  List<PeriodeSaisie> periodes;

  /// Les membres actifs de la caserne, comme les compterait
  /// `v_period_completion`.
  Set<String> actifs;

  /// Les membres ayant saisi, par clé de mois (`2026-11`).
  Map<String, Set<String>> saisies;

  bool erreurLecture;

  /// Le comptage échoue, la liste non : l'écran doit rester utilisable.
  bool erreurTaux;

  /// Le refus opposé à la prochaine écriture, ou `null`.
  ErreurPeriodes? erreurEcriture;

  int lectures = 0;
  int comptages = 0;

  /// Tout ce qui a été demandé, dans l'ordre.
  final List<String> verrouillages = <String>[];
  final List<({String id, DateTime limite})> reouvertures =
      <({String id, DateTime limite})>[];
  final List<({int annee, int mois})> creations = <({int annee, int mois})>[];

  @override
  Future<List<PeriodeSaisie>> lister(String stationId) async {
    lectures++;
    if (erreurLecture) throw const EchecPeriodes(ErreurPeriodes.inconnue);
    return <PeriodeSaisie>[...periodes];
  }

  /// Le comptage de `v_period_completion` : **une** requête pour toutes les
  /// périodes, et deux nombres par ligne.
  ///
  /// Le faux compte comme la vue : le numérateur est intersecté avec les
  /// membres actifs, et une caserne sans membre actif rend `0` et `0` plutôt
  /// qu'une ligne absente.
  @override
  Future<Map<String, TauxSaisie>> tauxParPeriode(String stationId) async {
    comptages++;
    if (erreurLecture || erreurTaux) {
      throw const EchecPeriodes(ErreurPeriodes.inconnue);
    }

    return <String, TauxSaisie>{
      for (final periode in periodes)
        periode.id: TauxSaisie(
          saisis: (saisies[periode.cle] ?? const <String>{})
              .intersection(actifs)
              .length,
          effectif: actifs.length,
        ),
    };
  }

  @override
  Future<PeriodeSaisie> verrouiller(String periodeId) async {
    verrouillages.add(periodeId);
    _verifier();

    final avant = _pour(periodeId);
    return _remplacer(
      PeriodeSaisie(
        id: avant.id,
        stationId: avant.stationId,
        annee: avant.annee,
        mois: avant.mois,
        statut: PeriodeEtat.verrouillee,
        dateLimite: avant.dateLimite,
        // Posé par le déclencheur, jamais par le client.
        verrouilleeLe: DateTime.now(),
      ),
    );
  }

  @override
  Future<PeriodeSaisie> rouvrir({
    required String periodeId,
    required DateTime dateLimite,
  }) async {
    reouvertures.add((id: periodeId, limite: dateLimite));
    _verifier();

    // `periods_guard_transition` : rouvrir, c'est dire jusqu'à quand.
    if (!dateLimite.isAfter(DateTime.now())) {
      throw const EchecPeriodes(ErreurPeriodes.dateLimitePassee);
    }

    final avant = _pour(periodeId);
    return _remplacer(
      PeriodeSaisie(
        id: avant.id,
        stationId: avant.stationId,
        annee: avant.annee,
        mois: avant.mois,
        statut: PeriodeEtat.ouverte,
        dateLimite: dateLimite,
      ),
    );
  }

  @override
  Future<PeriodeSaisie> creer({
    required String stationId,
    required int annee,
    required int mois,
  }) async {
    creations.add((annee: annee, mois: mois));
    _verifier();

    // Idempotente : le mois existant est rendu tel quel.
    for (final periode in periodes) {
      if (periode.annee == annee && periode.mois == mois) return periode;
    }

    final creee = PeriodeSaisie(
      id: 'periode-$annee-$mois',
      stationId: stationId,
      annee: annee,
      mois: mois,
      statut: PeriodeEtat.ouverte,
      dateLimite: DateTime(annee, mois - 1, 15, 23, 59, 59),
    );
    periodes = <PeriodeSaisie>[...periodes, creee];
    return creee;
  }

  void _verifier() {
    final echec = erreurEcriture;
    if (echec != null) throw EchecPeriodes(echec);
  }

  PeriodeSaisie _pour(String id) =>
      periodes.firstWhere((PeriodeSaisie p) => p.id == id);

  PeriodeSaisie _remplacer(PeriodeSaisie ecrite) {
    periodes = <PeriodeSaisie>[
      for (final periode in periodes)
        if (periode.id == ecrite.id) ecrite else periode,
    ];
    return ecrite;
  }
}

/// Une période verrouillée dont la date limite est passée depuis [jours].
PeriodeSaisie periodeFermeeDepuis({
  required int annee,
  required int mois,
  int jours = 5,
}) {
  final limite = DateTime.now().subtract(Duration(days: jours));
  return PeriodeSaisie(
    id: 'periode-$annee-$mois',
    stationId: stationTest,
    annee: annee,
    mois: mois,
    statut: PeriodeEtat.verrouillee,
    dateLimite: DateTime(limite.year, limite.month, limite.day, 23, 59, 59),
    verrouilleeLe: limite,
  );
}
