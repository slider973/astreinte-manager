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
    this.pastilles = false,
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

  /// **La forme du monde du pompier** (ticket 064c) : le mois choisi est une
  /// pastille pleine `primary-container`, les autres ne sont que leur texte.
  ///
  /// C'est la forme qu'ont déjà la bande de semaine de l'accueil et l'en-tête
  /// des dates de la matrice : un fond plein sous l'élément courant, rien
  /// sous les autres. Sur le papier doux, un bouton `surface` cerné par mois
  /// ferait une rangée de cinq cartes au-dessus d'une sixième — la carte de la
  /// grille —, là où il n'y a qu'un choix à porter.
  ///
  /// **Faux partout ailleurs** : la barre de commande et le suivi de l'admin
  /// gardent leurs boutons cernés, sur le papier blanc du registre, où rien
  /// ne les détacherait sans filet.
  final bool pastilles;

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
                pastille: pastilles,
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
    required this.pastille,
    required this.onChoisir,
  });

  final PeriodeSaisie periode;
  final bool choisi;
  final bool uneLigne;
  final bool pastille;
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

    // En pastille, le mois qui n'est pas choisi n'a ni fond ni filet : il est
    // son propre libellé, posé sur le papier doux. Le contraste de l'encre
    // sur ce papier est celui de tout le texte de l'écran, déjà mesuré.
    final fond = choisi
        ? theme.colorScheme.primaryContainer
        : pastille
        ? Colors.transparent
        : theme.colorScheme.surface;
    final bordure = pastille
        ? null
        : Border.all(
            color: choisi ? theme.colorScheme.primary : statuts.filetDecoratif,
            width: choisi ? AppStroke.etat : AppStroke.filet,
          );

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
              color: fond,
              borderRadius: AppRadius.controleRadius,
              border: bordure,
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
