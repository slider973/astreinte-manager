import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/notifications/domain/centre_providers.dart';
import '../session/session_providers.dart';
import '../widgets/app_scaffold.dart';
import 'app_router.dart';

/// Les destinations de la coquille, construites **une fois pour toute
/// l'application**.
///
/// Avant le ticket 064, la coquille d'accueil les construisait et les passait
/// à l'onglet affiché. Chaque destination ayant maintenant sa propre route,
/// c'est ce provider qui tient le rôle : une pastille qui ne serait chiffrée
/// que sur l'écran qui la porte serait un compte qui disparaît dès qu'on
/// change d'onglet.
final Provider<List<AppDestination>> destinationsProvider =
    Provider<List<AppDestination>>(
      (ref) => AppDestination.pour(
        admin: ref.watch(appartenanceCouranteProvider)?.estAdmin ?? false,
        boiteNonLues: ref.watch(notificationsNonLuesProvider),
      ),
    );

/// La place d'une destination dans la barre, par son nom de route.
///
/// `0` quand la route n'est pas une destination : un écran poussé qui
/// construirait quand même une coquille vaut mieux marqué sur l'accueil que
/// marqué nulle part — mais aucun ne le fait, et le test le vérifie.
int indexDestination(List<AppDestination> destinations, String route) {
  for (var index = 0; index < destinations.length; index++) {
    if (destinations[index].route == route) return index;
  }
  return 0;
}

/// Va à la destination choisie.
///
/// `goNamed` et non `push` : passer d'une destination à sa sœur n'est pas une
/// poussée, il n'y a ni avant ni après (ticket 063). Les cinq routes servies
/// ici passent par `pageDestination`, donc sans transition.
void allerVersDestination(
  BuildContext context,
  List<AppDestination> destinations,
  int index,
) {
  if (index < 0 || index >= destinations.length) return;
  context.goNamed(destinations[index].route);
}

/// L'emplacement où mène une ancienne adresse `/?onglet=N`, ou `null` quand
/// l'adresse n'a rien d'hérité.
///
/// **Aucune notification déjà partie ne doit tomber sur un écran vide.** Les
/// quatre onglets de la coquille d'avant le ticket 064 ont chacun leur route :
/// 0 le Calendrier, 1 les Propositions, 2 les Astreintes, 3 le Profil. Un
/// `?mois=` sans onglet visait « Mon mois », qui était l'onglet 0.
String? ongletHerite(Uri uri) {
  final parametres = uri.queryParameters;
  final onglet = parametres[AppRoutes.parametreOnglet];
  final mois = parametres[AppRoutes.parametreMois];

  // Sans mois, l'adresse est nue : `Uri` avec une carte de paramètres vide
  // écrirait « /calendrier? », un point d'interrogation orphelin dans la barre
  // d'adresse et dans l'historique.
  String versCalendrier() => mois == null
      ? AppRoutes.calendrier
      : Uri(
          path: AppRoutes.calendrier,
          queryParameters: <String, String>{AppRoutes.parametreMois: mois},
        ).toString();

  if (onglet == null) return mois == null ? null : versCalendrier();

  return switch (onglet) {
    '0' => versCalendrier(),
    '1' => AppRoutes.propositions,
    '2' => AppRoutes.astreintes,
    '3' => AppRoutes.profil,
    // Un onglet inconnu — cinquième onglet d'un admin, valeur bricolée — n'est
    // pas une erreur : l'accueil est la réponse, et il ne dit rien de faux.
    _ => AppRoutes.accueil,
  };
}
