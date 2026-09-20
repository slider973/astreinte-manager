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
    required this.firebaseApiKey,
    required this.firebaseAppId,
    required this.firebaseMessagingSenderId,
    required this.firebaseVapidKey,
  });

  /// Une configuration sans aucune valeur Firebase : l'état du projet tant
  /// qu'aucun projet Firebase n'a été créé. Sert de base aux tests et aux
  /// environnements qui n'ont pas de push.
  const Env.sansPush({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.appEnv,
  }) : firebaseProjectId = '',
       firebaseApiKey = '',
       firebaseAppId = '',
       firebaseMessagingSenderId = '',
       firebaseVapidKey = '';

  /// Valeurs issues des `--dart-define` de la compilation courante.
  static const Env fromDefines = Env(
    supabaseUrl: String.fromEnvironment(supabaseUrlKey),
    supabaseAnonKey: String.fromEnvironment(supabaseAnonKeyKey),
    firebaseProjectId: String.fromEnvironment(firebaseProjectIdKey),
    appEnv: String.fromEnvironment(appEnvKey, defaultValue: devEnv),
    firebaseApiKey: String.fromEnvironment(firebaseApiKeyKey),
    firebaseAppId: String.fromEnvironment(firebaseAppIdKey),
    firebaseMessagingSenderId: String.fromEnvironment(
      firebaseMessagingSenderIdKey,
    ),
    firebaseVapidKey: String.fromEnvironment(firebaseVapidKeyKey),
  );

  static const String supabaseUrlKey = 'SUPABASE_URL';
  static const String supabaseAnonKeyKey = 'SUPABASE_ANON_KEY';
  static const String firebaseProjectIdKey = 'FIREBASE_PROJECT_ID';
  static const String firebaseApiKeyKey = 'FIREBASE_API_KEY';
  static const String firebaseAppIdKey = 'FIREBASE_APP_ID';
  static const String firebaseMessagingSenderIdKey =
      'FIREBASE_MESSAGING_SENDER_ID';
  static const String firebaseVapidKeyKey = 'FIREBASE_VAPID_KEY';
  static const String appEnvKey = 'APP_ENV';

  static const String devEnv = 'dev';
  static const String prodEnv = 'prod';

  /// URL du projet Supabase (`https://<ref>.supabase.co`).
  final String supabaseUrl;

  /// Clé anon (publique) du projet Supabase.
  final String supabaseAnonKey;

  /// Identifiant du projet Firebase utilisé pour les notifications push.
  final String firebaseProjectId;

  /// Clé d'API web du projet Firebase. Publique par conception, comme la clé
  /// anon de Supabase : elle identifie le projet, elle n'autorise rien.
  final String firebaseApiKey;

  /// Identifiant de l'**application web** enregistrée dans le projet
  /// (`1:123…:web:abc…`). Une application par canal : celle-ci est la PWA.
  final String firebaseAppId;

  /// Numéro d'expéditeur du projet (`messagingSenderId`).
  final String firebaseMessagingSenderId;

  /// Clé publique VAPID de la paire « certificats push web » du projet. Elle
  /// est **publique** : c'est la clé que le navigateur vérifie. La moitié
  /// privée ne quitte jamais Firebase.
  final String firebaseVapidKey;

  /// `dev` ou `prod`. Vaut `dev` si non fourni.
  final String appEnv;

  bool get isProd => appEnv == prodEnv;

  bool get isDev => !isProd;

  /// Vrai si l'app dispose de quoi initialiser Supabase (ticket 002).
  bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Vrai si l'app dispose de **tout** ce qu'il faut pour le push web
  /// (ticket 024). Les cinq valeurs sont nécessaires : sans la clé VAPID, le
  /// navigateur refuse l'abonnement ; sans l'identifiant d'application, le
  /// SDK refuse de démarrer. Une configuration à moitié remplie est traitée
  /// comme absente — mieux vaut des notifications désactivées et annoncées
  /// qu'un échec silencieux à chaque lancement.
  ///
  /// Aucun secret ici : ces cinq valeurs sont celles que Firebase publie dans
  /// le HTML de n'importe quelle application web. Le droit d'**envoyer** un
  /// push tient à la clé de service, qui vit côté Edge Function (ticket 025).
  bool get hasFirebaseConfig =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty &&
      firebaseVapidKey.isNotEmpty;
}

/// Fournit la configuration d'environnement à toute l'app.
///
/// Surchargé dans les tests via `ProviderScope(overrides: [...])`.
final Provider<Env> envProvider = Provider<Env>((ref) => Env.fromDefines);
