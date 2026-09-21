import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';

/// **Pourquoi la vue est partielle.**
///
/// `assignments_select_station_validated` n'ouvre les attributions des autres
/// que sur un planning `validated` (`docs/SCHEMA.md § 4`). La règle est dans la
/// base ; ce bloc ne la double pas, il l'explique. Sans lui, une liste courte
/// se lirait « le planning est presque vide », ce qui est faux.
///
/// **Ce n'est pas une `AppBanner`**, pour deux raisons (`design/023 § 4`) :
/// la bannière transverse ne porte qu'un fait à la fois, et un pompier hors
/// ligne perdrait exactement l'explication dont il a besoin ; et ce fait n'est
/// pas transverse — il décrit **le mois affiché**, donc il se déplace avec lui.
///
/// L'ocre d'attente est celui de l'état **proposé** (`DESIGN.md § Attribution`),
/// avec `Icons.hourglass_top` : même grammaire que « En attente de ta réponse »,
/// pour la même raison — quelque chose est en cours et ne dépend pas de toi.
/// Pas de filet coloré à gauche (`DESIGN.md § Écarts, ticket 020`).
class BlocAttenteValidation extends StatelessWidget {
  const BlocAttenteValidation({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attente = context.statuts.attribution(AttributionEtat.propose);

    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: attente.fond,
          borderRadius: AppRadius.controleRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.hourglass_top,
                size: AppTouch.icone,
                color: attente.encre,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      AppStrings.planningCaserneAttenteTitre,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: attente.encre,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      AppStrings.planningCaserneAttenteTexte,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: attente.encre,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
