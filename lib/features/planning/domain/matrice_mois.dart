import 'package:flutter/foundation.dart';

import '../../../core/theme/app_status.dart';
import 'ligne_matrice.dart';

/// La matrice d'un mois : toutes ses lignes, et le compte de disponibles par
/// colonne.
///
/// **Les comptes sont calculés une fois**, à la construction, sur les chaînes
/// déjà chargées : zéro requête, et rien à recompter à chaque image. Ils sont
/// invalidés — c'est-à-dire recalculés — à chaque écriture locale, par
/// [avecCellule].
///
/// **Ils ignorent délibérément les filtres de l'écran** : c'est le nombre de
/// pompiers disponibles dans la caserne, pas dans la vue. Un compte de
/// couverture qui bouge quand on tape dans un champ de recherche est un
/// mensonge sur l'état du mois (brief § 6.4).
@immutable
class MatriceMois {
  MatriceMois({required this.lignes, required this.nombreDeJours})
    : _disponiblesJour = _compter(lignes, nombreDeJours, CreneauType.jour),
      _disponiblesNuit = _compter(lignes, nombreDeJours, CreneauType.nuit);

  /// Une ligne par membre actif, dans l'ordre rendu par la fonction : par nom
  /// affiché.
  final List<LigneMatrice> lignes;

  /// 28, 30 ou 31. Vient de la période, jamais supposé.
  final int nombreDeJours;

  final List<int> _disponiblesJour;
  final List<int> _disponiblesNuit;

  /// Aucun membre actif : la caserne est vide, pas le mois.
  bool get aucunMembre => lignes.isEmpty;

  /// Personne n'a rien saisi. La matrice s'affiche quand même — c'est la
  /// vérité du mois.
  bool get vierge => lignes.every((LigneMatrice l) => !l.aSaisiQuelqueChose);

  /// Le nombre de membres marqués disponibles sur ce créneau.
  int disponibles(int jour, CreneauType creneau) {
    final index = jour - 1;
    final comptes = creneau == CreneauType.jour
        ? _disponiblesJour
        : _disponiblesNuit;
    if (index < 0 || index >= comptes.length) return 0;
    return comptes[index];
  }

  /// La ligne d'un membre, ou `null`.
  LigneMatrice? ligneDe(String userId) {
    for (final ligne in lignes) {
      if (ligne.userId == userId) return ligne;
    }
    return null;
  }

  /// La même matrice, une cellule remplacée, et les comptes refaits.
  MatriceMois avecCellule({
    required String userId,
    required int jour,
    required CreneauType creneau,
    required CelluleMatrice cellule,
  }) => MatriceMois(
    nombreDeJours: nombreDeJours,
    lignes: <LigneMatrice>[
      for (final ligne in lignes)
        if (ligne.userId == userId)
          ligne.avec(jour, creneau, cellule)
        else
          ligne,
    ],
  );

  static List<int> _compter(
    List<LigneMatrice> lignes,
    int nombreDeJours,
    CreneauType creneau,
  ) {
    final comptes = List<int>.filled(nombreDeJours, 0);
    for (final ligne in lignes) {
      for (var jour = 1; jour <= nombreDeJours; jour++) {
        if (ligne.etatDe(jour, creneau) == DisponibiliteEtat.disponible) {
          comptes[jour - 1]++;
        }
      }
    }
    return List<int>.unmodifiable(comptes);
  }
}
