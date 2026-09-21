import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'telechargement_stub.dart'
    if (dart.library.js_interop) 'telechargement_web.dart';

/// Ce qu'il est advenu d'un fichier qu'on a voulu remettre à la personne.
///
/// Quatre issues, et elles se disent différemment à l'écran : un partage
/// annulé n'est pas une panne, et l'annoncer comme telle apprend aux gens à ne
/// plus lire les messages d'erreur (`design/034-rgpd-export.md § 4`).
enum ResultatTelechargement {
  /// Le navigateur a rangé le fichier — dossier de téléchargement, ou la
  /// destination choisie par la personne.
  enregistre,

  /// Le fichier est parti dans la feuille de partage du système. Ce qui suit
  /// appartient à iOS ou à Android : « Enregistrer dans Fichiers », un envoi
  /// par message, un dépôt dans un nuage.
  partage,

  /// La feuille de partage a été refermée sans rien faire. Rien à dire.
  annule,

  /// Ni l'un ni l'autre n'a abouti. L'écran doit le dire **et** proposer une
  /// sortie : c'est la seule issue qui mérite une phrase en rouge.
  impossible,
}

/// Remet un fichier à la personne, par le chemin que sa plateforme rend le plus
/// naturel.
///
/// **Ce n'est pas `window.open`.** L'application est une PWA installée
/// (`CLAUDE.md`) : en `display-mode: standalone` il n'y a plus de barre
/// d'adresse, et ouvrir un onglet expédie la personne hors de l'application —
/// quand le navigateur ne refuse pas tout simplement. Le fichier est donc
/// construit en mémoire et rangé par le navigateur lui-même.
typedef TelechargerFichier =
    Future<ResultatTelechargement> Function({
      required String nomFichier,
      required String contenu,
      String typeMime,
    });

/// Surchargé par un faux dans les tests : aucun test n'écrit sur le disque.
final Provider<TelechargerFichier> telechargementProvider =
    Provider<TelechargerFichier>((ref) => telechargerFichier);
