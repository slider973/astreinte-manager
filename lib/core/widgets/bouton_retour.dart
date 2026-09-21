import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_strings.dart';
import '../router/app_router.dart';
import '../theme/app_spacing.dart';

/// La sortie d'un écran qui ne porte **ni ossature de navigation, ni parent
/// dans le routeur**.
///
/// La cause de structure, nommée pour qu'elle ne revienne pas : un écran
/// atteint par une navigation depuis un autre écran, déclaré au premier niveau
/// et sans barre de navigation, n'a par construction aucune sortie. Sur un
/// ordinateur le bouton précédent du navigateur sauve la mise ; dans une PWA
/// installée en plein écran il n'y a pas de barre d'adresse, et la personne est
/// enfermée (ticket 052). **La règle : un tel écran s'ouvre par `push` et porte
/// ce bouton.**
///
/// Deux formes, une seule règle, et la même place dans les deux cas — ce qui
/// change est le mot, pas le repère :
///
/// - il y a une pile à dépiler : la flèche seule, `Retour` annoncé ;
/// - il n'y en a pas — lien profond application fermée, URL collée,
///   rechargement de la PWA, onglet restauré par le navigateur : la flèche
///   **suivie du mot « Accueil »**, et elle mène à l'accueil. La pile vide
///   n'est pas un cas rare, c'est le deuxième état nominal.
///
/// Aucune couleur ne porte la différence entre les deux états : c'est du
/// texte, lisible en niveaux de gris.
class BoutonRetour extends StatelessWidget {
  const BoutonRetour({super.key, this.repli = AppRoutes.accueilName});

  /// Où mener quand il n'y a rien à dépiler.
  ///
  /// **Un seul repli dans ce produit**, l'accueil : la cloche et les pages
  /// légales n'existent que sur les écrans de membre, et un admin est d'abord
  /// un pompier. Pas de branche par rôle (`design/052 § 5`).
  final String repli;

  /// La largeur de `leading` par défaut de Material : la flèche seule.
  static const double _largeurFleche = 56;

  /// La part de la largeur d'écran que la sortie ne dépasse jamais. Au-delà —
  /// échelle de texte à 200 % sur un téléphone étroit — le mot tombe et la
  /// flèche reste : **la sortie ne disparaît jamais, son commentaire peut.**
  static const double _partMaximale = 0.45;

  /// La taille d'icône d'une barre d'application Material, dans les deux
  /// formes : le mot apparaît à côté de la flèche, il ne la rapetisse pas.
  static const double _tailleFleche = 24;

  /// Ce qu'il faut donner à `AppBar.leadingWidth` sur l'écran qui porte ce
  /// bouton. Le calcul est le même que celui de [build], donc les deux ne
  /// peuvent pas diverger.
  static double largeur(BuildContext context) => _mesurer(context).largeur;

  static _FormeRetour _mesurer(BuildContext context) {
    if (context.canPop()) {
      return const _FormeRetour(mot: false, largeur: _largeurFleche);
    }

    // Le mot est mesuré avec le style et l'échelle de texte réels : à 200 %,
    // « Accueil » ne tient plus sur un téléphone étroit, et il vaut mieux le
    // savoir avant de réserver la place que de laisser déborder la barre.
    final peintre = TextPainter(
      text: TextSpan(
        text: AppStrings.retourAccueil,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final souhaitee =
        (AppSpacing.md * 2 +
                _tailleFleche +
                AppSpacing.sm +
                peintre.width)
            .ceilToDouble();
    peintre.dispose();

    return souhaitee <= MediaQuery.sizeOf(context).width * _partMaximale
        ? _FormeRetour(mot: true, largeur: souhaitee)
        : const _FormeRetour(mot: false, largeur: _largeurFleche);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final forme = _mesurer(context);
    final peutDepiler = context.canPop();

    // Un seul cran d'historique consommé, exactement comme le bouton précédent
    // du navigateur et le geste retour iOS : les trois passent par la même
    // pile. Rien à confirmer avant de sortir — le marquage des notifications
    // est optimiste et déjà parti — donc ni `onExit` ni `PopScope`.
    void sortir() {
      if (peutDepiler) {
        context.pop();
      } else {
        context.goNamed(repli);
      }
    }

    // L'encre de la barre, jamais une couleur à soi : c'est un élément de
    // barre d'application, pas un bouton posé dedans.
    final encre =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;

    if (!forme.mot) {
      // `BackButton` conviendrait, à un détail près : son libellé annoncé
      // vient de `MaterialLocalizations`, que cette application ne configure
      // pas — il dirait « Back ». Les textes du produit vivent dans
      // `AppStrings`, celui-là comme les autres.
      return IconButton(
        onPressed: sortir,
        color: encre,
        tooltip: peutDepiler
            ? AppStrings.actionRetour
            : AppStrings.retourAccueilSemantique,
        icon: const Icon(Icons.arrow_back, size: _tailleFleche),
      );
    }

    return TextButton.icon(
      onPressed: sortir,
      style: TextButton.styleFrom(
        foregroundColor: encre,
        iconSize: _tailleFleche,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
      icon: const Icon(Icons.arrow_back),
      // Le mot lu est « Accueil », le mot annoncé est « Aller à l'accueil » :
      // un lecteur d'écran nomme l'action, l'œil n'a besoin que de la
      // destination.
      label: const Text(
        AppStrings.retourAccueil,
        semanticsLabel: AppStrings.retourAccueilSemantique,
      ),
    );
  }
}

/// La forme retenue et la place qu'elle demande, décidées ensemble.
@immutable
class _FormeRetour {
  const _FormeRetour({required this.mot, required this.largeur});

  /// Le mot « Accueil » accompagne la flèche.
  final bool mot;

  /// Ce que vaut `AppBar.leadingWidth`.
  final double largeur;
}
