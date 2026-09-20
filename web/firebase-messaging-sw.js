/*
 * Service worker des notifications — Astreinte SP (ticket 024).
 *
 * Il tourne HORS de l'application Flutter : il ne voit ni les `--dart-define`,
 * ni `lib/core/env.dart`. Sa configuration lui arrive donc dans l'URL avec
 * laquelle l'application l'enregistre (voir `MessageriePushFirebase`) :
 *
 *   firebase-messaging-sw.js?apiKey=…&appId=…&messagingSenderId=…&projectId=…
 *
 * C'est ce qui permet de n'écrire AUCUNE clé Firebase dans le dépôt : dev,
 * préproduction et production utilisent le même fichier avec des valeurs
 * différentes. Ces quatre valeurs sont publiques par conception ; le droit
 * d'envoyer un push tient à la clé de service, qui vit côté Edge Function.
 *
 * Sans configuration, ce fichier ne fait rien du tout : il n'est même jamais
 * enregistré, puisque l'application ne demande pas de jeton.
 */

const parametres = new URL(self.location).searchParams;

const config = {
  apiKey: parametres.get('apiKey'),
  appId: parametres.get('appId'),
  messagingSenderId: parametres.get('messagingSenderId'),
  projectId: parametres.get('projectId'),
};

/*
 * La version doit rester alignée sur celle de `firebase_core_web`
 * (`supportedFirebaseJsSdkVersion`). Un écart fait échouer l'enregistrement du
 * jeton en arrière-plan sans message clair. Procédure de mise à jour :
 * `docs/FIREBASE.md § Mettre à jour le SDK`.
 */
const VERSION_SDK = '12.19.0';

/* Destination par défaut quand la notification n'en porte pas. */
const ACCUEIL = '/';

/* Le message convenu avec `lib/features/notifications/data/pont_web.dart`. */
const TYPE_NAVIGATION = 'astreinte-sp/navigation';

const configComplete =
  config.apiKey && config.appId && config.messagingSenderId && config.projectId;

if (configComplete) {
  importScripts(
    `https://www.gstatic.com/firebasejs/${VERSION_SDK}/firebase-app-compat.js`,
  );
  importScripts(
    `https://www.gstatic.com/firebasejs/${VERSION_SDK}/firebase-messaging-compat.js`,
  );

  firebase.initializeApp(config);
  const messaging = firebase.messaging();

  /*
   * Message « data only » : le SDK n'affiche rien tout seul, c'est à nous de
   * le faire. Un message qui porte un bloc `notification` est affiché par le
   * SDK et ne passe pas ici.
   */
  messaging.onBackgroundMessage((payload) => {
    const donnees = payload.data || {};
    const titre = donnees.title || 'Astreinte SP';

    return self.registration.showNotification(titre, {
      body: donnees.body || '',
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      tag: donnees.tag || undefined,
      /* La destination voyage avec la notification : c'est elle qu'on ouvre. */
      data: { route: donnees.route || ACCUEIL },
    });
  });
}

/*
 * Le clic sur une notification, dans les deux cas :
 *
 * - l'application tourne déjà (onglet en arrière-plan, PWA minimisée) : on la
 *   ramène au premier plan et on lui poste la destination ;
 * - elle est fermée : on ouvre une fenêtre directement sur la destination.
 *   Le démarrage à froid la conserve grâce à `DestinationInitiale`
 *   (`lib/core/router/destination_initiale.dart`).
 */
self.addEventListener('notificationclick', (evenement) => {
  evenement.notification.close();

  const donnees = evenement.notification.data || {};
  const lien =
    donnees.route ||
    (donnees.FCM_MSG && donnees.FCM_MSG.data && donnees.FCM_MSG.data.route) ||
    ACCUEIL;
  const cible = new URL(lien, self.location.origin).href;

  evenement.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((fenetres) => {
        for (const fenetre of fenetres) {
          if (new URL(fenetre.url).origin !== self.location.origin) continue;
          if ('focus' in fenetre) {
            fenetre.postMessage({ type: TYPE_NAVIGATION, route: lien });
            return fenetre.focus();
          }
        }
        return self.clients.openWindow(cible);
      }),
  );
});
