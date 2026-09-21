import 'package:astreinte_sp/core/plateforme/telechargement.dart';
import 'package:astreinte_sp/features/profil/data/export_repository.dart';
import 'package:astreinte_sp/features/profil/domain/export_donnees.dart';

/// Un export RGPD tel que l'Edge Function le rend, en plus petit.
///
/// La forme est **celle du vrai contrat** (`supabase/functions/README.md
/// § export-user-data`) : une entête `export` avec son inventaire, une section
/// `donnees` avec les treize sections. Un faux qui rendrait une autre forme ne
/// prouverait rien du nom de fichier ni du contenu remis.
Map<String, dynamic> exportDeTest({
  String genereLe = '2026-10-17T08:30:00.000Z',
  String email = 'membre1@caserne-a.test',
}) => <String, dynamic>{
  'export': <String, dynamic>{
    'produit': 'Astreinte SP',
    'version_format': 1,
    'genere_le': genereLe,
    'personne': 'u-1',
    'inventaire': <String, dynamic>{'profil': 1, 'disponibilites': 2},
  },
  'donnees': <String, dynamic>{
    'compte': <String, dynamic>{'adresse_de_connexion': email},
    'profil': <String, dynamic>{
      'prenom': 'Marie',
      'nom': 'Lefebvre',
      'email': email,
    },
    'casernes': <dynamic>[],
    'appartenances': <dynamic>[],
    'disponibilites': <dynamic>[],
    'preferences_de_charge': <dynamic>[],
    'attributions': <dynamic>[],
    'notifications': <dynamic>[],
    'appareils': <dynamic>[],
    'invitations_recues': <dynamic>[],
    'invitations_envoyees': <dynamic>[],
    'actes_administratifs_me_concernant': <dynamic>[],
    'mes_actes_administratifs': <dynamic>[],
    'editeur_du_produit': false,
  },
};

/// Un [ExportRepository] sans réseau.
class FauxExportRepository implements ExportRepository {
  FauxExportRepository({Map<String, dynamic>? contenu, this.echec})
    : contenu = contenu ?? exportDeTest();

  Map<String, dynamic> contenu;

  /// L'échec rendu par [demander], ou `null` pour réussir.
  EchecExport? echec;

  /// Nombre d'exports demandés.
  int demandes = 0;

  @override
  Future<ExportDonnees> demander() async {
    demandes++;
    final erreur = echec;
    if (erreur != null) throw erreur;
    return ExportDonnees(contenu);
  }
}

/// Un faux enregistrement de fichier : il **garde** ce qu'on lui a remis.
///
/// C'est ce qui permet de vérifier le contenu réellement téléchargé, et pas
/// seulement qu'un appel a eu lieu : le fichier est la livraison, pas l'appel.
class FauxTelechargement {
  FauxTelechargement({
    this.resultat = ResultatTelechargement.enregistre,
  });

  /// Ce que la plateforme est censée répondre.
  ResultatTelechargement resultat;

  final List<({String nom, String contenu, String typeMime})> fichiers =
      <({String nom, String contenu, String typeMime})>[];

  ({String nom, String contenu, String typeMime})? get dernier =>
      fichiers.isEmpty ? null : fichiers.last;

  Future<ResultatTelechargement> call({
    required String nomFichier,
    required String contenu,
    String typeMime = 'application/json',
  }) async {
    fichiers.add((nom: nomFichier, contenu: contenu, typeMime: typeMime));
    return resultat;
  }
}
