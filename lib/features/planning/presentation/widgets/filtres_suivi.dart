import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/suivi_planning.dart';

/// Les cinq puces de filtre de la liste des créneaux.
///
/// **Des puces, pas des onglets**, et la raison est concrète : le chef veut
/// souvent voir « en attente » **et** « non pourvus » ensemble — c'est-à-dire
/// ce qui lui reste à traiter. Des onglets forceraient un choix exclusif.
///
/// Une puce à zéro **reste visible et désactivée avec sa raison** : la faire
/// disparaître ferait sauter les autres sous le doigt.
class FiltresSuiviBarre extends StatelessWidget {
  const FiltresSuiviBarre({
    required this.selection,
    required this.comptes,
    required this.onBasculer,
    super.key,
  });

  final Set<FiltreSuivi> selection;
  final Map<FiltreSuivi, int> comptes;
  final ValueChanged<FiltreSuivi> onBasculer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          for (final filtre in FiltreSuivi.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.entreCibles),
              child: _Puce(
                filtre: filtre,
                compte: comptes[filtre] ?? 0,
                choisie: filtre == FiltreSuivi.tous
                    ? selection.isEmpty
                    : selection.contains(filtre),
                // « Tous » est toujours actionnable : c'est la sortie.
                inerte:
                    filtre != FiltreSuivi.tous && (comptes[filtre] ?? 0) == 0,
                onBasculer: onBasculer,
                style: theme.textTheme.labelMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class _Puce extends StatelessWidget {
  const _Puce({
    required this.filtre,
    required this.compte,
    required this.choisie,
    required this.inerte,
    required this.onBasculer,
    required this.style,
  });

  final FiltreSuivi filtre;
  final int compte;
  final bool choisie;
  final bool inerte;
  final ValueChanged<FiltreSuivi> onBasculer;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final puce = FilterChip(
      selected: choisie,
      onSelected: inerte ? null : (bool _) => onBasculer(filtre),
      showCheckmark: false,
      labelStyle: style,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(filtre.libelle),
          const SizedBox(width: AppSpacing.sm),
          // Le compte est une donnée, pas une décoration : chiffres tabulaires
          // pour qu'il change en place sans déplacer la puce suivante.
          Text('$compte', style: AppTextStyles.nombrePetit.copyWith(
            color: style?.color,
          )),
        ],
      ),
    );

    if (!inerte) return puce;
    return Tooltip(
      message: AppStrings.suiviFiltreDesactive(filtre.libelle),
      child: puce,
    );
  }
}
