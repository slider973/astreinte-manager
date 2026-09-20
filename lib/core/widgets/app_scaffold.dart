import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_breakpoints.dart';
import '../theme/app_spacing.dart';
import 'app_banner.dart';
import 'app_divider.dart';

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
    const AppDestination(
      libelle: AppStrings.navPlanning,
      icone: Icons.groups_outlined,
      iconeSelectionnee: Icons.groups,
      route: 'planning',
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
/// - `expanded` et `large` : rail étendu, plus un [panneauLateral] permanent
///   en `large` — un détail de créneau s'y ouvre, **jamais dans une modale**.
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
        ?banniere,
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

    return Scaffold(
      appBar: _barre(context),
      body: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            _rail(context, etendu: classe.supporteDeuxVolets),
            const AppDivider.vertical(),
            Expanded(child: contenu),
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
                  icon: _icone(destination, selectionnee: false),
                  selectedIcon: _icone(destination, selectionnee: true),
                  label: destination.libelle,
                  tooltip: _tooltip(destination),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rail(BuildContext context, {required bool etendu}) {
    return NavigationRail(
      extended: etendu,
      minExtendedWidth: 180,
      selectedIndex: indexSelectionne,
      onDestinationSelected: onDestination,
      destinations: <NavigationRailDestination>[
        for (final destination in destinations)
          NavigationRailDestination(
            icon: _icone(destination, selectionnee: false),
            selectedIcon: _icone(destination, selectionnee: true),
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

  Widget _icone(AppDestination destination, {required bool selectionnee}) {
    final icone = Icon(
      selectionnee ? destination.iconeSelectionnee : destination.icone,
    );
    final compte = destination.pastille ?? 0;
    if (compte == 0) return icone;

    // La pastille chiffrée est plafonnée à « 9+ », et doublée d'un libellé
    // annoncé : « 3 propositions en attente ».
    return Badge.count(
      count: compte,
      maxCount: 9,
      child: Semantics(
        label: AppStrings.navPropositionsBadge(compte),
        child: icone,
      ),
    );
  }
}
