import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/periode_saisie.dart';

/// Le sélecteur de mois — et **le titre de l'écran**.
///
/// Le bouton sélectionné porte le nom du mois : il n'y a pas de second titre
/// qui le répéterait. C'est aussi là que vit la date limite, plutôt que dans
/// une bannière `information` permanente qui coûterait 48 dp de grille sur
/// tous les mois ouverts pour redire ce que le sélecteur dit déjà.
class SelecteurMois extends StatelessWidget {
  const SelecteurMois({
    required this.periodes,
    required this.selectionnee,
    required this.onChoisir,
    super.key,
  });

  /// Hauteur du bouton : le nom du mois, puis sa ligne d'état.
  static const double hauteurBouton = 64;

  final List<PeriodeSaisie> periodes;
  final PeriodeSaisie? selectionnee;
  final ValueChanged<PeriodeSaisie> onChoisir;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: AppStrings.moisSelecteurLabel,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: <Widget>[
            for (final periode in periodes) ...<Widget>[
              _Bouton(
                periode: periode,
                choisi: periode.cle == selectionnee?.cle,
                onChoisir: () => onChoisir(periode),
              ),
              if (periode != periodes.last)
                const SizedBox(width: AppSpacing.entreCibles),
            ],
          ],
        ),
      ),
    );
  }
}

class _Bouton extends StatelessWidget {
  const _Bouton({
    required this.periode,
    required this.choisi,
    required this.onChoisir,
  });

  final PeriodeSaisie periode;
  final bool choisi;
  final VoidCallback onChoisir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statuts = context.statuts;
    final descripteur = statuts.periode(periode.statut);

    final encre = choisi
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      selected: choisi,
      label: choisi
          ? AppStrings.moisSelectionSemantique(periode.libelle)
          : periode.libelle,
      value: periode.ligneEtat,
      excludeSemantics: true,
      child: InkWell(
        onTap: choisi ? null : onChoisir,
        borderRadius: AppRadius.controleRadius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: SelecteurMois.hauteurBouton,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: choisi
                  ? theme.colorScheme.secondaryContainer
                  : theme.colorScheme.surface,
              borderRadius: AppRadius.controleRadius,
              border: Border.all(
                color: choisi
                    ? theme.colorScheme.secondary
                    : statuts.filetDecoratif,
                width: choisi ? AppStroke.etat : AppStroke.filet,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    periode.libelle,
                    style: AppTextStyles.titreBloc.copyWith(color: encre),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        descripteur.icone,
                        size: AppTouch.iconePetite,
                        color: encre,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        periode.ligneEtat,
                        style: AppTextStyles.mention.copyWith(color: encre),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
