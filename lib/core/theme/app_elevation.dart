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

  /// Niveau 2 — menu, info-bulle, sélecteur.
  static const List<BoxShadow> niveau2 = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A0B141A),
      offset: Offset(0, 2),
      blurRadius: 8,
    ),
  ];

  /// Niveau 3 — feuille de bas d'écran, dialogue.
  static const List<BoxShadow> niveau3 = <BoxShadow>[
    BoxShadow(
      color: Color(0x240B141A),
      offset: Offset(0, 8),
      blurRadius: 24,
    ),
  ];

  /// Niveau 4 — snackbar, bouton flottant.
  static const List<BoxShadow> niveau4 = <BoxShadow>[
    BoxShadow(
      color: Color(0x1F0B141A),
      offset: Offset(0, 4),
      blurRadius: 12,
    ),
  ];

  /// Variantes sombres : même géométrie, ombre noire au lieu de l'encre.
  static const List<BoxShadow> niveau2Sombre = <BoxShadow>[
    BoxShadow(color: Color(0x33000000), offset: Offset(0, 2), blurRadius: 8),
  ];

  static const List<BoxShadow> niveau3Sombre = <BoxShadow>[
    BoxShadow(color: Color(0x47000000), offset: Offset(0, 8), blurRadius: 24),
  ];

  static const List<BoxShadow> niveau4Sombre = <BoxShadow>[
    BoxShadow(color: Color(0x3D000000), offset: Offset(0, 4), blurRadius: 12),
  ];

  /// Ombres d'un [Brightness] donné, niveau par niveau.
  static List<BoxShadow> niveau(int niveau, Brightness brightness) {
    final sombre = brightness == Brightness.dark;
    return switch (niveau) {
      2 => sombre ? niveau2Sombre : niveau2,
      3 => sombre ? niveau3Sombre : niveau3,
      4 => sombre ? niveau4Sombre : niveau4,
      _ => niveau0,
    };
  }

  /// Teinte d'ombre du thème : l'encre en clair, le noir en sombre.
  static Color teinte(Brightness brightness) =>
      brightness == Brightness.dark ? AppColors.darkShadow : AppColors.shadow;
}
