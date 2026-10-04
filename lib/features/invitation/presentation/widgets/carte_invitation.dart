import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/carte_douce.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/invitation_providers.dart';
import '../../domain/invitation_recue.dart';

/// Les invitations encore valables d'un membre **déjà rattaché** (ticket 072).
///
/// Une source secondaire : en chargement, en échec, hors ligne ou expirée,
/// l'accueil n'en dit rien — il ne passe pas en erreur pour elle, et il n'y a
/// aucun geste possible sur une invitation expirée. C'est le Profil qui dit
/// l'échec et l'expiration (`design/072 § 5.2`).
final Provider<List<InvitationRecue>> invitationsAccueilProvider =
    Provider.autoDispose<List<InvitationRecue>>(
      (ref) => <InvitationRecue>[
        for (final invitation
            in ref.watch(invitationsRecuesProvider).value ??
                const <InvitationRecue>[])
          if (invitation.valide) invitation,
      ],
    );

/// **« CS Ury t'invite »**, en tête de l'accueil (`design/072 § 6.5`).
///
/// La seule chose de l'écran qui demande une décision qu'aucun autre écran
/// n'offre. On n'accepte pas sur la carte : « Voir l'invitation » ouvre
/// `/rejoindre/:id`, qui porte l'acceptation et ses fins de parcours — même
/// raison qu'au ticket 051. Pas de « Ignorer » : une invitation expire seule.
class CarteInvitation extends StatelessWidget {
  const CarteInvitation({required this.invitation, super.key});

  final InvitationRecue invitation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = formaterDateCourte(invitation.echeance);
    final inviteur = invitation.inviteur;
    final detail = inviteur == null
        ? AppStrings.accueilInvitationDetailSansInviteur(date)
        : AppStrings.accueilInvitationDetail(inviteur, date);

    return CarteDouce(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            container: true,
            label: AppStrings.accueilInvitationSemantique(
              invitation.caserne,
              date,
            ),
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: AppRadius.feuilleCarreeRadius,
                  ),
                  child: Icon(
                    Icons.mark_email_unread_outlined,
                    size: AppTouch.icone,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        AppStrings.accueilInvitationTitre(invitation.caserne),
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        detail,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: PrimaryButton(
              libelle: AppStrings.accueilInvitationAction,
              variante: PrimaryButtonVariante.secondaire,
              pleineLargeur: false,
              onPressed: () => context.goNamed(
                AppRoutes.rejoindreName,
                pathParameters: <String, String>{
                  AppRoutes.parametreInvitation: invitation.id,
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Les cartes de l'accueil, une par invitation valable, ou rien.
class CartesInvitations extends ConsumerWidget {
  const CartesInvitations({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitations = ref.watch(invitationsAccueilProvider);
    if (invitations.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < invitations.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            CarteInvitation(
              key: ValueKey<String>(invitations[i].id),
              invitation: invitations[i],
            ),
          ],
        ],
      ),
    );
  }
}
