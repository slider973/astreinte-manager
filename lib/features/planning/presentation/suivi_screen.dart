import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/reseau/connectivite.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_divider.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/status_badge.dart';
import '../../dispos/domain/dispos_providers.dart';
import '../../dispos/domain/periode_saisie.dart';
import '../../dispos/presentation/widgets/selecteur_mois.dart';
import '../../membres/domain/membres_providers.dart';
import '../domain/matrice_providers.dart';
import '../domain/suivi_planning.dart';
import '../domain/suivi_providers.dart';
import 'widgets/bloc_progression.dart';
import 'widgets/bloc_retardataires.dart';
import 'widgets/filtres_suivi.dart';
import 'widgets/indicateur_direct.dart';
import 'widgets/journee_suivi.dart';
import 'widgets/squelette_suivi.dart';

/// **« Suivi du planning »** — ce qui se passe après l'envoi.
///
/// Une colonne, du général au particulier : un chiffre en haut, des noms en
/// dessous. La tentation de la catégorie serait un tableau de bord de
/// graphiques ; ce qu'il faut à 21 h dans une salle de garde, c'est qui a
/// accepté, qui a refusé, et qui n'a rien dit.
///
/// C'est la cible du lien public `/admin/schedule/<AAAA-MM>`
/// (`docs/WORKFLOWS.md § 8`), qui retombait jusqu'ici sur les périodes faute
/// d'écran.
class SuiviScreen extends ConsumerStatefulWidget {
  const SuiviScreen({super.key, this.mois});

  /// Le mois porté par l'URL (`?mois=AAAA-MM`), s'il y en a un.
  final String? mois;

  @override
  ConsumerState<SuiviScreen> createState() => _SuiviScreenState();
}

class _SuiviScreenState extends ConsumerState<SuiviScreen> {
  static const String _routeAdmin = 'admin';

  @override
  void initState() {
    super.initState();
    _suivreUrl();
  }

  @override
  void didUpdateWidget(SuiviScreen ancien) {
    super.didUpdateWidget(ancien);
    if (widget.mois != ancien.mois) _suivreUrl();
  }

  /// Aligne le mois affiché sur celui de l'URL, **y compris vers `null`** : la
  /// même discipline qu'à la matrice, et le même provider de mois — les deux
  /// écrans travaillent le même mois et le retour du navigateur doit le dire.
  void _suivreUrl() {
    final cle = widget.mois;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(moisMatriceProvider.notifier).definir(cle);
    });
  }

  SuiviController get _controleur =>
      ref.read(suiviControllerProvider.notifier);

  void _choisirMois(PeriodeSaisie periode) {
    ref.read(moisMatriceProvider.notifier).definir(periode.cle);
    context.goNamed(
      AppRoutes.suiviName,
      queryParameters: <String, String>{AppRoutes.parametreMois: periode.cle},
    );
  }

  Future<void> _relancer({bool tout = false}) async {
    final resultat = await _controleur.relancer(tout: tout);
    if (!mounted || resultat == null) return;
    if (!resultat.nouvelle) {
      _annoncer(AppStrings.suiviRelanceDejaFaite);
      return;
    }
    _annoncer(
      tout
          ? AppStrings.suiviRattrapageFait(resultat.membres)
          : AppStrings.suiviRelanceFaite(resultat.membres),
    );
  }

  /// Pourquoi la relance est impossible, ou `null`. **Un contrôle désactivé
  /// porte sa raison** (`DESIGN.md § Do's`).
  String? _raisonRelance(EtatSuivi etat) {
    if (etat.lectureSeule) return AppStrings.lectureSeuleDetail;
    if (!(ref.watch(enLigneProvider).value ?? true)) {
      return AppStrings.suiviRelanceHorsLigne;
    }
    if (etat.suivi.etat != PlanningEtat.publie) {
      return AppStrings.suiviRelanceArchive;
    }
    return null;
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

  void _annoncer(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Semantics(liveRegion: true, child: Text(message)),
          showCloseIcon: true,
          duration: const Duration(seconds: 8),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(estAdminCaserneProvider);
    final asynchrone = ref.watch(suiviControllerProvider);
    final etat = asynchrone.value;
    final destinations = AppDestination.pour(admin: admin);
    final indexAdmin = destinations.indexWhere(
      (AppDestination d) => d.route == _routeAdmin,
    );
    final compact = AppWindowClass.of(context).estCompact;

    return AppScaffold(
      titre: AppStrings.suiviTitre,
      destinations: destinations,
      indexSelectionne: indexAdmin < 0 ? 0 : indexAdmin,
      onDestination: (int index) => _versDestination(index, destinations),
      actions: <Widget>[
        if (admin && compact) const _MenuAdmin(),
        if (admin && !compact)
          IconButton(
            onPressed: () => context.goNamed(AppRoutes.planningAdminName),
            icon: const Icon(Icons.grid_on_outlined),
            tooltip: AppStrings.matriceVersPlanning,
          ),
        IconButton(
          onPressed: () => unawaited(_controleur.rafraichir()),
          icon: const Icon(Icons.refresh),
          tooltip: AppStrings.matriceRafraichir,
        ),
      ],
      banniere: _banniere(etat),
      child: _corps(admin: admin, asynchrone: asynchrone, etat: etat),
    );
  }

  Widget _corps({
    required bool admin,
    required AsyncValue<EtatSuivi?> asynchrone,
    required EtatSuivi? etat,
  }) {
    if (!admin) {
      return const EmptyState(
        titre: AppStrings.suiviTitre,
        texte: AppStrings.suiviReserveAdmin,
        icone: Icons.lock_outline,
      );
    }

    if (etat == null) {
      if (asynchrone.isLoading) return const SqueletteSuivi();
      if (asynchrone.hasError) {
        return EmptyState.erreur(
          texte: AppStrings.suiviErreurTexte,
          onAction: () => ref.invalidate(suiviControllerProvider),
        );
      }
      return EmptyState(
        titre: AppStrings.matriceAucunePeriodeTitre,
        texte: AppStrings.matriceAucunePeriodeTexte,
        icone: Icons.event_busy_outlined,
        libelleAction: AppStrings.matriceAucunePeriodeAction,
        onAction: () => context.goNamed(AppRoutes.periodesName),
      );
    }

    final periodes =
        ref.watch(periodesProvider).value ?? const <PeriodeSaisie>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SelecteurMois(
          periodes: periodes,
          selectionnee: etat.periode,
          onChoisir: _choisirMois,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              StatusBadge.planning(etat.suivi.etat, tampon: etat.valideSousNosYeux),
              const Spacer(),
              IndicateurDirect(branche: etat.canalBranche),
            ],
          ),
        ),
        const AppDivider(),
        Expanded(child: _contenu(etat)),
      ],
    );
  }

  /// Ce qu'il y a à suivre, ou pourquoi il n'y a rien.
  Widget _contenu(EtatSuivi etat) {
    if (!etat.suivi.existe) {
      return EmptyState(
        titre: AppStrings.suiviAbsentTitre,
        texte: AppStrings.suiviAbsentTexte,
        icone: Icons.campaign_outlined,
        libelleAction: AppStrings.suiviAbsentAction,
        onAction: () => context.goNamed(AppRoutes.planningAdminName),
      );
    }

    if (!etat.suivi.suivable) {
      // Le suivi d'un brouillon n'a pas de sens : rien n'est parti.
      return EmptyState(
        titre: AppStrings.suiviBrouillonTitre,
        texte: AppStrings.suiviBrouillonTexte,
        icone: Icons.edit_note,
        libelleAction: AppStrings.suiviVersConstruction,
        onAction: () => context.goNamed(AppRoutes.planningAdminName),
      );
    }

    final journees = ref.watch(journeesVisiblesProvider);
    final retardataires = ref.watch(retardatairesProvider);
    final comptes = ref.watch(comptesSuiviProvider);
    final filtres = ref.watch(filtresSuiviProvider);

    // **Virtualisée.** La liste peut porter 3 720 lignes dans le pire cas ;
    // une `Column` de soixante-deux groupes les construirait toutes.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      itemCount: journees.length + 2,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              BlocProgression(progression: etat.suivi.progression),
              if (retardataires.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                BlocRetardataires(
                  retardataires: retardataires,
                  // **La base compte, l'écran nomme.** `assignments_late` est
                  // la seule définition du retard du produit ; la resservir
                  // depuis la vue évite deux chiffres pour une chose, et la
                  // relance vise de toute façon ce que la base voit, pas ce que
                  // la liste affiche.
                  compte: etat.suivi.progression.enRetard,
                  delaiHeures: etat.suivi.delaiRetardHeures,
                  enVol: etat.relance,
                  raisonInactif: _raisonRelance(etat),
                  onRelancer: () => unawaited(_relancer()),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FiltresSuiviBarre(
                selection: filtres,
                comptes: comptes,
                onBasculer: ref.read(filtresSuiviProvider.notifier).basculer,
              ),
            ],
          );
        }

        if (index == 1 && journees.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: EmptyState(
              titre: AppStrings.suiviTitre,
              texte: AppStrings.suiviFiltreVide(
                filtres.map((FiltreSuivi f) => f.libelle).join(', '),
              ),
              icone: Icons.filter_alt_off_outlined,
              libelleAction: AppStrings.suiviToutAfficher,
              onAction: ref.read(filtresSuiviProvider.notifier).tout,
            ),
          );
        }

        if (index > journees.length) return const SizedBox.shrink();
        return JourneeSuiviBloc(journee: journees[index - 1]);
      },
    );
  }

  // -------------------------------------------------------------------
  // La bannière — au plus une
  // -------------------------------------------------------------------

  AppBanner? _banniere(EtatSuivi? etat) {
    if (etat == null) return null;

    final horsLigne = !(ref.watch(enLigneProvider).value ?? true);
    final valide = etat.suivi.planning?.valideLe;

    // L'envoi de la publication n'a pas abouti et personne n'a encore rattrapé.
    // Le bandeau reste : il décrit un état persistant, et il porte l'action qui
    // le lève.
    final envoiManque =
        etat.suivi.planning != null &&
        ref.watch(alerteEnvoiProvider) == etat.suivi.planning!.id;

    final variantes = <AppBannerVariante>[
      if (etat.messageErreur != null || envoiManque) AppBannerVariante.erreur,
      if (horsLigne) AppBannerVariante.horsLigne,
      if (etat.lectureSeule) AppBannerVariante.lectureSeule,
      if (valide != null && etat.suivi.etat == PlanningEtat.valide)
        AppBannerVariante.information,
    ];

    final gagnante = AppBannerVariante.prioritaire(variantes);
    if (gagnante == null) return null;

    return switch (gagnante) {
      // Un envoi manqué passe devant une erreur de lecture : la lecture se
      // rattrape d'un bouton, les pompiers non prévenus attendent une action.
      AppBannerVariante.erreur => envoiManque
          ? AppBanner(
              variante: AppBannerVariante.erreur,
              texte: AppStrings.suiviEnvoiManque,
              libelleAction: AppStrings.suiviPrevenir,
              onAction: etat.relance || _raisonRelance(etat) != null
                  ? null
                  : () => unawaited(_relancer(tout: true)),
            )
          : AppBanner(
              variante: AppBannerVariante.erreur,
              texte: etat.messageErreur!,
              libelleAction: AppStrings.actionReessayer,
              onAction: () => unawaited(_controleur.rafraichir()),
            ),
      AppBannerVariante.horsLigne => const AppBanner(
        variante: AppBannerVariante.horsLigne,
        texte: AppStrings.horsLigneDetail,
      ),
      AppBannerVariante.lectureSeule => const AppBanner(
        variante: AppBannerVariante.lectureSeule,
        texte: AppStrings.lectureSeuleDetail,
      ),
      // L'aboutissement du mois : il se dit en toutes lettres et il reste.
      AppBannerVariante.information => AppBanner(
        variante: AppBannerVariante.information,
        texte: AppStrings.suiviValideLe(formaterDateLongue(valide!)),
      ),
      AppBannerVariante.verrouille ||
      AppBannerVariante.attention => null,
    };
  }
}

/// Les autres écrans admin, repliés en menu **nommé** sur `compact` : un menu
/// nommé vaut mieux qu'une icône devinée.
class _MenuAdmin extends StatelessWidget {
  const _MenuAdmin();

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    icon: const Icon(Icons.more_vert),
    tooltip: AppStrings.navOuvrirMenu,
    onSelected: (String route) => context.goNamed(route),
    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        value: AppRoutes.planningAdminName,
        child: Text(AppStrings.matriceVersPlanning),
      ),
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
