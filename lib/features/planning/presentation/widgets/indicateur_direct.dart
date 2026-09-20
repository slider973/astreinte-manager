import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';

/// L'état du canal temps réel, **affiché**, jamais supposé.
///
/// Un écran collaboratif qui perd son abonnement en silence est un écran qui
/// ment : le chef croirait voir l'état réel du mois. L'icône et le libellé vont
/// ensemble, et l'infobulle dit la conséquence.
///
/// Partagé par la construction du planning (ticket 017) et par le suivi
/// (ticket 019) : deux écrans, un seul objet, aucune chance qu'ils divergent.
class IndicateurDirect extends StatelessWidget {
  const IndicateurDirect({required this.branche, super.key});

  final bool branche;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encre = branche
        ? theme.colorScheme.onSurfaceVariant
        : context.statuts.attribution(AttributionEtat.propose).encre;

    return Tooltip(
      message: branche
          ? AppStrings.planningDirectDetail
          : AppStrings.planningDirectInterrompuDetail,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            branche ? Icons.sync : Icons.cloud_off,
            size: AppTouch.iconePetite,
            color: encre,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            branche
                ? AppStrings.planningDirect
                : AppStrings.planningDirectInterrompu,
            style: AppTextStyles.mention.copyWith(color: encre),
          ),
        ],
      ),
    );
  }
}
