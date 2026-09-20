import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/supabase/enums.dart';
import '../../../core/theme/app_status.dart';
import '../domain/proposition.dart';

/// Pourquoi une lecture ou une réponse n'a pas abouti.
enum ErreurProposition {
  /// La caserne est suspendue, ou une politique refuse l'écriture.
  lectureSeule(AppStrings.lectureSeuleDetail),

  reseau(AppStrings.erreurReseauTexte),

  inconnue(AppStrings.propositionsErreurTexte);

  const ErreurProposition(this.message);

  final String message;

  static ErreurProposition depuisCode(String? code) => switch (code) {
    'station_suspended' => ErreurProposition.lectureSeule,
    _ => ErreurProposition.inconnue,
  };
}

/// Un accès refusé, avec sa phrase déjà en français.
class EchecProposition implements Exception {
  const EchecProposition(this.erreur);

  final ErreurProposition erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecProposition(${erreur.name})';
}

/// Ce que la base répond à une réponse envoyée.
enum ResultatReponse {
  /// La ligne a changé de statut. Un seul cas heureux.
  enregistree,

  /// **Zéro ligne touchée.** L'attribution n'est plus `proposed` : le chef de
  /// centre l'a annulée, l'a confiée à quelqu'un d'autre (ticket 020), ou la
  /// réponse est déjà partie depuis un autre appareil. Ce n'est pas une
  /// panne, c'est une nouvelle (`design/021 § 7.1`).
  disparue,
}

/// Tout ce que l'écran des propositions sait faire.
///
/// **Le contrat de coût est dans l'interface** : [lister] vaut exactement une
/// requête PostgREST, [repondre] exactement une, et [etatPlanning] lit une
/// seule colonne d'une seule ligne.
abstract interface class PropositionsRepository {
  /// Les astreintes proposées à ce membre et sans réponse.
  ///
  /// Ne rend que des lignes `proposed` dont `proposed_at` n'est pas nul : une
  /// attribution de brouillon n'a rien demandé à personne
  /// (`docs/WORKFLOWS.md § 3`). Un planning encore en brouillon ne renvoie de
  /// toute façon rien du tout — la RLS s'en charge, et c'est voulu.
  Future<List<Proposition>> lister({
    required String userId,
    required String stationId,
  });

  /// Répond à une proposition.
  ///
  /// **La charge utile porte `status`, et au refus `decline_reason`. Rien
  /// d'autre, jamais** : `assignments_member_transition` compare l'avant et
  /// l'après en dehors d'une liste blanche de quatre colonnes, et une seule
  /// colonne de trop fait échouer la requête entière (`docs/SCHEMA.md § 4`).
  /// `responded_at` est posé par la base : l'envoyer serait envoyer l'heure du
  /// téléphone.
  ///
  /// [motif] est ignoré à l'acceptation : un motif n'existe que pour un refus.
  Future<ResultatReponse> repondre({
    required String attributionId,
    required bool accepte,
    String? motif,
  });

  /// L'état d'un planning, relu après une acceptation qui pourrait avoir été
  /// la dernière. Une colonne, une ligne (`design/021 § 7.4`).
  Future<PlanningEtat?> etatPlanning(String planningId);
}

/// Implémentation Supabase.
class SupabasePropositionsRepository implements PropositionsRepository {
  const SupabasePropositionsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Proposition>> lister({
    required String userId,
    required String stationId,
  }) async {
    try {
      final lignes = await _client
          .from('assignments')
          .select(Proposition.colonnes)
          .eq('user_id', userId)
          .eq('station_id', stationId)
          .eq('status', 'proposed')
          // `proposed_at is null` **est** le brouillon. La RLS l'exclut déjà
          // en masquant les plannings `draft` ; ce filtre est la seconde
          // ceinture, sur une donnée qui, affichée par erreur, ferait répondre
          // un pompier à un planning que son chef est en train d'écrire.
          .not('proposed_at', 'is', null);

      // Le tri est fait en Dart : soixante-deux lignes au pire, et ordonner
      // par une colonne de table jointe côté PostgREST échangerait une
      // comparaison contre une syntaxe fragile.
      return <Proposition>[
        for (final ligne in lignes)
          if (Proposition.depuisJson(ligne) case final Proposition proposition)
            proposition,
      ]..sort((Proposition a, Proposition b) => a.comparer(b));
    } on Object catch (echec) {
      throw EchecProposition(_traduire(echec));
    }
  }

  @override
  Future<ResultatReponse> repondre({
    required String attributionId,
    required bool accepte,
    String? motif,
  }) async {
    // **La charge minimale, construite à la main.** Pas de `toJson()`, pas de
    // `copyWith` sérialisé : deux clés au maximum, et on peut les compter.
    final charge = <String, dynamic>{
      'status': accepte ? 'accepted' : 'declined',
    };
    final propre = motif?.trim();
    if (!accepte && propre != null && propre.isNotEmpty) {
      charge['decline_reason'] = propre;
    }

    try {
      final lignes = await _client
          .from('assignments')
          .update(charge)
          .eq('id', attributionId)
          // **La condition qui fait tout le travail.** Sans elle, une
          // attribution déjà annulée déclencherait `invalid transition` et
          // l'écran verrait une panne là où il y a une nouvelle. Avec elle,
          // zéro ligne touchée est la réponse propre du cas « plus proposée ».
          .eq('status', 'proposed')
          .select('id');

      return lignes.isEmpty
          ? ResultatReponse.disparue
          : ResultatReponse.enregistree;
    } on Object catch (echec) {
      throw EchecProposition(_traduire(echec));
    }
  }

  @override
  Future<PlanningEtat?> etatPlanning(String planningId) async {
    try {
      final ligne = await _client
          .from('schedules')
          .select('status')
          .eq('id', planningId)
          .maybeSingle();
      if (ligne == null) return null;
      return PlanningSql.depuisSql(ligne['status'] as String?);
    } on Object catch (_) {
      // Un état de planning est un **confort** : son échec ne doit pas
      // transformer une acceptation réussie en écran d'erreur.
      return null;
    }
  }

  static ErreurProposition _traduire(Object echec) {
    if (echec is EchecProposition) return echec.erreur;
    if (echec is PostgrestException) {
      final message = echec.message.toLowerCase();
      if (message.contains('station_suspended') || echec.code == '42501') {
        return ErreurProposition.lectureSeule;
      }
      // Un code absent signale une réponse qui n'est jamais arrivée.
      if (echec.code == null) return ErreurProposition.reseau;
      return ErreurProposition.depuisCode(echec.code);
    }
    if (echec is AuthException) return ErreurProposition.inconnue;
    return ErreurProposition.reseau;
  }
}
