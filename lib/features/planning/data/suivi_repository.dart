import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../domain/creneau_planning.dart';
import '../domain/suivi_planning.dart';

/// Pourquoi une lecture ou une action du suivi a échoué.
enum ErreurSuivi {
  /// `not_admin` : l'appelant n'administre pas cette caserne.
  reserveAdmin(AppStrings.publierReserveAdmin),

  /// `station_suspended`, ou une politique qui refuse l'écriture.
  lectureSeule(AppStrings.lectureSeuleDetail),

  /// `schedule_not_found` : le planning n'existe plus.
  planningIntrouvable(AppStrings.suiviAbsentTexte),

  /// `schedule_not_draft` : l'adjoint a publié le premier. Ce n'est pas une
  /// panne.
  dejaPublie(AppStrings.publierDejaFait),

  /// `schedule_not_published` : on ne relance pas un brouillon.
  pasPublie(AppStrings.suiviBrouillonTexte),

  reseau(AppStrings.erreurReseauTexte),

  inconnue(AppStrings.suiviErreurTexte);

  const ErreurSuivi(this.message);

  final String message;

  static ErreurSuivi depuisCode(String? code) => switch (code) {
    'not_admin' => ErreurSuivi.reserveAdmin,
    'station_suspended' => ErreurSuivi.lectureSeule,
    'schedule_not_found' => ErreurSuivi.planningIntrouvable,
    'schedule_not_draft' => ErreurSuivi.dejaPublie,
    'schedule_not_published' => ErreurSuivi.pasPublie,
    _ => ErreurSuivi.inconnue,
  };
}

/// Un accès au suivi refusé, avec sa phrase déjà en français.
class EchecSuivi implements Exception {
  const EchecSuivi(this.erreur);

  final ErreurSuivi erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecSuivi(${erreur.name})';
}

/// Ce que la publication rend à l'administrateur qui vient de cliquer.
///
/// [membres] compte des **personnes**, pas des attributions : c'est le nombre
/// de téléphones qui ont sonné, et c'est lui qu'on annonce.
class ResultatPublication {
  const ResultatPublication({
    required this.membres,
    required this.attributions,
    this.envoiComplet = true,
  });

  final int membres;
  final int attributions;

  /// Faux quand `send-notification` n'a pas servi tout le monde. **La
  /// publication reste acquise** : elle est faite en base, et une notification
  /// manquée se rattrape par une relance.
  final bool envoiComplet;
}

/// Ce que la relance rend.
class ResultatRelance {
  const ResultatRelance({required this.membres, required this.nouvelle});

  final int membres;

  /// Faux quand la clé de dédoublonnage a écarté la demande : ces pompiers ont
  /// déjà été relancés dans l'heure. Le dire vaut mieux que feindre un envoi.
  final bool nouvelle;
}

/// Ce que le canal temps réel du suivi annonce.
///
/// Deux tables, une seule discipline. `assignments` y était depuis le ticket
/// 017 ; `schedules` y entre au 019 parce que **la validation automatique est
/// un `update` que personne ne déclenche depuis cet écran**.
sealed class EvenementSuivi {
  const EvenementSuivi();
}

/// Une attribution posée ou modifiée ailleurs — le plus souvent, une réponse.
///
/// Le nom du membre **n'est pas dans la charge utile** : `postgres_changes`
/// diffuse les colonnes de la table, pas les jointures. Le contrôleur reprend
/// celui qu'il connaît déjà.
final class ReponseRecue extends EvenementSuivi {
  const ReponseRecue(this.attribution);

  final AttributionSuivi attribution;
}

/// Une attribution supprimée ailleurs. Seule la clé primaire est diffusée
/// (identité de réplique `default`, `design/017 § 7.2`).
final class ReponseSupprimee extends EvenementSuivi {
  const ReponseSupprimee(this.id);

  final String id;
}

/// Le planning a changé d'état. C'est presque toujours la validation
/// automatique, et c'est le seul moment chorégraphié de l'application.
final class PlanningRecu extends EvenementSuivi {
  const PlanningRecu(this.planning);

  final PlanningBrouillon planning;
}

/// L'état du canal. Un écran qui perd son abonnement en silence est un écran
/// qui ment.
final class EtatCanalSuivi extends EvenementSuivi {
  const EtatCanalSuivi({required this.branche});

  final bool branche;
}

/// Tout ce que l'écran de suivi sait faire.
abstract interface class SuiviRepository {
  /// Le suivi d'un mois : le planning, ses créneaux, toutes ses attributions et
  /// son avancement. Rend un [SuiviPlanning] **vide** quand le planning n'a pas
  /// encore été construit : c'est un état normal, pas une erreur.
  Future<SuiviPlanning> lire({
    required String stationId,
    required String periodeId,
    required int annee,
    required int mois,
  });

  /// L'avancement seul. Relu après une salve de réponses reçues en temps
  /// réel : le canal diffuse des lignes, pas des agrégats, et les six nombres
  /// du bloc de progression ne se recomptent pas en Dart.
  Future<ProgressionPlanning> lireProgression({required String planningId});

  /// Publie le planning : Edge Function `publish-schedule`.
  Future<ResultatPublication> publier({required String planningId});

  /// Relance les retardataires : `remind_schedule(p_schedule)`.
  Future<ResultatRelance> relancer({required String planningId});

  /// Le canal temps réel des attributions **et** des plannings.
  Stream<EvenementSuivi> ecouter({required String stationId});
}

/// Implémentation Supabase.
class SupabaseSuiviRepository implements SuiviRepository {
  const SupabaseSuiviRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<SuiviPlanning> lire({
    required String stationId,
    required String periodeId,
    required int annee,
    required int mois,
  }) async {
    try {
      final planning = await _client
          .from('schedules')
          .select(PlanningBrouillon.colonnes)
          .eq('station_id', stationId)
          .eq('period_id', periodeId)
          .maybeSingle();

      if (planning == null) return SuiviPlanning.vide(annee: annee, mois: mois);

      final entete = PlanningBrouillon.depuisJson(planning);

      final creneaux = await _client
          .from('shifts')
          .select(CreneauPlanning.colonnes)
          .eq('station_id', stationId)
          .eq('schedule_id', entete.id)
          .order('date');

      final ids = <String>[
        for (final ligne in creneaux) ligne['id']! as String,
      ];

      // **Tous les statuts**, pas seulement les actifs : un refus est
      // l'information la plus utile de l'écran, et un créneau dont l'unique
      // attribution est refusée doit montrer pourquoi il est redevenu vide.
      final attributions = ids.isEmpty
          ? const <Map<String, dynamic>>[]
          : await _client
                .from('assignments')
                .select(AttributionSuivi.colonnes)
                .eq('station_id', stationId)
                .inFilter('shift_id', ids);

      // **Le nom d'usage vit dans `memberships`, pas dans `profiles`**
      // (`docs/SCHEMA.md § 2.3`) : une jointure depuis `assignments` ne peut
      // donc pas le rapporter. Une lecture de la caserne — soixante lignes —
      // le donne pour tout le monde, y compris les membres désactivés depuis :
      // une attribution ne perd pas son nom parce que son titulaire est parti.
      final membres = await _client
          .from('memberships')
          .select(AttributionSuivi.colonnesMembre)
          .eq('station_id', stationId);

      final noms = <String, String>{
        for (final ligne in membres)
          ligne['user_id']! as String: AttributionSuivi.nomDeMembre(ligne),
      };

      // La vue du ticket 017. Six nombres, rendus par la base, que rien ne
      // recompte en Dart.
      final avancement = await _client
          .from('v_schedule_progress')
          .select(ProgressionPlanning.colonnes)
          .eq('schedule_id', entete.id)
          .maybeSingle();

      // Le délai de retard de la caserne. Une requête d'une ligne, mais le
      // sous-titre du bloc des retardataires annonce le délai **réel** : un 72
      // écrit en dur mentirait à toute caserne qui a changé son réglage.
      final caserne = await _client
          .from('stations')
          .select('settings')
          .eq('id', stationId)
          .maybeSingle();

      return SuiviPlanning(
        planning: entete,
        progression: avancement == null
            ? ProgressionPlanning.vide
            : ProgressionPlanning.depuisJson(avancement),
        creneaux: <CreneauPlanning>[
          for (final ligne in creneaux) CreneauPlanning.depuisJson(ligne),
        ],
        attributions: <AttributionSuivi>[
          for (final ligne in attributions)
            AttributionSuivi.depuisJson(
              ligne,
              nom: noms[ligne['user_id'] as String?] ?? '',
            ),
        ],
        annee: annee,
        mois: mois,
        delaiRetardHeures: _delaiRetard(caserne),
      );
    } on Object catch (echec) {
      throw EchecSuivi(_traduire(echec));
    }
  }

  @override
  Future<ProgressionPlanning> lireProgression({
    required String planningId,
  }) async {
    try {
      final ligne = await _client
          .from('v_schedule_progress')
          .select(ProgressionPlanning.colonnes)
          .eq('schedule_id', planningId)
          .maybeSingle();
      return ligne == null
          ? ProgressionPlanning.vide
          : ProgressionPlanning.depuisJson(ligne);
    } on Object catch (echec) {
      throw EchecSuivi(_traduire(echec));
    }
  }

  @override
  Future<ResultatPublication> publier({required String planningId}) async {
    try {
      final reponse = await _client.functions.invoke(
        'publish-schedule',
        body: <String, dynamic>{'schedule_id': planningId},
      );

      final corps = reponse.data;
      if (corps is! Map<String, dynamic>) {
        throw const EchecSuivi(ErreurSuivi.inconnue);
      }

      final envoi = corps['notification'];
      return ResultatPublication(
        membres: (corps['notified'] as int?) ?? 0,
        attributions: (corps['assignments'] as int?) ?? 0,
        envoiComplet: envoi is! Map<String, dynamic> ||
            ((envoi['ok'] as bool?) ?? true),
      );
    } on FunctionException catch (echec) {
      throw EchecSuivi(_traduireFonction(echec));
    } on Object catch (echec) {
      throw EchecSuivi(_traduire(echec));
    }
  }

  @override
  Future<ResultatRelance> relancer({required String planningId}) async {
    try {
      final reponse = await _client.rpc<dynamic>(
        'remind_schedule',
        params: <String, dynamic>{'p_schedule': planningId},
      );

      if (reponse is! Map<String, dynamic>) {
        throw const EchecSuivi(ErreurSuivi.inconnue);
      }
      if ((reponse['ok'] as bool?) != true) {
        throw EchecSuivi(ErreurSuivi.depuisCode(reponse['code'] as String?));
      }

      return ResultatRelance(
        membres: (reponse['members'] as int?) ?? 0,
        // `outbox_id` nul avec des destinataires : la clé de dédoublonnage a
        // écarté la demande, personne ne recevra rien de plus dans l'heure.
        nouvelle: reponse['outbox_id'] != null,
      );
    } on Object catch (echec) {
      throw EchecSuivi(_traduire(echec));
    }
  }

  /// Le canal du suivi : **un seul canal Supabase, deux souscriptions**.
  ///
  /// Un canal par table doublerait le coût de connexion pour la même
  /// information. Comme au ticket 017, aucun filtre côté serveur : un filtre
  /// ne s'évalue que sur les colonnes diffusées, et la charge utile d'un
  /// `delete` se réduit à la clé primaire. Le tri se fait côté client, où les
  /// politiques de `select` ont déjà réduit ce qui arrive.
  @override
  Stream<EvenementSuivi> ecouter({required String stationId}) {
    final controleur = StreamController<EvenementSuivi>();
    final canal = _client.channel('suivi:$stationId');

    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'assignments',
          callback: (PostgresChangePayload charge) {
            final evenement = _evenementAttribution(charge);
            if (evenement != null && !controleur.isClosed) {
              controleur.add(evenement);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'schedules',
          callback: (PostgresChangePayload charge) {
            final ligne = charge.newRecord;
            if (ligne['id'] == null || controleur.isClosed) return;
            controleur.add(PlanningRecu(PlanningBrouillon.depuisJson(ligne)));
          },
        )
        .subscribe((RealtimeSubscribeStatus statut, Object? _) {
          if (controleur.isClosed) return;
          controleur.add(
            EtatCanalSuivi(
              branche: statut == RealtimeSubscribeStatus.subscribed,
            ),
          );
        });

    controleur.onCancel = () async {
      await _client.removeChannel(canal);
      await controleur.close();
    };

    return controleur.stream;
  }

  static EvenementSuivi? _evenementAttribution(PostgresChangePayload charge) {
    switch (charge.eventType) {
      case PostgresChangeEvent.delete:
        final id = charge.oldRecord['id'] as String?;
        return id == null ? null : ReponseSupprimee(id);
      case PostgresChangeEvent.insert:
      case PostgresChangeEvent.update:
        final ligne = charge.newRecord;
        if (ligne['id'] == null || ligne['shift_id'] == null) return null;
        return ReponseRecue(AttributionSuivi.depuisJson(ligne));
      case PostgresChangeEvent.all:
        return null;
    }
  }

  static int _delaiRetard(Map<String, dynamic>? caserne) {
    final reglages = caserne?['settings'];
    if (reglages is! Map<String, dynamic>) return 72;
    final valeur = reglages['late_report_hours'];
    if (valeur is int && valeur > 0) return valeur;
    if (valeur is String) return int.tryParse(valeur) ?? 72;
    return 72;
  }

  static ErreurSuivi _traduireFonction(FunctionException echec) {
    // Aucune réponse n'est parvenue : c'est le réseau, pas le serveur.
    if (echec.status == 0) return ErreurSuivi.reseau;

    final details = echec.details;
    if (details is Map) {
      final erreur = details['error'];
      if (erreur is Map) {
        return ErreurSuivi.depuisCode(erreur['code'] as String?);
      }
    }
    return echec.status == 401 ? ErreurSuivi.reserveAdmin : ErreurSuivi.inconnue;
  }

  static ErreurSuivi _traduire(Object echec) {
    if (echec is EchecSuivi) return echec.erreur;
    if (echec is FunctionException) return _traduireFonction(echec);
    if (echec is PostgrestException) {
      final message = echec.message.toLowerCase();
      if (message.contains('forbidden')) return ErreurSuivi.reserveAdmin;
      if (message.contains('station_suspended') || echec.code == '42501') {
        return ErreurSuivi.lectureSeule;
      }
      if (message.contains('schedule_not_found')) {
        return ErreurSuivi.planningIntrouvable;
      }
      // Un code absent signale une réponse qui n'est jamais arrivée.
      if (echec.code == null) return ErreurSuivi.reseau;
      return ErreurSuivi.inconnue;
    }
    if (echec is AuthException) return ErreurSuivi.inconnue;
    return ErreurSuivi.reseau;
  }
}
