import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../domain/echanges_providers.dart';
import '../../domain/filtre_echanges.dart';

/// Le bloc « N échanges à valider » en tête du Suivi (`design/073 § 8.1`) :
/// un **fait qui décrit le contenu**, de la famille d'attente, pas une
/// bannière (`DESIGN.md § Écarts 023`). Absent quand la file est vide.
class BlocEchangesSuivi extends ConsumerWidget {
  const BlocEchangesSuivi({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(echangesAValiderProvider);
    if (n == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final attente = context.statuts.attribution(AttributionEtat.propose);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: attente.fond,
          borderRadius: AppRadius.controleRadius,
          border: Border.all(color: attente.filet ?? attente.encre),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            children: <Widget>[
              Icon(Icons.how_to_reg, size: AppTouch.icone, color: attente.encre),
              Text(
                AppStrings.echangesBlocSuivi(n),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: attente.encre,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(AppTouch.cible, AppTouch.cible),
                ),
                onPressed: () => context.go(
                  AppRoutes.echangesAdminFiltre(FiltreEchanges.aValider),
                ),
                child: const Text(AppStrings.echangesBlocSuiviAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
