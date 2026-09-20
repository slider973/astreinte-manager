import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/loading_skeleton.dart';
import 'geometrie_matrice.dart';

/// Le chargement, **à la forme de la matrice qui va s'afficher** : colonne
/// figée, en-tête de dates, damier de cases.
///
/// Jamais un `CircularProgressIndicator` au milieu de l'écran
/// (`DESIGN.md § Don't`). Douze lignes : de quoi remplir l'écran sans
/// promettre un effectif qu'on ne connaît pas encore.
class SqueletteMatrice extends StatelessWidget {
  const SqueletteMatrice({super.key, this.lignes = 12});

  final int lignes;

  /// Le squelette ne dessine jamais plus de colonnes que ça, quelle que soit
  /// la largeur de l'écran.
  static const int _colonnesMax = 16;

  @override
  Widget build(BuildContext context) {
    final largeurFigee = GeoMatrice.colonneFigee(AppWindowClass.of(context));

    return LoadingSkeleton(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints contraintes) {
            // Arrondi **par le bas** : un squelette qui déborde sa largeur
            // est un défaut de mise en page, pas une approximation.
            //
            // **Et borné à seize colonnes.** Le balayage du squelette
            // repeint tout son sous-arbre à chaque image : sur un poste de
            // 1 920 px, cinquante colonnes × douze lignes coûtaient 73 ms par
            // image pendant toute la lecture du mois, et retardaient la
            // première image de la grille de plus d'une seconde. Mesuré au
            // navigateur, en `--profile` (voir la PR du ticket 016). Un
            // squelette dit une forme ; il n'a pas à la dire en entier.
            final colonnes = math.min(
              _colonnesMax,
              math.max(
                1,
                (contraintes.maxWidth - largeurFigee) ~/
                    (GeoMatrice.colonne + GeoMatrice.ecartCreneaux),
              ),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: largeurFigee,
                      child: const SkeletonLigne(largeur: 120),
                    ),
                    for (var colonne = 0; colonne < colonnes; colonne++)
                      const Padding(
                        padding: EdgeInsets.only(
                          right: GeoMatrice.ecartCreneaux,
                        ),
                        child: SkeletonLigne(
                          largeur: GeoMatrice.colonne,
                          hauteur: GeoMatrice.hauteurEntete - AppSpacing.sm,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                for (var ligne = 0; ligne < lignes; ligne++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: largeurFigee,
                          child: SkeletonLigne(
                            largeur: 160 - (ligne.isEven ? 0 : 24),
                          ),
                        ),
                        for (var colonne = 0; colonne < colonnes; colonne++)
                          const Padding(
                            padding: EdgeInsets.only(
                              right: GeoMatrice.ecartCreneaux,
                            ),
                            child: SkeletonLigne(
                              largeur: GeoMatrice.colonne,
                              hauteur: GeoMatrice.colonne,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
