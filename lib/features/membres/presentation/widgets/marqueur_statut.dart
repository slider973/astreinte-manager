import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';

/// Le marqueur « Désactivé » d'une ligne de membre.
///
/// Un fait gris, pas une alarme (`DESIGN.md § Do` : « Traiter "verrouillé",
/// "suspendu", "annulé" comme des faits gris »). Trois signaux redondants — un
/// filet, une icône, un libellé — et la couleur en quatrième : photocopié en
/// noir et blanc, il se lit encore.
///
/// Ce n'est pas un [StatusBadge] : celui-là ne rend que les états énumérés du
/// thème (disponibilité, créneau, attribution, planning, période, synchro), et
/// le statut d'une appartenance n'en fait pas partie. Un état de plus dans
/// `AppStatusColors` pour une seule ligne de liste coûterait plus cher qu'il
/// ne rapporte.
class MarqueurDesactive extends StatelessWidget {
  const MarqueurDesactive({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        borderRadius: AppRadius.caseRegistreRadius,
        border: Border.all(color: theme.colorScheme.outline),
        color: theme.colorScheme.surfaceDim,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.block,
            size: AppTouch.iconePetite,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            AppStrings.membreStatutDesactive,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
