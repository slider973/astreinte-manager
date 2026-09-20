import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
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
          : SliverFixedExtentList(itemExtent: hauteurLigne, delegate: delegue),
    );
  }
}

bool _memeJour(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
