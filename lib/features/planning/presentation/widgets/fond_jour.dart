import 'package:flutter/material.dart';

import '../../../../core/l10n/jours_feries.dart';
import '../../../../core/theme/app_spacing.dart';
import 'geometrie_matrice.dart';

/// Les quatre repères verticaux de la matrice, sans lesquels soixante-deux
/// colonnes sont une bouillie (brief § 6.3).
///
/// | Repère | Rendu |
/// |---|---|
/// | début de semaine | filet 2 dp `outline` à gauche de chaque lundi |
/// | weekend ou férié | fond `surface-dim` sur les deux colonnes |
/// | aujourd'hui | filet 2 dp `primary` à gauche de la colonne du jour |
///
/// Ils sont peints **par journée et par ligne** : chaque segment mis bout à
/// bout fait le trait continu du haut de l'en-tête au bas de la grille, sans
/// qu'aucun objet ne traverse la virtualisation.
///
/// Peints et non bordés : une `Border` gauche décalerait le contenu de 2 px
/// et les cases ne seraient plus en face de leur en-tête.
class FondJour extends StatelessWidget {
  const FondJour({
    required this.date,
    required this.aujourdhui,
    required this.child,
    super.key,
  });

  final DateTime date;
  final DateTime aujourdhui;
  final Widget child;

  /// Vrai un samedi, un dimanche ou un jour férié. Calculé côté application
  /// (`jours_feries.dart`), **jamais redemandé au serveur** : la parité avec
  /// les fonctions SQL de la migration 0017 est testée des deux côtés.
  static bool marque(DateTime date) =>
      date.weekday >= DateTime.saturday || estJourFerie(date);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memeJour =
        date.year == aujourdhui.year &&
        date.month == aujourdhui.month &&
        date.day == aujourdhui.day;

    return SizedBox(
      width: GeoMatrice.largeurJour,
      child: Padding(
        padding: const EdgeInsets.only(right: GeoMatrice.ecartJours),
        child: CustomPaint(
          painter: _PeintreJour(
            fond: marque(date) ? theme.colorScheme.surfaceDim : null,
            filet: switch (0) {
              // Le filet du jour courant est l'un des emplois de `primary`.
              _ when memeJour => theme.colorScheme.primary,
              _ when date.weekday == DateTime.monday =>
                theme.colorScheme.outline,
              _ => null,
            },
          ),
          child: child,
        ),
      ),
    );
  }
}

class _PeintreJour extends CustomPainter {
  const _PeintreJour({required this.fond, required this.filet});

  final Color? fond;
  final Color? filet;

  @override
  void paint(Canvas canvas, Size size) {
    final couleurFond = fond;
    if (couleurFond != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = couleurFond);
    }

    final couleurFilet = filet;
    if (couleurFilet == null) return;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, AppStroke.etat, size.height),
      Paint()..color = couleurFilet,
    );
  }

  @override
  bool shouldRepaint(_PeintreJour ancien) =>
      ancien.fond != fond || ancien.filet != filet;
}
