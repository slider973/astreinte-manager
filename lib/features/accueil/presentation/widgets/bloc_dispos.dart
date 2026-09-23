import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../domain/tableau_bord.dart';

/// La section « Disponibilités » de l'accueil.
///
/// Deux formes, et une troisième qui est une absence : l'appel à saisir quand
/// le mois ouvert n'est pas rempli, la ligne de constat quand il l'est, et
/// rien du tout quand aucun mois n'est ouvert — ce que l'écran décide avant
/// d'arriver ici (`AppelDispos`).
class BlocDispos extends StatelessWidget {
  const BlocDispos({required this.appel, required this.onSaisir, super.key});

  final AppelDispos appel;

  /// Ouvre le Calendrier sur le mois concerné.
  final ValueChanged<String> onSaisir;

  @override
  Widget build(BuildContext context) => switch (appel) {
    final SaisieAFaire a => _Appel(appel: a, onSaisir: onSaisir),
    final SaisieFaite f => _Constat(appel: f, onSaisir: onSaisir),
  };
}

/// « Saisir mes disponibilités d'octobre » + « Reste 3 jours ».
///
/// Une carte `primaryContainer` : c'est la seule chose de l'accueil qui
/// demande une action **avec une échéance**, et elle doit se voir avant les
/// cartes grises des jours libres. Le délai est du texte, jamais une couleur
/// qui vire au rouge à J-1 — une date limite de saisie n'est pas une alarme.
class _Appel extends StatelessWidget {
  const _Appel({required this.appel, required this.onSaisir});

  final SaisieAFaire appel;
  final ValueChanged<String> onSaisir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final periode = context.statuts.periode(PeriodeEtat.ouverte);
    final titre = AppStrings.accueilSaisirMois(appel.nomMois);
    final delai = AppStrings.accueilResteJours(appel.joursRestants);

    return Semantics(
      button: true,
      label: '$titre, $delai',
      child: ExcludeSemantics(
        child: Material(
          color: scheme.primaryContainer,
          borderRadius: AppRadius.carteRadius,
          child: InkWell(
            onTap: () => onSaisir(appel.cleMois),
            borderRadius: AppRadius.carteRadius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.cible),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: <Widget>[
                    Icon(
                      periode.icone,
                      size: AppTouch.icone,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            titre,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            delai,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// « Octobre saisi : 12 jours, 4 nuits ».
///
/// Une ligne et non une carte : il n'y a rien à faire. Elle reste malgré tout
/// une porte vers le Calendrier — on relit ce qu'on a donné plus souvent qu'on
/// ne le croit, et le mois est encore ouvert.
class _Constat extends StatelessWidget {
  const _Constat({required this.appel, required this.onSaisir});

  final SaisieFaite appel;
  final ValueChanged<String> onSaisir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final texte = AppStrings.accueilMoisSaisi(
      appel.libelleMois,
      appel.jours,
      appel.nuits,
    );

    return Semantics(
      button: true,
      label: texte,
      child: ExcludeSemantics(
        // Une carte de `surface` sur le papier doux de la page, comme les
        // lignes de proposition : rien à faire ici, mais la ligne appartient
        // au même monde (`design/064 § 2`).
        child: Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.carteRadius,
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: InkWell(
            onTap: () => onSaisir(appel.cleMois),
            borderRadius: AppRadius.carteRadius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.cible),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.task_alt,
                      size: AppTouch.icone,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(texte, style: theme.textTheme.bodyLarge),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
