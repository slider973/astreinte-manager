import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/app_strings.dart';
import '../domain/parametres_caserne.dart';

/// Tout ce que l'écran « Paramètres » sait faire de la ligne `stations`.
///
/// Une interface, pas un client Supabase : l'écran se teste avec un faux.
abstract interface class ParametresRepository {
  /// Les réglages de la caserne, lus sous la RLS de `stations`
  /// (`stations_select_member_or_super_admin`).
  Future<ParametresCaserne> lire(String stationId);

  /// Écrit le nom, le fuseau et le document `settings`, et **relit la ligne
  /// écrite**. Lève un [EchecParametres] si la base refuse.
  Future<ParametresCaserne> enregistrer(ParametresCaserne parametres);
}

/// Pourquoi une écriture de paramètres a été refusée.
enum ErreurParametres {
  /// La RLS a filtré ou refusé la ligne : la personne n'administre pas cette
  /// caserne (ou ne l'administre plus).
  droits(AppStrings.parametresRefusDroits),

  /// La contrainte `stations_settings_valide` (ou celle du nom) a refusé le
  /// document. L'écran valide avant d'envoyer : y arriver signifie que les
  /// deux validations ont divergé, et la phrase le dit sans accuser.
  document(AppStrings.parametresRefusDocument),

  /// Le déclencheur `stations_check_timezone` : fuseau absent de la base IANA.
  fuseau(AppStrings.parametresRefusFuseau),

  /// Réseau tombé, serveur en vrac, réponse illisible : la sortie est la même,
  /// réessayer.
  inconnue(AppStrings.parametresEchecGenerique);

  const ErreurParametres(this.message);

  final String message;
}

/// Une écriture de paramètres refusée, avec sa phrase déjà en français.
class EchecParametres implements Exception {
  const EchecParametres(this.erreur);

  final ErreurParametres erreur;

  String get message => erreur.message;

  @override
  String toString() => 'EchecParametres(${erreur.name})';
}

/// Implémentation Supabase.
///
/// Aucune Edge Function : la RLS de `stations` dit déjà qui écrit, et la
/// validation vit dans une contrainte `check` (migration `0011`). Un
/// intermédiaire en Deno n'ajouterait ici qu'un point de panne.
class SupabaseParametresRepository implements ParametresRepository {
  SupabaseParametresRepository(this._client);

  final SupabaseClient _client;

  /// Les colonnes de `stations` (§ 2.1) que l'écran règle. `slug` n'en est
  /// pas : il identifie la caserne dans les liens, et se change en SQL.
  static const String _colonnes = 'id, name, timezone, settings';

  @override
  Future<ParametresCaserne> lire(String stationId) async {
    final ligne = await _client
        .from('stations')
        .select(_colonnes)
        .eq('id', stationId)
        .maybeSingle();

    if (ligne == null) throw const EchecParametres(ErreurParametres.droits);
    return ParametresCaserne.depuisJson(ligne);
  }

  @override
  Future<ParametresCaserne> enregistrer(ParametresCaserne parametres) async {
    try {
      // La relecture n'est pas décorative : une politique `using` qui ne
      // matche pas **ne lève rien**, elle filtre. Sans elle, un admin
      // rétrogradé entre-temps lirait « c'est enregistré » sans que rien ne
      // le soit. Elle rapporte en outre la ligne telle que la base l'a
      // acceptée, déclencheurs compris.
      final lignes = await _client
          .from('stations')
          .update(<String, dynamic>{
            'name': parametres.nom.trim(),
            'timezone': parametres.fuseau,
            'settings': parametres.settingsJson,
          })
          .eq('id', parametres.stationId)
          .select(_colonnes);

      if (lignes.isEmpty) {
        throw const EchecParametres(ErreurParametres.droits);
      }
      return ParametresCaserne.depuisJson(lignes.first);
    } on PostgrestException catch (echec) {
      throw EchecParametres(_traduire(echec));
    }
  }

  /// Les messages du déclencheur et des contraintes arrivent tels quels dans
  /// `message` : ce sont des identifiants, jamais affichés.
  static ErreurParametres _traduire(PostgrestException echec) {
    final message = echec.message;
    if (message.contains('station_timezone_unknown')) {
      return ErreurParametres.fuseau;
    }
    // 23514 : contrainte `check` — le document ou le nom.
    if (echec.code == '23514' ||
        message.contains('stations_settings_valide') ||
        message.contains('stations_name_non_vide')) {
      return ErreurParametres.document;
    }
    // 42501 : la clause `with check` a refusé la ligne.
    return echec.code == '42501'
        ? ErreurParametres.droits
        : ErreurParametres.inconnue;
  }
}
