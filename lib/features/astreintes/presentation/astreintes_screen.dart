import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/reseau/connectivite.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/destinations.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_banner.dart';
import '../../../core/widgets/app_divider.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/entete_section.dart';
import '../../notifications/presentation/widgets/bouton_notifications.dart';
import '../../profil/presentation/widgets/bouton_compte.dart';
import '../domain/astreinte.dart';
import '../domain/astreintes_providers.dart';
import '../domain/planning_caserne.dart';
import '../domain/planning_caserne_providers.dart';
import 'widgets/bascule_vue.dart';
import 'widgets/calendrier_astreintes.dart';
import 'widgets/feuille_astreinte.dart';
import 'widgets/ligne_astreinte.dart';
import 'widgets/squelette_astreintes.dart';
import 'widgets/vue_planning_caserne.dart';

/// **« Astreintes »** — l'écran que ce produit affichera le plus souvent une
/// fois le planning validé.
///
/// Il répond à une question posée à deux échelles — « suis-je d'astreinte, et
/// quand ? » puis « qui est d'astreinte ? » — et il doit y répondre **sans
/// réseau** : une caserne est un bâtiment de béton dans une zone rurale
/// (`design/027 § 1`). La source de vérité de l'affichage est donc le cache
/// local, et la requête vient par-dessus.
///
/// **Les deux portées sont deux filtres d'une même donnée**, pas deux écrans :
/// même table `assignments`, même politique — mes attributions dès `published`,
/// celles de toute la caserne dès `validated` (`design/027 § 4`,
/// `design/023 § 2`). D'où un sélecteur en tête, et non une sixième
/// destination.
///
/// L'écran est la destination « Astreintes », à la route `/astreintes` depuis
/// le ticket 064, où mène le lien public `/schedule/<période>` d'une
/// notification de planning validé.
class AstreintesScreen extends ConsumerStatefulWidget {
  const AstreintesScreen({super.key});

  /// Au-delà de cette échelle de texte, la vue calendrier **change de forme**
  /// plutôt que de rogner : elle cède la place à la liste
  /// (`DESIGN.md § Typography — Named Rules`).
  static const double echelleMaxCalendrier = 1.6;


  @override
  ConsumerState<AstreintesScreen> createState() => _AstreintesScreenState();
}

class _AstreintesScreenState extends ConsumerState<AstreintesScreen>
    with WidgetsBindingObserver {
  VueAstreintes _vue = VueAstreintes.liste;

  /// Le mois affiché par le calendrier. `null` tant qu'il n'a pas été ouvert :
  /// il s'ouvre alors sur le mois courant.
  DateTime? _mois;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // **Le cache d'abord, la requête ensuite.** `build()` du contrôleur rend
    // l'instantané local sans attendre le réseau ; c'est ici, à la première
    // image, qu'on va chercher mieux.
    //
    // Et à **chaque** ouverture de l'écran, pas seulement quand l'instantané
    // vient du cache : le contrôleur n'est pas auto-disposé, donc une
    // proposition acceptée sur l'onglet voisin ne le réveillerait jamais.
    // Trouvé dans Chrome — accepter puis passer ici ne montrait rien
    // (`design/027 § 11`). Le rafraîchissement ne vide pas l'écran : il
    // remplace ce qui est déjà lisible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rafraichir();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Le retour au premier plan est le seul moment où la liste peut avoir
  /// vieilli sans qu'on l'ait demandé. Posé dans l'écran et non dans le
  /// contrôleur, qui vit sur tous les onglets (même raison qu'au ticket 021).
  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    if (etat == AppLifecycleState.resumed) _rafraichir();
  }

  /// Rafraîchit **la portée affichée**, pas les deux : lire le planning entier
  /// de la caserne pour quelqu'un qui regarde ses propres dates serait trois
  /// requêtes pour rien, sur un réseau qu'on sait mauvais.
  void _rafraichir() {
    unawaited(
      ref.read(porteeAstreintesProvider) == PorteeAstreintes.caserne
          ? ref.read(planningCaserneControllerProvider.notifier).rafraichir()
          : ref.read(astreintesControllerProvider.notifier).rafraichir(),
    );
  }

  void _choisirPortee(PorteeAstreintes portee) {
    ref.read(porteeAstreintesProvider.notifier).choisir(portee);
    // La portée qu'on vient d'ouvrir va chercher mieux que son cache, tout de
    // suite : elle a pu vieillir pendant qu'on regardait l'autre.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rafraichir();
    });
  }

  void _ouvrir(List<Astreinte> astreintes, HeuresAffichage heures) {
    unawaited(
      ouvrirDetailAstreinte(
        context,
        astreintes: astreintes,
        heures: heures,
        // Le nom de la caserne n'est pas affiché par la feuille : il part dans
        // le fichier calendrier, où l'événement doit dire d'où il vient — un
        // pompier peut appartenir à deux centres (ticket 028).
        nomCaserne: ref.read(appartenanceCouranteProvider)?.nomCaserne ?? '',
      ),
    );
  }

  /// Vrai quand le calendrier ne tient plus : au-delà de ×1,6, sept colonnes
  /// coupent leurs chiffres.
  bool get _calendrierTropGrand =>
      MediaQuery.textScalerOf(context).scale(16) / 16 >
      AstreintesScreen.echelleMaxCalendrier;

  @override
  Widget build(BuildContext context) {
    final portee = ref.watch(porteeAstreintesProvider);
    final caserne = portee == PorteeAstreintes.caserne;
    final enLigne = ref.watch(enLigneProvider).value ?? true;
    final destinations = ref.watch(destinationsProvider);

    return AppScaffold(
      // Le titre suit la portée : la barre d'application est ce qu'un lecteur
      // d'écran annonce en arrivant, et « Mes astreintes » serait faux de
      // l'autre côté du sélecteur.
      titre: caserne
          ? AppStrings.planningCaserneTitre
          : AppStrings.astreintesTitre,
      destinations: destinations,
      indexSelectionne: indexDestination(
        destinations,
        AppRoutes.astreintesName,
      ),
      onDestination: (index) =>
          allerVersDestination(context, destinations, index),
      actions: <Widget>[
        // Le geste de tirage n'est jamais le seul chemin : il lui faut son
        // équivalent visible, au clavier comme à la souris.
        IconButton(
          onPressed: _rafraichir,
          icon: const Icon(Icons.refresh),
          tooltip: caserne
              ? AppStrings.planningCaserneRafraichir
              : AppStrings.astreintesRafraichir,
        ),
        const BoutonNotifications(),
        const BoutonCompte(),
      ],
      banniere: caserne
          ? _banniereCaserne(enLigne: enLigne)
          : _banniereMoi(enLigne: enLigne),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          BasculePortee(portee: portee, onChoisir: _choisirPortee),
          const AppDivider(),
          Expanded(child: caserne ? _corpsCaserne() : _corpsMoi()),
        ],
      ),
    );
  }

  /// La ligne de fraîcheur, commune aux deux portées : « Dernière mise à
  /// jour : il y a 2 h. »
  String? _fraicheur(DateTime? instant) => instant == null
      ? null
      : AppStrings.astreintesFraicheur(
          // La même horloge que le tri « à venir » / « passé ». Deux horloges
          // sur un même écran finissent toujours par se contredire.
          formaterInstantRelatif(
            instant,
            maintenant: ref.read(horlogeAstreintesProvider)(),
          ),
        );

  /// **Une seule bannière à la fois**, par l'ordre de priorité du système.
  ///
  /// Hors ligne, cet écran ne promet pas d'envoyer des modifications — il ne
  /// fait que lire. Ce qu'il dit, c'est l'âge de ce qu'on lit
  /// (`design/027 § 9`).
  AppBanner? _banniereMoi({required bool enLigne}) {
    final valeur = ref.watch(astreintesControllerProvider).value;
    if (valeur == null) return null;
    final detail = _fraicheur(valeur.donnees.luLe);

    if (!enLigne) {
      return AppBanner(
        variante: AppBannerVariante.horsLigne,
        texte: AppStrings.astreintesHorsLigne,
        detail: detail,
      );
    }

    if (valeur.depuisCache) {
      return AppBanner(
        variante: AppBannerVariante.attention,
        texte: AppStrings.astreintesNonActualisees,
        detail: detail,
        libelleAction: AppStrings.actionReessayer,
        onAction: _rafraichir,
      );
    }

    return null;
  }

  /// La même mécanique côté caserne. **Le bloc « planning publié » n'est pas
  /// ici** : ce fait n'est pas transverse, il décrit le mois affiché, et un
  /// pompier hors ligne perdrait l'explication dont il a besoin
  /// (`design/023 § 4`).
  AppBanner? _banniereCaserne({required bool enLigne}) {
    final valeur = ref.watch(planningCaserneControllerProvider).value;
    if (valeur == null) return null;
    final detail = _fraicheur(valeur.planning?.luLe);

    if (!enLigne) {
      return AppBanner(
        variante: AppBannerVariante.horsLigne,
        texte: AppStrings.astreintesHorsLigne,
        detail: detail,
      );
    }

    // Seulement quand il reste quelque chose de lisible à l'écran : un mois
    // qui n'a rien du tout porte son échec dans son corps, pas en bandeau.
    if (valeur.depuisCache && valeur.planning != null) {
      return AppBanner(
        variante: AppBannerVariante.attention,
        texte: AppStrings.planningCaserneNonActualise,
        detail: detail,
        libelleAction: AppStrings.actionReessayer,
        onAction: _rafraichir,
      );
    }

    return null;
  }

  Widget _corpsCaserne() {
    final etat = ref.watch(planningCaserneControllerProvider);

    if (etat.isLoading && !etat.hasValue) {
      return const SquelettePlanningCaserne();
    }

    // **Un échec sans aucun mois est un échec, pas un état vide.** La
    // condition porte sur le contenu et non sur `hasValue` : le contrôleur
    // rend d'abord un état « en chargement » vide, que Riverpod garde ensuite
    // à côté de l'erreur — s'arrêter à `hasValue` afficherait « Aucun planning
    // publié » à quelqu'un dont la lecture n'a simplement pas abouti.
    if (etat.hasError && (etat.value?.mois.isEmpty ?? true)) {
      final enLigne = ref.read(enLigneProvider).value ?? true;
      // Le seul cas où l'écran n'a vraiment rien : pas de cache, pas de
      // réseau. La phrase nomme alors ce qui manque.
      return enLigne
          ? EmptyState.erreur(
              texte: AppStrings.planningCaserneErreurTexte,
              onAction: _rafraichir,
            )
          : EmptyState.horsLigne(onAction: _rafraichir);
    }

    return VuePlanningCaserne(
      etat: etat.value ?? const EtatPlanningCaserne(),
      onMois: (MoisPlanning mois) => unawaited(
        ref.read(planningCaserneControllerProvider.notifier).allerAu(mois),
      ),
      onRafraichir: ref
          .read(planningCaserneControllerProvider.notifier)
          .rafraichir,
      onVersMoi: () => _choisirPortee(PorteeAstreintes.moi),
    );
  }

  Widget _corpsMoi() {
    final etat = ref.watch(astreintesControllerProvider);
    // Le bouton « Calendrier » cesse d'être sélectionnable **et** la vue
    // retombe sur la liste : un bouton sélectionné qui montre autre chose que
    // ce qu'il nomme est un mensonge.
    final vue = _calendrierTropGrand ? VueAstreintes.liste : _vue;
    return _corps(etat: etat, vue: vue);
  }

  Widget _corps({
    required AsyncValue<EtatAstreintes> etat,
    required VueAstreintes vue,
  }) {
    if (etat.isLoading && !etat.hasValue) {
      return const SqueletteAstreintes();
    }

    if (etat.hasError && !etat.hasValue) {
      final enLigne = ref.read(enLigneProvider).value ?? true;
      // Le seul cas où l'écran n'a vraiment rien : pas de cache, pas de
      // réseau. La phrase nomme alors ce qui manque.
      return enLigne
          ? EmptyState.erreur(
              texte: AppStrings.astreintesErreurTexte,
              onAction: _rafraichir,
            )
          : EmptyState.horsLigne(onAction: _rafraichir);
    }

    final valeur = etat.value ?? const EtatAstreintes();
    final heures = valeur.donnees.heures;
    final aujourdhui = ref.watch(horlogeAstreintesProvider)();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        BasculeVue(
          vue: vue,
          onChoisir: (VueAstreintes choisie) => setState(() => _vue = choisie),
          calendrierIndisponible: _calendrierTropGrand
              ? AppStrings.astreintesCalendrierTropGrand
              : null,
        ),
        const AppDivider(),
        Expanded(
          child: vue == VueAstreintes.calendrier
              ? CalendrierAstreintes(
                  mois: _mois ?? valeur.donnees.moisDouverture(aujourdhui),
                  donnees: valeur.donnees,
                  aujourdhui: aujourdhui,
                  onMois: (DateTime mois) => setState(() => _mois = mois),
                  onOuvrir: (List<Astreinte> astreintes) =>
                      _ouvrir(astreintes, heures),
                )
              : _Liste(
                  elements: ref.watch(elementsAstreintesProvider),
                  heures: heures,
                  onOuvrir: (Astreinte astreinte) =>
                      _ouvrir(<Astreinte>[astreinte], heures),
                  onBasculerPassees: () =>
                      ref.read(passeesOuvertesProvider.notifier).basculer(),
                  onRafraichir: ref
                      .read(astreintesControllerProvider.notifier)
                      .rafraichir,
                  // Rien à consulter veut dire : il y a peut-être quelque
                  // chose à répondre. L'état vide mène là où se trouve la
                  // suite.
                  onVersPropositions: () =>
                      unawaited(context.pushNamed<void>(
                        AppRoutes.propositionsName,
                      )),
                ),
        ),
      ],
    );
  }
}

/// La liste, groupée par mois et **virtualisée**.
///
/// L'historique n'est jamais supprimé (`docs/PRD.md § 7.6`) : les passées se
/// comptent en centaines après deux ans d'usage, et un `Column` dans un
/// `SingleChildScrollView` les construirait toutes à chaque image.
class _Liste extends StatelessWidget {
  const _Liste({
    required this.elements,
    required this.heures,
    required this.onOuvrir,
    required this.onBasculerPassees,
    required this.onRafraichir,
    required this.onVersPropositions,
  });

  final List<ElementAstreintes> elements;
  final HeuresAffichage heures;
  final ValueChanged<Astreinte> onOuvrir;
  final VoidCallback onBasculerPassees;
  final Future<void> Function() onRafraichir;
  final VoidCallback onVersPropositions;

  /// Vrai quand rien n'est à venir. Le repli des passées peut alors être le
  /// seul élément de la liste : l'état vide se pose au-dessus de lui plutôt
  /// que de laisser une ligne seule au milieu de l'écran.
  bool get _aucuneAVenir => elements.isEmpty || elements.first is ReplisPassees;

  @override
  Widget build(BuildContext context) {
    final classe = AppWindowClass.of(context);
    final marge = classe.margePage;
    final vide = _aucuneAVenir;
    final entete = vide ? 1 : 0;

    return RefreshIndicator(
      onRefresh: onRafraichir,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.colonneMax),
          child: ListView.builder(
            // L'état vide reste tirable : c'est ainsi qu'on vérifie qu'il n'y
            // a vraiment rien.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(marge, 0, marge, AppSpacing.xxl),
            itemCount: elements.length + entete,
            itemBuilder: (BuildContext context, int index) {
              if (vide && index == 0) {
                return ConstrainedBox(
                  // Un **minimum**, jamais une hauteur figée : l'état vide
                  // grandit avec l'échelle de texte au lieu de déborder.
                  constraints: BoxConstraints(
                    minHeight: elements.isEmpty
                        ? MediaQuery.sizeOf(context).height * 0.5
                        : 0,
                  ),
                  child: EmptyState(
                    titre: AppStrings.videAstreintesTitre,
                    texte: AppStrings.videAstreintesTexte,
                    icone: Icons.event_available_outlined,
                    libelleAction: AppStrings.astreintesVideAction,
                    onAction: onVersPropositions,
                  ),
                );
              }

              final element = elements[index - entete];
              return switch (element) {
                EnteteMoisAstreintes() => EnteteSection(
                  titre: element.libelle,
                  compte: AppStrings.astreintesCompte(element.compte),
                  premiere: element.premier,
                ),
                ReplisPassees() => Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const AppDivider(),
                      ReplisPasseesLigne(
                        compte: element.compte,
                        ouvert: element.ouvert,
                        onBasculer: onBasculerPassees,
                      ),
                      const AppDivider(),
                    ],
                  ),
                ),
                LigneAstreinte(:final astreinte, :final passee) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    LigneDAstreinte(
                      key: ValueKey<String>(astreinte.id),
                      astreinte: astreinte,
                      heures: heures,
                      passee: passee,
                      onOuvrir: () => onOuvrir(astreinte),
                    ),
                    if (_suivant(index - entete) is LigneAstreinte)
                      const AppDivider(),
                  ],
                ),
              };
            },
          ),
        ),
      ),
    );
  }

  ElementAstreintes? _suivant(int index) =>
      index + 1 < elements.length ? elements[index + 1] : null;
}
