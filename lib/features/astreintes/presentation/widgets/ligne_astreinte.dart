import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/l10n/jours_feries.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/astreinte.dart';

/// Une astreinte acceptée, et rien d'autre.
///
/// **Ce n'est pas une carte** (`DESIGN.md § Cards / Containers`) : une marge de
/// registre, un corps, un filet de réglure qui la sépare de la suivante.
/// Aucune ombre, aucun fond, aucun rayon.
///
/// La ligne entière est actionnable — différence assumée avec la ligne de
/// proposition du ticket 021, qui est inerte parce qu'elle porte deux boutons
/// irréversibles. Ici l'ouverture ne commet rien, et se tromper coûte un geste
/// retour (`design/027 § 7.3`).
class LigneDAstreinte extends StatelessWidget {
  const LigneDAstreinte({
    required this.astreinte,
    required this.heures,
    required this.onOuvrir,
    super.key,
    this.passee = false,
  });

  /// Largeur de la marge du registre. **La même qu'au ticket 011 et qu'au
  /// 021** : trois écrans, une seule marge, aucune variante à maintenir.
  static const double largeurMarge = 48;

  final Astreinte astreinte;
  final HeuresAffichage heures;
  final VoidCallback onOuvrir;

  /// Les passées sont atténuées : ce sont des faits, pas des rendez-vous.
  final bool passee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final creneau = context.statuts.creneau(astreinte.creneau);
    final jourEtDate = dateAvecJourSemaine(astreinte.jour);
    final intervalle = heures.intervalle(astreinte.creneau);

    return Semantics(
      button: true,
      label: AppStrings.astreintesLigneSemantique(
        jourEtDate: jourEtDate,
        creneau: creneau.libelle,
        heures: AppStrings.astreintesIntervalleDit(
          astreinte.creneau == CreneauType.jour
              ? heures.debutJour
              : heures.finJour,
          astreinte.creneau == CreneauType.jour
              ? heures.finJour
              : heures.debutJour,
        ),
      ),
      excludeSemantics: true,
      child: InkWell(
        onTap: onOuvrir,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Marge(jour: astreinte.jour, attenuee: passee),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: <Widget>[
                          Text(
                            jourEtDate,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: passee
                                  ? theme.colorScheme.onSurfaceVariant
                                  : null,
                            ),
                          ),
                          StatusBadge.creneau(
                            astreinte.creneau,
                            taille: StatusBadgeTaille.compacte,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        intervalle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Icon(
                    Icons.chevron_right,
                    size: AppTouch.icone,
                    color: theme.colorScheme.onSurfaceVariant,
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

/// La marge du registre : le numéro du jour en chiffres tabulaires, son
/// abréviation dessous, et le fond de week-end.
class _Marge extends StatelessWidget {
  const _Marge({required this.jour, required this.attenuee});

  final DateTime jour;
  final bool attenuee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ferie = nomJourFerie(jour);
    final weekend =
        jour.weekday == DateTime.saturday || jour.weekday == DateTime.sunday;

    return Container(
      width: LigneDAstreinte.largeurMarge,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        // Une astreinte passée n'a plus de week-end : le fond de marge sert à
        // repérer un rendez-vous à venir, pas à colorier un fait.
        color: !attenuee && (weekend || ferie != null)
            ? theme.colorScheme.surfaceDim
            : Colors.transparent,
        borderRadius: AppRadius.caseRegistreRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${jour.day}',
            style: AppTextStyles.nombre.copyWith(
              color: attenuee
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
          Text(
            nomJourCourt(jour),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: weekend && !attenuee ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Le repli des astreintes passées : une ligne, un compte, un chevron.
///
/// **Replié par défaut, toujours** : l'écran s'ouvre sur l'avenir. Le compte
/// est dans le libellé — un repli qui ne dit pas ce qu'il cache n'apprend rien,
/// et ce nombre est lui-même une information.
class ReplisPasseesLigne extends StatelessWidget {
  const ReplisPasseesLigne({
    required this.compte,
    required this.ouvert,
    required this.onBasculer,
    super.key,
  });

  final int compte;
  final bool ouvert;
  final VoidCallback onBasculer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      expanded: ouvert,
      hint: ouvert
          ? AppStrings.astreintesPasseesMasquer
          : AppStrings.astreintesPasseesAfficher,
      child: InkWell(
        onTap: onBasculer,
        child: SizedBox(
          height: AppTouch.bouton,
          child: Row(
            children: <Widget>[
              Icon(
                ouvert ? Icons.expand_less : Icons.expand_more,
                size: AppTouch.icone,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AppStrings.astreintesPassees(compte),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
