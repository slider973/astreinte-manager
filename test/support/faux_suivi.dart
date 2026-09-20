import 'dart:async';

import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/planning/data/suivi_repository.dart';
import 'package:astreinte_sp/features/planning/domain/creneau_planning.dart';
import 'package:astreinte_sp/features/planning/domain/suivi_planning.dart';

/// Une attribution de suivi toute faite.
AttributionSuivi attributionSuivi({
  required String id,
  required String creneauId,
  required String userId,
  required String nom,
  AttributionEtat etat = AttributionEtat.propose,
  DateTime? proposeeLe,
  DateTime? repondueLe,
  String? motifRefus,
  int relances = 0,
  DateTime? derniereRelance,
}) => AttributionSuivi(
  id: id,
  creneauId: creneauId,
  userId: userId,
  nom: nom,
  etat: etat,
  proposeeLe: proposeeLe,
  repondueLe: repondueLe,
  motifRefus: motifRefus,
  relances: relances,
  derniereRelance: derniereRelance,
);

/// Le planning publié de référence.
PlanningBrouillon planningPublie({DateTime? publieLe}) => PlanningBrouillon(
  id: 'plan-1',
  etat: PlanningEtat.publie,
  publieLe: publieLe ?? DateTime.now().subtract(const Duration(days: 5)),
);

/// Un [SuiviRepository] sans réseau.
///
/// Il rejoue deux règles de la base, sans quoi il mentirait :
/// - **l'avancement vient de la vue**, pas d'un comptage client : le faux le
///   recompte une fois, comme `v_schedule_progress` le compterait ;
/// - **le canal ne diffuse pas les jointures** : une réponse reçue en temps
///   réel arrive sans le nom du membre.
class FauxSuiviRepository implements SuiviRepository {
  FauxSuiviRepository({
    PlanningBrouillon? planning,
    List<CreneauPlanning>? creneaux,
    List<AttributionSuivi>? attributions,
    this.delaiRetardHeures = 72,
    this.erreurLecture,
    this.erreurPublication,
    this.erreurRelance,
    this.membresRelances = 0,
    this.relanceNouvelle = true,
    this.membresPublies = 0,
    this.attributionsPubliees = 0,
  }) : _planning = planning,
       _creneaux = <CreneauPlanning>[...?creneaux],
       _attributions = <AttributionSuivi>[...?attributions];

  PlanningBrouillon? _planning;
  final List<CreneauPlanning> _creneaux;
  final List<AttributionSuivi> _attributions;

  final int delaiRetardHeures;

  ErreurSuivi? erreurLecture;
  ErreurSuivi? erreurPublication;
  ErreurSuivi? erreurRelance;

  int membresRelances;
  bool relanceNouvelle;
  int membresPublies;
  int attributionsPubliees;

  int lectures = 0;
  int lecturesAvancement = 0;
  final List<String> publications = <String>[];
  final List<String> relances = <String>[];

  final StreamController<EvenementSuivi> _canal =
      StreamController<EvenementSuivi>.broadcast();

  void diffuser(EvenementSuivi evenement) => _canal.add(evenement);

  Future<void> fermer() => _canal.close();

  @override
  Future<SuiviPlanning> lire({
    required String stationId,
    required String periodeId,
    required int annee,
    required int mois,
  }) async {
    lectures++;
    final echec = erreurLecture;
    if (echec != null) throw EchecSuivi(echec);

    final entete = _planning;
    if (entete == null) return SuiviPlanning.vide(annee: annee, mois: mois);

    return SuiviPlanning(
      planning: entete,
      progression: _avancement(),
      creneaux: <CreneauPlanning>[..._creneaux],
      attributions: <AttributionSuivi>[..._attributions],
      annee: annee,
      mois: mois,
      delaiRetardHeures: delaiRetardHeures,
    );
  }

  @override
  Future<ProgressionPlanning> lireProgression({
    required String planningId,
  }) async {
    lecturesAvancement++;
    final echec = erreurLecture;
    if (echec != null) throw EchecSuivi(echec);
    return _avancement();
  }

  @override
  Future<ResultatPublication> publier({required String planningId}) async {
    publications.add(planningId);
    final echec = erreurPublication;
    if (echec != null) throw EchecSuivi(echec);
    _planning = planningPublie();
    return ResultatPublication(
      membres: membresPublies,
      attributions: attributionsPubliees,
    );
  }

  @override
  Future<ResultatRelance> relancer({required String planningId}) async {
    relances.add(planningId);
    final echec = erreurRelance;
    if (echec != null) throw EchecSuivi(echec);
    return ResultatRelance(
      membres: membresRelances,
      nouvelle: relanceNouvelle,
    );
  }

  @override
  Stream<EvenementSuivi> ecouter({required String stationId}) async* {
    yield const EtatCanalSuivi(branche: true);
    yield* _canal.stream;
  }

  /// Ce que `v_schedule_progress` rendrait sur ces données.
  ProgressionPlanning _avancement() {
    var pourvus = 0;
    var enAttente = 0;
    var acceptees = 0;
    var refusees = 0;
    var enRetard = 0;
    final seuil = DateTime.now().subtract(Duration(hours: delaiRetardHeures));

    for (final creneau in _creneaux) {
      final actives = _attributions
          .where(
            (AttributionSuivi a) => a.creneauId == creneau.id && a.active,
          )
          .length;
      if (actives >= creneau.effectifRequis) pourvus++;
    }

    for (final attribution in _attributions) {
      switch (attribution.etat) {
        case AttributionEtat.propose:
          enAttente++;
          final depuis = attribution.proposeeLe;
          if (depuis != null && depuis.isBefore(seuil)) enRetard++;
        case AttributionEtat.accepte:
          acceptees++;
        case AttributionEtat.refuse:
          refusees++;
        case AttributionEtat.annule:
          break;
      }
    }

    return ProgressionPlanning(
      creneauxTotal: _creneaux.length,
      creneauxPourvus: pourvus,
      enAttente: enAttente,
      acceptees: acceptees,
      refusees: refusees,
      enRetard: enRetard,
    );
  }
}
