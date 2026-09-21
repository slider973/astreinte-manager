/// Les quatre destinations qu'une notification sait ouvrir
/// (`docs/WORKFLOWS.md § 8`), et leur traduction en emplacement interne.
///
/// Deux vocabulaires cohabitent, et c'est voulu :
///
/// - **le lien public**, celui que l'Edge Function écrit dans
///   `notifications.data.route` et que le navigateur ouvre quand on touche la
///   notification : `/proposals`, `/schedule/2026-10`… Il est stable, il ne
///   dépend pas de la forme des écrans, et il survivra à leur refonte ;
/// - **l'emplacement interne**, celui que `go_router` sert aujourd'hui. La
///   coquille d'accueil porte encore trois destinations dans des onglets, donc
///   « les propositions » s'écrit `/?onglet=1`.
///
/// Tout est ici, dans une fonction pure et testée, pour que le jour où les
/// écrans des tickets 019, 021 et 023 existent, **une seule ligne change** et
/// les liens déjà partis en notification continuent de fonctionner.
library;

import '../../../core/router/app_router.dart';

/// Les onglets de la coquille d'accueil (`AppDestination.pour`).
const int _ongletMonMois = 0;
const int _ongletPropositions = 1;
const int _ongletAstreintes = 2;

/// Une période de saisie, `AAAA-MM`. Rien d'autre n'est accepté : un lien
/// forgé ne doit pas se promener dans l'URL de l'application.
final RegExp _periode = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

/// Vrai si [periode] est un mois bien formé.
bool periodeValide(String? periode) =>
    periode != null && _periode.hasMatch(periode);

/// Traduit le lien public d'une notification en emplacement interne.
///
/// Renvoie `null` quand le lien est inconnu, mal formé, ou mène à un écran que
/// ce compte n'a pas le droit d'ouvrir. L'appelant retombe alors sur l'accueil
/// **sans message d'erreur** : le membre n'a rien fait de mal, et le lien peut
/// simplement dater d'avant une rétrogradation.
String? destinationInterne(String? lien, {required bool admin}) {
  if (lien == null || lien.isEmpty) return null;

  final uri = Uri.tryParse(lien);
  if (uri == null) return null;

  final segments = uri.pathSegments;
  if (segments.isEmpty) return null;

  // `/proposals`
  if (segments.length == 1 && segments.first == 'proposals') {
    return _accueil(onglet: _ongletPropositions);
  }

  if (segments.length == 2) {
    final periode = segments[1];
    if (!periodeValide(periode)) return null;

    // `/schedule/<period>` — le planning de la caserne. La destination
    // « Astreintes » porte depuis le ticket 027 « Mes astreintes », et le
    // ticket 023 y ajoutera la vue de la caserne : le lien mène donc enfin à
    // un écran. Il n'ouvre toujours pas un mois — le sélecteur de mois est du
    // ressort du 023.
    if (segments.first == 'schedule') {
      return _accueil(onglet: _ongletAstreintes);
    }

    // `/availability/<period>` — la saisie du mois. La seule des quatre qui
    // mène déjà exactement où il faut.
    if (segments.first == 'availability') {
      return _accueil(onglet: _ongletMonMois, mois: periode);
    }
  }

  // `/admin/schedule/<period>` — le suivi admin. L'écran existe depuis le
  // ticket 019 : le lien mène enfin au mois qu'il nomme.
  if (segments.length == 3 &&
      segments[0] == 'admin' &&
      segments[1] == 'schedule') {
    final periode = segments[2];
    if (!periodeValide(periode)) return null;
    if (!admin) return null;
    return Uri(
      path: AppRoutes.suivi,
      queryParameters: <String, String>{AppRoutes.parametreMois: periode},
    ).toString();
  }

  return null;
}

String _accueil({required int onglet, String? mois}) {
  final parametres = <String, String>{
    AppRoutes.parametreOnglet: '$onglet',
    AppRoutes.parametreMois: ?mois,
  };
  return Uri(path: AppRoutes.accueil, queryParameters: parametres).toString();
}
