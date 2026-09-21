import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_providers.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/empty_state.dart';
import '../../astreintes/presentation/astreintes_screen.dart';
import '../../dispos/presentation/mois_screen.dart';
import '../../notifications/presentation/widgets/bouton_notifications.dart';
import '../../profil/presentation/profil_screen.dart';
import '../../propositions/domain/propositions_providers.dart';
import '../../propositions/presentation/propositions_screen.dart';

/// La coquille des destinations de premier niveau.
///
/// Depuis le ticket 011, l'onglet 0 **est** l'écran « Mon mois » : il porte
/// sa propre bannière, sa barre de compteurs et son panneau latéral, donc
/// c'est lui qui construit l'`AppScaffold`. Chaque destination a fini par faire
/// de même — propositions (021), astreintes (027), profil (007) — et la
/// coquille ne garde plus que le choix de destination.
class AccueilScreen extends ConsumerStatefulWidget {
  const AccueilScreen({super.key, this.ongletInitial = 0, this.mois});

  /// L'onglet ouvert à l'arrivée. Porté par l'URL : revenir depuis l'écran
  /// « Membres », qui a sa propre route, ne ramène pas sur « Mon mois » quand
  /// on a demandé « Planning ».
  final int ongletInitial;

  /// Le mois affiché par « Mon mois », au format `AAAA-MM`.
  final String? mois;

  @override
  ConsumerState<AccueilScreen> createState() => _AccueilScreenState();
}

class _AccueilScreenState extends ConsumerState<AccueilScreen> {
  late int _destination = widget.ongletInitial;

  /// La destination « Admin » n'est pas un onglet local : c'est une route.
  static const String _routeAdmin = 'admin';

  /// L'onglet du profil (ticket 007) : identité, caserne, notifications,
  /// langue, et les deux sorties du produit.
  static const String _routeProfil = 'profil';

  /// L'onglet des propositions (ticket 021). C'est là que mène le lien public
  /// `/proposals` d'une notification, traduit par `destinationInterne`.
  static const String _routePropositions = 'propositions';

  /// L'onglet de consultation (ticket 027) : « Mes astreintes ». C'est là que
  /// mène le lien public `/schedule/<période>`, et c'est là que le ticket 023
  /// ajoutera la vue de la caserne.
  static const String _routeAstreintes = 'astreintes';

  /// **L'onglet demandé par l'URL gagne sur l'onglet affiché.**
  ///
  /// La coquille est déjà montée quand une notification arrive : `go` change
  /// la chaîne de requête mais réutilise le même `State`, donc `_destination`
  /// restait sur l'onglet précédent et le lien `/proposals` ramenait sur
  /// « Mon mois ». Vu en test, et c'est exactement le chemin que le ticket 021
  /// promet en deux touches.
  @override
  void didUpdateWidget(AccueilScreen ancien) {
    super.didUpdateWidget(ancien);
    if (widget.ongletInitial != ancien.ongletInitial) {
      setState(() => _destination = widget.ongletInitial);
    }
  }

  void _choisir(int index, List<AppDestination> destinations) {
    if (destinations[index].route == _routeAdmin) {
      // La destination « Admin » tombe sur **le travail**, pas sur
      // l'annuaire : la matrice du mois (ticket 016, écart reporté dans
      // `DESIGN.md`). Les trois autres écrans admin sont à un clic de là.
      context.goNamed(AppRoutes.planningAdminName);
      return;
    }
    setState(() => _destination = index);
  }

  /// Le mois voyage dans l'URL. `goNamed` empile une entrée d'historique :
  /// le retour du navigateur ramène au mois précédemment consulté.
  void _changerMois(String cle) {
    context.goNamed(
      AppRoutes.accueilName,
      queryParameters: <String, String>{
        AppRoutes.parametreOnglet: '$_destination',
        AppRoutes.parametreMois: cle,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appartenance = ref.watch(appartenanceCouranteProvider);
    // La pastille est construite **une fois pour toute la coquille** : la
    // barre du bas et le rail latéral la partagent, et « Mon mois » l'affiche
    // sans savoir ce qu'est une proposition (ticket 021).
    final destinations = AppDestination.pour(
      admin: appartenance?.estAdmin ?? false,
      propositionsEnAttente: ref.watch(propositionsEnAttenteProvider),
    );
    final index = _destination.clamp(0, destinations.length - 1);
    final route = destinations[index].route;

    if (index == 0) {
      return MoisScreen(
        destinations: destinations,
        indexSelectionne: index,
        onDestination: (nouvelle) => _choisir(nouvelle, destinations),
        moisInitial: widget.mois,
        onMoisChange: _changerMois,
      );
    }

    if (route == _routePropositions) {
      return PropositionsScreen(
        destinations: destinations,
        indexSelectionne: index,
        onDestination: (nouvelle) => _choisir(nouvelle, destinations),
        onVersMonMois: () => setState(() => _destination = 0),
      );
    }

    if (route == _routeAstreintes) {
      return AstreintesScreen(
        destinations: destinations,
        indexSelectionne: index,
        onDestination: (nouvelle) => _choisir(nouvelle, destinations),
        // Rien à consulter veut dire : il y a peut-être quelque chose à
        // répondre. L'état vide mène là où se trouve la suite.
        onVersPropositions: () => setState(() => _destination = 1),
      );
    }

    if (route == _routeProfil) {
      return ProfilScreen(
        destinations: destinations,
        indexSelectionne: index,
        onDestination: (nouvelle) => _choisir(nouvelle, destinations),
      );
    }

    return AppScaffold(
      titre: AppStrings.appTitle,
      destinations: destinations,
      indexSelectionne: index,
      onDestination: (nouvelle) => _choisir(nouvelle, destinations),
      actions: const <Widget>[BoutonNotifications()],
      child: EmptyState(
        titre: AppStrings.accueilAVenirTitre,
        texte: AppStrings.accueilAVenirTexte,
        icone: Icons.construction_outlined,
        libelleAction: AppStrings.accueilRetour,
        onAction: () => setState(() => _destination = 0),
      ),
    );
  }
}
