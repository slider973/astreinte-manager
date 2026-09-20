import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/preferences/reperes_locaux.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../core/widgets/peinture_grille.dart';
import '../domain/dispos_providers.dart';
import '../domain/periode_saisie.dart';
import 'controllers/saisie_controller.dart';
import 'widgets/barre_compteurs.dart';
import 'widgets/barre_raccourcis.dart';
import 'widgets/bloc_astuce.dart';
import 'widgets/entete_colonnes.dart';
import 'widgets/grille_calendrier.dart';
import 'widgets/grille_registre.dart';
import 'widgets/section_preferences.dart';
import 'widgets/selecteur_mois.dart';

/// Vrai si le membre a déjà terminé une peinture sur cet appareil.
final FutureProvider<bool> peintureDejaFaiteProvider = FutureProvider<bool>(
  (ref) =>
      ref.watch(reperesLocauxProvider).dejaVu(RepereAccueil.peintureDispos),
);

/// **« Mon mois »** — l'écran le plus ouvert du produit.
///
/// Le membre ouvre le mois, pose ses créneaux, et repart sans avoir cherché
/// de bouton « Enregistrer ». Il n'y en a pas : l'écran enregistre seul.
///
/// Trois compositions pour une seule donnée et une seule règle de geste :
/// le **registre** à trois colonnes en `compact` et `medium`, le
/// **calendrier** à sept colonnes dès `expanded`, et le retour au registre
/// quelle que soit la largeur au-delà de ×1.6 d'échelle de texte — la grille
/// change de forme plutôt que de rogner son texte.
class MoisScreen extends ConsumerStatefulWidget {
  const MoisScreen({
    required this.destinations,
    required this.indexSelectionne,
    required this.onDestination,
    super.key,
    this.moisInitial,
    this.onMoisChange,
  });

  /// L'échelle de texte au-delà de laquelle la vue calendaire retombe sur le
  /// registre et la ligne passe à deux niveaux.
  static const double seuilDeuxNiveaux = 1.6;

  /// Largeur maximale du registre en `medium` : au-delà, les cases
  /// deviendraient absurdement larges.
  static const double largeurRegistreMax = 560;

  final List<AppDestination> destinations;
  final int indexSelectionne;
  final ValueChanged<int> onDestination;

  /// Le mois porté par l'URL (`?mois=AAAA-MM`), s'il y en a un.
  final String? moisInitial;

  /// Remonte le mois choisi à la coquille, qui l'écrit dans l'URL.
  final ValueChanged<String>? onMoisChange;

  @override
  ConsumerState<MoisScreen> createState() => _MoisScreenState();
}

class _MoisScreenState extends ConsumerState<MoisScreen>
    with WidgetsBindingObserver {
  final ScrollController _defilement = ScrollController();

  /// Le contrôleur, gardé en champ : `ref` n'est plus lisible depuis
  /// `dispose()`, et c'est précisément là qu'il faut vider la file.
  SaisieController? _saisie;

  /// Le bloc d'aide, figé le temps d'un geste.
  ///
  /// Il s'efface dès la première saisie — mais **pas sous un doigt qui
  /// peint** : le retirer déplacerait la grille de soixante dp au moment
  /// précis où l'utilisateur vise une case.
  bool _astuceVisible = true;
  bool _astuceTouche = false;
  bool _astuceGlissement = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _suivreUrl();
  }

  @override
  void didUpdateWidget(MoisScreen ancien) {
    super.didUpdateWidget(ancien);
    if (widget.moisInitial != ancien.moisInitial) _suivreUrl();
  }

  /// Aligne le mois affiché sur celui de l'URL.
  ///
  /// **Y compris vers `null`** : l'entrée d'historique précédente n'avait pas
  /// de mois, c'est-à-dire le mois par défaut. Ne traiter que les valeurs non
  /// nulles laissait l'écran sur le mois qu'on venait de quitter, l'URL
  /// disant le contraire. Vu en vrai dans Chrome.
  ///
  /// Reporté d'une image : modifier un provider depuis `initState` ou
  /// `didUpdateWidget` est interdit par Riverpod, et pour une bonne raison —
  /// deux widgets abonnés au même provider liraient des états différents.
  void _suivreUrl() {
    final cle = widget.moisInitial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(moisSelectionneProvider.notifier).definir(cle);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    // L'application passe en arrière-plan : la file part sans attendre le
    // délai. Une PWA fermée ne doit rien emporter avec elle.
    if (etat == AppLifecycleState.paused || etat == AppLifecycleState.hidden) {
      unawaited(ref.read(saisieControllerProvider.notifier).viderMaintenant());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Le vidage est reporté d'une micro-tâche : appelé ici, il publierait un
    // nouvel état **pendant** le démontage de l'arbre, et les abonnements
    // Riverpod des lignes de jour se réveilleraient sur des éléments déjà
    // défunts. L'écriture, elle, part quand même : le contrôleur survit à
    // l'écran.
    final saisie = _saisie;
    if (saisie != null) {
      unawaited(Future<void>.microtask(saisie.viderMaintenant));
    }
    _defilement.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------
  // Le geste
  // -------------------------------------------------------------------

  void _finGeste() {
    final controleur = ref.read(saisieControllerProvider.notifier);
    final peintes = ref.read(saisieControllerProvider).value?.casesPeintes ?? 0;
    controleur.finGeste();
    if (peintes > 0) unawaited(_marquerPeintureDecouverte());
  }

  Future<void> _marquerPeintureDecouverte() async {
    if (ref.read(peintureDejaFaiteProvider).value ?? false) return;
    await ref
        .read(reperesLocauxProvider)
        .marquerVu(RepereAccueil.peintureDispos);
    if (mounted) ref.invalidate(peintureDejaFaiteProvider);
  }

  // -------------------------------------------------------------------
  // Le refus d'un mois fermé
  // -------------------------------------------------------------------

  /// **Ce que reçoit un membre qui appuie sur un mois verrouillé**
  /// (ticket 014, critère d'acceptation 2).
  ///
  /// Une phrase en bas d'écran, pas une bannière de plus : la bannière dit
  /// déjà l'état permanent du mois, celle-ci répond à un geste précis. Elle
  /// n'est **pas rouge** — un mois fermé est un fait, pas une panne
  /// (`DESIGN.md § Do`).
  void _annoncerRefus() {
    final etat = ref.read(saisieControllerProvider).value;
    if (etat == null) return;

    final message = etat.lectureSeule
        ? AppStrings.moisRefusLectureSeule
        : AppStrings.moisRefusVerrouille(etat.periode.libelle);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          // `liveRegion` : sur le web, le contenu d'un `SnackBar` n'est pas
          // annoncé tout seul, et c'est justement la réponse à un geste.
          content: Semantics(liveRegion: true, child: Text(message)),
          showCloseIcon: true,
        ),
      );
  }

  // -------------------------------------------------------------------
  // Rendu
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Un compteur et non un message : l'écran connaît le mois et la cause,
    // le contrôleur n'a qu'à publier l'événement.
    ref.listen<int>(
      saisieControllerProvider.select(
        (AsyncValue<EtatSaisie?> valeur) => valeur.value?.refusSaisie ?? 0,
      ),
      (int? avant, int apres) {
        if (apres > (avant ?? 0)) _annoncerRefus();
      },
    );

    final periodes = ref.watch(periodesProvider);
    final saisie = ref.watch(saisieControllerProvider);
    final etat = saisie.value;
    _saisie = ref.read(saisieControllerProvider.notifier);

    final classe = AppWindowClass.of(context);
    final echelle = MediaQuery.textScalerOf(context).scale(16) / 16;
    final deuxNiveaux = echelle > MoisScreen.seuilDeuxNiveaux;
    final calendrier = classe.supporteDeuxVolets && !deuxNiveaux;

    return AppScaffold(
      titre: AppStrings.navMonMois,
      destinations: widget.destinations,
      indexSelectionne: widget.indexSelectionne,
      onDestination: widget.onDestination,
      banniere: _banniere(etat, periodes),
      filActions: etat == null || classe.estLarge
          ? null
          : _barre(etat, grand: false),
      panneauLateral: etat == null ? null : _panneau(etat),
      child: _corps(
        periodes: periodes,
        saisie: saisie,
        calendrier: calendrier,
        deuxNiveaux: deuxNiveaux,
        classe: classe,
      ),
    );
  }

  Widget _corps({
    required AsyncValue<List<PeriodeSaisie>> periodes,
    required AsyncValue<EtatSaisie?> saisie,
    required bool calendrier,
    required bool deuxNiveaux,
    required AppWindowClass classe,
  }) {
    if (periodes.hasError && !periodes.hasValue) {
      return EmptyState.horsLigne(
        onAction: () => ref.invalidate(periodesProvider),
      );
    }
    if (periodes.hasValue && periodes.requireValue.isEmpty) {
      return const EmptyState(
        titre: AppStrings.moisAucunePeriodeTitre,
        texte: AppStrings.moisAucunePeriodeTexte,
        icone: Icons.event_busy_outlined,
      );
    }
    if (saisie.hasError && !saisie.hasValue) {
      return EmptyState.erreur(
        texte: AppStrings.moisChargementImpossibleTexte,
        onAction: () => ref.read(saisieControllerProvider.notifier).recharger(),
      );
    }

    final etat = saisie.value;
    if (etat == null) return const _Squelette();

    final grille = _grille(
      etat: etat,
      periodes: periodes.value ?? const <PeriodeSaisie>[],
      calendrier: calendrier,
      deuxNiveaux: deuxNiveaux,
      classe: classe,
    );

    return _borner(
      classe: classe,
      calendrier: calendrier,
      enfant: PeintureGrille(
        actif: etat.modifiable,
        pointeurFin: context.estPointeurFin,
        controleurDefilement: _defilement,
        // En registre, la bande des 24 premiers dp ne contient aucune case :
        // c'est la colonne « Date », et le conflit avec le geste retour iOS
        // n'existe pas. En calendaire, il faut s'en garder.
        margeGaucheInerte: calendrier ? margeGesteRetour(context) : 0,
        onDebut: ref.read(saisieControllerProvider.notifier).debutGeste,
        onFin: _finGeste,
        onAnnulation: ref.read(saisieControllerProvider.notifier).annulerGeste,
        child: grille,
      ),
    );
  }

  /// Borne et centre le contenu selon la classe de fenêtre.
  Widget _borner({
    required AppWindowClass classe,
    required bool calendrier,
    required Widget enfant,
  }) {
    if (classe.estCompact) return enfant;

    final largeur = calendrier
        ? AppSpacing.contenuMax
        : MoisScreen.largeurRegistreMax;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: largeur),
        child: enfant,
      ),
    );
  }

  Widget _grille({
    required EtatSaisie etat,
    required List<PeriodeSaisie> periodes,
    required bool calendrier,
    required bool deuxNiveaux,
    required AppWindowClass classe,
  }) {
    final aujourdhui = DateTime.now();
    final astuce = _astuce(etat);

    return CustomScrollView(
      controller: _defilement,
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: SelecteurMois(
              periodes: periodes,
              selectionnee: etat.periode,
              onChoisir: _choisirMois,
            ),
          ),
        ),
        // La place que le brief du 011 avait gardée aux raccourcis : entre le
        // sélecteur de mois et l'en-tête épinglé. En `large`, la bande n'est
        // pas ici mais en tête du panneau de droite.
        if (!classe.estLarge)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: AppSpacing.md),
              child: BarreRaccourcis(),
            ),
          ),
        // La place du ticket 013 : **au-dessus de la grille**, dans le même
        // champ de vision que les raccourcis qui viennent de tout cocher. Le
        // brief du 011 l'avait réservée sous le dernier jour du mois ; depuis
        // le 012, on remplit un mois en deux touches sans jamais défiler
        // jusque-là (`design/013 § 3`). En `large`, elle est dans le panneau.
        if (!classe.estLarge)
          const SliverToBoxAdapter(child: SectionPreferences()),
        if (astuce != null) SliverToBoxAdapter(child: astuce),
        SliverToBoxAdapter(child: _Annonce(texte: etat.annonce)),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
        SliverPersistentHeader(
          pinned: true,
          delegate: EnteteColonnes(
            calendrier: calendrier,
            hauteur: _hauteurEntete(context),
          ),
        ),
        if (calendrier)
          GrilleCalendrier(periode: etat.periode, aujourdhui: aujourdhui)
        else
          GrilleRegistre(
            periode: etat.periode,
            aujourdhui: aujourdhui,
            deuxNiveaux: deuxNiveaux,
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      ],
    );
  }

  Widget? _astuce(EtatSaisie etat) {
    // Sur un mois verrouillé, le bloc d'aide ne s'affiche jamais : il n'y a
    // rien à apprendre sur un geste qu'on ne peut pas faire.
    if (!etat.modifiable) return null;

    final dejaPeint = ref.watch(peintureDejaFaiteProvider).value ?? true;
    final montrerTouche = etat.mois.estVierge;
    final montrerGlissement = !dejaPeint;

    // Pendant un geste, le bloc garde exactement la forme qu'il avait :
    // c'est la seule façon de ne pas déplacer le document sous le doigt.
    if (!etat.enPeinture) {
      _astuceTouche = montrerTouche;
      _astuceGlissement = montrerGlissement;
      _astuceVisible = montrerTouche || montrerGlissement;
    }
    if (!_astuceVisible) return null;

    return BlocAstuce(
      montrerTouche: _astuceTouche,
      montrerGlissement: _astuceGlissement,
    );
  }

  static double _hauteurEntete(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(12) * 2 + AppSpacing.lg;

  void _choisirMois(PeriodeSaisie periode) {
    unawaited(
      ref.read(saisieControllerProvider.notifier).choisirMois(periode.cle),
    );
    widget.onMoisChange?.call(periode.cle);
  }

  Widget _barre(EtatSaisie etat, {required bool grand}) => BarreCompteurs(
    compteurs: etat.compteurs,
    sync: etat.sync,
    pinceau: etat.pinceau,
    // Sur un mois verrouillé, il n'y a plus rien à enregistrer : l'indicateur
    // se retire, les compteurs restent.
    montrerIndicateur: etat.modifiable,
    onReessayer: () =>
        unawaited(ref.read(saisieControllerProvider.notifier).reessayer()),
    grand: grand,
    plafondAstreintes: etat.preferences.valeurs.maxAstreintes,
    plafondWeekends: etat.preferences.valeurs.maxWeekends,
  );

  /// En `large`, la barre du bas disparaît et son contenu s'installe en tête
  /// du panneau de droite.
  Widget _panneau(EtatSaisie etat) => SingleChildScrollView(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const BarreRaccourcis(vertical: true),
        const SizedBox(height: AppSpacing.xl),
        _barre(etat, grand: true),
        // La place que le 011 avait réservée : sous les compteurs. Elle est
        // gardée telle quelle — ici, rien n'est en concurrence avec la
        // grille, et la section est visible sans défiler.
        const SectionPreferences(dansPanneau: true),
      ],
    ),
  );

  // -------------------------------------------------------------------
  // La bannière — au plus une
  // -------------------------------------------------------------------

  AppBanner? _banniere(
    EtatSaisie? etat,
    AsyncValue<List<PeriodeSaisie>> periodes,
  ) {
    if (etat == null) return null;

    final refus = etat.refusServeur;
    final variantes = <AppBannerVariante>[
      if (refus != null || etat.echecPersistant || etat.filePerimee)
        AppBannerVariante.erreur,
      if (etat.horsLigne) AppBannerVariante.horsLigne,
      if (etat.lectureSeule && refus == null) AppBannerVariante.lectureSeule,
      if (!etat.periode.ouverte) AppBannerVariante.verrouille,
      if (_bientotFermee(etat.periode)) AppBannerVariante.attention,
    ];

    final gagnante = AppBannerVariante.prioritaire(variantes);
    if (gagnante == null) return null;

    return switch (gagnante) {
      // La file périmée passe devant : elle dit une perte déjà consommée,
      // là où les deux autres disent un envoi qui peut encore aboutir.
      AppBannerVariante.erreur => switch (0) {
        _ when etat.filePerimee => AppBanner(
          variante: AppBannerVariante.erreur,
          texte: AppStrings.moisFilePerimeeBanniere,
          libelleAction: AppStrings.actionFermer,
          onAction: () =>
              ref.read(saisieControllerProvider.notifier).accuserFilePerimee(),
        ),
        _ when refus != null => AppBanner(
          variante: AppBannerVariante.erreur,
          texte: refus,
          libelleAction: AppStrings.actionRecharger,
          onAction: () =>
              ref.read(saisieControllerProvider.notifier).recharger(),
        ),
        _ => AppBanner(
          variante: AppBannerVariante.erreur,
          texte: AppStrings.moisErreurEnregistrementBanniere,
          libelleAction: AppStrings.actionReessayer,
          onAction: () => unawaited(
            ref.read(saisieControllerProvider.notifier).reessayer(),
          ),
        ),
      },
      AppBannerVariante.horsLigne => const AppBanner(
        variante: AppBannerVariante.horsLigne,
        texte: AppStrings.horsLigneDetail,
      ),
      AppBannerVariante.lectureSeule => const AppBanner(
        variante: AppBannerVariante.lectureSeule,
        texte: AppStrings.lectureSeuleDetail,
      ),
      AppBannerVariante.verrouille => AppBanner(
        variante: AppBannerVariante.verrouille,
        texte: AppStrings.periodeVerrouilleeDetail(
          formaterDateLongue(
            etat.periode.verrouilleeLe ?? etat.periode.dateLimite,
          ),
        ),
      ),
      AppBannerVariante.attention => AppBanner(
        variante: AppBannerVariante.attention,
        texte: AppStrings.periodeBientotFermee(
          etat.periode.joursAvantLimite(DateTime.now()) ?? 0,
          AppStrings.moisLongs[etat.periode.mois - 1],
        ),
      ),
      AppBannerVariante.information => null,
    };
  }

  /// La bannière de rappel n'apparaît qu'à J-3 : plus tôt, elle coûterait
  /// 48 dp de grille tous les mois pour redire ce que le sélecteur dit déjà.
  static bool _bientotFermee(PeriodeSaisie periode) {
    final restants = periode.joursAvantLimite(DateTime.now());
    return restants != null && restants <= 3;
  }
}

/// L'annonce de fin de geste, sans surface et sans hauteur.
///
/// C'est elle qui porte « 14 cases mises à jour, disponible » ou « Peinture
/// annulée ». La barre des compteurs, elle, n'est **pas** une `liveRegion` :
/// elle changerait à chaque case peinte et noierait cette annonce-ci.
class _Annonce extends StatelessWidget {
  const _Annonce({required this.texte});

  final String? texte;

  @override
  Widget build(BuildContext context) {
    final phrase = texte;
    if (phrase == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      label: phrase,
      child: const SizedBox.shrink(),
    );
  }
}

/// Le chargement, **à la forme de la grille qui va s'afficher**.
///
/// Sélecteur, en-tête de colonnes, puis huit lignes de jour. Jamais de
/// `CircularProgressIndicator` : l'écran montre l'ossature de ce qui arrive.
class _Squelette extends StatelessWidget {
  const _Squelette();

  @override
  Widget build(BuildContext context) {
    return LoadingSkeleton(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(
              height: SelecteurMois.hauteurBouton,
              child: SkeletonLigne(hauteur: SelecteurMois.hauteurBouton),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (var ligne = 0; ligne < 8; ligne++) ...<Widget>[
              const SizedBox(
                height: GrilleRegistre.hauteurLigne - AppSpacing.sm,
                child: Row(
                  children: <Widget>[
                    Expanded(child: SkeletonLigne(hauteur: 48)),
                    SizedBox(width: AppSpacing.entreCibles),
                    Expanded(child: SkeletonLigne(hauteur: 48)),
                    SizedBox(width: AppSpacing.entreCibles),
                    Expanded(child: SkeletonLigne(hauteur: 48)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}
