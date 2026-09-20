import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/notification_interne.dart';

/// Une ligne du registre des notifications.
///
/// Pas une carte (`DESIGN.md § Don't`) : une ligne réglée, séparée de la
/// suivante par le filet de l'`AppDivider` que pose la liste.
///
/// **Une non-lue porte quatre signaux avant la couleur** (`design/026 § 1`) :
/// une marque carrée pleine, un titre en graisse 600, un fond plus dense, et
/// le mot « Non lue » en tête du libellé annoncé. La ligne reste lisible
/// photocopiée en noir et blanc — c'est le test de la direction.
class LigneNotification extends StatelessWidget {
  const LigneNotification({
    required this.notification,
    required this.onTouche,
    super.key,
    this.maintenant,
  });

  final NotificationInterne notification;
  final VoidCallback onTouche;

  /// L'horloge, injectée par les tests pour que « il y a 2 h » soit stable.
  final DateTime? maintenant;

  /// La largeur de la colonne de gauche : la marque, puis l'espace qu'elle
  /// occupe quand elle est absente. Réservé dans les deux cas, sinon les
  /// titres des lignes lues et non lues ne s'alignent plus.
  static const double largeurMarque = AppSpacing.lg;

  /// Le côté du carré de non-lue.
  static const double coteMarque = 10;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sombre = theme.brightness == Brightness.dark;
    final lue = notification.lue;

    final titre = notification.titre.isEmpty
        ? AppStrings.centreSansTitre
        : notification.titre;
    final date = formaterInstantRelatif(
      notification.creeLe,
      maintenant: maintenant,
    );

    // Le libellé annoncé porte tout ce que l'œil lit d'un coup : l'état, le
    // titre, le corps, l'ancienneté. Un lecteur d'écran ne doit pas avoir à
    // parcourir quatre nœuds pour reconstituer une ligne.
    final annonce = <String>[
      if (!lue) AppStrings.centreNonLue,
      titre,
      if (notification.corps.isNotEmpty) notification.corps,
      if (notification.enEchec) AppStrings.centreEnvoiEchoue,
      date,
    ].join('. ');

    return Semantics(
      button: true,
      label: annonce,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTouche,
          child: Ink(
            color: lue
                ? theme.colorScheme.surface
                : theme.colorScheme.surfaceContainerLow,
            child: ConstrainedBox(
              // Deux lignes de corps à l'échelle 1 tiennent largement ; la
              // contrainte est là pour la cible tactile, pas pour la hauteur.
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _Marque(
                      visible: !lue,
                      couleur: sombre
                          ? AppColors.darkEtatInfo
                          : AppColors.etatInfo,
                    ),
                    Icon(
                      notification.type.icone,
                      size: AppTouch.glypheConfortable,
                      color: lue
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _Texte(
                        titre: titre,
                        corps: notification.corps,
                        echec: notification.enEchec,
                        lue: lue,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _Date(texte: date, lue: lue),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le carré de non-lue. Le carré du registre, pas une pastille : le rayon
/// `pastille` est réservé aux compteurs (`DESIGN.md § Rayons`).
class _Marque extends StatelessWidget {
  const _Marque({required this.visible, required this.couleur});

  final bool visible;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: LigneNotification.largeurMarque,
      // Aligné sur la première ligne de texte, pas sur le haut du bloc.
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs + 1),
        child: visible
            ? Container(
                width: LigneNotification.coteMarque,
                height: LigneNotification.coteMarque,
                decoration: BoxDecoration(
                  color: couleur,
                  borderRadius: AppRadius.caseRegistreRadius,
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _Texte extends StatelessWidget {
  const _Texte({
    required this.titre,
    required this.corps,
    required this.echec,
    required this.lue,
  });

  final String titre;
  final String corps;
  final bool echec;
  final bool lue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rouge = theme.brightness == Brightness.dark
        ? AppColors.darkEtatAbsent
        : AppColors.etatAbsent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          titre,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: lue ? FontWeight.w400 : FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (corps.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            corps,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (echec) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.error_outline,
                size: AppTouch.iconePetite,
                color: rouge,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  AppStrings.centreEnvoiEchoue,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: rouge,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// L'ancienneté, en marge droite comme la date d'un registre.
class _Date extends StatelessWidget {
  const _Date({required this.texte, required this.lue});

  final String texte;
  final bool lue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Text(
        texte,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: lue ? FontWeight.w400 : FontWeight.w600,
        ),
      ),
    );
  }
}
