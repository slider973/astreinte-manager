import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/loading_skeleton.dart';

/// Le squelette de « Mes astreintes » : **à la forme du contenu attendu**,
/// jamais un indicateur circulaire au milieu de l'écran
/// (`DESIGN.md § Don't`).
///
/// Il n'apparaît que lorsqu'il n'y a **rien en cache** : dès qu'un instantané
/// local existe, c'est lui qu'on montre, et la requête part derrière
/// (`design/027 § 3`).
class SqueletteAstreintes extends StatelessWidget {
  const SqueletteAstreintes({super.key, this.lignes = 3});

  final int lignes;

  @override
  Widget build(BuildContext context) => LoadingSkeleton(
    child: SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // La bascule de vue, puis l'en-tête d'un mois, puis les lignes.
          const SkeletonLigne(hauteur: AppTouch.cible),
          const SizedBox(height: AppSpacing.xl),
          const SkeletonLigne(largeur: 200, hauteur: AppSpacing.xxl),
          const SizedBox(height: AppSpacing.sm),
          const SkeletonLigne(largeur: 110),
          const SizedBox(height: AppSpacing.lg),
          for (var ligne = 0; ligne < lignes; ligne++) ...<Widget>[
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonLigne(largeur: 48, hauteur: 40),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SkeletonLigne(largeur: 190),
                      SizedBox(height: AppSpacing.sm),
                      SkeletonLigne(largeur: 120, hauteur: AppSpacing.md),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ],
      ),
    ),
  );
}
