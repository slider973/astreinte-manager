import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';

/// L'en-tête de colonnes, **épinglé**.
///
/// Épinglé parce que c'est lui qui dit, à tout moment de la peinture, quelle
/// colonne est la nuit. En orientation registre, l'icône du créneau ne vit
/// nulle part ailleurs : soixante-deux petits soleils et lunes répétés dans
/// les cases seraient du bruit (brief 011 § 6.5).
class EnteteColonnes extends SliverPersistentHeaderDelegate {
  const EnteteColonnes({required this.calendrier, required this.hauteur});

  /// Vrai pour la vue calendaire : `L M M J V S D`.
  final bool calendrier;

  final double hauteur;

  @override
  double get minExtent => hauteur;

  @override
  double get maxExtent => hauteur;

  @override
  bool shouldRebuild(EnteteColonnes ancien) =>
      ancien.calendrier != calendrier || ancien.hauteur != hauteur;

  @override
  Widget build(
    BuildContext context,
    double decalage,
    bool chevauchementDuContenu,
  ) {
    final theme = Theme.of(context);

    // `layoutChild` donne au délégué une hauteur **lâche** : sans hauteur
    // imposée ici, l'en-tête se dimensionne sur son texte et le sliver rend
    // une géométrie invalide (`layoutExtent` supérieur à `paintExtent`).
    return SizedBox(
      height: hauteur,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          border: Border(
            bottom: BorderSide(color: context.statuts.filetDecoratif),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Center(
            child: calendrier
                ? const _EnteteCalendrier()
                : const _EnteteRegistre(),
          ),
        ),
      ),
    );
  }
}

class _EnteteRegistre extends StatelessWidget {
  const _EnteteRegistre();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(child: _Titre(libelle: AppStrings.grilleColonneDate)),
        const SizedBox(width: AppSpacing.entreCibles),
        Expanded(
          child: _Titre(
            libelle: AppStrings.creneauJour,
            icone: context.statuts.creneau(CreneauType.jour).icone,
          ),
        ),
        const SizedBox(width: AppSpacing.entreCibles),
        Expanded(
          child: _Titre(
            libelle: AppStrings.creneauNuit,
            icone: context.statuts.creneau(CreneauType.nuit).icone,
          ),
        ),
      ],
    );
  }
}

class _EnteteCalendrier extends StatelessWidget {
  const _EnteteCalendrier();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (var index = 0; index < 7; index++)
          Expanded(
            child: Semantics(
              label: AppStrings.grilleJoursLongs[index],
              excludeSemantics: true,
              child: _Titre(
                libelle: AppStrings.grilleJoursInitiales[index],
                // Samedi et dimanche en gras : le weekend se voit avant de se
                // lire, même à la largeur d'une initiale.
                accentue: index >= 5,
                centre: true,
              ),
            ),
          ),
      ],
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre({
    required this.libelle,
    this.icone,
    this.accentue = false,
    this.centre = false,
  });

  final String libelle;
  final IconData? icone;
  final bool accentue;
  final bool centre;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = AppTextStyles.etiquette.copyWith(
      color: accentue
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurfaceVariant,
    );

    return Row(
      mainAxisAlignment: centre
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: <Widget>[
        if (icone != null) ...<Widget>[
          Icon(
            icone,
            size: AppTouch.iconePetite,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        Flexible(
          child: Text(libelle, style: style, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
