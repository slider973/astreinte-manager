import 'dart:math' as math;

import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/ligne_matrice.dart';

/// La géométrie de la matrice, en un seul endroit.
///
/// **Une ligne est une ligne des deux côtés.** La colonne figée et la grille
/// partagent ces mesures au pixel près : si elles divergeaient d'un seul
/// pixel, le nom ne serait plus en face de ses cases et l'écran mentirait.
/// C'est la raison d'être de ce fichier — pas la mutualisation, la parité.
///
/// Échelle de 4 exclusivement (`DESIGN.md § Espacement`) : la colonne de 30
/// du brief est ici 28 + 2, et la journée 58 + 4.
abstract final class GeoMatrice {
  /// Côté d'une case dense. `AppTouch.caseDense`, jamais servi au doigt.
  static const double colonne = 28;

  /// Écart entre le jour et la nuit d'une même journée.
  static const double ecartCreneaux = AppSpacing.xxs;

  /// Écart entre deux journées.
  static const double ecartJours = AppSpacing.xs;

  /// Le pas d'une journée : deux colonnes solidaires, puis la séparation.
  static const double largeurJour = colonne * 2 + ecartCreneaux + ecartJours;

  /// Hauteur d'une ligne de membre : la case 28, plus 2 px en haut et en bas.
  static const double hauteurLigne = 32;

  /// La même, quand le commentaire du mois se déplie en seconde ligne.
  static const double hauteurLigneCommentee = 52;

  /// En-tête des dates : la lettre du jour, son numéro, les deux créneaux.
  static const double hauteurEntete = 56;

  /// La ligne « Disponibles », dernière du bloc épinglé.
  static const double hauteurDisponibles = colonne;

  /// Le bloc épinglé entier.
  static const double hauteurBlocEpingle = hauteurEntete + hauteurDisponibles;

  /// Largeur de la colonne figée : 280 en `large`, 240 en `expanded`.
  static double colonneFigee(AppWindowClass classe) =>
      classe.estLarge ? 280 : 240;

  /// Largeur des deux compteurs de quota, dans l'en-tête de ligne.
  static const double largeurQuota = 48;

  /// La largeur totale de la grille pour un mois de [jours] journées.
  static double largeurTotale(int jours) => jours * largeurJour;

  /// Hauteur d'une ligne de commentaire dépliée.
  static const double hauteurCommentaire = 20;

  /// Le commentaire déplié tient au plus trois lignes.
  static const int lignesCommentaireDeplie = 3;

  /// La hauteur d'une ligne : 32, 52 avec un commentaire, et deux lignes de
  /// plus quand il est déplié.
  ///
  /// **Cette fonction est la parité** : la colonne figée et la grille
  /// l'appellent toutes les deux, avec les mêmes arguments.
  static double hauteurDe(
    LigneMatrice ligne, {
    required bool commentaires,
    bool deplie = false,
  }) {
    if (!commentaires || !ligne.aUnCommentaire) return hauteurLigne;
    if (!deplie) return hauteurLigneCommentee;
    return hauteurLigneCommentee +
        hauteurCommentaire * (lignesCommentaireDeplie - 1);
  }

  /// La première journée visible pour un décalage horizontal donné.
  ///
  /// C'est la fenêtre de virtualisation horizontale : une ligne ne construit
  /// que les journées qui sont à l'écran, et elle ne se reconstruit qu'au
  /// franchissement d'une journée, pas à chaque pixel.
  static int premierJourVisible(double decalage) =>
      math.max(0, decalage ~/ largeurJour);

  /// Le nombre de journées à construire pour une largeur visible donnée.
  /// Une de plus de chaque côté : la journée à demi entrée doit exister.
  static int joursVisibles(double largeur) =>
      math.max(1, (largeur / largeurJour).ceil() + 1);
}
