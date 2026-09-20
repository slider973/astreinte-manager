import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Motif de hachures à 45°.
///
/// Ce n'est **pas un composant** mais une primitive de dessin, partagée par
/// `SlotChip` (état « absent », case verrouillée) et par `AppBanner`
/// (variantes `verrouille` et `lectureSeule`). Elle vit dans son propre
/// fichier pour qu'une bannière n'ait pas à importer une case.
///
/// `DESIGN.md § Shapes` : trait 1.5 dp, pas de 6 dp, opacité 28 % de l'encre
/// de l'état. Le motif n'est utilisé que pour « absent » et pour « mois
/// verrouillé », nulle part ailleurs — c'est ce qui le garde signifiant.
class HachuresPainter extends CustomPainter {
  const HachuresPainter({
    required this.encre,
    this.opacite = AppStroke.opaciteHachure,
    this.pas = AppStroke.pasHachure,
    this.epaisseur = AppStroke.hachure,
  });

  /// Encre de l'état hachuré. Le motif en reprend la teinte, atténuée.
  final Color encre;

  final double opacite;
  final double pas;
  final double epaisseur;

  @override
  void paint(Canvas canvas, Size size) {
    final trait = Paint()
      ..color = encre.withValues(alpha: opacite)
      ..strokeWidth = epaisseur
      ..strokeCap = StrokeCap.square;

    // Diagonales à 45° : on balaie de -hauteur à +largeur pour que le motif
    // couvre le rectangle entier, coins compris.
    for (var x = -size.height; x < size.width; x += pas) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        trait,
      );
    }
  }

  @override
  bool shouldRepaint(HachuresPainter oldDelegate) =>
      oldDelegate.encre != encre ||
      oldDelegate.opacite != opacite ||
      oldDelegate.pas != pas ||
      oldDelegate.epaisseur != epaisseur;
}

/// Surface hachurée, découpée au rayon demandé.
class Hachures extends StatelessWidget {
  const Hachures({
    required this.encre,
    super.key,
    this.borderRadius = BorderRadius.zero,
  });

  final Color encre;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: CustomPaint(
        painter: HachuresPainter(encre: encre),
        size: Size.infinite,
      ),
    );
  }
}
