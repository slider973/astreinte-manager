import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Ce que le fichier doit contenir, écrit noir sur blanc.
///
/// **Un bloc réglé et non un paragraphe** (`DESIGN.md § Cards / Containers`) :
/// la ligne d'en-têtes est la seule chose que la personne va recopier dans son
/// tableur, et elle doit se distinguer du texte qui l'entoure au premier coup
/// d'œil.
///
/// La ligne d'en-têtes est en police à chasse fixe parce que c'est **du
/// contenu de fichier**, pas un costume de technicité : les points-virgules
/// s'y comptent, et c'est exactement le cas où le mono sert à quelque chose.
class BlocFormatFichier extends StatelessWidget {
  const BlocFormatFichier({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.controle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(
                AppStrings.importFormatTitre,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                AppStrings.importFormatEntetes,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: AppFonts.nombre,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppStrings.importFormatExplication,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppStrings.importFormatVariantes,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppStrings.importFormatLimites,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
