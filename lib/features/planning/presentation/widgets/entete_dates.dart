import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/l10n/jours_feries.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import 'fond_jour.dart';
import 'geometrie_matrice.dart';

/// L'en-tête des dates, deux niveaux, 56 px.
///
/// Niveau 1, sur les deux colonnes de la journée : la lettre du jour puis son
/// numéro. Niveau 2, une par colonne : `light_mode` et `bedtime`. **C'est le
/// seul endroit où les icônes de créneau sont écrites** — soixante-deux
/// petits soleils répétés dans la grille seraient du bruit, exactement comme
/// au ticket 011.
class EnteteJour extends StatelessWidget {
  const EnteteJour({required this.date, required this.aujourdhui, super.key});

  final DateTime date;
  final DateTime aujourdhui;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ferie = nomJourFerie(date);
    final marque = FondJour.marque(date);

    final encre = theme.colorScheme.onSurfaceVariant;
    final libelle = <String>[
      dateAvecJourSemaine(date),
      if (ferie != null) AppStrings.jourFerieNomme(ferie),
      if (_estAujourdhui) AppStrings.jourAujourdhui,
    ].join(', ');

    final entete = Semantics(
      label: libelle,
      excludeSemantics: true,
      child: SizedBox(
        height: GeoMatrice.hauteurEntete,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (ferie != null) ...<Widget>[
                  Icon(Icons.star, size: 12, color: theme.colorScheme.tertiary),
                  const SizedBox(width: AppSpacing.xxs),
                ],
                Text(
                  AppStrings.grilleJoursInitiales[date.weekday - 1],
                  style: AppTextStyles.etiquette.copyWith(
                    color: encre,
                    // Le weekend se dit aussi par la graisse, pas seulement
                    // par le fond : jamais la couleur seule.
                    fontWeight: marque ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
            Text(
              '${date.day}',
              style: AppTextStyles.nombrePetit.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: <Widget>[
                _IconeCreneau(creneau: CreneauType.jour, encre: encre),
                const SizedBox(width: GeoMatrice.ecartCreneaux),
                _IconeCreneau(creneau: CreneauType.nuit, encre: encre),
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
  const CoinFige({required this.largeur, super.key});

  final double largeur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = AppTextStyles.etiquette.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return SizedBox(
      width: largeur,
      height: GeoMatrice.hauteurBlocEpingle,
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
