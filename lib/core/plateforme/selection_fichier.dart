import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'selection_fichier_stub.dart'
    if (dart.library.js_interop) 'selection_fichier_web.dart';

/// Ce qu'il est advenu d'une demande de fichier.
///
/// Quatre issues, et elles se disent différemment à l'écran — exactement comme
/// [ResultatTelechargement] du ticket 034 dans l'autre sens. Un sélecteur
/// refermé sans rien choisir n'est **pas** une panne, et l'annoncer comme telle
/// apprend aux gens à ne plus lire les messages d'erreur.
@immutable
sealed class SelectionFichier {
  const SelectionFichier();
}

/// Un fichier est là, entièrement lu en mémoire.
@immutable
final class FichierChoisi extends SelectionFichier {
  const FichierChoisi({required this.nom, required this.octets});

  /// Le nom tel que la personne le connaît, affiché dans l'aperçu.
  final String nom;

  /// Le contenu brut. **Pas une chaîne** : l'encodage n'est pas encore
  /// tranché, et le décider ici reviendrait à le deviner deux fois.
  final Uint8List octets;
}

/// Le sélecteur s'est refermé sans choix. Rien à dire, rien à afficher.
@immutable
final class SelectionAnnulee extends SelectionFichier {
  const SelectionAnnulee();
}

/// Le fichier dépasse la limite. **Refusé avant d'être lu** : un refus qui
/// commence par charger deux cents mégaoctets dans l'onglet n'est pas un refus.
@immutable
final class FichierTropGros extends SelectionFichier {
  const FichierTropGros({required this.octets, required this.limite});

  /// La taille annoncée par le navigateur, pour pouvoir la dire.
  final int octets;
  final int limite;
}

/// Aucun moyen de demander un fichier sur cette plateforme.
@immutable
final class SelectionIndisponible extends SelectionFichier {
  const SelectionIndisponible();
}

/// Demande un fichier à la personne.
///
/// [typesAcceptes] est la liste que le sélecteur du système propose en premier
/// (`accept` d'un `input[type=file]`) : un filtre d'affichage, jamais une
/// garantie. La validation du contenu appartient au domaine.
///
/// **Aucun plugin.** L'implémentation web est un `input[type=file]` derrière un
/// import conditionnel, comme `telechargement_web.dart`. La PWA est le canal
/// principal (`CLAUDE.md`) et un paquet qui n'existerait que pour ouvrir un
/// sélecteur de fichier ajouterait deux implémentations natives à maintenir
/// pour des builds que personne ne produit.
typedef DemanderFichier =
    Future<SelectionFichier> Function({
      required String typesAcceptes,
      required int tailleMaxOctets,
    });

/// Surchargé par un faux dans les tests : aucun test n'ouvre de sélecteur.
final Provider<DemanderFichier> selectionFichierProvider =
    Provider<DemanderFichier>((ref) => demanderFichier);
