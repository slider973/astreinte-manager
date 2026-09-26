import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Le type de message convenu avec `web/firebase-messaging-sw.js`. Le service
/// worker poste aussi d'autres messages (ceux du SDK Firebase) : on ne réagit
/// qu'au nôtre.
const String _typeNavigation = 'astreinte-sp/navigation';

/// Désabonne ce navigateur de **tous** les push de l'origine, sans réseau.
///
/// `PushSubscription.unsubscribe()` est local : le navigateur oublie
/// l'abonnement, et le service worker ne reçoit plus rien, même si FCM n'a
/// pas été prévenu. C'est ce qui tient hors ligne, là où le `deleteToken` du
/// SDK Firebase commence par un appel au serveur et s'arrête s'il échoue.
/// L'application n'utilise les push que pour FCM : il n'y a rien d'autre à
/// épargner.
Future<void> desabonnerPushLocal() async {
  final enregistrements = await web.window.navigator.serviceWorker
      .getRegistrations()
      .toDart;
  for (final enregistrement in enregistrements.toDart) {
    final abonnement = await enregistrement.pushManager
        .getSubscription()
        .toDart;
    if (abonnement != null) await abonnement.unsubscribe().toDart;
  }
}

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
