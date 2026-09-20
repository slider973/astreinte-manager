import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// L'effectif requis d'un créneau : `−  1  +`.
///
/// **« Ne change que ce créneau » n'est pas décoratif.** C'est la règle du
/// ticket 010 rendue visible : `required_count` est une copie faite à la
/// création du planning, jamais une référence aux réglages de la caserne.
/// Changer l'effectif ici ne change pas la caserne ; changer la caserne ne
/// change pas les plannings déjà créés.
///
/// Écriture optimiste et immédiate : c'est un réglage, pas un formulaire.
class ChampEffectif extends StatelessWidget {
  const ChampEffectif({
    required this.valeur,
    required this.onChanger,
    this.actif = true,
    this.raison,
    super.key,
  });

  /// La borne haute de `station_settings` : ce qu'un réglage de caserne
  /// autorise, un créneau l'autorise aussi, et pas davantage.
  static const int maximum = 50;

  final int valeur;
  final ValueChanged<int> onChanger;

  /// Faux quand la caserne est suspendue, le réseau absent ou le planning
  /// publié. **Un contrôle désactivé porte sa raison** à côté de lui.
  final bool actif;
  final String? raison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peutBaisser = actif && valeur > 0;
    final peutMonter = actif && valeur < maximum;

    return Semantics(
      container: true,
      label: AppStrings.planningEffectifRequis,
      value: '$valeur',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  AppStrings.planningEffectifRequis,
                  style: theme.textTheme.labelMedium,
                ),
              ),
              IconButton(
                onPressed: peutBaisser ? () => onChanger(valeur - 1) : null,
                icon: const Icon(Icons.remove),
                tooltip: peutBaisser
                    ? AppStrings.planningEffectifMoins
                    : AppStrings.planningEffectifMinimum,
              ),
              SizedBox(
                width: AppTouch.cible,
                child: Text(
                  '$valeur',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.nombre.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontFeatures: AppTextStyles.chiffresTabulaires,
                  ),
                ),
              ),
              IconButton(
                onPressed: peutMonter ? () => onChanger(valeur + 1) : null,
                icon: const Icon(Icons.add),
                tooltip: peutMonter
                    ? AppStrings.planningEffectifPlus
                    : AppStrings.planningEffectifMaximum,
              ),
            ],
          ),
          Text(
            raison ?? AppStrings.planningEffectifDetail,
            style: AppTextStyles.mention.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}
