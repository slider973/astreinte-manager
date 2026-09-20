import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/day_cell.dart';
import '../../domain/periode_saisie.dart';
import 'ligne_jour.dart';

/// **La vue calendaire** : sept colonnes, du lundi au dimanche.
///
/// Elle ne revient qu'à partir de `expanded` (≥ 840 dp), où la largeur la
/// paie honnêtement : chaque colonne fait alors ~108 dp et chaque case
/// ~72 × 48 dp. En dessous, c'est le registre qui tient (brief 011 § 3).
///
/// Les jours des mois voisins complètent les semaines en `horsMois` :
/// atténués, inertes, traversés par la peinture sans effet.
class GrilleCalendrier extends StatelessWidget {
  const GrilleCalendrier({
    required this.periode,
    required this.aujourdhui,
    super.key,
  });

  /// Écart entre deux cases en vue calendaire (`DESIGN.md § Espacement`).
  static const double ecartCases = 6;

  final PeriodeSaisie periode;
  final DateTime aujourdhui;

  /// Les semaines du mois, chacune de sept jours, du lundi au dimanche.
  List<List<DateTime>> get semaines {
    final premier = periode.premierJour;
    // `weekday` vaut 1 le lundi : le décalage est direct.
    final debut = premier.subtract(Duration(days: premier.weekday - 1));
    final dernier = DateTime(
      periode.annee,
      periode.mois,
      periode.nombreDeJours,
    );
    final fin = dernier.add(Duration(days: 7 - dernier.weekday));

    final total = fin.difference(debut).inDays + 1;
    return <List<DateTime>>[
      for (var semaine = 0; semaine * 7 < total; semaine++)
        <DateTime>[
          for (var jour = 0; jour < 7; jour++)
            DateTime(debut.year, debut.month, debut.day + semaine * 7 + jour),
        ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final lignes = semaines;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: ecartCases),
      sliver: SliverList.builder(
        itemCount: lignes.length,
        // Les sept blocs d'une semaine s'alignent sur le plus haut : un
        // `stretch` seul demanderait une hauteur infinie dans un sliver.
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(top: ecartCases),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final date in lignes[index]) ...<Widget>[
                  Expanded(
                    child: JourDeGrille(
                      key: ValueKey<String>('cal-${date.month}-${date.day}'),
                      date: date,
                      orientation: DayCellOrientation.colonne,
                      horsMois: date.month != periode.mois,
                      aujourdhui: _memeJour(date, aujourdhui),
                    ),
                  ),
                  if (date != lignes[index].last)
                    const SizedBox(width: ecartCases),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _memeJour(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// La marge horizontale d'une vue calendaire bornée.
const double margeCalendrier = AppSpacing.pageMedium;
