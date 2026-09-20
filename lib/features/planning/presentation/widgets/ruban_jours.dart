import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'geometrie_matrice.dart';

/// La virtualisation **horizontale** de la matrice, en un seul objet.
///
/// Un ruban occupe toute la largeur du mois, mais ne construit que les
/// journées visibles : un espaceur en tête pose la fenêtre à sa place, et les
/// journées suivent. Le ruban ne se reconstruit qu'au **franchissement d'une
/// journée**, pas à chaque pixel de défilement — c'est ce que fait un
/// `ListView` dans son viewport, ici sans le viewport, parce que soixante
/// lignes partagent un seul défilement horizontal.
///
/// Sans cette fenêtre, une matrice de 60 × 62 construirait 3 720 cases au lieu
/// des ~1 100 réellement à l'écran (brief § 6.9, virtualisation obligatoire
/// sur les deux axes).
class RubanJours extends StatelessWidget {
  const RubanJours({
    required this.fenetre,
    required this.nombreDeJours,
    required this.joursVisibles,
    required this.construire,
    super.key,
  });

  /// L'index (base 0) de la première journée visible.
  final ValueListenable<int> fenetre;

  /// 28, 30 ou 31.
  final int nombreDeJours;

  /// Combien de journées tiennent dans la largeur visible, marge comprise.
  final int joursVisibles;

  /// Construit une journée. Le jour est **en base 1** : c'est celui du
  /// calendrier, pas un index de chaîne.
  final Widget Function(BuildContext context, int jour) construire;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: GeoMatrice.largeurTotale(nombreDeJours),
      child: ValueListenableBuilder<int>(
        valueListenable: fenetre,
        builder: (BuildContext context, int premier, Widget? _) {
          final debut = premier
              .clamp(0, math.max(0, nombreDeJours - 1))
              .toInt();
          final fin = math.min(nombreDeJours, debut + joursVisibles);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (debut > 0) SizedBox(width: debut * GeoMatrice.largeurJour),
              for (var jour = debut + 1; jour <= fin; jour++)
                construire(context, jour),
            ],
          );
        },
      ),
    );
  }
}
