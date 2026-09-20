import 'package:flutter/material.dart';

/// Toutes les couleurs du système, écrites valeur par valeur.
///
/// Source unique : `DESIGN.md § Colors`. Aucune couleur n'est calculée, aucune
/// graine n'est utilisée (`ColorScheme.fromSeed` est explicitement refusé par
/// le brief) : chaque paire texte/fond a été vérifiée en contraste et le test
/// `test/core/theme/contraste_test.dart` le prouve à chaque exécution.
///
/// Aucun widget ne référence cette classe directement : il passe par
/// `Theme.of(context).colorScheme` ou par `AppStatusColors`.
abstract final class AppColors {
  // ---------------------------------------------------------------------
  // Rôles Material 3 — thème clair
  // ---------------------------------------------------------------------

  /// L'encre du registre : noir bleuté, jamais noir pur. 16.34:1 sur blanc.
  static const Color primary = Color(0xFF16212A);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFD6DEE4);
  static const Color onPrimaryContainer = Color(0xFF0B141A);

  /// Le bleu de réglure. 7.41:1 sur blanc.
  static const Color secondary = Color(0xFF0F5C7A);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFCDE7F2);
  static const Color onSecondaryContainer = Color(0xFF052B3B);

  /// L'ocre d'attente. 6.92:1 sur blanc.
  static const Color tertiary = Color(0xFF7A5200);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFFFE6B0);
  static const Color onTertiaryContainer = Color(0xFF2A1C00);

  /// Le vermillon. 7.47:1 sur blanc. Jamais décoratif : c'est un état.
  static const Color error = Color(0xFFA3231A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFCDDD8);
  static const Color onErrorContainer = Color(0xFF3E0A05);

  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF131C23);
  static const Color onSurfaceVariant = Color(0xFF45535C);
  static const Color surfaceDim = Color(0xFFE7ECEE);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF7F9FA);
  static const Color surfaceContainer = Color(0xFFF1F4F6);
  static const Color surfaceContainerHigh = Color(0xFFE9EDF0);
  static const Color surfaceContainerHighest = Color(0xFFE2E7EA);

  /// Bordure de contrôle, porteuse de forme (≥ 3:1).
  static const Color outline = Color(0xFF6E7D87);

  /// Réglure décorative du registre (1.62:1). Ne porte jamais d'information.
  static const Color outlineVariant = Color(0xFFC3CDD3);

  static const Color inverseSurface = Color(0xFF222C33);
  static const Color onInverseSurface = Color(0xFFEDF1F3);
  static const Color inversePrimary = Color(0xFFD8E2E8);
  static const Color shadow = Color(0xFF0B141A);

  // ---------------------------------------------------------------------
  // Rôles Material 3 — thème sombre
  // ---------------------------------------------------------------------

  static const Color darkPrimary = Color(0xFFD8E2E8);
  static const Color darkOnPrimary = Color(0xFF16212A);
  static const Color darkPrimaryContainer = Color(0xFF3A454C);
  static const Color darkOnPrimaryContainer = Color(0xFFE7EFF4);

  static const Color darkSecondary = Color(0xFF7FD0EC);
  static const Color darkOnSecondary = Color(0xFF00344A);
  static const Color darkSecondaryContainer = Color(0xFF0B4C66);
  static const Color darkOnSecondaryContainer = Color(0xFFC8E9F7);

  static const Color darkTertiary = Color(0xFFF0C46A);
  static const Color darkOnTertiary = Color(0xFF402C00);
  static const Color darkTertiaryContainer = Color(0xFF4A3400);
  static const Color darkOnTertiaryContainer = Color(0xFFFFE0A3);

  static const Color darkError = Color(0xFFFFB4A6);
  static const Color darkOnError = Color(0xFF5C0F07);
  static const Color darkErrorContainer = Color(0xFF7E1A12);
  static const Color darkOnErrorContainer = Color(0xFFFFDAD4);

  static const Color darkSurface = Color(0xFF0F161B);
  static const Color darkOnSurface = Color(0xFFE2E8EC);
  static const Color darkOnSurfaceVariant = Color(0xFFB3C0C8);
  static const Color darkSurfaceDim = Color(0xFF0A1015);
  static const Color darkSurfaceContainerLowest = Color(0xFF0A1015);
  static const Color darkSurfaceContainerLow = Color(0xFF141C22);
  static const Color darkSurfaceContainer = Color(0xFF182127);
  static const Color darkSurfaceContainerHigh = Color(0xFF222C33);
  static const Color darkSurfaceContainerHighest = Color(0xFF2C373E);

  static const Color darkOutline = Color(0xFF7E8D96);
  static const Color darkOutlineVariant = Color(0xFF3A454C);

  static const Color darkInverseSurface = Color(0xFFE2E8EC);
  static const Color darkOnInverseSurface = Color(0xFF131C23);
  static const Color darkInversePrimary = Color(0xFF16212A);
  static const Color darkShadow = Color(0xFF000000);

  // ---------------------------------------------------------------------
  // Encres d'état — thème clair
  // ---------------------------------------------------------------------

  static const Color etatDisponible = Color(0xFF145C31);
  static const Color etatDisponiblePlein = Color(0xFF1A6B3A);
  static const Color etatDisponibleFond = Color(0xFFCFE9D8);
  static const Color etatDisponibleSurFond = Color(0xFF05321A);

  static const Color etatAbsent = Color(0xFFA3231A);
  static const Color etatAbsentFond = Color(0xFFFBDED9);
  static const Color etatAbsentSurFond = Color(0xFF3E0A05);

  static const Color etatNonSaisi = Color(0xFF52626C);

  /// Filet **porteur d'état** de la case non saisie. 3.33:1 sur `surfaceDim`.
  /// À ne jamais confondre avec [outlineVariant], qui est décoratif.
  static const Color etatNonSaisiFilet = Color(0xFF73828B);

  static const Color etatAttente = Color(0xFF7A5200);
  static const Color etatAttenteFond = Color(0xFFFFE9BF);
  static const Color etatAttenteSurFond = Color(0xFF2A1C00);

  static const Color etatNeutre = Color(0xFF45535C);
  static const Color etatNeutreFond = Color(0xFFE7EBEE);

  static const Color etatInfo = Color(0xFF0F5C7A);
  static const Color etatInfoFond = Color(0xFFCDE7F2);

  /// « Annulé » : un fait gris, pas une alarme. 10.61:1 sur [etatNeutreFond].
  static const Color etatAnnule = Color(0xFF2A343A);

  /// « Archivé » : atténué. 6.48:1 sur [etatArchiveFond].
  static const Color etatArchive = Color(0xFF4A5860);
  static const Color etatArchiveFond = Color(0xFFEEF1F3);

  /// « Mois verrouillé » : gris-encre, jamais rouge. 7.49:1 sur son fond.
  static const Color etatVerrouille = Color(0xFF3A464E);
  static const Color etatVerrouilleFond = Color(0xFFDDE3E7);

  // ---------------------------------------------------------------------
  // Encres d'état — thème sombre
  // ---------------------------------------------------------------------

  static const Color darkEtatDisponible = Color(0xFF7ADB9F);
  static const Color darkEtatDisponiblePlein = Color(0xFF2F7E4E);
  static const Color darkEtatDisponibleFond = Color(0xFF0C4A28);
  static const Color darkEtatDisponibleSurFond = Color(0xFFBFEFD1);

  static const Color darkEtatAbsent = Color(0xFFFFB4A6);
  static const Color darkEtatAbsentFilet = Color(0xFFFF9D8C);
  static const Color darkEtatAbsentFond = Color(0xFF4A1B15);
  static const Color darkEtatAbsentSurFond = Color(0xFFFFDAD4);

  static const Color darkEtatNonSaisi = Color(0xFFA4B1B9);
  static const Color darkEtatNonSaisiFilet = Color(0xFF6E7D87);

  static const Color darkEtatAttente = Color(0xFFF0C46A);
  static const Color darkEtatAttenteFond = Color(0xFF4A3400);
  static const Color darkEtatAttenteSurFond = Color(0xFFFFE0A3);

  static const Color darkEtatNeutre = Color(0xFFC4CFD6);
  static const Color darkEtatNeutreFond = Color(0xFF222C33);

  static const Color darkEtatInfo = Color(0xFF7FD0EC);
  static const Color darkEtatInfoFond = Color(0xFF0B4C66);

  /// Encre lisible posée sur [darkEtatInfoFond] : `dark-on-secondary-container`
  /// de `DESIGN.md`, réemployé tel quel pour les pastilles bleues pleines.
  static const Color darkEtatInfoSurFond = darkOnSecondaryContainer;

  /// « Archivé » en sombre : encre atténuée sur un cran de surface.
  static const Color darkEtatArchive = darkEtatNonSaisi;
  static const Color darkEtatArchiveFond = darkSurfaceContainer;

  /// « Mois verrouillé » en sombre : gris-encre sur un cran de surface.
  static const Color darkEtatVerrouille = darkOnSurfaceVariant;
  static const Color darkEtatVerrouilleFond = darkSurfaceContainerHigh;

  // ---------------------------------------------------------------------
  // Surimpressions
  // ---------------------------------------------------------------------

  /// Surimpression d'appui sur un fond sombre (8 % d'`on-primary`).
  static const Color pressionClaire = Color(0x14FFFFFF);

  /// Surimpression d'appui sur un fond clair (8 % d'encre).
  static const Color pressionSombre = Color(0x1416212A);

  /// Voile des feuilles et dialogues : 32 % (`DESIGN.md § Elevation`).
  static const Color scrim = Color(0x520B141A);
}
