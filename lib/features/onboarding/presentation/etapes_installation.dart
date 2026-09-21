import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/plateforme/contexte_plateforme.dart';
import '../../../core/theme/app_spacing.dart';

/// Les gestes d'installation, pour le navigateur qu'on a sous la main.
///
/// Liste vide pour [NavigateurInstallation.autre] : on ne connaît pas sa
/// procédure, et trois gestes faux sont pires que rien. L'écran public
/// (`/install`) traite ce cas en écrivant où chercher, sans numéroter.
List<String> etapesInstallation(NavigateurInstallation navigateur) {
  return switch (navigateur) {
    NavigateurInstallation.safariIos => const <String>[
      AppStrings.installIosEtape1,
      AppStrings.installIosEtape2,
      AppStrings.installIosEtape3,
    ],
    NavigateurInstallation.chromeAndroid => const <String>[
      AppStrings.installAndroidEtape1,
      AppStrings.installAndroidEtape2,
      AppStrings.installAndroidEtape3,
    ],
    NavigateurInstallation.autre => const <String>[],
  };
}

/// La liste numérotée des gestes, titre compris.
///
/// Partagée par l'écran du parcours d'accueil (ticket 006) et par la page
/// publique `/install` (ticket 032) : les gestes sont les mêmes, seuls le
/// contexte et la sortie changent.
class EtapesInstallation extends StatelessWidget {
  const EtapesInstallation({required this.etapes, super.key});

  final List<String> etapes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
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
