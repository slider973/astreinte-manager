import 'package:flutter/material.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/periode_saisie.dart';

/// Le sélecteur de mois — et **le titre de l'écran**.
///
/// Le bouton sélectionné porte le nom du mois : il n'y a pas de second titre
/// qui le répéterait. C'est aussi là que vit la date limite, plutôt que dans
/// une bannière `information` permanente qui coûterait 48 dp de grille sur
/// tous les mois ouverts pour redire ce que le sélecteur dit déjà.
class SelecteurMois extends StatelessWidget {
  const SelecteurMois({
    required this.periodes,
    required this.selectionnee,
    required this.onChoisir,
    super.key,
    this.uneLigne = false,
  });

  /// Hauteur du bouton : le nom du mois, puis sa ligne d'état.
  static const double hauteurBouton = 64;

  /// La même chose sur une seule ligne : « Octobre 2026 · Verrouillé ».
  static const double hauteurBoutonUneLigne = AppTouch.cible;

  final List<PeriodeSaisie> periodes;
  final PeriodeSaisie? selectionnee;
  final ValueChanged<PeriodeSaisie> onChoisir;

  /// Plie le bouton sur une ligne : le mois et son état séparés d'un point
  /// médian, 48 points de haut au lieu de 64.
  ///
  /// La barre de commande de l'admin la demande sur grand écran, où elle doit
  /// tenir en deux rangées (chantier 061c). Sur téléphone, le bouton garde
  /// ses deux lignes : « Ouvert jusqu'au 15 sept. » à la suite du mois n'y
  /// tiendrait pas sans se replier, et un bouton qui se replie sur deux
  /// lignes n'est pas plus court qu'un bouton à deux lignes.
  final bool uneLigne;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: AppStrings.moisSelecteurLabel,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // La marge de page appartient à l'écran qui empile le sélecteur ;
        // dans une rangée de contrôles, elle ferait 32 points de vide.
        padding: uneLigne
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: <Widget>[
            for (final periode in periodes) ...<Widget>[
              _Bouton(
                periode: periode,
                choisi: periode.cle == selectionnee?.cle,
                uneLigne: uneLigne,
                onChoisir: () => onChoisir(periode),
              ),
              if (periode != periodes.last)
                const SizedBox(width: AppSpacing.entreCibles),
            ],
          ],
        ),
      ),
    );
  }
}

class _Bouton extends StatelessWidget {
  const _Bouton({
    required this.periode,
    required this.choisi,
    required this.uneLigne,
    required this.onChoisir,
  });

  final PeriodeSaisie periode;
  final bool choisi;
  final bool uneLigne;
  final VoidCallback onChoisir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statuts = context.statuts;
    final descripteur = statuts.periode(periode.statut);

    // Le mois choisi porte la pastille indigo de la sélection (ticket 061) :
    // le vert est réservé à l'accepté et au couvert.
    final encre = choisi
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      selected: choisi,
      label: choisi
          ? AppStrings.moisSelectionSemantique(periode.libelle)
          : periode.libelle,
      value: periode.ligneEtat,
      excludeSemantics: true,
      child: InkWell(
        onTap: choisi ? null : onChoisir,
        borderRadius: AppRadius.controleRadius,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: uneLigne
                ? SelecteurMois.hauteurBoutonUneLigne
                : SelecteurMois.hauteurBouton,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: choisi
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surface,
              borderRadius: AppRadius.controleRadius,
              border: Border.all(
                color: choisi
                    ? theme.colorScheme.primary
                    : statuts.filetDecoratif,
                width: choisi ? AppStroke.etat : AppStroke.filet,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: uneLigne
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          descripteur.icone,
                          size: AppTouch.iconePetite,
                          color: encre,
                          // Sur une ligne, « Ouvert » n'est plus écrit : le
                          // cadenas le dit seul, et un lecteur d'écran ne
                          // voit pas les cadenas. La valeur du bouton porte
                          // déjà la phrase entière ; ceci la double pour qui
                          // parcourt les icônes.
                          semanticLabel: periode.ouverte
                              ? AppStrings.moisOuvertCourt
                              : AppStrings.moisVerrouilleCourt,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          AppStrings.moisEtEtat(
                            periode.libelle,
                            periode.ligneEtatBreve,
                          ),
                          style: AppTextStyles.libelleChamp.copyWith(
                            color: encre,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          periode.libelle,
                          style: AppTextStyles.titreBloc.copyWith(color: encre),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              descripteur.icone,
                              size: AppTouch.iconePetite,
                              color: encre,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              periode.ligneEtat,
                              style: AppTextStyles.mention.copyWith(
                                color: encre,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
