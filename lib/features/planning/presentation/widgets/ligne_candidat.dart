import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/candidat.dart';

/// Ce que la ligne propose de faire.
///
/// Quatre actions pour deux gestes : le libellé change avec la **conséquence**,
/// pas avec le geste. En brouillon on attribue et on retire ; sur un planning
/// publié on réattribue — un téléphone sonne — et on annule — une trace reste
/// (`design/020 § 5.2`).
enum ActionCandidat {
  attribuer(AppStrings.planningAttribuer, Icons.person_add_alt_1),
  retirer(AppStrings.planningRetirer, Icons.person_remove_outlined),
  reattribuer(AppStrings.reattribuerAction, Icons.published_with_changes),
  annuler(AppStrings.annulerAstreinteAction, Icons.block);

  const ActionCandidat(this.libelle, this.icone);

  final String libelle;
  final IconData icone;

  /// Vrai pour les deux actions qui **posent** quelqu'un sur le créneau.
  bool get pose =>
      this == ActionCandidat.attribuer || this == ActionCandidat.reattribuer;
}

/// Une ligne du panneau des candidats.
///
/// Même anatomie que la ligne de la liste des membres : un bloc de texte qui
/// prend la place, une cible de 48 dp à droite. Ce n'est pas une carte, et une
/// liste de blocs identiques n'est pas une structure de page
/// (`DESIGN.md § Cards / Containers`) : les lignes se séparent par le filet.
///
/// **Trois faits sont toujours visibles avant le geste** : le nom, les quotas
/// du mois, et l'avertissement s'il y en a un. C'est ce qui permet à
/// l'attribution d'être un simple appui : le chef a déjà lu ce qu'elle coûte.
class LigneCandidat extends StatelessWidget {
  const LigneCandidat({
    required this.candidat,
    required this.action,
    required this.onAction,
    super.key,
    this.raison,
  });

  final Candidat candidat;
  final ActionCandidat action;

  /// `null` désactive l'action — et exige alors [raison].
  final VoidCallback? onAction;

  /// Pourquoi l'action est impossible. Affichée à côté du contrôle.
  final String? raison;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membre = candidat.membre;
    final quota = candidat.quotaAtteint;

    // Un membre au quota atteint est **grisé mais attribuable** : l'app
    // avertit, l'admin décide (`docs/PRD.md § 7.4`).
    final encreNom = quota
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;

    final mesures = AppStrings.planningCandidatMesures(
      astreintesRestantes: membre.astreintesRestantes,
      maxAstreintes: membre.maxAstreintes,
      astreintes: membre.astreintes,
      weekendsRestants: membre.weekendsRestants,
      maxWeekends: membre.maxWeekends,
      unitesWeekend: membre.unitesWeekend,
      accepteesPrecedentes: membre.accepteesPrecedentes,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.cible),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Semantics(
              label: membre.nomAffiche,
              value: <String>[
                mesures,
                if (quota) _libelleQuota,
                if (!candidat.estDisponible && !candidat.estAttribue)
                  context.statuts.disponibilite(candidat.disponibilite).libelle,
                if (membre.aUnCommentaire) membre.commentaire!,
              ].join(', '),
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      membre.nomAffiche,
                      style: AppTextStyles.corps.copyWith(color: encreNom),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      mesures,
                      style: AppTextStyles.mention.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: AppTextStyles.chiffresTabulaires,
                      ),
                    ),
                    if (membre.aUnCommentaire) ...<Widget>[
                      const SizedBox(height: AppSpacing.xxs),
                      _Commentaire(texte: membre.commentaire!),
                    ],
                    if (_marqueurs(context).isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: _marqueurs(context),
                      ),
                    ],
                    if (raison != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        raison!,
                        style: AppTextStyles.mention.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.entreCibles),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            // **L'étiquette nomme la personne**, pas seulement l'action : au
            // lecteur d'écran, douze boutons « Réattribuer » à la suite ne
            // disent rien de ce qu'on choisit. Elle passe par le texte du
            // bouton et non par un `Semantics` englobant, qui effacerait
            // l'action du nœud avec `excludeSemantics`.
            child: TextButton.icon(
              onPressed: onAction,
              icon: Icon(action.icone, size: AppTouch.icone),
              label: Text(
                action.libelle,
                semanticsLabel: '${action.libelle} ${membre.nomAffiche}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _libelleQuota => candidat.quotaDepasse
      ? AppStrings.planningQuotaDepasse
      : AppStrings.planningQuotaAtteint;

  /// Les marqueurs d'état : le quota atteint, et la disponibilité quand elle
  /// n'est pas acquise. Jamais de marqueur « disponible » : l'absence de
  /// marqueur **est** l'état normal de cette liste.
  List<Widget> _marqueurs(BuildContext context) => <Widget>[
    if (candidat.quotaAtteint)
      StatusBadge.attribution(
        AttributionEtat.propose,
        taille: StatusBadgeTaille.compacte,
        libelle: _libelleQuota,
      ),
    if (!candidat.estDisponible)
      StatusBadge.disponibilite(
        candidat.disponibilite,
        taille: StatusBadgeTaille.compacte,
      ),
  ];
}

/// Le commentaire du mois, **en clair et non derrière une icône** : c'est la
/// moitié utile d'une décision, et c'est ici qu'elle sert le plus.
class _Commentaire extends StatelessWidget {
  const _Commentaire({required this.texte});

  final String texte;

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
          child: Text(
            texte,
            style: AppTextStyles.mention.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
