import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/plateforme/telechargement.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/export_providers.dart';

/// **« Exporter mes données »**, et la phrase qui dit ce que contient le
/// fichier.
///
/// Un seul composant pour ses deux places : le bloc « Ton compte » de l'écran
/// de profil, et la feuille de suppression — dernière sortie avant le point de
/// non-retour (`design/034-rgpd-export.md § 1`). Le bouton n'a pas deux
/// comportements selon l'endroit : il demande le fichier, il le range, il dit
/// ce qu'il a fait.
///
/// **Ce qu'il dit compte autant que ce qu'il fait.** Dans une PWA installée, il
/// n'y a pas de barre de téléchargement : si l'écran ne nomme pas le fichier
/// enregistré, rien ne le fait, et la personne reste sans savoir si son export
/// existe. D'où la ligne d'état annoncée (`liveRegion`) sous le bouton, et le
/// nom du fichier dedans.
class BoutonExportDonnees extends ConsumerWidget {
  const BoutonExportDonnees({super.key, this.aideVisible = true});

  /// La phrase d'aide sous le bouton. Masquée dans la feuille de suppression,
  /// où le volet qui précède dit déjà de quoi il s'agit : deux explications
  /// l'une sous l'autre ne s'additionnent pas, elles se concurrencent.
  final bool aideVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final etat = ref.watch(exportControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PrimaryButton(
          libelle: AppStrings.exportBouton,
          variante: PrimaryButtonVariante.secondaire,
          icone: Icons.download_outlined,
          chargement: etat.enCours,
          onPressed: () =>
              unawaited(ref.read(exportControllerProvider.notifier).exporter()),
        ),
        if (aideVisible) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppStrings.exportAide,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_phrase(etat) case final String phrase) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _Resultat(
            texte: phrase,
            icone: switch ((etat.echec != null, etat.enCours)) {
              (true, _) => Icons.error_outline,
              (false, true) => Icons.hourglass_top,
              (false, false) => Icons.check_circle_outline,
            },
            enErreur: etat.echec != null,
          ),
        ],
      ],
    );
  }

  /// Ce qu'il y a à dire, ou `null` quand il n'y a rien à dire.
  ///
  /// **Un partage refermé ne dit rien.** Ce n'est pas une panne, c'est un
  /// choix, et annoncer une erreur à qui vient d'annuler lui apprend à ne plus
  /// lire les messages (`design/034-rgpd-export.md § 4`).
  static String? _phrase(EtatExport etat) {
    if (etat.enCours) return AppStrings.exportEnCours;
    if (etat.message case final String erreur) return erreur;
    return switch (etat.resultat) {
      ResultatTelechargement.enregistre => AppStrings.exportEnregistre(
        etat.nomFichier ?? '',
      ),
      ResultatTelechargement.partage => AppStrings.exportPartage,
      ResultatTelechargement.annule => null,
      ResultatTelechargement.impossible => null,
      null => null,
    };
  }
}

/// Le résultat, **sur place**, sous le bouton — jamais dans un message passager
/// qui part avant qu'on ait fini de le lire. Porté par icône + libellé, la
/// couleur en quatrième (`DESIGN.md § Do's`).
class _Resultat extends StatelessWidget {
  const _Resultat({
    required this.texte,
    required this.icone,
    required this.enErreur,
  });

  final String texte;
  final IconData icone;
  final bool enErreur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encre = enErreur
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icone, size: AppTouch.icone, color: encre),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              texte,
              style: theme.textTheme.bodyMedium?.copyWith(color: encre),
            ),
          ),
        ],
      ),
    );
  }
}
