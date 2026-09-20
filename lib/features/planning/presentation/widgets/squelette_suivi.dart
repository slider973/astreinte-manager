import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/loading_skeleton.dart';

/// Le squelette du suivi : **à la forme du contenu attendu**, jamais un
/// indicateur circulaire au milieu de l'écran (`DESIGN.md § Don't`).
///
/// Un bloc de progression, une barre de filtres, trois journées : ce que le
/// chef verra dans une demi-seconde, en gris.
class SqueletteSuivi extends StatelessWidget {
  const SqueletteSuivi({super.key});

  @override
  Widget build(BuildContext context) => LoadingSkeleton(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SkeletonBloc(hauteur: 160),
          const SizedBox(height: AppSpacing.xl),
          const SkeletonLigne(largeur: 240, hauteur: AppSpacing.xxl),
          const SizedBox(height: AppSpacing.lg),
          for (var journee = 0; journee < 3; journee++) ...<Widget>[
            const SkeletonLigne(largeur: 160),
            const SizedBox(height: AppSpacing.sm),
            const SkeletonBloc(hauteur: 56),
            const SizedBox(height: AppSpacing.sm),
            const SkeletonBloc(hauteur: 56),
            const SizedBox(height: AppSpacing.xl),
          ],
        ],
      ),
    ),
  );
}
