import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/entete_section.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../core/widgets/primary_button.dart';
import '../../membres/domain/membres_providers.dart';
import '../domain/abonnement.dart';
import '../domain/abonnement_providers.dart';
import 'widgets/etat_abonnement_bloc.dart';
import 'widgets/formules_bloc.dart';

/// L'écran « Abonnement » de la destination Admin.
///
/// Trois blocs : l'état, les formules, la gestion. Pas une page de vente — une
/// fiche d'état avec deux portes de sortie (`design/029-stripe-abonnement.md`).
///
/// **Il fonctionne sans prestataire de paiement configuré**, et c'est le cas du
/// projet aujourd'hui : les tarifs restent affichés — un chef de centre en
/// essai a le droit de savoir ce que ça coûtera — et les deux boutons sont
/// inertes avec leur raison écrite à côté.
class AbonnementScreen extends ConsumerStatefulWidget {
  const AbonnementScreen({super.key, this.retour});

  /// Le paramètre `?paiement=` de l'URL, au retour du prestataire.
  final RetourPaiement? retour;

  @override
  ConsumerState<AbonnementScreen> createState() => _AbonnementScreenState();
}

class _AbonnementScreenState extends ConsumerState<AbonnementScreen> {
  static const String _routeAdmin = 'admin';

  /// Le retour n'est pris en compte qu'une fois : relire à chaque
  /// reconstruction ferait boucler l'écran sur lui-même.
  bool _retourTraite = false;

  AbonnementController get _controleur =>
      ref.read(abonnementControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    final retour = widget.retour;
    if (retour != null) {
      // Après le premier rendu : le contrôleur n'a pas encore son état, et
      // toucher un provider pendant `initState` est interdit.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _traiterRetour(retour),
      );
    }
  }

  Future<void> _traiterRetour(RetourPaiement retour) async {
    if (_retourTraite || !mounted) return;
    _retourTraite = true;

    // Le retour du prestataire arrive **en même temps** que l'écran s'ouvre :
    // la première lecture n'a pas encore abouti. L'attendre évite de perdre le
    // retour en silence, ce qui laisserait un chef de centre devant un écran
    // qui ne dit rien de son paiement.
    try {
      await ref.read(abonnementControllerProvider.future);
    } on Object {
      return;
    }
    if (!mounted) return;

    await _controleur.prendreEnCompteRetour(retour);
  }

  void _relire() => unawaited(_controleur.relire());

  Future<void> _souscrire(FormuleAbonnement formule) async {
    _annoncer(await _controleur.souscrire(formule));
  }

  Future<void> _gerer() async {
    _annoncer(await _controleur.gerer());
  }

  void _annoncer(ResultatAbonnement resultat) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(resultat.message),
          backgroundColor: resultat.reussi
              ? null
              : theme.colorScheme.errorContainer,
          showCloseIcon: true,
          closeIconColor: resultat.reussi
              ? null
              : theme.colorScheme.onErrorContainer,
        ),
      );
  }

  void _versDestination(int index, List<AppDestination> destinations) {
    if (destinations[index].route == _routeAdmin) {
      context.goNamed(AppRoutes.planningAdminName);
      return;
    }
    context.goNamed(
      AppRoutes.accueilName,
      queryParameters: <String, String>{AppRoutes.parametreOnglet: '$index'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(estAdminCaserneProvider);
    final asynchrone = ref.watch(abonnementControllerProvider);
    final destinations = AppDestination.pour(admin: admin);
    final indexAdmin = destinations.indexWhere(
      (AppDestination d) => d.route == _routeAdmin,
    );

    final vue = asynchrone.value;

    return AppScaffold(
      titre: AppStrings.abonnementTitre,
      destinations: destinations,
      indexSelectionne: indexAdmin < 0 ? 0 : indexAdmin,
      onDestination: (int index) => _versDestination(index, destinations),
      actions: <Widget>[
        if (admin)
          IconButton(
            onPressed: () => context.goNamed(AppRoutes.parametresName),
            icon: const Icon(Icons.tune),
            tooltip: AppStrings.parametresDepuisMembres,
          ),
        IconButton(
          onPressed: _relire,
          icon: const Icon(Icons.refresh),
          tooltip: AppStrings.abonnementRafraichir,
        ),
      ],
      banniere: _banniere(asynchrone: asynchrone, vue: vue),
      child: _corps(admin: admin, asynchrone: asynchrone, vue: vue),
    );
  }

  /// Une seule bannière, par ordre de priorité (`DESIGN.md § AppBanner`) :
  /// erreur, puis retour de paiement, puis essai expiré, puis l'absence de
  /// configuration.
  AppBanner? _banniere({
    required AsyncValue<VueAbonnement?> asynchrone,
    required VueAbonnement? vue,
  }) {
    // Une erreur d'action reste à l'écran tant qu'une autre action n'a pas eu
    // lieu : un `SnackBar` disparaît, une raison de refus doit rester lisible.
    final echec = vue?.echec;
    if (echec != null) {
      return AppBanner(
        variante: AppBannerVariante.erreur,
        texte: echec,
        libelleAction: AppStrings.actionReessayer,
        onAction: _relire,
      );
    }

    // Une erreur de relecture alors que l'état est déjà affiché ne vide pas
    // l'écran : ce qui était juste reste lisible.
    if (asynchrone.hasError && vue != null) {
      return AppBanner(
        variante: AppBannerVariante.erreur,
        texte: AppStrings.abonnementErreurTexte,
        libelleAction: AppStrings.actionReessayer,
        onAction: _relire,
      );
    }

    if (vue == null) return null;

    // L'abandon n'est **pas** un échec : quelqu'un a regardé le prix et fermé
    // l'onglet. Aucune bannière, aucun message (`design/029 § 4`).
    if (vue.retour == RetourPaiement.reussi) {
      return AppBanner(
        variante: AppBannerVariante.information,
        texte: vue.statutEnAttente
            ? AppStrings.abonnementPaiementEnAttente
            : AppStrings.abonnementPaiementEnregistre,
      );
    }

    if (vue.etat.abonnement.essaiExpire(
      maintenant: ref.read(horlogeAbonnementProvider)(),
    )) {
      return const AppBanner(
        variante: AppBannerVariante.attention,
        texte: AppStrings.abonnementEssaiExpireTexte,
      );
    }

    // Le cas d'aujourd'hui. `information` et jamais `erreur` : rien n'est
    // cassé, la caserne tourne.
    if (!vue.etat.configure) {
      return const AppBanner(
        variante: AppBannerVariante.information,
        texte: AppStrings.abonnementNonConfigureTexte,
      );
    }

    return null;
  }

  Widget _corps({
    required bool admin,
    required AsyncValue<VueAbonnement?> asynchrone,
    required VueAbonnement? vue,
  }) {
    if (!admin) {
      return const EmptyState(
        titre: AppStrings.abonnementTitre,
        texte: AppStrings.abonnementReserveAdmin,
        icone: Icons.lock_outline,
      );
    }

    if (vue == null) {
      return asynchrone.hasError
          ? EmptyState.erreur(
              texte: AppStrings.abonnementErreurTexte,
              onAction: _relire,
            )
          : const _SqueletteAbonnement();
    }

    final marge = AppWindowClass.of(context).margePage;

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: marge, vertical: AppSpacing.lg),
      children: <Widget>[
        const EnteteSection(
          titre: AppStrings.abonnementSectionEtat,
          premiere: true,
        ),
        EtatAbonnementBloc(
          abonnement: vue.etat.abonnement,
          maintenant: ref.read(horlogeAbonnementProvider)(),
        ),
        if (vue.etat.montreFormules) ...<Widget>[
          const EnteteSection(titre: AppStrings.abonnementSectionFormules),
          FormulesBloc(
            etat: vue.etat,
            formuleEnCours: vue.formuleEnCours,
            onSouscrire: (FormuleAbonnement formule) =>
                unawaited(_souscrire(formule)),
          ),
        ],
        // Le bloc de gestion n'apparaît que s'il mène quelque part : sans
        // client chez le prestataire, il n'y a rien à gérer.
        if (vue.etat.portailDisponible) ...<Widget>[
          const EnteteSection(titre: AppStrings.abonnementSectionGestion),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            libelle: AppStrings.abonnementGerer,
            variante: PrimaryButtonVariante.secondaire,
            icone: Icons.open_in_new,
            chargement: vue.portailEnCours,
            onPressed: () => unawaited(_gerer()),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Annoncer la sortie de l'application : une ouverture d'onglet ne
          // surprend jamais. L'icône `open_in_new` la double.
          Text(
            AppStrings.abonnementGererDetail,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

/// L'ossature des trois blocs. Jamais une roue au milieu de l'écran
/// (`DESIGN.md § Don't`).
class _SqueletteAbonnement extends StatelessWidget {
  const _SqueletteAbonnement();

  @override
  Widget build(BuildContext context) {
    final marge = AppWindowClass.of(context).margePage;

    return LoadingSkeleton(
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: marge,
          vertical: AppSpacing.lg,
        ),
        children: <Widget>[
          const SkeletonLigne(largeur: 120, hauteur: AppSpacing.xl),
          const SizedBox(height: AppSpacing.lg),
          const SkeletonLigne(largeur: 180, hauteur: AppSpacing.xxl),
          const SizedBox(height: AppSpacing.sm),
          const SkeletonLigne(largeur: 260),
          const SizedBox(height: AppSpacing.xxl),
          const SkeletonLigne(largeur: 120, hauteur: AppSpacing.xl),
          for (int formule = 0; formule < 2; formule++) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            const SkeletonLigne(largeur: 220),
            const SizedBox(height: AppSpacing.md),
            const SkeletonLigne(hauteur: AppTouch.bouton),
          ],
        ],
      ),
    );
  }
}
