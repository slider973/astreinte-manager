import 'package:flutter/widgets.dart';

/// Échelle d'espacement de 4, unique dans toute l'application.
///
/// Source : `DESIGN.md § Layout — Espacement`. Un widget qui a besoin d'une
/// valeur absente de cette échelle a un problème de composition, pas un
/// problème de token.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Marge de page en compact.
  static const double pageCompact = lg;

  /// Marge de page en medium et expanded.
  static const double pageMedium = xl;

  /// Marge de page en large.
  static const double pageLarge = xxl;

  /// Espace au-dessus d'un titre. Toujours plus qu'en dessous (24 / 8).
  static const double auDessusTitre = xl;

  /// Espace sous un titre.
  static const double sousTitre = sm;

  /// Écart minimal entre deux cibles tactiles adjacentes.
  static const double entreCibles = sm;

  /// Largeur maximale du contenu sur poste admin.
  static const double contenuMax = 1440;

  /// Largeur maximale d'une colonne de contenu en medium.
  static const double colonneMax = 720;
}

/// Rayons de coin. Le registre est fait de cases, pas de pastilles.
///
/// Source : `DESIGN.md § Shapes`.
abstract final class AppRadius {
  /// Traits de réglure, en-têtes collants, séparateurs.
  static const double filet = 0;

  /// **La forme signature** : case de créneau, badge d'état, puce.
  static const double caseRegistre = 4;

  /// Bouton, champ de saisie, panneau, « bloc réglé ».
  static const double controle = 8;

  /// Dialogue, feuille de bas d'écran, menu.
  static const double feuille = 12;

  /// **La carte du monde du pompier** (ticket 064). Le registre de l'admin est
  /// fait de cases à rayon 4 et de blocs à rayon 8 ; les écrans du pompier
  /// sont faits de cartes posées sur un fond doux, et c'est leur rayon qui
  /// les distingue (`design/064 § 2`). Réservé à ces cartes : un bouton ou un
  /// champ à rayon 20 serait une gélule, que `DESIGN.md § Shapes` proscrit.
  static const double carte = 20;

  /// Avatar et pastille de compteur de notifications **uniquement**.
  static const double pastille = 999;

  static const BorderRadius caseRegistreRadius = BorderRadius.all(
    Radius.circular(caseRegistre),
  );
  static const BorderRadius controleRadius = BorderRadius.all(
    Radius.circular(controle),
  );
  static const BorderRadius feuilleRadius = BorderRadius.vertical(
    top: Radius.circular(feuille),
  );

  /// Le rayon `feuille` sur les **quatre** coins : le carré d'initiale des
  /// lignes de liste du monde du pompier (ticket 064). [feuilleRadius] ne
  /// porte que les deux coins hauts, parce qu'il sert aux feuilles de bas
  /// d'écran.
  static const BorderRadius feuilleCarreeRadius = BorderRadius.all(
    Radius.circular(feuille),
  );
  static const BorderRadius carteRadius = BorderRadius.all(
    Radius.circular(carte),
  );
  static const BorderRadius pastilleRadius = BorderRadius.all(
    Radius.circular(pastille),
  );
}

/// Épaisseurs de trait.
///
/// Source : `DESIGN.md § Shapes`. Deux valeurs seulement : un filet qui
/// sépare, un filet qui porte un état.
abstract final class AppStroke {
  /// Réglure et contour de contrôle.
  static const double filet = 1;

  /// Contour **porteur d'état** : case sélectionnée, case absente, focus.
  static const double etat = 2;

  /// Décalage de l'anneau de focus.
  static const double focusOffset = 2;

  /// Trait des hachures à 45°.
  static const double hachure = 1.5;

  /// Pas des hachures à 45°.
  static const double pasHachure = 6;

  /// Opacité de l'encre dans les hachures.
  static const double opaciteHachure = 0.28;
}

/// Tailles de cible tactile et de case.
///
/// Source : `DESIGN.md § Layout — Cibles tactiles`. Le plancher WCAG est 44,
/// on vise 48 partout : le public porte des gants.
abstract final class AppTouch {
  /// Plancher absolu, jamais franchi vers le bas au tactile.
  static const double plancher = 44;

  /// Cible visée pour tout contrôle tactile.
  static const double cible = 48;

  /// Case de créneau en densité confortable (téléphone).
  static const double caseConfortable = 48;

  /// Case de créneau en densité compacte (tablette, listes).
  static const double caseCompacte = 40;

  /// Case de créneau en densité dense — **matrice admin, pointeur seul**.
  static const double caseDense = 28;

  /// Hauteur du bouton principal.
  static const double bouton = 52;

  /// Hauteur d'un champ de saisie.
  static const double champ = 56;

  /// Hauteur d'un badge d'état en taille normale.
  static const double badge = 28;

  /// Hauteur d'un badge d'état en taille compacte.
  static const double badgeCompact = 22;

  /// Hauteur de la barre de navigation, hors zone sûre.
  static const double navigation = 72;

  /// Bande du bord gauche laissée libre pour le geste retour iOS.
  static const double bandeGesteRetour = 24;

  /// Taille de glyphe d'état selon la densité de case.
  static const double glypheConfortable = 24;
  static const double glypheCompact = 20;
  static const double glypheDense = 16;

  /// Icône d'accompagnement d'un libellé (bouton, badge, bannière).
  static const double icone = 20;

  /// Petite icône (marqueur de jour férié).
  static const double iconePetite = 14;
}
