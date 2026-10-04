import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../l10n/format_date.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status.dart';
import 'carre_creneau.dart';

/// Le sens d'une rangée de garde, du point de vue du lecteur.
enum SensGarde {
  /// « Tu donnes » : ce qu'on perd. `remove_circle_outline`.
  donne,

  /// « Tu prends » : ce qu'on gagne. `add_circle_outline`.
  prend,

  /// Un verbe libre, sans sens pour le lecteur (« Antoine C. cède », vu par
  /// l'administrateur). `swap_horiz`.
  neutre,
}

/// La rangée **verbe + carré + date + heures** d'une paire de gardes
/// (ticket 073, `design/073 § 3`).
///
/// C'est le moment focal du parcours : accepter un échange en croyant
/// accepter une cession est l'erreur qui coûte cher. Le sens se lit donc par
/// le **verbe en gras** et l'**icône de sens**, jamais par une flèche — le
/// glyphe « → » n'existe pas dans les coupes Atkinson — ni par la couleur.
///
/// Une phrase sémantique complète : « Tu donnes : mardi 15 octobre, jour, de
/// 07:00 à 19:00 ».
class RangeeGarde extends StatelessWidget {
  const RangeeGarde({
    required this.verbe,
    required this.sens,
    required this.jour,
    required this.creneau,
    required this.debut,
    required this.fin,
    super.key,
  });

  final String verbe;
  final SensGarde sens;
  final DateTime jour;
  final CreneauType creneau;

  /// « 19:00 » et « 07:00 » : les heures de la garde.
  final String debut;
  final String fin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final libelleCreneau = context.statuts.creneau(creneau).libelle;
    final jourEtDate = dateAvecJourSemaine(jour);

    final icone = switch (sens) {
      SensGarde.donne => Icons.remove_circle_outline,
      SensGarde.prend => Icons.add_circle_outline,
      SensGarde.neutre => Icons.swap_horiz,
    };

    return Semantics(
      label: AppStrings.echangeRangeeSemantique(
        verbe: verbe,
        jourEtDate: jourEtDate,
        creneau: libelleCreneau,
        debut: debut,
        fin: fin,
      ),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Icon(
                icone,
                size: AppTouch.glypheConfortable,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Le verbe a sa colonne : lu de loin, il ouvre chaque ligne. Elle
            // s'élargit avec l'échelle de texte au lieu de couper le mot.
            Flexible(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  verbe,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            CarreCreneau(creneau: creneau),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    AppStrings.echangeGardeTitre(jourEtDate, libelleCreneau),
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    AppStrings.astreintesIntervalle(debut, fin),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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
