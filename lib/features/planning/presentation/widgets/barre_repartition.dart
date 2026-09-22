import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Une part de la barre de répartition : ce qu'elle vaut, ce qu'elle dit.
@immutable
class PartDuMois {
  const PartDuMois({
    required this.libelle,
    required this.icone,
    required this.couleur,
    required this.valeur,
  });

  final String libelle;
  final IconData icone;

  /// La teinte de remplissage. **Jamais une encre de texte** : c'est ici que
  /// `orange-vif` et `rose-vif` vivent, et nulle part ailleurs.
  final Color couleur;

  final int valeur;
}

/// La barre de répartition du mois, et sa légende.
///
/// **La barre seule ne dit rien** : quatre teintes côte à côte ne sont pas un
/// état lisible en niveaux de gris, et deux d'entre elles — l'orange vif et
/// le rose vif — n'ont pas le droit d'être du texte. La légende est donc
/// obligatoire, icône plus libellé plus nombre, et c'est elle que les
/// lecteurs d'écran lisent ; la barre, elle, est exclue de la sémantique.
///
/// Les parts nulles disparaissent, barre et légende : une part de zéro pixel
/// avec sa ligne de légende serait un mot pour rien.
class BarreRepartition extends StatelessWidget {
  const BarreRepartition({required this.parts, super.key});

  /// Hauteur de la barre, comme celle du suivi (ticket 019).
  static const double hauteur = 8;

  final List<PartDuMois> parts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibles = <PartDuMois>[
      for (final part in parts)
        if (part.valeur > 0) part,
    ];
    final total = visibles.fold<int>(0, (int somme, PartDuMois p) => somme + p.valeur);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: AppRadius.caseRegistreRadius,
            child: SizedBox(
              height: hauteur,
              child: visibles.isEmpty
                  ? ColoredBox(color: theme.colorScheme.surfaceContainerHigh)
                  : Row(
                      // `stretch` et non le centrage par défaut : une part
                      // n'a pas de hauteur à elle, et centrée elle en prend
                      // zéro. La barre serait invisible.
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final part in visibles)
                          Expanded(
                            flex: part.valeur,
                            child: ColoredBox(color: part.couleur),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            for (final part in visibles)
              _LigneLegende(part: part, total: total),
          ],
        ),
      ],
    );
  }
}

class _LigneLegende extends StatelessWidget {
  const _LigneLegende({required this.part, required this.total});

  final PartDuMois part;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: AppStrings.bandeauPartSemantique(part.libelle, part.valeur, total),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // La pastille de teinte est doublée d'une icône : la couleur n'est
          // que le quatrième signal.
          Container(
            width: AppSpacing.md,
            height: AppSpacing.md,
            decoration: BoxDecoration(
              color: part.couleur,
              borderRadius: AppRadius.caseRegistreRadius,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            part.icone,
            size: AppTouch.iconePetite,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            part.libelle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '${part.valeur}',
            style: AppTextStyles.nombrePetit.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
