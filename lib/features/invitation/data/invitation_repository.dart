import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/acceptation.dart';

/// L'échange d'un jeton d'invitation contre une place dans la caserne.
abstract interface class InvitationRepository {
  /// Lève un [EchecAcceptation] pour chaque fin de parcours du contrat
  /// (`supabase/functions/README.md § accept-invitation`).
  Future<AcceptationInvitation> accepter(String jeton);
}

/// Implémentation Supabase.
///
/// L'appel passe par l'Edge Function : la fonction SQL `accept_invitation` est
/// réservée au rôle `service_role` (migration `0009`) et refuse un client.
/// C'est elle qui confronte l'adresse du jeton à celle de la session.
class SupabaseInvitationRepository implements InvitationRepository {
  SupabaseInvitationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<AcceptationInvitation> accepter(String jeton) async {
    if (jeton.trim().isEmpty) {
      throw const EchecAcceptation(ErreurAcceptation.jetonManquant);
    }

    try {
      final reponse = await _client.functions.invoke(
        'accept-invitation',
        body: <String, dynamic>{'token': jeton.trim()},
      );

      final corps = reponse.data;
      if (corps is! Map<String, dynamic>) {
        throw const EchecAcceptation(ErreurAcceptation.inconnue);
      }
      return AcceptationInvitation.depuisJson(corps);
    } on FunctionException catch (echec) {
      throw _traduire(echec);
    }
  }

  static EchecAcceptation _traduire(FunctionException echec) {
    if (echec.status == 0) {
      return const EchecAcceptation(ErreurAcceptation.reseau);
    }

    final details = echec.details;
    final erreur = details is Map ? details['error'] : null;
    if (erreur is! Map) {
      return const EchecAcceptation(ErreurAcceptation.inconnue);
    }

    return EchecAcceptation(
      ErreurAcceptation.depuisCode(erreur['code'] as String?),
      caserne: CaserneInvitation.depuisJson(erreur['station']),
      inviteur: InviteurInvitation.depuisJson(erreur['inviter']),
      adresseInviteeMasquee: erreur['invited_email_masked'] as String?,
      adresseCourante: erreur['current_email'] as String?,
    );
  }
}
