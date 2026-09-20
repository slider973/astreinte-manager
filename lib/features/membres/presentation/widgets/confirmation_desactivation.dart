import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/membre_caserne.dart';

/// Demande confirmation avant de couper l'accès d'un membre.
///
/// La **seule** modale de l'écran, et elle est justifiée : c'est le seul acte
/// qui met quelqu'un dehors. Promouvoir, rétrograder, renommer sont réversibles
/// d'un geste et visibles aussitôt dans la liste ; les confirmer toutes ferait
/// du bruit et userait celle qui compte (`DESIGN.md § Don't` : « pas de modale
/// pour une tâche qui ne demande ni interruption ni protection »).
Future<bool> confirmerDesactivation({
  required BuildContext context,
  required MembreCaserne membre,
}) async {
  final confirme = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(AppStrings.membreDesactiverTitre(membre.libelle)),
      content: const Text(AppStrings.membreDesactiverTexte),
      actionsOverflowButtonSpacing: AppSpacing.entreCibles,
      actions: <Widget>[
        PrimaryButton(
          libelle: AppStrings.actionAnnuler,
          variante: PrimaryButtonVariante.secondaire,
          pleineLargeur: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        PrimaryButton(
          libelle: AppStrings.membreActionDesactiver,
          variante: PrimaryButtonVariante.danger,
          pleineLargeur: false,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirme ?? false;
}
