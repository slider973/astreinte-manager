import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../domain/abonnement.dart';

/// Tout ce que l'écran « Abonnement » sait faire.
///
/// Une interface, pas un client Supabase : l'écran se teste avec un faux, y
/// compris — et surtout — dans l'état « aucun prestataire configuré ».
abstract interface class AbonnementRepository {
  /// L'état de l'abonnement **et** celui de la configuration du prestataire.
  ///
  /// Une seule requête, à l'Edge Function `create-checkout` (action `state`) :
  /// la table dit le statut, mais elle ne sait pas si un compte est branché ni
  /// à quel tarif. Lire les deux séparément donnerait un écran qui affiche un
  /// bouton une seconde avant de le retirer.
  Future<EtatAbonnement> lire(String stationId);

  /// Ouvre une session de paiement et rend l'adresse vers laquelle envoyer le
  /// navigateur.
  Future<String> ouvrirPaiement({
    required String stationId,
    required FormuleAbonnement formule,
  });

  /// Ouvre le portail de gestion (carte, factures, résiliation).
  Future<String> ouvrirPortail(String stationId);
}

/// Pourquoi une action d'abonnement a été refusée.
enum ErreurAbonnement {
  /// Aucun compte chez le prestataire n'est configuré sur ce projet. **Ce n'est
  /// pas une panne** : la caserne reste en essai et pleinement utilisable.
  nonConfigure(AppStrings.abonnementNonConfigureTexte),

  /// L'appelant n'administre pas cette caserne (ou ne l'administre plus).
  droits(AppStrings.abonnementRefusDroits),

  /// La caserne est déjà abonnée : le changement passe par le portail.
  dejaAbonne(AppStrings.abonnementDejaAbonne),

  /// Aucun client chez le prestataire : il n'y a rien à gérer.
  sansClient(AppStrings.abonnementSansClient),

  /// Le prestataire a refusé ou n'a pas répondu.
  prestataire(AppStrings.abonnementEchecPrestataire),

  /// Réseau tombé, serveur en vrac, réponse illisible.
  inconnue(AppStrings.abonnementEchecGenerique);

  const ErreurAbonnement(this.message);

  final String message;

  /// Les codes rendus par l'Edge Function (`supabase/functions/README.md`).
  static ErreurAbonnement depuisCode(String? code) => switch (code) {
    'stripe_not_configured' => ErreurAbonnement.nonConfigure,
    'not_admin' || 'unauthenticated' => ErreurAbonnement.droits,
    'already_subscribed' => ErreurAbonnement.dejaAbonne,
    'no_customer' => ErreurAbonnement.sansClient,
    'stripe_error' => ErreurAbonnement.prestataire,
    _ => ErreurAbonnement.inconnue,
  };
}

/// Une action d'abonnement refusée, avec sa phrase déjà en français.
class EchecAbonnement implements Exception {
  const EchecAbonnement(this.erreur);

  final ErreurAbonnement erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecAbonnement(${erreur.name})';
}

/// Implémentation Supabase.
///
/// **Tout passe par l'Edge Function**, y compris la lecture, alors que la RLS
/// autoriserait un `select` direct sur `subscriptions`. La raison n'est pas le
/// droit mais la vérité : la table ne sait pas si un compte est branché chez le
/// prestataire, et l'écran a besoin de le savoir pour ne pas proposer un bouton
/// qui échouerait. Une lecture directe obligerait à embarquer cette
/// connaissance dans la PWA, donc à la recompiler le jour où le propriétaire
/// crée son compte.
class SupabaseAbonnementRepository implements AbonnementRepository {
  SupabaseAbonnementRepository(this._client);

  final SupabaseClient _client;

  static const String _fonction = 'create-checkout';

  @override
  Future<EtatAbonnement> lire(String stationId) async {
    final corps = await _appeler(<String, dynamic>{
      'station_id': stationId,
      'action': 'state',
    });
    return EtatAbonnement.depuisJson(corps);
  }

  @override
  Future<String> ouvrirPaiement({
    required String stationId,
    required FormuleAbonnement formule,
  }) async {
    final corps = await _appeler(<String, dynamic>{
      'station_id': stationId,
      'action': 'checkout',
      'plan': formule.valeurSql,
    });
    return _adresse(corps);
  }

  @override
  Future<String> ouvrirPortail(String stationId) async {
    final corps = await _appeler(<String, dynamic>{
      'station_id': stationId,
      'action': 'portal',
    });
    return _adresse(corps);
  }

  Future<Map<String, dynamic>> _appeler(Map<String, dynamic> corps) async {
    try {
      final reponse = await _client.functions.invoke(_fonction, body: corps);
      final donnees = reponse.data;
      if (donnees is! Map<String, dynamic> || donnees['ok'] != true) {
        throw const EchecAbonnement(ErreurAbonnement.inconnue);
      }
      return donnees;
    } on FunctionException catch (echec) {
      throw EchecAbonnement(_traduireFonction(echec));
    } on EchecAbonnement {
      rethrow;
    } on Object {
      throw const EchecAbonnement(ErreurAbonnement.inconnue);
    }
  }

  /// L'adresse de redirection. Une réponse sans adresse est un échec : envoyer
  /// le navigateur nulle part donnerait un onglet blanc et aucun message.
  static String _adresse(Map<String, dynamic> corps) {
    final url = corps['url'];
    if (url is! String || url.isEmpty) {
      throw const EchecAbonnement(ErreurAbonnement.prestataire);
    }
    return url;
  }

  static ErreurAbonnement _traduireFonction(FunctionException echec) {
    // Aucune réponse n'est parvenue : c'est le réseau, pas le serveur.
    if (echec.status == 0) return ErreurAbonnement.inconnue;

    final details = echec.details;
    if (details is Map) {
      final erreur = details['error'];
      if (erreur is Map) {
        return ErreurAbonnement.depuisCode(erreur['code'] as String?);
      }
    }
    return switch (echec.status) {
      401 || 403 => ErreurAbonnement.droits,
      503 => ErreurAbonnement.nonConfigure,
      _ => ErreurAbonnement.inconnue,
    };
  }
}
