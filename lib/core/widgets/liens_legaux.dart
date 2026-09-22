import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_strings.dart';
import '../router/app_router.dart';
import '../theme/app_spacing.dart';

/// Les deux liens vers la politique de confidentialité et les mentions
/// légales.
///
/// Dans `core/` et non dans une fonctionnalité : ils apparaissent sur l'écran
/// de profil **et** sur l'écran de connexion. Le second n'est pas décoratif —
/// c'est le seul écran qu'un visiteur non connecté voit, et une politique de
/// confidentialité joignable seulement une fois connecté ne remplit pas son
/// office (ticket 034).
///
/// Deux `TextButton` de 48 dp séparés de 8 dp, jamais deux mots collés dans un
/// `RichText` : sur un téléphone, avec des gants, un lien de la taille d'un mot
/// n'est pas une cible (`DESIGN.md § Cibles tactiles`).
class LiensLegaux extends StatelessWidget {
  const LiensLegaux({super.key, this.titreVisible = true});

  /// Le petit titre au-dessus des deux liens. Masqué là où le contexte le dit
  /// déjà — sous un formulaire de connexion, par exemple.
  final bool titreVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (titreVisible) ...<Widget>[
          Text(
            AppStrings.legalPiedTitre,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        // `Wrap` plutôt qu'une `Row` : à grande échelle de texte, les deux
        // libellés ne tiennent pas côte à côte sur un téléphone, et ils
        // passent alors l'un sous l'autre au lieu de déborder.
        const Wrap(
          spacing: AppSpacing.entreCibles,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            _Lien(
              libelle: AppStrings.legalConfidentialiteLien,
              route: AppRoutes.confidentialiteName,
            ),
            _Lien(
              libelle: AppStrings.legalMentionsLien,
              route: AppRoutes.mentionsName,
            ),
          ],
        ),
      ],
    );
  }
}

class _Lien extends StatelessWidget {
  const _Lien({required this.libelle, required this.route});

  final String libelle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.cible),
      child: TextButton(
        // **Un détour, pas une destination** (ticket 052). `push` pose la page
        // au-dessus de l'écran courant : la flèche ramène à l'onglet
        // « Profil » ou à l'écran de connexion d'où l'on vient, alors qu'un
        // `go` remettait la pile à plat et renvoyait tout le monde sur
        // « Mon mois ».
        onPressed: () => unawaited(context.pushNamed<void>(route)),
        child: Text(libelle),
      ),
    );
  }
}
