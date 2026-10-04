import 'package:flutter/material.dart';

/// **« Astreinte ailleurs »**, la marque d'une case (ticket 072,
/// `design/072 § 6.7`) : un coin rabattu dans l'angle haut droit.
///
/// **Une forme, pas une teinte.** Le triangle plein, à l'encre du texte, se lit
/// en niveaux de gris sur les trois états de disponibilité et sur les trois
/// états d'attribution ; il ne touche pas le glyphe central, qui reste le
/// premier signal de l'état. Un liseré de la couleur du papier le détache de
/// l'indigo plein et de l'orange. Pas de hachures (réservées à « absent » et
/// « verrouillé »), pas de rose (ni refus ni erreur), pas d'orange (pas une
/// attente de la caserne ouverte).
///
/// Décoratif pour les lecteurs d'écran : la case dit la même chose en mots.
class CoinAilleurs extends StatelessWidget {
  const CoinAilleurs({required this.cote, super.key, this.fond});

  /// Le côté du triangle : 8 en densité dense (case de 28), 12 au-delà.
  final double cote;

  /// Le fond de la case. L'encre du coin est celle du texte (`on-surface`),
  /// **sauf** quand ce fond est plus proche d'elle que du papier — l'orange
  /// d'une proposition en thème sombre ne laisse que 1,8:1 à l'encre claire.
  /// Le coin prend alors l'encre du papier, et le liseré l'autre : il reste à
  /// 3:1 au moins sur les six états, dans les deux thèmes.
  final Color? fond;

  /// L'encre la plus lisible sur [fond], entre l'encre du texte et le papier.
  static (Color encre, Color lisere) encres(ColorScheme scheme, Color? fond) {
    final texte = scheme.onSurface;
    final papier = scheme.surface;
    if (fond == null) return (texte, papier);
    return ratio(texte, fond) >= ratio(papier, fond)
        ? (texte, papier)
        : (papier, texte);
  }

  /// Rapport de contraste WCAG entre deux couleurs opaques.
  static double ratio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final claire = la > lb ? la : lb;
    final sombre = la > lb ? lb : la;
    return (claire + 0.05) / (sombre + 0.05);
  }

  /// Le côté pour une case de [taille].
  static double pourCase(double taille) => taille <= 28 ? 8 : 12;

  @override
  Widget build(BuildContext context) {
    final (encre, lisere) = encres(Theme.of(context).colorScheme, fond);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(cote),
          painter: PeintureCoinAilleurs(encre: encre, lisere: lisere),
        ),
      ),
    );
  }
}

/// La peinture du coin, publique pour le test de contraste.
class PeintureCoinAilleurs extends CustomPainter {
  const PeintureCoinAilleurs({required this.encre, required this.lisere});

  final Color encre;
  final Color lisere;

  @override
  void paint(Canvas canvas, Size size) {
    final triangle = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas
      ..drawPath(triangle, Paint()..color = encre)
      // Le liseré suit l'hypoténuse seulement : les deux autres côtés sont
      // ceux de la case, déjà bordée.
      ..drawLine(
        Offset.zero,
        Offset(size.width, size.height),
        Paint()
          ..color = lisere
          ..strokeWidth = 1,
      );
  }

  @override
  bool shouldRepaint(PeintureCoinAilleurs ancienne) =>
      ancienne.encre != encre || ancienne.lisere != lisere;
}
