import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// Squelette de chargement, **à la forme du contenu attendu**.
///
/// `DESIGN.md § Don't` : « pas de `CircularProgressIndicator` au milieu d'un
/// écran ». L'écran montre l'ossature de ce qui va arriver, pas une roue qui
/// ne dit rien.
///
/// Le balayage disparaît sous Reduce Motion : le squelette devient un aplat
/// statique (`DESIGN.md § Motion`, contrainte produit).
class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({
    required this.child,
    super.key,
    this.semanticsLabel = AppStrings.chargementSemantique,
  });

  /// L'ossature : une composition de [SkeletonLigne], [SkeletonBloc] ou
  /// [SkeletonGrilleMois].
  final Widget child;

  final String semanticsLabel;

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  // Créé dès initState, jamais paresseusement : un contrôleur instancié
  // pendant dispose() irait chercher son TickerMode dans un arbre déjà
  // démonté.
  late final AnimationController _controleur;

  @override
  void initState() {
    super.initState();
    _controleur = AnimationController(
      vsync: this,
      duration: AppDuration.balayage,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce Motion n'est pas connu avant d'avoir un MediaQuery : on démarre
    // (ou non) la boucle ici, et on la coupe si la préférence change.
    if (AppMotion.reduit(context)) {
      _controleur
        ..stop()
        ..value = 0;
    } else if (!_controleur.isAnimating) {
      unawaited(_controleur.repeat());
    }
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aplat = theme.colorScheme.surfaceContainerHigh;

    final contenu = DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.transparent),
      child: IconTheme.merge(
        data: IconThemeData(color: aplat),
        child: widget.child,
      ),
    );

    return Semantics(
      label: widget.semanticsLabel,
      liveRegion: true,
      container: true,
      excludeSemantics: true,
      child: ExcludeFocus(
        child: AppMotion.reduit(context)
            ? contenu
            : AnimatedBuilder(
                animation: _controleur,
                builder: (context, enfant) => ShaderMask(
                  blendMode: BlendMode.srcATop,
                  shaderCallback: (rect) => LinearGradient(
                    colors: <Color>[
                      aplat,
                      theme.colorScheme.surfaceContainerLow,
                      aplat,
                    ],
                    stops: _arretsBalayage(_controleur.value),
                  ).createShader(rect),
                  child: enfant,
                ),
                child: contenu,
              ),
      ),
    );
  }

  /// Le balayage parcourt la largeur d'un bord à l'autre, sans saut.
  static List<double> _arretsBalayage(double t) {
    final centre = t * 2 - 0.5;
    return <double>[
      (centre - 0.25).clamp(0.0, 1.0),
      centre.clamp(0.0, 1.0),
      (centre + 0.25).clamp(0.0, 1.0),
    ];
  }
}

/// Une ligne de texte en attente.
class SkeletonLigne extends StatelessWidget {
  const SkeletonLigne({
    super.key,
    this.largeur,
    this.hauteur = AppSpacing.lg,
  });

  /// `null` prend toute la largeur disponible.
  final double? largeur;
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: largeur,
      height: hauteur,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: AppRadius.caseRegistreRadius,
      ),
    );
  }
}

/// Un bloc réglé en attente : titre, deux lignes, filet.
class SkeletonBloc extends StatelessWidget {
  const SkeletonBloc({super.key, this.hauteur = 96});

  /// Hauteur **minimale** : le bloc grandit si l'échelle de texte grandit.
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(minHeight: hauteur),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: AppRadius.controleRadius,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SkeletonLigne(largeur: 140, hauteur: AppSpacing.xl - 4),
          SizedBox(height: AppSpacing.md),
          SkeletonLigne(),
          SizedBox(height: AppSpacing.sm),
          SkeletonLigne(largeur: 200),
        ],
      ),
    );
  }
}

/// La grille du mois en attente : 7 colonnes de cases, à la forme exacte de la
/// grille qui va s'afficher.
class SkeletonGrilleMois extends StatelessWidget {
  const SkeletonGrilleMois({super.key, this.jours = 31, this.colonnes = 7});

  final int jours;
  final int colonnes;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: jours,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: colonnes,
        mainAxisSpacing: AppSpacing.xs,
        crossAxisSpacing: AppSpacing.xs,
        childAspectRatio: 0.62,
      ),
      itemBuilder: (context, index) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: AppRadius.caseRegistreRadius,
        ),
      ),
    );
  }
}
