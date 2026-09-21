import 'selection_fichier.dart';

/// Hors du web : aucun sélecteur de fichier.
///
/// Cette version est compilée pour les builds iOS et Android natifs, qui ne
/// sont produits qu'à la demande d'une caserne (`CLAUDE.md`). Le jour où l'un
/// d'eux doit ouvrir un fichier, c'est ici qu'un paquet natif se branchera — et
/// nulle part ailleurs dans l'application. En attendant, l'écran dit
/// honnêtement que ce n'est pas possible plutôt que d'ouvrir un bouton qui ne
/// fait rien.
Future<SelectionFichier> demanderFichier({
  required String typesAcceptes,
  required int tailleMaxOctets,
}) async => const SelectionIndisponible();
