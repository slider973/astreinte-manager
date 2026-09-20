import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/dispos/data/dispos_repository.dart';
import 'package:astreinte_sp/features/dispos/domain/creneau_cle.dart';
import 'package:astreinte_sp/features/dispos/domain/periode_saisie.dart';

import 'faux_invitations.dart';

/// Le membre 1 de la caserne A (`supabase/seed.sql`).
const String membreTest = 'aaaaaaaa-0000-4000-8000-000000000101';

PeriodeSaisie periodeOuverte({
  int annee = 2026,
  int mois = 10,
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

PeriodeSaisie periodeVerrouillee({int annee = 2026, int mois = 9}) =>
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
  }) : _periodes = periodes ?? <PeriodeSaisie>[periodeOuverte()],
       base = <CreneauCle, DisponibiliteEtat>{...?disponibilites};

  final List<PeriodeSaisie> _periodes;

  /// L'état « en base ».
  final Map<CreneauCle, DisponibiliteEtat> base;

  /// Le nombre d'appels réseau, toutes opérations d'écriture confondues.
  int requetes = 0;

  /// Les lots d'écriture reçus, dans l'ordre.
  final List<List<LigneDisponibilite>> ecritures = <List<LigneDisponibilite>>[];

  /// Les lots de suppression reçus, dans l'ordre.
  final List<List<CreneauCle>> suppressions = <List<CreneauCle>>[];

  int lectures = 0;

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
    final echec = erreurLecture;
    if (echec != null) throw EchecDispos(echec);
    return _periodes;
  }

  @override
  Future<Map<CreneauCle, DisponibiliteEtat>> lireMois({
    required String stationId,
    required String userId,
    required int annee,
    required int mois,
  }) async {
    lectures++;
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
}
