import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../dispos/domain/periode_saisie.dart';

/// Demande confirmation avant de fermer un mois avant l'heure.
///
/// La **seule** modale de l'écran, et elle est justifiée : verrouiller coupe
/// la saisie de toute la caserne d'un coup, sans que personne soit prévenu.
/// Rouvrir et ouvrir un mois, eux, passent par une feuille — ils demandent une
/// saisie, pas une protection (`DESIGN.md § Don't`).
///
/// Le texte dit ce que le verrouillage **ne** fait **pas** : l'admin garde la
/// main, et le mois peut être rouvert. Une confirmation qui ne dit que le
/// danger pousse à annuler une action légitime.
Future<bool> confirmerVerrouillage({
  required BuildContext context,
  required PeriodeSaisie periode,
}) async {
  final confirme = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(AppStrings.periodeVerrouillerTitre(periode.libelle)),
      content: const Text(AppStrings.periodeVerrouillerTexte),
      actionsOverflowButtonSpacing: AppSpacing.entreCibles,
      actions: <Widget>[
        PrimaryButton(
          libelle: AppStrings.actionAnnuler,
          variante: PrimaryButtonVariante.secondaire,
          pleineLargeur: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        PrimaryButton(
          libelle: AppStrings.periodeVerrouillerConfirmer,
          icone: Icons.lock_outline,
          pleineLargeur: false,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirme ?? false;
}
