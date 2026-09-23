import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/l10n/jours_feries.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import 'fond_jour.dart';
import 'geometrie_matrice.dart';

/// L'en-tête des dates, deux niveaux, 60 px.
///
/// Niveau 1, sur les deux colonnes de la journée : **la pastille du jour** —
/// l'abréviation du jour au-dessus de son numéro, en indigo pâle quand c'est
/// aujourd'hui. C'est la forme que le chantier 061b avait donnée à la bande
/// de semaine ; au 061c elle revient ici, et la bande disparaît. La référence
/// du brief n'a qu'une rangée de dates, et c'est l'en-tête de sa grille.
///
/// Niveau 2, une par colonne : `light_mode` et `bedtime`. **C'est le seul
/// endroit où les icônes de créneau sont écrites** — soixante-deux petits
/// soleils répétés dans la grille seraient du bruit, exactement comme au
/// ticket 011.
///
/// **L'en-tête ne se touche pas.** Il nomme les colonnes, il ne les commande
/// pas : ni `InkWell`, ni `button` dans la sémantique. Le seul geste que la
/// bande apportait — amener une colonne au bord gauche — déplaçait le contenu
/// sous le pointeur, ce qu'une grille qu'on lit en diagonale ne pardonne pas.
class EnteteJour extends StatelessWidget {
  const EnteteJour({required this.date, required this.aujourdhui, super.key});

  final DateTime date;
  final DateTime aujourdhui;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ferie = nomJourFerie(date);
    // Le weekend et les fériés portent déjà leur fond `surface-dim` sur toute
    // la colonne (`FondJour`) : l'en-tête n'y ajoute que la graisse.
    final marque = FondJour.marque(date);
    final courant = _estAujourdhui;

    final encre = courant ? scheme.onPrimaryContainer : scheme.onSurface;
    final encreSoutien = courant
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    final libelle = <String>[
      dateAvecJourSemaine(date),
      if (ferie != null) AppStrings.jourFerieNomme(ferie),
      if (courant) AppStrings.jourAujourdhui,
    ].join(', ');

    final entete = Semantics(
      label: libelle,
      excludeSemantics: true,
      child: SizedBox(
        height: GeoMatrice.hauteurEntete,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // La pastille d'aujourd'hui **couvre les deux créneaux** de la
            // journée : le jour courant est une colonne entière, pas une
            // moitié de colonne.
            DecoratedBox(
              decoration: BoxDecoration(
                color: courant ? scheme.primaryContainer : Colors.transparent,
                borderRadius: AppRadius.controleRadius,
              ),
              child: SizedBox(
                width: GeoMatrice.largeurPastille,
                height: GeoMatrice.hauteurPastille,
                // Les deux lignes se réduisent jusqu'à la pastille plutôt que
                // de la déborder : à grande échelle de texte, une date un peu
                // plus dense vaut mieux qu'un numéro coupé.
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (ferie != null) ...<Widget>[
                              Icon(
                                Icons.star,
                                size: 12,
                                color: courant
                                    ? scheme.onPrimaryContainer
                                    : scheme.tertiary,
                              ),
                              const SizedBox(width: AppSpacing.xxs),
                            ],
                            Text(
                              AppStrings.grilleJoursCourts[date.weekday - 1],
                              style: AppTextStyles.etiquette.copyWith(
                                color: encreSoutien,
                                // Le weekend se dit aussi par la graisse, pas
                                // seulement par le fond : jamais la couleur
                                // seule.
                                fontWeight: marque
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${date.day}',
                          style: AppTextStyles.nombrePetit.copyWith(
                            color: encre,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: <Widget>[
                _IconeCreneau(
                  creneau: CreneauType.jour,
                  encre: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: GeoMatrice.ecartCreneaux),
                _IconeCreneau(
                  creneau: CreneauType.nuit,
                  encre: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // Le nom du férié se lit au survol **et** s'annonce : une info-bulle seule
    // serait un accès par le survol, ce que le système interdit.
    return ferie == null
        ? entete
        : Tooltip(message: AppStrings.jourFerieNomme(ferie), child: entete);
  }

  bool get _estAujourdhui =>
      date.year == aujourdhui.year &&
      date.month == aujourdhui.month &&
      date.day == aujourdhui.day;
}

class _IconeCreneau extends StatelessWidget {
  const _IconeCreneau({required this.creneau, required this.encre});

  final CreneauType creneau;
  final Color encre;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: GeoMatrice.colonne,
    child: Icon(
      context.statuts.creneau(creneau).icone,
      size: AppTouch.iconePetite,
      color: encre,
    ),
  );
}

/// Le coin figé : là où l'en-tête des dates croise la colonne des noms.
///
/// Il ne bouge pas du tout — ni horizontalement, ni verticalement. Il porte
/// les titres des trois zones de l'en-tête de ligne, et le libellé de la
/// ligne « Disponibles ».
class CoinFige extends StatelessWidget {
  const CoinFige({
    required this.largeur,
    required this.avecCreneaux,
    super.key,
  });

  final double largeur;

  /// Vrai quand la ligne des créneaux à pourvoir est affichée : le coin porte
  /// alors son libellé, à la même hauteur qu'elle.
  final bool avecCreneaux;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = AppTextStyles.etiquette.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return SizedBox(
      width: largeur,
      height: GeoMatrice.hauteurBlocEpingle(avecCreneaux: avecCreneaux),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: GeoMatrice.hauteurEntete,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Text(
                        AppStrings.matriceColonneMembre,
                        style: style,
                      ),
                    ),
                  ),
                  _Titre(
                    texte: AppStrings.matriceColonneAstreintes,
                    style: style,
                  ),
                  _Titre(
                    texte: AppStrings.matriceColonneWeekends,
                    style: style,
                  ),
                ],
              ),
            ),
            if (avecCreneaux)
              SizedBox(
                height: GeoMatrice.hauteurCreneaux,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(AppStrings.planningLigneCreneaux, style: style),
                ),
              ),
            SizedBox(
              height: GeoMatrice.hauteurDisponibles,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(AppStrings.matriceLigneDisponibles, style: style),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre({required this.texte, required this.style});

  final String texte;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: GeoMatrice.largeurQuota,
    child: Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(texte, style: style, textAlign: TextAlign.end),
    ),
  );
}
