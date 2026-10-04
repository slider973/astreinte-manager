import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../../astreintes/data/astreintes_repository.dart';
import '../../parametres/domain/parametres_caserne.dart';
import '../../planning/domain/suivi_planning.dart';
import '../domain/echange.dart';

/// Pourquoi une lecture ou un geste d'échange n'a pas abouti — **hors refus
/// métier**, qui reviennent en [ResultatEchange] et non en exception.
enum ErreurEchange {
  /// La requête n'est jamais partie, ou la réponse n'est jamais arrivée.
  reseau(AppStrings.erreurReseauTexte),

  /// La base a répondu par une erreur qui n'est pas un refus métier.
  inconnue(AppStrings.echangesErreur);

  const ErreurEchange(this.message);

  final String message;
}

class EchecEchange implements Exception {
  const EchecEchange(this.erreur);

  final ErreurEchange erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecEchange(${erreur.name})';
}

/// Ce que rend une des quatre fonctions d'échange.
///
/// Les refus métier sont des **réponses**, pas des pannes : la base les rend
/// en `{"ok": false, "code": …}` (`docs/SCHEMA.md § 3`), et l'écran a une
/// phrase pour chacun.
@immutable
class ResultatEchange {
  const ResultatEchange({
    required this.ok,
    this.code,
    this.statut,
    this.qui,
    this.codeMotif,
    this.detail,
    this.notifies,
    this.autoValide = false,
    this.expireLe,
    this.echangeId,
  });

  /// Lit la réponse JSON d'une fonction.
  factory ResultatEchange.depuisJson(Object? reponse) {
    final carte = reponse is Map
        ? Map<String, dynamic>.from(reponse)
        : const <String, dynamic>{};
    final statut = carte['status'];
    final expire = carte['expires_at'];
    final notifies = carte['notified'];
    return ResultatEchange(
      ok: carte['ok'] == true,
      code: carte['code'] as String?,
      statut: statut is String ? StatutEchange.depuisSql(statut) : null,
      qui: carte['who'] as String?,
      codeMotif: carte['reason_code'] as String?,
      detail: carte['detail'] as String?,
      notifies: notifies is num ? notifies.toInt() : null,
      autoValide: carte['auto_approved'] == true,
      expireLe: expire is String ? DateTime.tryParse(expire)?.toLocal() : null,
      echangeId: carte['exchange_id'] as String?,
    );
  }

  final bool ok;

  /// Le code du refus (`exchange_not_open`, `already_assigned`…), `null` en
  /// cas de succès.
  final String? code;

  /// Le statut de la demande après l'appel, quand la base le dit.
  final StatutEchange? statut;

  /// `target` ou `requester` : de qui parle une règle du remplaçant refusée
  /// à la demande.
  final String? qui;

  /// `reason_code` d'un `exchange_failed`.
  final String? codeMotif;

  /// Le motif précis d'un échec que les pompiers ne lisent pas
  /// (`*_taken_elsewhere`), rendu au seul administrateur.
  final String? detail;

  /// `notified` de `request_exchange` : le nombre de destinataires **mis en
  /// file**. Zéro pour une demande à la caserne que personne n'est libre de
  /// reprendre — et l'écran doit le dire.
  final int? notifies;

  final bool autoValide;
  final DateTime? expireLe;
  final String? echangeId;
}

/// Tout ce que les écrans d'échange savent lire et faire.
///
/// **Le contrat de coût est dans l'interface** : [lister] vaut deux requêtes
/// (les demandes, puis les noms de la caserne), [collegues] une, [gardesDe]
/// une, [reglages] une, et chaque geste exactement un appel de fonction.
abstract interface class EchangesRepository {
  /// Les demandes que la RLS montre à ce compte dans la caserne : les
  /// siennes, celles « à la caserne » qui lui sont envoyées, et toutes pour un
  /// administrateur. Les demandes closes depuis plus de trente jours ne sont
  /// pas relues.
  Future<List<Echange>> lister({required String stationId});

  /// Les membres actifs de la caserne, sauf [moi], par ordre alphabétique.
  Future<List<Collegue>> collegues({
    required String stationId,
    required String moi,
  });

  /// Les gardes de [pairId] que je peux demander en retour, dans cette
  /// caserne (`exchangeable_shifts_of`).
  Future<List<GardeProposable>> gardesDe({
    required String pairId,
    required String stationId,
  });

  /// La validation automatique et l'échéance, lues dans les réglages.
  Future<ReglagesEchange> reglages(String stationId);

  Future<ResultatEchange> demander({
    required String attributionId,
    String? cibleId,
    String? attributionRendueId,
  });

  Future<ResultatEchange> repondre({
    required String echangeId,
    required bool accepte,
  });

  Future<ResultatEchange> decider({
    required String echangeId,
    required bool valide,
    String? motif,
  });

  Future<ResultatEchange> annuler({required String echangeId});
}

/// Implémentation Supabase.
class SupabaseEchangesRepository implements EchangesRepository {
  const SupabaseEchangesRepository(this._client, {DateTime Function()? horloge})
    : _horloge = horloge ?? DateTime.now;

  final SupabaseClient _client;
  final DateTime Function() _horloge;

  /// Combien de temps une demande close reste relue : les trente jours de
  /// « Terminés » côté administrateur (`design/073 § 8.4`).
  static const Duration historique = Duration(days: 30);

  @override
  Future<List<Echange>> lister({required String stationId}) async {
    try {
      final depuis = _horloge().toUtc().subtract(historique).toIso8601String();
      final lignes = await _client
          .from('shift_exchanges')
          .select(Echange.colonnes)
          .eq('station_id', stationId)
          // Les demandes en cours, toujours ; les closes, trente jours.
          .or('status.in.(open,accepted_by_peer),updated_at.gte.$depuis')
          .order('created_at', ascending: false)
          .limit(200);
      if (lignes.isEmpty) return const <Echange>[];

      final noms = await _noms(stationId);
      return <Echange>[
        for (final ligne in lignes)
          if (Echange.depuisJson(ligne, noms: noms) case final Echange e) e,
      ];
    } on Object catch (echec) {
      throw EchecEchange(_traduire(echec));
    }
  }

  /// Les noms d'usage de la caserne, par identifiant. **Le nom vit dans
  /// `memberships`**, comme pour les équipiers du ticket 027 : une lecture de
  /// la caserne, soixante lignes au plus.
  Future<Map<String, String>> _noms(String stationId) async {
    final membres = await _client
        .from('memberships')
        .select(AttributionSuivi.colonnesMembre)
        .eq('station_id', stationId);
    return <String, String>{
      for (final ligne in membres)
        ligne['user_id']! as String: AttributionSuivi.nomDeMembre(ligne),
    };
  }

  @override
  Future<List<Collegue>> collegues({
    required String stationId,
    required String moi,
  }) async {
    try {
      final membres = await _client
          .from('memberships')
          .select(AttributionSuivi.colonnesMembre)
          .eq('station_id', stationId)
          .eq('status', 'active');
      return <Collegue>[
        for (final ligne in membres)
          if (ligne['user_id'] != moi)
            Collegue(
              userId: ligne['user_id']! as String,
              nom: AttributionSuivi.nomDeMembre(ligne),
            ),
      ]..sort(
        (Collegue a, Collegue b) =>
            a.nom.toLowerCase().compareTo(b.nom.toLowerCase()),
      );
    } on Object catch (echec) {
      throw EchecEchange(_traduire(echec));
    }
  }

  @override
  Future<List<GardeProposable>> gardesDe({
    required String pairId,
    required String stationId,
  }) async {
    try {
      final lignes = await _client.rpc<List<dynamic>>(
        'exchangeable_shifts_of',
        params: <String, dynamic>{'p_peer': pairId},
      );
      return <GardeProposable>[
        for (final ligne in lignes)
          if (GardeProposable.depuisJson(Map<String, dynamic>.from(ligne as Map))
              case final GardeProposable garde
              // La fonction rend les gardes de **toutes** les casernes
              // partagées : l'échange entre casernes est hors périmètre.
              when garde.stationId == stationId)
            garde,
      ]..sort((GardeProposable a, GardeProposable b) => a.comparer(b));
    } on Object catch (echec) {
      throw EchecEchange(_traduire(echec));
    }
  }

  @override
  Future<ReglagesEchange> reglages(String stationId) async {
    try {
      final ligne = await _client
          .from('stations')
          .select('id, name, timezone, settings')
          .eq('id', stationId)
          .maybeSingle();
      if (ligne == null) return ReglagesEchange.defaut;
      final parametres = ParametresCaserne.depuisJson(ligne);
      return ReglagesEchange(
        validationAuto: parametres.echangeAuto,
        echeanceHeures: parametres.echangeEcheanceHeures,
        debutJour: parametres.debutJour,
        finJour: parametres.finJour,
      );
    } on Object {
      // Un confort d'affichage : la base pose l'échéance elle-même.
      return ReglagesEchange.defaut;
    }
  }

  // Les quatre gestes. **Les arguments sont construits à la main**, clé par
  // clé (leçon du ticket 021) : jamais un `toJson()` de modèle.

  @override
  Future<ResultatEchange> demander({
    required String attributionId,
    String? cibleId,
    String? attributionRendueId,
  }) => _appeler('request_exchange', <String, dynamic>{
    'p_assignment': attributionId,
    'p_target': cibleId,
    'p_return_assignment': attributionRendueId,
  });

  @override
  Future<ResultatEchange> repondre({
    required String echangeId,
    required bool accepte,
  }) => _appeler('respond_exchange', <String, dynamic>{
    'p_exchange': echangeId,
    'p_accept': accepte,
  });

  @override
  Future<ResultatEchange> decider({
    required String echangeId,
    required bool valide,
    String? motif,
  }) {
    final propre = motif?.trim();
    return _appeler('decide_exchange', <String, dynamic>{
      'p_exchange': echangeId,
      'p_approve': valide,
      'p_reason': (!valide && propre != null && propre.isNotEmpty)
          ? propre
          : null,
    });
  }

  @override
  Future<ResultatEchange> annuler({required String echangeId}) =>
      _appeler('cancel_exchange', <String, dynamic>{'p_exchange': echangeId});

  Future<ResultatEchange> _appeler(
    String fonction,
    Map<String, dynamic> arguments,
  ) async {
    try {
      final reponse = await _client.rpc<dynamic>(fonction, params: arguments);
      return ResultatEchange.depuisJson(reponse);
    } on Object catch (echec) {
      throw EchecEchange(_traduire(echec));
    }
  }

  static ErreurEchange _traduire(Object echec) {
    if (echec is EchecEchange) return echec.erreur;
    return echecDeTransport(echec) ? ErreurEchange.reseau : ErreurEchange.inconnue;
  }
}
