import 'package:flutter/material.dart';

/// Les deux familles embarquées.
///
/// Atkinson Hyperlegible a été dessinée par le Braille Institute pour
/// maximiser la distinction entre caractères en basse vision. Elle est choisie
/// pour une raison de brief : public de tous âges, lecture au soleil et en
/// mouvement, écrans pleins de chiffres où confondre `1`/`l`/`I` ou `0`/`O`
/// coûte une garde non couverte.
abstract final class AppFonts {
  /// Famille de texte. Provenance et sous-ensemble : `assets/fonts/README.md`.
  static const String texte = 'AtkinsonHyperlegibleNext';

  /// Famille à chasse fixe, pour tout nombre qui s'aligne ou change en place.
  static const String nombre = 'AtkinsonHyperlegibleMono';

  /// Replis système, dans l'ordre. Utilisés si un glyphe manque au
  /// sous-ensemble embarqué ou si le chargement échoue.
  ///
  /// **`Roboto` n'y figure pas volontairement.** Les replis listés ici sont
  /// tous résolus par le système, sans une seule requête réseau.
  ///
  /// Le moteur web, lui, garde un dernier recours à part, qu'il nomme
  /// `Roboto` et qu'aucun `TextStyle` ne peut lui retirer. Le ticket 037 l'a
  /// désamorcé là où il se règle : `pubspec.yaml` déclare une famille de ce
  /// nom, pointée sur l'Atkinson régulière. Sans cette déclaration, CanvasKit
  /// téléchargeait Roboto depuis `fonts.gstatic.com` à chaque démarrage —
  /// 63 Ko pris chez un tiers, sur une 4G rurale, pour une police qu'on
  /// n'affiche jamais.
  static const List<String> replis = <String>[
    'system-ui',
    '-apple-system',
    'Segoe UI',
    'sans-serif',
  ];
}

/// Styles typographiques du système.
///
/// Source : `DESIGN.md § Typography`. Échelle fixe de ratio ≈ 1.2, pas de
/// typographie fluide. Aucun widget n'écrit `TextStyle(fontSize: …)` : il
/// passe par `Theme.of(context).textTheme` ou par cette classe.
abstract final class AppTextStyles {
  /// Chiffres à chasse fixe : indispensable dès qu'une colonne de nombres
  /// s'aligne ou qu'un compteur change en place sans faire sauter la mise en
  /// page. Appliqué en plus de la famille Mono, jamais à sa place.
  static const List<FontFeature> chiffresTabulaires = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  // --- Texte -----------------------------------------------------------

  /// Titre d'écran (« Octobre 2026 »). 28 / 36 / 700.
  static const TextStyle titreEcran = TextStyle(
    fontFamily: AppFonts.texte,
    fontFamilyFallback: AppFonts.replis,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.28,
  );

  /// Barre d'application, titre de feuille. 22 / 28 / 700.
  static const TextStyle titreSection = TextStyle(
    fontFamily: AppFonts.texte,
    fontFamilyFallback: AppFonts.replis,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
  );

  /// En-tête de groupe, nom de membre. 18 / 24 / 600.
  static const TextStyle titreBloc = TextStyle(
    fontFamily: AppFonts.texte,
    fontFamilyFallback: AppFonts.replis,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
  );

  /// Texte de base. **Jamais plus petit pour une information nécessaire.**
  static const TextStyle corps = TextStyle(
    fontFamily: AppFonts.texte,
    fontFamilyFallback: AppFonts.replis,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );

  /// Texte de soutien. 14 / 20 / 400.
  static const TextStyle corpsSecondaire = TextStyle(
    fontFamily: AppFonts.texte,
    fontFamilyFallback: AppFonts.replis,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );

  /// Horodatage, note de bas de bloc. 13 / 18 / 400.
  static const TextStyle mention = TextStyle(
    fontFamily: AppFonts.texte,
    fontFamilyFallback: AppFonts.replis,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.13,
  );

  /// Libellé de bouton — **16, pas 14**. 16 / 20 / 600.
  static const TextStyle libelleAction = TextStyle(
    fontFamily: AppFonts.texte,
    fontFamilyFallback: AppFonts.replis,
    fontSize: 16,
    height: 20 / 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.16,
  );

  /// Libellé de champ, badge d'état. 14 / 18 / 600.
  static const TextStyle libelleChamp = TextStyle(
    fontFamily: AppFonts.texte,
    fontFamilyFallback: AppFonts.replis,
    fontSize: 14,
    height: 18 / 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.14,
  );

  /// En-tête de colonne, libellé de navigation. 12 / 16 / 700, +0.04em.
  static const TextStyle etiquette = TextStyle(
    fontFamily: AppFonts.texte,
    fontFamilyFallback: AppFonts.replis,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.48,
  );

  // --- Nombres ---------------------------------------------------------

  /// Compteur du mois, gros total. 32 / 36 / 700 mono.
  static const TextStyle displayNombre = TextStyle(
    fontFamily: AppFonts.nombre,
    fontFamilyFallback: AppFonts.replis,
    fontSize: 32,
    height: 36 / 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.32,
    fontFeatures: chiffresTabulaires,
  );

  /// Quota, compteur en ligne. 20 / 24 / 600 mono.
  static const TextStyle nombre = TextStyle(
    fontFamily: AppFonts.nombre,
    fontFamilyFallback: AppFonts.replis,
    fontSize: 20,
    height: 24 / 20,
    fontWeight: FontWeight.w600,
    fontFeatures: chiffresTabulaires,
  );

  /// Numéro du jour dans la grille, matrice. 15 / 18 / 600 mono.
  static const TextStyle nombrePetit = TextStyle(
    fontFamily: AppFonts.nombre,
    fontFamilyFallback: AppFonts.replis,
    fontSize: 15,
    height: 18 / 15,
    fontWeight: FontWeight.w600,
    fontFeatures: chiffresTabulaires,
  );

  /// `TextTheme` Material 3 complet, construit depuis l'échelle ci-dessus.
  ///
  /// Les rôles non employés par le système (`displayLarge`, `displayMedium`,
  /// `headlineLarge`, `headlineSmall`) sont quand même renseignés : un widget
  /// Material tiers qui les lit doit tomber sur la bonne famille, pas sur la
  /// police par défaut de la plateforme.
  static TextTheme textTheme(Color onSurface, Color onSurfaceVariant) {
    return TextTheme(
          displayLarge: displayNombre.copyWith(fontSize: 44, height: 48 / 44),
          displayMedium: displayNombre.copyWith(fontSize: 38, height: 42 / 38),
          displaySmall: displayNombre,
          headlineLarge: titreEcran.copyWith(fontSize: 32, height: 40 / 32),
          headlineMedium: titreEcran,
          headlineSmall: titreEcran.copyWith(fontSize: 24, height: 32 / 24),
          titleLarge: titreSection,
          titleMedium: titreBloc,
          titleSmall: libelleChamp,
          bodyLarge: corps,
          bodyMedium: corpsSecondaire,
          bodySmall: mention,
          labelLarge: libelleAction,
          labelMedium: libelleChamp,
          labelSmall: etiquette,
        )
        .apply(bodyColor: onSurface, displayColor: onSurface)
        .copyWith(bodySmall: mention.copyWith(color: onSurfaceVariant));
  }
}
