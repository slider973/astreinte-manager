import 'package:astreinte_sp/features/profil/data/profil_repository.dart';
import 'package:astreinte_sp/features/profil/domain/profil.dart';

/// Un [ProfilRepository] sans réseau.
///
/// Il **garde un profil**, il ne se contente pas de compter les appels : une
/// écriture suivie d'une relecture doit rendre ce qui a été écrit, sinon aucun
/// test ne peut vérifier que l'écran affiche ce que la base a accepté.
class FauxProfilRepository implements ProfilRepository {
  FauxProfilRepository({this.echoue = false, Profil? profil})
    : profil =
          profil ??
          const Profil(
            prenom: 'Marie',
            nom: 'Lefebvre',
            email: 'membre1@caserne-a.test',
            telephone: '+33600000101',
          );

  bool echoue;

  /// Fait échouer la seule lecture du profil, sans toucher aux écritures :
  /// c'est le cas de la bannière d'erreur de l'écran.
  bool lectureEchoue = false;

  Profil profil;

  final List<({String prenom, String nom, String? telephone})> ecritures =
      <({String prenom, String nom, String? telephone})>[];

  /// `profiles.push_enabled`, avec la valeur par défaut du schéma.
  bool pushNonCritiquesActifs = true;

  /// Nombre de suppressions de compte demandées.
  int suppressions = 0;

  /// L'échec rendu par [supprimerCompte], ou `null` pour réussir.
  EchecSuppression? echecSuppression;

  int lectures = 0;

  @override
  Future<Profil> lire(String userId) async {
    lectures++;
    if (echoue || lectureEchoue) {
      throw const FormatException('lecture refusée');
    }
    return profil;
  }

  @override
  Future<void> completer({
    required String userId,
    required String prenom,
    required String nom,
    String? telephone,
  }) async {
    if (echoue) throw const FormatException('écriture refusée');
    final numero = telephone?.trim() ?? '';
    ecritures.add((prenom: prenom, nom: nom, telephone: telephone));
    profil = profil.copyWith(
      prenom: prenom.trim(),
      nom: nom.trim(),
      telephone: numero.isEmpty ? null : numero,
      effacerTelephone: numero.isEmpty,
    );
  }

  @override
  Future<bool> pushNonCritiques(String userId) async {
    if (echoue) throw const FormatException('lecture refusée');
    return pushNonCritiquesActifs;
  }

  @override
  Future<void> definirPushNonCritiques({
    required String userId,
    required bool actif,
  }) async {
    if (echoue) throw const FormatException('écriture refusée');
    pushNonCritiquesActifs = actif;
  }

  @override
  Future<void> supprimerCompte() async {
    suppressions++;
    final echec = echecSuppression;
    if (echec != null) throw echec;
  }
}
