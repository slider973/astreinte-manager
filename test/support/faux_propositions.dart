import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/propositions/data/propositions_repository.dart';
import 'package:astreinte_sp/features/propositions/domain/proposition.dart';

/// Une proposition toute faite, proposée il y a deux heures.
Proposition proposition({
  required String id,
  required DateTime jour,
  CreneauType creneau = CreneauType.nuit,
  String creneauId = 'c-1',
  String planningId = 'plan-1',
  PlanningEtat planningEtat = PlanningEtat.publie,
  DateTime? proposeeLe,
  int relances = 0,
  DateTime? derniereRelance,
}) => Proposition(
  id: id,
  creneauId: creneauId,
  planningId: planningId,
  jour: jour,
  creneau: creneau,
  planningEtat: planningEtat,
  proposeeLe: proposeeLe ?? DateTime.now().subtract(const Duration(hours: 2)),
  relances: relances,
  derniereRelance: derniereRelance,
);

/// Un [PropositionsRepository] sans réseau.
///
/// Il rejoue **la** règle de la base qui décide de tout cet écran : une
/// réponse ne touche que `status` et, au refus, `decline_reason`. La charge
/// utile réellement envoyée est conservée dans [chargesEnvoyees], et un test
/// s'en sert pour échouer si une colonne de plus s'y glissait un jour
/// (`design/021 § 3`).
class FauxPropositionsRepository implements PropositionsRepository {
  FauxPropositionsRepository({
    List<Proposition>? propositions,
    this.erreurLecture,
    this.erreurReponse,
    this.disparue = false,
    this.etatApresReponse,
  }) : _propositions = <Proposition>[...?propositions];

  List<Proposition> _propositions;

  ErreurProposition? erreurLecture;
  ErreurProposition? erreurReponse;

  /// Vrai quand la base répondra « zéro ligne touchée » : l'attribution n'est
  /// plus `proposed`.
  bool disparue;

  /// Ce que [etatPlanning] rendra. `null` : le planning n'est pas relu, ou il
  /// n'existe plus.
  PlanningEtat? etatApresReponse;

  int lectures = 0;

  /// Les charges utiles envoyées, dans l'ordre. **C'est le garde-fou du
  /// ticket.**
  final List<Map<String, dynamic>> chargesEnvoyees = <Map<String, dynamic>>[];

  final List<String> planningsRelus = <String>[];

  /// Remplace la liste servie à la prochaine lecture.
  void definir(List<Proposition> propositions) =>
      _propositions = <Proposition>[...propositions];

  @override
  Future<List<Proposition>> lister({
    required String userId,
    required String stationId,
  }) async {
    lectures++;
    final echec = erreurLecture;
    if (echec != null) throw EchecProposition(echec);
    // Le même tri que `SupabasePropositionsRepository` : une proposition d'un
    // mois archivé n'est plus répondable, donc elle n'est plus listée
    // (ticket 044).
    return <Proposition>[
      for (final proposition in _propositions)
        if (proposition.repondable) proposition,
    ]..sort((Proposition a, Proposition b) => a.comparer(b));
  }

  @override
  Future<ResultatReponse> repondre({
    required String attributionId,
    required bool accepte,
    String? motif,
  }) async {
    final echec = erreurReponse;
    if (echec != null) throw EchecProposition(echec);

    // Exactement la charge que construit `SupabasePropositionsRepository`.
    final charge = <String, dynamic>{
      'status': accepte ? 'accepted' : 'declined',
    };
    final propre = motif?.trim();
    if (!accepte && propre != null && propre.isNotEmpty) {
      charge['decline_reason'] = propre;
    }
    chargesEnvoyees.add(charge);

    if (disparue) return ResultatReponse.disparue;

    _propositions = <Proposition>[
      for (final existante in _propositions)
        if (existante.id != attributionId) existante,
    ];
    return ResultatReponse.enregistree;
  }

  @override
  Future<PlanningEtat?> etatPlanning(String planningId) async {
    planningsRelus.add(planningId);
    return etatApresReponse;
  }
}
