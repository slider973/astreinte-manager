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
    this.detail,
    this.icone,
    this.libelleAction,
    this.onAction,
    this.onFermer,
    this.libelleFermer,
  }) : assert(
         onFermer == null || variante == AppBannerVariante.information,
         'Une bannière qui décrit un état persistant ne se ferme pas : la '
         'fermer mentirait sur l\'état de l\'écran.',
       ),
       assert(
         onFermer == null || libelleFermer != null,
         'Le bouton de fermeture doit être nommé pour les lecteurs d\'écran.',
       );

  final AppBannerVariante variante;

  /// Une phrase, courte, qui dit le fait et sa conséquence.
  final String texte;

  /// Seconde ligne, en retrait typographique, quand le fait a un détail qui ne
  /// tient pas dans la première. Deux lignes au plus au total.
  final String? detail;

  /// Remplace l'icône de la variante. Réservé à un événement que l'icône de
  /// famille décrirait mal (une notification reçue, ticket 024).
  final IconData? icone;

  final String? libelleAction;
  final VoidCallback? onAction;

  /// Ferme la bannière. **Interdit sur un état persistant** : seule la
  /// variante `information` peut décrire un événement passager.
  final VoidCallback? onFermer;

  /// Le nom du bouton de fermeture, annoncé aux lecteurs d'écran.
  final String? libelleFermer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statuts = context.statuts;
    final sombre = theme.brightness == Brightness.dark;

    final (
      Color fond,
      Color encre,
      IconData iconeVariante,
      bool hachure,
    ) = switch (variante) {
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
      // Les deux thèmes prennent l'encre « sur fond » : depuis le ticket 061,
      // l'orange `etatAttente` ne fait plus que 4.22:1 sur son propre fond.
      // Il reste la teinte du texte **sur blanc** et des filets, pas celle
      // d'un texte posé dans le bloc.
      AppBannerVariante.attention => (
        sombre ? AppColors.darkEtatAttenteFond : AppColors.etatAttenteFond,
        sombre
            ? AppColors.darkEtatAttenteSurFond
            : AppColors.etatAttenteSurFond,
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
                  Icon(
                    icone ?? iconeVariante,
                    size: AppTouch.icone,
                    color: encre,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          texte,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: encre,
                            fontWeight: detail == null ? null : FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (detail != null)
                          Text(
                            detail!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: encre,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
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
                  if (onFermer != null) ...<Widget>[
                    const SizedBox(width: AppSpacing.xs),
                    // Pas d'info-bulle : la bannière peut être posée
                    // au-dessus du navigateur de l'application (ticket 024),
                    // où aucun `Overlay` n'existe. Le nom du bouton passe par
                    // la sémantique, qui n'en demande pas.
                    IconButton(
                      onPressed: onFermer,
                      icon: Icon(Icons.close, semanticLabel: libelleFermer),
                      iconSize: AppTouch.icone,
                      color: encre,
                      constraints: const BoxConstraints(
                        minWidth: AppTouch.cible,
                        minHeight: AppTouch.cible,
                      ),
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
