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

    final etapes = ios
        ? const <String>[
            AppStrings.installIosEtape1,
            AppStrings.installIosEtape2,
            AppStrings.installIosEtape3,
          ]
        : const <String>[
            AppStrings.installAndroidEtape1,
            AppStrings.installAndroidEtape2,
            AppStrings.installAndroidEtape3,
          ];

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
        Semantics(
          header: true,
          child: Text(
            AppStrings.installEtapesTitre,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (int index = 0; index < etapes.length; index++) ...<Widget>[
          _Etape(numero: index + 1, texte: etapes[index]),
          if (index < etapes.length - 1) const SizedBox(height: AppSpacing.lg),
        ],
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

/// Un geste, numéroté. La numérotation porte l'information — l'ordre des
/// gestes — et non la décoration.
class _Etape extends StatelessWidget {
  const _Etape({required this.numero, required this.texte});

  final int numero;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: '$numero. $texte',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: AppRadius.caseRegistreRadius,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: SizedBox.square(
              dimension: AppTouch.badge,
              child: Center(
                child: Text('$numero', style: theme.textTheme.labelLarge),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(texte, style: theme.textTheme.bodyLarge),
            ),
          ),
        ],
      ),
    );
  }
}
