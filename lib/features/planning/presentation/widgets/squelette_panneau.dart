import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/loading_skeleton.dart';

/// Le squelette du panneau des candidats.
///
/// Il n'apparaît que sur l'écran de suivi : la matrice a déjà lu ses lignes et
/// son planning quand on y touche un créneau, tandis que le suivi ne les lit
/// **qu'à l'ouverture du panneau** — deux requêtes qu'on ne fait pas payer au
/// chargement de l'écran (`design/020 § 7.5`).
///
/// À la forme du contenu attendu : un en-tête, un champ d'effectif, un titre et
/// des lignes de noms. Jamais un indicateur circulaire (`DESIGN.md § Don't`).
class SquelettePanneau extends StatelessWidget {
  const SquelettePanneau({super.key});

  @override
  Widget build(BuildContext context) => LoadingSkeleton(
    semanticsLabel: AppStrings.reattributionChargement,
    child: SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SkeletonLigne(largeur: 200, hauteur: AppSpacing.xl),
          const SizedBox(height: AppSpacing.sm),
          const SkeletonLigne(largeur: 96),
          const SizedBox(height: AppSpacing.lg),
          const SkeletonBloc(hauteur: 56),
          const SizedBox(height: AppSpacing.xl),
          const SkeletonLigne(largeur: 140),
          const SizedBox(height: AppSpacing.md),
          for (var ligne = 0; ligne < 5; ligne++) ...<Widget>[
            const SkeletonBloc(hauteur: 64),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    ),
  );
}
