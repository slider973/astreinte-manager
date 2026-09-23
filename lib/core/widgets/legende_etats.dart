import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_status.dart';
import '../theme/app_typography.dart';
import 'slot_chip.dart';

/// La légende des trois états de la case du registre.
///
/// Trois cases **inertes** et leurs libellés, en ligne ou repliés en `Wrap`.
/// Elle vit dans `core` parce que tout écran qui montre une grille d'états en
/// a besoin : la matrice du ticket 016, puis les créneaux du 017, la
/// publication du 019 et le planning du 023.
///
/// Les cases sont celles du système, pas des carrés dessinés à la main : une
/// légende qui n'emploie pas le composant qu'elle décrit ment le jour où le
/// composant change.
class LegendeEtats extends StatelessWidget {
  const LegendeEtats({
    super.key,
    this.densite = SlotChipDensite.dense,
    this.creneau = CreneauType.jour,
    this.espacement = AppSpacing.lg,
  });

  /// Densité des cases de la légende. [SlotChipDensite.dense] par défaut :
  /// une légende ne se touche pas, elle se lit.
  final SlotChipDensite densite;

  /// Créneau employé pour peindre la case « non saisi », seule à laisser voir
  /// son fond.
  final CreneauType creneau;

  /// Écart entre deux entrées. `lg` dans un bloc, où la légende respire ;
  /// la barre de commande de l'admin la resserre à `sm`, parce que sa rangée
  /// se compte au point près (chantier 061c).
  final double espacement;

  /// Les trois états, dans l'ordre du registre : cochée, barrée, vide.
  static const List<DisponibiliteEtat> etats = <DisponibiliteEtat>[
    DisponibiliteEtat.disponible,
    DisponibiliteEtat.absent,
    DisponibiliteEtat.nonSaisi,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statuts = context.statuts;

    return Wrap(
      spacing: espacement,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final etat in etats)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // La case est décorative ici : le libellé qui suit porte
              // l'information, et l'annoncer deux fois n'apprend rien.
              ExcludeSemantics(
                child: SlotChip(
                  etat: etat,
                  creneau: creneau,
                  densite: densite,
                  libelleSemantique: statuts.disponibilite(etat).libelle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                statuts.disponibilite(etat).libelle,
                style: AppTextStyles.mention.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
