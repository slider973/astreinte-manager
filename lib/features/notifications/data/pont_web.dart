import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Le type de message convenu avec `web/push/firebase-messaging-sw.js`. Le
/// service worker poste aussi d'autres messages (ceux du SDK Firebase) : on ne
/// réagit qu'au nôtre.
const String _typeNavigation = 'astreinte-sp/navigation';

/// Le nom du script du service worker des push, à l'ancien emplacement comme
/// au nouveau.
const String _scriptFirebase = '/firebase-messaging-sw.js';

/// La portée que le SDK Firebase prend de lui-même quand on ne lui donne pas
/// d'enregistrement (`deleteToken()` sans `getToken()` préalable).
const String _porteeParDefautFirebase = 'firebase-cloud-messaging-push-scope';

/// Range les service workers de l'origine, **sans réseau** (ticket 074).
///
/// Pour chaque enregistrement :
///
/// 1. la portée `push/` — celle du vrai worker des push — est **gardée** au
///    lancement ([garderPush]) : c'est là que vit l'abonnement du jeton
///    publié ;
/// 2. tout autre abonnement push est oublié. `PushSubscription.unsubscribe()`
///    est local : le navigateur oublie l'abonnement, et le worker ne reçoit
///    plus rien, même si FCM n'a pas été prévenu. C'est ce qui tient hors
///    ligne, là où le `deleteToken` du SDK commence par un appel au serveur et
///    s'arrête s'il échoue. L'application n'utilise les push que pour FCM : il
///    n'y a rien d'autre à épargner. Sur `/`, c'est l'abonnement que les
///    versions d'avant le 074 y avaient posé, et que le worker de Flutter
///    reçoit et perd ;
/// 3. un enregistrement Firebase resté hors de `push/` — la portée par défaut
///    du SDK, ou un worker Firebase **actif** ailleurs — est désinscrit. Celui
///    de Flutter, sur `/`, ne l'est jamais : un worker Firebase qui attend
///    derrière lui est remplacé par le chargeur de Flutter à chaque lancement,
///    et le script de l'ancien emplacement se désinscrit de lui-même
///    (`web/firebase-messaging-sw.js`).
///
/// Un enregistrement qui résiste n'empêche pas de ranger les suivants.
Future<void> nettoyerEnregistrements({required bool garderPush}) async {
  final conteneur = web.window.navigator.serviceWorker;
  final porteePush = Uri.parse(
    web.document.baseURI,
  ).resolve('push/').toString();

  final enregistrements = await conteneur.getRegistrations().toDart;
  for (final enregistrement in enregistrements.toDart) {
    try {
      final estPush = enregistrement.scope == porteePush;
      if (estPush && garderPush) continue;

      final abonnement = await enregistrement.pushManager
          .getSubscription()
          .toDart;
      if (abonnement != null) await abonnement.unsubscribe().toDart;
      if (estPush) continue;

      final actif = enregistrement.active?.scriptURL;
      final firebaseEgare =
          enregistrement.scope.endsWith('/$_porteeParDefautFirebase') ||
          (actif != null && Uri.parse(actif).path.endsWith(_scriptFirebase));
      if (firebaseEgare) await enregistrement.unregister().toDart;
    } on Object catch (erreur) {
      avertir('Service worker non rangé (${enregistrement.scope}) : $erreur');
    }
  }
}

/// `console.warn`, qui reste visible dans une construction de production.
void avertir(String message) =>
    web.console.warn('Astreinte SP — $message'.toJS);

/// Écoute les destinations postées par le service worker.
Stream<String> ecouterServiceWorker() {
  // Le contrôleur vit aussi longtemps que l'abonnement : il se ferme quand le
  // dernier auditeur se retire, dans `onCancel`.
  // ignore: close_sinks
  late final StreamController<String> controleur;

  void ecouter(web.MessageEvent evenement) {
    final donnees = evenement.data;
    if (donnees == null || !donnees.isA<JSObject>()) return;

    final objet = donnees as JSObject;
    final type = objet.getProperty<JSAny?>('type'.toJS);
    if (!type.isA<JSString>() || (type! as JSString).toDart != _typeNavigation) {
      return;
    }

    final route = objet.getProperty<JSAny?>('route'.toJS);
    if (!route.isA<JSString>()) return;

    final valeur = (route! as JSString).toDart;
    if (valeur.isNotEmpty) controleur.add(valeur);
  }

  final rappel = ecouter.toJS;

  controleur = StreamController<String>(
    onListen: () => web.window.navigator.serviceWorker.addEventListener(
      'message',
      rappel,
    ),
    onCancel: () {
      web.window.navigator.serviceWorker.removeEventListener('message', rappel);
      return controleur.close();
    },
  );

  return controleur.stream;
}
