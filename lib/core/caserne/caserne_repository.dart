import 'package:supabase_flutter/supabase_flutter.dart';

import 'etat_caserne.dart';

/// Lit l'état d'abonnement de la caserne, du point de vue d'un membre.
abstract interface class CaserneRepository {
  /// Les quatre faits de `station_access(uuid)` (migration `0024`).
  ///
  /// **Ne lève jamais.** Une lecture impossible rend [EtatCaserne.inconnue],
  /// c'est-à-dire une caserne qui écrit : on n'invente pas une suspension. La
  /// base reste l'autorité — si elle refuse vraiment, l'écran l'apprendra du
  /// refus, comme avant ce ticket.
  Future<EtatCaserne> lire(String stationId);

  /// La même lecture, mais qui **dit qu'elle n'a pas abouti** : `null` quand
  /// la réponse n'est pas arrivée ou n'est pas lisible.
  ///
  /// C'est celle des relectures (ticket 070). Une caserne déjà connue comme
  /// suspendue ne doit pas redevenir « ouverte » parce qu'un retour au premier
  /// plan est tombé dans un tunnel : [EtatCaserne.inconnue] est le bon repli
  /// quand on ne sait rien, pas quand on savait.
  Future<EtatCaserne?> essayer(String stationId);
}

/// Implémentation Supabase de [CaserneRepository].
class SupabaseCaserneRepository implements CaserneRepository {
  const SupabaseCaserneRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<EtatCaserne> lire(String stationId) async =>
      // Réseau, fonction absente sur un déploiement en retard, réponse
      // illisible : trois pannes, une seule conséquence, et c'est la plus
      // sûre des deux.
      await essayer(stationId) ?? EtatCaserne.inconnue;

  @override
  Future<EtatCaserne?> essayer(String stationId) async {
    try {
      final reponse = await _client.rpc<dynamic>(
        'station_access',
        params: <String, dynamic>{'p_station': stationId},
      );
      if (reponse is! Map<String, dynamic>) return null;
      return EtatCaserne.depuisJson(reponse);
    } on Object {
      return null;
    }
  }
}
