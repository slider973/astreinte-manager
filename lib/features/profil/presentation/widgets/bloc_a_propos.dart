import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/version/version_app.dart';
import 'bloc_regle.dart';

/// **« À propos »** — ce qui identifie la construction qui tourne.
///
/// Ticket 080, demandé par le propriétaire : « rajouter un numéro de version
/// quelque part que je puisse identifier les différentes versions ». Il teste la
/// PWA après chaque correctif et ne pouvait pas savoir ce qu'il avait sous les
/// yeux — un service worker sert parfois l'ancienne version depuis le cache.
///
/// **Sélectionnable**, parce que son usage réel est d'être recopiée dans un
/// message pour dire « j'ai celle-ci ». Un texte qu'on ne peut pas copier
/// obligerait à le retranscrire à la main.
///
/// Le dernier bloc de l'écran, après le compte : on ne vient jamais pour ça,
/// mais on doit pouvoir le trouver sans chercher.
class BlocAPropos extends StatelessWidget {
  const BlocAPropos({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final date = dateConstruction;

    return BlocRegle(
      titre: AppStrings.aProposTitre,
      enfants: <Widget>[
        // Une seule zone sélectionnable pour les deux lignes : on copie « la
        // version », pas un champ à la fois.
        SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                constructionLocale
                    ? AppStrings.aProposVersionLocale
                    : AppStrings.aProposVersion(appCommit),
                style: style,
              ),
              if (date != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppStrings.aProposConstruiteLe(
                    formaterDateLongue(date),
                    formaterHeureDuJour(date),
                  ),
                  style: style,
                ),
              ],
              // L'environnement n'apparaît **que hors production** : dire
              // « production » à un pompier qui ouvre son profil n'apprend rien
              // à personne, alors que voir « dev » explique pourquoi ses
              // données ne sont pas celles qu'il attendait.
              if (!enProduction) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppStrings.aProposEnvironnement(appEnv),
                  style: style?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
