import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Une rangée de **choix exclusif** (ticket 073, `design/073 § 12`).
///
/// Un grand bouton de liste qui se coche : icône à gauche, titre, ligne
/// d'aide, et la coche `check_circle` sur fond `primary-container` quand il
/// est choisi. **Jamais la couleur seule** : la coche, le filet de 2 dp et
/// l'état `selected` annoncé disent la même chose.
///
/// Inerte, la rangée écrit sa raison dessous : un choix grisé sans raison est
/// un défaut (`DESIGN.md § Buttons`).
///
/// 56 dp au moins, 64 avec une ligne d'aide : la cible se touche avec un gant.
class ChoixExclusif extends StatelessWidget {
  const ChoixExclusif({
    required this.titre,
    required this.choisi,
    required this.onChoisir,
    super.key,
    this.icone,
    this.avantTitre,
    this.aide,
    this.raisonInerte,
    this.libelleAnnonce,
  });

  final String titre;
  final bool choisi;

  /// `null` rend la rangée inerte ; [raisonInerte] dit alors pourquoi.
  final VoidCallback? onChoisir;

  final IconData? icone;

  /// Un visuel à la place de l'icône (avatar, carré de créneau). Décoratif :
  /// il est exclu de la sémantique.
  final Widget? avantTitre;

  final String? aide;
  final String? raisonInerte;

  /// La phrase annoncée, quand le titre seul ne suffit pas.
  final String? libelleAnnonce;

  static const double hauteurMin = 56;
  static const double hauteurAvecAide = 64;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final actif = onChoisir != null;
    final raison = actif ? null : raisonInerte;
    final encre = actif ? scheme.onSurface : scheme.onSurfaceVariant;

    final visuel =
        avantTitre ??
        (icone == null
            ? null
            : Icon(icone, size: AppTouch.glypheConfortable, color: encre));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          button: true,
          selected: choisi,
          inMutuallyExclusiveGroup: true,
          enabled: actif,
          label: <String>[
            libelleAnnonce ?? titre,
            ?aide,
            ?raison,
          ].join('. '),
          excludeSemantics: true,
          child: Material(
            color: choisi ? scheme.primaryContainer : scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.controleRadius,
              side: BorderSide(
                color: choisi ? scheme.primary : scheme.outlineVariant,
                width: choisi ? AppStroke.etat : AppStroke.filet,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onChoisir,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: aide == null ? hauteurMin : hauteurAvecAide,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: <Widget>[
                      if (visuel != null) ...<Widget>[
                        visuel,
                        const SizedBox(width: AppSpacing.md),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              titre,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: choisi ? scheme.onPrimaryContainer : encre,
                              ),
                            ),
                            if (aide != null) ...<Widget>[
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                aide!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: choisi
                                      ? scheme.onPrimaryContainer
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        choisi
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: AppTouch.glypheConfortable,
                        color: choisi ? scheme.primary : scheme.outline,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (raison != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: ExcludeSemantics(
              child: Text(
                raison,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
