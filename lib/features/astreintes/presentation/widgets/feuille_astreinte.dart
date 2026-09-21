import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/l10n/format_date.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/astreinte.dart';
import 'bouton_ajout_calendrier.dart';

/// Ouvre le détail d'une journée d'astreinte.
///
/// Feuille de bas d'écran en compact, medium et expanded ; dialogue en large.
/// Même mécanique que `demanderRefus` au ticket 021, mêmes valeurs
/// d'élévation (`DESIGN.md § Elevation`).
///
/// [astreintes] porte **la journée**, pas un créneau : un pompier peut être de
/// jour et de nuit le même jour, et le calendrier n'a qu'une case par jour.
Future<void> ouvrirDetailAstreinte(
  BuildContext context, {
  required List<Astreinte> astreintes,
  required HeuresAffichage heures,
  String nomCaserne = '',
}) {
  if (astreintes.isEmpty) return Future<void>.value();

  final corps = DetailAstreinte(
    astreintes: astreintes,
    heures: heures,
    nomCaserne: nomCaserne,
  );

  if (AppWindowClass.of(context).estLarge) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: corps,
        ),
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => corps,
  );
}

/// Le contenu du détail.
///
/// **Il ne charge rien** : tout ce qu'il affiche a été lu avec la liste, donc
/// il s'ouvre aussi vite hors ligne qu'en ligne. C'est la raison pour laquelle
/// les équipiers sont lus d'avance plutôt qu'à l'ouverture de la feuille — et
/// c'est vérifiable par construction : ce widget n'a accès à aucun dépôt.
class DetailAstreinte extends StatelessWidget {
  const DetailAstreinte({
    required this.astreintes,
    required this.heures,
    super.key,
    this.nomCaserne = '',
  });

  final List<Astreinte> astreintes;
  final HeuresAffichage heures;

  /// Le nom de la caserne, pour l'intitulé et le lieu du fichier calendrier.
  /// Vide quand la caserne n'a pas pu être lue : l'intitulé se replie alors sur
  /// « Astreinte nuit » plutôt que de finir par un tiret orphelin.
  final String nomCaserne;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final jour = astreintes.first.jour;
    final triees = <Astreinte>[...astreintes]
      ..sort((Astreinte a, Astreinte b) => a.comparer(b));

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  AppStrings.astreintesDetailTitre(
                    dateAvecJourSemaine(jour),
                    jour.year,
                  ),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              for (final astreinte in triees) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                _BlocCreneau(
                  astreinte: astreinte,
                  heures: heures,
                  nomCaserne: nomCaserne,
                ),
                if (astreinte != triees.last) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  const AppDivider(),
                ],
              ],
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                libelle: AppStrings.astreintesFermer,
                variante: PrimaryButtonVariante.secondaire,
                pleineLargeur: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlocCreneau extends StatelessWidget {
  const _BlocCreneau({
    required this.astreinte,
    required this.heures,
    required this.nomCaserne,
  });

  final Astreinte astreinte;
  final HeuresAffichage heures;
  final String nomCaserne;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            StatusBadge.creneau(astreinte.creneau),
            Text(
              heures.intervalle(astreinte.creneau),
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _Equipiers(astreinte: astreinte),
        const SizedBox(height: AppSpacing.lg),
        // **Un bouton par créneau**, et pas un par feuille : la feuille porte
        // une journée, et un pompier peut être de jour **et** de nuit le même
        // jour — un bouton unique ne saurait pas lequel enregistrer
        // (`design/028-export-ics.md § 6`).
        BoutonAjoutCalendrier(
          astreinte: astreinte,
          heures: heures,
          nomCaserne: nomCaserne,
        ),
      ],
    );
  }
}

/// Les autres membres du créneau — **ou la phrase qui dit pourquoi ils ne sont
/// pas là**.
///
/// La RLS n'ouvre les attributions des autres que sur un planning `validated`
/// ou `archived` (`docs/SCHEMA.md § 4`). Tant qu'il est `published`, afficher
/// une liste vide se lirait « personne d'autre n'est de garde », ce qui est
/// faux.
class _Equipiers extends StatelessWidget {
  const _Equipiers({required this.astreinte});

  final Astreinte astreinte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!astreinte.equipiersConnus) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.hourglass_top,
            size: AppTouch.icone,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              AppStrings.astreintesEquipiersAttente,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    if (astreinte.equipiers.isEmpty) {
      return Text(
        AppStrings.astreintesSeul,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            AppStrings.astreintesEquipiersTitre,
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final nom in astreinte.equipiers)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.person_outline,
                  size: AppTouch.icone,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(nom, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}
