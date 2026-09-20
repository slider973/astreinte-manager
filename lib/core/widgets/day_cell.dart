import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status.dart';
import '../theme/app_typography.dart';
import 'slot_chip.dart';

/// Un jour du mois : un **bloc réglé**, pas une carte.
///
/// `DESIGN.md § Cards / Containers` : fond `surface`, filet 1 dp
/// `outline-variant`, rayon 8, **sans ombre**. Les blocs ne s'imbriquent
/// jamais.
///
/// Composition, de haut en bas : le numéro du jour en `nombre-petit`, le nom
/// du jour en `etiquette`, le marqueur de jour férié, puis les deux cases —
/// jour au-dessus, nuit en dessous. Le jour courant porte un filet `primary`
/// de 2 dp sur son bord gauche et le mot « Aujourd'hui » en semantics.
class DayCell extends StatelessWidget {
  const DayCell({
    required this.numero,
    required this.nomJour,
    required this.etatJour,
    required this.etatNuit,
    required this.dateLongue,
    super.key,
    this.densite = SlotChipDensite.confortable,
    this.weekend = false,
    this.nomJourFerie,
    this.aujourdhui = false,
    this.horsMois = false,
    this.verrouille = false,
    this.onTapJour,
    this.onTapNuit,
  });

  /// Numéro du jour dans le mois (1 à 31).
  final int numero;

  /// Nom court du jour (« sam. »), affiché en en-tête de la case.
  final String nomJour;

  /// Date complète pour les lecteurs d'écran : « samedi 4 octobre ».
  final String dateLongue;

  final DisponibiliteEtat etatJour;
  final DisponibiliteEtat etatNuit;

  final SlotChipDensite densite;

  /// Samedi, dimanche ou jour férié : fond `surface-dim`, nom en gras.
  final bool weekend;

  /// Nom du jour férié, si c'en est un. Affiché en info-bulle **et** annoncé.
  final String? nomJourFerie;

  final bool aujourdhui;

  /// Jour appartenant au mois précédent ou suivant : atténué, non actionnable.
  final bool horsMois;

  /// Mois verrouillé : les cases restent lisibles, l'interaction disparaît.
  final bool verrouille;

  final VoidCallback? onTapJour;
  final VoidCallback? onTapNuit;

  bool get _inerte => horsMois || verrouille;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statuts = context.statuts;
    final ferie = nomJourFerie != null;

    final fond = weekend || ferie
        ? theme.colorScheme.surfaceDim
        : theme.colorScheme.surface;

    final enTete = Row(
      children: <Widget>[
        Text(
          '$numero',
          style: AppTextStyles.nombrePetit.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            nomJour,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: weekend || ferie ? FontWeight.w700 : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (ferie)
          Tooltip(
            message: AppStrings.jourFerieNomme(nomJourFerie!),
            child: Icon(
              Icons.star,
              size: AppTouch.iconePetite,
              color: theme.colorScheme.tertiary,
            ),
          ),
      ],
    );

    final contenu = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        enTete,
        const SizedBox(height: AppSpacing.sm),
        _case(context, CreneauType.jour, etatJour, onTapJour),
        const SizedBox(height: AppSpacing.xs),
        _case(context, CreneauType.nuit, etatNuit, onTapNuit),
      ],
    );

    return Semantics(
      container: true,
      label: <String>[
        dateLongue,
        if (aujourdhui) AppStrings.jourAujourdhui,
        if (ferie) AppStrings.jourFerieNomme(nomJourFerie!),
        if (weekend && !ferie) AppStrings.jourWeekend,
        if (horsMois) AppStrings.jourHorsMois,
        if (verrouille) AppStrings.periodeVerrouillee,
      ].join('. '),
      child: Opacity(
        opacity: horsMois ? 0.45 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fond,
            borderRadius: AppRadius.controleRadius,
            border: Border(
              // Le jour courant se signe par un filet d'encre en marge, pas
              // par une pastille colorée.
              left: BorderSide(
                color: aujourdhui
                    ? theme.colorScheme.primary
                    : statuts.filetDecoratif,
                width: aujourdhui ? AppStroke.etat : AppStroke.filet,
              ),
              top: BorderSide(color: statuts.filetDecoratif),
              right: BorderSide(color: statuts.filetDecoratif),
              bottom: BorderSide(color: statuts.filetDecoratif),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: contenu,
          ),
        ),
      ),
    );
  }

  Widget _case(
    BuildContext context,
    CreneauType creneau,
    DisponibiliteEtat etat,
    VoidCallback? onTap,
  ) {
    final descripteurCreneau = context.statuts.creneau(creneau);
    final libelleCreneau = descripteurCreneau.libelle;

    final chip = SlotChip(
      etat: etat,
      creneau: creneau,
      densite: densite,
      verrouille: verrouille,
      onTap: _inerte ? null : onTap,
      libelleSemantique: AppStrings.slotSemantique(
        jourEtDate: dateLongue,
        creneau: libelleCreneau,
        etat: context.statuts.disponibilite(etat).libelle,
      ),
      actionSemantique: switch (etat) {
        DisponibiliteEtat.nonSaisi => AppStrings.slotActionMarquerDisponible,
        DisponibiliteEtat.disponible => AppStrings.slotActionMarquerAbsent,
        DisponibiliteEtat.absent => AppStrings.slotActionEffacer,
      },
    );

    if (densite == SlotChipDensite.dense) return chip;

    // Jour et nuit se distinguent par l'icône et par la position — le fond ne
    // fait que confirmer (`DESIGN.md § Créneau`).
    return Row(
      children: <Widget>[
        Icon(
          descripteurCreneau.icone,
          size: AppTouch.iconePetite,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: chip),
      ],
    );
  }
}
