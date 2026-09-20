import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Un compteur : une valeur, éventuellement un plafond.
///
/// Employé pour les quotas du membre (« 2 sur 3 astreintes ») et pour les
/// totaux de la matrice admin. Le nombre est en **chasse fixe avec chiffres
/// tabulaires** : il change en place sans faire sauter la mise en page, et une
/// colonne de compteurs s'aligne au pixel (`DESIGN.md § Typography`).
///
/// Ce n'est pas une « métrique héroïque » : le libellé est au moins aussi
/// lisible que le nombre, et le compteur ne vit jamais seul sur une page.
class CountStat extends StatelessWidget {
  const CountStat({
    required this.libelle,
    required this.valeur,
    super.key,
    this.plafond,
    this.grand = false,
  });

  /// « Jours », « Nuits », « Weekends ».
  final String libelle;

  final int valeur;

  /// `null` signifie **illimité**, et c'est écrit en toutes lettres : un
  /// symbole `∞` seul n'est pas lisible pour tout le monde.
  final int? plafond;

  /// Compteur du mois, gros total : `display-nombre` au lieu de `nombre`.
  final bool grand;

  /// Vrai si le quota est atteint ou dépassé.
  bool get atteint => plafond != null && valeur >= plafond!;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final limite = plafond;

    final styleValeur =
        (grand ? AppTextStyles.displayNombre : AppTextStyles.nombre).copyWith(
          color: theme.colorScheme.onSurface,
        );
    final stylePlafond = AppTextStyles.nombre.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Semantics(
      container: true,
      label: libelle,
      value: limite == null
          ? AppStrings.compteurSansPlafond(valeur)
          : AppStrings.compteurSurPlafond(valeur, limite),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            libelle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          // À très grande échelle de texte, un gros total peut dépasser la
          // colonne. On le réduit jusqu'à la largeur disponible plutôt que de
          // le tronquer : un compteur à moitié lu est pire qu'un compteur un
          // peu plus petit. Le libellé, lui, garde sa taille.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('$valeur', style: styleValeur),
                if (limite != null) ...<Widget>[
                  Text(' / ', style: stylePlafond),
                  Text('$limite', style: stylePlafond),
                ] else ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    AppStrings.compteurIllimite,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
