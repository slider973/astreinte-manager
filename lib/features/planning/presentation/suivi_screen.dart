import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/caserne/caserne_providers.dart';
import '../../../core/caserne/fait_caserne_ecran.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/reseau/connectivite.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/destinations.dart';
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
import '../domain/candidat.dart';
import '../domain/matrice_providers.dart';
import '../domain/planning_providers.dart';
import '../domain/suivi_planning.dart';
import '../domain/suivi_providers.dart';
import 'widgets/bloc_progression.dart';
import 'widgets/bloc_retardataires.dart';
import 'widgets/confirmation_annulation.dart';
import 'widgets/confirmation_reattribution.dart';
import 'widgets/filtres_suivi.dart';
import 'widgets/indicateur_direct.dart';
import 'widgets/journee_suivi.dart';
import 'widgets/panneau_creneau.dart';
import 'widgets/squelette_panneau.dart';
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

  SuiviController get _controleur => ref.read(suiviControllerProvider.notifier);

  PlanningController get _planning =>
      ref.read(planningControllerProvider.notifier);

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

  // -------------------------------------------------------------------
  // La réattribution — le geste que le 019 laissait au chef à faire ailleurs
  // -------------------------------------------------------------------

  /// Ouvre le panneau des candidats sur un créneau à réparer.
  ///
  /// **Le panneau est celui du 017, et il vit ailleurs** : il se nourrit du
  /// planning et de la matrice du mois, que cet écran ne lit pas. Les deux
  /// providers se chargent ici, à l'ouverture, et pas une seconde plus tôt — un
  /// écran de suivi ne doit pas payer deux requêtes pour un panneau qu'on
  /// n'ouvrira peut-être pas.
  void _ouvrirCreneau(CreneauSuivi creneau) {
    ref.read(creneauSelectionneProvider.notifier).choisir(creneau.creneau.id);
    // Ce que la réattribution vient réparer, désigné plutôt que deviné : le
    // lien `replaced_by` pointera ce refus-là.
    ref.read(cibleReattributionProvider.notifier).viser(creneau.aRemplacer?.id);
    if (!AppWindowClass.of(context).estLarge) unawaited(_ouvrirFeuille());
  }

  Future<void> _ouvrirFeuille() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext contexteFeuille) => FractionallySizedBox(
        heightFactor: 0.85,
        child: Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? _) =>
              _panneau(onFermer: () => Navigator.of(contexteFeuille).pop()),
        ),
      ),
    );
    if (mounted) ref.read(creneauSelectionneProvider.notifier).fermer();
  }

  /// Le panneau, ou son squelette tant que la matrice du mois n'est pas lue.
  Widget _panneau({VoidCallback? onFermer}) {
    final panneau = ref.watch(panneauCandidatsProvider);
    if (panneau == null) return const SquelettePanneau();

    final fermer =
        onFermer ?? ref.read(creneauSelectionneProvider.notifier).fermer;

    return PanneauCreneau(
      panneau: panneau,
      raisonInactif: _raisonReattribution(),
      messageReattribution: _messageReattribution(panneau),
      onFermer: fermer,
      onAttribuer: (Candidat candidat) =>
          unawaited(_reattribuer(candidat, panneau)),
      onRetirer: (Candidat candidat) => unawaited(_annuler(candidat, panneau)),
      onEffectif: (int effectif) => unawaited(
        _planning.definirEffectif(
          creneauId: panneau.creneau.id,
          effectif: effectif,
        ),
      ),
    );
  }

  /// « Bruno B. a refusé ce créneau. La personne choisie sera notifiée tout de
  /// suite. » — le nom quand on le connaît, la conséquence toujours.
  String? _messageReattribution(PanneauCandidats panneau) {
    if (!panneau.notifie) return null;
    final cible = ref.read(cibleReattributionProvider);
    if (cible == null) return AppStrings.reattributionBandeau;
    final refusee = ref
        .read(suiviControllerProvider)
        .value
        ?.suivi
        .attributionParId(cible);
    if (refusee == null || refusee.nom.isEmpty) {
      return AppStrings.reattributionBandeau;
    }
    // Un refus et une annulation ne se disent pas de la même façon : l'un est
    // la réponse d'un pompier, l'autre une décision de la caserne.
    return refusee.etat == AttributionEtat.refuse
        ? AppStrings.reattributionBandeauRefus(refusee.nom)
        : AppStrings.reattributionBandeauAnnulation(refusee.nom);
  }

  /// Pourquoi la réattribution est impossible, ou `null`.
  ///
  /// **Hors ligne, elle est refusée plutôt que mise en file** : la
  /// notification partirait une heure plus tard, pour un créneau peut-être déjà
  /// pourvu par l'adjoint.
  String? _raisonReattribution() {
    final etat = ref.watch(suiviControllerProvider).value;
    if (etat == null) return null;
    if (etat.lectureSeule) return AppStrings.lectureSeuleDetail;
    if (!(ref.watch(enLigneProvider).value ?? true)) {
      return AppStrings.reattribuerHorsLigne;
    }
    return switch (etat.suivi.etat) {
      PlanningEtat.brouillon => AppStrings.reattribuerBrouillon,
      PlanningEtat.archive => AppStrings.reattribuerArchive,
      _ => null,
    };
  }

  Future<void> _reattribuer(Candidat candidat, PanneauCandidats panneau) async {
    final cible = ref.read(cibleReattributionProvider);
    final sortant = cible == null
        ? null
        : ref
              .read(suiviControllerProvider)
              .value
              ?.suivi
              .attributionParId(cible);

    final confirme = await confirmerReattribution(
      context,
      candidat: candidat,
      jour: panneau.jour,
      creneau: panneau.creneau.creneau,
      // On ne nomme le titulaire sortant que si on lui retire vraiment quelque
      // chose : celui qui a refusé ne perd rien et ne sera pas prévenu.
      titulaireSortant: sortant?.etat == AttributionEtat.accepte
          ? sortant?.nom
          : null,
    );
    if (!confirme || !mounted) return;

    final reponse = await _planning.reattribuer(
      creneauId: panneau.creneau.id,
      userId: candidat.userId,
      ancienneId: cible,
    );
    if (!mounted) return;

    final resultat = reponse.fait;
    if (resultat == null) {
      // **Le refus se dit avec ses mots.** « Ce créneau est déjà pourvu » nomme
      // la sortie ; « la réattribution n'a pas abouti » ne nomme rien.
      _annoncer(reponse.erreur?.message ?? AppStrings.reattribuerErreur);
      unawaited(_controleur.rafraichir());
      return;
    }

    // Le panneau se referme : le créneau est réparé, et le laisser ouvert
    // inviterait à recommencer.
    ref.read(creneauSelectionneProvider.notifier).fermer();
    // **Ne dire que ce que la réponse prouve** (ticket 055) : `notified` pour
    // l'entrant, `previous.notified` pour le sortant — des demandes en file,
    // d'où « sera prévenu ».
    final entrant = candidat.membre.nomAffiche;
    final ancien = resultat.ancienPrevenu ? sortant?.nom : null;
    _annoncer(switch ((resultat.entrantEnFile, ancien)) {
      (true, final String ancien) => AppStrings.reattribuerFaiteEtAncien(
        entrant,
        ancien,
      ),
      (true, null) => AppStrings.reattribuerFaite(entrant),
      (false, final ancien) => AppStrings.reattribuerFaiteSansPreuve(
        entrant,
        ancien: ancien,
      ),
    });
    unawaited(_controleur.rafraichir());
  }

  Future<void> _annuler(Candidat candidat, PanneauCandidats panneau) async {
    final attribution = candidat.attribution;
    if (attribution == null) return;

    // Accepté ou seulement proposé : la feuille le dit, parce que la
    // conséquence n'est pas la même — un téléphone sonne, ou personne n'est
    // prévenu.
    final connue = ref
        .read(suiviControllerProvider)
        .value
        ?.suivi
        .attributionParId(attribution.id);
    final acquise = connue?.etat == AttributionEtat.accepte;

    final demande = await confirmerAnnulation(
      context,
      membre: candidat.membre.nomAffiche,
      jour: panneau.jour,
      creneau: panneau.creneau.creneau,
      prevenu: acquise,
    );
    if (demande == null || !mounted) return;

    final reponse = await _planning.annuler(
      attributionId: attribution.id,
      motif: demande.motif,
    );
    if (!mounted) return;

    final prevenu = reponse.prevenu;
    if (prevenu == null) {
      _annoncer(reponse.erreur?.message ?? AppStrings.annulerErreur);
      unawaited(_controleur.rafraichir());
      return;
    }

    _annoncer(
      prevenu
          ? AppStrings.annulerFaite(candidat.membre.nomAffiche)
          : AppStrings.annulerFaiteSansEnvoi(candidat.membre.nomAffiche),
    );
    unawaited(_controleur.rafraichir());
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
    final destinations = ref.watch(destinationsProvider);
    final compact = AppWindowClass.of(context).estCompact;

    return AppScaffold(
      titre: AppStrings.suiviTitre,
      destinations: destinations,
      indexSelectionne: indexDestination(
        destinations,
        AppRoutes.planningAdminName,
      ),
      onDestination: (int index) =>
          allerVersDestination(context, destinations, index),
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
      // Le panneau des candidats prend, sur cet écran aussi, la place que le
      // 016 lui avait réservée. Il n'existe que si un créneau est ouvert.
      panneauLateral: ref.watch(creneauSelectionneProvider) == null
          ? null
          : _panneau(),
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
              StatusBadge.planning(
                etat.suivi.etat,
                tampon: etat.valideSousNosYeux,
              ),
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
        return JourneeSuiviBloc(
          journee: journees[index - 1],
          // Rien à ouvrir sur un brouillon ni sur un mois archivé : le bouton
          // ne s'affiche pas plutôt que de s'afficher inerte.
          onReparer:
              etat.suivi.etat == PlanningEtat.publie ||
                  etat.suivi.etat == PlanningEtat.valide
              ? _ouvrirCreneau
              : null,
          raisonInactif: _raisonReattribution(),
        );
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

    final fait = faitCaserneEcran(context, ref);
    final lectureSeule =
        etat.lectureSeule || ref.watch(lectureSeuleCaserneProvider);

    final variantes = <AppBannerVariante>[
      if (etat.messageErreur != null || envoiManque) AppBannerVariante.erreur,
      if (horsLigne) AppBannerVariante.horsLigne,
      if (lectureSeule) AppBannerVariante.lectureSeule,
      if (fait != null && !lectureSeule) fait.variante,
      if (valide != null && etat.suivi.etat == PlanningEtat.valide)
        AppBannerVariante.information,
    ];

    final gagnante = AppBannerVariante.prioritaire(variantes);
    if (gagnante == null) return null;

    return switch (gagnante) {
      // Un envoi manqué passe devant une erreur de lecture : la lecture se
      // rattrape d'un bouton, les pompiers non prévenus attendent une action.
      AppBannerVariante.erreur =>
        envoiManque
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
      AppBannerVariante.lectureSeule =>
        fait?.variante == AppBannerVariante.lectureSeule
            ? fait!.banniere
            : const AppBanner(
                variante: AppBannerVariante.lectureSeule,
                texte: AppStrings.lectureSeuleDetail,
              ),
      // L'aboutissement du mois : il se dit en toutes lettres et il reste. Un
      // essai qui se termine ne le chasse pas — le mois validé est le fait de
      // l'écran, l'échéance de facturation n'en est pas un.
      AppBannerVariante.information =>
        valide != null
            ? AppBanner(
                variante: AppBannerVariante.information,
                texte: AppStrings.suiviValideLe(formaterDateLongue(valide)),
              )
            : fait?.banniere,
      AppBannerVariante.attention => fait?.banniere,
      AppBannerVariante.verrouille => null,
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
