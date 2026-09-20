import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/suivi_planning.dart';

/// Les pompiers qui n'ont pas répondu, et le bouton qui les relance.
///
/// **Le bloc n'existe pas quand il n'y a personne** : « 0 retardataire » est du
/// bruit. Et le retard est un **fait gris**, jamais une alarme rouge — un
/// pompier sans réponse était en intervention, en vacances, ou n'a pas vu
/// passer la notification. L'ocre d'attente, pas le vermillon.
class BlocRetardataires extends StatelessWidget {
  const BlocRetardataires({
    required this.retardataires,
    required this.compte,
    required this.delaiHeures,
    required this.onRelancer,
    super.key,
    this.enVol = false,
    this.raisonInactif,
  });

  /// Les noms que l'écran a su résoudre.
  final List<Retardataire> retardataires;

  /// Le nombre que rend `v_schedule_progress.assignments_late` — **le compte
  /// fait autorité**, la liste dit qui. Les deux appliquent la même règle et
  /// ne divergent qu'à la seconde près, au bord du délai ; quand ils
  /// divergent, c'est la base qui a raison.
  final int compte;

  /// `settings.late_report_hours` de la caserne, jamais un 72 écrit en dur.
  final int delaiHeures;

  final VoidCallback? onRelancer;
  final bool enVol;

  /// Pourquoi la relance est impossible. **Un contrôle désactivé porte sa
  /// raison** (`DESIGN.md § Do's`).
  final String? raisonInactif;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attente = context.statuts.attribution(AttributionEtat.propose);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: AppRadius.controleRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.schedule, size: 20, color: attente.encre),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      AppStrings.suiviRetardatairesTitre(compte),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              AppStrings.suiviRetardatairesDetail(delaiHeures),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final retardataire in retardataires)
              _LigneRetardataire(retardataire: retardataire),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              libelle: enVol
                  ? AppStrings.suiviRelanceEnCours
                  : AppStrings.suiviRelancer,
              variante: PrimaryButtonVariante.secondaire,
              icone: Icons.notifications_active_outlined,
              chargement: enVol,
              raisonDesactivation: raisonInactif,
              onPressed: raisonInactif != null || enVol ? null : onRelancer,
            ),
          ],
        ),
      ),
    );
  }
}

/// Une ligne de 56 dp : le nom, puis ce qui est en jeu.
class _LigneRetardataire extends StatelessWidget {
  const _LigneRetardataire({required this.retardataire});

  final Retardataire retardataire;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final relance = retardataire.derniereRelance;

    // Le nombre de créneaux d'abord : c'est ce qui dit l'enjeu.
    final detail = <String>[
      AppStrings.suiviRetardataireLigne(
        creneaux: retardataire.creneaux,
        depuis: formaterInstantRelatif(retardataire.depuis),
      ),
      if (relance != null)
        AppStrings.suiviRelanceLe(formaterInstantRelatif(relance)),
    ].join(' · ');

    return Semantics(
      container: true,
      label: '${retardataire.nom}. $detail',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(retardataire.nom, style: theme.textTheme.bodyLarge),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
