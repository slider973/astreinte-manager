import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status.dart';
import 'hachures.dart';

/// Les six faits que la bannière sait porter, **par ordre de priorité**.
///
/// Une seule bannière à la fois : erreur > hors-ligne > lecture-seule >
/// verrouillé > attention > information. L'ordre de déclaration des valeurs
/// **est** cet ordre de priorité, ce qui rend [AppBannerVariante.prioritaire]
/// trivialement juste.
enum AppBannerVariante {
  erreur,
  horsLigne,
  lectureSeule,
  verrouille,
  attention,
  information;

  /// La variante la plus prioritaire d'une liste, ou `null` si la liste est
  /// vide. Sert à n'afficher qu'une bannière quand plusieurs faits sont vrais.
  static AppBannerVariante? prioritaire(Iterable<AppBannerVariante> variantes) {
    AppBannerVariante? gagnante;
    for (final variante in variantes) {
      if (gagnante == null || variante.index < gagnante.index) {
        gagnante = variante;
      }
    }
    return gagnante;
  }

  /// Vrai si la variante décrit un état persistant : elle n'est alors pas
  /// fermable, parce que la fermer mentirait sur l'état de l'écran.
  bool get persistante => this != AppBannerVariante.information;
}

/// **Le composant signature** : la bannière de contexte.
///
/// Bandeau pleine largeur sous la barre d'application, rayon 0, filet haut et
/// bas de 1 dp, **aucune ombre** (niveau 0). Elle porte les faits qui changent
/// tout ce qui est en dessous et qu'on doit comprendre sans lire : mois
/// verrouillé, caserne suspendue, hors ligne, échec d'enregistrement.
///
/// Les variantes `verrouille` et `lectureSeule` sont hachurées : l'état se
/// comprend sans lire la phrase, et il est **gris-encre, jamais rouge** — un
/// verrouillage est un fait, pas une panne.
class AppBanner extends StatelessWidget {
  const AppBanner({
    required this.variante,
    required this.texte,
    super.key,
    this.libelleAction,
    this.onAction,
  });

  final AppBannerVariante variante;

  /// Une phrase, courte, qui dit le fait et sa conséquence.
  final String texte;

  final String? libelleAction;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statuts = context.statuts;
    final sombre = theme.brightness == Brightness.dark;

    final (Color fond, Color encre, IconData icone, bool hachure) =
        switch (variante) {
          AppBannerVariante.erreur => (
            theme.colorScheme.errorContainer,
            theme.colorScheme.onErrorContainer,
            Icons.error_outline,
            false,
          ),
          AppBannerVariante.horsLigne => (
            statuts.sync(SyncEtat.horsLigne).fond,
            statuts.sync(SyncEtat.horsLigne).encre,
            Icons.cloud_off,
            false,
          ),
          AppBannerVariante.lectureSeule => (
            sombre ? AppColors.darkEtatNeutreFond : AppColors.etatNeutreFond,
            sombre ? AppColors.darkEtatNeutre : AppColors.etatNeutre,
            Icons.visibility,
            true,
          ),
          AppBannerVariante.verrouille => (
            statuts.periode(PeriodeEtat.verrouillee).fond,
            statuts.periode(PeriodeEtat.verrouillee).encre,
            Icons.lock,
            true,
          ),
          AppBannerVariante.attention => (
            sombre ? AppColors.darkEtatAttenteFond : AppColors.etatAttenteFond,
            sombre
                ? AppColors.darkEtatAttenteSurFond
                : AppColors.etatAttente,
            Icons.schedule,
            false,
          ),
          AppBannerVariante.information => (
            statuts.periode(PeriodeEtat.ouverte).fond,
            statuts.periode(PeriodeEtat.ouverte).encre,
            Icons.info_outline,
            false,
          ),
        };

    return Semantics(
      container: true,
      liveRegion: variante == AppBannerVariante.erreur,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fond,
          border: Border.symmetric(
            horizontal: BorderSide(color: encre.withValues(alpha: 0.35)),
          ),
        ),
        child: Stack(
          children: <Widget>[
            if (hachure) Positioned.fill(child: Hachures(encre: encre)),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icone, size: AppTouch.icone, color: encre),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      texte,
                      style: theme.textTheme.bodyMedium?.copyWith(color: encre),
                    ),
                  ),
                  if (onAction != null && libelleAction != null) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(foregroundColor: encre),
                      child: Text(libelleAction!),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
