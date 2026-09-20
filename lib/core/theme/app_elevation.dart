import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Les cinq niveaux de profondeur.
///
/// Source : `DESIGN.md § Elevation & Depth`. **La profondeur n'est pas le
/// matériau de ce système : le filet l'est.** Tout le contenu — panneaux,
/// listes, « cartes », bannières — reste au niveau 0 et se sépare par un trait
/// de réglure et un cran de surface tonale. Seuls les objets qui flottent
/// vraiment portent une ombre, et chaque ombre a un décalage **et** un flou :
/// un halo coloré à décalage zéro est de la décoration.
abstract final class AppShadows {
  /// Niveau 0 — tout contenu. Aucune ombre, jamais.
  static const List<BoxShadow> niveau0 = <BoxShadow>[];

  /// Niveau 1 — barre d'application au défilement, barre de navigation.
  /// Surface tonale et filet, toujours pas d'ombre.
  static const List<BoxShadow> niveau1 = <BoxShadow>[];

  /// Opacité de chaque niveau, telle que `DESIGN.md § Elevation` la fixe.
  static const double opaciteNiveau2 = 0.10;
  static const double opaciteNiveau3 = 0.14;
  static const double opaciteNiveau4 = 0.12;

  /// Une ombre du système : un décalage **et** un flou, jamais un halo.
  ///
  /// La teinte n'est jamais réécrite en dur : elle est toujours dérivée de
  /// `AppColors.shadow` (l'encre) ou de `AppColors.darkShadow` (le noir), pour
  /// qu'un changement de `DESIGN.md § Colors` se propage tout seul.
  static List<BoxShadow> _ombre({
    required Brightness brightness,
    required double opacite,
    required double decalage,
    required double flou,
  }) => <BoxShadow>[
    BoxShadow(
      color: teinte(brightness).withValues(alpha: opacite),
      offset: Offset(0, decalage),
      blurRadius: flou,
    ),
  ];

  /// Niveau 2 — menu, info-bulle, sélecteur.
  static List<BoxShadow> niveau2(Brightness brightness) => _ombre(
    brightness: brightness,
    // Le noir du thème sombre porte moins loin que l'encre : on compense.
    opacite: brightness == Brightness.dark
        ? opaciteNiveau2 * 2
        : opaciteNiveau2,
    decalage: 2,
    flou: 8,
  );

  /// Niveau 3 — feuille de bas d'écran, dialogue.
  static List<BoxShadow> niveau3(Brightness brightness) => _ombre(
    brightness: brightness,
    opacite: brightness == Brightness.dark
        ? opaciteNiveau3 * 2
        : opaciteNiveau3,
    decalage: 8,
    flou: 24,
  );

  /// Niveau 4 — snackbar, bouton flottant.
  static List<BoxShadow> niveau4(Brightness brightness) => _ombre(
    brightness: brightness,
    opacite: brightness == Brightness.dark
        ? opaciteNiveau4 * 2
        : opaciteNiveau4,
    decalage: 4,
    flou: 12,
  );

  /// Ombres d'un [Brightness] donné, niveau par niveau.
  static List<BoxShadow> niveau(int niveau, Brightness brightness) =>
      switch (niveau) {
        2 => niveau2(brightness),
        3 => niveau3(brightness),
        4 => niveau4(brightness),
        _ => niveau0,
      };

  /// Teinte d'ombre du thème : l'encre en clair, le noir en sombre.
  static Color teinte(Brightness brightness) =>
      brightness == Brightness.dark ? AppColors.darkShadow : AppColors.shadow;
}
