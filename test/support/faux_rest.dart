import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Un faux PostgREST : **le transport est remplacé, le dépôt reste le vrai**.
///
/// Les autres faux de `test/support/` remplacent l'implémentation entière
/// (`FauxPropositionsRepository`, `FauxPlanningCaserneRepository`) : ils
/// servent aux écrans, qui n'ont pas à connaître PostgREST. Celui-ci fait
/// l'inverse et ne sert qu'aux dépôts `Supabase*Repository`, pour vérifier ce
/// qui part vraiment dans l'URL et ce qui est fait de la réponse.
///
/// C'est la seule façon de verrouiller un filtre : un `status=in.(…)` auquel
/// il manque un état ne se voit dans aucun autre test (ticket 044).
class FauxRest {
  FauxRest([Map<String, List<Map<String, dynamic>>>? tables])
    : _tables = <String, List<Map<String, dynamic>>>{...?tables};

  /// Les lignes rendues par table. La clé est le nom de la table ; une table
  /// absente rend zéro ligne, comme une RLS qui filtre tout.
  final Map<String, List<Map<String, dynamic>>> _tables;

  /// Les URL demandées, dans l'ordre d'appel.
  final List<Uri> requetes = <Uri>[];

  late final SupabaseClient client = SupabaseClient(
    'https://caserne.exemple.test',
    'cle-anon-de-test',
    httpClient: MockClient(_repondre),
  );

  void definir(String table, List<Map<String, dynamic>> lignes) =>
      _tables[table] = lignes;

  /// L'URL de la requête envoyée à [table]. Échoue si elle n'a pas eu lieu :
  /// une requête attendue qui ne part pas est un défaut, pas un `null`.
  Uri requete(String table) => requetes.firstWhere(
    (Uri url) => url.pathSegments.last == table,
    orElse: () => throw StateError('Aucune requête sur « $table ».'),
  );

  /// Combien de requêtes ont visé [table]. Sert au contrat de coût des dépôts.
  int compte(String table) =>
      requetes.where((Uri url) => url.pathSegments.last == table).length;

  Future<void> fermer() => client.dispose();

  Future<http.Response> _repondre(http.Request requete) async {
    requetes.add(requete.url);

    final table = requete.url.pathSegments.last;
    final lignes = _tables[table] ?? const <Map<String, dynamic>>[];

    // `maybeSingle()` demande un objet, pas un tableau : PostgREST le signale
    // par l'en-tête `Accept`, et le dépôt lit `ligne['…']` directement.
    final objet =
        requete.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
    final corps = objet
        ? jsonEncode(lignes.isEmpty ? null : lignes.first)
        : jsonEncode(lignes);

    return http.Response(
      corps,
      200,
      request: requete,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}
