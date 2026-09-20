import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/membre_caserne.dart';

/// Une ligne de la liste des membres : le nom, puis l'adresse et le rôle.
///
/// Ce n'est pas un bloc réglé et encore moins une carte : une liste de blocs
/// identiques « icône + titre + texte » est interdite comme structure de page
/// (`DESIGN.md § Cards / Containers`). Les lignes sont séparées par le filet.
class LigneMembre extends StatelessWidget {
  const LigneMembre({required this.membre, super.key});

  final MembreCaserne membre;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaire = <String>[
      membre.email,
      if (membre.estAdmin) membre.role.libelle,
    ].join(' · ');

    return Semantics(
      label: membre.libelle,
      value: secondaire,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.cible),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(membre.libelle, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      secondaire,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (membre.estAdmin) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.admin_panel_settings_outlined,
                  size: AppTouch.icone,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
