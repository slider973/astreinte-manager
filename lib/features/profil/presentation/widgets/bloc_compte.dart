import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/session/deconnexion.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_divider.dart';
import '../../../../core/widgets/liens_legaux.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/suppression_providers.dart';
import 'bloc_regle.dart';
import 'bouton_export.dart';
import 'feuille_suppression.dart';

/// Les deux sorties du produit, dans l'ordre : celle dont on revient, puis
/// celle dont on ne revient pas.
///
/// Elles sont séparées par un filet et le bloc est **le dernier de l'écran** :
/// on ne tombe pas sur « Supprimer mon compte » en cherchant son numéro de
/// téléphone (`design/007-profil.md § 4`).
///
/// Le ticket 034 a rempli la place prévue : « Exporter mes données » est entre
/// le filet et la suppression — on récupère avant de partir, jamais après — et
/// les deux liens légaux ferment le bloc.
class BlocCompte extends ConsumerWidget {
  const BlocCompte({super.key});

  /// **La feuille se referme avant que la session tombe.**
  ///
  /// `showModalBottomSheet` pousse une route que `go_router` ne connaît pas :
  /// fermer la session pendant qu'elle est ouverte remplace toutes les pages du
  /// routeur en laissant la feuille seule au sommet de la pile, et l'écran reste
  /// **blanc** jusqu'au rechargement. Vu dans Chrome, PWA, après une vraie
  /// suppression (`design/007-profil.md § 8`).
  Future<void> _supprimer(BuildContext context, WidgetRef ref) async {
    final supprime = await demanderSuppressionCompte(context);
    if (!supprime) return;
    await ref
        .read(suppressionCompteControllerProvider.notifier)
        .fermerSession();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BlocRegle(
      titre: AppStrings.profilCompteTitre,
      enfants: <Widget>[
        const BoutonDeconnexion(),
        const SizedBox(height: AppSpacing.lg),
        const AppDivider(),
        const SizedBox(height: AppSpacing.lg),
        // L'export d'abord, la suppression ensuite : c'est l'ordre dans lequel
        // on quitte un produit qui détient des données
        // (`design/034-rgpd-export.md § 1`).
        const BoutonExportDonnees(),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          libelle: AppStrings.profilSupprimerCompte,
          variante: PrimaryButtonVariante.danger,
          icone: Icons.delete_outline,
          onPressed: () => unawaited(_supprimer(context, ref)),
        ),
        const SizedBox(height: AppSpacing.lg),
        const AppDivider(),
        const SizedBox(height: AppSpacing.sm),
        const LiensLegaux(),
      ],
    );
  }
}
