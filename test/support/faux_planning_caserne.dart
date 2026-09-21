import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/astreintes/data/planning_caserne_repository.dart';
import 'package:astreinte_sp/features/astreintes/domain/astreinte.dart';
import 'package:astreinte_sp/features/astreintes/domain/planning_caserne.dart';

/// Un mois atteignable, tout fait.
MoisPlanning moisPlanning({
  required int annee,
  required int mois,
  PlanningEtat etat = PlanningEtat.valide,
  String? planningId,
}) => MoisPlanning(
  planningId: planningId ?? 'plan-$annee-$mois',
  annee: annee,
  mois: mois,
  etat: etat,
);

/// Un créneau du registre, tout fait.
CreneauCaserne creneauCaserne({
  required String id,
  CreneauType creneau = CreneauType.nuit,
  int requis = 2,
  List<String> noms = const <String>[],
  bool moi = false,
  int anonymes = 0,
}) => CreneauCaserne(
  id: id,
  creneau: creneau,
  requis: requis,
  noms: noms,
  moi: moi,
  anonymes: anonymes,
);

/// Un planning de mois, tout fait. [journees] est donné jour par jour.
PlanningCaserne planningCaserne({
  required MoisPlanning mois,
  Map<int, List<CreneauCaserne>> journees = const <int, List<CreneauCaserne>>{},
  HeuresAffichage heures = HeuresAffichage.defaut,
  DateTime? luLe,
}) => PlanningCaserne(
  mois: mois,
  journees: assemblerJournees(
    etat: mois.etat,
    parJour: <DateTime, List<CreneauCaserne>>{
      for (final entree in journees.entries)
        DateTime(mois.annee, mois.mois, entree.key): entree.value,
    },
  ),
  heures: heures,
  luLe: luLe ?? DateTime(2026, 10, 15, 9),
);

/// Un [PlanningCaserneRepository] sans réseau.
class FauxPlanningCaserneRepository implements PlanningCaserneRepository {
  FauxPlanningCaserneRepository({
    List<MoisPlanning>? mois,
    Map<String, PlanningCaserne>? plannings,
    this.erreurMois,
    this.erreurLecture,
  }) : _mois = <MoisPlanning>[...?mois],
       _plannings = <String, PlanningCaserne>{...?plannings};

  List<MoisPlanning> _mois;
  final Map<String, PlanningCaserne> _plannings;

  /// L'échec levé à la lecture de la liste des mois, ou `null`.
  ErreurPlanningCaserne? erreurMois;

  /// L'échec levé à la lecture d'un mois, ou `null`.
  ErreurPlanningCaserne? erreurLecture;

  int lecturesMois = 0;
  int lecturesPlanning = 0;

  /// Les mois réellement demandés, dans l'ordre. Le test du sélecteur s'en sert
  /// pour vérifier qu'un aller-retour ne redemande pas ce qui est déjà gardé.
  final List<String> demandes = <String>[];

  void definirMois(List<MoisPlanning> mois) =>
      _mois = <MoisPlanning>[...mois];

  void definirPlanning(PlanningCaserne planning) =>
      _plannings[planning.mois.cle] = planning;

  /// Retire un mois du dépôt sans le retirer de la liste : le cas de course
  /// entre la liste des mois et la lecture d'un mois.
  void oublierPlanning(String cleMois) => _plannings.remove(cleMois);

  @override
  Future<List<MoisPlanning>> moisLisibles({required String stationId}) async {
    lecturesMois++;
    final echec = erreurMois;
    if (echec != null) throw EchecPlanningCaserne(echec);
    return List<MoisPlanning>.unmodifiable(_mois);
  }

  @override
  Future<PlanningCaserne?> lireMois({
    required String stationId,
    required String userId,
    required MoisPlanning mois,
  }) async {
    lecturesPlanning++;
    demandes.add(mois.cle);
    final echec = erreurLecture;
    if (echec != null) throw EchecPlanningCaserne(echec);
    return _plannings[mois.cle];
  }
}
