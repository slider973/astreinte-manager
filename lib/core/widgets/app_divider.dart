import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_status.dart';

/// Le filet de réglure — **le matériau de séparation du système**.
///
/// `DESIGN.md § Elevation & Depth` : on sépare par un trait et par un cran de
/// surface tonale, jamais par une ombre. Un `Divider` Material nu laisse
/// 16 dp d'espace de part et d'autre et se teinte au hasard du thème ; celui-ci
/// ne prend que son épaisseur et sa couleur du système.
///
/// Deux filets, deux rôles, à ne jamais confondre :
/// - **décoratif** (par défaut) : `outlineVariant`, ne porte aucune
///   information, contraste volontairement bas ;
/// - **porteur d'état** ([porteurEtat] à vrai) : `filetEtat`, ≥ 3:1, employé
///   quand le trait lui-même dit quelque chose.
class AppDivider extends StatelessWidget {
  /// Filet horizontal pleine largeur, sans espace autour.
  const AppDivider({
    super.key,
    this.porteurEtat = false,
    this.indent = 0,
    this.endIndent = 0,
  }) : _axe = Axis.horizontal,
       _epaisseur = AppStroke.filet;

  /// Filet vertical, pour séparer deux volets ou figer une colonne.
  const AppDivider.vertical({
    super.key,
    this.porteurEtat = false,
    this.indent = 0,
    this.endIndent = 0,
  }) : _axe = Axis.vertical,
       _epaisseur = AppStroke.filet;

  /// Filet d'en-tête collant : 2 dp, porteur d'état, il marque la limite
  /// entre un en-tête figé et le contenu qui défile dessous.
  const AppDivider.enTete({super.key})
    : _axe = Axis.horizontal,
      _epaisseur = AppStroke.etat,
      porteurEtat = true,
      indent = 0,
      endIndent = 0;

  final Axis _axe;
  final double _epaisseur;

  /// Vrai si le trait porte une information et doit atteindre 3:1.
  final bool porteurEtat;

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    final statuts = context.statuts;
    final couleur = porteurEtat ? statuts.filetEtat : statuts.filetDecoratif;

    return _axe == Axis.horizontal
        ? Divider(
            height: _epaisseur,
            thickness: _epaisseur,
            color: couleur,
            indent: indent,
            endIndent: endIndent,
          )
        : VerticalDivider(
            width: _epaisseur,
            thickness: _epaisseur,
            color: couleur,
            indent: indent,
            endIndent: endIndent,
          );
  }
}
