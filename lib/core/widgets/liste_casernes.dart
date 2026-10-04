import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/invitation/domain/invitation_providers.dart';
import '../../features/invitation/domain/invitation_recue.dart';
import '../../features/notifications/domain/centre_providers.dart';
import '../l10n/app_strings.dart';
import '../session/appartenance.dart';
import '../session/bascule_caserne.dart';
import '../session/session_providers.dart';
import '../theme/app_spacing.dart';
import 'app_divider.dart';

/// **Le choix de la caserne**, en un seul endroit (ticket 072,
/// `design/072 § 6.2`).
///
/// Le Profil, la feuille de l'accueil et le menu du grand écran posent tous
/// les trois cette liste : une ligne par caserne active, dans l'ordre des
/// appartenances (alphabétique — une liste qui se réordonnerait sous le pouce
/// tromperait), puis les invitations en attente.
///
/// **Toucher une ligne bascule tout de suite** : pas de « Valider », deux
/// touches en tout depuis l'accueil. La caserne ouverte se lit au radio
/// rempli, à la coche et au mot « Ouverte », jamais à la seule teinte.
class ListeCasernes extends ConsumerWidget {
  const ListeCasernes({
    super.key,
    this.onChoisie,
    this.onInvitation,
    this.avecInvitations = true,
  });

  /// Appelé après le choix d'une ligne — ouverte comprise : la feuille et le
  /// menu se ferment.
  final VoidCallback? onChoisie;

  /// Ouvre une invitation (`/rejoindre/:id`). `null` : pas de section.
  final ValueChanged<String>? onInvitation;

  /// Faux au Profil, qui dit ses invitations dans son propre bloc.
  final bool avecInvitations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actives = ref.watch(appartenancesActivesProvider);
    final courante = ref.watch(appartenanceCouranteProvider);
    final ailleurs = ref.watch(nonLuesAilleursProvider);
    final invitations = avecInvitations && onInvitation != null
        ? (ref.watch(invitationsRecuesProvider).value ??
                  const <InvitationRecue>[])
              .where((InvitationRecue i) => i.valide)
              .toList()
        : const <InvitationRecue>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        RadioGroup<String>(
          groupValue: courante?.stationId,
          onChanged: (String? stationId) =>
              _choisir(context, ref, stationId, actives),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final appartenance in actives)
                _LigneCaserne(
                  appartenance: appartenance,
                  ouverte: appartenance.stationId == courante?.stationId,
                  nonLues: ailleurs[appartenance.stationId] ?? 0,
                  onTap: () => _choisir(
                    context,
                    ref,
                    appartenance.stationId,
                    actives,
                  ),
                ),
            ],
          ),
        ),
        if (invitations.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          const AppDivider(),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            header: true,
            child: Text(
              AppStrings.caserneChoixInvitationsTitre,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final invitation in invitations)
            _LigneInvitation(
              invitation: invitation,
              onVoir: () => onInvitation!(invitation.id),
            ),
        ],
      ],
    );
  }

  void _choisir(
    BuildContext context,
    WidgetRef ref,
    String? stationId,
    List<Appartenance> actives,
  ) {
    if (stationId == null) return;
    final courante = ref.read(appartenanceCouranteProvider);
    if (stationId != courante?.stationId) {
      unawaited(ref.read(basculeCaserneProvider.notifier).choisir(stationId));
      // Pas de bandeau après un choix manuel, mais une annonce : le lecteur
      // d'écran doit savoir que tout ce qui suit a changé de cadre.
      final nom = actives
          .firstWhere((Appartenance a) => a.stationId == stationId)
          .nomCaserne;
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          AppStrings.caserneOuverteAnnonce(nom),
          Directionality.of(context),
        ),
      );
    }
    onChoisie?.call();
  }
}

class _LigneCaserne extends StatelessWidget {
  const _LigneCaserne({
    required this.appartenance,
    required this.ouverte,
    required this.nonLues,
    required this.onTap,
  });

  /// Hauteur minimale d'une ligne : deux lignes de texte et un doigt ganté.
  static const double hauteur = 64;

  final Appartenance appartenance;
  final bool ouverte;
  final int nonLues;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondaire = AppStrings.caserneChoixLigne(
      appartenance.role.libelle,
      nonLues,
    );

    return Semantics(
      selected: ouverte,
      button: true,
      inMutuallyExclusiveGroup: true,
      label: '${appartenance.nomCaserne}, $secondaire'
          '${ouverte ? ', ${AppStrings.caserneChoixOuverte}' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controleRadius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: hauteur),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                Radio<String>(value: appartenance.stationId),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        appartenance.nomCaserne,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: ouverte ? FontWeight.w600 : null,
                        ),
                      ),
                      Text(
                        secondaire,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (ouverte) ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(Icons.check, size: AppTouch.icone, color: scheme.primary),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    AppStrings.caserneChoixOuverte,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LigneInvitation extends StatelessWidget {
  const _LigneInvitation({required this.invitation, required this.onVoir});

  final InvitationRecue invitation;
  final VoidCallback onVoir;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.cible),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              AppStrings.caserneChoixInvitation(invitation.caserne),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: onVoir,
            style: TextButton.styleFrom(
              minimumSize: const Size(AppTouch.cible, AppTouch.cible),
            ),
            child: Text(
              AppStrings.caserneChoixInvitationAction,
              semanticsLabel:
                  '${AppStrings.caserneChoixInvitationAction} · '
                  '${AppStrings.caserneChoixInvitation(invitation.caserne)}',
            ),
          ),
        ],
      ),
    );
  }
}
