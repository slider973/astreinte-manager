import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_spacing.dart';
import 'app_scaffold.dart';

/// La colonne de navigation du grand écran (`design/061 § 5`).
///
/// Ce que le rail étendu faisait à la verticale — icône au-dessus du libellé,
/// pastille autour de l'icône seule — la colonne le fait à l'horizontale :
/// **le libellé à côté de l'icône, la pastille sur toute la largeur de
/// l'élément**. C'est la seule différence de fond avec le rail, et c'est ce
/// que la référence du propriétaire montre.
///
/// Elle est bâtie sur `NavigationDrawer`, dont le thème a été réglé au
/// chantier 061a pour cette place précise : pastille `primary-container`,
/// glyphe `on-primary-container`, rayon `controle`, aucune ombre. Le thème
/// local qui l'enveloppe ne fait qu'ajouter ce qu'une colonne large ne peut
/// pas deviner — sa largeur, la taille de sa pastille, et l'encre du libellé
/// choisi, qui suit son icône sur `on-primary-container`.
///
/// Ni champ de recherche, ni boîte promotionnelle : ce que la référence porte
/// à ces deux places n'a pas d'objet ici (`design/061 § 6`).
class ColonneNavigation extends StatelessWidget {
  const ColonneNavigation({
    required this.destinations,
    required this.indexSelectionne,
    required this.onDestination,
    super.key,
  });

  /// Largeur de la colonne : celle du rail étendu qu'elle remplace.
  ///
  /// Le libellé le plus large du produit, « Propositions », mesure 94 points
  /// en `libelle-action` ; il en reste 104 une fois retirés la marge de la
  /// pastille, l'icône et son écart. La mesure est dans le test.
  static const double largeur = 180;

  /// Marge horizontale de la pastille, de part et d'autre.
  static const double _margePastille = AppSpacing.md;

  /// Hauteur d'un élément, telle que Material la pose. C'est aussi la hauteur
  /// de la pastille : au-dessus du plancher tactile de 44.
  static const double _hauteurElement = 56;

  /// Ce qui précède le libellé dans un élément : l'écart de tête, l'icône,
  /// puis l'écart qui les sépare. Les trois valeurs sont celles de Material,
  /// qui ne les expose pas.
  static const double _avantLibelle = 16 + 24 + 12;

  final List<AppDestination> destinations;
  final int indexSelectionne;
  final ValueChanged<int> onDestination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const largeurLibelle = largeur - 2 * _margePastille - _avantLibelle;

    return SizedBox(
      width: largeur,
      child: DrawerTheme(
        data: DrawerThemeData(
          width: largeur,
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.controleRadius,
          ),
        ),
        child: NavigationDrawerTheme(
          data: NavigationDrawerTheme.of(context).copyWith(
            backgroundColor: scheme.surface,
            indicatorSize: const Size(
              largeur - 2 * _margePastille,
              _hauteurElement,
            ),
            // L'élément choisi porte l'encre de sa pastille, icône **et**
            // texte : 6,74:1 sur `primary-container`.
            labelTextStyle: WidgetStateProperty.resolveWith(
              (Set<WidgetState> etats) => theme.textTheme.labelLarge?.copyWith(
                color: etats.contains(WidgetState.selected)
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
          child: NavigationDrawer(
            selectedIndex: indexSelectionne,
            onDestinationSelected: onDestination,
            header: const _TeteDeColonne(),
            children: <Widget>[
              for (final destination in destinations)
                NavigationDrawerDestination(
                  icon: destination.glyphe(selectionnee: false),
                  selectedIcon: destination.glyphe(selectionnee: true),
                  label: SizedBox(
                    width: largeurLibelle,
                    child: Text(
                      destination.libelle,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le nom du produit, en tête de colonne. Pas de logo, pas de marque
/// empruntée : le mot suffit, et il dit où l'on est.
class _TeteDeColonne extends StatelessWidget {
  const _TeteDeColonne();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.md,
    ),
    child: Semantics(
      header: true,
      child: Text(
        AppStrings.appTitle,
        style: Theme.of(context).textTheme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}
