import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/invitation.dart';

/// Une invitation en attente : qui elle vise, son échéance, et les deux
/// sorties.
///
/// **Le nom en titre quand il est connu** (ticket 047) : un chef de centre qui
/// vient d'importer sa caserne passerait sinon deux semaines devant une liste
/// d'adresses. Une invitation créée à la main n'en a pas — le formulaire ne
/// demande que des adresses — et garde exactement la forme du ticket 006.
///
/// L'état est porté par un badge (marque + icône + libellé) et non par la
/// seule couleur : une invitation périmée se lit en niveaux de gris.
///
/// **Ce que la caserne sait de l'envoi du courriel** (ticket 048) se dit sur
/// la même ligne, en trois états et jamais deux (voir [_Envoi]). Sans lui,
/// une invitation dont le courriel n'est jamais parti affiche « En attente »
/// et sa date d'expiration, exactement comme une invitation partie que le
/// destinataire tarde à accepter : l'administrateur attend alors une réponse
/// que personne ne peut lui donner.
class LigneInvitation extends StatelessWidget {
  const LigneInvitation({
    required this.invitation,
    required this.onRenvoyer,
    required this.onAnnuler,
    this.lectureSeule = false,
    required this.maintenant,
    super.key,
    this.occupee = false,
  });

  final Invitation invitation;
  final VoidCallback onRenvoyer;
  final VoidCallback onAnnuler;

  /// Caserne suspendue : les deux boutons restent, inertes, et leur libellé
  /// annoncé dit la raison (ticket 030).
  final bool lectureSeule;

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
    final envoye = invitation.courrielEnvoyeLe;
    final envoi = envoye == null ? null : formaterDateLongue(envoye);

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
                    Text(
                      invitation.nomComplet ?? invitation.email,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (invitation.nomComplet != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        invitation.email,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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
                        _Envoi(etat: invitation.envoiCourriel, date: envoi),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ActionInvitation(
                icone: Icons.refresh,
                libelle: lectureSeule
                    ? AppStrings.membresSuspendue
                    : AppStrings.invitationRenvoyerSemantique(invitation.email),
                onPressed: occupee || lectureSeule ? null : onRenvoyer,
              ),
              const SizedBox(width: AppSpacing.entreCibles),
              _ActionInvitation(
                icone: Icons.delete_outline,
                libelle: lectureSeule
                    ? AppStrings.membresSuspendue
                    : AppStrings.invitationAnnulerSemantique(invitation.email),
                onPressed: occupee || lectureSeule ? null : onAnnuler,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ce que la caserne sait de l'envoi du courriel (ticket 048).
///
/// **Trois états, et un gris pour les trois.** En production aucun
/// fournisseur de courriel n'est configuré : toute la liste est alors dans
/// l'état [EnvoiCourriel.nonParti], et une liste entièrement rouge ne dirait
/// plus rien. C'est un fait de la maison, pas une faute — `DESIGN.md § Do`
/// range « verrouillé », « suspendu », « annulé » du même côté, et l'aperçu
/// d'import applique déjà cette distinction. Ce qui sépare les trois états
/// est donc l'icône et le libellé, jamais la teinte.
///
/// Le geste utile est juste à droite : « Renvoyer », sur la même ligne. Le
/// lien, lui, n'est pas affichable — `token` est hors du grant de select
/// (migration `0008`), un écran admin ne voit jamais le lien qu'il a envoyé.
class _Envoi extends StatelessWidget {
  const _Envoi({required this.etat, this.date});

  final EnvoiCourriel etat;

  /// La date du dernier envoi réussi, déjà formatée. Nulle hors de
  /// [EnvoiCourriel.parti].
  final String? date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encre = theme.colorScheme.onSurfaceVariant;

    // La date fait partie de la phrase : « parti » sans date ne se dit pas à
    // moitié, il retombe sur « on ne sait pas », qui reste vrai.
    final (IconData icone, String libelle) = switch ((etat, date)) {
      (EnvoiCourriel.nonParti, _) => (
        Icons.schedule_send_outlined,
        AppStrings.invitationCourrielNonParti,
      ),
      (EnvoiCourriel.parti, final String quand) => (
        Icons.mark_email_read_outlined,
        AppStrings.invitationCourrielEnvoyeLe(quand),
      ),
      _ => (Icons.help_outline, AppStrings.invitationCourrielInconnu),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icone, size: AppTouch.icone, color: encre),
        const SizedBox(width: AppSpacing.xs),
        // Souple : à grande taille de police ou sur un petit écran, la phrase
        // se replie plutôt que de déborder de la ligne.
        Flexible(
          child: Text(
            libelle,
            style: theme.textTheme.bodyMedium?.copyWith(color: encre),
          ),
        ),
      ],
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
