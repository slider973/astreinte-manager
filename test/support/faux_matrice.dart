import 'package:astreinte_sp/core/l10n/format_date.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/features/planning/data/matrice_repository.dart';
import 'package:astreinte_sp/features/planning/domain/ligne_matrice.dart';

/// Construit une ligne de matrice comme le ferait `availability_matrix`.
///
/// Les deux chaînes sont écrites telles quelles : c'est **l'alphabet de la
/// base** que les tests exercent, pas une abstraction Dart.
LigneMatrice ligneMatrice({
  required String userId,
  required String nom,
  required String jours,
  required String nuits,
  String? commentaire,
  int? maxAstreintes,
  int? maxWeekends,
  int astreintes = 0,
  int unitesWeekend = 0,
  int? astreintesRestantes,
  int? weekendsRestants,
  int accepteesPrecedentes = 0,
}) => LigneMatrice(
  userId: userId,
  nomAffiche: nom,
  jours: jours,
  nuits: nuits,
  commentaire: commentaire,
  maxAstreintes: maxAstreintes,
  maxWeekends: maxWeekends,
  astreintes: astreintes,
  unitesWeekend: unitesWeekend,
  astreintesRestantes: astreintesRestantes ?? _reste(maxAstreintes, astreintes),
  weekendsRestants: weekendsRestants ?? _reste(maxWeekends, unitesWeekend),
  accepteesPrecedentes: accepteesPrecedentes,
);

/// `null` quand le plafond est `null` : un illimité n'a pas de reste.
int? _reste(int? plafond, int charge) =>
    plafond == null ? null : plafond - charge;

/// Une chaîne de mois toute faite : [jours] caractères, tous [code].
String moisUniforme(String code, {int jours = 31}) => code * jours;

/// Un [MatriceRepository] sans réseau, qui **rejoue l'alphabet de la base**.
///
/// La règle qui compte est reproduite ici, sinon le faux mentirait : une
/// écriture faite par l'admin se relit en **minuscule**, parce que le
/// déclencheur `availabilities_trace_auteur` pose `set_by` et que la fonction
/// distingue l'auteur.
class FauxMatriceRepository implements MatriceRepository {
  FauxMatriceRepository({
    List<LigneMatrice>? lignes,
    this.erreurLecture,
    this.erreurEcriture,
    this.refuseSansLever = false,
  }) : lignes = <LigneMatrice>[...?lignes];

  List<LigneMatrice> lignes;

  ErreurMatrice? erreurLecture;
  ErreurMatrice? erreurEcriture;

  /// La RLS filtre sans lever : la requête répond 200 et n'affecte rien.
  bool refuseSansLever;

  int lectures = 0;

  /// Tout ce qui a été écrit, dans l'ordre.
  final List<
    ({String userId, String date, CreneauType creneau, DisponibiliteEtat etat})
  >
  ecritures =
      <
        ({
          String userId,
          String date,
          CreneauType creneau,
          DisponibiliteEtat etat,
        })
      >[];

  final List<({String userId, String date, CreneauType creneau})> suppressions =
      <({String userId, String date, CreneauType creneau})>[];

  @override
  Future<List<LigneMatrice>> matrice({
    required String stationId,
    required String periodeId,
  }) async {
    lectures++;
    final echec = erreurLecture;
    if (echec != null) throw EchecMatrice(echec);
    return <LigneMatrice>[...lignes];
  }

  @override
  Future<bool> ecrire({
    required String stationId,
    required String userId,
    required DateTime jour,
    required CreneauType creneau,
    required DisponibiliteEtat etat,
  }) async {
    ecritures.add((
      userId: userId,
      date: isoJour(jour),
      creneau: creneau,
      etat: etat,
    ));
    final echec = erreurEcriture;
    if (echec != null) throw EchecMatrice(echec);
    if (refuseSansLever) return false;

    _remplacer(
      userId: userId,
      jour: jour.day,
      creneau: creneau,
      // **Minuscule** : c'est un admin qui a écrit.
      code: etat == DisponibiliteEtat.disponible ? 'd' : 'a',
    );
    return true;
  }

  @override
  Future<bool> effacer({
    required String stationId,
    required String userId,
    required DateTime jour,
    required CreneauType creneau,
  }) async {
    suppressions.add((userId: userId, date: isoJour(jour), creneau: creneau));
    final echec = erreurEcriture;
    if (echec != null) throw EchecMatrice(echec);

    _remplacer(userId: userId, jour: jour.day, creneau: creneau, code: '.');
    return true;
  }

  void _remplacer({
    required String userId,
    required int jour,
    required CreneauType creneau,
    required String code,
  }) {
    lignes = <LigneMatrice>[
      for (final ligne in lignes)
        if (ligne.userId == userId)
          ligne.avec(jour, creneau, CelluleMatrice.depuisCode(code))
        else
          ligne,
    ];
  }
}
