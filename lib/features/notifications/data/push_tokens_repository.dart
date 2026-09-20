import 'package:supabase_flutter/supabase_flutter.dart';

/// `push_platform` (`docs/SCHEMA.md § 1`). Le ticket 024 n'écrit que `web` ;
/// `ios` et `android` attendent le ticket 036.
enum PlateformePush {
  web('web'),
  ios('ios'),
  android('android');

  const PlateformePush(this.valeurSql);

  final String valeurSql;
}

/// Les jetons push de l'utilisateur connecté (`docs/SCHEMA.md § 2.11`).
abstract interface class PushTokensRepository {
  /// Enregistre ou rafraîchit le jeton de cet appareil.
  Future<void> enregistrer({
    required String userId,
    required String token,
    required PlateformePush plateforme,
    String? libelleAppareil,
  });

  /// Supprime un jeton devenu inutile : celui qu'un navigateur vient de
  /// remplacer, ou celui d'un appareil dont on se déconnecte.
  Future<void> oublier(String token);
}

/// Implémentation Supabase.
///
/// L'écriture passe par RLS : `push_tokens_insert_self` et
/// `push_tokens_update_self` n'acceptent que `user_id = auth.uid()`
/// (migration `0007`). Le `user_id` écrit ici est donc vérifié en base, pas
/// ici.
class SupabasePushTokensRepository implements PushTokensRepository {
  SupabasePushTokensRepository(this._client);

  final SupabaseClient _client;

  /// Un `upsert` sur la contrainte d'unicité de `token`, **jamais un insert**.
  ///
  /// C'est ce qui tient la promesse « rafraîchi à chaque lancement, sans
  /// doublon » : FCM rend le même jeton tant que l'abonnement du navigateur
  /// tient, et la ligne existante est alors mise à jour — seul `last_seen_at`
  /// bouge. Quand le navigateur en rend un nouveau, c'est une nouvelle ligne,
  /// et l'ancienne est supprimée par [oublier] (voir `JetonPushLocal`).
  @override
  Future<void> enregistrer({
    required String userId,
    required String token,
    required PlateformePush plateforme,
    String? libelleAppareil,
  }) async {
    final libelle = libelleAppareil?.trim() ?? '';

    await _client
        .from('push_tokens')
        .upsert(<String, dynamic>{
          'user_id': userId,
          'token': token,
          'platform': plateforme.valeurSql,
          'device_label': libelle.isEmpty ? null : libelle,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'token');
  }

  @override
  Future<void> oublier(String token) async {
    await _client.from('push_tokens').delete().eq('token', token);
  }
}
