import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/preferences/reperes_locaux.dart';
import '../../../core/reseau/connectivite.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/slot_chip.dart';
import '../../dispos/domain/dispos_providers.dart';
import '../../dispos/domain/periode_saisie.dart';
import '../../membres/domain/membres_providers.dart';
import '../data/matrice_repository.dart';
import '../domain/cle_cellule.dart';
import '../domain/ligne_matrice.dart';
import '../domain/matrice_filtres.dart';
import '../domain/matrice_providers.dart';
import 'widgets/barre_commande_matrice.dart';
import 'widgets/confirmation_saisie_admin.dart';
import 'widgets/grille_matrice.dart';
import 'widgets/squelette_matrice.dart';
import 'widgets/vue_jour.dart';

/// **« Planning du mois »** — la vue centrale de l'admin.
///
/// Le seul écran du produit conçu **d'abord pour grand écran**, puis dégradé :
/// un chef de centre, assis, une fois par mois, une heure durant, doit couvrir
/// soixante-deux créneaux avec ce que soixante pompiers ont bien voulu donner.
///
/// Deux compositions pour une seule donnée : la **matrice** dès `expanded`, la
/// **vue par jour** en dessous et au-delà de ×1.6 d'échelle de texte. Ce n'est
/// pas une dégradation, c'est la même donnée autrement (brief § 6.6).
class MatriceScreen extends ConsumerStatefulWidget {
  const MatriceScreen({super.key, this.mois});

  /// L'échelle de texte au-delà de laquelle la matrice change de forme.
  static const double seuilVueJour = 1.6;

  /// Le mois porté par l'URL (`?mois=AAAA-MM`), s'il y en a un.
  final String? mois;

  @override
  ConsumerState<MatriceScreen> createState() => _MatriceScreenState();
}

class _MatriceScreenState extends ConsumerState<MatriceScreen> {
  static const String _routeAdmin = 'admin';

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_touche);
    _suivreUrl();
  }

  @override
  void didUpdateWidget(MatriceScreen ancien) {
    super.didUpdateWidget(ancien);
    if (widget.mois != ancien.mois) _suivreUrl();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_touche);
    super.dispose();
  }

  /// Aligne le mois affiché sur celui de l'URL, **y compris vers `null`** :
  /// l'entrée d'historique précédente n'avait pas de mois, c'est-à-dire le
  /// mois par défaut.
  void _suivreUrl() {
    final cle = widget.mois;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(moisMatriceProvider.notifier).definir(cle);
    });
  }

  /// `Échap` désarme la saisie. Le raccourci est posé sur le clavier et non
  /// sur un `Shortcuts` : il doit sortir du mode même quand le focus est dans
  /// le champ de recherche ou nulle part.
  bool _touche(KeyEvent evenement) {
    if (evenement is! KeyDownEvent) return false;
    if (evenement.logicalKey != LogicalKeyboardKey.escape) return false;
    if (!(ref.read(matriceControllerProvider).value?.modeArme ?? false)) {
      return false;
    }
    ref.read(matriceControllerProvider.notifier).armer(arme: false);
    return true;
  }

  MatriceController get _controleur =>
      ref.read(matriceControllerProvider.notifier);

  void _relire() => unawaited(_controleur.rafraichir());

  void _choisirMois(PeriodeSaisie periode) {
    _controleur.choisirMois(periode.cle);
    // Le mois voyage dans l'URL : le retour du navigateur ramène au mois
    // précédemment consulté. Les filtres, eux, n'y vont pas.
    context.goNamed(
      AppRoutes.planningAdminName,
      queryParameters: <String, String>{AppRoutes.parametreMois: periode.cle},
    );
  }

  /// Arme ou désarme la saisie par procuration.
  ///
  /// À l'armement **initial** — repère local par navigateur — un dialogue
  /// prévient que l'écriture est tracée. Ensuite, l'interrupteur arme sans
  /// rien demander : redemander à chaque fois apprend à cliquer « Oui » sans
  /// lire.
  Future<void> _armer({required bool arme}) async {
    if (!arme) {
      _controleur.armer(arme: false);
      return;
    }

    final reperes = ref.read(reperesLocauxProvider);
    if (!await reperes.dejaVu(RepereAccueil.saisieProcuration)) {
      if (!mounted) return;
      if (!await confirmerSaisieAdmin(context)) return;
      await reperes.marquerVu(RepereAccueil.saisieProcuration);
    }
    if (!mounted) return;
    _controleur.armer(arme: true);
  }

  void _versDestination(int index, List<AppDestination> destinations) {
    if (destinations[index].route == _routeAdmin) return;
    context.goNamed(
      AppRoutes.accueilName,
      queryParameters: <String, String>{AppRoutes.parametreOnglet: '$index'},
    );
  }

  @override
  Widget build(BuildContext context) {
    // Un mois qui n'existe plus ne vide pas l'écran : on retombe sur le mois
    // par défaut et on le dit d'une phrase.
    ref.listen<AsyncValue<EtatMatrice?>>(matriceControllerProvider, (
      AsyncValue<EtatMatrice?>? _,
      AsyncValue<EtatMatrice?> apres,
    ) {
      final echec = apres.error;
      if (echec is! EchecMatrice ||
          echec.erreur != ErreurMatrice.moisIntrouvable) {
        return;
      }
      // Reporté d'une image : modifier un provider ou ouvrir un `SnackBar`
      // pendant une construction est interdit, et pour de bonnes raisons.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controleur.choisirMois(null);
        _annoncer(AppStrings.matriceMoisIntrouvable);
      });
    });

    final admin = ref.watch(estAdminCaserneProvider);
    final asynchrone = ref.watch(matriceControllerProvider);
    final etat = asynchrone.value;
    final destinations = AppDestination.pour(admin: admin);
    final indexAdmin = destinations.indexWhere(
      (AppDestination d) => d.route == _routeAdmin,
    );
    final compact = AppWindowClass.of(context).estCompact;

    return AppScaffold(
      titre: AppStrings.matriceTitre,
      destinations: destinations,
      indexSelectionne: indexAdmin < 0 ? 0 : indexAdmin,
      onDestination: (int index) => _versDestination(index, destinations),
      actions: <Widget>[
        if (admin && compact) const _MenuAdmin(),
        if (admin && !compact) ..._liensAdmin(),
        IconButton(
          onPressed: _relire,
          icon: const Icon(Icons.refresh),
          tooltip: AppStrings.matriceRafraichir,
        ),
      ],
      banniere: _banniere(etat, asynchrone),
      // `filActions` et `panneauLateral` restent vides : ce sont les places du
      // bouton « Publier » (ticket 019) et du panneau de candidats (017).
      child: _corps(admin: admin, asynchrone: asynchrone, etat: etat),
    );
  }

  List<Widget> _liensAdmin() => <Widget>[
    IconButton(
      onPressed: () => context.goNamed(AppRoutes.membresName),
      icon: const Icon(Icons.group_outlined),
      tooltip: AppStrings.matriceVersMembres,
    ),
    IconButton(
      onPressed: () => context.goNamed(AppRoutes.parametresName),
      icon: const Icon(Icons.tune),
      tooltip: AppStrings.matriceVersParametres,
    ),
    IconButton(
      onPressed: () => context.goNamed(AppRoutes.periodesName),
      icon: const Icon(Icons.event_available_outlined),
      tooltip: AppStrings.matriceVersPeriodes,
    ),
  ];

  Widget _corps({
    required bool admin,
    required AsyncValue<EtatMatrice?> asynchrone,
    required EtatMatrice? etat,
  }) {
    if (!admin) {
      return const EmptyState(
        titre: AppStrings.matriceTitre,
        texte: AppStrings.matriceReserveAdmin,
        icone: Icons.lock_outline,
      );
    }

    if (etat == null) {
      if (asynchrone.isLoading) return const SqueletteMatrice();

      final echec = asynchrone.error;
      if (echec is EchecMatrice && echec.erreur == ErreurMatrice.reserveAdmin) {
        return const EmptyState(
          titre: AppStrings.matriceTitre,
          texte: AppStrings.matriceReserveAdmin,
          icone: Icons.lock_outline,
        );
      }
      if (asynchrone.hasError) {
        return EmptyState.erreur(
          texte: AppStrings.matriceErreurTexte,
          onAction: () => ref.invalidate(matriceControllerProvider),
        );
      }

      // Pas d'erreur et pas d'état : aucune période ouverte.
      return EmptyState(
        titre: AppStrings.matriceAucunePeriodeTitre,
        texte: AppStrings.matriceAucunePeriodeTexte,
        icone: Icons.event_busy_outlined,
        libelleAction: AppStrings.matriceAucunePeriodeAction,
        onAction: () => context.goNamed(AppRoutes.periodesName),
      );
    }

    if (etat.matrice.aucunMembre) {
      return EmptyState(
        titre: AppStrings.matriceAucunMembreTitre,
        texte: AppStrings.matriceAucunMembreTexte,
        icone: Icons.group_off_outlined,
        libelleAction: AppStrings.matriceAucunMembreAction,
        onAction: () => context.goNamed(AppRoutes.inviterName),
      );
    }

    final filtres = ref.watch(filtresMatriceProvider);
    final visibles = ref.watch(lignesVisiblesProvider);
    final periodes =
        ref.watch(periodesProvider).value ?? const <PeriodeSaisie>[];

    final echelle = MediaQuery.textScalerOf(context).scale(16) / 16;
    final classe = AppWindowClass.of(context);
    final matriceVisible =
        classe.supporteDeuxVolets && echelle <= MatriceScreen.seuilVueJour;

    final barre = BarreCommandeMatrice(
      periodes: periodes,
      periode: etat.periode,
      onMois: _choisirMois,
      filtres: filtres,
      onFiltres: ref.read(filtresMatriceProvider.notifier).definir,
      modeArme: etat.modeArme,
      onArmer: (bool arme) => unawaited(_armer(arme: arme)),
      raisonSaisieImpossible: _raisonSaisie(etat, matrice: matriceVisible),
      sync: etat.sync,
      onReessayer: _relire,
      total: etat.matrice.lignes.length,
      affiches: visibles.length,
      montrerLegende: matriceVisible,
    );

    // La vue par jour porte la barre de commande **dans son défilement** : un
    // téléphone n'a pas la hauteur pour deux blocs fixes.
    if (!matriceVisible && visibles.isNotEmpty) {
      return _zoneSaisie(
        arme: etat.modeArme,
        enfant: _vueJour(etat, visibles, filtres, barre),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        barre,
        Expanded(
          child: visibles.isEmpty
              ? _aucunResultat(filtres)
              : _zoneSaisie(
                  arme: etat.modeArme,
                  enfant: _matrice(etat, visibles, filtres),
                ),
        ),
      ],
    );
  }

  Widget _matrice(
    EtatMatrice etat,
    List<LigneMatrice> visibles,
    FiltresMatrice filtres,
  ) => GrilleMatrice(
    matrice: etat.matrice,
    lignes: visibles,
    annee: etat.periode.annee,
    mois: etat.periode.mois,
    commentaires: filtres.commentaires,
    aujourdhui: DateTime.now(),
    erreurs: etat.erreurs,
    saisieActive: _saisieActive(etat, matrice: true),
    onCase: _basculer,
  );

  Widget _vueJour(
    EtatMatrice etat,
    List<LigneMatrice> visibles,
    FiltresMatrice filtres,
    Widget barre,
  ) => VueJour(
    enTete: barre,
    matrice: etat.matrice,
    lignes: visibles,
    annee: etat.periode.annee,
    mois: etat.periode.mois,
    aujourdhui: DateTime.now(),
    commentaires: filtres.commentaires,
    erreurs: etat.erreurs,
    saisieActive: _saisieActive(etat, matrice: false),
    onCase: _basculer,
  );

  /// Le liseré du mode armé : **2 dp `tertiary` autour de la zone entière**.
  ///
  /// L'un des trois signaux du mode armé, avec la bannière et le curseur —
  /// deux d'entre eux ne demandent pas de lire.
  Widget _zoneSaisie({required bool arme, required Widget enfant}) {
    if (!arme) return enfant;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiary,
          width: AppStroke.etat,
        ),
      ),
      child: enfant,
    );
  }

  Widget _aucunResultat(FiltresMatrice filtres) => EmptyState(
    titre: AppStrings.matriceAucunResultatTitre,
    texte: AppStrings.matriceAucunResultatTexte(filtres.recherche),
    icone: Icons.search_off,
    libelleAction: AppStrings.matriceToutAfficher,
    onAction: ref.read(filtresMatriceProvider.notifier).effacerFiltres,
  );

  void _basculer(CleCellule cle) => unawaited(_controleur.basculer(cle));

  /// Vrai quand une case répond au clic : le mode est armé, la caserne est
  /// modifiable, le réseau est là, et la densité employée est actionnable
  /// dans ce contexte.
  bool _saisieActive(EtatMatrice etat, {required bool matrice}) =>
      etat.modeArme && _raisonSaisie(etat, matrice: matrice) == null;

  /// Pourquoi la saisie est impossible, ou `null`. **Un contrôle désactivé
  /// porte sa raison** (`DESIGN.md § Do's`).
  String? _raisonSaisie(EtatMatrice etat, {required bool matrice}) {
    if (etat.lectureSeule) return AppStrings.matriceSaisieIndisponibleSuspendue;
    if (!(ref.watch(enLigneProvider).value ?? true)) {
      return AppStrings.matriceSaisieIndisponibleHorsLigne;
    }
    // La densité dense n'est **jamais** servie au doigt : sur une tablette
    // tactile, on lit la matrice et on saisit depuis la vue par jour.
    if (matrice && !SlotChipDensite.dense.actionnableDans(context)) {
      return AppStrings.matriceSaisieIndisponibleTactile;
    }
    return null;
  }

  void _annoncer(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Semantics(liveRegion: true, child: Text(message)),
          showCloseIcon: true,
        ),
      );
  }

  // -------------------------------------------------------------------
  // La bannière — au plus une
  // -------------------------------------------------------------------

  AppBanner? _banniere(EtatMatrice? etat, AsyncValue<EtatMatrice?> asynchrone) {
    if (etat == null) return null;

    final horsLigne = !(ref.watch(enLigneProvider).value ?? true);
    final variantes = <AppBannerVariante>[
      if (etat.messageErreur != null) AppBannerVariante.erreur,
      if (horsLigne) AppBannerVariante.horsLigne,
      if (etat.lectureSeule) AppBannerVariante.lectureSeule,
      if (!etat.periode.ouverte) AppBannerVariante.verrouille,
      if (etat.modeArme) AppBannerVariante.attention,
      if (etat.matrice.vierge) AppBannerVariante.information,
    ];

    final gagnante = AppBannerVariante.prioritaire(variantes);
    if (gagnante == null) return null;

    return switch (gagnante) {
      AppBannerVariante.erreur => AppBanner(
        variante: AppBannerVariante.erreur,
        texte: etat.messageErreur!,
        libelleAction: AppStrings.actionReessayer,
        onAction: _relire,
      ),
      AppBannerVariante.horsLigne => const AppBanner(
        variante: AppBannerVariante.horsLigne,
        texte: AppStrings.horsLigneDetail,
      ),
      AppBannerVariante.lectureSeule => const AppBanner(
        variante: AppBannerVariante.lectureSeule,
        texte: AppStrings.lectureSeuleDetail,
      ),
      // **La matrice reste vivante sur un mois verrouillé** : le PRD § 6.3
      // donne explicitement à l'admin le droit d'y saisir, et la bannière le
      // dit en toutes lettres.
      AppBannerVariante.verrouille => AppBanner(
        variante: AppBannerVariante.verrouille,
        texte: AppStrings.matriceVerrouilleTexte(
          formaterDateLongue(
            etat.periode.verrouilleeLe ?? etat.periode.dateLimite,
          ),
        ),
      ),
      // **Non fermable tant que le mode est armé**, et sans action : elle
      // décrit un état persistant, et l'interrupteur qui le lève est juste
      // au-dessus d'elle. `Échap` le lève aussi.
      AppBannerVariante.attention => const AppBanner(
        variante: AppBannerVariante.attention,
        texte: AppStrings.matriceModeSaisieActif,
      ),
      AppBannerVariante.information => AppBanner(
        variante: AppBannerVariante.information,
        texte: AppStrings.matriceMoisViergeTexte(
          AppStrings.moisLongs[etat.periode.mois - 1],
        ),
      ),
    };
  }
}

/// Les trois autres écrans admin, repliés en menu **nommé** sur `compact` :
/// quatre icônes plus un titre ne tiennent pas sur 320 dp, et un menu nommé
/// vaut mieux qu'une icône devinée.
class _MenuAdmin extends StatelessWidget {
  const _MenuAdmin();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: AppStrings.navOuvrirMenu,
      onSelected: (String route) => context.goNamed(route),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: AppRoutes.membresName,
          child: Text(AppStrings.matriceVersMembres),
        ),
        const PopupMenuItem<String>(
          value: AppRoutes.parametresName,
          child: Text(AppStrings.matriceVersParametres),
        ),
        const PopupMenuItem<String>(
          value: AppRoutes.periodesName,
          child: Text(AppStrings.matriceVersPeriodes),
        ),
      ],
    );
  }
}
