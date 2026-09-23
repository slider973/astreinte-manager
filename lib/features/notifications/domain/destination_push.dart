/// Les cinq destinations qu'une notification sait ouvrir
/// (`docs/WORKFLOWS.md § 8`), et leur traduction en emplacement interne.
///
/// Deux vocabulaires cohabitent, et c'est voulu :
///
/// - **le lien public**, celui que l'Edge Function écrit dans
///   `notifications.data.route` et que le navigateur ouvre quand on touche la
///   notification : `/proposals`, `/schedule/2026-10`… Il est stable, il ne
///   dépend pas de la forme des écrans, et il survivra à leur refonte ;
/// - **l'emplacement interne**, celui que `go_router` sert aujourd'hui. Chaque
///   écran a sa route depuis le ticket 064, et « les propositions » sont un
///   onglet de la Boîte depuis le 064b : `/boite?onglet=propositions`, et non
///   plus `/propositions` ni `/?onglet=1`.
///
/// Tout est ici, dans une fonction pure et testée : c'est **le seul endroit**
/// qui a changé quand la coquille d'accueil a éclaté en routes, et les liens
/// déjà partis en notification ont continué de fonctionner.
library;

import '../../../core/router/app_router.dart';
import '../../boite/domain/onglet_boite.dart';

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

  // `/proposals` — l'onglet « Propositions » de la Boîte depuis le chantier
  // 064b. L'écran à qui cette adresse menait n'existe plus ; le lien public,
  // lui, n'a pas bougé d'un caractère. C'est exactement ce à quoi sert cette
  // fonction.
  if (segments.length == 1 && segments.first == 'proposals') {
    return AppRoutes.boiteOnglet(OngletBoite.propositions);
  }

  // `/admin/subscription` — l'abonnement de la caserne (ticket 030). Le lien
  // des deux notifications de fin d'essai et de suspension. **Ignoré pour un
  // membre ordinaire** : le routeur ferme `/admin` de toute façon, et rendre
  // `null` ici le ramène à l'accueil sans message d'erreur, comme pour un lien
  // qui daterait d'avant une rétrogradation.
  if (segments.length == 2 &&
      segments[0] == 'admin' &&
      segments[1] == 'subscription') {
    return admin ? AppRoutes.abonnement : null;
  }

  if (segments.length == 2) {
    final periode = segments[1];
    if (!periodeValide(periode)) return null;

    // `/schedule/<period>` — le planning de la caserne. La destination
    // « Astreintes » porte depuis le ticket 027 « Mes astreintes », et le
    // ticket 023 y a ajouté la vue de la caserne. Elle n'ouvre toujours pas un
    // mois : le sélecteur de mois de cet écran n'est pas dans l'URL.
    if (segments.first == 'schedule') {
      return AppRoutes.astreintes;
    }

    // `/availability/<period>` — la saisie du mois. La seule des quatre qui
    // mène exactement où il faut, mois compris.
    if (segments.first == 'availability') {
      return Uri(
        path: AppRoutes.calendrier,
        queryParameters: <String, String>{AppRoutes.parametreMois: periode},
      ).toString();
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
