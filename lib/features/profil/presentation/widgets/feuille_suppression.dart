import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/suppression_providers.dart';
import 'bouton_export.dart';

/// Ouvre la feuille de suppression de compte. Rend `true` quand le compte a
/// bien été supprimé.
///
/// **Une feuille, et non un dialogue**, alors que `DESIGN.md § Don't` réserve
/// la modale à ce qui demande interruption ou protection : celle-ci demande les
/// deux, mais elle demande surtout **de la place pour lire**. Il y a quatre
/// choses à comprendre avant de toucher le bouton rouge — ce qui part, ce qui
/// reste, que c'est définitif, et comment sortir — et un `AlertDialog` de
/// téléphone n'en montre pas trois.
///
/// Pas de phrase à recopier pour confirmer : le public a une aisance numérique
/// variable, et deux touches réfléchies valent mieux qu'une formule recopiée
/// sans lire (`design/007-profil.md § 5.3`).
Future<bool> demanderSuppressionCompte(BuildContext context) async {
  final supprime = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Le geste de fermeture reste possible tant que rien n'est parti ; la
    // feuille se verrouille elle-même pendant l'appel (voir `_Corps`).
    builder: (BuildContext context) => const _Corps(),
  );
  return supprime ?? false;
}

class _Corps extends ConsumerWidget {
  const _Corps();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final etat = ref.watch(suppressionCompteControllerProvider);

    // La feuille ne ferme **que** la feuille : la session est fermée par
    // l'appelant, une fois cette route retirée de la pile (`BlocCompte`).
    Future<void> supprimer() async {
      final ok = await ref
          .read(suppressionCompteControllerProvider.notifier)
          .supprimer();
      if (!ok || !context.mounted) return;
      Navigator.of(context).pop(true);
    }

    return PopScope(
      // Pendant l'appel, ni le geste retour ni le glissement ne ferment la
      // feuille : la réponse du serveur arrive dans une seconde, et une
      // suppression dont on ne voit pas le résultat est pire que l'attente.
      canPop: !etat.enCours,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(
                    AppStrings.suppressionTitre,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  AppStrings.suppressionDefinitif,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                // Ce qui part d'abord, ce qui reste ensuite : c'est l'ordre
                // des questions qu'on se pose, et la seconde réponse est
                // rassurante — elle ne doit pas être lue en premier.
                const _Volet(
                  icone: Icons.delete_outline,
                  titre: AppStrings.suppressionCeQuiPartTitre,
                  texte: AppStrings.suppressionCeQuiPart,
                ),
                const SizedBox(height: AppSpacing.lg),
                const _Volet(
                  icone: Icons.history,
                  titre: AppStrings.suppressionCeQuiResteTitre,
                  texte: AppStrings.suppressionCeQuiReste,
                ),
                // **La dernière sortie avant le point de non-retour**
                // (ticket 034). Elle ne ferme pas la feuille, elle ne bloque
                // pas la suppression et elle n'en est pas une étape : forcer
                // un téléchargement avant de partir, c'est retenir quelqu'un
                // qui a décidé (`design/034-rgpd-export.md § 5.2`).
                const SizedBox(height: AppSpacing.lg),
                const _Volet(
                  icone: Icons.download_outlined,
                  titre: AppStrings.exportAvantSuppressionTitre,
                  texte: AppStrings.exportAvantSuppression,
                ),
                const SizedBox(height: AppSpacing.md),
                const BoutonExportDonnees(aideVisible: false),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  libelle: AppStrings.suppressionConfirmer,
                  variante: PrimaryButtonVariante.danger,
                  icone: Icons.delete_forever,
                  chargement: etat.enCours,
                  onPressed: () => unawaited(supprimer()),
                ),
                const SizedBox(height: AppSpacing.entreCibles),
                PrimaryButton(
                  libelle: AppStrings.suppressionAnnuler,
                  variante: PrimaryButtonVariante.secondaire,
                  onPressed: etat.enCours
                      ? null
                      : () => Navigator.of(context).pop(false),
                  // La raison est **annoncée** mais pas réécrite sous le
                  // bouton : c'est la ligne d'état commune aux deux, juste en
                  // dessous, qui la porte (`PrimaryButton.raisonVisible`).
                  raisonDesactivation: AppStrings.suppressionEnCours,
                  raisonVisible: false,
                ),
                if (etat.enCours || etat.message != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  _Resultat(
                    texte: etat.message ?? AppStrings.suppressionEnCours,
                    enErreur: etat.message != null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Un fait de la feuille : icône, titre, phrase. Porté par **icône + libellé**,
/// la couleur en quatrième (`DESIGN.md § Do's`) — et ici il n'y a pas de
/// couleur du tout : ce qui reste à la caserne n'est pas une alarme.
class _Volet extends StatelessWidget {
  const _Volet({required this.icone, required this.titre, required this.texte});

  final IconData icone;
  final String titre;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          icone,
          size: AppTouch.icone,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(titre, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                texte,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Le motif d'un refus, **dans la feuille**, sous le bouton — jamais dans un
/// message passager qui part avant qu'on ait fini de le lire.
class _Resultat extends StatelessWidget {
  const _Resultat({required this.texte, required this.enErreur});

  final String texte;
  final bool enErreur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encre = enErreur
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            enErreur ? Icons.error_outline : Icons.hourglass_top,
            size: AppTouch.icone,
            color: encre,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              texte,
              style: theme.textTheme.bodyMedium?.copyWith(color: encre),
            ),
          ),
        ],
      ),
    );
  }
}
