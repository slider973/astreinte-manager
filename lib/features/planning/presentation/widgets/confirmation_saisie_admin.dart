import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/primary_button.dart';

/// La confirmation de **première fois** de la saisie par procuration.
///
/// Le cas rare où `DESIGN.md` autorise une modale : une écriture irréversible
/// sur les données d'un tiers, tracée en base, dont le membre n'est pas
/// prévenu.
///
/// **Une fois, et une seule.** L'appelant garde un repère local
/// (`RepereAccueil.saisieProcuration`) : redemander à chaque armement apprend
/// à cliquer « Oui » sans lire.
Future<bool> confirmerSaisieAdmin(BuildContext context) async {
  final confirme = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text(AppStrings.matriceConfirmationTitre),
      content: const Text(AppStrings.matriceConfirmationTexte),
      actionsOverflowButtonSpacing: AppSpacing.entreCibles,
      actions: <Widget>[
        PrimaryButton(
          libelle: AppStrings.matriceConfirmationAnnuler,
          variante: PrimaryButtonVariante.secondaire,
          pleineLargeur: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        PrimaryButton(
          libelle: AppStrings.matriceConfirmationValider,
          icone: Icons.edit_note,
          pleineLargeur: false,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirme ?? false;
}
