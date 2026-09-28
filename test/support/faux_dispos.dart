import 'dart:async';

import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/data/dispos_repository.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';
import 'package:astreinte_sp/features/dispos/domain/preferences_mois.dart';

import 'faux_invitations.dart';

/// Le membre 1 de la caserne A (`supabase/seed.sql`).
const String membreTest = 'aaaaaaaa-0000-4000-8000-000000000101';

PeriodeSaisie periodeOuverte({
  required int annee,
  required int mois,
  String? id,
  DateTime? dateLimite,
}) => PeriodeSaisie(
  id: id ?? 'periode-$annee-$mois',
  stationId: stationTest,
  annee: annee,
  mois: mois,
  statut: PeriodeEtat.ouverte,
  dateLimite: dateLimite ?? DateTime(annee, mois - 1, 15, 23, 59, 59),
);

PeriodeSaisie periodeVerrouillee({required int annee, required int mois}) =>
    PeriodeSaisie(
      id: 'periode-$annee-$mois',
      stationId: stationTest,
      annee: annee,
      mois: mois,
      statut: PeriodeEtat.verrouillee,
      dateLimite: DateTime(annee, mois - 1, 15, 23, 59, 59),
      verrouilleeLe: DateTime(annee, mois - 1, 15, 23, 59, 59),
    );

/// Un [DisposRepository] sans réseau, qui **compte ses requêtes**.
///
/// C'est ce compteur qui prouve la coalescence : quarante cases peintes
/// doivent produire deux appels, pas quarante. Le faux ne triche pas —
/// [enregistrerLot] et [supprimerLot] sont, côté Supabase, exactement une
/// requête PostgREST chacune.
class FauxDisposRepository implements DisposRepository {
  FauxDisposRepository({
    List<PeriodeSaisie>? periodes,
    Map<CreneauCle, DisponibiliteEtat>? disponibilites,
    Map<String, PreferencesMois>? preferences,
  }) : _periodes = <PeriodeSaisie>[
         ...periodes ?? <PeriodeSaisie>[periodeOuverte(annee: 2026, mois: 10)],
       ],
       base = <CreneauCle, DisponibiliteEtat>{...?disponibilites},
       basePreferences = <String, PreferencesMois>{...?preferences};

  final List<PeriodeSaisie> _periodes;

  /// Ce que l'admin fait pendant que l'application tourne : ouvrir un mois
  /// (ticket 068). La période n'apparaît qu'à la prochaine lecture.
  void ajouterPeriode(PeriodeSaisie periode) => _periodes.add(periode);

  /// L'état « en base ».
  final Map<CreneauCle, DisponibiliteEtat> base;

  /// Le nombre d'appels réseau, toutes opérations d'écriture confondues.
  int requetes = 0;

  /// Les lots d'écriture reçus, dans l'ordre.
  final List<List<LigneDisponibilite>> ecritures = <List<LigneDisponibilite>>[];

  /// Les lots de suppression reçus, dans l'ordre.
  final List<List<CreneauCle>> suppressions = <List<CreneauCle>>[];

  int lectures = 0;

  /// Le nombre de lectures de la liste des périodes.
  int lecturesPeriodes = 0;

  /// Si posé, la lecture des périodes attend qu'il soit complété avant de
  /// répondre : c'est la fenêtre pendant laquelle un geste peut commencer
  /// (ticket 068).
  Completer<void>? retenueLecturePeriodes;

  /// Les appels reçus, dans l'ordre : `periodes`, `lireMois`,
  /// `enregistrerLot`, `supprimerLot`.
  final List<String> journal = <String>[];

  /// Les préférences « en base », par `period_id`.
  final Map<String, PreferencesMois> basePreferences;

  /// Les préférences reçues, dans l'ordre : `(period_id, valeurs)`.
  final List<MapEntry<String, PreferencesMois>> ecrituresPreferences =
      <MapEntry<String, PreferencesMois>>[];

  int lecturesPreferences = 0;

  /// Erreur levée par les écritures, ou `null`.
  ErreurDispos? erreurEcriture;

  /// Erreur levée par les lectures, ou `null`.
  ErreurDispos? erreurLecture;

  /// Vrai pour simuler une RLS qui **filtre sans lever** : la requête part,
  /// répond 200, et n'affecte aucune ligne. C'est le comportement réel d'une
  /// période verrouillée sur un `update` ou un `delete`.
  bool filtreSansLever = false;

  @override
  Future<List<PeriodeSaisie>> periodes(String stationId) async {
    lecturesPeriodes++;
    journal.add('periodes');
    final retenue = retenueLecturePeriodes;
    if (retenue != null) await retenue.future;
    final echec = erreurLecture;
    if (echec != null) throw EchecDispos(echec);
    // Une copie, comme une vraie réponse : rendre la liste elle-même ferait
    // apparaître un mois ajouté **sans relecture**, et le test ne prouverait
    // plus rien.
    return List<PeriodeSaisie>.of(_periodes);
  }

  @override
  Future<Map<CreneauCle, DisponibiliteEtat>> lireMois({
    required String stationId,
    required String userId,
    required int annee,
    required int mois,
  }) async {
    lectures++;
    journal.add('lireMois');
    final echec = erreurLecture;
    if (echec != null) throw EchecDispos(echec);

    return <CreneauCle, DisponibiliteEtat>{
      for (final entree in base.entries)
        if (entree.key.date.year == annee && entree.key.date.month == mois)
          entree.key: entree.value,
    };
  }

  @override
  Future<int> enregistrerLot({
    required String stationId,
    required String userId,
    required List<LigneDisponibilite> lignes,
  }) async {
    if (lignes.isEmpty) return 0;
    requetes++;
    journal.add('enregistrerLot');
    ecritures.add(lignes);

    final echec = erreurEcriture;
    if (echec != null) throw EchecDispos(echec);
    if (filtreSansLever) return 0;

    for (final ligne in lignes) {
      base[ligne.cle] = ligne.etat;
    }
    return lignes.length;
  }

  @override
  Future<int> supprimerLot({
    required String stationId,
    required String userId,
    required List<CreneauCle> cles,
  }) async {
    if (cles.isEmpty) return 0;
    requetes++;
    journal.add('supprimerLot');
    suppressions.add(cles);

    final echec = erreurEcriture;
    if (echec != null) throw EchecDispos(echec);
    if (filtreSansLever) return 0;

    var supprimees = 0;
    for (final cle in cles) {
      if (base.remove(cle) != null) supprimees++;
    }
    return supprimees;
  }

  @override
  Future<Map<String, PreferencesMois>> lirePreferences({
    required String stationId,
    required String userId,
    required List<String> periodIds,
  }) async {
    lecturesPreferences++;
    final echec = erreurLecture;
    if (echec != null) throw EchecDispos(echec);

    return <String, PreferencesMois>{
      for (final id in periodIds)
        if (basePreferences.containsKey(id)) id: basePreferences[id]!,
    };
  }

  @override
  Future<int> enregistrerPreferences({
    required String stationId,
    required String userId,
    required String periodId,
    required PreferencesMois preferences,
  }) async {
    requetes++;
    ecrituresPreferences.add(
      MapEntry<String, PreferencesMois>(periodId, preferences),
    );

    final echec = erreurEcriture;
    if (echec != null) throw EchecDispos(echec);
    if (filtreSansLever) return 0;

    basePreferences[periodId] = preferences;
    return 1;
  }
}
