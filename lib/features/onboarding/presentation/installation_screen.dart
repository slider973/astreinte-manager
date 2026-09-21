import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/plateforme/contexte_plateforme.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/ecran_simple.dart';
import '../../../core/widgets/primary_button.dart';
import '../domain/parcours_accueil.dart';
import 'etapes_installation.dart';

/// « Ajouter à l'écran d'accueil », une fois et une seule.
///
/// Rien ne s'affiche si l'application tourne déjà en mode autonome : expliquer
/// comment installer ce qui est installé est du bruit. Sur iPhone, l'écran
/// insiste, parce que l'enjeu n'est pas le confort : **sans installation, iOS
/// n'envoie aucune notification**, donc aucune proposition d'astreinte.
class InstallationScreen extends ConsumerWidget {
  const InstallationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plateforme = ref.watch(contextePlateformeProvider);
    final ios = plateforme.navigateur == NavigateurInstallation.safariIos;

    Future<void> terminer() async {
      final suite = await ref
          .read(parcoursAccueilProvider)
          .apresLInstallation();
      if (!context.mounted) return;
      context.goNamed(suite);
    }

    return EcranSimple(
      titre: AppStrings.installTitre,
      // L'avertissement iOS n'est pas une erreur : c'est un fait qui change
      // tout ce qui suit, donc une bannière d'attention.
      banniere: ios
          ? const AppBanner(
              variante: AppBannerVariante.attention,
              texte: AppStrings.installAvertissementIos,
            )
          : null,
      children: <Widget>[
        Text(
          ios ? AppStrings.installIntroIos : AppStrings.installIntroAndroid,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.auDessusTitre),
        EtapesInstallation(etapes: etapesInstallation(plateforme.navigateur)),
        const SizedBox(height: AppSpacing.xxl),
        PrimaryButton(
          libelle: AppStrings.installTermine,
          icone: Icons.check,
          onPressed: () => unawaited(terminer()),
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: AlignmentDirectional.center,
          child: TextButton(
            onPressed: () => unawaited(terminer()),
            child: const Text(AppStrings.installPlusTard),
          ),
        ),
      ],
    );
  }
}
