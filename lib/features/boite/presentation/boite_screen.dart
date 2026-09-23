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
import '../../../core/session/session_providers.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/banniere_caserne.dart';
import '../../../core/widgets/barre_actions_basse.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/primary_button.dart';
import '../../astreintes/domain/astreinte.dart';
import '../../astreintes/domain/astreintes_providers.dart';
import '../../notifications/domain/centre_providers.dart';
import '../../notifications/domain/destination_push.dart';
import '../../notifications/domain/notification_interne.dart';
import '../../profil/presentation/widgets/bouton_compte.dart';
import '../../propositions/domain/proposition.dart';
import '../../propositions/domain/propositions_providers.dart';
import '../../propositions/presentation/widgets/feuille_refus.dart';
import '../domain/composition_boite.dart';
import '../domain/onglet_boite.dart';
import 'widgets/liste_boite.dart';
import 'widgets/panneau_reponse.dart';
import 'widgets/squelette_boite.dart';

/// **La Boîte** — le journal de bord du pompier, et ce à quoi il doit
/// répondre.
///
/// Quatrième destination (ticket 064), à la route `/boite`. Elle réunit depuis
/// le chantier 064b les deux écrans qui vivaient à côté l'un de l'autre : le
/// centre de notifications du ticket 026 et les propositions du ticket 021.
/// Trois onglets, `design/064 § 3.4` : **Tout**, **Propositions**, **Rappels**.
///
/// C'est **le filet du produit** quand le push n'arrive pas — iPhone hors
/// écran d'accueil, autorisation refusée, batterie économisée. Une proposition
/// d'astreinte jamais lue est une garde non couverte, et cet écran est le seul
/// endroit où elle reste visible.
///
/// **L'onglet est dans l'URL**, jamais dans un cache : `/boite?onglet=
/// propositions` est l'adresse de « Tout voir » de l'accueil, du lien public
/// `/proposals` et de l'ancienne route `/propositions`.
class BoiteScreen extends ConsumerStatefulWidget {
  const BoiteScreen({required this.onglet, super.key});

  final OngletBoite onglet;

  @override
  ConsumerState<BoiteScreen> createState() => _BoiteScreenState();
}

class _BoiteScreenState extends ConsumerState<BoiteScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _onglets;

  /// La durée avec laquelle [_onglets] a été construit. Le contrôleur la porte
  /// en champ final : la refaire est le seul moyen d'obéir à Reduce Motion
  /// quand la préférence change en cours de session.
  Duration? _dureeOnglets;

  /// Une action de notification est en cours : les lignes n'ouvrent rien le
  /// temps de l'aller-retour, sinon deux touches rapides partent deux fois.
  bool _occupe = false;

  /// La bannière des propositions, s'il y en a une. Elle survit au défilement
  /// et ne s'efface que sur un geste ou sur un rafraîchissement.
  NouvellePropositions? _bandeau;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // **Relire à l'ouverture.** Les deux contrôleurs sont gardés en vie pour
    // la pastille : arriver ici ne les relit pas tout seul, et un onglet
    // laissé ouvert une heure rouvrirait la Boîte sur la liste d'il y a une
    // heure. Reporté d'une image, modifier un provider pendant `initState`
    // étant interdit par Riverpod.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _relire();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce Motion est une contrainte produit, pas une option
    // (`DESIGN.md § Motion`) : l'indicateur d'onglet ne glisse pas quand elle
    // est active.
    final duree = AppMotion.duree(context, AppDuration.instantane);
    if (duree == _dureeOnglets) return;

    final index = _dureeOnglets == null ? widget.onglet.index : _onglets.index;
    if (_dureeOnglets != null) {
      final ancien = _onglets;
      ancien.removeListener(_suivreOnglet);
      // Différé d'une image : la `TabBar` de l'image en cours l'écoute encore,
      // et elle ne se détachera qu'à sa prochaine construction.
      WidgetsBinding.instance.addPostFrameCallback((_) => ancien.dispose());
    }
    _dureeOnglets = duree;
    _onglets = TabController(
      length: OngletBoite.values.length,
      vsync: this,
      initialIndex: index,
      animationDuration: duree,
    )..addListener(_suivreOnglet);
  }

  @override
  void didUpdateWidget(BoiteScreen ancien) {
    super.didUpdateWidget(ancien);
    // L'URL commande : un lien profond, « Tout voir » de l'accueil ou le
    // bouton précédent du navigateur amènent l'onglet ici.
    if (widget.onglet.index != _onglets.index) {
      _onglets.animateTo(widget.onglet.index);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _onglets
      ..removeListener(_suivreOnglet)
      ..dispose();
    super.dispose();
  }

  /// **Le cas exact du pompier qui revient de sa notification.** La Boîte
  /// n'écoute aucun canal temps réel (`design/021 § 7.3`, `design/026 § 6`) :
  /// le retour au premier plan est le seul moment qui mérite une requête.
  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    if (etat == AppLifecycleState.resumed) _relire();
  }

  /// L'onglet suit le doigt, et l'URL suit l'onglet.
  ///
  /// `indexIsChanging` est vrai pendant toute l'animation : on n'écrit
  /// l'adresse qu'une fois, à l'arrivée.
  void _suivreOnglet() {
    if (_onglets.indexIsChanging) return;
    final onglet = OngletBoite.values[_onglets.index];
    if (onglet == widget.onglet) return;
    context.goNamed(
      AppRoutes.boiteName,
      queryParameters: <String, String>{
        AppRoutes.parametreOnglet: onglet.valeurUrl,
      },
    );
  }

  void _relire() {
    unawaited(ref.read(centreNotificationsProvider.notifier).rafraichir());
    unawaited(ref.read(propositionsControllerProvider.notifier).rafraichir());
  }

  // -------------------------------------------------------------------
  // Les rappels : une touche, deux effets
  // -------------------------------------------------------------------

  /// Une touche fait **deux choses dans le même mouvement** : la ligne passe
  /// lue, et la destination s'ouvre.
  ///
  /// La destination passe par `destinationInterne` (ticket 024), **la même
  /// fonction que le push**, et pas une seconde. Un lien inconnu ou refusé
  /// ramène à l'accueil **sans message d'erreur** : le membre n'a rien fait de
  /// mal, et le lien peut dater d'avant une rétrogradation.
  Future<void> _ouvrirRappel(NotificationInterne notification) async {
    if (_occupe) return;
    setState(() => _occupe = true);

    final admin = ref.read(appartenanceCouranteProvider)?.estAdmin ?? false;
    final destination =
        destinationInterne(notification.route, admin: admin) ??
        AppRoutes.accueil;

    // Le marquage part d'abord, mais la navigation ne l'attend pas : elle est
    // ce que le pompier a demandé. Un réseau lent ne doit pas retenir l'écran.
    final marquage = ref
        .read(centreNotificationsProvider.notifier)
        .marquerLue(notification);

    ref.read(appRouterProvider).go(destination);

    final reussi = await marquage;
    if (!mounted) return;
    setState(() => _occupe = false);
    if (!reussi) _annoncer(AppStrings.centreEchecLecture);
  }

  Future<void> _toutMarquerLu() async {
    if (_occupe) return;
    setState(() => _occupe = true);

    final reussi = await ref
        .read(centreNotificationsProvider.notifier)
        .toutMarquerLu();

    if (!mounted) return;
    setState(() => _occupe = false);
    _annoncer(
      reussi
          ? AppStrings.centreToutMarqueLuConfirmation
          : AppStrings.centreEchecLecture,
    );
  }

  // -------------------------------------------------------------------
  // Les propositions : ouvrir la réponse, puis répondre
  // -------------------------------------------------------------------

  /// Ouvre la réponse : le volet de droite en `large`, une feuille de bas
  /// d'écran en dessous. Jamais un dialogue (`DESIGN.md § Don't`).
  void _ouvrirReponse(Proposition proposition) {
    ref.read(propositionEnReponseProvider.notifier).choisir(proposition.id);
    if (!AppWindowClass.of(context).estLarge) unawaited(_ouvrirFeuille());
  }

  Future<void> _ouvrirFeuille() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext contexteFeuille) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) {
          final proposition = ref.watch(propositionOuverteProvider);
          if (proposition == null) return const SizedBox.shrink();
          return SafeArea(top: false, child: _panneau(proposition));
        },
      ),
    );
    // Le geste retour ferme la feuille : la sélection doit suivre, sinon la
    // ligne reste choisie sans rien derrière.
    if (mounted) ref.read(propositionEnReponseProvider.notifier).fermer();
  }

  /// Referme la réponse, quel que soit le contenant. La feuille est une route
  /// à elle : la dépiler est le seul moyen de la faire disparaître.
  void _fermerReponse() {
    final selection = ref.read(propositionEnReponseProvider);
    if (selection == null) return;
    ref.read(propositionEnReponseProvider.notifier).fermer();
    if (!AppWindowClass.of(context).estLarge) Navigator.of(context).pop();
  }

  /// Une touche, rien de plus. Pas de confirmation : c'est le ticket 021.
  void _accepter(Proposition proposition) {
    _fermerReponse();
    unawaited(
      ref
          .read(propositionsControllerProvider.notifier)
          .repondre(proposition, accepte: true),
    );
  }

  /// Deux touches : la feuille de refus porte le motif court facultatif, et
  /// elle confirme. L'asymétrie est assumée (`design/021 § 6.3`).
  Future<void> _refuser(Proposition proposition) async {
    final creneau = _libelle(proposition);
    final motif = await demanderRefus(context, creneau: creneau);
    if (motif == null || !mounted) return;

    _fermerReponse();
    await ref
        .read(propositionsControllerProvider.notifier)
        .repondre(proposition, accepte: false, motif: motif);
  }

  // -------------------------------------------------------------------
  // Les nouvelles des propositions
  // -------------------------------------------------------------------

  /// Ce que l'écran fait d'une nouvelle : un message passager pour une réponse
  /// partie, une bannière pour ce qui doit rester lisible.
  void _recevoir(NouvellePropositions nouvelle) {
    switch (nouvelle) {
      case ReponseEnvoyee(:final proposition, :final accepte):
        _annoncer(
          accepte
              ? AppStrings.propositionsAcceptee(_libelle(proposition))
              : AppStrings.propositionsRefusee(_libelle(proposition)),
        );
      case PropositionDisparue() || ReponseEchouee() || PlanningValide():
        setState(() => _bandeau = nouvelle);
    }
    ref.read(propositionsControllerProvider.notifier).nouvelleLue();
  }

  String _libelle(Proposition proposition) =>
      '${dateAvecJourSemaine(proposition.jour)}, '
      '${context.statuts.creneau(proposition.creneau).libelle.toLowerCase()}';

  void _annoncer(String texte) {
    final messager = ScaffoldMessenger.maybeOf(context);
    if (messager == null) return;
    messager
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

    final etat = ref.watch(etatBoiteProvider);
    final destinations = ref.watch(destinationsProvider);
    final enLigne = ref.watch(enLigneProvider).value ?? true;
    // Deux sources pour un même fait, et c'est voulu : `etatCaserneProvider`
    // le sait **avant** le premier geste (ticket 030), `lectureSeule` le
    // déduit d'un refus du serveur. La seconde reste le filet — une Boîte
    // ouverte depuis dix minutes peut avoir manqué une suspension.
    final lectureSeule =
        (ref.watch(propositionsControllerProvider).value?.lectureSeule ??
            false) ||
        ref.watch(lectureSeuleCaserneProvider);
    final raisonBlocage = _raisonBlocage(
      enLigne: enLigne,
      lectureSeule: lectureSeule,
    );
    final ouverte = ref.watch(propositionOuverteProvider);
    final grand = AppWindowClass.of(context).estLarge;

    return AppScaffold(
      titre: AppStrings.boiteTitre(etat.nonLus),
      destinations: destinations,
      indexSelectionne: indexDestination(destinations, AppRoutes.boiteName),
      onDestination: (int index) =>
          allerVersDestination(context, destinations, index),
      // **La matière du monde du pompier** (`design/064 § 2`) : fond de page
      // `surface-container-low`, lignes en cartes `surface` à filet.
      fondDoux: true,
      actions: <Widget>[
        IconButton(
          onPressed: _relire,
          icon: const Icon(Icons.refresh),
          tooltip: AppStrings.boiteRafraichir,
        ),
        // Pas de cloche ici : elle mène à l'écran qu'elle occupe. Le compte
        // qu'elle porte ailleurs est dans le titre.
        const BoutonCompte(),
      ],
      banniere: _banniere(
        enLigne: enLigne,
        lectureSeule: lectureSeule,
        fait: faitCaserneEcran(context, ref),
      ),
      // Le volet de droite ne prend la réponse qu'en `large` ; en dessous,
      // c'est la feuille de bas d'écran (`_ouvrirFeuille`).
      panneauLateral: grand && ouverte != null
          ? _panneau(ouverte, etendu: true)
          : null,
      child: Column(
        children: <Widget>[
          _BarreOnglets(controleur: _onglets),
          Expanded(
            child: _corps(etat: etat, raisonBlocage: raisonBlocage),
          ),
          // Le bouton n'apparaît que s'il y a quelque chose à marquer. Un
          // bouton désactivé qu'il faudrait expliquer à côté vaut moins qu'un
          // bouton absent (`design/026 § 3`). Absent aussi de l'onglet
          // « Propositions », où il ne marquerait rien de ce qui est à
          // l'écran.
          if (etat.nonLus > 0 && widget.onglet != OngletBoite.propositions)
            BarreActionsBasse(
              child: PrimaryButton(
                libelle: AppStrings.centreToutMarquerLu,
                icone: Icons.done_all,
                variante: PrimaryButtonVariante.secondaire,
                chargement: _occupe,
                onPressed: () => unawaited(_toutMarquerLu()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panneau(Proposition proposition, {bool etendu = false}) =>
      PanneauReponse(
        proposition: proposition,
        etendu: etendu,
    heures: _heures(),
    raisonBlocage: _raisonBlocage(
      enLigne: ref.watch(enLigneProvider).value ?? true,
      lectureSeule:
          (ref.watch(propositionsControllerProvider).value?.lectureSeule ??
              false) ||
          ref.watch(lectureSeuleCaserneProvider),
    ),
    maintenant: ref.watch(horlogeAstreintesProvider)(),
    onAccepter: () => _accepter(proposition),
    onRefuser: () => unawaited(_refuser(proposition)),
    onFermer: _fermerReponse,
  );

  /// Les heures d'affichage de la caserne.
  ///
  /// **Aucune lecture propre à la Boîte** : elles voyagent avec les astreintes
  /// (ticket 027), dont le contrôleur n'est pas auto-disposé et vit déjà
  /// depuis l'accueil, la route d'ouverture de l'application. Tant qu'il n'a
  /// rien rendu, la Boîte affiche les valeurs par défaut de la colonne
  /// `settings` — exactement ce que `lireHeuresAffichage` rend elle-même quand
  /// la caserne est illisible.
  HeuresAffichage _heures() =>
      ref.watch(astreintesControllerProvider).value?.donnees.heures ??
      HeuresAffichage.defaut;

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
  AppBanner? _banniere({
    required bool enLigne,
    required bool lectureSeule,
    required FaitCaserne? fait,
  }) {
    final bandeau = _bandeau;

    if (bandeau case ReponseEchouee(:final message)) {
      return AppBanner(
        variante: AppBannerVariante.erreur,
        texte: AppStrings.propositionsEchecTitre,
        detail: message,
        libelleAction: AppStrings.actionReessayer,
        onAction: () {
          setState(() => _bandeau = null);
          _relire();
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
      // La bannière du système quand l'état est lu (elle porte la date et,
      // pour un admin, la sortie) ; la phrase propre à l'écran sinon — c'est
      // le cas d'un refus serveur essuyé avant que l'état n'arrive.
      return fait?.variante == AppBannerVariante.lectureSeule
          ? fait!.banniere
          : const AppBanner(
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

  Widget _corps({required EtatBoite etat, required String? raisonBlocage}) {
    final maintenant = ref.watch(horlogeAstreintesProvider)();

    return switch (widget.onglet) {
      OngletBoite.tout => ListeTout(
        etat: etat,
        heures: _heures(),
        maintenant: maintenant,
        onProposition: _ouvrirReponse,
        onRappel: (NotificationInterne rappel) =>
            unawaited(_ouvrirRappel(rappel)),
        onRelire: _relire,
      ),
      OngletBoite.propositions => _corpsPropositions(
        etat: etat,
        maintenant: maintenant,
      ),
      OngletBoite.rappels => _corpsRappels(etat: etat, maintenant: maintenant),
    };
  }

  Widget _corpsPropositions({
    required EtatBoite etat,
    required DateTime maintenant,
  }) {
    if (etat.chargePropositions) return const SqueletteBoite();
    if (etat.echecPropositions) {
      return EmptyState.erreur(
        texte: AppStrings.propositionsErreurTexte,
        onAction: _relire,
      );
    }
    if (etat.propositions.isEmpty) {
      return EmptyState(
        titre: AppStrings.videPropositionsTitre,
        texte: AppStrings.videPropositionsTexte,
        libelleAction: AppStrings.propositionsVideAction,
        onAction: () => context.goNamed(AppRoutes.calendrierName),
      );
    }
    return ListePropositions(
      elements: ref.watch(elementsPropositionsProvider),
      heures: _heures(),
      maintenant: maintenant,
      onOuvrir: _ouvrirReponse,
      onRelire: _relire,
    );
  }

  Widget _corpsRappels({
    required EtatBoite etat,
    required DateTime maintenant,
  }) {
    if (etat.chargeRappels) return const SqueletteBoite();
    if (etat.echecRappels) {
      return EmptyState.erreur(
        texte: AppStrings.centreErreurTexte,
        onAction: _relire,
      );
    }
    if (etat.rappels.isEmpty) {
      // Pas d'action : il n'y a rien à faire, et le dire est plus honnête
      // qu'un bouton qui n'irait nulle part.
      return const EmptyState(
        titre: AppStrings.boiteVideRappelsTitre,
        texte: AppStrings.boiteVideRappelsTexte,
        icone: Icons.notifications_none_outlined,
      );
    }
    return ListeRappels(
      rappels: etat.rappels,
      maintenant: maintenant,
      onOuvrir: (NotificationInterne rappel) =>
          unawaited(_ouvrirRappel(rappel)),
      onRelire: _relire,
    );
  }
}

/// Les trois onglets.
///
/// **Ils ne se glissent pas.** Le contenu change sous la barre, il ne passe
/// pas de côté : le ticket 063 a retiré le glissement entre destinations, et
/// `DESIGN.md § Zones sûres` réserve les vingt-quatre premiers points du bord
/// gauche au geste retour du navigateur, que le pompier utilise en PWA
/// installée. Reste l'indicateur, qui dit lequel des trois porte le contenu.
class _BarreOnglets extends StatelessWidget {
  const _BarreOnglets({required this.controleur});

  final TabController controleur;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
      // **Pleine largeur, et le rembourrage des libellés au minimum.** Trois
      // onglets se partagent la largeur à parts égales : à 390 points, la
      // marge de page et les 32 points de rembourrage par défaut de `Tab`
      // laissaient 92 points à « Propositions », qui en demande 102 — le mot
      // s'éteignait sur son « s », vu dans Chrome. Une barre d'onglets est
      // d'ailleurs un bandeau de commande, comme le filet qu'elle porte : elle
      // va d'un bord à l'autre.
      child: TabBar(
        controller: controleur,
        labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        tabs: <Widget>[
          for (final onglet in OngletBoite.values)
            Tab(
              height: AppTouch.cible,
              child: Text(
                onglet.libelle,
                semanticsLabel: onglet.annonce,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
              ),
            ),
        ],
      ),
    ),
  );
}
