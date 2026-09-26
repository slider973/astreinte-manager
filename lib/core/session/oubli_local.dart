import 'package:flutter_riverpod/flutter_riverpod.dart';

// Les caches appartiennent à leurs fonctionnalités, mais **c'est ici que
// s'écrit la règle** « rien de cette personne ne reste sur l'appareil ». Les
// liens sont donc directs, comme ceux du routeur vers les écrans : une liste
// que les fonctionnalités viendraient garnir d'elles-mêmes serait une liste
// qu'on oublie de garnir, et c'est exactement le défaut qu'on corrige.
import '../../features/astreintes/data/cache_astreintes.dart';
import '../../features/astreintes/data/cache_planning_caserne.dart';
import '../../features/dispos/data/file_locale.dart';
import '../../features/notifications/domain/notifications_providers.dart';
import 'appartenances_locales.dart';
import 'caserne_choisie.dart';
import 'session_providers.dart';

/// **Tout ce que l'appareil garde de la personne connectée, oublié d'un coup.**
///
/// Deux appelants, une seule règle : la déconnexion
/// (`core/session/deconnexion.dart`) et la suppression de compte
/// (`features/profil/domain/suppression_providers.dart`). Une suppression doit
/// laisser l'appareil **au moins** aussi propre qu'une déconnexion ; les faire
/// diverger, c'est garantir qu'une des deux prendra du retard.
///
/// Toujours appelé **avant** la fermeture de session : après, ni l'identifiant
/// du membre ni ceux de ses casernes ne sont plus lisibles, et les caches
/// rangent par clé — une clé qu'on ne sait plus composer ne s'efface pas.
///
/// Ce qui part :
///
///   - le nom des casernes (`session.appartenances.…`) et la caserne choisie
///     (`session.caserne.…`) ;
///   - l'instantané des astreintes (`astreintes.cache.…`), qui porte **les noms
///     des autres membres du créneau** ;
///   - les mois du planning de la caserne (`planning.caserne.…`), qui portent
///     **les noms de toute la caserne** ;
///   - la file de saisie hors ligne (`dispos.file.…`, `dispos.prefs.…`), qui
///     porte **les disponibilités déclarées** et qui, après une suppression de
///     compte, tenterait d'écrire au nom de quelqu'un qui n'existe plus.
///   - le jeton push de l'appareil (`notifications.jeton.appareil`, ticket
///     057) : sa ligne de `push_tokens` est **d'abord** supprimée côté serveur
///     — sinon les push du compte sorti continuent d'arriver sur un téléphone
///     prêté —, puis la clé locale part, que la suppression ait réussi ou non.
///
/// Ne restent que les repères d'accueil (`accueil.…`, `dispos.peinture.faite`,
/// `matrice.procuration.confirmee`) : des marques de passage de l'appareil,
/// sans rien de la personne. `test/core/session/deconnexion_caches_test.dart`
/// relit **tout** le stockage après la déconnexion, et ne tolère que ceux-là.
///
/// Sur un téléphone prêté ou dans un véhicule partagé, ce sont des données de
/// tiers qui n'ont rien à faire là pour la personne suivante — même règle que
/// la destination en attente, oubliée elle aussi à la déconnexion
/// (`DESIGN.md § Écarts, ticket 024`).
///
/// **La boucle porte sur toutes les appartenances, pas sur la caserne
/// courante.** Depuis le sélecteur du ticket 007, quelqu'un peut avoir consulté
/// deux casernes dans la même session ; n'effacer que celle affichée laissait
/// derrière lui l'annuaire de l'autre.
///
/// Aucune panne de stockage ne remonte : elles sont déjà avalées par les
/// dépôts. Un effacement qui échoue ne doit retenir personne dans une session
/// qu'il veut quitter, ni faire échouer une suppression déjà acquise en base.
class OubliLocal {
  const OubliLocal(this._ref);

  final Ref _ref;

  Future<void> tout() async {
    // **En premier, et hors de la garde de session** : la suppression côté
    // serveur a besoin de la session encore ouverte, et la clé est une clé
    // d'appareil — elle part même si l'identifiant du membre n'est plus lisible.
    await _ref.read(jetonPushProvider.notifier).desenregistrer();

    final userId = _ref.read(sessionProvider).value?.userId;
    if (userId == null) return;

    // Les casernes sont relues **avant** d'effacer la liste : c'est elle qui
    // dit quelles clés composer.
    final stations = <String>{
      for (final appartenance in _ref.read(appartenancesActivesProvider))
        appartenance.stationId,
      ?_ref.read(caserneChoisieProvider),
    };

    await _ref.read(appartenancesLocalesProvider).effacer(userId);
    await _ref.read(caserneChoisieLocaleProvider).effacer(userId);

    final astreintes = _ref.read(cacheAstreintesProvider);
    final planning = _ref.read(cachePlanningCaserneProvider);
    final file = _ref.read(fileLocaleProvider);

    for (final stationId in stations) {
      await astreintes.effacer(stationId: stationId, userId: userId);
      await planning.effacer(stationId: stationId, userId: userId);
      await file.effacer(stationId: stationId, userId: userId);
    }
  }
}

final Provider<OubliLocal> oubliLocalProvider = Provider<OubliLocal>(
  OubliLocal.new,
);
