import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/supabase/enums.dart';
import '../../../core/theme/app_status.dart';
import '../domain/creneau_cle.dart';
import '../domain/periode_saisie.dart';

/// Pourquoi une lecture ou une écriture de disponibilités a échoué.
enum ErreurDispos {
  /// La période s'est verrouillée, ou la caserne est passée en lecture seule,
  /// pendant que l'écran était ouvert. La RLS refuse.
  verrouille(AppStrings.moisErreurVerrouilleEnCours),

  /// La caserne n'est plus modifiable : abonnement suspendu.
  lectureSeule(AppStrings.moisErreurSuspendueEnCours),

  /// Réseau tombé, serveur injoignable. **Ce n'est pas un échec de saisie** :
  /// l'écran garde sa file et la rejoue au retour du réseau.
  reseau(AppStrings.horsLigneDetail),

  /// Tout le reste.
  inconnue(AppStrings.moisErreurEnregistrementBanniere);

  const ErreurDispos(this.message);

  final String message;

  /// Vrai quand le serveur a **refusé** : il n'y a rien à rejouer, il faut
  /// recharger l'écran pour prendre son nouvel état.
  bool get estRefus =>
      this == ErreurDispos.verrouille || this == ErreurDispos.lectureSeule;
}

/// Un accès aux disponibilités refusé, avec sa phrase déjà en français.
class EchecDispos implements Exception {
  const EchecDispos(this.erreur);

  final ErreurDispos erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecDispos(${erreur.name})';
}

/// Une ligne de `availabilities` prête à partir.
class LigneDisponibilite {
  const LigneDisponibilite({required this.cle, required this.etat});

  final CreneauCle cle;

  /// Jamais [DisponibiliteEtat.nonSaisi] : celui-là se supprime.
  final DisponibiliteEtat etat;
}

/// Tout ce que l'écran « Mon mois » sait faire des tables `periods` et
/// `availabilities`.
///
/// **Le contrat de coût est dans l'interface** : [enregistrerLot] et
/// [supprimerLot] valent chacune **exactement une requête**, quel que soit le
/// nombre de créneaux. Une peinture de quarante cases coûte donc deux
/// requêtes, et c'est ce qui rend tenable le critère des trente secondes sur
/// un réseau de caserne.
abstract interface class DisposRepository {
  /// Les périodes de saisie connues de la caserne, toutes années confondues.
  Future<List<PeriodeSaisie>> periodes(String stationId);

  /// Les disponibilités du membre pour un mois. L'absence de ligne vaut
  /// « non saisi » : la carte rendue ne contient que ce qui est saisi.
  Future<Map<CreneauCle, DisponibiliteEtat>> lireMois({
    required String stationId,
    required String userId,
    required int annee,
    required int mois,
  });

  /// **Une seule requête** : `upsert` de toutes les lignes, sur la contrainte
  /// d'unicité `(station_id, user_id, date, slot)`.
  ///
  /// Rend le nombre de lignes que la base a réellement acceptées. L'appelant
  /// **doit** le comparer au nombre envoyé : voir [supprimerLot] pour la
  /// raison, qui vaut ici aussi.
  Future<int> enregistrerLot({
    required String stationId,
    required String userId,
    required List<LigneDisponibilite> lignes,
  });

  /// **Une seule requête** : suppression groupée des couples date + créneau.
  ///
  /// Rend le nombre de lignes réellement supprimées. Ce nombre est la seule
  /// preuve disponible : en période verrouillée ou caserne suspendue, la
  /// clause `using` de la politique RLS **filtre sans lever**, et un `delete`
  /// refusé répond « 0 ligne, tout va bien » (`supabase/README.md`, ticket
  /// 008). Un appelant qui ne compte pas les lignes affiche « Enregistré »
  /// sur un refus.
  Future<int> supprimerLot({
    required String stationId,
    required String userId,
    required List<CreneauCle> cles,
  });
}

/// Implémentation Supabase. Aucune Edge Function : la RLS de `availabilities`
/// dit déjà qui écrit et quand (`docs/SCHEMA.md § 4`).
class SupabaseDisposRepository implements DisposRepository {
  const SupabaseDisposRepository(this._client);

  final SupabaseClient _client;

  static const String _colonnesPeriode =
      'id, station_id, year, month, status, deadline_at, locked_at';

  /// `set_by` n'est jamais touché par cet écran : le membre saisit pour
  /// lui-même (brief § 7.1).
  static const String _colonnesDispo = 'date, slot, status';

  @override
  Future<List<PeriodeSaisie>> periodes(String stationId) async {
    try {
      final lignes = await _client
          .from('periods')
          .select(_colonnesPeriode)
          .eq('station_id', stationId)
          // `ascending` vaut **false** par défaut dans postgrest-dart : sans
          // ces deux drapeaux, le sélecteur de mois affichait décembre avant
          // octobre. Vu en vrai dans Chrome.
          .order('year', ascending: true)
          .order('month', ascending: true);

      return <PeriodeSaisie>[
        for (final ligne in lignes) PeriodeSaisie.depuisJson(ligne),
      ];
    } on Object catch (echec) {
      throw EchecDispos(_traduire(echec));
    }
  }

  @override
  Future<Map<CreneauCle, DisponibiliteEtat>> lireMois({
    required String stationId,
    required String userId,
    required int annee,
    required int mois,
  }) async {
    final premier = DateTime(annee, mois);
    final suivant = DateTime(annee, mois + 1);

    try {
      final lignes = await _client
          .from('availabilities')
          .select(_colonnesDispo)
          .eq('station_id', stationId)
          .eq('user_id', userId)
          .gte('date', _iso(premier))
          .lt('date', _iso(suivant));

      return <CreneauCle, DisponibiliteEtat>{
        for (final ligne in lignes)
          CreneauCle(
            DateTime.parse(ligne['date']! as String),
            CreneauSql.depuisSql(ligne['slot']! as String),
          ): DisponibiliteSql.depuisSql(
            ligne['status']! as String,
          ),
      };
    } on Object catch (echec) {
      throw EchecDispos(_traduire(echec));
    }
  }

  @override
  Future<int> enregistrerLot({
    required String stationId,
    required String userId,
    required List<LigneDisponibilite> lignes,
  }) async {
    if (lignes.isEmpty) return 0;

    try {
      final rendues = await _client
          .from('availabilities')
          .upsert(<Map<String, dynamic>>[
            for (final ligne in lignes)
              <String, dynamic>{
                'station_id': stationId,
                'user_id': userId,
                'date': ligne.cle.dateIso,
                'slot': ligne.cle.creneau.valeurSql,
                'status': ligne.etat.valeurSql,
              },
          ], onConflict: 'station_id,user_id,date,slot')
          .select(_colonnesDispo);

      return rendues.length;
    } on Object catch (echec) {
      throw EchecDispos(_traduire(echec));
    }
  }

  @override
  Future<int> supprimerLot({
    required String stationId,
    required String userId,
    required List<CreneauCle> cles,
  }) async {
    if (cles.isEmpty) return 0;

    // Un `or` de `and` : une seule requête pour n couples, au lieu d'un
    // `delete` par case ou d'un `delete` par créneau.
    final filtre = cles
        .map(
          (cle) =>
              'and(date.eq.${cle.dateIso},slot.eq.${cle.creneau.valeurSql})',
        )
        .join(',');

    try {
      final rendues = await _client
          .from('availabilities')
          .delete()
          .eq('station_id', stationId)
          .eq('user_id', userId)
          .or(filtre)
          .select(_colonnesDispo);

      return rendues.length;
    } on Object catch (echec) {
      throw EchecDispos(_traduire(echec));
    }
  }

  static String _iso(DateTime jour) {
    final mois = jour.month.toString().padLeft(2, '0');
    final numero = jour.day.toString().padLeft(2, '0');
    return '${jour.year}-$mois-$numero';
  }

  /// Traduit ce que le SDK a levé.
  ///
  /// Le refus de la clause `with check` d'une politique remonte en `42501`.
  /// Le refus de la clause `using`, lui, ne remonte pas du tout : c'est le
  /// nombre de lignes affectées qui le dit, et c'est l'appelant qui le
  /// vérifie.
  static ErreurDispos _traduire(Object echec) {
    if (echec is EchecDispos) return echec.erreur;
    if (echec is PostgrestException) {
      // 42501 : `new row violates row-level security policy`. Sur cette
      // table, la seule cause est une période verrouillée ou une caserne
      // devenue non modifiable.
      if (echec.code == '42501') return ErreurDispos.verrouille;
      // Un code absent signale une réponse qui n'est jamais arrivée.
      if (echec.code == null) return ErreurDispos.reseau;
      return ErreurDispos.inconnue;
    }
    if (echec is AuthException) return ErreurDispos.inconnue;
    // `ClientException`, `SocketException`, `TimeoutException` : le réseau.
    return ErreurDispos.reseau;
  }
}
