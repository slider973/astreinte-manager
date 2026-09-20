import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/loading_skeleton.dart';

/// Un paragraphe de contexte : la caserne, la personne qui invite, l'adresse
/// connectée. Toujours sous le titre, jamais à la place.
class TexteInvitation extends StatelessWidget {
  const TexteInvitation(this.texte, {super.key, this.principal = false});

  final String texte;

  /// Vrai pour la phrase qui porte le sens de l'écran.
  final bool principal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      texte,
      style: principal
          ? theme.textTheme.bodyLarge
          : theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
    );
  }
}

/// L'attente pendant que le lien est vérifié.
///
/// Pas de roue au milieu de l'écran (`DESIGN.md § Don't`) : l'ossature du
/// texte attendu, et une phrase qui dit ce qui se passe.
class AttenteInvitation extends StatelessWidget {
  const AttenteInvitation({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TexteInvitation(AppStrings.invitationVerification, principal: true),
          SizedBox(height: AppSpacing.xl),
          LoadingSkeleton(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SkeletonLigne(),
                SizedBox(height: AppSpacing.sm),
                SkeletonLigne(largeur: 220),
                SizedBox(height: AppSpacing.xl),
                SkeletonBloc(hauteur: AppTouch.bouton),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
