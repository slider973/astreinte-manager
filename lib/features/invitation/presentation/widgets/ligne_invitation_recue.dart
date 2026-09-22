import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/invitation_recue.dart';
import 'panneau_invitation.dart';

/// Une invitation reçue, vue par la personne qui l'a reçue.
///
/// **C'est la ligne que l'administrateur a déjà sous les yeux**, vue de
/// l'autre côté : même badge, mêmes libellés « En attente » et « Expirée »,
/// mêmes phrases d'échéance que `LigneInvitation` de l'écran « Membres ». Les
/// deux bouts du produit nomment la même chose du même mot — c'est ce qui
/// permet à un chef de centre de dire au téléphone « tu dois voir “En
/// attente” » et d'être compris.
///
/// Un filet sépare deux lignes, jamais une carte.
///
/// **Aucun instant de référence n'est injecté ici**, contrairement à
/// `LigneInvitation` : l'expiration est celle que le serveur a tranchée
/// (`InvitationRecue.expiree`), et l'horloge de l'appareil n'a pas voix au
/// chapitre. [InvitationRecue.echeance] ne sert qu'à écrire une date.
class LigneInvitationRecue extends StatelessWidget {
  const LigneInvitationRecue({
    required this.invitation,
    required this.onRejoindre,
    this.variante = PrimaryButtonVariante.primaire,
    super.key,
  });

  final InvitationRecue invitation;

  /// Ouvre l'écran d'invitation, qui accepte. **On n'accepte pas ici** : les
  /// six fins de parcours et la chaîne « Bienvenue → profil → guide » vivent
  /// là-bas, et une seule fois.
  final VoidCallback onRejoindre;

  /// `primaire` quand c'est l'action de l'écran, `secondaire` dès qu'il y a
  /// plusieurs invitations : aucune n'est « la » bonne, et hiérarchiser au
  /// hasard deux casernes serait un avis que le produit n'a pas à donner.
  final PrimaryButtonVariante variante;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = formaterDateLongue(invitation.echeance);
    final echeance = invitation.expiree
        ? AppStrings.invitationExpireeDepuis(date)
        : AppStrings.invitationExpireLe(date);
    final etat = invitation.expiree
        ? AppStrings.invitationExpiree
        : AppStrings.invitationEnAttente;
    final inviteur = invitation.inviteur;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Le descriptif se lit d'une phrase ; le bouton reste hors de ce
          // conteneur, sinon il disparaîtrait de l'arbre d'accessibilité.
          Semantics(
            container: true,
            excludeSemantics: true,
            label: AppStrings.invitationRecueSemantique(
              caserne: invitation.caserne,
              inviteur: inviteur,
              etat: etat,
              echeance: echeance,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(invitation.caserne, style: theme.textTheme.titleMedium),
                if (inviteur != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxs),
                  TexteInvitation(AppStrings.invitationParQui(inviteur)),
                ],
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    if (invitation.expiree)
                      const StatusBadge.attribution(
                        AttributionEtat.annule,
                        libelle: AppStrings.invitationExpiree,
                      )
                    else
                      const StatusBadge.attribution(
                        AttributionEtat.propose,
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
          const SizedBox(height: AppSpacing.lg),
          // Expirée : **pas de bouton**. Un bouton dont on sait qu'il échouera
          // est un piège, et un bouton grisé n'aurait rien à dire de plus que
          // la phrase qui le remplace — laquelle, elle, nomme la sortie.
          if (invitation.expiree)
            TexteInvitation(
              inviteur == null
                  ? AppStrings.invitationExpireeDemanderSansNom
                  : AppStrings.invitationExpireeDemander(inviteur),
            )
          else
            PrimaryButton(
              libelle: AppStrings.invitationRejoindre(invitation.caserne),
              icone: Icons.arrow_forward,
              variante: variante,
              onPressed: onRejoindre,
            ),
        ],
      ),
    );
  }
}
