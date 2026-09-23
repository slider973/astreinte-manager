import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/l10n/jours_feries.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/day_cell.dart';
import '../../domain/periode_saisie.dart';
import 'ligne_jour.dart';

/// **Le registre** : une ligne par jour, trois colonnes.
///
/// La composition de référence sur téléphone. Le mois est une seule liste
/// continue — jamais une pagination par semaine, jamais un détail à ouvrir —
/// et la peinture y devient verticale : « toutes mes nuits » est un seul
/// geste qui descend la colonne de droite.
class GrilleRegistre extends StatelessWidget {
  const GrilleRegistre({
    required this.periode,
    required this.aujourdhui,
    super.key,
    this.deuxNiveaux = false,
  });

  /// Hauteur d'une ligne : 48 dp de case plus 4 dp de part et d'autre.
  static const double hauteurLigne = 56;

  /// **La hauteur d'une ligne de jour férié suit l'échelle de texte**
  /// (chantier 064d).
  ///
  /// La colonne de date d'un jour férié porte **deux** rangs — le numéro et
  /// le nom du jour, puis le nom du férié en clair — là où les autres n'en
  /// ont qu'un. Les deux valent 36 points à l'échelle 1, et 57,6 à ×1,6 :
  /// dans une ligne de 56 dont 8 partent en rembourrage, la Toussaint
  /// débordait de dix points, vu à ×1,6 sur un téléphone de 390. La ligne
  /// prend donc ce qui lui manque, et elle seule.
  ///
  /// Au-delà de `MoisScreen.seuilDeuxNiveaux`, la question ne se pose plus :
  /// la ligne passe à deux niveaux et sa hauteur redevient libre.
  static double hauteurDeLigne(BuildContext context, DateTime date) {
    if (nomJourFerie(date) == null) return hauteurLigne;

    final echelle = MediaQuery.textScalerOf(context);
    // Arrondi **au point supérieur**, comme le moteur de texte arrondit la
    // hauteur d'une ligne : 28,8 se peint sur 29, et deux rangs calculés au
    // dixième laissaient la ligne déborder de quatre dixièmes de point.
    double rang(TextStyle style) =>
        (echelle.scale(style.fontSize!) * (style.height ?? 1)).ceilToDouble();

    return math.max(
      hauteurLigne,
      rang(AppTextStyles.nombrePetit) +
          rang(AppTextStyles.mention) +
          AppSpacing.xs * 2,
    );
  }

  final PeriodeSaisie periode;

  /// La date du jour, pour le filet d'encre en marge.
  final DateTime aujourdhui;

  /// À très grande échelle de texte, la ligne passe à deux niveaux et sa
  /// hauteur devient libre.
  final bool deuxNiveaux;

  @override
  Widget build(BuildContext context) {
    final jours = periode.jours;

    Widget construire(BuildContext context, int index) {
      final date = jours[index];
      return ReglureJour(
        date: date,
        premiere: index == 0,
        child: JourDeGrille(
          key: ValueKey<String>('jour-${date.day}'),
          date: date,
          orientation: DayCellOrientation.ligne,
          deuxNiveaux: deuxNiveaux,
          aujourdhui: _memeJour(date, aujourdhui),
        ),
      );
    }

    final delegue = SliverChildBuilderDelegate(
      construire,
      childCount: jours.length,
    );

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      sliver: deuxNiveaux
          ? SliverList(delegate: delegue)
          // Varié, et non fixe : seules les lignes de jour férié grandissent
          // avec le texte, et la virtualisation reste entière — c'est un
          // calcul par indice, pas une construction.
          : SliverVariedExtentList(
              itemExtentBuilder: (int index, _) =>
                  hauteurDeLigne(context, jours[index]),
              delegate: delegue,
            ),
    );
  }
}

bool _memeJour(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
