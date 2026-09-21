import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../parametres/domain/parametres_caserne.dart';
import '../../planning/domain/suivi_planning.dart';
import '../domain/astreinte.dart';

/// Pourquoi la lecture de « Mes astreintes » n'a pas abouti.
///
/// Deux motifs, parce qu'il n'y a que deux sorties : réessayer maintenant, ou
/// réessayer plus tard. Cet écran **n'écrit rien**, donc ni caserne suspendue
/// ni droit refusé n'ont de phrase à eux ici.
enum ErreurAstreintes {
  reseau(AppStrings.erreurReseauTexte),

  inconnue(AppStrings.astreintesErreurTexte);

  const ErreurAstreintes(this.message);

  final String message;
}

/// Une lecture qui n'a pas abouti, avec sa phrase déjà en français.
class EchecAstreintes implements Exception {
  const EchecAstreintes(this.erreur);

  final ErreurAstreintes erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecAstreintes(${erreur.name})';
}

/// Vrai quand l'échec est un **défaut de transport** : la requête n'est jamais
/// partie, ou la réponse n'est jamais arrivée.
///
/// Partagé par les deux dépôts de cette fonctionnalité, qui lisent les mêmes
/// tables sous les mêmes politiques et n'ont donc aucune raison de classer
/// leurs pannes différemment. Un `PostgrestException` **sans code** est le
/// signal d'une réponse absente ; avec un code, la base a répondu, et l'écran
/// n'a pas à promettre qu'un simple « Réessayer » suffira.
bool echecDeTransport(Object echec) {
  if (echec is PostgrestException) return echec.code == null;
  if (echec is AuthException) return false;
  return true;
}

/// Les heures d'affichage d'une caserne.
///
/// La lecture passe par [ParametresCaserne], seul lecteur légitime du document
/// `settings` : un second lecteur des mêmes clés divergerait du premier au
/// premier réglage ajouté. Hors de toute classe parce que les deux dépôts de
/// cette fonctionnalité en ont besoin, et qu'une seconde copie divergerait
/// pour la même raison.
Future<HeuresAffichage> lireHeuresAffichage(
  SupabaseClient client,
  String stationId,
) async {
  final ligne = await client
      .from('stations')
      .select('id, name, timezone, settings')
      .eq('id', stationId)
      .maybeSingle();
  if (ligne == null) return HeuresAffichage.defaut;

  final parametres = ParametresCaserne.depuisJson(ligne);
  return HeuresAffichage(
    debutJour: parametres.debutJour,
    finJour: parametres.finJour,
  );
}

/// Tout ce que l'écran « Mes astreintes » sait faire.
abstract interface class AstreintesRepository {
  /// Les astreintes **acceptées** de ce membre, ses équipiers quand le
  /// planning est validé, et les heures d'affichage de la caserne.
  ///
  /// [depuis] borne la lecture côté serveur : l'historique n'est jamais
  /// supprimé (`docs/PRD.md § 7.6`), mais il n'a pas à être téléchargé à
  /// chaque ouverture.
  Future<MesAstreintes> lire({
    required String userId,
    required String stationId,
    required DateTime depuis,
  });
}

/// Implémentation Supabase.
///
/// **Le contrat de coût est dans l'implémentation** : au plus quatre requêtes,
/// et seulement deux quand le membre n'a aucune astreinte
/// (`design/027 § 8.1`).
class SupabaseAstreintesRepository implements AstreintesRepository {
  const SupabaseAstreintesRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<MesAstreintes> lire({
    required String userId,
    required String stationId,
    required DateTime depuis,
  }) async {
    try {
      final heures = await lireHeuresAffichage(_client, stationId);

      // **La borne porte sur `shifts.date`, pas sur `assignments`.**
      // `assignments` ne connaît que `proposed_at`, qui est la date de la
      // publication et non celle de la garde : borner dessus couperait un
      // planning publié tôt pour un mois lointain.
      final lignes = await _client
          .from('assignments')
          .select(Astreinte.colonnes)
          .eq('user_id', userId)
          .eq('station_id', stationId)
          .eq('status', 'accepted')
          .gte('shifts.date', isoJour(depuis));

      final miennes = <Astreinte>[
        for (final ligne in lignes)
          if (Astreinte.depuisJson(ligne) case final Astreinte astreinte)
            astreinte,
      ];
      if (miennes.isEmpty) {
        return MesAstreintes(heures: heures, luLe: DateTime.now().toUtc());
      }

      final equipiers = await _equipiers(
        stationId: stationId,
        userId: userId,
        astreintes: miennes,
      );

      return MesAstreintes(
        astreintes: <Astreinte>[
          for (final astreinte in miennes)
            astreinte.avecEquipiers(
              equipiers[astreinte.creneauId] ?? const <String>[],
            ),
        ],
        heures: heures,
        luLe: DateTime.now().toUtc(),
      );
    } on Object catch (echec) {
      throw EchecAstreintes(_traduire(echec));
    }
  }

  /// Les autres membres acceptés, par identifiant de créneau.
  ///
  /// **La RLS fait le tri** : `assignments_select_station_validated` n'ouvre
  /// les attributions des autres que sur un planning `validated`. La liste des
  /// créneaux interrogés est néanmoins réduite aux plannings validés — seconde
  /// ceinture, sur une donnée qui, montrée trop tôt, ferait croire à un
  /// planning figé (`design/027 § 8.1`).
  Future<Map<String, List<String>>> _equipiers({
    required String stationId,
    required String userId,
    required List<Astreinte> astreintes,
  }) async {
    final creneaux = <String>{
      for (final astreinte in astreintes)
        if (astreinte.equipiersConnus) astreinte.creneauId,
    };
    if (creneaux.isEmpty) return const <String, List<String>>{};

    final lignes = await _client
        .from('assignments')
        .select('shift_id, user_id, status')
        .eq('station_id', stationId)
        .eq('status', 'accepted')
        .inFilter('shift_id', creneaux.toList(growable: false));

    final autres = <String, List<String>>{};
    final aNommer = <String>{};
    for (final ligne in lignes) {
      final creneauId = ligne['shift_id'] as String?;
      final membre = ligne['user_id'] as String?;
      if (creneauId == null || membre == null || membre == userId) continue;
      aNommer.add(membre);
      (autres[creneauId] ??= <String>[]).add(membre);
    }
    if (aNommer.isEmpty) return const <String, List<String>>{};

    // **Le nom d'usage vit dans `memberships`, pas dans `profiles`**
    // (`docs/SCHEMA.md § 2.3`) : une jointure depuis `assignments` ne peut pas
    // le rapporter. Une lecture de la caserne — soixante lignes — le donne
    // pour tout le monde. C'est la requête du ticket 019, à l'identique.
    final membres = await _client
        .from('memberships')
        .select(AttributionSuivi.colonnesMembre)
        .eq('station_id', stationId);

    final noms = <String, String>{
      for (final ligne in membres)
        ligne['user_id']! as String: AttributionSuivi.nomDeMembre(ligne),
    };

    return <String, List<String>>{
      for (final entree in autres.entries)
        entree.key:
            <String>[
                for (final membre in entree.value)
                  if ((noms[membre] ?? '').isNotEmpty) noms[membre]!,
              ]
              // L'ordre alphabétique : il n'y a pas d'autre ordre juste entre
              // deux personnes du même créneau, et un ordre stable évite qu'une
              // liste se réordonne d'une lecture à l'autre.
              ..sort(),
    };
  }

  static ErreurAstreintes _traduire(Object echec) {
    if (echec is EchecAstreintes) return echec.erreur;
    return echecDeTransport(echec)
        ? ErreurAstreintes.reseau
        : ErreurAstreintes.inconnue;
  }
}
