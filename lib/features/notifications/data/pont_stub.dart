/// Hors du web : pas de service worker, donc jamais de destination par ce
/// chemin. Compilé dans les builds iOS et Android (ticket 036).
Stream<String> ecouterServiceWorker() => const Stream<String>.empty();
