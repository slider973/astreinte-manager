import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/parametres_caserne.dart';

/// Une ligne de registre : ce que la surcharge désigne, ce qu'elle vaut, et de
/// quoi la changer.
///
/// L'état est écrit en toutes lettres (« Par défaut », « 2 en journée · 3 la
/// nuit ») : rien n'est porté par une couleur, et la ligne reste lisible
/// photocopiée.
class LigneSurcharge extends StatelessWidget {
  const LigneSurcharge({
    required this.libelle,
    required this.surcharge,
    required this.onModifier,
    super.key,
    this.onRetirer,
  });

  /// Ce que la ligne désigne : « Samedi », « 31/12/2026 ».
  final String libelle;

  /// `null` : aucune surcharge, la ligne suit l'effectif par défaut.
  final SurchargeEffectif? surcharge;

  final VoidCallback onModifier;

  /// Présent pour les dates seulement : un jour de semaine ne se retire pas de
  /// la semaine, il revient au défaut.
  final VoidCallback? onRetirer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valeur =
        surcharge?.valeurLibelle ?? AppStrings.parametresSurchargeAucune;
    final pose = surcharge != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              label: '$libelle, $valeur',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(libelle, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    valeur,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: pose
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onRetirer != null)
            IconButton(
              onPressed: onRetirer,
              icon: const Icon(Icons.delete_outline),
              tooltip: AppStrings.parametresSurchargeRetirer(libelle),
            ),
          IconButton(
            onPressed: onModifier,
            icon: Icon(pose ? Icons.edit : Icons.add),
            tooltip: AppStrings.parametresSurchargeModifier(libelle),
          ),
        ],
      ),
    );
  }
}
