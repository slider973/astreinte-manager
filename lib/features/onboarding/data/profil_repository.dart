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
}
