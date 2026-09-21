import 'package:supabase_flutter/supabase_flutter.dart';

import 'appartenance.dart';
import 'auth_erreur.dart';

/// Lecture des appartenances de l'utilisateur connecté.
abstract interface class MembershipRepository {
  /// Les lignes de `memberships` de l'utilisateur [userId], avec le nom de
  /// leur caserne.
  Future<List<Appartenance>> mesAppartenances(String userId);
}

/// Implémentation Supabase de [MembershipRepository].
class SupabaseMembershipRepository implements MembershipRepository {
  SupabaseMembershipRepository(this._client);

  final SupabaseClient _client;

  /// Colonnes de `docs/SCHEMA.md § 2.3`, jointes au nom de la caserne
  /// (§ 2.1). Rien d'autre n'est demandé : une requête ne rapatrie jamais une
  /// colonne qu'aucun écran n'affiche.
  static const String _colonnes =
      'id, station_id, role, status, display_name, stations(name)';

  @override
  Future<List<Appartenance>> mesAppartenances(String userId) async {
    try {
      // Le filtre sur `user_id` est là pour la lisibilité du résultat, pas
      // pour la sécurité : la politique de `memberships` laisse voir toutes
      // les lignes des casernes dont on est membre (`docs/SCHEMA.md § 4`).
      // Sans ce filtre, on lirait aussi les collègues.
      final lignes = await _client
          .from('memberships')
          .select(_colonnes)
          .eq('user_id', userId);

      return lignes.map(Appartenance.depuisJson).toList(growable: false);
    } on Object catch (erreur) {
      throw AuthEchec(_traduire(erreur));
    }
  }

  /// **Distingue le transport du refus**, parce que `appartenancesProvider`
  /// n'a le droit de retomber sur son cache que pour le premier : masquer une
  /// révocation derrière un instantané périmé ferait croire à quelqu'un qu'il
  /// appartient encore à une caserne qui l'a retiré.
  ///
  /// PostgREST enveloppe parfois une requête qui n'est jamais partie dans une
  /// `PostgrestException` **sans code** — c'est la même règle que
  /// `SupabaseAstreintesRepository`. Le reste part à `traduireErreurAuth`.
  static AuthErreur _traduire(Object erreur) {
    if (erreur is PostgrestException && erreur.code == null) {
      return AuthErreur.reseau;
    }
    return traduireErreurAuth(erreur, etape: AuthEtape.envoi);
  }
}
