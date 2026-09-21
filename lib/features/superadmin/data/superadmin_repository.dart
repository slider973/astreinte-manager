import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../domain/caserne_supervisee.dart';

/// Tout ce que l'écran de l'éditeur du produit sait faire.
///
/// Une interface, pas un client Supabase : l'écran se teste avec un faux, y
/// compris dans l'état « je ne suis pas l'éditeur », qui est celui de tout le
/// monde sauf une personne.
///
/// **Il n'y a pas de méthode d'invitation ici.** Nommer le premier
/// administrateur d'une caserne passe par `MembresRepository.inviter` — donc
/// par l'Edge Function `invite-member` et par `create_invitation` (ticket 006).
/// Un second chemin d'invitation aurait dupliqué la validation d'adresse, le
/// renvoi, le contrôle de suspension et la trace d'audit.
abstract interface class SuperAdminRepository {
  /// Vrai si le compte connecté est inscrit dans `super_admins`.
  ///
  /// C'est cette réponse qui ouvre la route `/superadmin` ; la base la
  /// redemande de toute façon à chaque appel de fonction.
  Future<bool> estSuperAdmin();

  /// Les casernes et leurs faits d'exploitation, triées par nom.
  Future<List<CaserneSupervisee>> casernes();

  /// Crée une caserne et rend son identifiant. L'essai de 60 jours est posé
  /// par la base, pas par l'appelant.
  Future<CaserneSupervisee> creerCaserne({
    required String nom,
    required String fuseau,
  });

  /// Suspend ou réactive une caserne. [raison] est obligatoire et part dans le
  /// journal d'audit de la caserne.
  Future<void> definirSuspension({
    required String stationId,
    required bool suspendue,
    required String raison,
  });

  /// La consultation de support : les plannings d'une caserne, du plus récent
  /// au plus ancien. **Chaque appel laisse une ligne d'audit** dans la caserne
  /// consultée ; [raison] y est inscrite telle quelle.
  Future<List<PlanningSupervise>> plannings({
    required String stationId,
    required String raison,
  });
}

/// Pourquoi une action de l'éditeur a été refusée.
enum ErreurSuperAdmin {
  /// Le compte n'est pas (ou n'est plus) dans `super_admins`.
  droits(AppStrings.superAdminRefusDroits),

  /// Nom de caserne vide ou trop long.
  nom(AppStrings.superAdminRefusNom),

  /// Fuseau absent de `pg_timezone_names`.
  fuseau(AppStrings.superAdminRefusFuseau),

  /// Raison absente ou trop courte : la base refuse, pas seulement le
  /// formulaire.
  raison(AppStrings.superAdminRefusRaison),

  /// La caserne a disparu entre l'affichage de la liste et l'action.
  caserneInconnue(AppStrings.superAdminRefusCaserne),

  reseau(AppStrings.erreurReseauTexte),

  inconnue(AppStrings.erreurTexteGenerique);

  const ErreurSuperAdmin(this.message);

  final String message;

  /// Les codes rendus par les fonctions SQL (`docs/SCHEMA.md § 3`).
  static ErreurSuperAdmin depuisCode(String? code) => switch (code) {
    'forbidden' => droits,
    'invalid_name' => nom,
    'invalid_timezone' => fuseau,
    'reason_required' => raison,
    'station_not_found' => caserneInconnue,
    _ => inconnue,
  };
}

/// Une action de l'éditeur refusée, avec sa phrase déjà en français.
class EchecSuperAdmin implements Exception {
  const EchecSuperAdmin(this.erreur);

  final ErreurSuperAdmin erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecSuperAdmin(${erreur.name})';
}

/// Implémentation Supabase : quatre appels RPC, et rien d'autre.
///
/// Aucune table n'est interrogée directement, et ce n'est pas un choix de
/// style : depuis la migration `0025`, l'éditeur n'a **aucune** politique de
/// lecture hors `super_admins`. Un `select` direct sur `stations` rendrait zéro
/// ligne, silencieusement.
class SupabaseSuperAdminRepository implements SuperAdminRepository {
  const SupabaseSuperAdminRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> estSuperAdmin() async {
    try {
      final reponse = await _client.rpc<dynamic>('is_super_admin');
      return reponse == true;
    } on Object {
      // Un échec de lecture **n'invente jamais un droit**, et n'invente pas non
      // plus son absence pour un écran qui refusera de toute façon côté base :
      // on répond non, la route reste fermée, et rien n'est cassé.
      return false;
    }
  }

  @override
  Future<List<CaserneSupervisee>> casernes() async {
    final reponse = await _executer<dynamic>('super_admin_stations');
    final lignes = reponse is List ? reponse : const <dynamic>[];
    return List<CaserneSupervisee>.unmodifiable(
      lignes.whereType<Map<String, dynamic>>().map(
        CaserneSupervisee.depuisJson,
      ),
    );
  }

  @override
  Future<CaserneSupervisee> creerCaserne({
    required String nom,
    required String fuseau,
  }) async {
    final corps = await _appeler(
      'super_admin_create_station',
      <String, dynamic>{'p_name': nom, 'p_timezone': fuseau},
    );

    final creee = corps['station'];
    if (creee is! Map<String, dynamic>) {
      throw const EchecSuperAdmin(ErreurSuperAdmin.inconnue);
    }

    // La caserne vient de naître : aucun membre, aucun planning, un essai. On
    // compose la ligne au lieu de relire la liste, pour que la feuille puisse
    // enchaîner sur l'invitation sans attendre un aller-retour de plus.
    return CaserneSupervisee.depuisJson(<String, dynamic>{
      ...creee,
      'active_members': 0,
      'active_admins': 0,
      'pending_invites': 0,
      'status': 'trialing',
      'writable': true,
    });
  }

  @override
  Future<void> definirSuspension({
    required String stationId,
    required bool suspendue,
    required String raison,
  }) async {
    await _appeler('super_admin_set_station_suspended', <String, dynamic>{
      'p_station': stationId,
      'p_suspended': suspendue,
      'p_reason': raison,
    });
  }

  @override
  Future<List<PlanningSupervise>> plannings({
    required String stationId,
    required String raison,
  }) async {
    final corps = await _appeler(
      'super_admin_support_schedules',
      <String, dynamic>{'p_station': stationId, 'p_reason': raison},
    );

    final lignes = corps['schedules'];
    return List<PlanningSupervise>.unmodifiable(
      (lignes is List ? lignes : const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(PlanningSupervise.depuisJson),
    );
  }

  /// Un appel qui rend `{ok: …}` : le refus métier y est un code, jamais une
  /// exception Postgres (même convention qu'`create_invitation`).
  Future<Map<String, dynamic>> _appeler(
    String fonction,
    Map<String, dynamic> parametres,
  ) async {
    final reponse = await _executer<dynamic>(fonction, parametres);
    if (reponse is! Map<String, dynamic>) {
      throw const EchecSuperAdmin(ErreurSuperAdmin.inconnue);
    }
    if (reponse['ok'] != true) {
      throw EchecSuperAdmin(
        ErreurSuperAdmin.depuisCode(reponse['code'] as String?),
      );
    }
    return reponse;
  }

  Future<T> _executer<T>(String fonction, [Map<String, dynamic>? parametres]) {
    return _client.rpc<T>(fonction, params: parametres).onError<Object>((
      Object erreur,
      _,
    ) {
      if (erreur is EchecSuperAdmin) throw erreur;
      throw EchecSuperAdmin(_traduire(erreur));
    });
  }

  static ErreurSuperAdmin _traduire(Object erreur) {
    if (erreur is PostgrestException) {
      // 42501 : `permission denied for function`. Le compte n'est pas l'éditeur
      // — ou ne l'est plus, et la liste affichée date d'avant.
      if (erreur.code == '42501') return ErreurSuperAdmin.droits;
      return ErreurSuperAdmin.inconnue;
    }
    return ErreurSuperAdmin.reseau;
  }
}
