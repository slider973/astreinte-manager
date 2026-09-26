import 'package:supabase_flutter/supabase_flutter.dart';

/// `push_platform` (`docs/SCHEMA.md § 1`). La PWA n'écrit que `web` ; `ios` est
/// écrit par l'app iOS native (`foco/`, ticket 066d).
enum PlateformePush {
  web('web'),
  ios('ios'),
  android('android');

  const PlateformePush(this.valeurSql);

  final String valeurSql;
}

/// Les jetons push de l'utilisateur connecté (`docs/SCHEMA.md § 2.11`).
abstract interface class PushTokensRepository {
  /// Enregistre ou rafraîchit le jeton de cet appareil **au nom de la
  /// session**, et le retire à tout autre compte qui le portait encore.
  ///
  /// Pas d'identifiant de membre : c'est la base qui le lit dans la session
  /// (`register_push_token`, migration `0037`).
  Future<void> enregistrer({
    required String token,
    required PlateformePush plateforme,
    String? libelleAppareil,
  });

  /// Supprime un jeton devenu inutile : celui qu'un navigateur vient de
  /// remplacer, ou celui d'un appareil dont on se déconnecte.
  Future<void> oublier(String token);
}

/// Implémentation Supabase.
class SupabasePushTokensRepository implements PushTokensRepository {
  SupabasePushTokensRepository(this._client);

  final SupabaseClient _client;

  /// Le nom de la fonction, figé ici et dans le contrat de l'app iOS.
  static const String fonctionEnregistrement = 'register_push_token';

  /// **Par `register_push_token`, jamais par un `upsert` direct.**
  ///
  /// Un téléphone de caserne est prêté. Si la personne précédente s'est
  /// déconnectée hors ligne, la ligne de ce jeton est restée à son nom, et
  /// l'`upsert` de la personne suivante sur la même clé unique était refusé par
  /// la RLS : les push de l'une continuaient d'arriver sur l'appareil, l'autre
  /// n'en recevait aucun. La fonction réattribue le jeton au compte de la
  /// session — un jeton FCM identifie l'appareil, et le présenter prouve qu'on
  /// le tient (`docs/WORKFLOWS.md § 8`, ticket 057).
  ///
  /// Même promesse qu'avant : rafraîchi à chaque lancement, sans doublon.
  /// `last_seen_at` est posé par le serveur ; un libellé vide s'écrit `null`.
  @override
  Future<void> enregistrer({
    required String token,
    required PlateformePush plateforme,
    String? libelleAppareil,
  }) async {
    final libelle = libelleAppareil?.trim() ?? '';

    await _client.rpc<dynamic>(
      fonctionEnregistrement,
      params: <String, dynamic>{
        'p_token': token,
        'p_platform': plateforme.valeurSql,
        'p_device_label': libelle.isEmpty ? null : libelle,
      },
    );
  }

  /// Sous RLS (`push_tokens_delete_self`) : seulement tant que la session est
  /// ouverte, et seulement une ligne à soi.
  @override
  Future<void> oublier(String token) async {
    await _client.from('push_tokens').delete().eq('token', token);
  }
}
