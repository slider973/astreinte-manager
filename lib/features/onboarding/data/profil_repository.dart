import 'package:supabase_flutter/supabase_flutter.dart';

/// L'écriture du profil du membre connecté (`docs/SCHEMA.md § 2.2`).
abstract interface class ProfilRepository {
  /// Renseigne prénom, nom et téléphone. La ligne existe déjà : elle est
  /// créée par le trigger `handle_new_user` à l'inscription.
  Future<void> completer({
    required String userId,
    required String prenom,
    required String nom,
    String? telephone,
  });

  /// `profiles.push_enabled` : les notifications **non critiques** sont-elles
  /// acceptées ? Les propositions d'astreinte, elles, partent toujours
  /// (`docs/PRD.md § 6.5`) — cette colonne ne les concerne pas.
  Future<bool> pushNonCritiques(String userId);

  Future<void> definirPushNonCritiques({
    required String userId,
    required bool actif,
  });
}

/// Implémentation Supabase.
///
/// L'écriture passe par RLS : la politique de `profiles` n'autorise que sa
/// propre ligne. Le filtre sur `id` est donc une courtoisie envers le serveur,
/// pas la sécurité — elle est en base.
class SupabaseProfilRepository implements ProfilRepository {
  SupabaseProfilRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> completer({
    required String userId,
    required String prenom,
    required String nom,
    String? telephone,
  }) async {
    final numero = telephone?.trim() ?? '';

    await _client
        .from('profiles')
        .update(<String, dynamic>{
          'first_name': prenom.trim(),
          'last_name': nom.trim(),
          // Colonne nullable : un champ vidé remet `null`, jamais la chaîne
          // vide, pour que « pas de téléphone » ait une seule écriture.
          'phone': numero.isEmpty ? null : numero,
        })
        .eq('id', userId);
  }

  @override
  Future<bool> pushNonCritiques(String userId) async {
    final ligne = await _client
        .from('profiles')
        .select('push_enabled')
        .eq('id', userId)
        .single();

    // Colonne `not null default true` : la valeur existe toujours. Une
    // réponse illisible est traitée comme « oui », qui est le défaut du
    // schéma — jamais comme « non », qui couperait des rappels sans que
    // personne ne l'ait demandé.
    return ligne['push_enabled'] as bool? ?? true;
  }

  @override
  Future<void> definirPushNonCritiques({
    required String userId,
    required bool actif,
  }) async {
    await _client
        .from('profiles')
        .update(<String, dynamic>{'push_enabled': actif})
        .eq('id', userId);
  }
}
