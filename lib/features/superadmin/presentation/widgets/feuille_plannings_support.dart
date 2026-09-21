import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/caserne_supervisee.dart';

/// Ce que la consultation de support a rendu : l'avancement des plannings,
/// mois par mois, et rien qui nomme quelqu'un.
///
/// La feuille répète, en bas, que la consultation est inscrite au journal
/// d'audit de la caserne. Ce n'est pas une redondance : la phrase a été lue
/// avant l'action, elle doit rester vraie et visible pendant qu'on regarde.
Future<void> afficherPlanningsSupport({
  required BuildContext context,
  required String caserne,
  required List<PlanningSupervise> plannings,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) =>
      _FeuillePlannings(caserne: caserne, plannings: plannings),
);

class _FeuillePlannings extends StatelessWidget {
  const _FeuillePlannings({required this.caserne, required this.plannings});

  final String caserne;
  final List<PlanningSupervise> plannings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marge = AppWindowClass.of(context).margePage;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController defilement) => ListView(
        controller: defilement,
        padding: EdgeInsets.fromLTRB(
          marge,
          AppSpacing.lg,
          marge,
          AppSpacing.lg,
        ),
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(caserne, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppStrings.superAdminSupportPortee,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (plannings.isEmpty)
            const EmptyState(
              titre: AppStrings.superAdminSupportVideTitre,
              texte: AppStrings.superAdminSupportVideTexte,
              icone: Icons.event_busy_outlined,
            )
          else
            for (final PlanningSupervise planning in plannings)
              _LignePlanning(planning: planning),
          const SizedBox(height: AppSpacing.lg),
          Text(
            AppStrings.superAdminSupportAide,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            libelle: AppStrings.actionFermer,
            variante: PrimaryButtonVariante.secondaire,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _LignePlanning extends StatelessWidget {
  const _LignePlanning({required this.planning});

  final PlanningSupervise planning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaire = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.controle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  AppStrings.moisNomEtAnnee(planning.mois, planning.annee),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              StatusBadge.planning(planning.etat),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${AppStrings.superAdminSupportCreneaux(planning.creneaux)} · '
            '${AppStrings.superAdminSupportAttributions(planning.total)}',
            style: theme.textTheme.bodyMedium?.merge(AppTextStyles.nombre),
          ),
          if (planning.etatsPresents.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              // Les libellés viennent des descripteurs du thème, ceux-là mêmes
              // que porte l'écran de suivi : « Accepté » veut dire la même
              // chose des deux côtés.
              planning.etatsPresents
                  .map(
                    (AttributionEtat e) =>
                        '${planning.compte(e)} '
                        '${context.statuts.attribution(e).libelle.toLowerCase()}',
                  )
                  .join(' · '),
              style: secondaire?.merge(AppTextStyles.nombrePetit),
            ),
          ],
          if (planning.publieLe != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              AppStrings.superAdminSupportPublieLe(
                formaterDateLongue(planning.publieLe!),
              ),
              style: secondaire,
            ),
          ],
          if (planning.valideLe != null)
            Text(
              AppStrings.superAdminSupportValideLe(
                formaterDateLongue(planning.valideLe!),
              ),
              style: secondaire,
            ),
        ],
      ),
    );
  }
}
