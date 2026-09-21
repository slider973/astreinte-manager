import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/plateforme/contexte_plateforme.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/ecran_simple.dart';
import '../../../core/widgets/primary_button.dart';
import 'etapes_installation.dart';

/// `/install` — l'aide à l'ajout à l'écran d'accueil, **sans compte**.
///
/// L'adresse se donne au téléphone, se colle dans un SMS, s'affiche sur une
/// feuille punaisée dans la salle de garde. Celui qui l'ouvre n'a pas de
/// session, et n'en a pas besoin : ajouter une icône à son écran d'accueil ne
/// regarde ni la base de données ni la caserne. La page s'ouvre donc dans tous
/// les états d'authentification, et **même quand l'application n'a reçu
/// aucune configuration Supabase** (`core/router/app_router.dart`).
///
/// Ce n'est pas [InstallationScreen] : celle-là appartient au parcours
/// d'accueil du ticket 006, elle est derrière la session et son bouton fait
/// avancer une suite d'étapes. Les trois gestes, eux, sont les mêmes et vivent
/// dans `etapes_installation.dart`.
class AideInstallationScreen extends ConsumerWidget {
  const AideInstallationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plateforme = ref.watch(contextePlateformeProvider);

    // Déjà installée : expliquer comment installer ce qui est installé serait
    // du bruit. On le dit, et on ouvre.
    if (plateforme.autonome) {
      return const _AideInstallation(
        titre: AppStrings.installDejaFaitTitre,
        children: <Widget>[_Paragraphe(AppStrings.installDejaFaitTexte)],
      );
    }

    final ios = plateforme.navigateur == NavigateurInstallation.safariIos;
    final etapes = etapesInstallation(plateforme.navigateur);

    if (etapes.isEmpty) {
      // Navigateur dont on ne connaît pas la procédure : où chercher, puis
      // l'aveu. Nommer le problème et la sortie, comme pour une erreur.
      return const _AideInstallation(
        titre: AppStrings.installTitre,
        children: <Widget>[
          _Paragraphe(AppStrings.installAutreIntro),
          SizedBox(height: AppSpacing.auDessusTitre),
          _SousTitre(AppStrings.installAutreTitre),
          SizedBox(height: AppSpacing.md),
          _Paragraphe(AppStrings.installAutreOu),
          SizedBox(height: AppSpacing.lg),
          _Paragraphe(AppStrings.installAutreAveu, second: true),
        ],
      );
    }

    return _AideInstallation(
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
        _Paragraphe(
          ios ? AppStrings.installIntroIos : AppStrings.installIntroAndroid,
        ),
        const SizedBox(height: AppSpacing.auDessusTitre),
        EtapesInstallation(etapes: etapes),
      ],
    );
  }
}

/// L'ossature commune aux trois cas : le contenu, puis une sortie unique.
///
/// Une seule action, et elle est primaire. Il n'y a rien à remettre à plus
/// tard sur une page qu'on a ouverte exprès.
class _AideInstallation extends StatelessWidget {
  const _AideInstallation({
    required this.titre,
    required this.children,
    this.banniere,
  });

  final String titre;
  final List<Widget> children;
  final AppBanner? banniere;

  @override
  Widget build(BuildContext context) {
    return EcranSimple(
      titre: titre,
      banniere: banniere,
      children: <Widget>[
        ...children,
        const SizedBox(height: AppSpacing.xxl),
        PrimaryButton(
          libelle: AppStrings.installOuvrir,
          icone: Icons.arrow_forward,
          onPressed: () => context.go(AppRoutes.accueil),
        ),
      ],
    );
  }
}

class _Paragraphe extends StatelessWidget {
  const _Paragraphe(this.texte, {this.second = false});

  final String texte;

  /// Texte d'appoint : `on-surface-variant` (7.94:1), jamais un gris inventé.
  final bool second;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      texte,
      style: second
          ? theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )
          : theme.textTheme.bodyLarge,
    );
  }
}

class _SousTitre extends StatelessWidget {
  const _SousTitre(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(texte, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
