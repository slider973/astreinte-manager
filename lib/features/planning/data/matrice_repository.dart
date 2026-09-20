import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/format_date.dart';
import '../../../core/supabase/enums.dart';
import '../../../core/theme/app_status.dart';
import '../domain/ligne_matrice.dart';

/// Pourquoi une lecture ou une écriture de la matrice a échoué.
enum ErreurMatrice {
  /// `availability_matrix` a levé `forbidden` : l'appelant n'administre pas
  /// cette caserne. La route est déjà fermée par `redirectionAuth` ; le cas
  /// est traité quand même.
  reserveAdmin(AppStrings.matriceReserveAdmin),

  /// `period_not_found` : l'URL porte un mois qui n'existe plus, ou qui
  /// n'appartient pas à cette caserne.
  moisIntrouvable(AppStrings.matriceMoisIntrouvable),

  /// La RLS a refusé l'écriture. Pour un admin, la seule cause possible est
  /// une caserne devenue non modifiable : le verrouillage d'un mois, lui, ne
  /// le concerne pas (PRD § 6.3).
  lectureSeule(AppStrings.lectureSeuleDetail),

  /// Réseau tombé, serveur injoignable.
  reseau(AppStrings.erreurReseauTexte),

  inconnue(AppStrings.matriceErreurTexte);

  const ErreurMatrice(this.message);

  final String message;
}

/// Un accès à la matrice refusé, avec sa phrase déjà en français.
class EchecMatrice implements Exception {
  const EchecMatrice(this.erreur);

  final ErreurMatrice erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecMatrice(${erreur.name})';
}

/// Tout ce que l'écran « Planning du mois » sait faire de la base.
///
/// **Une seule lecture pour tout le mois** : `availability_matrix` rend une
/// ligne par membre actif, le mois encodé en deux chaînes. Les filtres, le
/// tri, la recherche et le compte de couverture se dérivent de ces lignes,
/// sans un seul aller-retour de plus.
///
/// **L'écriture n'est pas une RPC** : c'est l'`upsert` habituel sur
/// `availabilities`, que les politiques `availabilities_*_admin` autorisent
/// déjà. `set_by` n'est **jamais** envoyé — le déclencheur
/// `availabilities_trace_auteur` (migration 0012) le pose lui-même, et c'est
/// lui qui fait que la saisie par procuration se relit en minuscule.
abstract interface class MatriceRepository {
  /// La matrice d'un mois. Lève [EchecMatrice] pour un non-admin
  /// ([ErreurMatrice.reserveAdmin]) ou une période inconnue
  /// ([ErreurMatrice.moisIntrouvable]).
  Future<List<LigneMatrice>> matrice({
    required String stationId,
    required String periodeId,
  });

  /// Écrit une case à la place d'un membre. Rend `false` si la base n'a
  /// accepté aucune ligne : la clause `using` d'une politique **filtre sans
  /// lever**, et un refus répond « 0 ligne, tout va bien »
  /// (`supabase/README.md`).
  Future<bool> ecrire({
    required String stationId,
    required String userId,
    required DateTime jour,
    required CreneauType creneau,
    required DisponibiliteEtat etat,
  });

  /// Efface une case : « non saisi » n'a pas de valeur SQL, l'absence de
  /// ligne **est** le non-saisi.
  Future<bool> effacer({
    required String stationId,
    required String userId,
    required DateTime jour,
    required CreneauType creneau,
  });
}

/// Implémentation Supabase.
class SupabaseMatriceRepository implements MatriceRepository {
  const SupabaseMatriceRepository(this._client);

  final SupabaseClient _client;

  /// Les colonnes relues après écriture. `set_by` n'y est pas : l'écran ne le
  /// lit pas plus qu'il ne l'écrit, la matrice le lui dit déjà.
  static const String _colonnesDispo = 'date, slot, status';

  @override
  Future<List<LigneMatrice>> matrice({
    required String stationId,
    required String periodeId,
  }) async {
    try {
      final lignes = await _client.rpc<List<dynamic>>(
        'availability_matrix',
        params: <String, dynamic>{
          'p_station': stationId,
          'p_period': periodeId,
        },
      );

      return <LigneMatrice>[
        for (final ligne in lignes)
          LigneMatrice.depuisJson(ligne as Map<String, dynamic>),
      ];
    } on Object catch (echec) {
      throw EchecMatrice(_traduire(echec));
    }
  }

  @override
  Future<bool> ecrire({
    required String stationId,
    required String userId,
    required DateTime jour,
    required CreneauType creneau,
    required DisponibiliteEtat etat,
  }) async {
    try {
      final rendues = await _client
          .from('availabilities')
          .upsert(<String, dynamic>{
            'station_id': stationId,
            'user_id': userId,
            'date': isoJour(jour),
            'slot': creneau.valeurSql,
            'status': etat.valeurSql,
          }, onConflict: 'station_id,user_id,date,slot')
          .select(_colonnesDispo);

      return rendues.isNotEmpty;
    } on Object catch (echec) {
      throw EchecMatrice(_traduire(echec));
    }
  }

  @override
  Future<bool> effacer({
    required String stationId,
    required String userId,
    required DateTime jour,
    required CreneauType creneau,
  }) async {
    try {
      await _client
          .from('availabilities')
          .delete()
          .eq('station_id', stationId)
          .eq('user_id', userId)
          .eq('date', isoJour(jour))
          .eq('slot', creneau.valeurSql);

      // **Zéro ligne n'est pas un refus ici** : une case déjà vide ne
      // supprime rien non plus. Le compte ne distingue pas les deux cas, on
      // ne s'en sert donc pas — un refus, lui, lève.
      return true;
    } on Object catch (echec) {
      throw EchecMatrice(_traduire(echec));
    }
  }

  /// Traduit ce que le SDK a levé.
  ///
  /// `raise exception 'forbidden'` remonte en `P0001` avec le message de
  /// l'exception : c'est le message qui identifie le refus, pas le code.
  static ErreurMatrice _traduire(Object echec) {
    if (echec is EchecMatrice) return echec.erreur;
    if (echec is PostgrestException) {
      final message = echec.message.toLowerCase();
      if (message.contains('forbidden')) return ErreurMatrice.reserveAdmin;
      if (message.contains('period_not_found')) {
        return ErreurMatrice.moisIntrouvable;
      }
      // 42501 : `new row violates row-level security policy`. Sur cette table
      // et pour un admin, la seule cause est une caserne non modifiable.
      if (echec.code == '42501') return ErreurMatrice.lectureSeule;
      // Un code absent signale une réponse qui n'est jamais arrivée.
      if (echec.code == null) return ErreurMatrice.reseau;
      return ErreurMatrice.inconnue;
    }
    if (echec is AuthException) return ErreurMatrice.inconnue;
    // `ClientException`, `SocketException`, `TimeoutException` : le réseau.
    return ErreurMatrice.reseau;
  }
}
