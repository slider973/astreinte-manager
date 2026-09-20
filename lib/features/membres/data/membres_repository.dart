import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/session/appartenance.dart';
import '../domain/invitation.dart';
import '../domain/membre_caserne.dart';

/// Tout ce que l'écran d'administration sait faire des membres et des
/// invitations d'une caserne.
///
/// Une interface, pas un client Supabase : l'écran se teste avec un faux.
abstract interface class MembresRepository {
  /// Les membres actifs de la caserne, triés par nom.
  Future<List<MembreCaserne>> membres(String stationId);

  /// Les invitations non acceptées, de la plus récente à la plus ancienne.
  Future<List<Invitation>> invitationsEnAttente(String stationId);

  /// Invite une ou plusieurs adresses. Lève un [EchecInvitation] quand la
  /// requête entière est refusée ; les refus par adresse sont dans le rapport.
  Future<RapportInvitations> inviter({
    required String stationId,
    required List<String> emails,
    required RoleMembre role,
  });

  /// Supprime une invitation en attente. Le lien déjà envoyé cesse de marcher.
  Future<void> annuler(String invitationId);
}

/// Implémentation Supabase.
///
/// Les deux écritures passent par l'Edge Function `invite-member` : les
/// fonctions SQL `create_invitation` et `accept_invitation` sont réservées au
/// rôle `service_role` (migration `0009`) et refusent un appel client.
class SupabaseMembresRepository implements MembresRepository {
  SupabaseMembresRepository(this._client);

  final SupabaseClient _client;

  /// Colonnes de `memberships` (§ 2.3) jointes aux colonnes affichables de
  /// `profiles` (§ 2.2).
  static const String _colonnesMembres =
      'id, user_id, role, status, display_name, '
      'profiles!inner(first_name, last_name, email)';

  /// **Jamais `select *`** : `invitations.token` est hors du grant de select
  /// du rôle `authenticated`, et une étoile ferait échouer la requête entière
  /// (`docs/SCHEMA.md § 4`, migration `0008`).
  static const String _colonnesInvitations =
      'id, email, role, expires_at, created_at';

  @override
  Future<List<MembreCaserne>> membres(String stationId) async {
    final lignes = await _client
        .from('memberships')
        .select(_colonnesMembres)
        .eq('station_id', stationId)
        .eq('status', StatutMembre.actif.valeurSql);

    final membres = lignes.map(MembreCaserne.depuisJson).toList()
      ..sort(
        (MembreCaserne a, MembreCaserne b) => a.cleDeTri.compareTo(b.cleDeTri),
      );
    return List<MembreCaserne>.unmodifiable(membres);
  }

  @override
  Future<List<Invitation>> invitationsEnAttente(String stationId) async {
    final lignes = await _client
        .from('invitations')
        .select(_colonnesInvitations)
        .eq('station_id', stationId)
        .isFilter('accepted_at', null)
        .order('created_at', ascending: false);

    return List<Invitation>.unmodifiable(lignes.map(Invitation.depuisJson));
  }

  @override
  Future<RapportInvitations> inviter({
    required String stationId,
    required List<String> emails,
    required RoleMembre role,
  }) async {
    try {
      final reponse = await _client.functions.invoke(
        'invite-member',
        body: <String, dynamic>{
          'station_id': stationId,
          'emails': emails,
          'role': role.valeurSql,
        },
      );

      final corps = reponse.data;
      if (corps is! Map<String, dynamic>) {
        throw const EchecInvitation(ErreurInvitation.inconnue);
      }
      return RapportInvitations.depuisJson(corps);
    } on FunctionException catch (echec) {
      throw EchecInvitation(_traduire(echec));
    }
  }

  @override
  Future<void> annuler(String invitationId) async {
    await _client.from('invitations').delete().eq('id', invitationId);
  }

  /// `{"error": {"code", "message"}}` — la forme unique des Edge Functions
  /// (`supabase/functions/_shared/http.ts`).
  static ErreurInvitation _traduire(FunctionException echec) {
    // Aucune réponse n'est parvenue : c'est le réseau, pas le serveur.
    if (echec.status == 0) return ErreurInvitation.reseau;

    final details = echec.details;
    if (details is Map) {
      final erreur = details['error'];
      if (erreur is Map) {
        return ErreurInvitation.depuisCode(erreur['code'] as String?);
      }
    }
    return echec.status >= 500
        ? ErreurInvitation.inconnue
        : ErreurInvitation.requeteInvalide;
  }
}
