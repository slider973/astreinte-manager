import 'package:flutter/material.dart';

import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/loading_skeleton.dart';

/// L'ossature d'un onglet de la Boîte : quatre cartes de liste.
///
/// **À la forme du contenu attendu**, jamais un indicateur circulaire au
/// milieu de l'écran (`DESIGN.md § Don't`). La hauteur est celle d'une carte
/// de proposition ou de rappel à l'échelle 1 : l'onglet ne saute pas quand les
/// vraies lignes arrivent.
class SqueletteBoite extends StatelessWidget {
  const SqueletteBoite({super.key, this.lignes = 4});

  /// La hauteur d'une carte de liste, mesurée à l'échelle 1 : le carré de 40,
  /// ses deux lignes de texte et les 12 points de marge autour.
  static const double hauteurCarte = 72;

  final int lignes;

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;

    return LoadingSkeleton(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
          // Défilable et **inerte** : rien à lire dessous, mais rien ne
          // déborde non plus sur un petit écran.
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              marge,
              AppSpacing.md,
              marge,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var ligne = 0; ligne < lignes; ligne++) ...<Widget>[
                  const SkeletonBloc(hauteur: hauteurCarte),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
