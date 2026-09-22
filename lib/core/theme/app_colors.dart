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
  //
  // Chaque valeur porte son ratio WCAG mesuré, calculé par
  // `test/core/theme/contraste_test.dart` — pas estimé à l'œil.
  // ---------------------------------------------------------------------

  /// L'indigo : **l'accent**. Bouton principal, sélection, jour courant,
  /// focus. 4.72:1 en remplissage sous [onPrimary].
  ///
  /// Ce n'est pas la couleur du texte indigo : voir [accentTexte].
  static const Color primary = Color(0xFF7655FA);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFE4DDFE);

  /// 6.74:1 sur [primaryContainer].
  static const Color onPrimaryContainer = Color(0xFF4D37A2);

  /// L'indigo **en texte**, assombri pour tenir sur le papier autant que sur
  /// le blanc : 7.31:1 sur [surface], 6.92:1 sur [surfaceContainerLow].
  ///
  /// Un lien, un libellé d'accent, un chiffre mis en avant passent par ici ;
  /// [primary] reste un remplissage. Séparer les deux est ce qui permet à
  /// l'accent d'être vif en bloc sans devenir illisible en ligne.
  static const Color accentTexte = Color(0xFF5840BC);

  /// Le vert. 5.12:1 en remplissage sous [onSecondary]. Accepté, couvert,
  /// publié, saisie ouverte.
  static const Color secondary = Color(0xFF097C69);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFCEE5E1);

  /// 7.02:1 sur [secondaryContainer].
  static const Color onSecondaryContainer = Color(0xFF065144);

  /// L'orange **assombri**, seule forme de l'orange qui a le droit d'être du
  /// texte. 4.94:1 sur [surface]. Attente, proposition, à pourvoir.
  static const Color tertiary = Color(0xFF9F6224);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFFDEAD7);

  /// Encre du registre sur le conteneur orange : 14.72:1.
  static const Color onTertiaryContainer = Color(0xFF131C23);

  /// L'orange vif de la charte. **Remplissage seulement** — bloc de grille,
  /// segment de barre de répartition, pastille. 2.26:1 sur blanc : y poser du
  /// texte est un défaut bloquant, et le texte d'un bloc orange est
  /// [onTertiaryContainer].
  static const Color orangeVif = Color(0xFFF59638);

  /// Le rose **assombri**, seule forme du rose qui a le droit d'être du texte.
  /// 5.87:1 sur [surface]. Refusé, absent, conflit, échec.
  static const Color error = Color(0xFFBB285D);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFED7E5);

  /// Encre du registre sur le conteneur rose : 13.19:1.
  static const Color onErrorContainer = Color(0xFF131C23);

  /// Le rose vif de la charte. **Remplissage seulement**, comme [orangeVif] :
  /// 3.60:1 sur blanc, sous le seuil du texte.
  static const Color roseVif = Color(0xFFF9357C);

  /// Le violet de la charte : **décoratif**, jamais porteur d'état, jamais du
  /// texte. 4.36:1 sur blanc — sous le seuil, et c'est voulu : une couleur qui
  /// ne peut pas être lue ne peut pas être prise pour une information.
  /// Marque, illustration d'état vide, rien d'autre.
  static const Color accentDecoratif = Color(0xFFB142E8);

  /// Fond décoratif violet, 1.31:1 sur [surface]. Le texte posé dessus est
  /// l'encre [onSurface] (12.75:1), jamais une teinte.
  static const Color accentDecoratifFond = Color(0xFFEFD9FA);

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

  /// Accent posé sur [inverseSurface] — l'action d'un bandeau. C'est l'indigo
  /// du thème sombre, parce que le fond est sombre : 5.43:1.
  static const Color inversePrimary = Color(0xFFA690FC);
  static const Color shadow = Color(0xFF0B141A);

  // ---------------------------------------------------------------------
  // Rôles Material 3 — thème sombre
  //
  // Les accents viennent du superviseur ; les conteneurs sont dérivés ici,
  // avec deux cibles : le texte du conteneur à 4.5:1 au moins **sur** le
  // conteneur, et le conteneur lui-même détaché de la surface (≥ 1.3:1), sans
  // quoi un bloc d'état se fondrait dans le fond de nuit.
  // ---------------------------------------------------------------------

  /// 6.97:1 sur [darkSurface].
  static const Color darkPrimary = Color(0xFFA690FC);
  static const Color darkOnPrimary = Color(0xFF131C23);

  /// 1.54:1 sur [darkSurface] — le bloc se détache.
  static const Color darkPrimaryContainer = Color(0xFF3A2B73);

  /// 9.07:1 sur [darkPrimaryContainer].
  static const Color darkOnPrimaryContainer = Color(0xFFE4DDFE);

  /// L'indigo en texte, côté nuit : c'est déjà [darkPrimary], éclairci pour
  /// le fond sombre. Le pendant de [accentTexte].
  static const Color darkAccentTexte = darkPrimary;

  /// 6.72:1 sur [darkSurface].
  static const Color darkSecondary = Color(0xFF5FAA9E);
  static const Color darkOnSecondary = Color(0xFF131C23);

  /// 1.63:1 sur [darkSurface].
  static const Color darkSecondaryContainer = Color(0xFF14423B);

  /// 8.67:1 sur [darkSecondaryContainer].
  static const Color darkOnSecondaryContainer = Color(0xFFCDE8E2);

  /// 8.08:1 sur [darkSurface]. **De nuit, l'orange vif passe en texte** : ce
  /// qui lui était interdit sur blanc lui est permis ici, mesure à l'appui.
  static const Color darkTertiary = Color(0xFFF59638);
  static const Color darkOnTertiary = Color(0xFF131C23);

  /// 1.72:1 sur [darkSurface].
  static const Color darkTertiaryContainer = Color(0xFF613305);

  /// 9.10:1 sur [darkTertiaryContainer].
  static const Color darkOnTertiaryContainer = Color(0xFFFDEBD8);

  /// 7.44:1 sur [darkSurface]. Comme l'orange, le rose passe en texte de nuit.
  static const Color darkError = Color(0xFFFB7CAA);
  static const Color darkOnError = Color(0xFF131C23);

  /// 1.69:1 sur [darkSurface].
  static const Color darkErrorContainer = Color(0xFF6F203D);

  /// 8.24:1 sur [darkErrorContainer].
  static const Color darkOnErrorContainer = Color(0xFFFED7E5);

  /// Décoratif de nuit, jamais porteur d'état. 7.06:1 sur [darkSurface] — il
  /// serait lisible, mais la règle tient : il ne dit rien.
  static const Color darkAccentDecoratif = Color(0xFFCC84F0);

  /// 1.61:1 sur [darkSurface].
  static const Color darkAccentDecoratifFond = Color(0xFF522768);

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

  /// Accent posé sur [darkInverseSurface], qui est clair : c'est donc l'indigo
  /// de jour. 5.91:1.
  static const Color darkInversePrimary = accentTexte;
  static const Color darkShadow = Color(0xFF000000);

  // ---------------------------------------------------------------------
  // Encres d'état — thème clair
  //
  // Règle du monde visuel : sur un bloc teinté, le texte est l'encre du
  // registre (`etat*SurFond`), jamais une teinte. La teinte `etat*` ne sert
  // qu'au texte **sur blanc** et aux filets.
  // ---------------------------------------------------------------------

  /// Disponible : famille indigo. 7.31:1 sur [surface].
  static const Color etatDisponible = accentTexte;

  /// Remplissage de la case cochée. 4.72:1 sous [onPrimary].
  static const Color etatDisponiblePlein = primary;
  static const Color etatDisponibleFond = primaryContainer;

  /// 13.20:1 sur [etatDisponibleFond].
  static const Color etatDisponibleSurFond = onSurface;

  /// Absent, refusé : famille rose. 5.87:1 sur [surface], 4.49:1 en filet sur
  /// [etatAbsentFond].
  static const Color etatAbsent = error;
  static const Color etatAbsentFond = errorContainer;

  /// 13.19:1 sur [etatAbsentFond].
  static const Color etatAbsentSurFond = onSurface;

  static const Color etatNonSaisi = Color(0xFF52626C);

  /// Filet **porteur d'état** de la case non saisie. 3.33:1 sur `surfaceDim`.
  /// À ne jamais confondre avec [outlineVariant], qui est décoratif.
  static const Color etatNonSaisiFilet = Color(0xFF73828B);

  /// Attente : famille orange. 4.94:1 sur [surface], 4.22:1 en filet sur
  /// [etatAttenteFond] — filet, donc seuil 3:1 ; **le texte d'un bloc orange
  /// est [etatAttenteSurFond]**, pas cette teinte.
  static const Color etatAttente = tertiary;
  static const Color etatAttenteFond = tertiaryContainer;

  /// 14.72:1 sur [etatAttenteFond].
  static const Color etatAttenteSurFond = onSurface;

  static const Color etatNeutre = Color(0xFF45535C);
  static const Color etatNeutreFond = Color(0xFFE7EBEE);

  /// Information : famille verte. 6.61:1 sur [surface], assombri d'un cran par
  /// rapport à [secondary] pour tenir aussi en texte sur le papier.
  static const Color etatInfo = Color(0xFF086959);

  /// 7.02:1 sous [onSecondaryContainer].
  static const Color etatInfoFond = secondaryContainer;

  /// « Annulé » : un fait gris, pas une alarme. 10.61:1 sur [etatNeutreFond].
  static const Color etatAnnule = Color(0xFF2A343A);

  /// « Archivé » : atténué. 6.48:1 sur [etatArchiveFond].
  static const Color etatArchive = Color(0xFF4A5860);
  static const Color etatArchiveFond = Color(0xFFEEF1F3);

  /// « Mois verrouillé » : gris-encre, jamais rose. 7.49:1 sur son fond.
  static const Color etatVerrouille = Color(0xFF3A464E);
  static const Color etatVerrouilleFond = Color(0xFFDDE3E7);

  // ---------------------------------------------------------------------
  // Encres d'état — thème sombre
  // ---------------------------------------------------------------------

  /// 6.97:1 sur [darkSurface].
  static const Color darkEtatDisponible = darkPrimary;

  /// Remplissage de la case cochée, de nuit : 7.31:1 sous le glyphe blanc,
  /// 2.50:1 sur [darkSurface].
  static const Color darkEtatDisponiblePlein = Color(0xFF5840BC);
  static const Color darkEtatDisponibleFond = darkPrimaryContainer;

  /// 9.07:1 sur [darkEtatDisponibleFond].
  static const Color darkEtatDisponibleSurFond = darkOnPrimaryContainer;

  /// 7.44:1 sur [darkSurface].
  static const Color darkEtatAbsent = darkError;

  /// Filet porteur d'état sur le bloc rose : 4.39:1 sur [darkEtatAbsentFond].
  static const Color darkEtatAbsentFilet = darkError;
  static const Color darkEtatAbsentFond = darkErrorContainer;

  /// 8.24:1 sur [darkEtatAbsentFond].
  static const Color darkEtatAbsentSurFond = darkOnErrorContainer;

  static const Color darkEtatNonSaisi = Color(0xFFA4B1B9);
  static const Color darkEtatNonSaisiFilet = Color(0xFF6E7D87);

  /// 8.08:1 sur [darkSurface].
  static const Color darkEtatAttente = darkTertiary;
  static const Color darkEtatAttenteFond = darkTertiaryContainer;

  /// 9.10:1 sur [darkEtatAttenteFond].
  static const Color darkEtatAttenteSurFond = darkOnTertiaryContainer;

  static const Color darkEtatNeutre = Color(0xFFC4CFD6);
  static const Color darkEtatNeutreFond = Color(0xFF222C33);

  /// 6.72:1 sur [darkSurface].
  static const Color darkEtatInfo = darkSecondary;
  static const Color darkEtatInfoFond = darkSecondaryContainer;

  /// Encre lisible posée sur [darkEtatInfoFond] : `dark-on-secondary-container`,
  /// réemployé tel quel pour les pastilles vertes pleines. 8.67:1.
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
