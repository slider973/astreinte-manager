import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_divider.dart';

/// Un en-tête de section : le titre, son compte, et le filet qui ouvre la
/// liste.
///
/// `DESIGN.md § Espacement` : toujours plus d'espace au-dessus d'un titre
/// qu'en dessous. Le compte est une donnée, pas une décoration — il dit
/// combien de lignes suivent avant qu'on ait fini de défiler.
class EnteteSection extends StatelessWidget {
  const EnteteSection({
    required this.titre,
    super.key,
    this.compte,
    this.premiere = false,
    this.discret = false,
  });

  final String titre;

  /// Phrase déjà composée (« 9 membres actifs »).
  ///
  /// Facultative : une section dont le contenu n'est pas une liste n'a rien à
  /// compter, et une ligne vide sous le titre serait un trou (écran
  /// « Abonnement », ticket 029).
  final String? compte;

  /// La première section d'un écran n'a pas besoin du grand écart du dessus :
  /// le titre de l'écran vient juste de le donner.
  final bool premiere;

  /// **L'en-tête du monde du pompier** (ticket 064c) : le titre descend de
  /// `titleLarge` à `titleMedium`, et le filet s'en va.
  ///
  /// Une liste de cartes n'a pas besoin qu'on lui ouvre une réglure : les
  /// cartes se séparent toutes seules, et un trait de plus au-dessus de la
  /// première serait le registre de l'admin posé sur le papier doux. Le titre,
  /// lui, n'a plus à porter l'écran — le mois n'est qu'un repère entre deux
  /// paquets de dates.
  final bool discret;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(height: premiere ? AppSpacing.lg : AppSpacing.auDessusTitre),
        Semantics(
          header: true,
          child: Text(
            titre,
            style: discret
                ? theme.textTheme.titleMedium
                : theme.textTheme.titleLarge,
          ),
        ),
        if (compte != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            compte!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (!discret) const AppDivider(),
      ],
    );
  }
}
