import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/invitation.dart';

/// Une invitation en attente : l'adresse, son échéance, et les deux sorties.
///
/// L'état est porté par un badge (marque + icône + libellé) et non par la
/// seule couleur : une invitation périmée se lit en niveaux de gris.
class LigneInvitation extends StatelessWidget {
  const LigneInvitation({
    required this.invitation,
    required this.onRenvoyer,
    required this.onAnnuler,
    required this.maintenant,
    super.key,
    this.occupee = false,
  });

  final Invitation invitation;
  final VoidCallback onRenvoyer;
  final VoidCallback onAnnuler;

  /// L'instant de référence, injecté : une date « expirée » doit se tester.
  final DateTime maintenant;

  /// Vrai pendant qu'une action est en cours sur cette ligne : les deux
  /// boutons sont alors inertes, pour ne pas envoyer deux fois.
  final bool occupee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiree = invitation.expiree(maintenant);
    final date = formaterDateLongue(invitation.expireLe);
    final echeance = expiree
        ? AppStrings.invitationExpireeDepuis(date)
        : AppStrings.invitationExpireLe(date);

    return Semantics(
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.cible),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(invitation.email, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        if (expiree)
                          const StatusBadge.attribution(
                            AttributionEtat.annule,
                            taille: StatusBadgeTaille.compacte,
                            libelle: AppStrings.invitationExpiree,
                          )
                        else
                          const StatusBadge.attribution(
                            AttributionEtat.propose,
                            taille: StatusBadgeTaille.compacte,
                            libelle: AppStrings.invitationEnAttente,
                          ),
                        Text(
                          echeance,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ActionInvitation(
                icone: Icons.refresh,
                libelle: AppStrings.invitationRenvoyerSemantique(
                  invitation.email,
                ),
                onPressed: occupee ? null : onRenvoyer,
              ),
              const SizedBox(width: AppSpacing.entreCibles),
              _ActionInvitation(
                icone: Icons.delete_outline,
                libelle: AppStrings.invitationAnnulerSemantique(
                  invitation.email,
                ),
                onPressed: occupee ? null : onAnnuler,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un bouton d'action de 48 dp, avec son libellé annoncé et son info-bulle :
/// aucune action n'est accessible par le seul survol.
class _ActionInvitation extends StatelessWidget {
  const _ActionInvitation({
    required this.icone,
    required this.libelle,
    required this.onPressed,
  });

  final IconData icone;
  final String libelle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: libelle,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: AppTouch.cible,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icone),
          tooltip: libelle,
        ),
      ),
    );
  }
}
