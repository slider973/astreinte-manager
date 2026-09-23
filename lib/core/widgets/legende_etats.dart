import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_status.dart';
import '../theme/app_typography.dart';
import 'case_attribution.dart';
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
///
/// Quand le planning du mois existe, les cases de la matrice ne disent plus
/// seulement une disponibilité : trois d'entre elles portent une attribution.
/// [LegendeEtats.attributions] les nomme — une marque nouvelle à l'écran sans
/// son libellé serait un code à deviner. Les deux familles ne se mélangent pas
/// dans une même rangée : mesurée, la légende complète pousse la barre de
/// commande de l'admin de 120 à 176 points (`DESIGN.md § Écarts, 061c-2`).
class LegendeEtats extends StatelessWidget {
  const LegendeEtats({
    super.key,
    this.densite = SlotChipDensite.dense,
    this.creneau = CreneauType.jour,
    this.espacement = AppSpacing.lg,
  }) : _attributions = false;

  /// Les trois états d'**attribution** seuls : proposé, accepté, refusé. La
  /// forme que porte le bandeau du mois, sous la légende de répartition, dès
  /// que le planning existe.
  const LegendeEtats.attributions({
    super.key,
    this.espacement = AppSpacing.lg,
  }) : densite = SlotChipDensite.dense,
       creneau = CreneauType.jour,
       _attributions = true;

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

  /// Vrai pour la famille des attributions, faux pour celle des
  /// disponibilités.
  final bool _attributions;

  /// Les trois états, dans l'ordre du registre : cochée, barrée, vide.
  static const List<DisponibiliteEtat> etats = <DisponibiliteEtat>[
    DisponibiliteEtat.disponible,
    DisponibiliteEtat.absent,
    DisponibiliteEtat.nonSaisi,
  ];

  /// Les trois états d'attribution qu'une case peut porter, dans l'ordre du
  /// travail : ce qui attend une réponse, ce qui est acquis, ce qui a cassé.
  /// « Remplacé » et « annulé » n'y sont pas — ils ne s'affichent nulle part
  /// dans la grille.
  static const List<AttributionEtat> etatsAttribution = <AttributionEtat>[
    AttributionEtat.propose,
    AttributionEtat.accepte,
    AttributionEtat.refuse,
  ];

  @override
  Widget build(BuildContext context) {
    final statuts = context.statuts;

    return Wrap(
      spacing: espacement,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: _attributions
          ? <Widget>[
              for (final etat in etatsAttribution)
                _Entree(
                  libelle: statuts.attribution(etat).libelle,
                  marque: CaseAttribution(
                    etat: etat,
                    libelleSemantique: statuts.attribution(etat).libelle,
                  ),
                ),
            ]
          : <Widget>[
              for (final etat in etats)
                _Entree(
                  libelle: statuts.disponibilite(etat).libelle,
                  // La case est décorative ici : le libellé qui suit porte
                  // l'information, et l'annoncer deux fois n'apprend rien.
                  marque: SlotChip(
                    etat: etat,
                    creneau: creneau,
                    densite: densite,
                    libelleSemantique: statuts.disponibilite(etat).libelle,
                  ),
                ),
            ],
    );
  }
}

/// Une marque et son mot. Le mot est le seul nœud de sémantique : une légende
/// qui s'annonce deux fois par entrée se lit deux fois plus longtemps.
class _Entree extends StatelessWidget {
  const _Entree({required this.marque, required this.libelle});

  final Widget marque;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(child: marque),
        const SizedBox(width: AppSpacing.sm),
        Text(
          libelle,
          style: AppTextStyles.mention.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
