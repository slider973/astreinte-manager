import 'dart:convert';

import 'package:astreinte_sp/core/plateforme/selection_fichier.dart';
import 'package:flutter/foundation.dart';

/// Un faux sélecteur de fichier : il rend ce qu'on lui a préparé, et **retient
/// ce qu'on lui a demandé**.
///
/// Aucun test n'ouvre de sélecteur de fichier : `flutter test` n'a pas de
/// navigateur, et un canal de plateforme absent ne rendrait jamais la main.
class FauxSelecteurFichier {
  FauxSelecteurFichier({SelectionFichier? selection})
    : selection = selection ?? const SelectionAnnulee();

  /// Ce que la plateforme est censée répondre au prochain appel.
  SelectionFichier selection;

  /// Les appels reçus, avec ce que l'écran a demandé au sélecteur.
  final List<({String typesAcceptes, int tailleMaxOctets})> demandes =
      <({String typesAcceptes, int tailleMaxOctets})>[];

  /// Prépare le choix d'un fichier texte, encodé en UTF-8.
  void posera(String contenu, {String nom = 'pompiers.csv'}) {
    selection = FichierChoisi(
      nom: nom,
      octets: Uint8List.fromList(utf8.encode(contenu)),
    );
  }

  /// Prépare le choix d'un fichier dont on fournit les octets bruts : c'est le
  /// seul moyen d'éprouver un encodage qui n'est pas celui de Dart.
  void poseraOctets(List<int> octets, {String nom = 'pompiers.csv'}) {
    selection = FichierChoisi(nom: nom, octets: Uint8List.fromList(octets));
  }

  Future<SelectionFichier> call({
    required String typesAcceptes,
    required int tailleMaxOctets,
  }) async {
    demandes.add((
      typesAcceptes: typesAcceptes,
      tailleMaxOctets: tailleMaxOctets,
    ));
    return selection;
  }
}
