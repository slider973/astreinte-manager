/// L'état du réseau, tel que le navigateur le rapporte.
///
/// **Hors ligne n'est pas une erreur** (brief 011 § 7.4) : la grille reste
/// éditable, aucune case n'est marquée, et la file d'écriture repart seule au
/// retour du réseau. Ce module n'existe que pour distinguer « ça n'a pas pu
/// partir » de « ça a été refusé ».
///
/// Aucun plugin : `navigator.onLine` et les événements `online` / `offline`
/// suffisent, ils sont gratuits, et ils n'ajoutent pas une dépendance qui
/// n'aurait d'implémentation que native.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'detection_stub.dart' if (dart.library.js_interop) 'detection_web.dart';

/// Ce que l'application sait du réseau.
abstract interface class Connectivite {
  /// Vrai si le navigateur se croit en ligne. Un « oui » ne garantit rien —
  /// un portail captif répond « en ligne » — mais un « non » est sûr.
  bool get enLigne;

  /// Chaque changement d'état, en commençant par l'état courant.
  Stream<bool> get etats;

  void dispose();
}

/// Implémentation en mémoire : toujours en ligne, ou ce qu'on lui dit.
///
/// Sert aux tests et aux plateformes natives, où la question n'a pas de
/// réponse fiable sans plugin.
class ConnectiviteMemoire implements Connectivite {
  ConnectiviteMemoire({bool enLigne = true}) : _enLigne = enLigne;

  bool _enLigne;
  final StreamController<bool> _controleur = StreamController<bool>.broadcast();

  @override
  bool get enLigne => _enLigne;

  @override
  Stream<bool> get etats async* {
    yield _enLigne;
    yield* _controleur.stream;
  }

  /// Simule une perte ou un retour de réseau.
  void definir({required bool enLigne}) {
    if (_enLigne == enLigne) return;
    _enLigne = enLigne;
    _controleur.add(enLigne);
  }

  @override
  void dispose() => unawaited(_controleur.close());
}

/// L'état du réseau de la plateforme courante. Surchargé dans les tests.
final Provider<Connectivite> connectiviteProvider = Provider<Connectivite>((
  ref,
) {
  final connectivite = detecterConnectivite();
  ref.onDispose(connectivite.dispose);
  return connectivite;
});

/// Vrai tant que le réseau est là. Par défaut « en ligne » : tant qu'on ne
/// sait pas, on n'affiche pas de bandeau qui accuse la connexion à tort.
final StreamProvider<bool> enLigneProvider = StreamProvider<bool>(
  (ref) => ref.watch(connectiviteProvider).etats,
);
