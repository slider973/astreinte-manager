import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_divider.dart';

/// Une section du catalogue : un titre, une note, et les spécimens.
///
/// Le catalogue applique à lui-même les règles du système : plus d'espace
/// au-dessus d'un titre qu'en dessous (24 / 8), séparation par un filet, zéro
/// ombre.
class DevSection extends StatelessWidget {
  const DevSection({
    required this.titre,
    required this.children,
    super.key,
    this.note,
  });

  final String titre;

  /// Ce que la section prouve, en une phrase.
  final String? note;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: AppSpacing.auDessusTitre),
        const AppDivider(),
        const SizedBox(height: AppSpacing.lg),
        Text(titre, style: theme.textTheme.titleLarge),
        if (note != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            note!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sousTitre),
        ...children,
      ],
    );
  }
}

/// Un spécimen : son état nommé au-dessus, le composant en dessous.
///
/// Le nom de l'état est affiché pour que la capture en niveaux de gris de
/// `/dev/components` reste vérifiable état par état.
class DevSpecimen extends StatelessWidget {
  const DevSpecimen({required this.nom, required this.child, super.key});

  final String nom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            nom,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// Une rangée de spécimens qui se replie quand la fenêtre rétrécit ou quand
/// l'échelle de texte grandit.
class DevRangee extends StatelessWidget {
  const DevRangee({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.lg,
      children: children,
    );
  }
}
