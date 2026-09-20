import 'dart:math' as math;

import 'package:astreinte_sp/core/theme/app_colors.dart';
import 'package:astreinte_sp/core/theme/app_status.dart';
import 'package:astreinte_sp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Luminance relative WCAG 2.1 d'une couleur opaque.
double _luminance(Color couleur) {
  double canal(double valeur) => valeur <= 0.03928
      ? valeur / 12.92
      : math.pow((valeur + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * canal(couleur.r) +
      0.7152 * canal(couleur.g) +
      0.0722 * canal(couleur.b);
}

/// Ratio de contraste WCAG entre deux couleurs opaques.
double ratio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Seuil WCAG AA pour le texte courant.
const double seuilTexte = 4.5;

/// Seuil WCAG AA pour un élément non textuel porteur d'information — ici, les
/// filets qui **disent un état** (case non saisie, sélection, case absente).
const double seuilFilet = 3;

void verifier(
  String nom,
  Color premierPlan,
  Color fond, {
  double seuil = seuilTexte,
}) {
  final valeur = ratio(premierPlan, fond);
  expect(
    valeur,
    greaterThanOrEqualTo(seuil),
    reason:
        '$nom : ${valeur.toStringAsFixed(2)}:1 entre '
        '${_hex(premierPlan)} et ${_hex(fond)}, minimum $seuil:1.',
  );
}

String _hex(Color couleur) =>
    '#${(couleur.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Toutes les paires texte/fond documentées dans `DESIGN.md § Colors`.
///
/// Le calcul est fait ici, pas à l'œil : un changement de couleur qui casse le
/// contraste fait échouer la suite, et le message dit quelle paire et de
/// combien. C'est la preuve exigée par le brief § 2.
void main() {
  group('Contraste — rôles Material 3', () {
    for (final (nom, theme) in <(String, ThemeData)>[
      ('clair', AppTheme.clair),
      ('sombre', AppTheme.sombre),
    ]) {
      group(nom, () {
        final scheme = theme.colorScheme;

        test('paires « on » / conteneur', () {
          verifier('onPrimary/primary', scheme.onPrimary, scheme.primary);
          verifier(
            'onPrimaryContainer/primaryContainer',
            scheme.onPrimaryContainer,
            scheme.primaryContainer,
          );
          verifier(
            'onSecondary/secondary',
            scheme.onSecondary,
            scheme.secondary,
          );
          verifier(
            'onSecondaryContainer/secondaryContainer',
            scheme.onSecondaryContainer,
            scheme.secondaryContainer,
          );
          verifier('onTertiary/tertiary', scheme.onTertiary, scheme.tertiary);
          verifier(
            'onTertiaryContainer/tertiaryContainer',
            scheme.onTertiaryContainer,
            scheme.tertiaryContainer,
          );
          verifier('onError/error', scheme.onError, scheme.error);
          verifier(
            'onErrorContainer/errorContainer',
            scheme.onErrorContainer,
            scheme.errorContainer,
          );
          verifier(
            'onInverseSurface/inverseSurface',
            scheme.onInverseSurface,
            scheme.inverseSurface,
          );
        });

        test('texte sur chaque cran de surface', () {
          final surfaces = <String, Color>{
            'surface': scheme.surface,
            'surfaceDim': scheme.surfaceDim,
            'surfaceContainerLowest': scheme.surfaceContainerLowest,
            'surfaceContainerLow': scheme.surfaceContainerLow,
            'surfaceContainer': scheme.surfaceContainer,
            'surfaceContainerHigh': scheme.surfaceContainerHigh,
            'surfaceContainerHighest': scheme.surfaceContainerHighest,
          };

          for (final entry in surfaces.entries) {
            verifier('onSurface/${entry.key}', scheme.onSurface, entry.value);
            verifier(
              'onSurfaceVariant/${entry.key}',
              scheme.onSurfaceVariant,
              entry.value,
            );
            // `outline` borde des contrôles : c'est un filet porteur de forme.
            verifier(
              'outline/${entry.key}',
              scheme.outline,
              entry.value,
              seuil: seuilFilet,
            );
          }
        });

        test('accents sur la surface de fond', () {
          verifier('secondary/surface', scheme.secondary, scheme.surface);
          verifier('tertiary/surface', scheme.tertiary, scheme.surface);
          verifier('error/surface', scheme.error, scheme.surface);
          verifier(
            'primary/surface',
            scheme.primary,
            scheme.surface,
            seuil: seuilFilet,
          );
        });
      });
    }
  });

  group('Contraste — encres d\'état', () {
    for (final (nom, statuts) in <(String, AppStatusColors)>[
      ('clair', AppStatusColors.clair),
      ('sombre', AppStatusColors.sombre),
    ]) {
      test('$nom : chaque descripteur est lisible sur son fond', () {
        for (final descripteur in statuts.tous) {
          verifier(
            'état « ${descripteur.libelle} »',
            descripteur.encre,
            descripteur.fond,
          );
        }
      });

      test('$nom : chaque filet porteur d\'état atteint 3:1', () {
        for (final descripteur in statuts.tous) {
          final filet = descripteur.filet;
          if (filet == null) continue;
          verifier(
            'filet de « ${descripteur.libelle} »',
            filet,
            descripteur.fond,
            seuil: seuilFilet,
          );
        }
      });
    }

    test('le filet de la case non saisie tient sur toutes ses surfaces', () {
      // La case non saisie se pose sur `surface` (jour), sur
      // `surface-container-high` (nuit) et sur `surface-dim` (fond de
      // grille). Les trois doivent tenir 3:1.
      verifier(
        'filet non saisi / surface',
        AppColors.etatNonSaisiFilet,
        AppColors.surface,
        seuil: seuilFilet,
      );
      verifier(
        'filet non saisi / surfaceContainerHigh',
        AppColors.etatNonSaisiFilet,
        AppColors.surfaceContainerHigh,
        seuil: seuilFilet,
      );
      verifier(
        'filet non saisi / surfaceDim',
        AppColors.etatNonSaisiFilet,
        AppColors.surfaceDim,
        seuil: seuilFilet,
      );
      verifier(
        'filet non saisi sombre / surface',
        AppColors.darkEtatNonSaisiFilet,
        AppColors.darkSurface,
        seuil: seuilFilet,
      );
      verifier(
        'filet non saisi sombre / surfaceContainerHigh',
        AppColors.darkEtatNonSaisiFilet,
        AppColors.darkSurfaceContainerHigh,
        seuil: seuilFilet,
      );
      verifier(
        'filet non saisi sombre / surfaceDim',
        AppColors.darkEtatNonSaisiFilet,
        AppColors.darkSurfaceDim,
        seuil: seuilFilet,
      );
    });

    test(
      'la réglure décorative reste décorative et n\'est jamais prise pour un '
      'filet d\'état',
      () {
        // `outline-variant` est volontairement sous 3:1 : s'il passait le
        // seuil, la tentation serait de lui faire porter un état.
        expect(
          ratio(AppColors.outlineVariant, AppColors.surface),
          lessThan(seuilFilet),
        );
        expect(
          ratio(AppColors.darkOutlineVariant, AppColors.darkSurface),
          lessThan(seuilFilet),
        );
      },
    );
  });

  group('Contraste — valeurs annoncées dans DESIGN.md', () {
    test('les ratios de tête sont bien ceux du document', () {
      expect(
        ratio(AppColors.onPrimary, AppColors.primary),
        closeTo(16.34, 0.02),
      );
      expect(
        ratio(AppColors.secondary, AppColors.surface),
        closeTo(7.41, 0.02),
      );
      expect(ratio(AppColors.tertiary, AppColors.surface), closeTo(6.92, 0.02));
      expect(ratio(AppColors.error, AppColors.surface), closeTo(7.47, 0.02));
      expect(
        ratio(AppColors.onSurface, AppColors.surface),
        closeTo(17.24, 0.02),
      );
      expect(
        ratio(AppColors.darkPrimary, AppColors.darkOnPrimary),
        closeTo(12.42, 0.02),
      );
      expect(
        ratio(AppColors.darkOnSurface, AppColors.darkSurface),
        closeTo(14.76, 0.02),
      );
    });

    test('l\'écart de valeur jour/nuit reste un repère, pas un état', () {
      // 1.18:1 : assez pour se repérer, trop peu pour être lu comme un état.
      expect(
        ratio(AppColors.surface, AppColors.surfaceContainerHigh),
        closeTo(1.18, 0.02),
      );
    });
  });
}
