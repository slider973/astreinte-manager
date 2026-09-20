import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/session/appartenance.dart';
import '../domain/invitation.dart';
import '../domain/membre_caserne.dart';

/// Tout ce que l'écran d'administration sait faire des membres et des
/// invitations d'une caserne.
///
/// Une interface, pas un client Supabase : l'écran se teste avec un faux.
abstract interface class MembresRepository {
  /// Les membres de la caserne — actifs **et** désactivés —, triés par nom.
  ///
  /// Les désactivés restent de la liste : on ne réactive pas quelqu'un qu'on
  /// ne voit plus.
  Future<List<MembreCaserne>> membres(String stationId);

  /// Par identifiant d'utilisateur, la date de sa dernière saisie de
  /// disponibilités dans cette caserne. Absent de la table : jamais saisi.
  Future<Map<String, DateTime>> dernieresSaisies(String stationId);

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

  /// Promeut ou rétrograde un membre. Lève un [EchecAdministration] si la base
  /// refuse — dernier admin, soi-même, droits, abonnement.
  Future<void> changerRole({
    required String membershipId,
    required RoleMembre role,
  });

  /// Désactive ou réactive l'accès d'un membre à la caserne.
  Future<void> changerStatut({
    required String membershipId,
    required StatutMembre statut,
  });

  /// Change le nom affiché dans la caserne. `null` efface le surnom et rend au
  /// membre le nom de son profil.
  Future<void> renommer({required String membershipId, String? nomAffiche});
}

/// Pourquoi une écriture d'administration a été refusée.
enum ErreurAdministration {
  /// Le déclencheur `memberships_guard_admin` : la caserne se retrouverait
  /// sans administrateur actif.
  dernierAdmin(AppStrings.membreRefusDernierAdmin),

  /// Le même déclencheur : un admin s'appliquait le retrait à lui-même.
  soiMeme(AppStrings.membreRefusSoiMeme),

  /// La RLS a filtré ou refusé la ligne. Les deux causes possibles ne sont pas
  /// distinguables depuis le client — `using` qui ne matche pas et `with
  /// check` qui échoue rendent la même chose —, la phrase les couvre donc
  /// toutes les deux.
  refusee(AppStrings.membreEchecRefus),

  /// Réseau tombé, serveur en vrac, réponse illisible : la sortie est la
  /// même, réessayer, et la phrase ne promet donc pas d'en savoir plus.
  inconnue(AppStrings.membreEchecGenerique);

  const ErreurAdministration(this.message);

  final String message;
}

/// Une écriture d'administration refusée, avec sa phrase déjà en français.
class EchecAdministration implements Exception {
  const EchecAdministration(this.erreur);

  final ErreurAdministration erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecAdministration(${erreur.name})';
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
        .inFilter('status', <String>[
          StatutMembre.actif.valeurSql,
          StatutMembre.desactive.valeurSql,
        ]);

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
  Future<Map<String, DateTime>> dernieresSaisies(String stationId) async {
    // `v_member_last_availability` (migration `0010`) : un `max(updated_at)`
    // par membre. Le groupement vit dans la base parce que les agrégats
    // PostgREST sont désactivés sur ce projet, et parce qu'un mois de
    // disponibilités pèse soixante lignes par membre.
    final lignes = await _client
        .from('v_member_last_availability')
        .select('user_id, last_set_at')
        .eq('station_id', stationId);

    return <String, DateTime>{
      for (final Map<String, dynamic> ligne in lignes)
        if (ligne['user_id'] is String && ligne['last_set_at'] is String)
          ligne['user_id']! as String: DateTime.parse(
            ligne['last_set_at']! as String,
          ),
    };
  }

  @override
  Future<void> annuler(String invitationId) async {
    await _client.from('invitations').delete().eq('id', invitationId);
  }

  @override
  Future<void> changerRole({
    required String membershipId,
    required RoleMembre role,
  }) => _ecrire(membershipId, <String, dynamic>{'role': role.valeurSql});

  @override
  Future<void> changerStatut({
    required String membershipId,
    required StatutMembre statut,
  }) => _ecrire(membershipId, <String, dynamic>{'status': statut.valeurSql});

  @override
  Future<void> renommer({required String membershipId, String? nomAffiche}) =>
      _ecrire(membershipId, <String, dynamic>{'display_name': nomAffiche});

  /// L'unique écriture sur `memberships`, avec sa relecture.
  ///
  /// Le `select` final n'est pas décoratif : une politique `using` qui ne
  /// matche pas **ne lève rien**, elle filtre. Sans relecture, un admin
  /// rétrogradé entre-temps verrait « c'est fait » sans que rien ne soit fait.
  ///
  /// `disabled_at` n'est pas écrit ici : le déclencheur le tient à jour
  /// (migration `0010`), pour que la date de sortie soit juste quel que soit
  /// l'auteur de l'écriture.
  Future<void> _ecrire(
    String membershipId,
    Map<String, dynamic> valeurs,
  ) async {
    try {
      final lignes = await _client
          .from('memberships')
          .update(valeurs)
          .eq('id', membershipId)
          .select('id');

      if (lignes.isEmpty) {
        throw const EchecAdministration(ErreurAdministration.refusee);
      }
    } on PostgrestException catch (echec) {
      throw EchecAdministration(_traduireEcriture(echec));
    }
  }

  /// Les deux messages du déclencheur `memberships_guard_admin` arrivent tels
  /// quels dans `message` : ce sont des identifiants, jamais affichés.
  static ErreurAdministration _traduireEcriture(PostgrestException echec) {
    final message = echec.message;
    if (message.contains('membership_last_admin')) {
      return ErreurAdministration.dernierAdmin;
    }
    if (message.contains('membership_self_admin_change')) {
      return ErreurAdministration.soiMeme;
    }
    // 42501 : la clause `with check` a refusé la ligne (plus admin, ou caserne
    // suspendue par `station_writable`).
    return echec.code == '42501'
        ? ErreurAdministration.refusee
        : ErreurAdministration.inconnue;
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
