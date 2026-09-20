import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';

/// Ce que le démarrage de Supabase a donné.
///
/// L'app ne plante jamais faute de configuration : elle sait le dire.
enum SupabaseDemarrage {
  /// Client prêt, session éventuellement restaurée.
  pret,

  /// `SUPABASE_URL` ou `SUPABASE_ANON_KEY` manquants à la compilation.
  configurationAbsente,

  /// Configuration présente mais l'initialisation a échoué (URL malformée,
  /// stockage local inutilisable…).
  echec;

  bool get estPret => this == pret;
}

/// Initialise le client Supabase une fois, au démarrage.
///
/// La clé transmise est la clé **anon / publishable**, publique par
/// conception : toute la sécurité est portée par les politiques RLS
/// (`docs/SCHEMA.md § 4`). La clé de service n'existe nulle part dans l'app.
///
/// Le paramètre s'appelle `publishableKey` depuis supabase_flutter 2.17 —
/// `anonKey` est déprécié et ferait échouer `flutter analyze`. Le nom de la
/// variable d'environnement, lui, reste `SUPABASE_ANON_KEY` (ticket 002) :
/// les deux formats de clé transitent par le même en-tête.
Future<SupabaseDemarrage> demarrerSupabase(Env env) async {
  if (!env.hasSupabaseConfig) return SupabaseDemarrage.configurationAbsente;

  try {
    await Supabase.initialize(
      url: env.supabaseUrl,
      publishableKey: env.supabaseAnonKey,
      // Les valeurs par défaut de `FlutterAuthClientOptions` sont exactement
      // celles qu'il faut et les réécrire serait un argument redondant que
      // `flutter analyze` refuse (même arbitrage qu'au ticket 004 pour
      // `themeMode`) :
      //   - `authFlowType: pkce` — le lien magique s'échange contre une
      //     session sans exposer de jeton dans l'URL ;
      //   - `autoRefreshToken: true` — le jeton se renouvelle tout seul ;
      //   - `persistSession: true` — la session survit à la fermeture de la
      //     PWA (localStorage sur le web) ;
      //   - `detectSessionInUri: true` — le lien magique est capté au
      //     chargement de la page.
    );
    return SupabaseDemarrage.pret;
  } on Object catch (erreur, pile) {
    // En production, l'écran « application non configurée » dit tout ce qu'un
    // utilisateur peut faire de cette panne ; la trace, elle, n'irait que dans
    // la console du navigateur, à la vue de tous.
    if (kDebugMode) {
      debugPrint('Initialisation Supabase impossible : $erreur\n$pile');
    }
    return SupabaseDemarrage.echec;
  }
}

/// Résultat du démarrage, injecté au lancement par `main`.
///
/// Valeur par défaut volontairement pessimiste : sans surcharge, l'app affiche
/// l'écran « Application non configurée » au lieu d'appeler un client absent.
/// Les tests la surchargent avec [SupabaseDemarrage.pret].
final Provider<SupabaseDemarrage> supabaseDemarrageProvider =
    Provider<SupabaseDemarrage>(
      (ref) => SupabaseDemarrage.configurationAbsente,
    );

/// Le client Supabase de l'application.
///
/// Lire ce provider avant un démarrage réussi est une erreur de programmation :
/// le routeur garantit qu'aucun écran qui en dépend n'est monté dans ce cas.
final Provider<SupabaseClient> supabaseClientProvider =
    Provider<SupabaseClient>((ref) => Supabase.instance.client);
