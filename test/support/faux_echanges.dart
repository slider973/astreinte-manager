import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/echanges/data/echanges_repository.dart';
import 'package:astreinte_sp/features/echanges/domain/echange.dart';

/// Une demande toute faite. Par défaut : Antoine (`u-antoine`) cède sa nuit
/// à Chloé (`u-chloe`), envoyée il y a deux heures.
Echange echange({
  String id = 'ech-1',
  StatutEchange statut = StatutEchange.ouvert,
  FormeEchange forme = FormeEchange.cession,
  String demandeurId = 'u-antoine',
  String demandeurNom = 'Antoine C.',
  String? cibleId = 'u-chloe',
  String? cibleNom = 'Chloé C.',
  String? repreneurId,
  String? repreneurNom,
  DateTime? jour,
  CreneauType creneau = CreneauType.nuit,
  String attributionId = 'att-a',
  GardeEchange? gardeRendue,
  bool autoValide = false,
  String? decideurId,
  String? decideurNom,
  String? codeMotif,
  String? motif,
  DateTime? creeLe,
  DateTime? accepteLe,
  DateTime? decideLe,
  DateTime? expireLe,
}) {
  final j = jour ?? DateTime(2026, 10, 24);
  return Echange(
    id: id,
    stationId: 'st-1',
    forme: forme,
    statut: statut,
    demandeurId: demandeurId,
    demandeurNom: demandeurNom,
    cibleId: cibleId,
    cibleNom: cibleNom,
    repreneurId: repreneurId,
    repreneurNom: repreneurNom,
    garde: GardeEchange(
      jour: j,
      creneau: creneau,
      attributionId: attributionId,
      creneauId: 'c-${j.day}',
    ),
    gardeRendue: gardeRendue,
    autoValide: autoValide,
    decideurId: decideurId,
    decideurNom: decideurNom,
    codeMotif: codeMotif,
    motif: motif,
    expireLe: expireLe ?? j.subtract(const Duration(hours: 5)),
    creeLe: creeLe ?? DateTime(2026, 10, 4, 8),
    accepteLe: accepteLe,
    decideLe: decideLe,
    closLe: decideLe,
  );
}

/// Un [EchangesRepository] sans réseau.
///
/// Il garde **les arguments réellement envoyés** à chaque fonction : un test
/// échoue si une clé de trop s'y glissait (leçon du ticket 021).
class FauxEchangesRepository implements EchangesRepository {
  FauxEchangesRepository({
    List<Echange>? echanges,
    List<Collegue>? collegues,
    Map<String, List<GardeProposable>>? gardes,
    this.reglagesServis = ReglagesEchange.defaut,
    this.erreurLecture,
  }) : _echanges = <Echange>[...?echanges],
       _collegues = <Collegue>[...?collegues],
       _gardes = <String, List<GardeProposable>>{...?gardes};

  List<Echange> _echanges;
  final List<Collegue> _collegues;
  final Map<String, List<GardeProposable>> _gardes;
  ReglagesEchange reglagesServis;
  ErreurEchange? erreurLecture;

  /// Ce que la prochaine fonction rendra ; un succès par défaut.
  ResultatEchange? prochaineReponse;

  /// Lève à la prochaine fonction : la réponse n'est jamais arrivée.
  ErreurEchange? prochainePanne;

  /// Appelé après un geste réussi, pour changer ce que la relecture rendra.
  void Function(String fonction, Map<String, dynamic> arguments)? apres;

  int lectures = 0;
  final List<(String, Map<String, dynamic>)> appels =
      <(String, Map<String, dynamic>)>[];

  void definir(List<Echange> echanges) => _echanges = <Echange>[...echanges];

  /// Les arguments de la dernière lecture.
  ({String moi, bool admin})? derniereLecture;

  @override
  Future<List<Echange>> lister({
    required String stationId,
    String moi = '',
    bool admin = false,
  }) async {
    derniereLecture = (moi: moi, admin: admin);
    lectures++;
    final echec = erreurLecture;
    if (echec != null) throw EchecEchange(echec);
    return List<Echange>.unmodifiable(_echanges);
  }

  @override
  Future<List<Collegue>> collegues({
    required String stationId,
    required String moi,
  }) async => <Collegue>[
    for (final c in _collegues)
      if (c.userId != moi) c,
  ];

  @override
  Future<List<GardeProposable>> gardesDe({
    required String pairId,
    required String stationId,
  }) async => _gardes[pairId] ?? const <GardeProposable>[];

  @override
  Future<ReglagesEchange> reglages(String stationId) async => reglagesServis;

  Future<ResultatEchange> _appel(
    String fonction,
    Map<String, dynamic> arguments,
    ResultatEchange parDefaut,
  ) async {
    appels.add((fonction, arguments));
    final panne = prochainePanne;
    if (panne != null) {
      prochainePanne = null;
      throw EchecEchange(panne);
    }
    final reponse = prochaineReponse ?? parDefaut;
    prochaineReponse = null;
    if (reponse.ok) apres?.call(fonction, arguments);
    return reponse;
  }

  @override
  Future<ResultatEchange> demander({
    required String attributionId,
    String? cibleId,
    String? attributionRendueId,
  }) => _appel(
    'request_exchange',
    <String, dynamic>{
      'p_assignment': attributionId,
      'p_target': cibleId,
      'p_return_assignment': attributionRendueId,
    },
    const ResultatEchange(
      ok: true,
      statut: StatutEchange.ouvert,
      notifies: 1,
      echangeId: 'ech-nouvelle',
    ),
  );

  @override
  Future<ResultatEchange> repondre({
    required String echangeId,
    required bool accepte,
  }) => _appel(
    'respond_exchange',
    <String, dynamic>{'p_exchange': echangeId, 'p_accept': accepte},
    ResultatEchange(
      ok: true,
      statut: accepte ? StatutEchange.accepteParPair : StatutEchange.refuse,
    ),
  );

  @override
  Future<ResultatEchange> decider({
    required String echangeId,
    required bool valide,
    String? motif,
  }) => _appel(
    'decide_exchange',
    <String, dynamic>{
      'p_exchange': echangeId,
      'p_approve': valide,
      'p_reason': motif,
    },
    ResultatEchange(
      ok: true,
      statut: valide ? StatutEchange.valide : StatutEchange.refuse,
    ),
  );

  @override
  Future<ResultatEchange> annuler({required String echangeId}) => _appel(
    'cancel_exchange',
    <String, dynamic>{'p_exchange': echangeId},
    const ResultatEchange(ok: true, statut: StatutEchange.annule),
  );
}
