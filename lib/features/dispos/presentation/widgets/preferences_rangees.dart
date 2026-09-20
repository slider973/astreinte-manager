import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../domain/preferences_mois.dart';

/// Une rangée de plafond : **les deux nombres qui font la leçon**.
///
/// À droite, ce qui est voulu, en chasse fixe tabulaire — ou « autant que
/// nécessaire » en toutes lettres, jamais un `∞`. En dessous, ce qui est
/// coché. C'est le rapport, à l'endroit exact où on le règle.
///
/// Sur un mois verrouillé, la rangée perd son chevron et son focus mais
/// **garde ses nombres** : l'information reste, seule l'interaction disparaît.
class RangeePlafond extends StatelessWidget {
  const RangeePlafond({
    required this.libelle,
    required this.valeur,
    required this.detail,
    required this.actionnable,
    required this.onOuvrir,
    super.key,
  });

  final String libelle;

  /// `null` : autant que nécessaire.
  final int? valeur;

  /// « 33 cochées ce mois ».
  final String detail;

  final bool actionnable;
  final VoidCallback onOuvrir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final limite = valeur;

    final contenu = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(libelle, style: theme.textTheme.labelMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  detail,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: limite == null
                ? Text(
                    AppStrings.preferencesSansLimite,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Text(
                    '$limite',
                    textAlign: TextAlign.end,
                    style: AppTextStyles.nombre.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
          ),
          if (actionnable) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right,
              size: AppTouch.icone,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    final rangee = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.champ),
      child: contenu,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const AppDivider(),
        Semantics(
          button: actionnable,
          enabled: actionnable,
          label: limite == null
              ? '$libelle, ${AppStrings.preferencesSansLimite}'
              : '$libelle, au maximum $limite',
          hint: detail,
          excludeSemantics: true,
          child: actionnable
              ? InkWell(onTap: onOuvrir, child: rangee)
              : rangee,
        ),
      ],
    );
  }
}

/// Une mention d'une ligne : une icône de 20 dp et une phrase.
/// Sert à la reprise du mois précédent et à la raison d'un contrôle inerte.
class LigneMention extends StatelessWidget {
  const LigneMention({required this.icone, required this.texte, super.key});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          icone,
          size: AppTouch.icone,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              texte,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Le commentaire d'un mois verrouillé : les mots du membre, **en entier**.
/// Il a le droit de les relire, et rien n'est vide et muet.
class CommentaireLecture extends StatelessWidget {
  const CommentaireLecture({
    required this.texte,
    required this.valeurs,
    super.key,
  });

  final String texte;
  final PreferencesMois valeurs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (texte.isEmpty && valeurs.sansAucuneLimite) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          0,
        ),
        child: Text(
          AppStrings.preferencesAucuneVerrouille,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (texte.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const AppDivider(),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                AppStrings.preferencesCommentaireRangee,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(texte, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}
