import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/caserne/caserne_providers.dart';
import '../../../core/caserne/fait_caserne_ecran.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/preferences/reperes_locaux.dart';
import '../../../core/reseau/connectivite.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/slot_chip.dart';
import '../../dispos/domain/dispos_providers.dart';
import '../../dispos/domain/periode_saisie.dart';
import '../../membres/domain/membres_providers.dart';
import '../../notifications/presentation/widgets/bouton_notifications.dart';
import '../../profil/presentation/widgets/bouton_compte.dart';
import '../data/matrice_repository.dart';
import '../data/planning_repository.dart';
import '../data/suivi_repository.dart';
import '../domain/candidat.dart';
import '../domain/cle_cellule.dart';
import '../domain/ligne_matrice.dart';
import '../domain/matrice_filtres.dart';
import '../domain/matrice_providers.dart';
import '../domain/planning_mois.dart';
import '../domain/planning_providers.dart';
import '../domain/proposition_automatique.dart';
import '../domain/recapitulatif_publication.dart';
import '../domain/resume_mois.dart';
import '../domain/suivi_providers.dart';
import 'widgets/bandeau_mois.dart';
import 'widgets/barre_commande_matrice.dart';
import 'widgets/confirmation_hors_dispo.dart';
import 'widgets/confirmation_saisie_admin.dart';
import 'widgets/geometrie_matrice.dart';
import 'widgets/grille_matrice.dart';
import 'widgets/panneau_creneau.dart';
import 'widgets/recapitulatif_proposition.dart';
import 'widgets/recapitulatif_publication.dart';
import 'widgets/squelette_matrice.dart';
import 'widgets/vue_jour.dart';
import 'widgets/zone_planning.dart';

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

  /// Ce qu'il faut laisser à la grille pour qu'elle dise encore quelque
  /// chose : quatre lignes de membres, 128 points.
  ///
  /// **Son bloc épinglé se sert le premier** dans cette réserve — 88 points
  /// sans planning, 116 avec la ligne des créneaux.
  static const double placeGrilleUtile = GeoMatrice.hauteurLigne * 4;

  /// La hauteur qu'il faut, **sous la barre de commande**, pour le bandeau
  /// complet : ses 134 points mesurés, plus ce qui reste dû à la grille.
  ///
  /// **La bande de semaine n'entre plus dans ce compte** (chantier 061c) :
  /// ses 72 points sont rendus au bandeau et à la grille, et les dates
  /// vivent désormais dans l'en-tête épinglé de la matrice, qui les portait
  /// déjà.
  ///
  /// **La matrice garde la main pour autant** : en dessous du seuil le
  /// bandeau se réduit à sa ligne de chiffres, puis s'efface. Un résumé qui
  /// laisserait deux lignes de grille aurait remplacé l'écran qu'il
  /// surplombe.
  static const double placeBandeauComplet =
      BandeauMois.hauteurComplet + placeGrilleUtile;

  /// En dessous, la ligne de trois chiffres seule ; puis plus rien.
  static const double placeBandeauReduit =
      BandeauMois.hauteurReduit + placeGrilleUtile;

  /// En dessous encore, le bandeau s'efface mais **pas la décision** : la
  /// zone du planning reste seule sur sa rangée, tant que la grille garde ses
  /// quatre lignes. Plus bas que ça, la matrice reprend tout : un écran de
  /// deux cents points ne sert plus à publier, il sert à lire.
  static const double placeZonePlanningSeule =
      AppTouch.cible + AppSpacing.sm * 2 + placeGrilleUtile;

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

  PlanningController get _planning =>
      ref.read(planningControllerProvider.notifier);

  /// « Rafraîchir » relit **les deux** : la matrice et le planning. Un bouton
  /// qui ne rafraîchirait que la moitié de l'écran serait pire que pas de
  /// bouton du tout.
  void _relire() {
    unawaited(_controleur.rafraichir());
    unawaited(_planning.rafraichir());
  }

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

  // -------------------------------------------------------------------
  // Le planning : créer, ouvrir un créneau, attribuer, retirer
  // -------------------------------------------------------------------

  Future<void> _creer() async {
    final avant = ref.read(planningControllerProvider).value;
    if (avant == null) return;

    await _planning.creer();
    final apres = ref.read(planningControllerProvider).value;
    if (!mounted || apres == null || !apres.planning.existe) return;
    _annoncer(
      AppStrings.planningCreeTexte(
        AppStrings.moisLongs[apres.periode.mois - 1],
        apres.periode.nombreDeJours * 2,
      ),
    );
  }

  /// Ouvre le panneau d'un créneau : le volet de droite en `large`, une
  /// feuille de bas d'écran en dessous. Jamais un dialogue.
  void _ouvrirCreneau(String creneauId) {
    ref.read(creneauSelectionneProvider.notifier).choisir(creneauId);
    if (!AppWindowClass.of(context).estLarge) unawaited(_ouvrirFeuille());
  }

  Future<void> _ouvrirFeuille() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext contexteFeuille) => FractionallySizedBox(
        heightFactor: 0.8,
        child: Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? _) {
            final panneau = ref.watch(panneauCandidatsProvider);
            if (panneau == null) return const SizedBox.shrink();
            return _panneau(
              panneau,
              onFermer: () => Navigator.of(contexteFeuille).pop(),
            );
          },
        ),
      ),
    );
    // Le geste retour ferme la feuille : la sélection doit suivre, sinon la
    // case reste marquée sélectionnée sans rien derrière.
    if (mounted) ref.read(creneauSelectionneProvider.notifier).fermer();
  }

  Widget _panneau(PanneauCandidats panneau, {VoidCallback? onFermer}) {
    final etat = ref.watch(planningControllerProvider).value;
    final distant = etat?.distant;

    return PanneauCreneau(
      panneau: panneau,
      raisonInactif: etat == null ? null : _raisonAttribution(etat),
      messageDistant: distant?.creneauId == panneau.creneau.id
          ? _libelleDistant(distant!)
          : null,
      onFermer:
          onFermer ?? ref.read(creneauSelectionneProvider.notifier).fermer,
      onAttribuer: (Candidat candidat) =>
          unawaited(_attribuer(candidat, panneau)),
      onRetirer: (Candidat candidat) => unawaited(_retirer(candidat)),
      onEffectif: (int effectif) => unawaited(
        _planning.definirEffectif(
          creneauId: panneau.creneau.id,
          effectif: effectif,
        ),
      ),
    );
  }

  /// Qui a modifié le créneau sous notre main. Le nom vient des lignes de la
  /// matrice **déjà chargées** : aucune requête pour un nom. À défaut, la
  /// phrase reste vraie sans lui.
  String _libelleDistant(ChangementDistant distant) {
    final auteur = distant.auteurId;
    final ligne = auteur == null
        ? null
        : ref.read(matriceControllerProvider).value?.matrice.ligneDe(auteur);
    return ligne == null
        ? AppStrings.planningModifieDistantAnonyme
        : AppStrings.planningModifieDistant(ligne.nomAffiche);
  }

  /// Attribue un candidat. **Un seul dialogue dans tout l'écran** : celui de
  /// l'attribution hors disponibilité. Le quota, lui, s'est déjà dit en clair
  /// sur la ligne (`design/017 § 6.3`).
  Future<void> _attribuer(Candidat candidat, PanneauCandidats panneau) async {
    if (!candidat.estDisponible) {
      final confirme = await confirmerHorsDispo(
        context,
        candidat: candidat,
        jour: panneau.jour,
        creneau: panneau.creneau.creneau,
      );
      if (!confirme) return;
    }

    final echec = await _planning.attribuer(
      creneauId: panneau.creneau.id,
      userId: candidat.userId,
    );

    // Un doublon n'est pas une panne : c'est l'autre administrateur qui a été
    // plus rapide. On le dit d'une phrase et on relit.
    if (echec == ErreurPlanning.dejaAttribue && mounted) {
      _annoncer(AppStrings.planningDejaAttribue);
      unawaited(_planning.rafraichir());
    }
  }

  /// Retire une attribution. **Pas de confirmation, une sortie** : en
  /// brouillon le geste est réversible en un clic, et un dialogue de plus
  /// apprendrait à cliquer « Oui » sans lire.
  Future<void> _retirer(Candidat candidat) async {
    final attribution = candidat.attribution;
    if (attribution == null) return;

    final retiree = await _planning.retirer(attribution.id);
    if (retiree == null || !mounted) return;

    _annoncer(
      AppStrings.planningRetireeTexte,
      libelleAction: AppStrings.planningAnnulerRetrait,
      onAction: () => unawaited(
        _planning.attribuer(
          creneauId: retiree.creneauId,
          userId: retiree.userId,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Proposer automatiquement — la partie du travail qu'une machine fait bien
  // -------------------------------------------------------------------

  /// Calcule le remplissage, montre le récapitulatif, applique si le chef
  /// confirme.
  ///
  /// **Le plan est calculé une fois, ici, et il part tel quel.** Le recalculer
  /// au moment d'appliquer en donnerait un second, et le récapitulatif que le
  /// chef vient de valider n'engagerait plus rien (`design/018 § 4`).
  Future<void> _proposer(EtatPlanning etat) async {
    final proposition = PropositionAutomatique.construire(
      planning: etat.planning,
      lignes: ref.read(lignesAvecChargeProvider),
      annee: etat.periode.annee,
      mois: etat.periode.mois,
    );

    // Rien à proposer : le dire d'une phrase vaut mieux qu'ouvrir une feuille
    // vide. Ce n'est pas une panne — personne n'est disponible, ou tous ceux
    // qui l'étaient ont fait leur compte.
    if (proposition.vide) {
      _annoncer(AppStrings.proposerRienATrouver);
      return;
    }

    await ouvrirProposition(
      context,
      proposition: proposition,
      mois: AppStrings.moisLongs[etat.periode.mois - 1],
      onAppliquer: () => _appliquer(proposition),
    );
  }

  /// L'application proprement dite. Rend `true` quand la base a répondu : la
  /// feuille ne se ferme qu'à ce moment-là.
  Future<bool> _appliquer(PropositionAutomatique proposition) async {
    final (:fait, :erreur) = await _planning.appliquerProposition(
      proposition.picks,
    );
    if (fait == null || !mounted) return false;

    // **Ce qui s'est réellement passé, pas ce qui était prévu.** L'adjoint a pu
    // remplir un créneau entre la lecture et l'appui : annoncer le chiffre du
    // plan serait annoncer un chiffre faux.
    _annoncer(switch (fait) {
      _ when fait.posees == 0 => AppStrings.proposerRienFait,
      _ when fait.ecartees > 0 => AppStrings.proposerFaitPartiel(
        fait.posees,
        fait.ecartees,
      ),
      _ => AppStrings.proposerFait(fait.posees, fait.decouverts),
    });
    return erreur == null;
  }

  /// Pourquoi la proposition automatique est impossible, ou `null`.
  String? _raisonProposition(EtatPlanning etat) {
    if (etat.lectureSeule) return AppStrings.matriceSaisieIndisponibleSuspendue;
    if (!(ref.watch(enLigneProvider).value ?? true)) {
      return AppStrings.proposerHorsLigne;
    }
    return null;
  }

  // -------------------------------------------------------------------
  // Publier — le geste qui fait sortir le planning du bureau
  // -------------------------------------------------------------------

  /// Ouvre le récapitulatif, puis publie si le chef confirme.
  ///
  /// **Le bordereau avant l'envoi** : créneaux non pourvus, membres au-delà de
  /// leur quota, membres attribués hors disponibilité. Il avertit, il ne bloque
  /// jamais (`docs/PRD.md § 7.4`).
  Future<void> _publier(EtatPlanning etat) async {
    final recapitulatif = RecapitulatifPublication.construire(
      planning: etat.planning,
      lignes: ref.read(lignesAvecChargeProvider),
      annee: etat.periode.annee,
      mois: etat.periode.mois,
    );

    final publie = await ouvrirRecapitulatif(
      context,
      recapitulatif: recapitulatif,
      mois: AppStrings.moisLongs[etat.periode.mois - 1],
      onPublier: _envoyer,
    );
    if (!publie || !mounted) return;

    // Le planning vient de quitter le bureau : c'est ici qu'on va le suivre.
    ref.invalidate(suiviControllerProvider);
    context.goNamed(
      AppRoutes.suiviName,
      queryParameters: <String, String>{
        AppRoutes.parametreMois: etat.periode.cle,
      },
    );
  }

  /// L'envoi proprement dit. Rend `true` quand la publication a abouti : la
  /// feuille ne se ferme qu'à ce moment-là.
  Future<bool> _envoyer() async {
    try {
      final resultat = await _planning.publier();
      if (resultat == null) return false;
      final etat = ref.read(planningControllerProvider).value;
      final planning = etat?.planning.planning;

      // **La publication est acquise, l'envoi ne l'est pas toujours**, et le
      // compte rendu du serveur le dit. Annoncer « 18 pompiers notifiés » quand
      // aucun téléphone n'a sonné, c'est retirer au chef la seule raison qu'il
      // aurait d'aller relancer.
      if (!resultat.envoiComplet && planning != null) {
        ref.read(alerteEnvoiProvider.notifier).signaler(planning.id);
      }

      if (mounted && etat != null) {
        final mois = AppStrings.moisLongs[etat.periode.mois - 1];
        _annoncer(
          resultat.envoiComplet
              ? AppStrings.publiePourMois(mois, resultat.membres)
              : AppStrings.publiePourMoisSansEnvoi(mois),
        );
      }
      return true;
    } on EchecSuivi catch (echec) {
      // « Déjà publié » n'est pas une panne : c'est l'adjoint qui a été plus
      // rapide. On le dit d'une phrase, on ferme, et l'écran de suivi montrera
      // l'état réel.
      if (echec.erreur == ErreurSuivi.dejaPublie) {
        if (mounted) _annoncer(AppStrings.publierDejaFait);
        return true;
      }
      return false;
    }
  }

  /// Pourquoi la publication est impossible, ou `null`.
  String? _raisonPublication(EtatPlanning etat) {
    if (etat.lectureSeule) return AppStrings.matriceSaisieIndisponibleSuspendue;
    if (!(ref.watch(enLigneProvider).value ?? true)) {
      return AppStrings.publierHorsLigne;
    }
    return null;
  }

  /// Le nombre de **téléphones qui vont sonner** si l'on publie : pas le
  /// nombre d'attributions, mais celui des membres attribués.
  int _membresAttribues(EtatPlanning etat) => <String>{
    for (final creneau in etat.planning.creneaux)
      for (final attribution in etat.planning.attributionsDe(creneau.id))
        attribution.userId,
  }.length;

  /// La barre d'actions du bas : le bouton « Publier », et rien d'autre.
  ///
  /// **Sur téléphone seulement** depuis le chantier 061c. `filActions` est la
  /// seule zone de l'ossature qui ne défile pas avec la vue par jour, et la
  /// barre de commande y défile : un bouton « Publier » qui s'en irait au
  /// défilement serait un bouton qu'on cherche. Sur grand écran, la barre de
  /// commande ne défile pas — « Publier » y prend sa place en seconde rangée
  /// et rend ces 70 points à la matrice.
  Widget? _filActions(EtatPlanning? etat) {
    if (etat == null || !etat.planning.modifiable) return null;

    final membres = _membresAttribues(etat);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PrimaryButton(
          libelle: AppStrings.publierAction,
          icone: Icons.campaign,
          chargement: etat.publication,
          raisonDesactivation: _raisonPublication(etat),
          onPressed: _raisonPublication(etat) != null || etat.publication
              ? null
              : () => unawaited(_publier(etat)),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Le nombre de **téléphones qui vont sonner**, pas le nombre
        // d'attributions : c'est la seule grandeur que le chef ait besoin de
        // sentir avant d'appuyer.
        Text(
          AppStrings.publierDetail(membres),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Pourquoi la création du planning est impossible, ou `null`.
  String? _raisonCreation(EtatPlanning etat) {
    if (etat.lectureSeule) return AppStrings.matriceSaisieIndisponibleSuspendue;
    if (!(ref.watch(enLigneProvider).value ?? true)) {
      return AppStrings.planningSaisieHorsLigne;
    }
    return null;
  }

  /// Pourquoi l'attribution est impossible, ou `null`.
  String? _raisonAttribution(EtatPlanning etat) {
    if (etat.lectureSeule) return AppStrings.matriceSaisieIndisponibleSuspendue;
    if (!(ref.watch(enLigneProvider).value ?? true)) {
      return AppStrings.planningSaisieHorsLigne;
    }
    // Le cas n'arrive pas encore — rien ne publie avant le ticket 019 — mais
    // l'écran ne le suppose pas.
    if (!etat.planning.modifiable) return AppStrings.planningPublieDetail;
    return null;
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
    final panneau = ref.watch(panneauCandidatsProvider);
    final destinations = AppDestination.pour(admin: admin);
    final indexAdmin = destinations.indexWhere(
      (AppDestination d) => d.route == _routeAdmin,
    );
    final compact = AppWindowClass.of(context).estCompact;

    return AppScaffold(
      titre: AppStrings.matriceTitre,
      // Sur grand écran, l'en-tête de la zone de travail porte le nom de la
      // caserne : le titre de l'écran, lui, est le mois, et il vit dans le
      // bandeau juste en dessous (`design/061 § 5`).
      caserne: ref.watch(appartenanceCouranteProvider)?.nomCaserne,
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
      actionsEnTete: const <Widget>[BoutonNotifications(), BoutonCompte()],
      banniere: _banniere(etat, asynchrone),
      // Le panneau du créneau prend la place que le brief du 016 lui avait
      // réservée ; `filActions` reçoit enfin le bouton « Publier » que le 016
      // avait annoncé et que le 017 a laissé vide.
      panneauLateral: panneau == null ? null : _panneau(panneau),
      // Sur grand écran, « Publier » est remonté dans la barre de commande :
      // le fil du bas n'a plus rien à porter (chantier 061c).
      filActions: compact
          ? _filActions(ref.watch(planningControllerProvider).value)
          : null,
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
    final etatPlanning = ref.watch(planningControllerProvider).value;
    final planning = etatPlanning?.planning ?? PlanningMois.vide();
    final creneauChoisi = ref.watch(creneauSelectionneProvider);

    final echelle = MediaQuery.textScalerOf(context).scale(16) / 16;
    final classe = AppWindowClass.of(context);
    final matriceVisible =
        classe.supporteDeuxVolets && echelle <= MatriceScreen.seuilVueJour;

    // Ce que la barre — et, sur grand écran, le bandeau — savent du planning.
    // **`null` tant que le planning n'est pas lu** : tant qu'on ne sait pas
    // s'il existe, on n'affirme ni qu'il existe ni le contraire.
    final commande = etatPlanning == null
        ? null
        : CommandePlanning(
            existe: planning.existe,
            etat: planning.planning?.etat ?? PlanningEtat.brouillon,
            canalBranche: etatPlanning.canalBranche,
            creation: etatPlanning.creation,
            onCreer: _raisonCreation(etatPlanning) != null
                ? null
                : () => unawaited(_creer()),
            raisonCreation: _raisonCreation(etatPlanning),
            resteAPourvoir: ref.watch(resteAPourvoirProvider),
            proposition: etatPlanning.proposition,
            onProposer: _raisonProposition(etatPlanning) != null
                ? null
                : () => unawaited(_proposer(etatPlanning)),
            raisonProposition: _raisonProposition(etatPlanning),
            // « Publier » vit dans le bandeau dès `expanded` (chantier 061c)
            // et sous la grille en `compact`, où la barre défile.
            publication: etatPlanning.publication,
            onPublier: matriceVisible && etatPlanning.planning.modifiable
                ? () => unawaited(_publier(etatPlanning))
                : null,
            raisonPublication: _raisonPublication(etatPlanning),
            detailPublication: AppStrings.publierDetail(
              _membresAttribues(etatPlanning),
            ),
          );

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
      planning: commande,
    );

    /// La zone du planning du bandeau, **sur grand écran seulement**.
    Widget? zonePlanning({required bool uneRangee}) =>
        !matriceVisible || commande == null
        ? null
        : ZonePlanning(
            planning: commande,
            mois: AppStrings.moisLongs[etat.periode.mois - 1],
            creneaux: etat.periode.nombreDeJours * 2,
            uneRangee: uneRangee,
          );

    // Les trois chiffres du mois, comptés sur les créneaux et les
    // attributions **déjà en mémoire** : aucune lecture de plus (ticket 061b).
    final bandeau = ResumeMois.construire(
      planning: planning,
      nombreDeJours: etat.periode.nombreDeJours,
    );

    // La vue par jour porte la barre de commande **dans son défilement** : un
    // téléphone n'a pas la hauteur pour deux blocs fixes. Le bandeau la suit,
    // réduit à sa ligne de chiffres ; la bande de semaine, elle, n'a pas
    // d'objet — la vue par jour a déjà son ruban, et il n'y a pas de matrice
    // à faire défiler.
    if (!matriceVisible && visibles.isNotEmpty) {
      return _zoneSaisie(
        arme: etat.modeArme,
        enfant: _vueJour(
          etat,
          visibles,
          filtres,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              barre,
              BandeauMois(resume: bandeau, compact: true),
            ],
          ),
          planning,
          creneauChoisi,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        barre,
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints contraintes) {
              final place = contraintes.maxHeight;
              // **L'état vide prend toute la place.** Un filtre qui ne rend
              // rien ouvre un message avec une sortie : la coincer sous deux
              // cents points de résumé, c'est la rendre inatteignable.
              final resume = visibles.isNotEmpty;
              final complet =
                  resume && place >= MatriceScreen.placeBandeauComplet;
              // **Réduit seulement si la rangée d'actions y tient.** Sur
              // une fenêtre étroite, elle se replierait sur deux lignes et
              // le bloc « réduit » serait plus haut que le bloc complet.
              final reduit =
                  resume &&
                  !complet &&
                  place >= MatriceScreen.placeBandeauReduit &&
                  (zonePlanning(uneRangee: true) == null ||
                      contraintes.maxWidth >=
                          BandeauMois.largeurReduitAvecActions);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (complet || reduit)
                    BandeauMois(
                      resume: bandeau,
                      compact: reduit,
                      actions: zonePlanning(uneRangee: reduit),
                    )
                  // **Le bandeau s'efface, pas la décision.** Sur une fenêtre
                  // trop courte pour ses chiffres, la zone du planning reste
                  // seule : un planning qu'on ne peut plus publier parce que
                  // la fenêtre est basse serait un cul-de-sac.
                  else if (resume &&
                      zonePlanning(uneRangee: true) != null &&
                      place >= MatriceScreen.placeZonePlanningSeule)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.sm,
                      ),
                      child: zonePlanning(uneRangee: true),
                    ),
                  Expanded(
                    child: visibles.isEmpty
                        ? _aucunResultat(filtres)
                        : _zoneSaisie(
                            arme: etat.modeArme,
                            enfant: _matrice(
                              etat,
                              visibles,
                              filtres,
                              planning,
                              creneauChoisi,
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _matrice(
    EtatMatrice etat,
    List<LigneMatrice> visibles,
    FiltresMatrice filtres,
    PlanningMois planning,
    String? creneauChoisi,
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
    planning: planning,
    creneauSelectionne: creneauChoisi,
    onCreneau: _ouvrirCreneau,
  );

  Widget _vueJour(
    EtatMatrice etat,
    List<LigneMatrice> visibles,
    FiltresMatrice filtres,
    Widget barre,
    PlanningMois planning,
    String? creneauChoisi,
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
    planning: planning,
    creneauSelectionne: creneauChoisi,
    onCreneau: _ouvrirCreneau,
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

  /// Une phrase passagère, et sa sortie quand il y en a une.
  ///
  /// **Huit secondes**, la durée retenue au ticket 024 : téléphone posé,
  /// regardé avec un temps de retard, parfois manipulé avec des gants.
  void _annoncer(
    String message, {
    String? libelleAction,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Semantics(liveRegion: true, child: Text(message)),
          showCloseIcon: true,
          duration: const Duration(seconds: 8),
          action: libelleAction == null || onAction == null
              ? null
              : SnackBarAction(label: libelleAction, onPressed: onAction),
        ),
      );
  }

  // -------------------------------------------------------------------
  // La bannière — au plus une
  // -------------------------------------------------------------------

  AppBanner? _banniere(EtatMatrice? etat, AsyncValue<EtatMatrice?> asynchrone) {
    if (etat == null) return null;

    final planning = ref.watch(planningControllerProvider).value;
    final horsLigne = !(ref.watch(enLigneProvider).value ?? true);
    // Une seule bannière à la fois : l'erreur de la matrice passe devant celle
    // du planning, parce que c'est elle qui décide de ce qui est lisible.
    final messageErreur = etat.messageErreur ?? planning?.messageErreur;
    // Trois sources pour un même fait, et c'est l'ordre du ticket 030 :
    // `etatCaserneProvider` le sait **avant** le premier geste, les deux autres
    // le déduisent d'un refus déjà essuyé.
    final fait = faitCaserneEcran(context, ref);
    final lectureSeule =
        etat.lectureSeule ||
        (planning?.lectureSeule ?? false) ||
        ref.watch(lectureSeuleCaserneProvider);
    final variantes = <AppBannerVariante>[
      if (messageErreur != null) AppBannerVariante.erreur,
      if (horsLigne) AppBannerVariante.horsLigne,
      if (lectureSeule) AppBannerVariante.lectureSeule,
      if (!etat.periode.ouverte) AppBannerVariante.verrouille,
      if (etat.modeArme) AppBannerVariante.attention,
      // Le fait d'abonnement (essai qui se termine) n'arbitre qu'ici, après le
      // mode armé : l'état de l'écran passe devant une échéance de facturation.
      if (fait != null && !lectureSeule) fait.variante,
      if (etat.matrice.vierge) AppBannerVariante.information,
    ];

    final gagnante = AppBannerVariante.prioritaire(variantes);
    if (gagnante == null) return null;

    return switch (gagnante) {
      AppBannerVariante.erreur => AppBanner(
        variante: AppBannerVariante.erreur,
        texte: messageErreur!,
        libelleAction: AppStrings.actionReessayer,
        onAction: _relire,
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
      AppBannerVariante.attention => etat.modeArme
          ? const AppBanner(
              variante: AppBannerVariante.attention,
              texte: AppStrings.matriceModeSaisieActif,
            )
          : fait?.banniere,
      AppBannerVariante.information =>
        fait?.variante == AppBannerVariante.information && !etat.matrice.vierge
            ? fait!.banniere
            : AppBanner(
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
