import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/acceptation.dart';
import '../domain/invitation_recue.dart';

/// L'échange d'une invitation contre une place dans la caserne, et la
/// question posée avant : « est-ce qu'on m'attend quelque part ? »
abstract interface class InvitationRepository {
  /// Lève un [EchecAcceptation] pour chaque fin de parcours du contrat
  /// (`supabase/functions/README.md § accept-invitation`).
  Future<AcceptationInvitation> accepter(EntreeInvitation entree);

  /// Les invitations non acceptées adressées à l'adresse de la session.
  ///
  /// **Zéro ligne n'est pas une erreur** : « pas d'invitation » et « pas le
  /// droit » sont indiscernables côté serveur, et c'est ce qui rend la
  /// fonction sûre. Une exception, elle, ne dit qu'une chose : la question n'a
  /// pas pu être posée — réseau ou serveur.
  Future<List<InvitationRecue>> mesInvitations();
}

/// Implémentation Supabase.
///
/// L'acceptation passe par l'Edge Function : les fonctions SQL
/// `accept_invitation` et `accept_invitation_by_id` sont réservées au rôle
/// `service_role` (migrations `0009` et `0036`) et refusent un client. C'est
/// la base qui confronte l'adresse de l'invitation à celle de la session.
class SupabaseInvitationRepository implements InvitationRepository {
  SupabaseInvitationRepository(this._client);

  /// La fonction sans paramètre qui rend les invitations de la session.
  ///
  /// **Sans paramètre, et c'est la contrainte principale** : l'adresse vient
  /// de `auth.jwt() ->> 'email'`, jamais d'un argument. Une fonction qui
  /// accepterait une adresse serait un oracle d'énumération.
  static const String _fonctionInvitations = 'my_pending_invitations';

  final SupabaseClient _client;

  @override
  Future<AcceptationInvitation> accepter(EntreeInvitation entree) async {
    if (entree.vide) {
      throw const EchecAcceptation(ErreurAcceptation.jetonManquant);
    }

    // Un jeton **ou** un identifiant, jamais les deux : le serveur refuse un
    // corps qui porterait les deux champs, et le type d'[EntreeInvitation]
    // rend cette requête-là impossible à composer.
    final corps = switch (entree.mode) {
      ModeInvitation.jeton => <String, dynamic>{'token': entree.valeurNettoyee},
      ModeInvitation.identifiant => <String, dynamic>{
        'invitation_id': entree.valeurNettoyee,
      },
    };

    try {
      final reponse = await _client.functions.invoke(
        'accept-invitation',
        body: corps,
      );

      final corpsReponse = reponse.data;
      if (corpsReponse is! Map<String, dynamic>) {
        throw const EchecAcceptation(ErreurAcceptation.inconnue);
      }
      return AcceptationInvitation.depuisJson(corpsReponse);
    } on FunctionException catch (echec) {
      throw _traduire(echec);
    }
  }

  @override
  Future<List<InvitationRecue>> mesInvitations() async {
    final reponse = await _client.rpc<dynamic>(_fonctionInvitations);
    return InvitationRecue.depuisListe(reponse);
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

    // `station` et `invited_email_masked` sont **absents** quand le refus
    // vient d'un identifiant (ticket 051) : la vue le tolère et dit la même
    // chose autrement.
    return EchecAcceptation(
      ErreurAcceptation.depuisCode(erreur['code'] as String?),
      caserne: CaserneInvitation.depuisJson(erreur['station']),
      inviteur: InviteurInvitation.depuisJson(erreur['inviter']),
      adresseInviteeMasquee: erreur['invited_email_masked'] as String?,
      adresseCourante: erreur['current_email'] as String?,
    );
  }
}
