import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';

/// Le jeton d'abonnement au calendrier de la personne **connectée**
/// (`docs/SCHEMA.md § 2.2` et § 3, migration `0029`).
///
/// **Aucun identifiant n'est passé, et c'est la règle de sécurité de l'appel.**
/// Les deux fonctions SQL ne prennent aucun paramètre : l'identité vient
/// d'`auth.uid()`. Un `p_user_id` exposé ici livrerait — ou couperait —
/// l'abonnement de n'importe qui.
///
/// La colonne, elle, n'est **pas** lisible par PostgREST : `select` et `update`
/// ont été retirés de la table puis re-donnés colonne par colonne, sans
/// `ics_token` (migration `0029`). Il n'existe donc pas d'autre chemin que ces
/// deux RPC.
abstract interface class CalendrierRepository {
  /// Le jeton actuel. Lève un [EchecAbonnement] pour chaque fin de parcours.
  Future<String> lireJeton();

  /// Tire un jeton neuf et **invalide l'ancien sur-le-champ**.
  Future<String> regenererJeton();
}

/// Implémentation Supabase.
class SupabaseCalendrierRepository implements CalendrierRepository {
  const SupabaseCalendrierRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String> lireJeton() => _appeler('my_ics_token');

  @override
  Future<String> regenererJeton() => _appeler('rotate_ics_token');

  Future<String> _appeler(String fonction) async {
    try {
      final reponse = await _client.rpc<dynamic>(fonction);

      // `null` veut dire « pas de session » ou « pas de profil » : la fonction
      // ne lève pas, elle rend null (migration `0029`). Les deux se disent de
      // la même façon à l'écran — reconnecte-toi — parce qu'il n'y a qu'une
      // sortie possible.
      if (reponse is! String || reponse.isEmpty) {
        throw const EchecAbonnement(ErreurAbonnement.nonAuthentifie);
      }
      return reponse;
    } on EchecAbonnement {
      rethrow;
    } on PostgrestException catch (echec) {
      // Sans code, la base n'a pas répondu : c'est le réseau, et « réessaie »
      // a un sens. Avec un code, elle a refusé, et réessayer n'y changera rien.
      throw EchecAbonnement(
        echec.code == null
            ? ErreurAbonnement.reseau
            : ErreurAbonnement.inconnue,
      );
    } on AuthException {
      throw const EchecAbonnement(ErreurAbonnement.nonAuthentifie);
    } on Object {
      throw const EchecAbonnement(ErreurAbonnement.reseau);
    }
  }
}

/// Pourquoi l'abonnement calendrier n'a pas pu être lu ou régénéré.
enum ErreurAbonnement {
  nonAuthentifie(AppStrings.calendrierNonAuthentifie),
  reseau(AppStrings.calendrierReseau),
  inconnue(AppStrings.calendrierEchec);

  const ErreurAbonnement(this.message);

  final String message;
}

/// Une opération qui n'a pas abouti, avec sa phrase déjà en français.
class EchecAbonnement implements Exception {
  const EchecAbonnement(this.erreur);

  final ErreurAbonnement erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecAbonnement(${erreur.name})';
}
