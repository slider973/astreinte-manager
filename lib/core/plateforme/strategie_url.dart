/// La stratégie d'URL de l'application : **des routes sans dièse**.
///
/// Voir `strategie_url_web.dart` pour la mise en œuvre, et
/// `strategie_url_stub.dart` pour les builds natifs, où il n'y a pas d'URL.
library;

export 'strategie_url_stub.dart'
    if (dart.library.js_interop) 'strategie_url_web.dart';
