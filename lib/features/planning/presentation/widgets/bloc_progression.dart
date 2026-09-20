import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/count_stat.dart';
import '../../domain/suivi_planning.dart';

/// Le bloc de progression : une barre, une phrase, quatre compteurs.
///
/// **La barre ne porte aucune information que la phrase ne porte pas déjà.**
/// C'est la règle « jamais la couleur seule » appliquée à une forme : jamais la
/// longueur seule. Et son remplissage est `primary` — l'encre —, pas une
/// couleur d'état : une barre qui verdirait à 100 % ajouterait une quatrième
/// sémantique de vert à un système qui en a déjà deux.
class BlocProgression extends StatelessWidget {
  const BlocProgression({required this.progression, super.key});

  /// Hauteur de la barre. Rayon `case`, comme tout ce qui est un bloc du
  /// registre.
  static const double hauteurBarre = 8;

  final ProgressionPlanning progression;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phrase = progression.attendues == 0
        ? AppStrings.suiviAucuneAttribution
        : AppStrings.suiviReponses(
            progression.reponses,
            progression.attendues,
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: AppRadius.controleRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: AppRadius.caseRegistreRadius,
              child: LinearProgressIndicator(
                value: progression.fraction,
                minHeight: hauteurBarre,
                backgroundColor: theme.colorScheme.surfaceContainerHigh,
                color: theme.colorScheme.primary,
                // La barre est décorative : la phrase juste en dessous porte
                // l'information, et elle est annoncée, elle.
                semanticsLabel: '',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // **Le seul `liveRegion` de l'écran.** Quatre compteurs qui
            // s'annonceraient à chaque réponse seraient inécoutables.
            Semantics(
              liveRegion: true,
              child: Text(phrase, style: theme.textTheme.bodyLarge),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: CountStat(
                    libelle: AppStrings.suiviEnAttente,
                    valeur: progression.enAttente,
                    plafondAttendu: false,
                  ),
                ),
                Expanded(
                  child: CountStat(
                    libelle: AppStrings.suiviAcceptees,
                    valeur: progression.acceptees,
                    plafondAttendu: false,
                  ),
                ),
                Expanded(
                  child: CountStat(
                    libelle: AppStrings.suiviRefusees,
                    valeur: progression.refusees,
                    plafondAttendu: false,
                  ),
                ),
                Expanded(
                  // La seule fraction du bloc : `shifts_filled` sur
                  // `shifts_total`, tels que `v_schedule_progress` les rend.
                  child: CountStat(
                    libelle: AppStrings.suiviCreneauxPourvus,
                    valeur: progression.creneauxPourvus,
                    plafond: progression.creneauxTotal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
