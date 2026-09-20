import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/taux_saisie.dart';

/// Le taux de saisie d'un mois : **la phrase d'abord, la jauge ensuite**.
///
/// La jauge répète ce que la phrase dit déjà ; elle ne la remplace pas. Une
/// barre seule serait un état porté par une longueur et une couleur, ce que
/// `DESIGN.md § Named Rules` interdit — et un admin qui lit « 7 membres sur
/// 9 » n'a besoin de rien mesurer à l'œil.
///
/// L'encre de la jauge est l'encre du texte, jamais une couleur d'état : un
/// mois à moitié saisi n'est ni une alarme ni une réussite, c'est un fait.
class JaugeSaisie extends StatelessWidget {
  const JaugeSaisie({required this.taux, super.key});

  /// Hauteur du filet plein. Assez pour être vu de loin, trop peu pour
  /// devenir un graphique.
  static const double hauteur = 6;

  final TauxSaisie taux;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statuts = context.statuts;

    final phrase = Text(
      taux.libelle,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    if (!taux.mesurable) {
      return Semantics(label: taux.libelle, excludeSemantics: true, child: phrase);
    }

    return Semantics(
      label: '${taux.libelle}, ${AppStrings.periodeTauxPourcentage(taux.pourcentage)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: phrase),
              const SizedBox(width: AppSpacing.sm),
              Text(
                AppStrings.periodeTauxPourcentage(taux.pourcentage),
                // Chiffres tabulaires : une colonne de pourcentages s'aligne,
                // et le nombre change en place sans faire sauter la ligne.
                style: AppTextStyles.nombrePetit.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: hauteur,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: statuts.filetDecoratif,
                borderRadius: AppRadius.caseRegistreRadius,
              ),
              // `widthFactor` accepte 0 : un mois que personne n'a rempli
              // affiche une jauge vide, pas une barre minimale de politesse.
              child: FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: taux.part,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: AppRadius.caseRegistreRadius,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
