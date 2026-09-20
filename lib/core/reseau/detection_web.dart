import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'connectivite.dart';

/// `navigator.onLine`, plus les événements `online` et `offline`.
///
/// C'est le seul signal que le navigateur donne, et il est franc dans un
/// sens : quand il dit « hors ligne », il l'est. Quand il dit « en ligne »,
/// il dit seulement qu'une interface réseau existe — c'est pourquoi l'écran
/// ne s'appuie jamais dessus pour décider qu'une écriture a réussi.
Connectivite detecterConnectivite() => _ConnectiviteNavigateur();

class _ConnectiviteNavigateur implements Connectivite {
  _ConnectiviteNavigateur() {
    _enLigne = web.window.navigator.onLine;
    _ecouteEnLigne = ((web.Event _) => _basculer(vrai: true)).toJS;
    _ecouteHorsLigne = ((web.Event _) => _basculer(vrai: false)).toJS;
    web.window.addEventListener('online', _ecouteEnLigne);
    web.window.addEventListener('offline', _ecouteHorsLigne);
  }

  late bool _enLigne;
  late final JSFunction _ecouteEnLigne;
  late final JSFunction _ecouteHorsLigne;
  final StreamController<bool> _controleur = StreamController<bool>.broadcast();

  @override
  bool get enLigne => _enLigne;

  @override
  Stream<bool> get etats async* {
    yield _enLigne;
    yield* _controleur.stream;
  }

  void _basculer({required bool vrai}) {
    if (_enLigne == vrai) return;
    _enLigne = vrai;
    _controleur.add(vrai);
  }

  @override
  void dispose() {
    web.window.removeEventListener('online', _ecouteEnLigne);
    web.window.removeEventListener('offline', _ecouteHorsLigne);
    unawaited(_controleur.close());
  }
}
