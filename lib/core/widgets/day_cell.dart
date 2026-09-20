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

/// Les deux façons de composer un jour, pour la **même** donnée.
///
/// Le choix n'est pas esthétique, il est arithmétique (brief 011 § 3) : sept
/// colonnes de cases réclament `7 × 48 + 6 × 8 = 384 dp`, un téléphone de
/// 360 dp n'en offre que 328 entre ses marges. La forme calendaire ne rentre
/// pas sur un téléphone, et la faire rentrer coûterait soit des cases sous le
/// plancher WCAG, soit des écarts de 2 dp entre deux cibles.
enum DayCellOrientation {
  /// Le bloc du calendrier : en-tête, puis les deux cases empilées, chacune
  /// précédée de son icône de créneau. Employée dès `expanded` (≥ 840 dp).
  colonne,

  /// La ligne du registre : trois colonnes de largeur égale, `Date | Jour |
  /// Nuit`. La composition de référence sur téléphone.
  ///
  /// L'icône du créneau n'y est **pas** répétée dans chaque cellule : elle
  /// vit dans l'en-tête de colonnes épinglé, et c'est la position en colonne
  /// qui distingue le jour de la nuit. Soixante-deux petits soleils et lunes
  /// seraient du bruit sur un registre. La sémantique de chaque case, elle,
  /// continue de dire « nuit » en toutes lettres.
  ligne,
}

/// Un jour du mois : un **bloc réglé**, pas une carte.
///
/// `DESIGN.md § Cards / Containers` : fond `surface`, filet 1 dp
/// `outline-variant`, rayon 8, **sans ombre**. Les blocs ne s'imbriquent
/// jamais.
///
/// En [DayCellOrientation.colonne], de haut en bas : le numéro du jour en
/// `nombre-petit`, le nom du jour en `etiquette`, le marqueur de jour férié,
/// puis les deux cases — jour au-dessus, nuit en dessous. En
/// [DayCellOrientation.ligne], de gauche à droite : la date, la case du jour,
/// la case de la nuit. Le jour courant porte un filet `primary` de 2 dp sur
/// son bord gauche et le mot « Aujourd'hui » en semantics.
class DayCell extends StatelessWidget {
  const DayCell({
    required this.numero,
    required this.nomJour,
    required this.jour,
    required this.nuit,
    required this.dateLongue,
    super.key,
    this.orientation = DayCellOrientation.colonne,
    this.densite = SlotChipDensite.confortable,
    this.weekend = false,
    this.nomJourFerie,
    this.aujourdhui = false,
    this.horsMois = false,
    this.verrouille = false,
    this.deuxNiveaux = false,
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

  /// Registre (une ligne) ou calendrier (un bloc). Défaut : le calendrier,
  /// pour que l'existant ne bouge pas.
  final DayCellOrientation orientation;

  final SlotChipDensite densite;

  /// Samedi, dimanche ou jour férié : fond `surface-dim`, nom en gras.
  final bool weekend;

  /// Nom du jour férié, si c'en est un. Affiché **en clair** en orientation
  /// ligne, en info-bulle en orientation colonne, et annoncé dans les deux.
  final String? nomJourFerie;

  final bool aujourdhui;

  /// Jour appartenant au mois précédent ou suivant : atténué, non actionnable.
  final bool horsMois;

  /// Mois verrouillé : les cases restent lisibles, l'interaction disparaît.
  final bool verrouille;

  /// En orientation ligne et à très grande échelle de texte (> ×1.6), la
  /// ligne passe à deux niveaux : la date au-dessus, les deux cases pleine
  /// largeur en dessous. Rien n'est rogné, la hauteur devient libre.
  final bool deuxNiveaux;

  bool get _inerte => horsMois || verrouille;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statuts = context.statuts;
    final ferie = nomJourFerie != null;

    final fond = weekend || ferie
        ? theme.colorScheme.surfaceDim
        : theme.colorScheme.surface;

    final semantique = Semantics(
      container: true,
      label: <String>[
        dateLongue,
        if (aujourdhui) AppStrings.jourAujourdhui,
        if (ferie) AppStrings.jourFerieNomme(nomJourFerie!),
        if (weekend && !ferie) AppStrings.jourWeekend,
        if (horsMois) AppStrings.jourHorsMois,
        if (verrouille) AppStrings.periodeVerrouillee,
      ].join('. '),
      child: orientation == DayCellOrientation.ligne
          ? _Ligne(cellule: this, fond: fond, ferie: ferie)
          : _Bloc(cellule: this, fond: fond, ferie: ferie, statuts: statuts),
    );

    return horsMois
        ? Opacity(opacity: 0.45, child: semantique)
        : semantique;
  }

  /// Le numéro du jour et le nom du jour, communs aux deux orientations.
  Widget _numeroEtNom(BuildContext context, {required bool ferie}) {
    final theme = Theme.of(context);
    return Row(
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
      ],
    );
  }

  Widget _case(
    BuildContext context,
    CreneauType creneau,
    DaySlot slot, {
    required bool avecIcone,
  }) {
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

    if (!avecIcone || densite == SlotChipDensite.dense) return chip;

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

/// La composition calendaire : un bloc réglé, deux cases empilées.
class _Bloc extends StatelessWidget {
  const _Bloc({
    required this.cellule,
    required this.fond,
    required this.ferie,
    required this.statuts,
  });

  final DayCell cellule;
  final Color fond;
  final bool ferie;
  final AppStatusColors statuts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final enTete = Row(
      children: <Widget>[
        Expanded(child: cellule._numeroEtNom(context, ferie: ferie)),
        if (ferie)
          Tooltip(
            message: AppStrings.jourFerieNomme(cellule.nomJourFerie!),
            child: Icon(
              Icons.star,
              size: AppTouch.iconePetite,
              color: theme.colorScheme.tertiary,
            ),
          ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fond,
        borderRadius: AppRadius.controleRadius,
        border: Border.all(color: statuts.filetDecoratif),
      ),
      child: Stack(
        children: <Widget>[
          // Le jour courant se signe par un filet d'encre en marge, pas par
          // une pastille colorée.
          if (cellule.aujourdhui)
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                enTete,
                const SizedBox(height: AppSpacing.sm),
                cellule._case(
                  context,
                  CreneauType.jour,
                  cellule.jour,
                  avecIcone: true,
                ),
                const SizedBox(height: AppSpacing.xs),
                cellule._case(
                  context,
                  CreneauType.nuit,
                  cellule.nuit,
                  avecIcone: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// La composition du registre : `Date | Jour | Nuit`, trois colonnes égales.
///
/// Ce n'est pas un bloc réglé mais une **ligne de registre** : pas de filet
/// qui l'entoure, pas de rayon. La réglure entre deux jours est posée par la
/// grille, qui seule sait où commencent les lundis.
class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.cellule,
    required this.fond,
    required this.ferie,
  });

  final DayCell cellule;
  final Color fond;
  final bool ferie;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final date = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        cellule._numeroEtNom(context, ferie: ferie),
        if (ferie)
          Row(
            children: <Widget>[
              Icon(
                Icons.star,
                size: AppTouch.iconePetite,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: AppSpacing.xxs),
              // Le nom du férié en clair : la place existe dans la colonne,
              // et une info-bulle au survol ne serait pas un accès.
              Expanded(
                child: Text(
                  cellule.nomJourFerie!,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
      ],
    );

    final caseJour = cellule._case(
      context,
      CreneauType.jour,
      cellule.jour,
      avecIcone: false,
    );
    final caseNuit = cellule._case(
      context,
      CreneauType.nuit,
      cellule.nuit,
      avecIcone: false,
    );

    final contenu = cellule.deuxNiveaux
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              date,
              const SizedBox(height: AppSpacing.sm),
              caseJour,
              const SizedBox(height: AppSpacing.entreCibles),
              caseNuit,
            ],
          )
        : Row(
            children: <Widget>[
              Expanded(child: date),
              const SizedBox(width: AppSpacing.entreCibles),
              Expanded(child: caseJour),
              const SizedBox(width: AppSpacing.entreCibles),
              Expanded(child: caseNuit),
            ],
          );

    return DecoratedBox(
      decoration: BoxDecoration(color: fond),
      child: Stack(
        children: <Widget>[
          if (cellule.aujourdhui)
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
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: contenu,
          ),
        ],
      ),
    );
  }
}
