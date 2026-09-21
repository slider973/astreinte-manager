import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/profil.dart';

/// Le profil du membre connecté (`docs/SCHEMA.md § 2.2`).
abstract interface class ProfilRepository {
  /// La ligne `profiles` de [userId], telle qu'elle est en base.
  Future<Profil> lire(String userId);

  /// Renseigne prénom, nom et téléphone. La ligne existe déjà : elle est
  /// créée par le trigger `handle_new_user` à l'inscription.
  ///
  /// Sert deux écrans : le complément d'accueil (ticket 006) et l'écran de
  /// profil (ticket 007). Le premier remplit, le second corrige — c'est la
  /// même écriture.
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

  /// Supprime le compte de la personne **connectée**.
  ///
  /// Aucun identifiant n'est passé, et c'est la règle de sécurité de l'appel :
  /// l'Edge Function tire l'identité du jeton, jamais d'un corps de requête
  /// (`supabase/functions/README.md § delete-account`).
  ///
  /// Lève un [EchecSuppression] pour chaque fin de parcours du contrat.
  Future<void> supprimerCompte();
}

/// Implémentation Supabase.
///
/// L'écriture passe par RLS : la politique de `profiles` n'autorise que sa
/// propre ligne. Le filtre sur `id` est donc une courtoisie envers le serveur,
/// pas la sécurité — elle est en base.
class SupabaseProfilRepository implements ProfilRepository {
  SupabaseProfilRepository(this._client);

  final SupabaseClient _client;

  /// Colonnes de `docs/SCHEMA.md § 2.2`. Ni `created_at` ni `updated_at` :
  /// aucun écran ne les affiche.
  static const String _colonnes =
      'first_name, last_name, email, phone, push_enabled, locale';

  @override
  Future<Profil> lire(String userId) async {
    final ligne = await _client
        .from('profiles')
        .select(_colonnes)
        .eq('id', userId)
        .single();
    return Profil.depuisJson(ligne);
  }

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

  @override
  Future<void> supprimerCompte() async {
    try {
      // Corps vide, et c'est voulu : l'identité vient du jeton porteur que le
      // client ajoute lui-même. Un `user_id` ici ferait de cette fonction une
      // porte pour supprimer le compte d'un autre.
      final reponse = await _client.functions.invoke('delete-account');

      final corps = reponse.data;
      if (corps is! Map<String, dynamic> || corps['ok'] != true) {
        throw const EchecSuppression(ErreurSuppression.inconnue);
      }
    } on FunctionException catch (echec) {
      throw _traduire(echec);
    }
  }

  /// `status == 0` est la marque d'une requête qui n'est jamais partie : le
  /// SDK range là ce que les autres dépôts du projet appellent « réseau ».
  static EchecSuppression _traduire(FunctionException echec) {
    if (echec.status == 0) {
      return const EchecSuppression(ErreurSuppression.reseau);
    }

    final details = echec.details;
    final erreur = details is Map ? details['error'] : null;
    if (erreur is! Map) {
      return const EchecSuppression(ErreurSuppression.inconnue);
    }

    return EchecSuppression(
      ErreurSuppression.depuisCode(erreur['code'] as String?),
      caserne: erreur['station'] as String?,
    );
  }
}
