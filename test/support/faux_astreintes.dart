import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/astreintes/data/astreintes_repository.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';

/// Une astreinte acceptée, toute faite.
Astreinte astreinte({
  required String id,
  required DateTime jour,
  CreneauType creneau = CreneauType.nuit,
  String creneauId = 'c-1',
  String planningId = 'plan-1',
  PlanningEtat planningEtat = PlanningEtat.valide,
  List<String> equipiers = const <String>[],
}) => Astreinte(
  id: id,
  creneauId: creneauId,
  planningId: planningId,
  jour: jour,
  creneau: creneau,
  planningEtat: planningEtat,
  equipiers: equipiers,
);

/// Un [AstreintesRepository] sans réseau.
class FauxAstreintesRepository implements AstreintesRepository {
  FauxAstreintesRepository({
    List<Astreinte>? astreintes,
    this.heures = HeuresAffichage.defaut,
    this.erreur,
    this.luLe,
  }) : _astreintes = <Astreinte>[...?astreintes];

  List<Astreinte> _astreintes;

  HeuresAffichage heures;

  /// L'échec levé à la lecture, ou `null`.
  ErreurAstreintes? erreur;

  /// L'horodatage rendu. `null` : l'instant de l'appel.
  DateTime? luLe;

  int lectures = 0;

  /// La borne demandée à chaque lecture. Le test du cache s'en sert pour
  /// vérifier que l'historique est borné côté serveur.
  final List<DateTime> bornes = <DateTime>[];

  void definir(List<Astreinte> astreintes) =>
      _astreintes = <Astreinte>[...astreintes];

  @override
  Future<MesAstreintes> lire({
    required String userId,
    required String stationId,
    required DateTime depuis,
  }) async {
    lectures++;
    bornes.add(depuis);
    final echec = erreur;
    if (echec != null) throw EchecAstreintes(echec);
    return MesAstreintes(
      astreintes: <Astreinte>[..._astreintes],
      heures: heures,
      luLe: luLe ?? DateTime.now(),
    );
  }
}
