import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/supabase/enums.dart';
import '../../../core/theme/app_status.dart';
import '../../dispos/domain/periode_saisie.dart';

/// Pourquoi la base a refusé une action sur une période.
///
/// Les messages levés par `create_period` et par `periods_guard_transition`
/// (migration `0012`) sont des **identifiants** : `forbidden`,
/// `station_suspended`, `period_month_in_past`… Ils ne s'affichent jamais tels
/// quels. L'indice (`hint`) qui les accompagne est, lui, une phrase française
/// affichable ; il sert de filet pour un refus que cette liste ne connaît pas
/// encore — mais quand le cas est connu, c'est la phrase d'ici qui gagne,
/// parce qu'elle est écrite dans le ton du produit et qu'un test peut s'y
/// accrocher.
enum ErreurPeriodes {
  /// `forbidden`, ou une politique RLS qui a filtré la ligne : la personne
  /// n'administre pas cette caserne, ou ne l'administre plus.
  droits(AppStrings.periodeRefusDroits),

  /// `station_suspended` : abonnement suspendu, la caserne est en lecture
  /// seule.
  suspendue(AppStrings.periodeRefusSuspendue),

  /// `period_month_in_past` : un mois écoulé ne s'ouvre plus.
  moisPasse(AppStrings.periodeRefusMoisPasse),

  /// `period_month_invalid` : mois hors de 1–12, ou année hors bornes.
  moisInvalide(AppStrings.periodeRefusMoisInvalide),

  /// `period_reopen_deadline_passed` : **le cœur du ticket**. Rouvrir sans
  /// repousser la date limite est une action que la tâche horaire défait dans
  /// l'heure.
  dateLimitePassee(AppStrings.periodeRefusDeadlinePassee),

  /// Réseau, panne, réponse illisible : la sortie est la même, réessayer.
  inconnue(AppStrings.periodeEchecGenerique);

  const ErreurPeriodes(this.message);

  final String message;
}

/// Une action sur une période refusée, avec sa phrase déjà en français.
class EchecPeriodes implements Exception {
  const EchecPeriodes(this.erreur, {String? message}) : _message = message;

  final ErreurPeriodes erreur;

  /// L'indice rendu par la base, quand il dit mieux que notre phrase par
  /// défaut (refus inconnu de [ErreurPeriodes]).
  final String? _message;

  String get message => _message ?? erreur.message;

  @override
  String toString() => 'EchecPeriodes(${erreur.name})';
}

/// Tout ce que l'écran d'administration « Périodes » sait faire de la table
/// `periods` (`docs/SCHEMA.md § 2.5`).
///
/// Une interface, pas un client Supabase : l'écran se teste avec un faux.
abstract interface class PeriodesRepository {
  /// Les mois de la caserne, du plus ancien au plus récent.
  Future<List<PeriodeSaisie>> lister(String stationId);

  /// Ouvre un mois à la saisie, par la fonction `create_period`.
  ///
  /// **Idempotente côté base** : un mois déjà ouvert est rendu tel quel plutôt
  /// que refusé. Deux adjoints qui cliquent en même temps obtiennent le même
  /// résultat.
  Future<PeriodeSaisie> creer({
    required String stationId,
    required int annee,
    required int mois,
  });

  /// Verrouille le mois maintenant. **`locked_at` n'est jamais envoyé** :
  /// c'est le déclencheur `periods_guard_transition` qui le pose.
  Future<PeriodeSaisie> verrouiller(String periodeId);

  /// Rouvre le mois **et repousse sa date limite dans le même geste**.
  ///
  /// Les deux champs partent ensemble parce que la base l'exige : une
  /// réouverture dont la date limite est déjà passée lève
  /// `period_reopen_deadline_passed`, et une réouverture qui la laisserait
  /// telle quelle serait défaite par la tâche horaire.
  Future<PeriodeSaisie> rouvrir({
    required String periodeId,
    required DateTime dateLimite,
  });

  /// Les membres **actifs** de la caserne : le dénominateur du taux de saisie.
  ///
  /// Des identifiants et non un compte, parce que le numérateur doit s'y
  /// intersecter : un membre désactivé qui avait saisi son mois compterait
  /// sinon dans « 10 membres sur 9 ».
  Future<Set<String>> membresActifs(String stationId);

  /// Les membres ayant au moins une disponibilité saisie sur ce mois.
  Future<Set<String>> membresAyantSaisi({
    required String stationId,
    required int annee,
    required int mois,
  });
}

/// Implémentation Supabase.
///
/// Aucune Edge Function : la RLS de `periods` dit déjà qui écrit
/// (`periods_update_admin`), et la seule règle qu'elle ne sait pas dire — la
/// date limite calculée depuis les réglages de la caserne — vit dans la
/// fonction `create_period`.
class SupabasePeriodesRepository implements PeriodesRepository {
  const SupabasePeriodesRepository(this._client);

  final SupabaseClient _client;

  /// Les colonnes de `periods`. `created_at` et `updated_at` n'ont pas de
  /// lecteur : elles ne sont pas demandées.
  static const String _colonnes =
      'id, station_id, year, month, status, deadline_at, locked_at';

  @override
  Future<List<PeriodeSaisie>> lister(String stationId) async {
    try {
      final lignes = await _client
          .from('periods')
          .select(_colonnes)
          .eq('station_id', stationId)
          // `ascending` vaut **false** par défaut dans postgrest-dart : sans
          // ces deux drapeaux, décembre passerait devant octobre.
          .order('year', ascending: true)
          .order('month', ascending: true);

      return <PeriodeSaisie>[
        for (final ligne in lignes) PeriodeSaisie.depuisJson(ligne),
      ];
    } on Object catch (echec) {
      throw _traduire(echec);
    }
  }

  @override
  Future<PeriodeSaisie> creer({
    required String stationId,
    required int annee,
    required int mois,
  }) async {
    try {
      // La fonction rend une ligne `periods` entière : le client ne calcule
      // jamais la date limite lui-même, sous peine d'écrire la règle une
      // seconde fois et d'accepter qu'elle diverge.
      final reponse = await _client.rpc<dynamic>(
        'create_period',
        params: <String, dynamic>{
          'p_station': stationId,
          'p_year': annee,
          'p_month': mois,
        },
      );

      final ligne = reponse is List ? reponse.firstOrNull : reponse;
      if (ligne is! Map<String, dynamic>) {
        throw const EchecPeriodes(ErreurPeriodes.inconnue);
      }
      return PeriodeSaisie.depuisJson(ligne);
    } on Object catch (echec) {
      throw _traduire(echec);
    }
  }

  @override
  Future<PeriodeSaisie> verrouiller(String periodeId) => _majStatut(
    periodeId,
    <String, dynamic>{'status': PeriodeEtat.verrouillee.valeurSql},
  );

  @override
  Future<PeriodeSaisie> rouvrir({
    required String periodeId,
    required DateTime dateLimite,
  }) => _majStatut(periodeId, <String, dynamic>{
    'status': PeriodeEtat.ouverte.valeurSql,
    // L'heure locale du navigateur, convertie en instant. Pour une caserne
    // française consultée depuis la France — le cas de tout le MVP — c'est
    // exactement le fuseau de la caserne. Le jour choisi est donc celui qui a
    // été lu à l'écran.
    'deadline_at': dateLimite.toUtc().toIso8601String(),
  });

  /// Le seul chemin d'écriture sur une période existante.
  ///
  /// **La caserne, l'année et le mois n'y figurent jamais** : la clé d'une
  /// période est gelée par `periods_guard_transition`, et l'envoyer ne
  /// pourrait que provoquer un `period_key_immutable` gratuit.
  ///
  /// La relecture n'est pas décorative : une politique `using` qui ne matche
  /// pas **ne lève rien**, elle filtre. Sans elle, un admin rétrogradé
  /// entre-temps lirait « c'est fait » sans que rien ne le soit.
  Future<PeriodeSaisie> _majStatut(
    String periodeId,
    Map<String, dynamic> valeurs,
  ) async {
    try {
      final lignes = await _client
          .from('periods')
          .update(valeurs)
          .eq('id', periodeId)
          .select(_colonnes);

      if (lignes.isEmpty) throw const EchecPeriodes(ErreurPeriodes.droits);
      return PeriodeSaisie.depuisJson(lignes.first);
    } on Object catch (echec) {
      throw _traduire(echec);
    }
  }

  @override
  Future<Set<String>> membresActifs(String stationId) async {
    try {
      final lignes = await _client
          .from('memberships')
          .select('user_id')
          .eq('station_id', stationId)
          .eq('status', 'active');
      return _identifiants(lignes);
    } on Object catch (echec) {
      throw _traduire(echec);
    }
  }

  @override
  Future<Set<String>> membresAyantSaisi({
    required String stationId,
    required int annee,
    required int mois,
  }) async {
    try {
      // **Une requête par mois affiché, et seulement les mois affichés**
      // (`design/014 § 7`). Une seule colonne est demandée : la réponse tient
      // en un identifiant par ligne saisie, et le comptage des membres
      // distincts se fait ici. Le jour où la matrice admin aura besoin des
      // mêmes chiffres, une vue les rendra en une ligne par mois.
      final lignes = await _client
          .from('availabilities')
          .select('user_id')
          .eq('station_id', stationId)
          .gte('date', _premierJour(annee, mois))
          .lt('date', _premierJour(annee, mois + 1));

      return _identifiants(lignes);
    } on Object catch (echec) {
      throw _traduire(echec);
    }
  }

  static Set<String> _identifiants(List<Map<String, dynamic>> lignes) =>
      <String>{
        for (final ligne in lignes)
          if (ligne['user_id'] is String) ligne['user_id']! as String,
      };

  /// Le premier jour d'un mois, au format d'une colonne `date`. `mois + 1`
  /// vaut 13 en décembre : `DateTime` le normalise en janvier suivant.
  static String _premierJour(int annee, int mois) {
    final jour = DateTime(annee, mois);
    return '${jour.year}-${jour.month.toString().padLeft(2, '0')}-01';
  }

  /// Traduit ce que le SDK a levé.
  static EchecPeriodes _traduire(Object echec) {
    if (echec is EchecPeriodes) return echec;
    if (echec is! PostgrestException) {
      // `ClientException`, `SocketException`, `TimeoutException` : le réseau.
      return const EchecPeriodes(ErreurPeriodes.inconnue);
    }

    final message = echec.message;
    final erreur = switch (message) {
      _ when message.contains('period_reopen_deadline_passed') =>
        ErreurPeriodes.dateLimitePassee,
      _ when message.contains('station_suspended') => ErreurPeriodes.suspendue,
      _ when message.contains('period_month_in_past') =>
        ErreurPeriodes.moisPasse,
      _ when message.contains('period_month_invalid') =>
        ErreurPeriodes.moisInvalide,
      _ when message.contains('forbidden') => ErreurPeriodes.droits,
      // 42501 : la clause `with check` d'une politique a refusé la ligne.
      _ when echec.code == '42501' => ErreurPeriodes.droits,
      _ => ErreurPeriodes.inconnue,
    };

    // Un refus que cette liste ne connaît pas : l'indice de la base est déjà
    // une phrase française, et il en dira toujours plus que « réessaie ».
    final indice = echec.hint;
    return EchecPeriodes(
      erreur,
      message: erreur == ErreurPeriodes.inconnue && indice != null
          ? indice
          : null,
    );
  }
}
