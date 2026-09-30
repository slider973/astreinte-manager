import 'package:flutter/foundation.dart';

/// Hors du web : pas de service worker, donc jamais de destination par ce
/// chemin. Compilé dans les builds iOS et Android (ticket 036).
Stream<String> ecouterServiceWorker() => const Stream<String>.empty();

/// Hors du web : pas de service worker à ranger.
Future<void> nettoyerEnregistrements({required bool garderPush}) async {}

/// Hors du web : pas de console de navigateur. Le journal de débogage suffit.
void avertir(String message) {
  if (kDebugMode) debugPrint(message);
}
