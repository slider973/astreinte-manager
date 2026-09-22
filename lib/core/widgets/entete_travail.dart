import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_spacing.dart';

/// L'en-tête de la zone de travail, sur grand écran (`design/061 § 5`).
///
/// Une ligne : le titre à gauche, les actions à droite. Il remplace la barre
/// d'application dès `expanded`, parce que la navigation n'est plus sous
/// l'écran mais à côté de lui : une barre pleine largeur au-dessus des deux
/// ferait un troisième bandeau pour redire le nom de l'endroit.
///
/// Pas de champ de recherche : celui de la référence n'a pas d'objet ici, le
/// filtre de membres vivant dans la barre de commande de la matrice
/// (`design/061 § 5`).
///
/// La hauteur n'est pas fixée : elle vient de ce que la ligne porte — une
/// cible tactile de 48 plus les deux marges de 8 font 64. Un en-tête qui
/// bornerait sa hauteur rognerait le titre à grande échelle de texte.
class EnTeteTravail extends StatelessWidget {
  const EnTeteTravail({
    required this.titre,
    super.key,
    this.actions = const <Widget>[],
  });

  /// Le nom de la caserne quand l'écran le connaît, son propre titre sinon.
  final String titre;

  /// Les actions de l'écran, puis la cloche et le compte.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: marge,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                titre,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          ...actions,
        ],
      ),
    );
  }
}
