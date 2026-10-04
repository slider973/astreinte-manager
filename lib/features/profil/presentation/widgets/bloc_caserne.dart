import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/session/caserne_choisie.dart';
import '../../../../core/session/session_providers.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/liste_casernes.dart';
import '../../../invitation/domain/invitation_providers.dart';
import '../../../invitation/domain/invitation_recue.dart';
import 'bloc_regle.dart';

/// La caserne où l'on travaille, et le moyen d'en changer quand il y en a
/// plusieurs.
///
/// **Le sélecteur n'apparaît qu'à partir de deux appartenances actives** : un
/// contrôle à un seul choix est un contrôle de trop, et la très grande majorité
/// des pompiers n'appartient qu'à une caserne (`design/007-profil.md § 5.2`).
class BlocCaserne extends ConsumerWidget {
  const BlocCaserne({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courante = ref.watch(appartenanceCouranteProvider);
    final plusieurs = ref.watch(plusieursCasernesProvider);

    return BlocRegle(
      titre: AppStrings.profilCaserneTitre,
      enfants: <Widget>[
        LigneLecture(
          libelle: AppStrings.accueilCaserneLabel,
          // Le titre du bloc dit déjà « Ta caserne » : le répéter au-dessus du
          // nom ferait lire deux fois la même chose.
          libelleVisible: false,
          valeur: courante?.nomCaserne ?? AppStrings.valueUndefined,
          icone: Icons.local_fire_department_outlined,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.lg),
        LigneLecture(
          libelle: AppStrings.accueilRoleLabel,
          valeur: courante?.role.libelle ?? AppStrings.valueUndefined,
        ),
        if (plusieurs) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          const AppDivider(),
          const SizedBox(height: AppSpacing.lg),
          const _Selecteur(),
        ],
        const SizedBox(height: AppSpacing.sm),
        const _Invitations(),
      ],
    );
  }
}

/// Le choix, partagé avec la feuille de l'accueil et le menu du grand écran
/// (`ListeCasernes`, ticket 072). Un groupe de boutons radio, **jamais un menu
/// déroulant** : deux ou trois entrées tiennent à l'écran.
class _Selecteur extends StatelessWidget {
  const _Selecteur();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            AppStrings.profilCaserneChoixTitre,
            style: theme.textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          AppStrings.profilCaserneChoixAide,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const ListeCasernes(avecInvitations: false),
      ],
    );
  }
}

/// **Les invitations d'un membre déjà rattaché** (ticket 072,
/// `design/072 § 6.5`) : une ligne par invitation, l'expirée dite avec sa
/// sortie, l'échec de lecture dit avec « Réessayer ». Rien n'est gardé sur
/// l'appareil (`invitationsRecuesProvider`).
class _Invitations extends ConsumerWidget {
  const _Invitations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lecture = ref.watch(invitationsRecuesProvider);
    final style = theme.textTheme.bodyMedium;

    if (lecture.hasError && !lecture.isLoading) {
      return Row(
        children: <Widget>[
          Expanded(
            child: Text(AppStrings.profilInvitationsEchec, style: style),
          ),
          TextButton(
            onPressed: () => ref.invalidate(invitationsRecuesProvider),
            child: const Text(AppStrings.actionReessayer),
          ),
        ],
      );
    }

    final invitations = lecture.value ?? const <InvitationRecue>[];
    if (invitations.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final invitation in invitations)
          if (invitation.expiree)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                AppStrings.profilInvitationExpiree(invitation.caserne),
                style: style?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.cible),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      AppStrings.profilInvitationLigne(
                        invitation.caserne,
                        formaterDateLongueSansAnnee(invitation.echeance),
                      ),
                      style: style,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton(
                    onPressed: () => context.goNamed(
                      AppRoutes.rejoindreName,
                      pathParameters: <String, String>{
                        AppRoutes.parametreInvitation: invitation.id,
                      },
                    ),
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
            ),
      ],
    );
  }
}
