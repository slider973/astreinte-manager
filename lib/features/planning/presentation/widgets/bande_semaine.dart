import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/l10n/jours_feries.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// **La bande de semaine** : le mois en une ligne de pastilles.
///
/// Elle sert à se déplacer, pas à lire un état : toucher un jour amène sa
/// colonne dans la matrice, qui fait deux mille pixels de large. Sans elle,
/// atteindre le 28 est une découverte par accident (`design/061 § 5`).
///
/// Trois repères, les mêmes que dans l'en-tête des dates de la matrice, pour
/// qu'on ne réapprenne rien d'un bandeau à l'autre : le jour courant en
/// pastille indigo, le weekend et les fériés d'un cran de surface plus
/// sombre **et** en gras, le reste nu.
///
/// Un quatrième s'y ajoute, qui ne dit pas une date mais un geste : le
/// **jour visé**, celui qu'on vient de toucher et que la matrice a amené sous
/// l'œil. Sans lui, la grille bougeait et la bande restait identique — on
/// perdait de vue ce qu'on venait de demander. Il se porte en liseré et en
/// `selected`, jamais par la couleur seule, et il coexiste avec la pastille
/// d'aujourd'hui : les deux peuvent tomber sur le même jour.
class BandeSemaine extends StatelessWidget {
  const BandeSemaine({
    required this.annee,
    required this.mois,
    required this.nombreDeJours,
    required this.aujourdhui,
    required this.onJour,
    super.key,
    this.jourVise,
  });

  /// Côté d'une pastille. Au-dessus du plancher tactile, même si la bande
  /// n'est servie qu'au pointeur : une cible de 28 px ne se vise pas avec des
  /// gants, et rien n'interdit une tablette.
  static const double cote = AppTouch.cible;

  /// Le pas d'une pastille : son côté, plus l'écart entre deux cibles.
  static const double pas = cote + AppSpacing.entreCibles;

  /// La hauteur de la bande : la pastille et ses marges.
  static const double hauteur = cote + AppSpacing.xl;

  final int annee;

  /// Le mois affiché, en base 1.
  final int mois;

  final int nombreDeJours;
  final DateTime aujourdhui;

  /// Le jour que la matrice montre parce qu'on l'a demandé, en base 1, ou
  /// `null` — au premier affichage, ou quand la grille a défilé ailleurs.
  final int? jourVise;

  /// Appelé avec le jour du mois, en base 1.
  final ValueChanged<int> onJour;

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;

    return SizedBox(
      height: hauteur,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: marge,
          vertical: AppSpacing.md,
        ),
        itemExtent: pas,
        itemCount: nombreDeJours,
        itemBuilder: (BuildContext context, int index) => _Pastille(
          date: DateTime(annee, mois, index + 1),
          aujourdhui: aujourdhui,
          vise: jourVise == index + 1,
          onJour: onJour,
        ),
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({
    required this.date,
    required this.aujourdhui,
    required this.vise,
    required this.onJour,
  });

  final DateTime date;
  final DateTime aujourdhui;

  /// Vrai pour le jour que la matrice montre sur demande.
  final bool vise;

  final ValueChanged<int> onJour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ferie = nomJourFerie(date);
    final marque = date.weekday >= DateTime.saturday || ferie != null;
    final courant =
        date.year == aujourdhui.year &&
        date.month == aujourdhui.month &&
        date.day == aujourdhui.day;

    final encre = courant ? scheme.onPrimaryContainer : scheme.onSurface;
    final fond = switch (0) {
      _ when courant => scheme.primaryContainer,
      _ when marque => scheme.surfaceContainer,
      _ => Colors.transparent,
    };

    final libelle = <String>[
      dateAvecJourSemaine(date),
      if (ferie != null) AppStrings.jourFerieNomme(ferie),
      if (courant) AppStrings.jourAujourdhui,
    ].join(', ');

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.entreCibles),
      child: Semantics(
        button: true,
        // **Le jour visé se dit aussi**, et pas seulement se voit : le liseré
        // le porte à l'œil, `selected` le porte à l'oreille. `null` et non
        // `false` sur les autres : tant que rien n'a été demandé, aucune
        // pastille n'a à s'annoncer « non sélectionnée » trente fois.
        selected: vise ? true : null,
        label: libelle,
        hint: AppStrings.bandeAllerAuJour,
        excludeSemantics: true,
        child: Material(
          color: fond,
          // Le liseré du jour visé **s'ajoute** au remplissage : un jour peut
          // être aujourd'hui et visé en même temps, et il le montre deux fois
          // plutôt que de choisir.
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.controleRadius,
            side: vise
                ? BorderSide(color: scheme.outline, width: AppStroke.etat)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: AppRadius.controleRadius,
            onTap: () => onJour(date.day),
            child: SizedBox(
              width: BandeSemaine.cote,
              height: BandeSemaine.cote,
              // Les deux lignes se réduisent jusqu'à la pastille plutôt que
              // de la déborder : à grande échelle de texte, une pastille un
              // peu plus dense vaut mieux qu'un numéro coupé — c'est la même
              // décision qu'au compteur du ticket 011.
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        AppStrings.grilleJoursCourts[date.weekday - 1],
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: courant ? encre : scheme.onSurfaceVariant,
                          // Le weekend se dit aussi par la graisse : jamais
                          // la couleur seule.
                          fontWeight: marque
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${date.day}',
                        style: AppTextStyles.nombrePetit.copyWith(color: encre),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
