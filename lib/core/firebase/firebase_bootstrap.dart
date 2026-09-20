import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env.dart';

/// Ce que le démarrage de Firebase a donné.
///
/// Mêmes règles que `core/supabase/supabase_bootstrap.dart` : **le démarrage
/// ne lève jamais**. Une configuration absente ou un SDK qui refuse de se
/// charger n'empêche pas d'ouvrir l'application — elle s'ouvre sans
/// notifications, et elle le dit.
enum FirebaseDemarrage {
  /// Les cinq variables `FIREBASE_*` ne sont pas toutes renseignées
  /// (`docs/FIREBASE.md`). C'est l'état **normal** tant qu'aucun projet
  /// Firebase n'existe.
  configurationAbsente,

  /// Build iOS ou Android : le push natif est le ticket 036, pas celui-ci.
  horsWeb,

  /// SDK initialisé, les notifications peuvent être proposées.
  pret,

  /// Configuration présente mais l'initialisation a échoué : SDK JS
  /// injoignable, valeurs refusées par Firebase, navigation privée.
  echec;

  bool get estPret => this == pret;
}

/// Les options de l'**application web** du projet Firebase, construites depuis
/// les `--dart-define`.
///
/// Il n'y a volontairement pas de `firebase_options.dart` généré par
/// `flutterfire configure` : ce fichier fige les clés d'un projet dans le
/// dépôt, alors que le projet n'existe pas encore et que dev et prod n'auront
/// pas les mêmes. Les valeurs suivent le même chemin que celles de Supabase,
/// `env/<env>.json` (`env/README.md`).
FirebaseOptions optionsFirebaseWeb(Env env) => FirebaseOptions(
  apiKey: env.firebaseApiKey,
  appId: env.firebaseAppId,
  messagingSenderId: env.firebaseMessagingSenderId,
  projectId: env.firebaseProjectId,
  // `authDomain` et `storageBucket` n'ont d'utilité que pour Firebase Auth et
  // Storage, dont l'application ne se sert pas : l'authentification est celle
  // de Supabase. Les omettre évite deux variables d'environnement à remplir
  // pour rien.
);

/// Initialise Firebase une fois, au démarrage, **et seulement sur le web**.
///
/// Le SDK JS n'est téléchargé par `firebase_core_web` qu'au premier appel de
/// `Firebase.initializeApp` : sans configuration, cette fonction sort avant,
/// et l'application ne fait aucune requête vers Google.
Future<FirebaseDemarrage> demarrerFirebase(Env env) async {
  if (!kIsWeb) return FirebaseDemarrage.horsWeb;
  if (!env.hasFirebaseConfig) return FirebaseDemarrage.configurationAbsente;

  try {
    await Firebase.initializeApp(options: optionsFirebaseWeb(env));
    return FirebaseDemarrage.pret;
  } on Object catch (erreur, pile) {
    if (kDebugMode) {
      debugPrint('Initialisation Firebase impossible : $erreur\n$pile');
    }
    return FirebaseDemarrage.echec;
  }
}

/// Résultat du démarrage, injecté au lancement par `main`.
///
/// Valeur par défaut volontairement pessimiste, comme pour Supabase : sans
/// surcharge — donc dans tous les tests — l'application se comporte comme si
/// aucun projet Firebase n'existait.
final Provider<FirebaseDemarrage> firebaseDemarrageProvider =
    Provider<FirebaseDemarrage>((ref) => FirebaseDemarrage.configurationAbsente);
