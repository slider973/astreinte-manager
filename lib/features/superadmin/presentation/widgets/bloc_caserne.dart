import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../abonnement/presentation/widgets/etat_abonnement_bloc.dart';
import '../../domain/caserne_supervisee.dart';

/// Une caserne, dans un **bloc réglé** : filet 1 dp, rayon 8, sans ombre.
///
/// `DESIGN.md § Cards / Containers` — il n'y a pas de composant « carte », et
/// une grille de cartes identiques est interdite comme structure de page. Trois
/// étages : le nom et son état, les faits, les actions.
class BlocCaserne extends StatelessWidget {
  const BlocCaserne({
    required this.caserne,
    required this.enCours,
    required this.onInviter,
    required this.onSuspension,
    required this.onConsulter,
    super.key,
  });

  final CaserneSupervisee caserne;

  /// Une action de cette ligne est en train de s'exécuter : les boutons
  /// s'éteignent, et celui qui a été touché porte l'indicateur.
  final bool enCours;

  final VoidCallback onInviter;
  final VoidCallback onSuspension;
  final VoidCallback onConsulter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descripteur = descripteurAbonnement(context, caserne.statut);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.controle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(caserne.nom, style: theme.textTheme.titleLarge),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge.descripteur(descripteur),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Faits(caserne: caserne),
          const SizedBox(height: AppSpacing.md),
          _Actions(
            caserne: caserne,
            enCours: enCours,
            onInviter: onInviter,
            onSuspension: onSuspension,
            onConsulter: onConsulter,
          ),
        ],
      ),
    );
  }
}

/// Les faits d'exploitation : effectifs, création, dernier planning publié.
///
/// Les nombres prennent le cut Mono (`DESIGN.md § Do's`) : quatre lignes
/// d'effectifs se comparent d'un coup d'œil ou ne servent à rien.
class _Faits extends StatelessWidget {
  const _Faits({required this.caserne});

  final CaserneSupervisee caserne;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaire = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          AppStrings.superAdminEffectif(
            caserne.membresActifs,
            caserne.adminsActifs,
          ),
          style: theme.textTheme.bodyLarge?.merge(AppTextStyles.nombre),
        ),
        // Le seul défaut qui appelle une action, et il ne se dit pas en gris
        // parmi les autres faits : il porte son icône et l'encre d'attente.
        if (caserne.sansAdministrateur) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          _Alerte(
            texte: caserne.invitationEnRoute
                ? AppStrings.superAdminInvitationsEnAttente(
                    caserne.invitationsEnAttente,
                  )
                : AppStrings.superAdminSansAdmin,
            icone: caserne.invitationEnRoute
                ? Icons.mail_outline
                : Icons.person_off_outlined,
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          AppStrings.superAdminCreeeLe(formaterDateLongue(caserne.creeLe)),
          style: secondaire,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          caserne.aUnPlanningPublie
              ? AppStrings.superAdminDernierPlanning(
                  AppStrings.moisNomEtAnnee(
                    caserne.dernierPlanningMois!,
                    caserne.dernierPlanningAnnee!,
                  ),
                )
              : AppStrings.superAdminAucunPlanning,
          style: secondaire,
        ),
      ],
    );
  }
}

class _Alerte extends StatelessWidget {
  const _Alerte({required this.texte, required this.icone});

  final String texte;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encre = theme.colorScheme.tertiary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icone, size: 18, color: encre),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            texte,
            style: theme.textTheme.bodyMedium?.copyWith(color: encre),
          ),
        ),
      ],
    );
  }
}

/// Les actions, en `Wrap` : sur compact elles s'enroulent au lieu de déborder.
///
/// Chaque libellé annoncé porte le nom de la caserne — quatre boutons
/// « Suspendre » ne se distinguent pas à l'oreille (`DESIGN.md § Chips`, même
/// règle que `SlotChip`).
class _Actions extends StatelessWidget {
  const _Actions({
    required this.caserne,
    required this.enCours,
    required this.onInviter,
    required this.onSuspension,
    required this.onConsulter,
  });

  final CaserneSupervisee caserne;
  final bool enCours;
  final VoidCallback onInviter;
  final VoidCallback onSuspension;
  final VoidCallback onConsulter;

  @override
  Widget build(BuildContext context) {
    final suspendre = !caserne.suspendue;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        _ActionCaserne(
          libelle: AppStrings.superAdminInviterAdmin,
          icone: Icons.person_add_outlined,
          caserne: caserne.nom,
          actif: !enCours,
          // Une caserne sans administrateur : c'est le geste qui la débloque,
          // il passe donc en tête et porte l'encre principale.
          proeminent: caserne.sansAdministrateur,
          onPressed: onInviter,
        ),
        _ActionCaserne(
          libelle: suspendre
              ? AppStrings.superAdminSuspendre
              : AppStrings.superAdminReactiver,
          icone: suspendre
              ? Icons.pause_circle_outline
              : Icons.play_circle_outline,
          caserne: caserne.nom,
          actif: !enCours,
          onPressed: onSuspension,
        ),
        _ActionCaserne(
          libelle: AppStrings.superAdminConsulter,
          icone: Icons.fact_check_outlined,
          caserne: caserne.nom,
          actif: !enCours,
          onPressed: onConsulter,
        ),
      ],
    );
  }
}

class _ActionCaserne extends StatelessWidget {
  const _ActionCaserne({
    required this.libelle,
    required this.icone,
    required this.caserne,
    required this.actif,
    required this.onPressed,
    this.proeminent = false,
  });

  final String libelle;
  final IconData icone;
  final String caserne;
  final bool actif;
  final bool proeminent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      enabled: actif,
      label: AppStrings.superAdminActionSemantique(libelle, caserne),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          // 44 dp de plancher tactile, même sur un écran qu'on n'ouvre pas
          // avec des gants : les règles ne changent pas de porte.
          constraints: const BoxConstraints(minHeight: AppTouch.plancher),
          child: TextButton.icon(
            onPressed: actif ? onPressed : null,
            icon: Icon(icone, size: 20),
            label: Text(libelle),
            style: TextButton.styleFrom(
              foregroundColor: proeminent
                  ? context.statuts.accentTexte
                  : theme.colorScheme.onSurfaceVariant,
              textStyle: proeminent
                  ? theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    )
                  : theme.textTheme.labelLarge,
            ),
          ),
        ),
      ),
    );
  }
}
