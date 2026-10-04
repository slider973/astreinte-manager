import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appartenance.dart';
import 'caserne_choisie.dart';
import 'session_providers.dart';

/// Pourquoi l'application a changé de caserne **sans qu'on le lui demande ici**
/// (ticket 072, décision 2 du propriétaire).
enum RaisonBascule {
  /// Une notification touchée, au premier plan ou en arrière-plan.
  notification,

  /// Une adresse ouverte qui porte `?station=<uuid>` (courriel, lien du push
  /// ouvert application fermée).
  lien,

  /// L'accès à la caserne ouverte a été désactivé ; une autre reste active.
  desactivee,
}

/// Une bascule automatique, telle que le bandeau la raconte.
@immutable
class BasculeAutomatique {
  const BasculeAutomatique({
    required this.ancienne,
    required this.nouvelle,
    required this.raison,
  });

  /// La caserne où l'on était.
  final Appartenance ancienne;

  /// La caserne désormais ouverte.
  final Appartenance nouvelle;

  final RaisonBascule raison;

  /// « Revenir à {ancienne} » n'a de sens que si l'on y a encore accès.
  bool get peutRevenir => raison != RaisonBascule.desactivee;
}

/// **Le seul endroit qui change de caserne** (ticket 072).
///
/// Trois portes, un même geste : le sélecteur (bascule manuelle, sans
/// bandeau), un push ou un lien d'une autre caserne, et l'accès retiré dans la
/// caserne ouverte (bascules automatiques, avec bandeau). Son état est la
/// dernière bascule automatique à annoncer, `null` sinon ; c'est la couche des
/// notifications qui le montre (`CoucheNotifications`).
///
/// **La base reste l'autorité** (`docs/WORKFLOWS.md § 8`) : on ne bascule que
/// vers une caserne où le compte a une appartenance **active**, lue dans
/// `appartenancesActivesProvider` — la liste relue, jamais un souvenir de
/// l'appareil qui ne serait pas passé par elle. Rien n'est écrit sur l'appareil
/// ici : le choix lui-même est rangé par `CaserneChoisie`, que la déconnexion
/// efface déjà.
class BasculeCaserne extends Notifier<BasculeAutomatique?> {
  /// Le compte dont la liste d'appartenances a été vue en dernier.
  String? _compte;

  @override
  BasculeAutomatique? build() {
    _compte = ref.read(sessionProvider).value?.userId;
    ref.listen<List<Appartenance>>(
      appartenancesActivesProvider,
      _surveillerLesAcces,
    );
    return null;
  }

  /// Le choix fait au sélecteur. Pas de bandeau : la personne vient de le
  /// faire. Un bandeau d'une bascule précédente s'efface, il raconterait une
  /// histoire qui n'est plus vraie.
  Future<void> choisir(String stationId) async {
    state = null;
    await ref.read(caserneChoisieProvider.notifier).choisir(stationId);
  }

  /// Ouvre la caserne [stationId] avant de suivre une notification ou un lien.
  ///
  /// Rend l'appartenance dans laquelle la destination doit s'ouvrir :
  ///
  /// - la caserne ouverte, si [stationId] est absent ou est déjà elle ;
  /// - la caserne visée, si le compte y est membre actif — la bascule est
  ///   faite, et le bandeau la dira ;
  /// - `null` si le compte n'y est pas (ou plus) membre actif : l'appelant
  ///   retombe sur l'accueil, **sans message**, comme pour un lien interdit.
  ///
  /// Le changement est **synchrone** : la garde du routeur, qui lit le rôle
  /// dans l'appartenance courante, voit déjà la nouvelle caserne quand
  /// l'appelant navigue.
  Appartenance? ouvrirPour(String? stationId, {required RaisonBascule raison}) {
    final courante = ref.read(appartenanceCouranteProvider);
    if (stationId == null || stationId.isEmpty) return courante;
    if (stationId == courante?.stationId) return courante;

    Appartenance? cible;
    for (final appartenance in ref.read(appartenancesActivesProvider)) {
      if (appartenance.stationId == stationId) cible = appartenance;
    }
    if (cible == null) return null;

    unawaited(ref.read(caserneChoisieProvider.notifier).choisir(stationId));
    if (courante != null) {
      state = BasculeAutomatique(
        ancienne: courante,
        nouvelle: cible,
        raison: raison,
      );
    }
    return cible;
  }

  /// « Revenir à {ancienne} » : rebascule sans nouveau bandeau.
  ///
  /// Rend vrai si la bascule a eu lieu — l'ancienne caserne peut avoir retiré
  /// l'accès pendant les huit secondes du bandeau.
  bool revenir() {
    final bascule = state;
    state = null;
    if (bascule == null || !bascule.peutRevenir) return false;
    final encore = ref
        .read(appartenancesActivesProvider)
        .any((Appartenance a) => a.stationId == bascule.ancienne.stationId);
    if (!encore) return false;
    unawaited(
      ref
          .read(caserneChoisieProvider.notifier)
          .choisir(bascule.ancienne.stationId),
    );
    return true;
  }

  /// Le bandeau a été lu, fermé ou s'est effacé.
  void oublier() => state = null;

  /// **L'accès retiré dans la caserne ouverte** : on part vers la première qui
  /// reste, et on le dit. Sans caserne restante, c'est l'écran « Aucune
  /// caserne » qui prend la suite, par la garde du routeur.
  ///
  /// **Seulement pour un même compte** : à un changement de session, la liste
  /// passe d'un compte à l'autre — Riverpod garde la précédente pendant la
  /// lecture —, et ce n'est pas un accès retiré.
  void _surveillerLesAcces(List<Appartenance>? avant, List<Appartenance> apres) {
    final userId = ref.read(sessionProvider).value?.userId;
    final memeCompte = userId != null && userId == _compte;
    _compte = userId;
    if (!memeCompte) return;
    if (avant == null || avant.isEmpty || apres.isEmpty) return;

    final choisie = ref.read(caserneChoisieProvider);
    final ouverteAvant = avant.firstWhere(
      (Appartenance a) => a.stationId == choisie,
      orElse: () => avant.first,
    );
    final toujours = apres.any(
      (Appartenance a) => a.stationId == ouverteAvant.stationId,
    );
    if (toujours) return;

    final nouvelle = apres.first;
    unawaited(
      ref.read(caserneChoisieProvider.notifier).choisir(nouvelle.stationId),
    );
    state = BasculeAutomatique(
      ancienne: ouverteAvant,
      nouvelle: nouvelle,
      raison: RaisonBascule.desactivee,
    );
  }
}

final NotifierProvider<BasculeCaserne, BasculeAutomatique?>
basculeCaserneProvider =
    NotifierProvider<BasculeCaserne, BasculeAutomatique?>(BasculeCaserne.new);
