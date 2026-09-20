import 'package:flutter/material.dart';

/// Classes de fenêtre Material 3, seuils sur la largeur en dp.
///
/// Source : `DESIGN.md § Layout — Points de rupture`.
enum AppWindowClass {
  /// < 600 : téléphone, PWA installée. `NavigationBar` en bas.
  compact,

  /// 600–839 : tablette portrait, téléphone paysage. `NavigationRail`.
  medium,

  /// 840–1199 : tablette paysage, petit portable. Rail étendu, deux volets.
  expanded,

  /// ≥ 1200 : poste admin. Rail étendu permanent, trois zones.
  large;

  static const double seuilMedium = 600;
  static const double seuilExpanded = 840;
  static const double seuilLarge = 1200;

  /// Classe de fenêtre déduite de la largeur logique.
  static AppWindowClass ofWidth(double largeur) {
    if (largeur >= seuilLarge) return AppWindowClass.large;
    if (largeur >= seuilExpanded) return AppWindowClass.expanded;
    if (largeur >= seuilMedium) return AppWindowClass.medium;
    return AppWindowClass.compact;
  }

  /// Classe de fenêtre courante.
  static AppWindowClass of(BuildContext context) =>
      ofWidth(MediaQuery.sizeOf(context).width);

  /// Vrai en `compact` : la navigation est une barre basse, le contenu est
  /// sur une seule colonne et la feuille de bas d'écran remplace la modale.
  bool get estCompact => this == AppWindowClass.compact;

  /// Vrai dès `expanded` : deux volets, liste et détail, sans modale.
  bool get supporteDeuxVolets => index >= AppWindowClass.expanded.index;

  /// Vrai en `large` seulement : panneau de détail permanent à droite.
  bool get estLarge => this == AppWindowClass.large;

  /// Marge de page de cette classe (`DESIGN.md § Espacement`).
  double get margePage => switch (this) {
    AppWindowClass.compact => 16,
    AppWindowClass.medium || AppWindowClass.expanded => 24,
    AppWindowClass.large => 32,
  };
}

/// Précision du pointeur courant.
///
/// La densité `dense` de `SlotChip` (28 px) est réservée au pointeur fin.
/// Sur tablette tactile, la matrice reste en densité compacte et défile :
/// aucune exception (`DESIGN.md § Cibles tactiles`, brief § 7.6).
extension AppPointeur on BuildContext {
  /// Vrai si l'appareil est piloté par une souris ou un stylet, c'est-à-dire
  /// si les cibles peuvent descendre sous 44 dp.
  ///
  /// Deux conditions cumulatives : le mode de navigation Flutter n'est pas
  /// `directional`, et la fenêtre est au moins `expanded`. La largeur sert
  /// de garde-fou parce que le web ne rapporte pas de type de pointeur
  /// fiable avant le premier événement de survol.
  bool get estPointeurFin {
    final media = MediaQuery.of(this);
    if (media.navigationMode == NavigationMode.directional) return false;
    return AppWindowClass.ofWidth(media.size.width).supporteDeuxVolets;
  }
}
