import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_status.dart';
import 'slot_chip.dart';

/// **Le bloc d'attribution** — la case du registre quand quelqu'un y est posé.
///
/// Même carré que [SlotChip] en densité dense — 28 px, `AppRadius.caseRegistre`
/// — mais il ne dit plus ce que le membre a déclaré : il dit ce que le planning
/// lui a donné. Fond, encre, contour et glyphe viennent d'un seul endroit,
/// `context.statuts.attribution(etat)` : aucune couleur n'est écrite ici, et
/// l'icône de la famille (`hourglass_top`, `task_alt`, `cancel`) porte l'état
/// avant la teinte — le glyphe reste le premier signal (chantier 061c).
///
/// **Le bloc est plein, à la teinte forte de sa famille**
/// ([StatusDescriptor.blocFond]), et non au fond pâle du badge. Un badge se lit
/// de près, dans une phrase ; ce bloc se repère de loin, en balayant soixante-
/// deux colonnes, et il doit peser au moins autant que la coche indigo pleine
/// de « disponible » qu'il remplace. Aux fonds pâles, l'écran disait l'inverse
/// de ce qu'il fallait lire — une déclaration l'emportait sur une astreinte
/// posée (chantier 061c-2).
///
/// **28 px, donc pointeur seulement**, comme la case dense et comme la ligne
/// des créneaux : au doigt le bloc se lit, et le panneau s'ouvre depuis la vue
/// par jour en cibles de 48 dp (`DESIGN.md § Cibles tactiles`).
///
/// Il ne sait rien de ce qu'il désigne : son parent compose la phrase de
/// sémantique, qui nomme le membre, le jour, le créneau, l'état — et entre
/// parenthèses la disponibilité déclarée, parce qu'une astreinte posée contre
/// une absence est exactement ce qu'un chef veut voir.
class CaseAttribution extends StatelessWidget {
  const CaseAttribution({
    required this.etat,
    required this.libelleSemantique,
    super.key,
    this.erreur = false,
    this.onTap,
    this.actionSemantique,
  });

  final AttributionEtat etat;

  /// **Phrase complète française**, jamais un code. Composée par le parent,
  /// qui seul connaît la date et le membre.
  final String libelleSemantique;

  /// Ce que l'appui va faire : « Appuie pour ouvrir le créneau ».
  final String? actionSemantique;

  /// L'enregistrement de **la disponibilité** sous ce bloc a échoué : le
  /// contour passe à `error`, comme sur la case nue. Sans lui, armer la saisie
  /// sur une case attribuée aurait fait disparaître la seule marque d'échec.
  final bool erreur;

  final VoidCallback? onTap;

  /// Le côté du bloc. La case dense du système, ni plus ni moins : la matrice
  /// et la légende qui la décrit partagent la même mesure.
  static const double cote = AppTouch.caseDense;

  bool _actionnable(BuildContext context) =>
      onTap != null && SlotChipDensite.dense.actionnableDans(context);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descripteur = context.statuts.attribution(etat);
    final actionnable = _actionnable(context);

    // Un seul contour à la fois : l'erreur d'abord, puis le filet propre à
    // l'état. Sur « proposé », ce filet n'est pas un ornement : l'orange vif
    // ne fait que 2,26:1 sur le papier, et c'est lui qui porte la limite du
    // bloc (WCAG 1.4.11). Les deux autres teintes passent seules.
    final filet = erreur ? theme.colorScheme.error : descripteur.filet;

    final corps = SizedBox.square(
      dimension: cote,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: descripteur.blocFond,
          borderRadius: AppRadius.caseRegistreRadius,
          border: filet == null
              ? null
              : Border.all(color: filet, width: AppStroke.etat),
        ),
        child: Icon(
          descripteur.icone,
          size: AppTouch.glypheDense,
          color: descripteur.blocEncre,
        ),
      ),
    );

    return Semantics(
      label: libelleSemantique,
      hint: actionnable ? actionSemantique : null,
      button: actionnable,
      enabled: actionnable,
      // L'action est portée par le nœud qui exclut ses enfants : sans elle, le
      // lecteur d'écran annoncerait un bouton que rien ne permet d'activer.
      onTap: actionnable ? onTap : null,
      excludeSemantics: true,
      child: actionnable
          ? InkWell(
              onTap: onTap,
              borderRadius: AppRadius.caseRegistreRadius,
              child: corps,
            )
          : corps,
    );
  }
}
