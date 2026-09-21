import 'telechargement.dart';

/// Hors du web : aucun navigateur pour ranger le fichier.
///
/// Cette version est compilée pour les builds iOS et Android natifs, qui ne
/// sont produits qu'à la demande d'une caserne (`CLAUDE.md`). Le jour où l'un
/// d'eux doit enregistrer un export, c'est ici que le paquet natif se
/// branchera — et nulle part ailleurs dans l'application. En attendant,
/// l'écran dit honnêtement que ce n'est pas possible plutôt que de faire
/// disparaître un fichier.
Future<ResultatTelechargement> telechargerFichier({
  required String nomFichier,
  required String contenu,
  String typeMime = 'application/json',
}) async => ResultatTelechargement.impossible;
