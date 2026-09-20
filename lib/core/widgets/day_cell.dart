import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status.dart';
import '../theme/app_typography.dart';
import 'slot_chip.dart';

/// Un créneau d'une journée, tel que la grille du mois le connaît.
///
/// Regroupe l'état affiché **et** tout ce que le parent veut brancher dessus.
/// Un objet par créneau plutôt que six paramètres `…Jour` / `…Nuit` sur
/// [DayCell] : la grille du ticket 011 doit pouvoir passer une sélection, une
/// erreur et un rappel de glissement pour chacun des deux créneaux sans que
/// [DayCell] soit rouvert à chaque besoin.
@immutable
class DaySlot {
  const DaySlot({
    required this.etat,
    this.onTap,
    this.onDragEnter,
    this.selectionne = false,
    this.erreur = false,
    this.enEnregistrement = false,
  });

  final DisponibiliteEtat etat;

  /// Appui simple sur la case.
  final VoidCallback? onTap;

  /// Entrée d'un glissement de sélection dans la case (ticket 011). La case
  /// publie ce rappel ; c'est la grille qui mène le geste.
  final VoidCallback? onDragEnter;

  /// Case prise dans la sélection courante : contour 2 dp `primary`.
  final bool selectionne;

  /// L'enregistrement de ce créneau a échoué : contour 2 dp `error`.
  final bool erreur;

  /// L'enregistrement de ce créneau est parti : le contour pulse une fois.
  final bool enEnregistrement;

  DaySlot copyWith({DisponibiliteEtat? etat, VoidCallback? onTap}) => DaySlot(
    etat: etat ?? this.etat,
    onTap: onTap ?? this.onTap,
    onDragEnter: onDragEnter,
    selectionne: selectionne,
    erreur: erreur,
    enEnregistrement: enEnregistrement,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DaySlot &&
          other.etat == etat &&
          other.onTap == onTap &&
          other.onDragEnter == onDragEnter &&
          other.selectionne == selectionne &&
          other.erreur == erreur &&
          other.enEnregistrement == enEnregistrement;

  @override
  int get hashCode => Object.hash(
    etat,
    onTap,
    onDragEnter,
    selectionne,
    erreur,
    enEnregistrement,
  );
}

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
    required this.jour,
    required this.nuit,
    required this.dateLongue,
    super.key,
    this.densite = SlotChipDensite.confortable,
    this.weekend = false,
    this.nomJourFerie,
    this.aujourdhui = false,
    this.horsMois = false,
    this.verrouille = false,
  });

  /// Numéro du jour dans le mois (1 à 31).
  final int numero;

  /// Nom court du jour (« sam. »), affiché en en-tête de la case.
  final String nomJour;

  /// Date complète pour les lecteurs d'écran : « samedi 4 octobre ».
  final String dateLongue;

  /// Le créneau de jour, avec son état et ses rappels.
  final DaySlot jour;

  /// Le créneau de nuit, avec son état et ses rappels.
  final DaySlot nuit;

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
        _case(context, CreneauType.jour, jour),
        const SizedBox(height: AppSpacing.xs),
        _case(context, CreneauType.nuit, nuit),
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
            border: Border.all(color: statuts.filetDecoratif),
          ),
          child: Stack(
            children: <Widget>[
              // Le jour courant se signe par un filet d'encre en marge, pas
              // par une pastille colorée.
              if (aujourdhui)
                PositionedDirectional(
                  top: 0,
                  bottom: 0,
                  start: 0,
                  child: ColoredBox(
                    color: theme.colorScheme.primary,
                    child: const SizedBox(width: AppStroke.etat),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: contenu,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _case(BuildContext context, CreneauType creneau, DaySlot slot) {
    final descripteurCreneau = context.statuts.creneau(creneau);

    final chip = SlotChip(
      etat: slot.etat,
      creneau: creneau,
      densite: densite,
      verrouille: verrouille,
      selectionne: slot.selectionne,
      erreur: slot.erreur,
      enEnregistrement: slot.enEnregistrement,
      onTap: _inerte ? null : slot.onTap,
      onDragEnter: _inerte ? null : slot.onDragEnter,
      libelleSemantique: AppStrings.slotSemantique(
        jourEtDate: dateLongue,
        creneau: descripteurCreneau.libelle,
        etat: context.statuts.disponibilite(slot.etat).libelle,
      ),
      actionSemantique: switch (slot.etat) {
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
