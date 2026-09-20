import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/reseau/connectivite.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_divider.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/entete_section.dart';
import '../../notifications/presentation/widgets/bouton_notifications.dart';
import '../domain/proposition.dart';
import '../domain/propositions_providers.dart';
import 'widgets/feuille_refus.dart';
import 'widgets/ligne_proposition.dart';
import 'widgets/squelette_propositions.dart';

/// **« Propositions »** — le deuxième écran du produit, et le seul qui promet
/// une réponse en **deux touches** : la notification, puis « Accepter ».
///
/// Tout ce qui pourrait s'ajouter sur ce chemin — une confirmation, un
/// indicateur de chargement, un écran de détail — coûterait la promesse. C'est
/// la contrainte qui décide de la forme de l'écran (`design/021 § 2`).
///
/// L'écran vit dans l'onglet 1 de la coquille d'accueil, là où le lien public
/// `/proposals` mène déjà depuis le ticket 024.
class PropositionsScreen extends ConsumerStatefulWidget {
  const PropositionsScreen({
    required this.destinations,
    required this.indexSelectionne,
    required this.onDestination,
    required this.onVersMonMois,
    super.key,
  });

  /// En dessous de cette largeur restante, les deux boutons retombent sous le
  /// corps de la ligne au lieu de se ranger à sa droite.
  static const double largeurActionsACote = 680;

  final List<AppDestination> destinations;
  final int indexSelectionne;
  final ValueChanged<int> onDestination;

  /// L'action de l'état vide : il n'y a rien à répondre, il y a un mois à
  /// saisir.
  final VoidCallback onVersMonMois;

  @override
  ConsumerState<PropositionsScreen> createState() => _PropositionsScreenState();
}

class _PropositionsScreenState extends ConsumerState<PropositionsScreen>
    with WidgetsBindingObserver {
  /// La bannière en cours, s'il y en a une. Elle survit au défilement et ne
  /// s'efface que sur un geste ou sur un rafraîchissement.
  NouvellePropositions? _bandeau;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// **Le cas exact du pompier qui revient de sa notification.**
  ///
  /// L'écran n'écoute pas de canal temps réel (`design/021 § 7.3`) : le retour
  /// au premier plan est le moment où la liste peut avoir vieilli, et c'est le
  /// seul qui mérite une requête. Le rafraîchissement est posé ici et non dans
  /// le contrôleur : celui-ci vit sur tous les onglets, et relire la liste au
  /// retour de la matrice admin serait une requête pour une pastille qui n'a
  /// pas bougé.
  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    if (etat == AppLifecycleState.resumed) _rafraichir();
  }

  void _rafraichir() {
    unawaited(ref.read(propositionsControllerProvider.notifier).rafraichir());
  }

  // -------------------------------------------------------------------
  // Les deux gestes
  // -------------------------------------------------------------------

  /// Une touche, rien de plus. Pas de confirmation : c'est le ticket.
  void _accepter(Proposition proposition) {
    unawaited(
      ref
          .read(propositionsControllerProvider.notifier)
          .repondre(proposition, accepte: true),
    );
  }

  /// Deux touches : la feuille de refus porte le motif court facultatif, et
  /// elle confirme. L'asymétrie est assumée (`design/021 § 6.3`).
  Future<void> _refuser(Proposition proposition) async {
    final creneau =
        '${dateAvecJourSemaine(proposition.jour)}, '
        '${context.statuts.creneau(proposition.creneau).libelle.toLowerCase()}';

    final motif = await demanderRefus(context, creneau: creneau);
    if (motif == null || !mounted) return;

    await ref
        .read(propositionsControllerProvider.notifier)
        .repondre(proposition, accepte: false, motif: motif);
  }

  // -------------------------------------------------------------------
  // Les nouvelles
  // -------------------------------------------------------------------

  /// Ce que l'écran fait d'une nouvelle : un message passager pour une réponse
  /// partie, une bannière pour ce qui doit rester lisible.
  void _recevoir(NouvellePropositions nouvelle) {
    switch (nouvelle) {
      case ReponseEnvoyee(:final proposition, :final accepte):
        _message(
          accepte
              ? AppStrings.propositionsAcceptee(_libelle(proposition))
              : AppStrings.propositionsRefusee(_libelle(proposition)),
        );
      case PropositionDisparue() ||
          ReponseEchouee() ||
          PlanningValide():
        setState(() => _bandeau = nouvelle);
    }
    ref.read(propositionsControllerProvider.notifier).nouvelleLue();
  }

  String _libelle(Proposition proposition) =>
      '${dateAvecJourSemaine(proposition.jour)}, '
      '${context.statuts.creneau(proposition.creneau).libelle.toLowerCase()}';

  void _message(String texte) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          // Sur le web, le contenu d'un `SnackBar` n'est pas annoncé tout
          // seul, et c'est précisément la réponse à un geste.
          content: Semantics(liveRegion: true, child: Text(texte)),
          showCloseIcon: true,
        ),
      );
  }

  // -------------------------------------------------------------------
  // Rendu
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen<NouvellePropositions?>(
      propositionsControllerProvider.select(
        (AsyncValue<EtatPropositions> valeur) => valeur.value?.nouvelle,
      ),
      (NouvellePropositions? _, NouvellePropositions? apres) {
        if (apres != null) _recevoir(apres);
      },
    );

    final etat = ref.watch(propositionsControllerProvider);
    final enLigne = ref.watch(enLigneProvider).value ?? true;
    final lectureSeule = etat.value?.lectureSeule ?? false;

    return AppScaffold(
      titre: AppStrings.propositionsTitre,
      destinations: widget.destinations,
      indexSelectionne: widget.indexSelectionne,
      onDestination: widget.onDestination,
      actions: <Widget>[
        // Le geste de tirage n'est jamais le seul chemin : il lui faut son
        // équivalent visible, au clavier comme à la souris.
        IconButton(
          onPressed: _rafraichir,
          icon: const Icon(Icons.refresh),
          tooltip: AppStrings.propositionsRafraichir,
        ),
        const BoutonNotifications(),
      ],
      banniere: _banniere(enLigne: enLigne, lectureSeule: lectureSeule),
      child: _corps(
        etat: etat,
        raisonBlocage: _raisonBlocage(
          enLigne: enLigne,
          lectureSeule: lectureSeule,
        ),
      ),
    );
  }

  String? _raisonBlocage({
    required bool enLigne,
    required bool lectureSeule,
  }) {
    if (lectureSeule) return AppStrings.propositionsLectureSeuleRaison;
    if (!enLigne) return AppStrings.propositionsHorsLigneRaison;
    return null;
  }

  /// **Une seule bannière à la fois**, par l'ordre de priorité du système :
  /// erreur > hors-ligne > lecture-seule > information.
  AppBanner? _banniere({required bool enLigne, required bool lectureSeule}) {
    final bandeau = _bandeau;

    if (bandeau case ReponseEchouee(:final message)) {
      return AppBanner(
        variante: AppBannerVariante.erreur,
        texte: AppStrings.propositionsEchecTitre,
        detail: message,
        libelleAction: AppStrings.actionReessayer,
        onAction: () {
          setState(() => _bandeau = null);
          _rafraichir();
        },
      );
    }

    if (!enLigne) {
      return const AppBanner(
        variante: AppBannerVariante.horsLigne,
        texte: AppStrings.propositionsHorsLigneRaison,
      );
    }

    if (lectureSeule) {
      return const AppBanner(
        variante: AppBannerVariante.lectureSeule,
        texte: AppStrings.propositionsLectureSeuleRaison,
      );
    }

    return switch (bandeau) {
      PropositionDisparue(:final proposition) => AppBanner(
        variante: AppBannerVariante.information,
        icone: Icons.swap_horiz,
        texte: AppStrings.propositionsDisparue,
        detail: AppStrings.propositionsDisparueDetail(_libelle(proposition)),
        onFermer: () => setState(() => _bandeau = null),
        libelleFermer: AppStrings.propositionsDisparueFermer,
      ),
      PlanningValide(:final nomMois) => AppBanner(
        variante: AppBannerVariante.information,
        icone: Icons.verified,
        texte: AppStrings.propositionsPlanningValide(nomMois),
        onFermer: () => setState(() => _bandeau = null),
        libelleFermer: AppStrings.propositionsPlanningValideFermer,
      ),
      _ => null,
    };
  }

  Widget _corps({
    required AsyncValue<EtatPropositions> etat,
    required String? raisonBlocage,
  }) {
    if (etat.isLoading && !etat.hasValue) {
      return const SquelettePropositions();
    }

    if (etat.hasError && !etat.hasValue) {
      return EmptyState.erreur(
        texte: AppStrings.propositionsErreurTexte,
        onAction: _rafraichir,
      );
    }

    final valeur = etat.value ?? const EtatPropositions();
    if (valeur.vide) {
      return RefreshIndicator(
        onRefresh: ref.read(propositionsControllerProvider.notifier).rafraichir,
        // L'état vide doit rester tirable : c'est la façon dont on vérifie
        // qu'il n'y a vraiment rien.
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.6,
              child: EmptyState(
                titre: AppStrings.videPropositionsTitre,
                texte: AppStrings.videPropositionsTexte,
                libelleAction: AppStrings.propositionsVideAction,
                onAction: widget.onVersMonMois,
              ),
            ),
          ],
        ),
      );
    }

    return _Liste(
      elements: ref.watch(elementsPropositionsProvider),
      raisonBlocage: raisonBlocage,
      onAccepter: _accepter,
      onRefuser: (Proposition proposition) =>
          unawaited(_refuser(proposition)),
      onRafraichir:
          ref.read(propositionsControllerProvider.notifier).rafraichir,
    );
  }
}

/// La liste, groupée par mois et **virtualisée**.
///
/// Soixante-deux propositions sont légales (`design/021 § 5.1`) : la liste est
/// construite par `ListView.builder` sur des éléments aplatis une fois par
/// état, et les en-têtes de mois défilent avec le contenu — ils ne sont pas
/// collants. À trois propositions typiques, un en-tête épinglé volerait 44 dp
/// pour ne rien dire de plus que la ligne qu'il surplombe.
class _Liste extends StatelessWidget {
  const _Liste({
    required this.elements,
    required this.raisonBlocage,
    required this.onAccepter,
    required this.onRefuser,
    required this.onRafraichir,
  });

  final List<ElementListe> elements;
  final String? raisonBlocage;
  final ValueChanged<Proposition> onAccepter;
  final ValueChanged<Proposition> onRefuser;
  final Future<void> Function() onRafraichir;

  @override
  Widget build(BuildContext context) {
    final classe = AppWindowClass.of(context);
    final marge = switch (classe) {
      AppWindowClass.compact => AppSpacing.pageCompact,
      AppWindowClass.medium || AppWindowClass.expanded => AppSpacing.pageMedium,
      AppWindowClass.large => AppSpacing.pageLarge,
    };

    return RefreshIndicator(
      onRefresh: onRafraichir,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints contraintes) {
          // Les deux boutons ne remontent à droite du corps que si la largeur
          // le permet **vraiment** : sous ce seuil, ils compriment la date au
          // point de la couper en deux dès que l'échelle de texte grandit.
          final aCote =
              contraintes.maxWidth >= PropositionsScreen.largeurActionsACote;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.colonneMax,
              ),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.xxl),
                itemCount: elements.length,
                itemBuilder: (BuildContext context, int index) {
                  final element = elements[index];
                  return switch (element) {
                    EnteteMois() => EnteteSection(
                      titre: element.libelle,
                      compte: AppStrings.propositionsCompte(element.compte),
                      premiere: element.premier,
                    ),
                    LigneProposition(:final proposition) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        LigneDeProposition(
                          key: ValueKey<String>(proposition.id),
                          proposition: proposition,
                          actionsACote: aCote,
                          raisonBlocage: raisonBlocage,
                          onAccepter: () => onAccepter(proposition),
                          onRefuser: () => onRefuser(proposition),
                        ),
                        if (_suivante(index) is LigneProposition)
                          const AppDivider(),
                      ],
                    ),
                  };
                },
              ),
            ),
          );
        },
      ),
    );
  }

  ElementListe? _suivante(int index) =>
      index + 1 < elements.length ? elements[index + 1] : null;
}
