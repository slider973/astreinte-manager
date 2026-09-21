import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/session/deconnexion.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/primary_button.dart';
import 'bloc_regle.dart';
import 'feuille_suppression.dart';

/// Les deux sorties du produit, dans l'ordre : celle dont on revient, puis
/// celle dont on ne revient pas.
///
/// Elles sont séparées par un filet et le bloc est **le dernier de l'écran** :
/// on ne tombe pas sur « Supprimer mon compte » en cherchant son numéro de
/// téléphone (`design/007-profil.md § 4`).
///
/// Le ticket 034 pose « Exporter mes données » entre le filet et la
/// suppression : c'est la place prévue, et rien n'y est posé aujourd'hui.
class BlocCompte extends ConsumerWidget {
  const BlocCompte({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BlocRegle(
      titre: AppStrings.profilCompteTitre,
      enfants: <Widget>[
        const BoutonDeconnexion(),
        const SizedBox(height: AppSpacing.lg),
        const AppDivider(),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          libelle: AppStrings.profilSupprimerCompte,
          variante: PrimaryButtonVariante.danger,
          icone: Icons.delete_outline,
          onPressed: () => demanderSuppressionCompte(context),
        ),
      ],
    );
  }
}
