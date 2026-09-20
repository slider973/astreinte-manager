import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configuration d'environnement injectée à la compilation via `--dart-define`
/// ou `--dart-define-from-file=env/<env>.json`.
///
/// Les valeurs sont lues avec `String.fromEnvironment`, donc résolues à la
/// compilation : une valeur absente donne une chaîne vide, jamais une erreur.
/// Aucun secret n'est versionné : seule la clé anon Supabase (publique par
/// conception, protégée par RLS) transite par ces variables.
@immutable
class Env {
  const Env({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.firebaseProjectId,
    required this.appEnv,
  });

  /// Valeurs issues des `--dart-define` de la compilation courante.
  static const Env fromDefines = Env(
    supabaseUrl: String.fromEnvironment(supabaseUrlKey),
    supabaseAnonKey: String.fromEnvironment(supabaseAnonKeyKey),
    firebaseProjectId: String.fromEnvironment(firebaseProjectIdKey),
    appEnv: String.fromEnvironment(appEnvKey, defaultValue: devEnv),
  );

  static const String supabaseUrlKey = 'SUPABASE_URL';
  static const String supabaseAnonKeyKey = 'SUPABASE_ANON_KEY';
  static const String firebaseProjectIdKey = 'FIREBASE_PROJECT_ID';
  static const String appEnvKey = 'APP_ENV';

  static const String devEnv = 'dev';
  static const String prodEnv = 'prod';

  /// URL du projet Supabase (`https://<ref>.supabase.co`).
  final String supabaseUrl;

  /// Clé anon (publique) du projet Supabase.
  final String supabaseAnonKey;

  /// Identifiant du projet Firebase utilisé pour les notifications push.
  final String firebaseProjectId;

  /// `dev` ou `prod`. Vaut `dev` si non fourni.
  final String appEnv;

  bool get isProd => appEnv == prodEnv;

  bool get isDev => !isProd;

  /// Vrai si l'app dispose de quoi initialiser Supabase (ticket 002).
  bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

/// Fournit la configuration d'environnement à toute l'app.
///
/// Surchargé dans les tests via `ProviderScope(overrides: [...])`.
final Provider<Env> envProvider = Provider<Env>((ref) => Env.fromDefines);
