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

  /// La sélection indigo et le vert de l'accepté, mesurés séparément.
  ///
  /// Deux teintes, deux sens, et deux pastilles qui se posent sous du texte :
  /// `primary-container` derrière ce qui est **choisi** (segment, puce, mois,
  /// jour, destination), `secondary-container` derrière ce qui est **acquis**
  /// (accepté, couvert, validé, publié). Tout ce qui se pose dessus est
  /// vérifié ici.
  group('Contraste — la pastille de sélection et le bloc de l\'accepté', () {
    for (final (nom, scheme) in <(String, ColorScheme)>[
      ('clair', AppTheme.clair.colorScheme),
      ('sombre', AppTheme.sombre.colorScheme),
    ]) {
      test('$nom : la pastille de sélection porte son texte et son filet', () {
        // Libellé d'un segment ou d'une puce choisie.
        verifier(
          'onPrimaryContainer/primaryContainer',
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
        );
        // Encre du registre : le nombre du jour choisi, le nom du mois choisi.
        verifier(
          'onSurface/primaryContainer',
          scheme.onSurface,
          scheme.primaryContainer,
        );
        // Texte de soutien de la même pastille : le jour de la semaine
        // au-dessus du quantième, la ligne d'état sous le nom du mois.
        verifier(
          'onSurfaceVariant/primaryContainer',
          scheme.onSurfaceVariant,
          scheme.primaryContainer,
        );
        // Le filet de sélection, 2 dp : porteur d'état, donc 3:1.
        verifier(
          'primary/primaryContainer',
          scheme.primary,
          scheme.primaryContainer,
          seuil: seuilFilet,
        );
        verifier(
          'primary/surface',
          scheme.primary,
          scheme.surface,
          seuil: seuilFilet,
        );
        // La pastille doit se détacher du papier, sans quoi « choisi » ne se
        // voit plus : même cible de 1.3:1 que les conteneurs de nuit.
        verifier(
          'primaryContainer/surface',
          scheme.primaryContainer,
          scheme.surface,
          seuil: 1.3,
        );
      });
    }

    test('clair : le vert de l\'accepté', () {
      verifier(
        'etatAccepteSurFond/etatAccepteFond',
        AppColors.etatAccepteSurFond,
        AppColors.etatAccepteFond,
      );
      verifier(
        'etatInfoSurFond/etatInfoFond',
        AppColors.etatInfoSurFond,
        AppColors.etatInfoFond,
      );
      // Le vert est, avec l'indigo de texte, la seule teinte d'état lisible
      // sur blanc : c'est ce qui autorise « Enregistré » en texte vert.
      verifier('etatAccepte/surface', AppColors.etatAccepte, AppColors.surface);
      verifier(
        'etatAccepteFond/surface',
        AppColors.etatAccepteFond,
        AppColors.surface,
        seuil: 1.3,
      );
    });

    test('sombre : le vert de l\'accepté', () {
      verifier(
        'darkEtatAccepteSurFond/darkEtatAccepteFond',
        AppColors.darkEtatAccepteSurFond,
        AppColors.darkEtatAccepteFond,
      );
      verifier(
        'darkEtatAccepte/darkSurface',
        AppColors.darkEtatAccepte,
        AppColors.darkSurface,
      );
      verifier(
        'darkEtatAccepteFond/darkSurface',
        AppColors.darkEtatAccepteFond,
        AppColors.darkSurface,
        seuil: 1.3,
      );
    });

    test('les deux pastilles ont la même valeur : c\'est la marque qui les '
        'sépare, pas la teinte', () {
      // 1.01:1 en clair, 1.06:1 en nuit : en niveaux de gris, la pastille
      // indigo et le bloc vert sont **le même gris**. C'est mesuré ici pour
      // qu'on ne se raconte pas l'inverse : rien de ce qui distingue
      // « choisi » de « accepté » ne peut reposer sur la couleur. L'icône
      // et le libellé le font, et le système les rend obligatoires
      // (`StatusDescriptor`).
      expect(
        ratio(AppColors.primaryContainer, AppColors.etatAccepteFond),
        lessThan(1.1),
      );
      expect(
        ratio(AppColors.darkPrimaryContainer, AppColors.darkEtatAccepteFond),
        lessThan(1.1),
      );

      final acceptee = AppStatusColors.clair.attribution(
        AttributionEtat.accepte,
      );
      final disponible = AppStatusColors.clair.disponibilite(
        DisponibiliteEtat.disponible,
      );
      expect(acceptee.icone, isNot(disponible.icone));
      expect(acceptee.libelle, isNot(disponible.libelle));
    });

    test('les ratios écrits dans `app_colors.dart` sont les vrais', () {
      expect(
        ratio(AppColors.etatAccepte, AppColors.surface),
        closeTo(6.61, 0.02),
      );
      expect(
        ratio(AppColors.etatAccepteSurFond, AppColors.etatAccepteFond),
        closeTo(7.02, 0.02),
      );
      expect(
        ratio(AppColors.etatAccepteFond, AppColors.surface),
        closeTo(1.32, 0.02),
      );
      expect(
        ratio(AppColors.darkEtatAccepte, AppColors.darkSurface),
        closeTo(6.72, 0.02),
      );
      expect(
        ratio(AppColors.darkEtatAccepteSurFond, AppColors.darkEtatAccepteFond),
        closeTo(8.67, 0.02),
      );
      expect(
        ratio(AppColors.darkEtatAccepteFond, AppColors.darkSurface),
        closeTo(1.63, 0.02),
      );
      expect(
        ratio(AppColors.onPrimaryContainer, AppColors.primaryContainer),
        closeTo(6.74, 0.02),
      );
      expect(
        ratio(AppColors.primary, AppColors.primaryContainer),
        closeTo(3.61, 0.02),
      );
      expect(
        ratio(AppColors.darkPrimary, AppColors.darkPrimaryContainer),
        closeTo(4.52, 0.02),
      );
    });
  });

  // -------------------------------------------------------------------
  // Les blocs pleins d'attribution, dans la case de la matrice
  // -------------------------------------------------------------------

  /// **Deux mesures par état, et aucune n'est optionnelle** (chantier 061c-2) :
  /// le glyphe doit se voir sur son bloc, et le bloc doit se détacher du papier
  /// de la grille. Ce sont des éléments non textuels porteurs d'information :
  /// le seuil est 3:1 (WCAG 1.4.11), pas 4,5:1.
  ///
  /// La grille a **deux papiers** : `surface` en semaine, `surface-dim` sur les
  /// colonnes de weekend et de jour férié (`FondJour`). Les deux sont mesurés —
  /// un bloc qui ne se verrait que du lundi au vendredi serait un bloc qui
  /// disparaît les jours où l'astreinte compte le plus.
  group('Contraste — les blocs pleins d\'attribution', () {
    const etats = <AttributionEtat>[
      AttributionEtat.propose,
      AttributionEtat.accepte,
      AttributionEtat.refuse,
    ];

    test('clair : le glyphe se voit sur son bloc', () {
      for (final etat in etats) {
        final bloc = AppStatusColors.clair.attribution(etat);
        verifier(
          'glyphe/bloc ${etat.name}',
          bloc.blocEncre,
          bloc.blocFond,
          seuil: seuilFilet,
        );
      }
    });

    test('sombre : le glyphe se voit sur son bloc', () {
      for (final etat in etats) {
        final bloc = AppStatusColors.sombre.attribution(etat);
        verifier(
          'glyphe/bloc ${etat.name}',
          bloc.blocEncre,
          bloc.blocFond,
          seuil: seuilFilet,
        );
      }
    });

    test('la limite du bloc se détache des deux papiers de la grille', () {
      for (final (nom, statuts, papier, weekend)
          in <(String, AppStatusColors, Color, Color)>[
        (
          'clair',
          AppStatusColors.clair,
          AppColors.surface,
          AppColors.surfaceDim,
        ),
        (
          'sombre',
          AppStatusColors.sombre,
          AppColors.darkSurface,
          AppColors.darkSurfaceDim,
        ),
      ]) {
        for (final etat in etats) {
          final bloc = statuts.attribution(etat);
          // **Le contour compte quand le remplissage ne suffit pas.** L'orange
          // vif de la charte ne fait que 1,90:1 sur le fond de weekend ; c'est
          // son filet ocre qui porte la limite, et c'est lui qu'on mesure
          // alors. Aucun des trois n'a le droit de se passer des deux.
          final limite = bloc.filet ?? bloc.blocFond;
          verifier(
            '$nom bloc/papier ${etat.name}',
            limite,
            papier,
            seuil: seuilFilet,
          );
          verifier(
            '$nom bloc/weekend ${etat.name}',
            limite,
            weekend,
            seuil: seuilFilet,
          );
        }
      }
    });

    test('les ratios consignés dans `DESIGN.md § 061c-2` sont les vrais', () {
      const clair = AppStatusColors.clair;
      const sombre = AppStatusColors.sombre;

      double glyphe(AppStatusColors s, AttributionEtat e) =>
          ratio(s.attribution(e).blocEncre, s.attribution(e).blocFond);
      double papier(AppStatusColors s, AttributionEtat e, Color fond) =>
          ratio(s.attribution(e).blocFond, fond);

      // Clair — glyphe sur le bloc.
      expect(glyphe(clair, AttributionEtat.propose), closeTo(7.64, 0.02));
      expect(glyphe(clair, AttributionEtat.accepte), closeTo(5.12, 0.02));
      expect(glyphe(clair, AttributionEtat.refuse), closeTo(4.78, 0.02));

      // Clair — le bloc sur le papier blanc de la grille.
      expect(
        papier(clair, AttributionEtat.propose, AppColors.surface),
        closeTo(2.26, 0.02),
      );
      expect(
        ratio(AppColors.etatAttente, AppColors.surface),
        closeTo(4.94, 0.02),
      );
      expect(
        papier(clair, AttributionEtat.accepte, AppColors.surface),
        closeTo(5.12, 0.02),
      );
      expect(
        papier(clair, AttributionEtat.refuse, AppColors.surface),
        closeTo(3.60, 0.02),
      );
      expect(
        papier(clair, AttributionEtat.refuse, AppColors.surfaceDim),
        closeTo(3.03, 0.02),
      );

      // Sombre — glyphe sur le bloc, puis le bloc sur le papier de nuit.
      expect(glyphe(sombre, AttributionEtat.propose), closeTo(7.64, 0.02));
      expect(glyphe(sombre, AttributionEtat.accepte), closeTo(6.35, 0.02));
      expect(glyphe(sombre, AttributionEtat.refuse), closeTo(7.03, 0.02));
      expect(
        papier(sombre, AttributionEtat.propose, AppColors.darkSurface),
        closeTo(8.08, 0.02),
      );
      expect(
        papier(sombre, AttributionEtat.accepte, AppColors.darkSurface),
        closeTo(6.72, 0.02),
      );
      expect(
        papier(sombre, AttributionEtat.refuse, AppColors.darkSurface),
        closeTo(7.44, 0.02),
      );
    });

    test('les trois blocs se distinguent entre eux, et de la case '
        '« disponible » qu\'ils remplacent', () {
      const clair = AppStatusColors.clair;
      final disponible = clair.disponibilite(DisponibiliteEtat.disponible).fond;

      // **Le bloc pèse au moins autant que la coche qu'il remplace** : c'est
      // toute la correction du 061c-2. Aucune des trois teintes fortes n'est
      // plus proche du papier que l'indigo plein ne l'est.
      final indigo = ratio(disponible, AppColors.surface);
      for (final etat in etats) {
        final bloc = clair.attribution(etat);
        final limite = bloc.filet ?? bloc.blocFond;
        expect(
          ratio(limite, AppColors.surface),
          greaterThanOrEqualTo(indigo - 2.5),
          reason:
              '${etat.name} s\'efface devant la coche « disponible » '
              '(${indigo.toStringAsFixed(2)}:1).',
        );
      }
    });
  });

  group('Contraste — les cartes de l\'accueil (ticket 064)', () {
    // Trois cartes de 144 × 168, lues à un mètre, au soleil, avec des gants.
    // Le brief du 064 nomme les deux paires : `onPrimary` sur `primary` pour
    // l'astreinte acceptée, `onSurface` sur `orangeVif` pour la proposition
    // en attente. La troisième, le jour libre, est un cran de surface.
    for (final theme in <(String, AppStatusColors, ColorScheme)>[
      ('clair', AppStatusColors.clair, AppTheme.clair.colorScheme),
      ('sombre', AppStatusColors.sombre, AppTheme.sombre.colorScheme),
    ]) {
      group(theme.$1, () {
        final statuts = theme.$2;
        final scheme = theme.$3;
        final propose = statuts.attribution(AttributionEtat.propose);

        test('la carte acceptée : encre sur l\'indigo plein', () {
          verifier('onPrimary/primary', scheme.onPrimary, scheme.primary);
        });

        test('la carte en attente : encre sur l\'orange vif', () {
          verifier(
            'blocEncre/blocFond (propose)',
            propose.blocEncre,
            propose.blocFond,
          );
        });

        test('la carte libre : encre sur le cran de surface', () {
          verifier(
            'onSurface/surfaceContainerHigh',
            scheme.onSurface,
            scheme.surfaceContainerHigh,
          );
        });

        test('les trois cartes se détachent du fond de page', () {
          // Un élément non textuel porteur d'information tient 3:1
          // (WCAG 1.4.11). L'orange ne le tient pas sur le papier : c'est son
          // contour `etatAttente` qui porte la limite, comme dans la matrice.
          final page = scheme.surfaceContainerLow;
          verifier(
            'primary/surfaceContainerLow',
            scheme.primary,
            page,
            seuil: seuilFilet,
          );
          verifier(
            'filet de la proposition/surfaceContainerLow',
            propose.filet ?? propose.blocFond,
            page,
            seuil: seuilFilet,
          );
        });

        test('le carré d\'initiale d\'une ligne de proposition', () {
          verifier(
            'onPrimaryContainer/primaryContainer',
            scheme.onPrimaryContainer,
            scheme.primaryContainer,
          );
        });

        test('la carte d\'appel à saisir ses disponibilités', () {
          verifier(
            'onPrimaryContainer/primaryContainer',
            scheme.onPrimaryContainer,
            scheme.primaryContainer,
          );
        });

        test('les points de la bande de semaine se voient sur le papier', () {
          final page = scheme.surfaceContainerLow;
          verifier(
            'point indigo/surfaceContainerLow',
            scheme.primary,
            page,
            seuil: seuilFilet,
          );
          // Le point orange est **doublé par la phrase du jour** : il ne porte
          // rien tout seul, et c'est la règle du système qui le permet
          // (`DESIGN.md § Do's`). On mesure quand même ce qu'il vaut.
          expect(
            ratio(propose.blocFond, page),
            greaterThan(1.5),
            reason: 'le point orange disparaîtrait dans le papier',
          );
        });
      });
    }
  });
}
