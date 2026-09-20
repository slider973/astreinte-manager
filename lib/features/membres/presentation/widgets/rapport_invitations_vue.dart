import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../domain/invitation.dart';

/// Le sort de chaque adresse, une ligne par adresse.
///
/// Un envoi de lot n'a pas de résultat unique : il en a autant que d'adresses.
/// L'écran ne dit donc jamais « envoyé » ni « échec » globalement — il nomme
/// chaque adresse, son statut et, s'il y a lieu, le motif en français.
class RapportInvitationsVue extends StatelessWidget {
  const RapportInvitationsVue({required this.rapport, super.key});

  final RapportInvitations rapport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          liveRegion: true,
          child: Text(
            AppStrings.inviterResume(
              envoyees: rapport.envoyees,
              echecs: rapport.echecs,
            ),
            style: theme.textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: AppSpacing.auDessusTitre),
        Semantics(
          header: true,
          child: Text(
            AppStrings.inviterResultatsTitre,
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const AppDivider(),
        for (final resultat in rapport.resultats) ...<Widget>[
          _LigneResultat(resultat: resultat),
          const AppDivider(),
        ],
      ],
    );
  }
}

class _LigneResultat extends StatelessWidget {
  const _LigneResultat({required this.resultat});

  final ResultatInvitation resultat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = resultat.detail;

    final (IconData icone, Color encre) = switch (resultat.statut) {
      StatutResultatInvitation.erreur => (
        Icons.error_outline,
        theme.colorScheme.error,
      ),
      StatutResultatInvitation.renvoyee => (
        Icons.mark_email_read_outlined,
        theme.colorScheme.onSurfaceVariant,
      ),
      StatutResultatInvitation.invitee => (
        Icons.check_circle_outline,
        theme.colorScheme.onSurfaceVariant,
      ),
    };

    // Le courriel qui n'est pas parti n'est pas un échec d'invitation : la
    // ligne existe, le renvoi la relance. L'icône le dit sans crier.
    final iconeEffective = !resultat.enEchec && !resultat.courrielEnvoye
        ? Icons.schedule_send_outlined
        : icone;

    return Semantics(
      label: resultat.email,
      value: <String>[resultat.statut.libelle, ?detail].join('. '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(iconeEffective, size: AppTouch.icone, color: encre),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(resultat.email, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    resultat.statut.libelle,
                    style: theme.textTheme.labelMedium?.copyWith(color: encre),
                  ),
                  if (detail != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      detail,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: resultat.enEchec
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
