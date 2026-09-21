import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/export_donnees.dart';

/// L'export RGPD de la personne **connectée**
/// (`supabase/functions/README.md § export-user-data`).
abstract interface class ExportRepository {
  /// Demande au serveur le dossier complet de la personne connectée.
  ///
  /// Aucun identifiant n'est passé, et c'est la règle de sécurité de l'appel :
  /// l'Edge Function tire l'identité du jeton, jamais d'un corps de requête.
  /// Ici l'enjeu est plus fort qu'à la suppression — un `user_id` cru sur
  /// parole ne détruirait rien, il **livrerait** le dossier d'un autre.
  ///
  /// Lève un [EchecExport] pour chaque fin de parcours du contrat.
  Future<ExportDonnees> demander();
}

/// Implémentation Supabase.
class SupabaseExportRepository implements ExportRepository {
  SupabaseExportRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ExportDonnees> demander() async {
    try {
      final reponse = await _client.functions.invoke('export-user-data');

      final dynamic corps = reponse.data;
      if (corps is! Map<String, dynamic> || corps['donnees'] is! Map) {
        // Une réponse sans section `donnees` n'est pas un export : mieux vaut
        // le dire que remettre un fichier vide à quelqu'un qui croira l'avoir.
        throw const EchecExport(ErreurExport.inconnue);
      }

      return ExportDonnees(corps);
    } on FunctionException catch (echec) {
      throw _traduire(echec);
    }
  }

  /// `status == 0` est la marque d'une requête qui n'est jamais partie : le
  /// SDK range là ce que les autres dépôts du projet appellent « réseau ».
  static EchecExport _traduire(FunctionException echec) {
    if (echec.status == 0) {
      return const EchecExport(ErreurExport.reseau);
    }

    final dynamic details = echec.details;
    final dynamic erreur = details is Map ? details['error'] : null;
    if (erreur is! Map) {
      return const EchecExport(ErreurExport.inconnue);
    }

    return EchecExport(ErreurExport.depuisCode(erreur['code'] as String?));
  }
}
