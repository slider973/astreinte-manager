import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../domain/tableau_bord.dart';

/// La bande de semaine à points (`design/064 § 2`).
///
/// Sept jours, la lettre du jour au-dessus de son numéro, le jour courant en
/// pastille `primaryContainer`, et sous chaque jour jusqu'à deux points de 6 :
/// indigo pour une astreinte acceptée, orange pour une proposition en attente.
///
/// **Les points ne sont jamais la seule marque.** Un point de 6 points ne se
/// lit ni au soleil ni avec des gants, et il ne s'entend pas du tout : chaque
/// jour porte sa phrase complète dans la sémantique — « mar. 24, astreinte
/// acceptée, proposition à répondre » — et la rangée de cartes au-dessus dit
/// la même chose en toutes lettres. La bande est un repère de balayage, pas un
/// porteur d'information unique.
///
/// Elle ne commande rien : ni `InkWell`, ni `button` dans la sémantique. La
/// bande du 061b avait été retirée précisément parce qu'elle déplaçait le
/// contenu sous le pointeur (`DESIGN.md § Écarts, ticket 061c`).
class BandeSemaine extends StatelessWidget {
  const BandeSemaine({required this.jours, super.key});

  /// Diamètre d'un point.
  static const double point = 6;

  /// Côté de la pastille du jour courant. Au-dessus du plancher tactile : la
  /// bande ne se touche pas, mais elle se lit, et une pastille plus petite
  /// serrerait le numéro contre son bord.
  static const double pastille = 36;

  final List<PointJour> jours;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: <Widget>[
      for (final jour in jours) Flexible(child: _Jour(jour: jour)),
    ],
  );
}

class _Jour extends StatelessWidget {
  const _Jour({required this.jour});

  final PointJour jour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statuts = context.statuts;

    final encre = jour.aujourdhui
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return Semantics(
      label: AppStrings.accueilJourSemantique(
        date: '${nomJourCourt(jour.jour)} ${jour.jour.day}',
        aujourdhui: jour.aujourdhui,
        astreinte: jour.astreinte,
        proposition: jour.proposition,
      ),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              // La première lettre du jour, majuscule : « L M M J V S D ».
              nomJourCourt(jour.jour).characters.first.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 1,
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              width: BandeSemaine.pastille,
              height: BandeSemaine.pastille,
              alignment: Alignment.center,
              decoration: jour.aujourdhui
                  ? BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: AppRadius.pastilleRadius,
                    )
                  : null,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${jour.jour.day}',
                  style: theme.textTheme.labelLarge?.copyWith(color: encre),
                  maxLines: 1,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: BandeSemaine.point,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (jour.astreinte)
                    _Point(couleur: scheme.primary)
                  else if (!jour.proposition)
                    const SizedBox.shrink(),
                  if (jour.astreinte && jour.proposition)
                    const SizedBox(width: AppSpacing.xs),
                  if (jour.proposition)
                    _Point(
                      couleur: statuts
                          .attribution(AttributionEtat.propose)
                          .blocFond,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.couleur});

  final Color couleur;

  @override
  Widget build(BuildContext context) => Container(
    width: BandeSemaine.point,
    height: BandeSemaine.point,
    decoration: BoxDecoration(
      color: couleur,
      borderRadius: AppRadius.pastilleRadius,
    ),
  );
}
