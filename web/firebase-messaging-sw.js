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

/*
 * Le service worker est enregistré à côté de l'application, quel que soit le
 * chemin où celle-ci est servie. Tout se dérive donc de sa propre adresse, et
 * rien n'est figé à la racine : l'hébergement du ticket 032 peut servir la PWA
 * sous un sous-chemin sans que ce fichier bouge.
 */
const PORTEE = new URL('./', self.location).pathname;

/*
 * L'application sert ses routes dans le **chemin** de l'adresse, sans dièse
 * (ticket 046 : le fragment appartient au fournisseur d'authentification, qui
 * y dépose ses jetons). C'est la forme que suit déjà le lien d'invitation
 * (`APP_INVITE_PATH` = `/invite/{token}`). Une notification ouverte
 * application fermée doit produire la même forme, sinon elle tombe sur une
 * page introuvable — et c'est le seul mode de réception qui compte vraiment
 * pour un pompier à qui on propose une astreinte.
 */
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
      icon: `${PORTEE}icons/Icon-192.png`,
      badge: `${PORTEE}icons/Icon-192.png`,
      tag: donnees.tag || undefined,
      /* La destination voyage avec la notification : c'est elle qu'on ouvre. */
      data: { route: donnees.route || ACCUEIL },
    });
  });
}

/*
 * L'adresse complète d'une destination interne.
 *
 * Le chemin de l'application est collé à sa portée — `/proposals` sous une PWA
 * servie à la racine, `/sous-chemin/proposals` ailleurs. Aucun dièse : le
 * routeur lit le chemin (ticket 046).
 *
 * Tout ce qui n'est pas un chemin de l'application — adresse absolue, adresse
 * de protocole, chemin à double barre oblique, qui est une autorité — retombe
 * sur l'accueil : une notification ne doit jamais pouvoir ouvrir autre chose
 * que cette application.
 */
function adresseInterne(lien) {
  const interne =
    typeof lien === 'string' &&
    lien.startsWith('/') &&
    !lien.startsWith('//') &&
    !lien.includes('\\');

  const accueil = new URL(`${PORTEE}${ACCUEIL.slice(1)}`, self.location.origin);
  if (!interne) return accueil.href;

  const cible = new URL(`${PORTEE}${lien.slice(1)}`, self.location.origin);
  return cible.origin === self.location.origin ? cible.href : accueil.href;
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
  const cible = adresseInterne(lien);

  evenement.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((fenetres) => {
        for (const fenetre of fenetres) {
          if (new URL(fenetre.url).origin !== self.location.origin) continue;
          if ('focus' in fenetre) {
            /*
             * L'application est déjà ouverte : on lui poste le chemin interne
             * (`/proposals`), qu'elle sait traduire et filtrer
             * (`destination_push.dart`). Pas d'adresse complète ici : elle
             * n'aurait rien à en faire.
             */
            fenetre.postMessage({ type: TYPE_NAVIGATION, route: lien });
            return fenetre.focus();
          }
        }
        return self.clients.openWindow(cible);
      }),
  );
});
