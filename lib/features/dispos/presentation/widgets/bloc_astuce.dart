import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/carte_douce.dart';

/// Le bloc qui apprend le geste, puis disparaît **tout seul**.
///
/// Jamais fermable à la main : il n'y a rien à fermer, il s'efface quand il
/// n'a plus rien à dire. La première ligne part à la première saisie du mois,
/// la seconde à la première peinture réussie sur cet appareil. Sur un mois
/// verrouillé, il ne s'affiche jamais.
class BlocAstuce extends StatelessWidget {
  const BlocAstuce({
    required this.montrerTouche,
    required this.montrerGlissement,
    super.key,
  });

  final bool montrerTouche;
  final bool montrerGlissement;

  bool get _vide => !montrerTouche && !montrerGlissement;

  @override
  Widget build(BuildContext context) {
    if (_vide) return const SizedBox.shrink();

    final marge = AppWindowClass.of(context).margePage;

    return Padding(
      padding: EdgeInsets.fromLTRB(marge, AppSpacing.md, marge, 0),
      // La carte du monde du pompier (ticket 064c) : le bloc d'aide était déjà
      // `surface` sur filet, il ne change que de rayon.
      child: CarteDouce(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (montrerTouche)
              const _Ligne(
                icone: Icons.touch_app,
                texte: AppStrings.astuceSaisieTouche,
              ),
            if (montrerTouche && montrerGlissement)
              const SizedBox(height: AppSpacing.sm),
            if (montrerGlissement)
              const _Ligne(
                icone: Icons.swipe_vertical,
                texte: AppStrings.astuceSaisieGlissement,
              ),
          ],
        ),
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.icone, required this.texte});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          icone,
          size: AppTouch.icone,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.md),
        // La prose reste bornée : une aide pleine largeur sur une tablette se
        // lit moins bien qu'une aide de soixante-cinq caractères.
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              texte,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
