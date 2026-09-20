import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/loading_skeleton.dart';

/// Le squelette des propositions : **à la forme du contenu attendu**, jamais
/// un indicateur circulaire au milieu de l'écran (`DESIGN.md § Don't`).
///
/// Un en-tête de mois et trois lignes — la marge du registre, le corps, la
/// rangée de deux boutons.
class SquelettePropositions extends StatelessWidget {
  const SquelettePropositions({super.key, this.lignes = 3});

  final int lignes;

  @override
  Widget build(BuildContext context) => LoadingSkeleton(
    // Défilable et **inerte** : rien à lire dessous, mais rien ne déborde non
    // plus sur un petit écran.
    child: SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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
                      SizedBox(height: AppSpacing.md),
                      SkeletonLigne(hauteur: AppTouch.bouton),
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
