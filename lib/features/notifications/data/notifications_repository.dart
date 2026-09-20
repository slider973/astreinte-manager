import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/notification_interne.dart';

/// Tout ce que le centre de notifications sait faire de la table
/// `notifications` (`docs/SCHEMA.md § 2.12`).
///
/// Une interface, pas un client Supabase : l'écran se teste avec un faux.
abstract interface class NotificationsRepository {
  /// Les lignes `inapp` du membre, **la plus récente en premier**.
  Future<List<NotificationInterne>> lister({
    required String userId,
    int limite,
  });

  /// Marque une ligne lue et rend l'instant écrit.
  ///
  /// Rend `null` quand la ligne était **déjà** lue : la requête ne touche que
  /// les lignes dont `read_at` est nul, pour que la date de première lecture
  /// ne soit pas repoussée à chaque ouverture.
  Future<DateTime?> marquerLue(String id);

  /// Marque lues toutes les non-lues du membre. Rend leur nombre.
  Future<int> toutMarquerLu(String userId);
}

/// Implémentation Supabase.
///
/// **Aucune écriture ne porte autre chose que `read_at`.** Ce n'est pas une
/// politesse : `authenticated` n'a le droit d'écrire que cette colonne
/// (`revoke update on notifications` puis `grant update (read_at)`,
/// `docs/SCHEMA.md § 5`), et une requête qui en nommerait une seconde serait
/// refusée en bloc — le `status` de la ligne, son `title`, n'importe quoi.
/// Ajouter un champ ici casse la lecture de tout l'écran, pas seulement du
/// champ ajouté.
class SupabaseNotificationsRepository implements NotificationsRepository {
  const SupabaseNotificationsRepository(this._client);

  final SupabaseClient _client;

  /// Les colonnes lues. `channel` sert au filtre et pas à l'affichage :
  /// elle n'est pas demandée. `sent_at` et `delivered` tracent l'envoi et
  /// n'ont aucun lecteur ici.
  static const String _colonnes =
      'id, type, title, body, data, read_at, error, created_at';

  /// Le plafond de lecture.
  ///
  /// PostgREST plafonne de toute façon une réponse à mille lignes sans le
  /// dire ; autant fixer la borne ici, où elle se lit. Deux cents événements,
  /// c'est plus d'un an de vie d'un pompier volontaire, et la tâche
  /// `prune_notifications` (`docs/SCHEMA.md § 8`) efface les lues de plus de
  /// quatre-vingt-dix jours.
  static const int limiteParDefaut = 200;

  @override
  Future<List<NotificationInterne>> lister({
    required String userId,
    int limite = limiteParDefaut,
  }) async {
    final lignes = await _client
        .from('notifications')
        .select(_colonnes)
        // `user_id` est déjà imposé par `notifications_select_self`. Le filtre
        // est là pour l'index `(user_id, created_at desc)`, pas pour la
        // sécurité : la RLS reste la seule autorité.
        .eq('user_id', userId)
        .eq('channel', 'inapp')
        .order('created_at', ascending: false)
        .limit(limite);

    return <NotificationInterne>[
      for (final ligne in lignes) NotificationInterne.depuisJson(ligne),
    ];
  }

  @override
  Future<DateTime?> marquerLue(String id) async {
    final lignes = await _client
        .from('notifications')
        .update(<String, dynamic>{'read_at': _maintenant()})
        .eq('id', id)
        .isFilter('read_at', null)
        .select('read_at');

    if (lignes.isEmpty) return null;
    return DateTime.tryParse(lignes.first['read_at'] as String? ?? '')
        ?.toLocal();
  }

  @override
  Future<int> toutMarquerLu(String userId) async {
    final lignes = await _client
        .from('notifications')
        .update(<String, dynamic>{'read_at': _maintenant()})
        .eq('user_id', userId)
        .eq('channel', 'inapp')
        .isFilter('read_at', null)
        // La relecture n'est pas décorative : une politique `using` qui ne
        // matche pas **ne lève rien**, elle filtre. Sans elle, l'écran dirait
        // « c'est fait » sans que rien ne le soit.
        .select('id');

    return lignes.length;
  }

  /// L'horodatage écrit dans `read_at`, en UTC.
  ///
  /// Posé par le client et non par un `now()` de base : la date de lecture est
  /// une information de confort, et un aller-retour de RPC pour l'obtenir
  /// coûterait plus cher que sa précision ne vaut.
  String _maintenant() => DateTime.now().toUtc().toIso8601String();
}
