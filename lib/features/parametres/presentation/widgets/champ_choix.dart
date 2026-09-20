import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Un choix dans une liste fermée, avec son libellé au-dessus.
///
/// Même grammaire que `ChampTexte` (`DESIGN.md § Inputs / Fields`) : libellé
/// toujours visible, hauteur 56 dp, erreur sous le champ. La liste est fermée
/// parce que la valeur voyage jusqu'à la base : un fuseau inventé y serait
/// refusé, autant ne pas le proposer.
class ChampChoix extends StatelessWidget {
  const ChampChoix({
    required this.libelle,
    required this.valeur,
    required this.options,
    required this.onChange,
    super.key,
    this.erreur,
    this.actif = true,
  });

  final String libelle;

  /// La valeur courante. Absente de [options], elle est tout de même
  /// proposée : on n'efface pas en silence un réglage qu'on ne comprend pas.
  final String valeur;

  /// Valeur technique vers libellé français.
  final Map<String, String> options;

  final ValueChanged<String> onChange;
  final String? erreur;
  final bool actif;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valeurs = <String>[
      ...options.keys,
      if (!options.containsKey(valeur)) valeur,
    ];

    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(libelle, style: theme.textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<String>(
            initialValue: valeur,
            isExpanded: true,
            decoration: InputDecoration(errorText: erreur),
            items: <DropdownMenuItem<String>>[
              for (final String option in valeurs)
                DropdownMenuItem<String>(
                  value: option,
                  child: Text(
                    options[option] ?? option,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
            ],
            onChanged: actif
                ? (String? choix) {
                    if (choix != null) onChange(choix);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
