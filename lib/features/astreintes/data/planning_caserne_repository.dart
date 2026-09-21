import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/supabase/enums.dart';
import '../../planning/domain/suivi_planning.dart';
import '../domain/planning_caserne.dart';
import 'astreintes_repository.dart';

/// Pourquoi la lecture du planning de la caserne n'a pas abouti.
///
/// Deux motifs, comme pour « Mes astreintes » et pour la même raison : il n'y a
/// que deux sorties, réessayer maintenant ou réessayer plus tard. Cet écran
/// **n'écrit rien**.
enum ErreurPlanningCaserne {
  reseau(AppStrings.erreurReseauTexte),

  inconnue(AppStrings.planningCaserneErreurTexte);

  const ErreurPlanningCaserne(this.message);

  final String message;
}

/// Une lecture qui n'a pas abouti, avec sa phrase déjà en français.
class EchecPlanningCaserne implements Exception {
  const EchecPlanningCaserne(this.erreur);

  final ErreurPlanningCaserne erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecPlanningCaserne(${erreur.name})';
}

/// Tout ce que la vue « La caserne » sait faire.
abstract interface class PlanningCaserneRepository {
  /// Les mois atteignables : les plannings `published`, `validated` et
  /// `archived` de la caserne, dans l'ordre du calendrier
  /// ([MoisPlanning.etatsLisibles]).
  Future<List<MoisPlanning>> moisLisibles({required String stationId});

  /// Le planning d'un mois, tel que ce membre a le droit de le lire.
  ///
  /// Rend `null` quand le planning n'a plus de créneau lisible : il a été
  /// supprimé, ou remis en brouillon, entre la lecture de la liste des mois et
  /// celle-ci. Ce n'est pas une erreur, c'est un mois qui n'existe plus.
  ///
  /// **L'archivage n'est pas un de ces cas depuis le ticket 044** : un mois
  /// archivé rend ses créneaux comme un mois publié
  /// (`shifts_select_member_published`, migration `0031`).
  Future<PlanningCaserne?> lireMois({
    required String stationId,
    required String userId,
    required MoisPlanning mois,
  });
}

/// Implémentation Supabase.
///
/// **Le contrat de coût est dans l'implémentation** : une requête pour la liste
/// des mois, et au plus quatre par mois affiché — trois quand personne n'est
/// attribué (`design/023 § 7`).
class SupabasePlanningCaserneRepository implements PlanningCaserneRepository {
  const SupabasePlanningCaserneRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<MoisPlanning>> moisLisibles({required String stationId}) async {
    try {
      final lignes = await _client
          .from('schedules')
          .select(MoisPlanning.colonnes)
          .eq('station_id', stationId)
          .inFilter('status', MoisPlanning.etatsLisibles);

      final mois = <MoisPlanning>[
        for (final ligne in lignes)
          if (MoisPlanning.depuisJson(ligne) case final MoisPlanning lu) lu,
      ]..sort((MoisPlanning a, MoisPlanning b) => a.comparer(b));

      return List<MoisPlanning>.unmodifiable(mois);
    } on Object catch (echec) {
      throw EchecPlanningCaserne(_traduire(echec));
    }
  }

  @override
  Future<PlanningCaserne?> lireMois({
    required String stationId,
    required String userId,
    required MoisPlanning mois,
  }) async {
    try {
      // 1. L'ossature du mois : soixante-deux créneaux, quatre colonnes.
      // Lisible dès que le planning est publié, et **toujours une fois
      // archivé** (`shifts_select_member_published`, migration `0031`) : un
      // mois passé garde sa grille, c'est ce qui en fait un tableau de garde.
      final lignes = await _client
          .from('shifts')
          .select(CreneauCaserne.colonnes)
          .eq('schedule_id', mois.planningId);
      if (lignes.isEmpty) return null;

      // 2. Les attributions acceptées. **C'est ici que la RLS tranche, et
      // nulle part ailleurs** : publié, elle ne rend que celles du lecteur ;
      // validé ou archivé, elle rend celles de toute la caserne
      // (`assignments_select_station_validated`,
      // `assignments_select_station_archived`). Aucun filtre sur `user_id`
      // n'est ajouté selon l'état du planning — le client n'a pas à deviner un
      // droit qu'il ne détient pas.
      //
      // La jointure interne sur `shifts` remplace une liste de soixante-deux
      // identifiants dans l'URL.
      final attributions = await _client
          .from('assignments')
          .select('id, user_id, shift_id, shifts!inner(schedule_id)')
          .eq('station_id', stationId)
          .eq('status', 'accepted')
          .eq('shifts.schedule_id', mois.planningId);

      final parCreneau = <String, List<String>>{};
      final miens = <String>{};
      final aNommer = <String>{};
      for (final ligne in attributions) {
        final creneauId = ligne['shift_id'] as String?;
        final membre = ligne['user_id'] as String?;
        if (creneauId == null || membre == null) continue;
        if (membre == userId) {
          miens.add(creneauId);
          continue;
        }
        aNommer.add(membre);
        (parCreneau[creneauId] ??= <String>[]).add(membre);
      }

      final noms = await _noms(stationId: stationId, membres: aNommer);
      final heures = await lireHeuresAffichage(_client, stationId);

      final parJour = <DateTime, List<CreneauCaserne>>{};
      for (final ligne in lignes) {
        final id = ligne['id'] as String?;
        final date = ligne['date'] as String?;
        final slot = ligne['slot'] as String?;
        if (id == null || date == null || slot == null) continue;

        final membres = parCreneau[id] ?? const <String>[];
        final nommes = <String>[
          for (final membre in membres)
            if ((noms[membre] ?? '').isNotEmpty) noms[membre]!,
        ]..sort();

        (parJour[depuisIsoJour(date)] ??= <CreneauCaserne>[]).add(
          CreneauCaserne(
            id: id,
            creneau: CreneauSql.depuisSql(slot),
            requis: (ligne['required_count'] as int?) ?? 0,
            noms: nommes,
            moi: miens.contains(id),
            anonymes: membres.length - nommes.length,
          ),
        );
      }

      return PlanningCaserne(
        mois: mois,
        journees: assemblerJournees(etat: mois.etat, parJour: parJour),
        heures: heures,
        luLe: DateTime.now(),
      );
    } on Object catch (echec) {
      throw EchecPlanningCaserne(_traduire(echec));
    }
  }

  /// Les noms d'usage de la caserne, par identifiant de membre.
  ///
  /// **Le nom d'usage vit dans `memberships`, pas dans `profiles`**
  /// (`docs/SCHEMA.md § 2.3`) : aucune jointure depuis `assignments` ne peut le
  /// rapporter. Une lecture de la caserne — soixante lignes — le donne pour
  /// tout le monde. C'est la requête des tickets 019 et 027, à l'identique, et
  /// elle est **sautée** quand il n'y a personne à nommer.
  Future<Map<String, String>> _noms({
    required String stationId,
    required Set<String> membres,
  }) async {
    if (membres.isEmpty) return const <String, String>{};

    final lignes = await _client
        .from('memberships')
        .select(AttributionSuivi.colonnesMembre)
        .eq('station_id', stationId);

    return <String, String>{
      for (final ligne in lignes)
        ligne['user_id']! as String: AttributionSuivi.nomDeMembre(ligne),
    };
  }

  static ErreurPlanningCaserne _traduire(Object echec) {
    if (echec is EchecPlanningCaserne) return echec.erreur;
    return echecDeTransport(echec)
        ? ErreurPlanningCaserne.reseau
        : ErreurPlanningCaserne.inconnue;
  }
}
