import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_elevation.dart';
import 'app_motion.dart';
import 'app_spacing.dart';
import 'app_status.dart';
import 'app_typography.dart';

/// Les deux thèmes de l'application.
///
/// Les `ColorScheme` sont écrits **valeur par valeur** : `ColorScheme.fromSeed`
/// est refusé par le brief parce qu'une graine recalcule les tons et casse les
/// contrastes vérifiés dans `DESIGN.md § Colors`.
///
/// Écarts assumés au Material 3 par défaut, à ne pas « corriger » :
/// pas de boutons en gélule (rayon 8), pas d'ombre sur le contenu, libellés de
/// navigation toujours visibles, libellé de bouton à 16 sp et non 14.
abstract final class AppTheme {
  /// Thème clair — celui par défaut : la scène dominante est le plein soleil.
  static ThemeData get clair => _construire(
    brightness: Brightness.light,
    scheme: const ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.onSecondaryContainer,
      tertiary: AppColors.tertiary,
      onTertiary: AppColors.onTertiary,
      tertiaryContainer: AppColors.tertiaryContainer,
      onTertiaryContainer: AppColors.onTertiaryContainer,
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      onSurfaceVariant: AppColors.onSurfaceVariant,
      surfaceDim: AppColors.surfaceDim,
      surfaceBright: AppColors.surface,
      surfaceContainerLowest: AppColors.surfaceContainerLowest,
      surfaceContainerLow: AppColors.surfaceContainerLow,
      surfaceContainer: AppColors.surfaceContainer,
      surfaceContainerHigh: AppColors.surfaceContainerHigh,
      surfaceContainerHighest: AppColors.surfaceContainerHighest,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
      inverseSurface: AppColors.inverseSurface,
      onInverseSurface: AppColors.onInverseSurface,
      inversePrimary: AppColors.inversePrimary,
      shadow: AppColors.shadow,
      scrim: AppColors.shadow,
    ),
    statuts: AppStatusColors.clair,
    pression: AppColors.pressionSombre,
  );

  /// Thème sombre — la salle de garde à 3 h du matin. La relation s'inverse :
  /// le papier devient l'accent, l'encre devient le fond.
  static ThemeData get sombre => _construire(
    brightness: Brightness.dark,
    scheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.darkOnPrimary,
      primaryContainer: AppColors.darkPrimaryContainer,
      onPrimaryContainer: AppColors.darkOnPrimaryContainer,
      secondary: AppColors.darkSecondary,
      onSecondary: AppColors.darkOnSecondary,
      secondaryContainer: AppColors.darkSecondaryContainer,
      onSecondaryContainer: AppColors.darkOnSecondaryContainer,
      tertiary: AppColors.darkTertiary,
      onTertiary: AppColors.darkOnTertiary,
      tertiaryContainer: AppColors.darkTertiaryContainer,
      onTertiaryContainer: AppColors.darkOnTertiaryContainer,
      error: AppColors.darkError,
      onError: AppColors.darkOnError,
      errorContainer: AppColors.darkErrorContainer,
      onErrorContainer: AppColors.darkOnErrorContainer,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkOnSurface,
      onSurfaceVariant: AppColors.darkOnSurfaceVariant,
      surfaceDim: AppColors.darkSurfaceDim,
      surfaceBright: AppColors.darkSurfaceContainerHighest,
      surfaceContainerLowest: AppColors.darkSurfaceContainerLowest,
      surfaceContainerLow: AppColors.darkSurfaceContainerLow,
      surfaceContainer: AppColors.darkSurfaceContainer,
      surfaceContainerHigh: AppColors.darkSurfaceContainerHigh,
      surfaceContainerHighest: AppColors.darkSurfaceContainerHighest,
      outline: AppColors.darkOutline,
      outlineVariant: AppColors.darkOutlineVariant,
      inverseSurface: AppColors.darkInverseSurface,
      onInverseSurface: AppColors.darkOnInverseSurface,
      inversePrimary: AppColors.darkInversePrimary,
      shadow: AppColors.darkShadow,
      scrim: AppColors.darkShadow,
    ),
    statuts: AppStatusColors.sombre,
    pression: AppColors.pressionClaire,
  );

  static ThemeData _construire({
    required Brightness brightness,
    required ColorScheme scheme,
    required AppStatusColors statuts,
    required Color pression,
  }) {
    final textTheme = AppTextStyles.textTheme(
      scheme.onSurface,
      scheme.onSurfaceVariant,
    );
    final sombre = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      textTheme: textTheme,
      fontFamily: AppFonts.texte,
      fontFamilyFallback: AppFonts.replis,
      extensions: <ThemeExtension<dynamic>>[statuts],
      shadowColor: AppShadows.teinte(brightness),

      // Caret, sélection de texte et poignées : le rendu par défaut de Flutter
      // web sort du système (bleu Material). On le ramène sur l'encre.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.24),
        selectionHandleColor: scheme.primary,
      ),

      // Anneau de focus : 2 dp `primary`, visible sur tous les fonds, jamais
      // supprimé (`DESIGN.md § Shapes`). Flutter n'expose pas de
      // `FocusTheme` ; l'anneau passe par `focusColor` et par le
      // `WidgetStateProperty` de chaque thème de composant ci-dessous.
      focusColor: scheme.primary.withValues(alpha: 0.12),
      hoverColor: scheme.primary.withValues(alpha: 0.06),
      highlightColor: pression,
      splashColor: pression,

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        },
      ),

      // --- Séparation : le filet, pas l'ombre --------------------------
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: AppStroke.filet,
        space: AppStroke.filet,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.controleRadius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      // --- Barre d'application -----------------------------------------
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: sombre
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),

      // --- Boutons : des blocs à rayon 8, jamais des gélules ------------
      filledButtonTheme: FilledButtonThemeData(
        style: _styleBouton(
          fond: scheme.primary,
          encre: scheme.onPrimary,
          desactiveFond: scheme.surfaceContainerHighest,
          desactiveEncre: scheme.outline,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _styleBouton(
          fond: scheme.surface,
          encre: scheme.primary,
          desactiveFond: scheme.surfaceContainerHighest,
          desactiveEncre: scheme.outline,
          textStyle: textTheme.labelLarge,
          bordure: scheme.outline,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
          minimumSize: const Size(AppTouch.cible, AppTouch.cible),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.controleRadius,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size(AppTouch.cible, AppTouch.cible),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.controleRadius,
          ),
        ),
      ),

      // --- Champs -------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        // 16 sp minimum : en dessous, iOS zoome à la saisie.
        hintStyle: textTheme.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        errorStyle: textTheme.bodyMedium?.copyWith(color: scheme.error),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg - 2,
        ),
        border: _bordureChamp(scheme.outline, AppStroke.filet),
        enabledBorder: _bordureChamp(scheme.outline, AppStroke.filet),
        focusedBorder: _bordureChamp(scheme.primary, AppStroke.etat),
        errorBorder: _bordureChamp(scheme.error, AppStroke.etat),
        focusedErrorBorder: _bordureChamp(scheme.error, AppStroke.etat),
        disabledBorder: _bordureChamp(scheme.outlineVariant, AppStroke.filet),
      ),

      // --- Navigation ---------------------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: AppRadius.controleRadius,
        ),
        elevation: 0,
        height: AppTouch.navigation,
        // Aisance numérique variable : une icône seule ne suffit pas.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: AppTouch.icone + 4,
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: AppRadius.controleRadius,
        ),
        elevation: 0,
        labelType: NavigationRailLabelType.all,
        selectedLabelTextStyle: textTheme.labelSmall?.copyWith(
          color: scheme.onSurface,
        ),
        unselectedLabelTextStyle: textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        selectedIconTheme: IconThemeData(
          size: AppTouch.icone + 4,
          color: scheme.onPrimaryContainer,
        ),
        unselectedIconTheme: IconThemeData(
          size: AppTouch.icone + 4,
          color: scheme.onSurfaceVariant,
        ),
      ),

      // --- Surfaces qui flottent vraiment -------------------------------
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surface,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.feuilleRadius,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyLarge,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.feuille)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: textTheme.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.controleRadius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyLarge?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.controleRadius,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: AppRadius.caseRegistreRadius,
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
        waitDuration: AppDuration.surface,
      ),

      // --- Puces et contrôles -------------------------------------------
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primaryContainer,
        disabledColor: scheme.surfaceContainerHighest,
        labelStyle: textTheme.labelMedium,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.caseRegistreRadius,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(
          scheme.outline.withValues(alpha: 0.6),
        ),
        radius: const Radius.circular(AppRadius.caseRegistre),
        thickness: const WidgetStatePropertyAll<double>(AppSpacing.sm),
        crossAxisMargin: AppSpacing.xxs,
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: AppSpacing.md,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        iconColor: scheme.onSurfaceVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.controleRadius,
        ),
      ),
    );
  }

  static ButtonStyle _styleBouton({
    required Color fond,
    required Color encre,
    required Color desactiveFond,
    required Color desactiveEncre,
    required TextStyle? textStyle,
    Color? bordure,
  }) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.disabled) ? desactiveFond : fond,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.disabled) ? desactiveEncre : encre,
      ),
      // 8 % d'encre en surimpression à l'appui : la largeur ne bouge pas.
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.pressed)
            ? encre.withValues(alpha: 0.12)
            : states.contains(WidgetState.focused)
            ? encre.withValues(alpha: 0.08)
            : null,
      ),
      textStyle: WidgetStatePropertyAll<TextStyle?>(textStyle),
      elevation: const WidgetStatePropertyAll<double>(0),
      shadowColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      minimumSize: const WidgetStatePropertyAll<Size>(
        Size(AppTouch.cible, AppTouch.bouton),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      ),
      side: bordure == null
          ? null
          : WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? desactiveEncre
                    : bordure,
              ),
            ),
      shape: const WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(borderRadius: AppRadius.controleRadius),
      ),
    );
  }

  static OutlineInputBorder _bordureChamp(Color couleur, double epaisseur) {
    return OutlineInputBorder(
      borderRadius: AppRadius.controleRadius,
      borderSide: BorderSide(color: couleur, width: epaisseur),
    );
  }
}
