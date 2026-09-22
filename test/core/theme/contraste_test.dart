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
          // `primary` est un **remplissage** depuis le ticket 061 : l'indigo
          // vif n'a pas à être lisible en ligne, il a à se voir. Le texte
          // indigo, lui, est `accentTexte`, vérifié plus bas à 4.5:1.
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

  /// Le monde visuel du ticket 061, paire par paire.
  ///
  /// Les valeurs d'accent viennent du superviseur ; les conteneurs sombres ont
  /// été dérivés ici. Le ratio attendu est écrit à côté de chaque paire **et**
  /// en commentaire dans `app_colors.dart` : les deux doivent rester d'accord,
  /// sinon l'un des deux ment.
  group('Contraste — le monde visuel du ticket 061', () {
    test('clair : tout ce qui est du texte tient 4.5:1', () {
      verifier('onPrimary/primary', AppColors.onPrimary, AppColors.primary);
      verifier(
        'onPrimaryContainer/primaryContainer',
        AppColors.onPrimaryContainer,
        AppColors.primaryContainer,
      );
      verifier('accentTexte/surface', AppColors.accentTexte, AppColors.surface);
      verifier(
        'accentTexte/surfaceContainerLow',
        AppColors.accentTexte,
        AppColors.surfaceContainerLow,
      );
      verifier(
        'onSecondary/secondary',
        AppColors.onSecondary,
        AppColors.secondary,
      );
      verifier(
        'onSecondaryContainer/secondaryContainer',
        AppColors.onSecondaryContainer,
        AppColors.secondaryContainer,
      );
      verifier('etatInfo/surface', AppColors.etatInfo, AppColors.surface);
      verifier('tertiary/surface', AppColors.tertiary, AppColors.surface);
      verifier('onTertiary/tertiary', AppColors.onTertiary, AppColors.tertiary);
      verifier(
        'onTertiaryContainer/tertiaryContainer',
        AppColors.onTertiaryContainer,
        AppColors.tertiaryContainer,
      );
      verifier('error/surface', AppColors.error, AppColors.surface);
      verifier('onError/error', AppColors.onError, AppColors.error);
      verifier(
        'onErrorContainer/errorContainer',
        AppColors.onErrorContainer,
        AppColors.errorContainer,
      );
      verifier(
        'onSurface/accentDecoratifFond',
        AppColors.onSurface,
        AppColors.accentDecoratifFond,
      );
      verifier(
        'inversePrimary/inverseSurface',
        AppColors.inversePrimary,
        AppColors.inverseSurface,
      );
    });

    test('clair : les quatre familles d\'état tiennent sur leur bloc', () {
      verifier(
        'etatDisponible/surface',
        AppColors.etatDisponible,
        AppColors.surface,
      );
      verifier(
        'onPrimary/etatDisponiblePlein',
        AppColors.onPrimary,
        AppColors.etatDisponiblePlein,
      );
      verifier(
        'etatDisponibleSurFond/etatDisponibleFond',
        AppColors.etatDisponibleSurFond,
        AppColors.etatDisponibleFond,
      );
      verifier('etatAttente/surface', AppColors.etatAttente, AppColors.surface);
      verifier(
        'etatAttenteSurFond/etatAttenteFond',
        AppColors.etatAttenteSurFond,
        AppColors.etatAttenteFond,
      );
      verifier('etatAbsent/surface', AppColors.etatAbsent, AppColors.surface);
      verifier(
        'etatAbsentSurFond/etatAbsentFond',
        AppColors.etatAbsentSurFond,
        AppColors.etatAbsentFond,
      );
      verifier(
        'etatInfo/etatInfoFond',
        AppColors.etatInfo,
        AppColors.etatInfoFond,
        seuil: seuilFilet,
      );
    });

    test('sombre : tout ce qui est du texte tient 4.5:1', () {
      verifier(
        'darkPrimary/darkSurface',
        AppColors.darkPrimary,
        AppColors.darkSurface,
      );
      verifier(
        'darkOnPrimary/darkPrimary',
        AppColors.darkOnPrimary,
        AppColors.darkPrimary,
      );
      verifier(
        'darkOnPrimaryContainer/darkPrimaryContainer',
        AppColors.darkOnPrimaryContainer,
        AppColors.darkPrimaryContainer,
      );
      verifier(
        'darkSecondary/darkSurface',
        AppColors.darkSecondary,
        AppColors.darkSurface,
      );
      verifier(
        'darkOnSecondary/darkSecondary',
        AppColors.darkOnSecondary,
        AppColors.darkSecondary,
      );
      verifier(
        'darkOnSecondaryContainer/darkSecondaryContainer',
        AppColors.darkOnSecondaryContainer,
        AppColors.darkSecondaryContainer,
      );
      verifier(
        'darkTertiary/darkSurface',
        AppColors.darkTertiary,
        AppColors.darkSurface,
      );
      verifier(
        'darkOnTertiary/darkTertiary',
        AppColors.darkOnTertiary,
        AppColors.darkTertiary,
      );
      verifier(
        'darkOnTertiaryContainer/darkTertiaryContainer',
        AppColors.darkOnTertiaryContainer,
        AppColors.darkTertiaryContainer,
      );
      verifier(
        'darkError/darkSurface',
        AppColors.darkError,
        AppColors.darkSurface,
      );
      verifier(
        'darkOnError/darkError',
        AppColors.darkOnError,
        AppColors.darkError,
      );
      verifier(
        'darkOnErrorContainer/darkErrorContainer',
        AppColors.darkOnErrorContainer,
        AppColors.darkErrorContainer,
      );
      verifier(
        'darkInversePrimary/darkInverseSurface',
        AppColors.darkInversePrimary,
        AppColors.darkInverseSurface,
      );
      verifier(
        'onPrimary/darkEtatDisponiblePlein',
        AppColors.onPrimary,
        AppColors.darkEtatDisponiblePlein,
      );
    });

    test('sombre : chaque conteneur dérivé se détache de la surface', () {
      // Cible de dérivation : 1.3:1 au moins. En dessous, un bloc d'état se
      // fond dans le fond de nuit et l'état disparaît pour qui ne lit pas le
      // libellé.
      const seuilDetachement = 1.3;
      final conteneurs = <String, Color>{
        'darkPrimaryContainer': AppColors.darkPrimaryContainer,
        'darkSecondaryContainer': AppColors.darkSecondaryContainer,
        'darkTertiaryContainer': AppColors.darkTertiaryContainer,
        'darkErrorContainer': AppColors.darkErrorContainer,
        'darkAccentDecoratifFond': AppColors.darkAccentDecoratifFond,
      };
      for (final entry in conteneurs.entries) {
        verifier(
          '${entry.key}/darkSurface',
          entry.value,
          AppColors.darkSurface,
          seuil: seuilDetachement,
        );
      }
    });

    test('l\'accent de texte tient sur tous les crans de surface', () {
      // C'est la raison d'être de `accentTexte` : `primary` passe sur blanc
      // (4.72:1) et échoue dès le premier panneau teinté. Un libellé de
      // bouton, un lien, le « toi » d'une liste se posent sur n'importe quel
      // cran — ils prennent donc l'indigo de texte, vérifié partout ici.
      for (final (nom, statuts, scheme)
          in <(String, AppStatusColors, ColorScheme)>[
            ('clair', AppStatusColors.clair, AppTheme.clair.colorScheme),
            ('sombre', AppStatusColors.sombre, AppTheme.sombre.colorScheme),
          ]) {
        final surfaces = <String, Color>{
          'surface': scheme.surface,
          'surfaceContainerLow': scheme.surfaceContainerLow,
          'surfaceContainer': scheme.surfaceContainer,
          'surfaceContainerHigh': scheme.surfaceContainerHigh,
          'surfaceContainerHighest': scheme.surfaceContainerHighest,
          'surfaceDim': scheme.surfaceDim,
        };
        for (final entry in surfaces.entries) {
          verifier(
            '$nom : accentTexte/${entry.key}',
            statuts.accentTexte,
            entry.value,
          );
        }
      }
    });

    test('sombre : le filet du bloc rose porte encore son état', () {
      verifier(
        'darkEtatAbsentFilet/darkEtatAbsentFond',
        AppColors.darkEtatAbsentFilet,
        AppColors.darkEtatAbsentFond,
        seuil: seuilFilet,
      );
    });

    test(
      'les trois teintes vives de la charte restent sous le seuil du texte',
      () {
        // Ce n'est pas un regret, c'est la garde : `orangeVif`, `roseVif` et
        // `accentDecoratif` sont des remplissages. Tant qu'ils échouent ici,
        // personne ne peut les glisser dans un `TextStyle` en croyant bien
        // faire — et les versions lisibles existent à côté (`tertiary`,
        // `error`, l'encre du registre).
        expect(
          ratio(AppColors.orangeVif, AppColors.surface),
          lessThan(seuilTexte),
        );
        expect(
          ratio(AppColors.roseVif, AppColors.surface),
          lessThan(seuilTexte),
        );
        expect(
          ratio(AppColors.accentDecoratif, AppColors.surface),
          lessThan(seuilTexte),
        );
      },
    );
  });

  group('Contraste — valeurs annoncées dans les tokens', () {
    test('les ratios de tête sont bien ceux écrits en commentaire', () {
      expect(
        ratio(AppColors.onPrimary, AppColors.primary),
        closeTo(4.72, 0.02),
      );
      expect(
        ratio(AppColors.secondary, AppColors.surface),
        closeTo(5.12, 0.02),
      );
      expect(ratio(AppColors.tertiary, AppColors.surface), closeTo(4.94, 0.02));
      expect(ratio(AppColors.error, AppColors.surface), closeTo(5.87, 0.02));
      expect(
        ratio(AppColors.onSurface, AppColors.surface),
        closeTo(17.24, 0.02),
      );
      expect(
        ratio(AppColors.darkPrimary, AppColors.darkOnPrimary),
        closeTo(6.58, 0.02),
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
