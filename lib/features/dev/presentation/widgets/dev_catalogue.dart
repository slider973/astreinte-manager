import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/bouton_retour.dart';
import '../../../../core/widgets/carte_douce.dart';
import '../../../../core/widgets/count_stat.dart';
import '../../../../core/widgets/day_cell.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/loading_skeleton.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/save_indicator.dart';
import '../../../../core/widgets/slot_chip.dart';
import '../../../../core/widgets/status_badge.dart';
import 'dev_section.dart';

/// Le catalogue complet : chaque composant, chaque état.
///
/// C'est la **preuve de couverture** du ticket 004 (brief § 2) : une capture
/// de cet écran en niveaux de gris doit rester entièrement interprétable, et
/// il doit tenir à une échelle de texte de 1.0, 1.3 et 2.0 sans texte tronqué.
class DevCatalogue extends StatelessWidget {
  const DevCatalogue({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionTypographie(),
        _SectionBoutons(),
        _SectionCases(),
        _SectionJours(),
        _SectionCartes(),
        _SectionBadges(),
        _SectionBannieres(),
        _SectionEtatsVides(),
        _SectionChargement(),
        _SectionMesures(),
        _SectionOssature(),
        _SectionRetour(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionTypographie extends StatelessWidget {
  const _SectionTypographie();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const echantillon = 'Samedi 4 octobre — Ill1 O0 «garde»';

    return DevSection(
      titre: 'Typographie',
      note:
          'Archivo sur les trois titres, Atkinson Hyperlegible Next en dessous '
          'de 18 points, Atkinson Mono sur tout chiffre — les trois embarquées. '
          'La ligne d\'échantillon contient les paires que la police sépare : '
          'I l 1, O 0.',
      children: <Widget>[
        for (final (nom, style) in <(String, TextStyle?)>[
          ('titre-ecran / headlineMedium', theme.textTheme.headlineMedium),
          ('titre-section / titleLarge', theme.textTheme.titleLarge),
          ('titre-bloc / titleMedium', theme.textTheme.titleMedium),
          ('corps / bodyLarge', theme.textTheme.bodyLarge),
          ('corps-secondaire / bodyMedium', theme.textTheme.bodyMedium),
          ('mention / bodySmall', theme.textTheme.bodySmall),
          ('libelle-action / labelLarge', theme.textTheme.labelLarge),
          ('etiquette / labelSmall', theme.textTheme.labelSmall),
        ])
          DevSpecimen(
            nom: nom,
            child: Text(echantillon, style: style),
          ),
        DevSpecimen(
          nom: 'display-nombre / nombre / nombre-petit (chasse fixe)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Les styles de token n'ont pas de couleur : elle vient du thème.
              for (final style in <TextStyle>[
                AppTextStyles.displayNombre,
                AppTextStyles.nombre,
                AppTextStyles.nombrePetit,
              ])
                Text(
                  '10 / 31',
                  style: style.copyWith(color: theme.colorScheme.onSurface),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionBoutons extends StatelessWidget {
  const _SectionBoutons();

  static void _rien() {}

  @override
  Widget build(BuildContext context) {
    return const DevSection(
      titre: 'PrimaryButton',
      note:
          'Hauteur 52, rayon 8, libellé 16 sp. Un bouton désactivé affiche '
          'toujours sa raison.',
      children: <Widget>[
        DevSpecimen(
          nom: 'primaire',
          child: PrimaryButton(
            libelle: 'Enregistrer le mois',
            onPressed: _rien,
          ),
        ),
        DevSpecimen(
          nom: 'primaire avec icône',
          child: PrimaryButton(
            libelle: 'Enregistrer le mois',
            icone: Icons.check,
            onPressed: _rien,
          ),
        ),
        DevSpecimen(
          nom: 'secondaire',
          child: PrimaryButton(
            libelle: 'Revenir au mois',
            variante: PrimaryButtonVariante.secondaire,
            onPressed: _rien,
          ),
        ),
        DevSpecimen(
          nom: 'danger',
          child: PrimaryButton(
            libelle: 'Refuser le créneau',
            variante: PrimaryButtonVariante.danger,
            icone: Icons.cancel,
            onPressed: _rien,
          ),
        ),
        DevSpecimen(
          nom: 'chargement (la largeur ne bouge pas)',
          child: PrimaryButton(
            libelle: 'Enregistrer le mois',
            icone: Icons.check,
            chargement: true,
            onPressed: _rien,
          ),
        ),
        DevSpecimen(
          nom: 'désactivé, avec sa raison',
          child: PrimaryButton(
            libelle: 'Enregistrer le mois',
            onPressed: null,
            raisonDesactivation:
                'Le mois est verrouillé depuis le 15 septembre.',
          ),
        ),
        DevSpecimen(
          nom: 'largeur intrinsèque (plancher 160 dp)',
          child: Align(
            alignment: Alignment.centerLeft,
            child: PrimaryButton(
              libelle: 'Continuer',
              pleineLargeur: false,
              onPressed: _rien,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionCases extends StatelessWidget {
  const _SectionCases();

  static void _rien() {}

  @override
  Widget build(BuildContext context) {
    return DevSection(
      titre: 'SlotChip',
      note:
          'Trois remplissages avant toute teinte : pleine, hachurée bordée, '
          'vide au filet tireté. La densité dense est réservée au pointeur.',
      children: <Widget>[
        for (final densite in SlotChipDensite.values)
          DevSpecimen(
            nom: '${densite.name} — ${densite.taille.toInt()} dp',
            child: DevRangee(
              children: <Widget>[
                for (final creneau in CreneauType.values)
                  for (final etat in DisponibiliteEtat.values)
                    SizedBox(
                      width: densite.taille,
                      child: SlotChip(
                        etat: etat,
                        creneau: creneau,
                        densite: densite,
                        onTap: densite == SlotChipDensite.dense ? null : _rien,
                        libelleSemantique: AppStrings.slotSemantique(
                          jourEtDate: 'Samedi 4 octobre',
                          creneau: creneau == CreneauType.jour
                              ? AppStrings.creneauJour
                              : AppStrings.creneauNuit,
                          etat: context.statuts.disponibilite(etat).libelle,
                        ),
                        actionSemantique:
                            AppStrings.slotActionMarquerDisponible,
                      ),
                    ),
              ],
            ),
          ),
        DevSpecimen(
          nom: 'sélectionné · verrouillé · en enregistrement · erreur',
          child: DevRangee(
            children: <Widget>[
              for (final (nom, chip) in <(String, SlotChip)>[
                (
                  'sélectionné',
                  const SlotChip(
                    etat: DisponibiliteEtat.disponible,
                    creneau: CreneauType.jour,
                    selectionne: true,
                    onTap: _rien,
                    libelleSemantique: 'Samedi 4 octobre, jour, disponible',
                  ),
                ),
                (
                  'verrouillé',
                  const SlotChip(
                    etat: DisponibiliteEtat.disponible,
                    creneau: CreneauType.jour,
                    verrouille: true,
                    libelleSemantique: 'Samedi 4 octobre, jour, disponible',
                  ),
                ),
                (
                  'enregistrement',
                  const SlotChip(
                    etat: DisponibiliteEtat.absent,
                    creneau: CreneauType.nuit,
                    enEnregistrement: true,
                    onTap: _rien,
                    libelleSemantique: 'Samedi 4 octobre, nuit, absent',
                  ),
                ),
                (
                  'erreur',
                  const SlotChip(
                    etat: DisponibiliteEtat.absent,
                    creneau: CreneauType.nuit,
                    erreur: true,
                    onTap: _rien,
                    libelleSemantique: 'Samedi 4 octobre, nuit, absent',
                  ),
                ),
              ])
                SizedBox(
                  width: 160,
                  child: DevSpecimen(nom: nom, child: chip),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionJours extends StatelessWidget {
  const _SectionJours();

  static void _rien() {}

  @override
  Widget build(BuildContext context) {
    return DevSection(
      titre: 'DayCell',
      note:
          'Un bloc réglé : filet 1 dp, rayon 8, aucune ombre. Le jour courant '
          'porte un filet d\'encre en marge. Chaque créneau porte ses propres '
          'rappels et son propre état (sélection, erreur, enregistrement).',
      children: <Widget>[
        DevRangee(
          children: <Widget>[
            for (final (nom, cellule) in <(String, DayCell)>[
              (
                'jour ouvré',
                const DayCell(
                  numero: 2,
                  nomJour: 'jeu.',
                  dateLongue: 'Jeudi 2 octobre',
                  jour: DaySlot(etat: DisponibiliteEtat.nonSaisi, onTap: _rien),
                  nuit: DaySlot(etat: DisponibiliteEtat.nonSaisi, onTap: _rien),
                ),
              ),
              (
                'weekend',
                const DayCell(
                  numero: 4,
                  nomJour: 'sam.',
                  dateLongue: 'Samedi 4 octobre',
                  weekend: true,
                  jour: DaySlot(
                    etat: DisponibiliteEtat.disponible,
                    onTap: _rien,
                  ),
                  nuit: DaySlot(etat: DisponibiliteEtat.absent, onTap: _rien),
                ),
              ),
              (
                'jour férié',
                const DayCell(
                  numero: 1,
                  nomJour: 'mer.',
                  dateLongue: 'Mercredi 1er novembre',
                  weekend: true,
                  nomJourFerie: 'Toussaint',
                  jour: DaySlot(
                    etat: DisponibiliteEtat.disponible,
                    onTap: _rien,
                  ),
                  nuit: DaySlot(
                    etat: DisponibiliteEtat.disponible,
                    onTap: _rien,
                  ),
                ),
              ),
              (
                'aujourd\'hui',
                const DayCell(
                  numero: 20,
                  nomJour: 'lun.',
                  dateLongue: 'Lundi 20 octobre',
                  aujourdhui: true,
                  jour: DaySlot(
                    etat: DisponibiliteEtat.disponible,
                    onTap: _rien,
                  ),
                  nuit: DaySlot(etat: DisponibiliteEtat.nonSaisi, onTap: _rien),
                ),
              ),
              (
                'sélection par glissement (ticket 011)',
                const DayCell(
                  numero: 5,
                  nomJour: 'dim.',
                  dateLongue: 'Dimanche 5 octobre',
                  weekend: true,
                  jour: DaySlot(
                    etat: DisponibiliteEtat.disponible,
                    selectionne: true,
                    onTap: _rien,
                    onDragEnter: _rien,
                  ),
                  nuit: DaySlot(
                    etat: DisponibiliteEtat.disponible,
                    selectionne: true,
                    onTap: _rien,
                    onDragEnter: _rien,
                  ),
                ),
              ),
              (
                'erreur et enregistrement par créneau',
                const DayCell(
                  numero: 6,
                  nomJour: 'lun.',
                  dateLongue: 'Lundi 6 octobre',
                  jour: DaySlot(
                    etat: DisponibiliteEtat.absent,
                    erreur: true,
                    onTap: _rien,
                  ),
                  nuit: DaySlot(
                    etat: DisponibiliteEtat.disponible,
                    enEnregistrement: true,
                    onTap: _rien,
                  ),
                ),
              ),
              (
                'mois verrouillé',
                const DayCell(
                  numero: 12,
                  nomJour: 'dim.',
                  dateLongue: 'Dimanche 12 octobre',
                  weekend: true,
                  verrouille: true,
                  jour: DaySlot(etat: DisponibiliteEtat.disponible),
                  nuit: DaySlot(etat: DisponibiliteEtat.absent),
                ),
              ),
              (
                'hors du mois',
                const DayCell(
                  numero: 30,
                  nomJour: 'mar.',
                  dateLongue: 'Mardi 30 septembre',
                  horsMois: true,
                  jour: DaySlot(etat: DisponibiliteEtat.nonSaisi),
                  nuit: DaySlot(etat: DisponibiliteEtat.nonSaisi),
                ),
              ),
            ])
              SizedBox(
                width: 132,
                child: DevSpecimen(nom: nom, child: cellule),
              ),
          ],
        ),
        // L'orientation ligne : la composition de référence du registre sur
        // téléphone (ticket 011). Même donnée, même règle de geste.
        DevSpecimen(
          nom: 'orientation ligne — le registre (ticket 011)',
          child: Column(
            children: <Widget>[
              for (final (numero, nom, weekend, ferie, aujourdhui)
                  in <(int, String, bool, String?, bool)>[
                    (2, 'ven.', false, null, false),
                    (3, 'sam.', true, null, false),
                    (4, 'dim.', true, null, true),
                    (11, 'mer.', true, 'Armistice', false),
                  ])
                DayCell(
                  numero: numero,
                  nomJour: nom,
                  dateLongue: 'Jour $numero novembre',
                  orientation: DayCellOrientation.ligne,
                  weekend: weekend,
                  nomJourFerie: ferie,
                  aujourdhui: aujourdhui,
                  jour: const DaySlot(
                    etat: DisponibiliteEtat.disponible,
                    onTap: _rien,
                  ),
                  nuit: const DaySlot(
                    etat: DisponibiliteEtat.nonSaisi,
                    onTap: _rien,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionCartes extends StatelessWidget {
  const _SectionCartes();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DevSection(
      titre: 'CarteDouce',
      note:
          'La carte du monde du pompier : fond «surface» sur le papier doux, '
          'rayon 20, filet «outline-variant», aucune ombre. Elle ne s\'imbrique '
          'jamais.',
      children: <Widget>[
        DevSpecimen(
          nom: 'au repos',
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainerLow,
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: CarteDouce(child: Text('Octobre saisi : 12 jours')),
            ),
          ),
        ),
        DevSpecimen(
          nom: 'actionnable, hauteur de cible',
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: CarteDouce(
                onTap: () {},
                hauteurMin: AppTouch.cible,
                child: const Text('samedi 17 octobre'),
              ),
            ),
          ),
        ),
        DevSpecimen(
          nom: 'en erreur : filet «error» de 2 dp',
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainerLow,
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: CarteDouce(
                enErreur: true,
                child: Text('Au maximum 40 astreintes : c\'est trop.'),
              ),
            ),
          ),
        ),
        DevSpecimen(
          nom: 'nue : l\'enfant porte ses marges',
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainerLow,
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: CarteDouce.nue(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text('  Les weekends · La semaine · Tout le mois'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionBadges extends StatelessWidget {
  const _SectionBadges();

  @override
  Widget build(BuildContext context) {
    return DevSection(
      titre: 'StatusBadge',
      note:
          'Les six familles d\'états. Chaque badge porte sa marque, son icône '
          'et son libellé : aucun n\'est lisible par la seule teinte.',
      children: <Widget>[
        DevSpecimen(
          nom: 'disponibilité',
          child: DevRangee(
            children: <Widget>[
              for (final etat in DisponibiliteEtat.values)
                StatusBadge.disponibilite(etat),
            ],
          ),
        ),
        DevSpecimen(
          nom: 'créneau',
          child: DevRangee(
            children: <Widget>[
              for (final type in CreneauType.values) StatusBadge.creneau(type),
            ],
          ),
        ),
        DevSpecimen(
          nom: 'attribution',
          child: DevRangee(
            children: <Widget>[
              for (final etat in AttributionEtat.values)
                StatusBadge.attribution(etat),
            ],
          ),
        ),
        DevSpecimen(
          nom: 'planning',
          child: DevRangee(
            children: <Widget>[
              for (final etat in PlanningEtat.values)
                StatusBadge.planning(etat),
            ],
          ),
        ),
        DevSpecimen(
          nom: 'période',
          child: DevRangee(
            children: <Widget>[
              for (final etat in PeriodeEtat.values) StatusBadge.periode(etat),
            ],
          ),
        ),
        DevSpecimen(
          nom: 'synchronisation',
          child: DevRangee(
            children: <Widget>[
              for (final etat in SyncEtat.values) StatusBadge.sync(etat),
            ],
          ),
        ),
        DevSpecimen(
          nom: 'taille compacte',
          child: DevRangee(
            children: <Widget>[
              for (final etat in AttributionEtat.values)
                StatusBadge.attribution(
                  etat,
                  taille: StatusBadgeTaille.compacte,
                ),
            ],
          ),
        ),
        const DevSpecimen(
          nom: 'libellé long, tronqué proprement',
          child: SizedBox(
            width: 160,
            child: StatusBadge.attribution(
              AttributionEtat.propose,
              libelle: AppStrings.attributionProposeMembre,
            ),
          ),
        ),
        const DevSpecimen(
          nom: 'le tampon (seul moment chorégraphié)',
          child: StatusBadge.planning(PlanningEtat.valide, tampon: true),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionBannieres extends StatelessWidget {
  const _SectionBannieres();

  static void _rien() {}

  @override
  Widget build(BuildContext context) {
    return DevSection(
      titre: 'AppBanner',
      note:
          'Une seule à la fois : erreur > hors-ligne > lecture-seule > '
          'verrouillé > attention > information.',
      children: <Widget>[
        const DevSpecimen(
          nom: 'erreur (annoncée, avec action)',
          child: AppBanner(
            variante: AppBannerVariante.erreur,
            texte: 'Impossible d\'enregistrer ta saisie du 4 octobre.',
            libelleAction: AppStrings.actionReessayer,
            onAction: _rien,
          ),
        ),
        const DevSpecimen(
          nom: 'hors ligne',
          child: AppBanner(
            variante: AppBannerVariante.horsLigne,
            texte: AppStrings.horsLigneDetail,
          ),
        ),
        const DevSpecimen(
          nom: 'lecture seule (hachuré)',
          child: AppBanner(
            variante: AppBannerVariante.lectureSeule,
            texte: AppStrings.lectureSeuleDetail,
          ),
        ),
        DevSpecimen(
          nom: 'verrouillé (hachuré, gris-encre et non rouge)',
          child: AppBanner(
            variante: AppBannerVariante.verrouille,
            texte: AppStrings.periodeVerrouilleeDetail('15 septembre'),
          ),
        ),
        DevSpecimen(
          nom: 'attention',
          child: AppBanner(
            variante: AppBannerVariante.attention,
            texte: AppStrings.periodeBientotFermee(2, 'octobre'),
          ),
        ),
        DevSpecimen(
          nom: 'information',
          child: AppBanner(
            variante: AppBannerVariante.information,
            texte: AppStrings.periodeOuverteJusquAu('15 septembre'),
          ),
        ),
        // La seule bannière fermable : un **événement**, pas un état. Deux
        // lignes, une icône qui lui est propre, une action nommée et une
        // sortie (ticket 024).
        DevSpecimen(
          nom: 'événement (notification reçue)',
          child: AppBanner(
            variante: AppBannerVariante.information,
            icone: Icons.notifications_active_outlined,
            texte: 'Astreinte proposée',
            detail: 'Samedi 4 octobre, nuit',
            libelleAction: AppStrings.notifBanniereVoir,
            onAction: () {},
            onFermer: () {},
            libelleFermer: AppStrings.notifBanniereFermer,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionEtatsVides extends StatelessWidget {
  const _SectionEtatsVides();

  static void _rien() {}

  @override
  Widget build(BuildContext context) {
    return const DevSection(
      titre: 'EmptyState',
      note: 'Jamais muet : un titre, une explication, et une sortie.',
      children: <Widget>[
        DevSpecimen(
          nom: 'vide sans action',
          child: EmptyState(
            titre: AppStrings.videPropositionsTitre,
            texte: AppStrings.videPropositionsTexte,
          ),
        ),
        DevSpecimen(
          nom: 'vide avec action',
          child: EmptyState(
            titre: AppStrings.videTitreGenerique,
            texte: AppStrings.videTexteGenerique,
            libelleAction: 'Saisir octobre',
            onAction: _rien,
          ),
        ),
        DevSpecimen(
          nom: 'erreur (annoncée)',
          child: EmptyState.erreur(onAction: _rien),
        ),
        DevSpecimen(
          nom: 'hors ligne',
          child: EmptyState.horsLigne(onAction: _rien),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionChargement extends StatelessWidget {
  const _SectionChargement();

  @override
  Widget build(BuildContext context) {
    return const DevSection(
      titre: 'LoadingSkeleton',
      note:
          'L\'ossature du contenu attendu, jamais une roue. Le balayage '
          'disparaît sous Reduce Motion.',
      children: <Widget>[
        DevSpecimen(
          nom: 'lignes',
          child: LoadingSkeleton(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonLigne(largeur: 220, hauteur: AppSpacing.xl),
                SizedBox(height: AppSpacing.sm),
                SkeletonLigne(),
                SizedBox(height: AppSpacing.sm),
                SkeletonLigne(largeur: 160),
              ],
            ),
          ),
        ),
        DevSpecimen(
          nom: 'bloc',
          child: LoadingSkeleton(child: SkeletonBloc()),
        ),
        DevSpecimen(
          nom: 'grille du mois',
          child: LoadingSkeleton(child: SkeletonGrilleMois(jours: 14)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionMesures extends StatelessWidget {
  const _SectionMesures();

  static void _rien() {}

  @override
  Widget build(BuildContext context) {
    return const DevSection(
      titre: 'AppDivider · CountStat · SaveIndicator',
      note: 'Le filet, le compteur et l\'état d\'enregistrement.',
      children: <Widget>[
        DevSpecimen(nom: 'filet décoratif', child: AppDivider()),
        DevSpecimen(
          nom: 'filet d\'en-tête collant (porteur d\'état)',
          child: AppDivider.enTete(),
        ),
        DevSpecimen(
          nom: 'filet vertical',
          child: SizedBox(height: 48, child: AppDivider.vertical()),
        ),
        DevSpecimen(
          nom: 'compteurs',
          child: DevRangee(
            children: <Widget>[
              CountStat(
                libelle: AppStrings.compteurJours,
                valeur: 2,
                plafond: 3,
              ),
              CountStat(libelle: AppStrings.compteurNuits, valeur: 0),
              CountStat(libelle: AppStrings.compteurWeekends, valeur: 1),
              CountStat(
                libelle: AppStrings.compteurJours,
                valeur: 11,
                plafond: 31,
                grand: true,
              ),
            ],
          ),
        ),
        DevSpecimen(
          nom: 'enregistrement',
          child: DevRangee(
            children: <Widget>[
              SaveIndicator(etat: SyncEtat.repos),
              SaveIndicator(etat: SyncEtat.enregistrement),
              SaveIndicator(etat: SyncEtat.enregistre),
              SaveIndicator(etat: SyncEtat.horsLigne),
              SaveIndicator(etat: SyncEtat.echec, onReessayer: _rien),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionOssature extends StatelessWidget {
  const _SectionOssature();

  @override
  Widget build(BuildContext context) {
    return const DevSection(
      titre: 'AppScaffold',
      note:
          'Barre basse en compact, rail au-delà. Libellés toujours visibles, '
          'pastille plafonnée à 9+.',
      children: <Widget>[
        DevSpecimen(
          nom: 'compact, membre, 3 non lues',
          child: _Fenetre(
            // 360 dp : la largeur du plus petit téléphone réellement visé.
            largeur: 360,
            hauteur: 380,
            admin: false,
            nonLues: 3,
          ),
        ),
        DevSpecimen(
          nom: 'compact, admin, 12 non lues (pastille « 9+ »)',
          child: _Fenetre(
            largeur: 360,
            hauteur: 380,
            admin: true,
            nonLues: 12,
          ),
        ),
        DevSpecimen(
          nom: 'medium, rail',
          child: _Fenetre(
            largeur: 640,
            hauteur: 380,
            admin: true,
            nonLues: 0,
          ),
        ),
      ],
    );
  }
}

/// Une fenêtre simulée : `AppScaffold` a besoin d'une largeur réelle pour
/// choisir sa navigation, donc le catalogue lui en fabrique une.
class _Fenetre extends StatelessWidget {
  const _Fenetre({
    required this.largeur,
    required this.hauteur,
    required this.admin,
    required this.nonLues,
  });

  final double largeur;
  final double hauteur;
  final bool admin;
  final int nonLues;

  @override
  Widget build(BuildContext context) {
    final destinations = AppDestination.pour(
      admin: admin,
      boiteNonLues: nonLues,
    );

    // Une fenêtre simulée grandit avec l'échelle de texte : à 2.0, un
    // téléphone réel est équivalent à un écran deux fois plus petit, et la
    // vignette doit rester une vignette lisible, pas une maquette tronquée.
    final facteur = MediaQuery.textScalerOf(context).scale(16) / 16;
    final largeurEffective = largeur * facteur;
    final hauteurEffective = hauteur * facteur;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.statuts.filetDecoratif),
        borderRadius: AppRadius.controleRadius,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.controleRadius,
        child: SizedBox(
          width: largeurEffective,
          height: hauteurEffective,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: Size(largeurEffective, hauteurEffective),
              viewPadding: EdgeInsets.zero,
              padding: EdgeInsets.zero,
            ),
            child: AppScaffold(
              titre: 'Octobre 2026',
              destinations: destinations,
              indexSelectionne: 0,
              onDestination: (_) {},
              banniere: const AppBanner(
                variante: AppBannerVariante.information,
                texte: 'Saisie ouverte jusqu\'au 15 septembre.',
              ),
              child: const SingleChildScrollView(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CountStat(
                  libelle: AppStrings.compteurJours,
                  valeur: 11,
                  plafond: 31,
                  grand: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// La sortie d'un écran sans ossature de navigation, dans ses deux états de
/// pile (ticket 052).
///
/// Chaque spécimen porte **son propre routeur** : `BoutonRetour` lit la pile
/// de navigation dès sa construction, et la lui fabriquer est la seule façon
/// de montrer les deux formes côte à côte dans un catalogue.
class _SectionRetour extends StatelessWidget {
  const _SectionRetour();

  @override
  Widget build(BuildContext context) {
    return const DevSection(
      titre: 'BoutonRetour',
      note:
          'Flèche seule quand il y a une pile à dépiler, flèche suivie du mot '
          '« Accueil » quand il n\'y en a pas. Même place, seul le mot '
          'change — et à l\'échelle 2.0 sur un téléphone étroit, le mot tombe '
          'et la flèche reste.',
      children: <Widget>[
        DevRangee(
          children: <Widget>[
            DevSpecimen(
              nom: 'pile pleine — la flèche dépile',
              child: _FenetreRetour(pilePleine: true),
            ),
            DevSpecimen(
              nom: 'pile vide — lien profond, URL collée, rechargement',
              child: _FenetreRetour(pilePleine: false),
            ),
          ],
        ),
      ],
    );
  }
}

/// Une barre d'application isolée, avec la pile qu'on lui demande.
class _FenetreRetour extends StatefulWidget {
  const _FenetreRetour({required this.pilePleine});

  /// Vrai : la barre s'ouvre sur une route enfant, il y a donc de quoi
  /// dépiler. Faux : elle s'ouvre à la racine, comme un lien profond.
  final bool pilePleine;

  @override
  State<_FenetreRetour> createState() => _FenetreRetourState();
}

class _FenetreRetourState extends State<_FenetreRetour> {
  static const String _detour = 'detour';

  late final GoRouter _routeur = _fabriquerRouteur();

  /// Le routeur du spécimen, **posé sur sa pile à la main**.
  ///
  /// `initialLocation` ne conviendrait pas : il transite par le fournisseur
  /// d'information de route, que ce spécimen n'a justement pas (voir [build]),
  /// et sur le web il serait de toute façon écrasé par l'adresse réelle de la
  /// page — `/dev/components`, qui ne correspond à aucune route d'ici.
  /// `currentConfiguration` est la même valeur que `Router` aurait fini par
  /// donner au délégué, sans le détour par la plateforme.
  GoRouter _fabriquerRouteur() {
    final routeur = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.accueil,
          // Le nom de repli de `BoutonRetour` : sans lui, presser la sortie en
          // pile vide chercherait une route qui n'existe pas ici.
          name: AppRoutes.accueilName,
          builder: (context, state) => const _BarreSeule(titre: 'Accueil'),
          routes: <RouteBase>[
            GoRoute(
              path: _detour,
              builder: (context, state) =>
                  const _BarreSeule(titre: 'Notifications'),
            ),
          ],
        ),
      ],
    );
    routeur.routerDelegate.currentConfiguration = routeur.configuration
        .findMatch(
          Uri.parse(widget.pilePleine ? '/$_detour' : AppRoutes.accueil),
        );
    return routeur;
  }

  @override
  void dispose() {
    _routeur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Une fenêtre simulée grandit avec l'échelle de texte, comme celle de
    // l'ossature : à 2.0, un téléphone réel équivaut à un écran deux fois plus
    // petit, et c'est là que le mot « Accueil » doit tomber.
    final facteur = MediaQuery.textScalerOf(context).scale(16) / 16;
    final largeur = 320 * facteur;
    final hauteur = 96 * facteur;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.statuts.filetDecoratif),
        borderRadius: AppRadius.controleRadius,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.controleRadius,
        child: SizedBox(
          width: largeur,
          height: hauteur,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: Size(largeur, hauteur),
              viewPadding: EdgeInsets.zero,
              padding: EdgeInsets.zero,
            ),
            // **Un `Router` nu, sans fournisseur ni analyseur d'information
            // de route.** Une application imbriquée en aurait un : `Router`
            // rapporte alors l'adresse de son délégué à la plateforme dès la
            // première image, quelle que soit sa profondeur dans l'arbre, et
            // ouvrir le catalogue réécrivait la barre d'adresse en « / » ou
            // « /detour » — un rechargement ne revenait plus ici. Un seul
            // `Router` écrit l'URL, celui de l'application.
            //
            // Ce qu'il en coûte : `go` et `goNamed` passent par ce
            // fournisseur absent et ne font donc rien ici. La flèche de la
            // pile pleine dépile bien — `pop` parle au délégué — et la sortie
            // de la pile vide mène à l'accueil, qui est déjà l'écran affiché :
            // les deux spécimens montrent à l'écran ce qu'ils promettent.
            child: Router<RouteMatchList>(
              routerDelegate: _routeur.routerDelegate,
            ),
          ),
        ),
      ),
    );
  }
}

/// Le spécimen lui-même : une barre, sa sortie, son titre.
class _BarreSeule extends StatelessWidget {
  const _BarreSeule({required this.titre});

  final String titre;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BoutonRetour(),
        leadingWidth: BoutonRetour.largeur(context),
        title: Text(titre),
      ),
      body: const SizedBox.expand(),
    );
  }
}
