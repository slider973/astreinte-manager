import 'package:astreinte_sp/features/parametres/data/parametres_repository.dart';
import 'package:astreinte_sp/features/parametres/domain/parametres_caserne.dart';

import 'faux_invitations.dart';

/// Les réglages du seed de la caserne A (`supabase/seed.sql`).
const ParametresCaserne parametresSeed = ParametresCaserne(
  stationId: stationTest,
  nom: 'CIS Saint-Martin',
  fuseau: 'Europe/Paris',
  debutJour: '07:00',
  finJour: '19:00',
  effectifJour: 1,
  effectifNuit: 1,
  jourLimite: 15,
  relancePushHeures: 24,
  relanceEmailHeures: 48,
  rapportRetardHeures: 72,
);

/// Un [ParametresRepository] sans réseau : il rend ce qu'on lui a donné, et
/// garde ce qu'on lui a écrit.
class FauxParametresRepository implements ParametresRepository {
  FauxParametresRepository({
    ParametresCaserne? parametres,
    this.erreurLecture,
    this.erreurEcriture,
  }) : parametres = parametres ?? parametresSeed;

  ParametresCaserne parametres;

  /// Erreur levée à la lecture, ou `null`.
  ErreurParametres? erreurLecture;

  /// Erreur levée à l'écriture, ou `null`.
  ErreurParametres? erreurEcriture;

  int lectures = 0;

  /// Tout ce qui a été envoyé, dans l'ordre.
  final List<ParametresCaserne> ecritures = <ParametresCaserne>[];

  @override
  Future<ParametresCaserne> lire(String stationId) async {
    lectures++;
    final echec = erreurLecture;
    if (echec != null) throw EchecParametres(echec);
    return parametres;
  }

  @override
  Future<ParametresCaserne> enregistrer(ParametresCaserne parametres) async {
    ecritures.add(parametres);
    final echec = erreurEcriture;
    if (echec != null) throw EchecParametres(echec);
    this.parametres = parametres;
    return parametres;
  }
}
