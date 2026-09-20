import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../domain/creneau_planning.dart';
import '../domain/planning_mois.dart';

/// Pourquoi une lecture ou une écriture du planning a échoué.
enum ErreurPlanning {
  /// `create_schedule` a levé `forbidden` : l'appelant n'administre pas cette
  /// caserne.
  reserveAdmin(AppStrings.matriceReserveAdmin),

  /// `period_not_found` : le mois n'existe plus, ou n'appartient pas à cette
  /// caserne.
  moisIntrouvable(AppStrings.matriceMoisIntrouvable),

  /// `station_suspended`, ou une politique qui refuse l'écriture : la caserne
  /// est en lecture seule.
  lectureSeule(AppStrings.lectureSeuleDetail),

  /// `23505` sur `assignments_active_uniq` : ce membre est déjà attribué à ce
  /// créneau. Ce n'est pas une panne, c'est l'autre administrateur.
  dejaAttribue(AppStrings.planningDejaAttribue),

  /// Le planning n'est plus en brouillon : la suppression d'une attribution
  /// publiée est filtrée par la politique, sans lever.
  planningPublie(AppStrings.planningPublieDetail),

  reseau(AppStrings.erreurReseauTexte),

  inconnue(AppStrings.planningErreurTexte);

  const ErreurPlanning(this.message);

  final String message;
}

/// Un accès au planning refusé, avec sa phrase déjà en français.
class EchecPlanning implements Exception {
  const EchecPlanning(this.erreur);

  final ErreurPlanning erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecPlanning(${erreur.name})';
}

/// Ce que le canal temps réel des attributions annonce.
///
/// Trois événements et pas un de plus. **La suppression ne porte qu'un
/// identifiant** : l'identité de réplique d'`assignments` est restée
/// `default`, et la charge utile d'un `delete` n'est de toute façon pas
/// filtrée par les politiques (`design/017 § 7.2`).
sealed class EvenementPlanning {
  const EvenementPlanning();
}

/// Une attribution posée ou modifiée ailleurs.
final class AttributionRecue extends EvenementPlanning {
  const AttributionRecue(this.attribution);

  final Attribution attribution;
}

/// Une attribution supprimée ailleurs. Seule la clé primaire est diffusée.
final class AttributionSupprimee extends EvenementPlanning {
  const AttributionSupprimee(this.id);

  final String id;
}

/// L'état du canal. Un écran collaboratif qui perd son abonnement en silence
/// est un écran qui ment : l'état est affiché, à côté de « Rafraîchir ».
final class EtatCanalPlanning extends EvenementPlanning {
  const EtatCanalPlanning({required this.branche});

  final bool branche;
}

/// Tout ce que l'écran « Planning du mois » sait faire des créneaux et des
/// attributions.
abstract interface class PlanningRepository {
  /// Le planning d'un mois, ses créneaux et ses attributions actives.
  /// Rend un [PlanningMois] **vide** — et non une erreur — quand le planning
  /// n'a pas encore été créé : c'est l'état normal d'un mois qui commence.
  Future<PlanningMois> lire({
    required String stationId,
    required String periodeId,
  });

  /// Crée le planning du mois et ses créneaux. Idempotente côté base : deux
  /// adjoints qui cliquent en même temps obtiennent le même planning.
  Future<PlanningMois> creer({
    required String stationId,
    required String periodeId,
  });

  /// Attribue un membre à un créneau.
  ///
  /// N'envoie **ni `was_available` ni `created_by`** : la base les pose
  /// elle-même (`assignments_trace_disponibilite`, migration 0018). Lève
  /// [ErreurPlanning.dejaAttribue] si la contrainte d'unicité refuse.
  Future<Attribution> attribuer({
    required String stationId,
    required String creneauId,
    required String userId,
  });

  /// Retire une attribution. Rend `false` si la base n'a supprimé aucune
  /// ligne : la politique **filtre sans lever**, et un planning publié répond
  /// « 0 ligne, tout va bien ».
  Future<bool> retirer({required String attributionId});

  /// Change l'effectif requis d'un **seul** créneau. Rend `false` si la base
  /// n'a modifié aucune ligne.
  Future<bool> definirEffectif({
    required String creneauId,
    required int effectif,
  });

  /// Le canal temps réel des attributions de la caserne.
  Stream<EvenementPlanning> ecouter({required String stationId});
}

/// Implémentation Supabase.
class SupabasePlanningRepository implements PlanningRepository {
  const SupabasePlanningRepository(this._client);

  final SupabaseClient _client;

  /// Les seules attributions qui comptent pour la couverture. Les autres
  /// (`declined`, `replaced`, `cancelled`) restent en base pour l'historique
  /// et n'occupent aucune place (`docs/SCHEMA.md § 2.10`).
  static const List<String> _statutsActifs = <String>['proposed', 'accepted'];

  @override
  Future<PlanningMois> lire({
    required String stationId,
    required String periodeId,
  }) async {
    try {
      final planning = await _client
          .from('schedules')
          .select(PlanningBrouillon.colonnes)
          .eq('station_id', stationId)
          .eq('period_id', periodeId)
          .maybeSingle();

      // Pas de planning : un mois qui commence, pas une erreur.
      if (planning == null) return PlanningMois.vide();

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

      final attributions = ids.isEmpty
          ? const <Map<String, dynamic>>[]
          : await _client
                .from('assignments')
                .select(Attribution.colonnes)
                .eq('station_id', stationId)
                .inFilter('shift_id', ids)
                .inFilter('status', _statutsActifs);

      return PlanningMois(
        planning: entete,
        creneaux: <CreneauPlanning>[
          for (final ligne in creneaux) CreneauPlanning.depuisJson(ligne),
        ],
        attributions: <Attribution>[
          for (final ligne in attributions) Attribution.depuisJson(ligne),
        ],
      );
    } on Object catch (echec) {
      throw EchecPlanning(_traduire(echec));
    }
  }

  @override
  Future<PlanningMois> creer({
    required String stationId,
    required String periodeId,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'create_schedule',
        params: <String, dynamic>{
          'p_station': stationId,
          'p_period': periodeId,
        },
      );
    } on Object catch (echec) {
      throw EchecPlanning(_traduire(echec));
    }

    // La fonction rend la ligne `schedules` ; les créneaux, eux, se relisent.
    // Une seconde lecture complète vaut mieux qu'une reconstruction de
    // soixante-deux créneaux à partir de ce que le client croit savoir.
    return lire(stationId: stationId, periodeId: periodeId);
  }

  @override
  Future<Attribution> attribuer({
    required String stationId,
    required String creneauId,
    required String userId,
  }) async {
    try {
      final ligne = await _client
          .from('assignments')
          .insert(<String, dynamic>{
            'station_id': stationId,
            'shift_id': creneauId,
            'user_id': userId,
          })
          .select(Attribution.colonnes)
          .single();

      return Attribution.depuisJson(ligne);
    } on Object catch (echec) {
      throw EchecPlanning(_traduire(echec));
    }
  }

  @override
  Future<bool> retirer({required String attributionId}) async {
    try {
      final rendues = await _client
          .from('assignments')
          .delete()
          .eq('id', attributionId)
          .select('id');

      return rendues.isNotEmpty;
    } on Object catch (echec) {
      throw EchecPlanning(_traduire(echec));
    }
  }

  @override
  Future<bool> definirEffectif({
    required String creneauId,
    required int effectif,
  }) async {
    try {
      final rendues = await _client
          .from('shifts')
          .update(<String, dynamic>{'required_count': effectif})
          .eq('id', creneauId)
          .select('id');

      return rendues.isNotEmpty;
    } on Object catch (echec) {
      throw EchecPlanning(_traduire(echec));
    }
  }

  /// Le canal des attributions.
  ///
  /// **Aucun filtre de colonne côté serveur, et c'est voulu.** Un filtre
  /// `station_id=eq.…` ne s'évalue que sur les colonnes diffusées ; pour un
  /// `delete`, la charge utile se réduit à la clé primaire et l'événement
  /// serait écarté. Or c'est précisément l'événement qui compte ici : en
  /// brouillon, retirer une attribution **est** une suppression. Le tri se
  /// fait donc côté client, comme `docs/SCHEMA.md § 9` l'écrit, et il ne coûte
  /// rien : les politiques de `select` ont déjà réduit les insertions et les
  /// modifications reçues aux lignes de la caserne, et un identifiant de
  /// suppression inconnu ne correspond à aucun créneau à l'écran.
  @override
  Stream<EvenementPlanning> ecouter({required String stationId}) {
    final controleur = StreamController<EvenementPlanning>();
    final canal = _client.channel('attributions:$stationId');

    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'assignments',
          callback: (PostgresChangePayload charge) {
            final evenement = _evenement(charge);
            if (evenement != null && !controleur.isClosed) {
              controleur.add(evenement);
            }
          },
        )
        .subscribe((RealtimeSubscribeStatus statut, Object? _) {
          if (controleur.isClosed) return;
          controleur.add(
            EtatCanalPlanning(
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

  static EvenementPlanning? _evenement(PostgresChangePayload charge) {
    switch (charge.eventType) {
      case PostgresChangeEvent.delete:
        final id = charge.oldRecord['id'] as String?;
        return id == null ? null : AttributionSupprimee(id);
      case PostgresChangeEvent.insert:
      case PostgresChangeEvent.update:
        final ligne = charge.newRecord;
        if (ligne['id'] == null || ligne['shift_id'] == null) return null;
        // Un statut qui sort de l'actif libère la place : l'attribution
        // disparaît de l'écran comme si elle avait été supprimée.
        final statut = ligne['status'] as String?;
        if (statut != null && !_statutsActifs.contains(statut)) {
          return AttributionSupprimee(ligne['id']! as String);
        }
        return AttributionRecue(Attribution.depuisJson(ligne));
      case PostgresChangeEvent.all:
        return null;
    }
  }

  /// Traduit ce que le SDK a levé.
  static ErreurPlanning _traduire(Object echec) {
    if (echec is EchecPlanning) return echec.erreur;
    if (echec is PostgrestException) {
      final message = echec.message.toLowerCase();
      // `23505` sur `assignments_active_uniq` : le seul doublon possible ici.
      if (echec.code == '23505') return ErreurPlanning.dejaAttribue;
      if (message.contains('forbidden')) return ErreurPlanning.reserveAdmin;
      if (message.contains('period_not_found')) {
        return ErreurPlanning.moisIntrouvable;
      }
      if (message.contains('station_suspended') || echec.code == '42501') {
        return ErreurPlanning.lectureSeule;
      }
      // Un code absent signale une réponse qui n'est jamais arrivée.
      if (echec.code == null) return ErreurPlanning.reseau;
      return ErreurPlanning.inconnue;
    }
    if (echec is AuthException) return ErreurPlanning.inconnue;
    return ErreurPlanning.reseau;
  }
}
