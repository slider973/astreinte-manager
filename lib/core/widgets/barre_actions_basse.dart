import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_spacing.dart';
import 'app_divider.dart';
import 'ecran_simple.dart';

/// La bande d'actions collée au bas d'un écran dont le contenu défile.
///
/// Elle existe parce que trois écrans — import, invitation, centre de
/// notifications — avaient recopié la même ossature à la main et l'avaient
/// recopiée incomplète : la zone sûre et la marge de page y étaient, la
/// colonne du corps non. Sur l'écran de 1280 points du chef de centre, deux
/// boutons de 1216 points flottaient sous une colonne de 720. Une barre
/// d'actions n'est pas une bande pleine largeur : c'est le pied de la colonne
/// qu'elle sert, et elle se borne comme elle, à [AppSpacing.colonneMax], après
/// la même marge de page.
///
/// Elle porte aussi la limite d'avec le contenu qui passe dessous. Le contenu
/// s'y faisait trancher net, sans rien pour dire où finissait la liste et où
/// commençait le bouton. `DESIGN.md § Elevation & Depth` range ce cas au
/// niveau 1 — « barre d'application quand le contenu défile dessous » — et
/// ce niveau se rend en surface tonale `surfaceContainerLow` et en filet de
/// 1 dp. **Pas d'ombre, pas de dégradé de fin de liste** : la profondeur n'est
/// pas le matériau de ce système, le filet l'est.
///
/// Le filet et la surface sont là en permanence, sans écouter le défilement :
/// partout où cette barre sert, le contenu peut passer dessous dès qu'il
/// grandit ou que l'échelle de texte monte, et une limite qui apparaît et
/// disparaît sous le pouce coûte plus qu'elle ne rapporte.
class BarreActionsBasse extends StatelessWidget {
  const BarreActionsBasse({
    required this.child,
    this.largeurMax = AppSpacing.colonneMax,
    super.key,
  });

  /// La largeur de la colonne dont cette barre est le pied.
  ///
  /// Par défaut celle d'un corps de liste, [AppSpacing.colonneMax]. Les écrans
  /// sans navigation lisent plus étroit — [EcranSimple.colonneLecture], 420
  /// points — et leur barre doit les suivre : une barre plus large que son
  /// corps est le même défaut que celui du ticket 048, d'un cran plus petit.
  final double largeurMax;

  /// Les actions : un bouton, ou une colonne de boutons empilés.
  ///
  /// Elles sont étirées à la largeur de la colonne, comme le corps étire la
  /// sienne.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;

    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AppDivider(),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.all(marge),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: largeurMax),
                  // La colonne étire ses enfants : un bouton d'action prend
                  // toute la largeur utile, jamais celle de son libellé.
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[child],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
