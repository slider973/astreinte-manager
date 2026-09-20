import 'dart:async';

import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/planning/data/planning_repository.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/planning_mois.dart';

/// Un créneau tout fait.
CreneauPlanning creneau({
  required String id,
  required int jour,
  CreneauType creneau = CreneauType.jour,
  int effectifRequis = 1,
}) => CreneauPlanning(
  id: id,
  jour: jour,
  creneau: creneau,
  effectifRequis: effectifRequis,
);

/// Les créneaux d'un mois entier, un par jour et par créneau, nommés
/// `c-<jour>-<j|n>` pour qu'un test puisse les désigner sans les chercher.
List<CreneauPlanning> creneauxDuMois(int jours, {int effectifRequis = 1}) =>
    <CreneauPlanning>[
      for (var jour = 1; jour <= jours; jour++) ...<CreneauPlanning>[
        creneau(
          id: 'c-$jour-j',
          jour: jour,
          effectifRequis: effectifRequis,
        ),
        creneau(
          id: 'c-$jour-n',
          jour: jour,
          creneau: CreneauType.nuit,
          effectifRequis: effectifRequis,
        ),
      ],
    ];

const PlanningBrouillon planningBrouillon = PlanningBrouillon(
  id: 'plan-1',
  etat: PlanningEtat.brouillon,
);

/// Un [PlanningRepository] sans réseau, qui **rejoue les règles de la base**.
///
/// Trois d'entre elles comptent, et un faux qui les oublierait mentirait :
/// - `was_available` est calculé par la base, jamais par le client ;
/// - la contrainte `assignments_active_uniq` refuse deux attributions actives
///   du même membre sur le même créneau ;
/// - le canal temps réel diffuse ce que **les autres** écrivent, et une
///   suppression n'y porte que la clé primaire.
class FauxPlanningRepository implements PlanningRepository {
  FauxPlanningRepository({
    PlanningBrouillon? planning,
    List<CreneauPlanning>? creneaux,
    List<Attribution>? attributions,
    this.disponibles = const <String>{},
    this.erreurLecture,
    this.erreurEcriture,
    this.refuseSansLever = false,
    this.joursDuMoisACreer = 31,
    this.effectifACreer = 1,
  }) : _planning = planning,
       _creneaux = <CreneauPlanning>[...?creneaux],
       _attributions = <Attribution>[...?attributions];

  PlanningBrouillon? _planning;
  List<CreneauPlanning> _creneaux;
  final List<Attribution> _attributions;

  /// Les clés `<userId>@<creneauId>` sur lesquelles le membre est disponible.
  /// Tout le reste sera attribué avec `was_available = false`.
  Set<String> disponibles;

  ErreurPlanning? erreurLecture;
  ErreurPlanning? erreurEcriture;

  /// La politique filtre sans lever : la requête répond 200 et n'affecte rien.
  bool refuseSansLever;

  /// Ce que `create_schedule` produira : un créneau par jour et par créneau,
  /// avec l'effectif requis **des réglages de la caserne**, copié une fois.
  final int joursDuMoisACreer;
  final int effectifACreer;

  int lectures = 0;
  int creations = 0;

  final List<({String creneauId, String userId})> attributions =
      <({String creneauId, String userId})>[];

  /// Les attributions réellement posées, avec ce que la base y a inscrit —
  /// `was_available` compris.
  final List<Attribution> attributionsPosees = <Attribution>[];
  final List<String> retraits = <String>[];
  final List<({String creneauId, int effectif})> effectifs =
      <({String creneauId, int effectif})>[];

  final StreamController<EvenementPlanning> _canal =
      StreamController<EvenementPlanning>.broadcast();

  var _compteur = 0;

  /// Ce que l'autre poste vient de faire, poussé dans le canal.
  void diffuser(EvenementPlanning evenement) => _canal.add(evenement);

  /// Une attribution posée par quelqu'un d'autre.
  Attribution posePar({
    required String creneauId,
    required String userId,
    required String auteurId,
  }) {
    final attribution = Attribution(
      id: 'distante-${_compteur++}',
      creneauId: creneauId,
      userId: userId,
      auteurId: auteurId,
    );
    _attributions.add(attribution);
    diffuser(AttributionRecue(attribution));
    return attribution;
  }

  Future<void> fermer() => _canal.close();

  @override
  Future<PlanningMois> lire({
    required String stationId,
    required String periodeId,
  }) async {
    lectures++;
    final echec = erreurLecture;
    if (echec != null) throw EchecPlanning(echec);

    return PlanningMois(
      planning: _planning,
      creneaux: <CreneauPlanning>[..._creneaux],
      attributions: <Attribution>[..._attributions],
    );
  }

  @override
  Future<PlanningMois> creer({
    required String stationId,
    required String periodeId,
  }) async {
    creations++;
    final echec = erreurEcriture;
    if (echec != null) throw EchecPlanning(echec);

    _planning ??= planningBrouillon;
    if (_creneaux.isEmpty) {
      _creneaux = creneauxDuMois(
        joursDuMoisACreer,
        effectifRequis: effectifACreer,
      );
    }
    return lire(stationId: stationId, periodeId: periodeId);
  }

  @override
  Future<Attribution> attribuer({
    required String stationId,
    required String creneauId,
    required String userId,
  }) async {
    attributions.add((creneauId: creneauId, userId: userId));
    final echec = erreurEcriture;
    if (echec != null) throw EchecPlanning(echec);

    // La contrainte d'unicité de la base, rejouée : sans elle, le faux
    // laisserait passer ce que la base refuse.
    final existe = _attributions.any(
      (Attribution a) => a.creneauId == creneauId && a.userId == userId,
    );
    if (existe) throw const EchecPlanning(ErreurPlanning.dejaAttribue);

    final attribution = Attribution(
      id: 'a-${_compteur++}',
      creneauId: creneauId,
      userId: userId,
      // **Calculé, jamais déclaré** : c'est ce que fait le déclencheur.
      etaitDisponible: disponibles.contains('$userId@$creneauId'),
      auteurId: 'moi',
    );
    _attributions.add(attribution);
    attributionsPosees.add(attribution);
    return attribution;
  }

  @override
  Future<bool> retirer({required String attributionId}) async {
    retraits.add(attributionId);
    final echec = erreurEcriture;
    if (echec != null) throw EchecPlanning(echec);
    if (refuseSansLever) return false;

    _attributions.removeWhere((Attribution a) => a.id == attributionId);
    return true;
  }

  @override
  Future<bool> definirEffectif({
    required String creneauId,
    required int effectif,
  }) async {
    effectifs.add((creneauId: creneauId, effectif: effectif));
    final echec = erreurEcriture;
    if (echec != null) throw EchecPlanning(echec);
    if (refuseSansLever) return false;

    _creneaux = <CreneauPlanning>[
      for (final c in _creneaux)
        if (c.id == creneauId) c.avecEffectif(effectif) else c,
    ];
    return true;
  }

  @override
  Stream<EvenementPlanning> ecouter({required String stationId}) async* {
    yield const EtatCanalPlanning(branche: true);
    yield* _canal.stream;
  }
}
