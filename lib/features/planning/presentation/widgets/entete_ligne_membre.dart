import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/avatar_initiales.dart';
import '../../domain/ligne_matrice.dart';
import 'geometrie_matrice.dart';

/// L'en-tête d'une ligne de membre : le nom, les deux quotas, le commentaire.
///
/// **Le commentaire n'est pas derrière une icône.** Quand il existe, il
/// s'écrit en clair sous le nom, sur une seconde ligne. Dix membres sur
/// soixante en écrivent un : la vue coûte 200 px de défilement vertical, un
/// axe qui n'est pas contraint ici ; une icône à survoler aurait coûté zéro
/// pixel et cent pour cent des lectures (brief § 6.2).
///
/// Toucher l'en-tête déplie le commentaire en entier, trois lignes au plus,
/// et le replie. Rien d'autre : la place d'un panneau est réservée au
/// ticket 017, et deux panneaux concurrents seraient une dette immédiate.
class EnteteLigneMembre extends StatelessWidget {
  const EnteteLigneMembre({
    required this.ligne,
    required this.largeur,
    required this.commentaires,
    required this.deplie,
    required this.onDeplier,
    super.key,
  });

  final LigneMatrice ligne;
  final double largeur;

  /// Les commentaires sont affichés (interrupteur de la barre de commande).
  final bool commentaires;

  /// Ce commentaire-ci est déplié.
  final bool deplie;

  final VoidCallback onDeplier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final montrerCommentaire = commentaires && ligne.aUnCommentaire;
    final hauteur = GeoMatrice.hauteurDe(
      ligne,
      commentaires: commentaires,
      deplie: deplie,
    );

    final contenu = SizedBox(
      height: hauteur,
      width: largeur,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: GeoMatrice.hauteurLigne,
              child: Row(
                children: <Widget>[
                  // **Décoratif, et rien d'autre.** Le disque distingue deux
                  // lignes voisines d'un coup d'œil ; le nom juste à côté est
                  // le seul libellé, et l'annoncer deux fois n'apprend rien.
                  // 24 points : la ligne en fait 32, et la hauteur ne bouge
                  // pas (`design/061 § 8 bis`).
                  ExcludeSemantics(
                    child: AvatarInitiales(
                      nom: ligne.nomAffiche,
                      taille: GeoMatrice.tailleAvatar,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      ligne.nomAffiche,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.corpsSecondaire.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  _Quota(
                    icone: Icons.event_available,
                    charge: ligne.astreintes,
                    plafond: ligne.maxAstreintes,
                    reste: ligne.astreintesRestantes,
                  ),
                  _Quota(
                    icone: Icons.weekend,
                    charge: ligne.unitesWeekend,
                    plafond: ligne.maxWeekends,
                    reste: ligne.weekendsRestants,
                  ),
                ],
              ),
            ),
            if (montrerCommentaire)
              Expanded(
                child: _Commentaire(
                  texte: ligne.commentaire!,
                  lignes: deplie ? GeoMatrice.lignesCommentaireDeplie : 1,
                ),
              ),
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      label: AppStrings.matriceLigneSemantique(
        nom: ligne.nomAffiche,
        quotas: semantiqueQuotas(ligne),
        commentaire: ligne.aUnCommentaire
            ? ligne.commentaire!
            : AppStrings.matriceCommentaireVide,
      ),
      button: ligne.aUnCommentaire,
      excludeSemantics: true,
      onTap: ligne.aUnCommentaire ? onDeplier : null,
      child: ligne.aUnCommentaire
          ? InkWell(onTap: onDeplier, child: contenu)
          : contenu,
    );
  }

  /// Les quotas en phrase complète, `accepted_previous` compris : il n'a pas
  /// de colonne à l'écran mais il vit ici et dans l'info-bulle.
  static String semantiqueQuotas(LigneMatrice ligne) => <String>[
    _phrase(
      plafond: ligne.maxAstreintes,
      charge: ligne.astreintes,
      reste: ligne.astreintesRestantes,
      sansPlafond: AppStrings.matriceQuotaSansPlafond,
      atteint: AppStrings.matriceQuotaAstreintesAtteint,
      depasse: AppStrings.matriceQuotaAstreintesDepasse,
      restant: AppStrings.matriceQuotaAstreintes,
    ),
    _phrase(
      plafond: ligne.maxWeekends,
      charge: ligne.unitesWeekend,
      reste: ligne.weekendsRestants,
      sansPlafond: AppStrings.matriceQuotaWeekendsSansPlafond,
      atteint: AppStrings.matriceQuotaWeekendsAtteint,
      depasse: AppStrings.matriceQuotaWeekendsDepasse,
      restant: AppStrings.matriceQuotaWeekends,
    ),
    AppStrings.matriceChargePrecedente(ligne.accepteesPrecedentes),
  ].join('. ');

  static String _phrase({
    required int? plafond,
    required int charge,
    required int? reste,
    required String Function(int) sansPlafond,
    required String Function(int) atteint,
    required String Function(int) depasse,
    required String Function(int, int) restant,
  }) {
    if (plafond == null || reste == null) return sansPlafond(charge);
    if (reste == 0) return atteint(plafond);
    if (reste < 0) return depasse(-reste);
    return restant(reste, plafond);
  }
}

/// Un compteur de quota, dans 48 px.
///
/// **La barre de fraction est le signe qu'un plafond existe.** Son absence dit
/// l'illimité sans écrire un mot qui ne tient pas dans 48 px, et sans le `∞`
/// que le ticket 013 a déjà proscrit. Le zéro et le signe moins sont des
/// caractères : la couleur ne fait que les renforcer.
class _Quota extends StatelessWidget {
  const _Quota({
    required this.icone,
    required this.charge,
    required this.plafond,
    required this.reste,
  });

  final IconData icone;
  final int charge;
  final int? plafond;
  final int? reste;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ocre = context.statuts.attribution(AttributionEtat.propose);

    final sansPlafond = plafond == null || reste == null;
    final depasse = !sansPlafond && reste! < 0;
    final atteint = !sansPlafond && reste == 0;

    final texte = sansPlafond ? '$charge' : '$reste/$plafond';
    final encre = switch (0) {
      _ when depasse => ocre.encre,
      _ when atteint => ocre.encre,
      _ when sansPlafond => theme.colorScheme.onSurfaceVariant,
      _ => theme.colorScheme.onSurface,
    };

    final contenu = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icone, size: AppTouch.iconePetite, color: encre),
        const SizedBox(width: AppSpacing.xs),
        Text(texte, style: AppTextStyles.nombrePetit.copyWith(color: encre)),
      ],
    );

    return SizedBox(
      width: GeoMatrice.largeurQuota,
      child: Align(
        alignment: Alignment.centerRight,
        // Le nombre se réduit plutôt que de déborder sa colonne à grande
        // échelle de texte : même règle que `CountStat` au ticket 004.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: depasse
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: ocre.fond,
                    borderRadius: AppRadius.caseRegistreRadius,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: contenu,
                  ),
                )
              : contenu,
        ),
      ),
    );
  }
}

class _Commentaire extends StatelessWidget {
  const _Commentaire({required this.texte, required this.lignes});

  final String texte;
  final int lignes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Icon(
            Icons.chat_bubble_outline,
            size: AppTouch.iconePetite,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Tooltip(
            message: texte,
            child: Text(
              texte,
              maxLines: lignes,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.mention.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
