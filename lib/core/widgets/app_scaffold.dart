import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_breakpoints.dart';
import '../theme/app_spacing.dart';
import 'app_banner.dart';
import 'app_divider.dart';
import 'colonne_navigation.dart';
import 'entete_travail.dart';

/// Une destination de premier niveau.
///
/// Cinq au maximum (`DESIGN.md § Navigation`), ce qui est exactement le compte
/// pour un admin. Aucune destination ne s'ajoute sans en retirer une.
@immutable
class AppDestination {
  const AppDestination({
    required this.libelle,
    required this.icone,
    required this.iconeSelectionnee,
    required this.route,
    this.pastille,
  });

  final String libelle;

  /// Icône non sélectionnée (contour).
  final IconData icone;

  /// Icône sélectionnée (pleine).
  final IconData iconeSelectionnee;

  /// Nom de route `go_router`.
  final String route;

  /// Nombre affiché en pastille, plafonné à « 9+ ». `null` ou `0` : aucune
  /// pastille.
  final int? pastille;

  /// Les cinq destinations du produit, dans l'ordre imposé par `DESIGN.md`.
  /// « Admin » n'est présente que pour un administrateur de caserne.
  static List<AppDestination> pour({
    required bool admin,
    int propositionsEnAttente = 0,
  }) => <AppDestination>[
    const AppDestination(
      libelle: AppStrings.navMonMois,
      icone: Icons.calendar_month_outlined,
      iconeSelectionnee: Icons.calendar_month,
      route: 'monMois',
    ),
    AppDestination(
      libelle: AppStrings.navPropositions,
      icone: Icons.inbox_outlined,
      iconeSelectionnee: Icons.inbox,
      route: 'propositions',
      pastille: propositionsEnAttente,
    ),
    // **La destination de consultation** (ticket 027). Elle portait
    // « Planning » et l'icône `groups` au ticket 004 ; `groups` disait « les
    // autres » sur un écran qui, tant qu'un planning reste `published`, ne
    // montre que soi. Le ticket 023 y ajoutera la vue de la caserne derrière
    // un sélecteur à deux segments — d'où le mot « Astreintes », qui couvre
    // les deux (`design/027 § 4`).
    const AppDestination(
      libelle: AppStrings.navAstreintes,
      icone: Icons.event_available_outlined,
      iconeSelectionnee: Icons.event_available,
      route: 'astreintes',
    ),
    const AppDestination(
      libelle: AppStrings.navProfil,
      icone: Icons.person_outline,
      iconeSelectionnee: Icons.person,
      route: 'profil',
    ),
    if (admin)
      const AppDestination(
        libelle: AppStrings.navAdmin,
        icone: Icons.admin_panel_settings_outlined,
        iconeSelectionnee: Icons.admin_panel_settings,
        route: 'admin',
      ),
  ];

  /// La place de « Profil » dans la liste, admin ou non : « Admin » vient
  /// après lui, donc l'indice ne bouge pas d'un rôle à l'autre.
  static const int indexProfil = 3;

  /// Le glyphe de la destination, avec sa pastille chiffrée s'il y en a une.
  ///
  /// La barre, le rail et la colonne le construisent tous les trois de la
  /// même façon : une pastille qui ne serait chiffrée qu'à deux endroits sur
  /// trois serait un compte qui change de valeur selon la largeur de fenêtre.
  Widget glyphe({required bool selectionnee}) {
    final dessin = Icon(selectionnee ? iconeSelectionnee : icone);
    final compte = pastille ?? 0;
    if (compte == 0) return dessin;

    // La pastille chiffrée est plafonnée à « 9+ », et doublée d'un libellé
    // annoncé : « 3 propositions en attente ».
    return Badge.count(
      count: compte,
      maxCount: 9,
      child: Semantics(
        label: AppStrings.navPropositionsBadge(compte),
        child: dessin,
      ),
    );
  }
}

/// L'ossature de tout écran de premier niveau.
///
/// Topologie, de haut en bas : barre d'application (titre + actions), zone de
/// bannière (**au plus une**), contenu, navigation. Le contenu ne passe jamais
/// sous la navigation ni sous la zone sûre.
///
/// Composition selon la classe de fenêtre (`DESIGN.md § Points de rupture`) :
/// - `compact` : `NavigationBar` en bas, libellés toujours visibles, hauteur
///   72 dp + `viewPadding.bottom` (barre d'accueil iOS) ;
/// - `medium` : `NavigationRail` à gauche, icônes et libellés ;
/// - `expanded` et `large` : [ColonneNavigation] à gauche, [EnTeteTravail] en
///   tête de la zone de travail **à la place de la barre d'application**, plus
///   un [panneauLateral] permanent en `large` — un détail de créneau s'y
///   ouvre, **jamais dans une modale**.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.titre,
    required this.destinations,
    required this.indexSelectionne,
    required this.onDestination,
    required this.child,
    super.key,
    this.actions,
    this.banniere,
    this.panneauLateral,
    this.filActions,
    this.caserne,
    this.actionsEnTete = const <Widget>[],
  });

  final String titre;
  final List<AppDestination> destinations;
  final int indexSelectionne;
  final ValueChanged<int> onDestination;

  /// Le contenu de l'écran.
  final Widget child;

  /// Actions de la barre d'application.
  final List<Widget>? actions;

  /// Au plus une bannière. Le tri de priorité est
  /// [AppBannerVariante.prioritaire].
  final AppBanner? banniere;

  /// Panneau de détail permanent, affiché à droite en `large` uniquement.
  final Widget? panneauLateral;

  /// Barre d'actions collée en bas du contenu (bouton principal pleine
  /// largeur sur téléphone).
  final Widget? filActions;

  /// Le nom de la caserne. Sur grand écran, c'est lui qui titre la zone de
  /// travail : l'endroit où l'on est se dit alors par la destination choisie
  /// dans la colonne, et le titre de l'écran vit dans son contenu
  /// (`design/061 § 5`). `null` : le [titre] de l'écran reste.
  final String? caserne;

  /// La cloche et le compte, à droite de l'en-tête de la zone de travail.
  ///
  /// **Ignorées hors grand écran** : en `compact` et en `medium`, la barre
  /// d'application n'a pas la largeur de deux actions de plus, et la cloche y
  /// vit déjà dans [actions] des écrans qui la portent.
  final List<Widget> actionsEnTete;

  @override
  Widget build(BuildContext context) {
    assert(
      destinations.length <= 5,
      'Cinq destinations au maximum : aucune ne s\'ajoute sans en retirer '
      'une (DESIGN.md § Navigation).',
    );

    final classe = AppWindowClass.of(context);
    final media = MediaQuery.of(context);

    final corps = Column(
      children: <Widget>[
        // **La zone de bannière existe toujours**, même vide. Avec un enfant
        // conditionnel, l'apparition d'une bannière décalait tous les
        // suivants d'un cran : Flutter n'appariait plus les éléments, jetait
        // le contenu et le reconstruisait depuis zéro. La grille du mois y
        // perdait sa position de défilement, et les abonnements Riverpod de
        // ses lignes se réveillaient sur des éléments déjà démontés.
        banniere ?? const SizedBox.shrink(),
        Expanded(child: child),
        if (filActions != null)
          SafeArea(
            top: false,
            bottom: classe.estCompact,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: filActions,
            ),
          ),
      ],
    );

    final zoneTravail = classe.estLarge && panneauLateral != null
        ? Row(
            children: <Widget>[
              Expanded(child: corps),
              const AppDivider.vertical(),
              SizedBox(width: 360, child: panneauLateral),
            ],
          )
        : corps;

    // Contenu centré et borné sur poste admin ; pleine largeur ailleurs.
    final contenu = classe.estLarge
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.contenuMax,
              ),
              child: zoneTravail,
            ),
          )
        : zoneTravail;

    if (classe.estCompact) {
      return Scaffold(
        appBar: _barre(context),
        body: SafeArea(top: false, bottom: false, child: contenu),
        bottomNavigationBar: _barreNavigation(context, media),
      );
    }

    if (!classe.supporteDeuxVolets) {
      return Scaffold(
        appBar: _barre(context),
        body: SafeArea(
          top: false,
          child: Row(
            children: <Widget>[
              _rail(context),
              const AppDivider.vertical(),
              Expanded(child: contenu),
            ],
          ),
        ),
      );
    }

    // Grand écran : la navigation passe à côté du contenu, et l'en-tête avec
    // elle. Plus de barre d'application pleine largeur au-dessus des deux.
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: <Widget>[
            ColonneNavigation(
              destinations: destinations,
              indexSelectionne: indexSelectionne,
              onDestination: onDestination,
            ),
            const AppDivider.vertical(),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  EnTeteTravail(
                    titre: caserne ?? titre,
                    actions: <Widget>[...?actions, ...actionsEnTete],
                  ),
                  const AppDivider(),
                  Expanded(child: contenu),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _barre(BuildContext context) =>
      AppBar(title: Text(titre), actions: actions);

  Widget _barreNavigation(BuildContext context, MediaQueryData media) {
    return Padding(
      // La barre d'accueil iOS s'ajoute à la hauteur, elle ne la mange pas.
      padding: EdgeInsets.only(bottom: media.viewPadding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AppDivider(),
          NavigationBar(
            selectedIndex: indexSelectionne,
            onDestinationSelected: onDestination,
            destinations: <Widget>[
              for (final destination in destinations)
                NavigationDestination(
                  icon: destination.glyphe(selectionnee: false),
                  selectedIcon: destination.glyphe(selectionnee: true),
                  label: destination.libelle,
                  tooltip: _tooltip(destination),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rail(BuildContext context) {
    // Le rail n'est pas défilant par défaut : sur un téléphone en paysage
    // (600 × 360) ou à grande échelle de texte, cinq destinations ne tiennent
    // pas. On le rend défilant sans qu'il perde sa hauteur pleine.
    return LayoutBuilder(
      builder: (context, contraintes) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: contraintes.maxHeight),
          child: IntrinsicHeight(child: _railNu()),
        ),
      ),
    );
  }

  Widget _railNu() {
    return NavigationRail(
      selectedIndex: indexSelectionne,
      onDestinationSelected: onDestination,
      destinations: <NavigationRailDestination>[
        for (final destination in destinations)
          NavigationRailDestination(
            icon: destination.glyphe(selectionnee: false),
            selectedIcon: destination.glyphe(selectionnee: true),
            label: Text(destination.libelle),
          ),
      ],
    );
  }

  String? _tooltip(AppDestination destination) {
    final compte = destination.pastille ?? 0;
    return compte == 0
        ? destination.libelle
        : AppStrings.navPropositionsBadge(compte);
  }
}
