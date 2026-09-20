import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../auth/data/auth_providers.dart';

/// Le temps de restaurer la session et de lire les appartenances.
///
/// Pas de roue au milieu de l'écran (`DESIGN.md § Don't`) : l'ossature du
/// contenu attendu. Si la lecture échoue — réseau coupé au lancement —, l'écran
/// le dit et propose de réessayer plutôt que d'annoncer à tort « aucune
/// caserne ».
class DemarrageScreen extends ConsumerWidget {
  const DemarrageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appartenances = ref.watch(appartenancesProvider);

    return Scaffold(
      body: SafeArea(
        child: appartenances.hasError
            ? EmptyState.horsLigne(
                onAction: () => ref.invalidate(appartenancesProvider),
              )
            : const _OssatureDemarrage(),
      ),
    );
  }
}

class _OssatureDemarrage extends StatelessWidget {
  const _OssatureDemarrage();

  @override
  Widget build(BuildContext context) {
    return const LoadingSkeleton(
      semanticsLabel: AppStrings.demarrageSemantique,
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SkeletonLigne(largeur: 180, hauteur: AppSpacing.xl),
            SizedBox(height: AppSpacing.xl),
            SkeletonBloc(),
            SizedBox(height: AppSpacing.lg),
            SkeletonBloc(),
          ],
        ),
      ),
    );
  }
}
