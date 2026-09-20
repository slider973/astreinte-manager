import 'package:flutter/material.dart';

/// Durées d'animation. Le mouvement dit un changement d'état, rien d'autre.
///
/// Source : `DESIGN.md § Motion`.
abstract final class AppDuration {
  /// Case cochée/décochée, bascule.
  static const Duration instantane = Duration(milliseconds: 120);

  /// Badge, bannière, apparition d'un état.
  static const Duration courant = Duration(milliseconds: 180);

  /// Feuille, panneau, navigation.
  static const Duration surface = Duration(milliseconds: 240);

  /// Transition de route.
  static const Duration page = Duration(milliseconds: 280);

  /// Balayage du squelette de chargement. Lent : c'est une respiration, pas
  /// un effet.
  static const Duration balayage = Duration(milliseconds: 1400);
}

/// Courbes d'animation. Sortie exponentielle, jamais de rebond.
abstract final class AppCurves {
  /// La courbe par défaut du système : sortie rapide puis freinage.
  static const Curve sortie = Curves.easeOutCubic;

  /// Transitions de page, où l'entrée compte autant que la sortie.
  static const Curve entreeSortie = Curves.easeInOutCubic;

  /// Balayage du squelette : linéaire, pour ne pas suggérer une progression.
  static const Curve balayage = Curves.linear;
}

/// Résolution du mouvement en fonction des préférences système.
///
/// Reduce Motion (`prefers-reduced-motion` sur le web, « Réduire les
/// animations » sur iOS et Android) est une **contrainte produit**, pas une
/// option : toute durée passée par [AppMotion.duree] tombe à zéro, et tout
/// widget animé doit interroger [AppMotion.reduit] avant de démarrer une
/// boucle.
abstract final class AppMotion {
  /// Vrai si l'utilisateur a demandé moins d'animation.
  static bool reduit(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// [duree] telle quelle, ou `Duration.zero` si Reduce Motion est actif.
  static Duration duree(BuildContext context, Duration duree) =>
      reduit(context) ? Duration.zero : duree;

  /// Alias lisible de [duree] pour la durée la plus courante.
  static Duration instantane(BuildContext context) =>
      duree(context, AppDuration.instantane);

  static Duration courant(BuildContext context) =>
      duree(context, AppDuration.courant);

  static Duration surface(BuildContext context) =>
      duree(context, AppDuration.surface);

  static Duration page(BuildContext context) =>
      duree(context, AppDuration.page);
}
