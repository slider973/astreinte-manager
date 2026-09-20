import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_divider.dart';

/// Un en-tête de section : le titre, son compte, et le filet qui ouvre la
/// liste.
///
/// `DESIGN.md § Espacement` : toujours plus d'espace au-dessus d'un titre
/// qu'en dessous. Le compte est une donnée, pas une décoration — il dit
/// combien de lignes suivent avant qu'on ait fini de défiler.
class EnteteSection extends StatelessWidget {
  const EnteteSection({
    required this.titre,
    required this.compte,
    super.key,
    this.premiere = false,
  });

  final String titre;

  /// Phrase déjà composée (« 9 membres actifs »).
  final String compte;

  /// La première section d'un écran n'a pas besoin du grand écart du dessus :
  /// le titre de l'écran vient juste de le donner.
  final bool premiere;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(height: premiere ? AppSpacing.lg : AppSpacing.auDessusTitre),
        Semantics(
          header: true,
          child: Text(titre, style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          compte,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const AppDivider(),
      ],
    );
  }
}
