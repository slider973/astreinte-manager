import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';

/// Les deux vues de l'écran.
enum VueAstreintes { liste, calendrier }

/// La bascule « Liste » / « Calendrier ».
///
/// **Pas un `SegmentedButton`** : le segmenté Material est en gélule
/// (`StadiumBorder`) et `DESIGN.md § Shapes` proscrit la pastille sur un
/// contrôle. La composition est celle du sélecteur de mois du ticket 011 :
/// deux blocs à rayon `controle`, le sélectionné en `secondary-container`.
///
/// Trois signaux pour l'état choisi — la coche, le fond, `Semantics(selected:)`
/// — jamais la couleur seule.
class BasculeVue extends StatelessWidget {
  const BasculeVue({
    required this.vue,
    required this.onChoisir,
    super.key,
    this.calendrierIndisponible,
  });

  final VueAstreintes vue;
  final ValueChanged<VueAstreintes> onChoisir;

  /// Pourquoi « Calendrier » est inerte, ou `null` quand il ne l'est pas. Un
  /// contrôle désactivé sans raison est un défaut (`DESIGN.md § Buttons`).
  final String? calendrierIndisponible;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: AppStrings.astreintesVueLabel,
      // Bornée comme la liste qu'elle commande : sur un portable, deux boutons
      // de 580 dp pour deux mots sont un défaut, pas une aération.
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
          child: Padding(
            // La **même** marge de page que la liste qu'elle commande : à 16
            // sur un portable où la liste en prend 32, les deux boîtes de
            // 720 dp ne s'alignent pas et le décalage se voit.
            padding: EdgeInsets.symmetric(
              horizontal: AppWindowClass.of(context).margePage,
              vertical: AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _Bouton(
                        libelle: AppStrings.astreintesVueListe,
                        icone: Icons.view_list_outlined,
                        choisi: vue == VueAstreintes.liste,
                        onChoisir: () => onChoisir(VueAstreintes.liste),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.entreCibles),
                    Expanded(
                      child: _Bouton(
                        libelle: AppStrings.astreintesVueCalendrier,
                        icone: Icons.calendar_month_outlined,
                        choisi: vue == VueAstreintes.calendrier,
                        onChoisir: calendrierIndisponible != null
                            ? null
                            : () => onChoisir(VueAstreintes.calendrier),
                        raison: calendrierIndisponible,
                      ),
                    ),
                  ],
                ),
                if (calendrierIndisponible
                    case final String raison) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    raison,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bouton extends StatelessWidget {
  const _Bouton({
    required this.libelle,
    required this.icone,
    required this.choisi,
    required this.onChoisir,
    this.raison,
  });

  final String libelle;
  final IconData icone;
  final bool choisi;
  final VoidCallback? onChoisir;
  final String? raison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inerte = onChoisir == null;

    final encre = inerte
        ? theme.colorScheme.outline
        : choisi
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      selected: choisi,
      enabled: !inerte,
      hint: raison,
      child: Material(
        color: inerte
            ? theme.colorScheme.surfaceContainerHighest
            : choisi
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surface,
        borderRadius: AppRadius.controleRadius,
        child: InkWell(
          onTap: onChoisir,
          borderRadius: AppRadius.controleRadius,
          child: Container(
            height: AppTouch.cible,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: AppRadius.controleRadius,
              border: Border.all(
                color: choisi && !inerte
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.outline,
                width: choisi && !inerte ? AppStroke.etat : AppStroke.filet,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // La coche est le signal robuste : elle survit à une capture
                // en niveaux de gris, le fond non.
                Icon(
                  choisi ? Icons.check : icone,
                  size: AppTouch.icone,
                  color: encre,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    libelle,
                    style: theme.textTheme.labelLarge?.copyWith(color: encre),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
