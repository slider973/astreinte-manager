import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/carte_douce.dart';
import '../../../../core/widgets/loading_skeleton.dart';

/// Le squelette de « Mes astreintes » : **à la forme du contenu attendu**,
/// jamais un indicateur circulaire au milieu de l'écran
/// (`DESIGN.md § Don't`).
///
/// Il n'apparaît que lorsqu'il n'y a **rien en cache** : dès qu'un instantané
/// local existe, c'est lui qu'on montre, et la requête part derrière
/// (`design/027 § 3`).
class SqueletteAstreintes extends StatelessWidget {
  const SqueletteAstreintes({super.key, this.lignes = 3});

  final int lignes;

  @override
  Widget build(BuildContext context) => LoadingSkeleton(
    child: SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // La bascule de vue, puis l'en-tête d'un mois, puis les lignes.
          const SkeletonLigne(hauteur: AppTouch.cible),
          const SizedBox(height: AppSpacing.xl),
          const SkeletonLigne(largeur: 200, hauteur: AppSpacing.xxl),
          const SizedBox(height: AppSpacing.sm),
          const SkeletonLigne(largeur: 110),
          const SizedBox(height: AppSpacing.lg),
          // La forme attendue depuis le chantier 064c : des **cartes**, le
          // carré d'initiale à gauche, la date et ses heures à droite.
          for (var ligne = 0; ligne < lignes; ligne++) ...<Widget>[
            const _CarteFantome(),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    ),
  );
}

/// Une ligne d'astreinte à venir : le filet de la carte, le carré du créneau,
/// la date et l'intervalle.
class _CarteFantome extends StatelessWidget {
  const _CarteFantome();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      borderRadius: AppRadius.carteRadius,
      border: Border.fromBorderSide(
        CarteDouce.filet(Theme.of(context).colorScheme),
      ),
    ),
    child: const Row(
      children: <Widget>[
        SkeletonLigne(largeur: 40, hauteur: 40),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SkeletonLigne(largeur: 190),
              SizedBox(height: AppSpacing.sm),
              SkeletonLigne(largeur: 120, hauteur: AppSpacing.md),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Le squelette du registre de la caserne : **à la forme d'une journée**, en-tête
/// de date puis deux créneaux nommés (`DESIGN.md § Don't` : jamais un indicateur
/// circulaire au milieu de l'écran).
///
/// Il n'apparaît que lorsqu'il n'y a **rien en cache pour ce mois-là** : dès
/// qu'un mois est gardé, c'est lui qu'on montre, et la requête part derrière.
class SquelettePlanningCaserne extends StatelessWidget {
  const SquelettePlanningCaserne({super.key, this.journees = 3});

  final int journees;

  @override
  Widget build(BuildContext context) => LoadingSkeleton(
    child: SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var journee = 0; journee < journees; journee++) ...<Widget>[
            const SkeletonLigne(largeur: 180, hauteur: AppSpacing.xl),
            const SizedBox(height: AppSpacing.lg),
            for (var creneau = 0; creneau < 2; creneau++) ...<Widget>[
              const Row(
                children: <Widget>[
                  SkeletonLigne(largeur: 72, hauteur: AppTouch.badgeCompact),
                  SizedBox(width: AppSpacing.sm),
                  SkeletonLigne(largeur: 110),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const SkeletonLigne(largeur: 210),
              const SizedBox(height: AppSpacing.lg),
            ],
          ],
        ],
      ),
    ),
  );
}
