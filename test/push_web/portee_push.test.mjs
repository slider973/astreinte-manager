// Le service worker des push, dans un vrai Chrome, contre la PWA construite
// (ticket 074).
//
//   flutter build web --wasm --dart-define-from-file=env/dev.json
//   cd test/push_web && npm ci && npm test
//
// **Le défaut qu'il garde fermé.** Enregistré à la racine, le worker Firebase
// partageait la portée `/` avec `flutter_service_worker.js` : il restait en
// attente derrière lui, et un push arrivait au worker de Flutter, qui n'a pas
// de gestionnaire `push`. Le jeton s'obtenait, rien n'arrivait jamais.
//
// Ce que ce test fait, dans l'ordre où l'application le vit :
//
//   1. il sert `build/web` avec les en-têtes de `vercel.json` et attend que le
//      worker de Flutter tienne `/` — la condition du défaut ;
//   2. il enregistre le worker des push **comme le fait
//      `firebase_messaging_web`** : `navigator.serviceWorker.register(chemin)`,
//      sans portée, avec le chemin relatif que rend
//      `cheminServiceWorkerPush` (épinglé par
//      `test/features/notifications/messagerie_push_test.dart`) ;
//   3. il vérifie que ce worker est **actif** sur une portée qui n'est pas `/`,
//      sans rien en attente ;
//   4. il livre un push par le protocole de débogage de Chrome
//      (`ServiceWorker.deliverPushMessage`) et attend que la page reçoive le
//      relais du SDK (`isFirebaseMessaging`) ;
//   5. il vérifie que l'ancien emplacement se désinscrit de lui-même, sauf
//      sur `/`, où il reste inerte et laisse la place à Flutter.
//
// **Sans FCM, sans clé.** La configuration est factice : elle suffit au SDK
// pour s'initialiser dans le worker, pas pour obtenir un jeton, et aucun jeton
// n'est demandé. Le SDK lui-même n'est pas pris chez Google : les deux
// scripts `compat` sont lus dans le paquet npm `firebase`, verrouillé par
// `package-lock.json` à la version épinglée dans le worker (`VERSION_SDK`,
// vérifié par `service_worker.test.mjs`), et servis à la place de
// `www.gstatic.com`. Le test lui-même ne télécharge rien. Toute autre requête hors de 127.0.0.1 est coupée, et le
// test échoue si l'une d'elles visait FCM ou Firebase.
import {after, before, test} from 'node:test';
import assert from 'node:assert/strict';
import {existsSync, readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright-core';

import {servir} from './serveur.mjs';

const RACINE = fileURLToPath(new URL('../../', import.meta.url));
const CONSTRUCTION = process.env.CONSTRUCTION_WEB ?? join(RACINE, 'build/web');
const DELAI = 60_000;

/// Ce que `cheminServiceWorkerPush` rend, avec une configuration factice.
const CHEMIN_WORKER =
  'push/firebase-messaging-sw.js?apiKey=cle-factice&appId=1%3A1%3Aweb%3A1' +
  '&messagingSenderId=1&projectId=essai-074';

let serveur;
let navigateur;
let contexte;
let page;
const horsOrigine = [];

/// Les deux scripts du SDK, lus dans le paquet npm installé par `npm ci`.
function sdkFirebase() {
  const scripts = ['firebase-app-compat.js', 'firebase-messaging-compat.js'];
  return Object.fromEntries(
    scripts.map((nom) => [
      nom,
      readFileSync(new URL(`./node_modules/firebase/${nom}`, import.meta.url)),
    ]),
  );
}

before(async () => {
  assert.ok(
    existsSync(join(CONSTRUCTION, 'index.html')),
    `${CONSTRUCTION} absent : construire d'abord la PWA ` +
      '(flutter build web --wasm --dart-define-from-file=env/dev.json).',
  );
  assert.ok(
    existsSync(join(CONSTRUCTION, 'push/firebase-messaging-sw.js')),
    'la construction ne contient pas push/firebase-messaging-sw.js',
  );

  const sdk = sdkFirebase();
  const vercel = JSON.parse(readFileSync(join(RACINE, 'vercel.json'), 'utf8'));
  serveur = await servir(CONSTRUCTION, vercel);

  const executable = process.env.CHROME_EXECUTABLE;
  navigateur = await chromium.launch(
    executable ? {executablePath: executable} : {channel: 'chrome'},
  );
  contexte = await navigateur.newContext();
  await contexte.grantPermissions(['notifications'], {origin: serveur.origine});

  // Les routes posées en dernier passent en premier : d'abord tout couper,
  // puis laisser passer le SDK, servi depuis le paquet npm.
  await contexte.route(
    (url) => url.hostname !== '127.0.0.1',
    (route) => {
      horsOrigine.push(route.request().url());
      return route.abort();
    },
  );
  await contexte.route('https://www.gstatic.com/firebasejs/**', (route) => {
    const nom = new URL(route.request().url()).pathname.split('/').pop();
    const corps = sdk[nom];
    if (!corps) return route.abort();
    return route.fulfill({
      status: 200,
      contentType: 'text/javascript',
      // Ce que répond `www.gstatic.com` : sans lui, l'isolation de la page
      // (`Cross-Origin-Embedder-Policy: require-corp`) refuserait le script.
      headers: {'Cross-Origin-Resource-Policy': 'cross-origin'},
      body: corps,
    });
  });

  page = await contexte.newPage();
  await page.goto(`${serveur.origine}/`);
});

after(async () => {
  await navigateur?.close();
  await serveur?.fermer();
});

/// Attend, côté Node, qu'une fonction de la page rende vrai.
///
/// Pas `page.waitForFunction` : il tient la promesse d'un prédicat `async`
/// pour une valeur vraie et rend la main tout de suite. Les enregistrements
/// de service worker ne se lisent qu'en asynchrone.
async function attendre(predicat, argument, delai = DELAI) {
  const limite = Date.now() + delai;
  while (Date.now() < limite) {
    if (await page.evaluate(predicat, argument)) return;
    await new Promise((resolu) => setTimeout(resolu, 100));
  }
  assert.fail(`condition jamais remplie en ${delai} ms : ${predicat}`);
}

test('le worker de Flutter tient la portée / — la condition du défaut', {timeout: DELAI}, async () => {
  await attendre(async () => {
    const racine = await navigator.serviceWorker.getRegistration('/');
    return racine?.active?.scriptURL.includes('flutter_service_worker.js') ?? false;
  });
});

test('le worker des push est actif sur sa propre portée, et reçoit un push', {timeout: DELAI}, async () => {
  const enregistrement = await page.evaluate(async (chemin) => {
    window.messagesPush = [];
    navigator.serviceWorker.addEventListener('message', (evenement) => {
      window.messagesPush.push(evenement.data);
    });

    // Exactement l'appel de `firebase_messaging_web` (`getToken`) : un
    // chemin relatif, aucune portée.
    const inscrit = await navigator.serviceWorker.register(chemin);
    const worker = inscrit.installing ?? inscrit.waiting ?? inscrit.active;
    // Le défaut se voit ici : un worker qui ne s'active jamais. On l'attend
    // quinze secondes, puis on rend l'état tel quel pour que l'échec le dise.
    if (worker.state !== 'activated') {
      await Promise.race([
        new Promise((resolu) => {
          worker.addEventListener('statechange', () => {
            if (worker.state === 'activated' || worker.state === 'redundant') {
              resolu();
            }
          });
        }),
        new Promise((resolu) => setTimeout(resolu, 15_000)),
      ]);
    }
    const racine = await navigator.serviceWorker.getRegistration('/');
    return {
      portee: inscrit.scope,
      actif: inscrit.active?.scriptURL ?? null,
      etat: inscrit.active?.state ?? null,
      enAttente: inscrit.waiting?.scriptURL ?? null,
      racine: racine?.active?.scriptURL ?? null,
    };
  }, CHEMIN_WORKER);

  assert.notEqual(enregistrement.portee, `${serveur.origine}/`, 'pas la portée de Flutter');
  assert.equal(enregistrement.portee, `${serveur.origine}/push/`);
  assert.equal(enregistrement.enAttente, null, 'rien n\'attend derrière lui');
  assert.equal(enregistrement.etat, 'activated', 'le worker des push est actif');
  assert.ok(
    enregistrement.actif.startsWith(`${serveur.origine}/push/firebase-messaging-sw.js?`),
    enregistrement.actif,
  );
  assert.ok(
    enregistrement.racine.includes('flutter_service_worker.js'),
    'le worker de Flutter garde la racine',
  );

  // Le push, livré par Chrome comme s'il venait du service push.
  const cdp = await contexte.newCDPSession(page);
  const portees = new Map();
  cdp.on('ServiceWorker.workerRegistrationUpdated', ({registrations}) => {
    for (const {scopeURL, registrationId, isDeleted} of registrations) {
      if (!isDeleted) portees.set(scopeURL, registrationId);
    }
  });
  await cdp.send('ServiceWorker.enable');
  const debut = Date.now();
  while (!portees.has(enregistrement.portee) && Date.now() - debut < 10_000) {
    await new Promise((resolu) => setTimeout(resolu, 100));
  }
  const registrationId = portees.get(enregistrement.portee);
  assert.ok(registrationId, 'enregistrement introuvable par le protocole de débogage');

  // La forme d'un message FCM : `notification` et `data`, comme l'envoie
  // `supabase/functions/_shared/fcm.ts`.
  await cdp.send('ServiceWorker.deliverPushMessage', {
    origin: serveur.origine,
    registrationId,
    data: JSON.stringify({
      from: '1',
      fcmMessageId: 'essai-074',
      notification: {title: 'Proposition d\'astreinte', body: 'Samedi 4 octobre'},
      data: {route: '/proposals'},
    }),
  });

  await attendre(
    () => window.messagesPush.some((message) => message?.isFirebaseMessaging),
    null,
    15_000,
  );
  const recu = await page.evaluate(() =>
    window.messagesPush.find((message) => message?.isFirebaseMessaging),
  );
  assert.equal(recu.messageType, 'push-received');
  assert.equal(recu.data.route, '/proposals');
  assert.equal(recu.notification.title, 'Proposition d\'astreinte');
});

test('l\'ancien emplacement se désinscrit de lui-même', {timeout: DELAI}, async () => {
  // Ce que le SDK enregistrait seul quand `deleteToken()` précédait
  // `getToken()` : l'ancien script, sans configuration, sur sa portée par
  // défaut.
  const reste = await page.evaluate(async () => {
    const portee = '/firebase-cloud-messaging-push-scope';
    await navigator.serviceWorker.register('firebase-messaging-sw.js', {scope: portee});
    const limite = Date.now() + 15_000;
    while (Date.now() < limite) {
      const enregistrements = await navigator.serviceWorker.getRegistrations();
      if (!enregistrements.some((e) => e.scope.endsWith(portee))) break;
      await new Promise((resolu) => setTimeout(resolu, 100));
    }
    const enregistrements = await navigator.serviceWorker.getRegistrations();
    return enregistrements.map((e) => new URL(e.scope).pathname).sort();
  });

  assert.deepEqual(reste, ['/', '/push/'], 'seuls Flutter et le worker des push restent');
});

test('un worker Firebase en attente sur / ne déloge pas Flutter', {timeout: DELAI}, async () => {
  // L'état des navigateurs passés par une version d'avant le 074 : une page
  // contrôlée par le worker de Flutter, et l'ancien script, avec sa
  // configuration, enregistré sans portée — donc sur `/`, derrière lui.
  await page.reload();
  await attendre(() => navigator.serviceWorker.controller !== null);
  const avant = await page.evaluate(async (chemin) => {
    const inscrit = await navigator.serviceWorker.register(chemin);
    const worker = inscrit.installing ?? inscrit.waiting;
    if (worker && worker.state === 'installing') {
      await Promise.race([
        new Promise((resolu) => worker.addEventListener('statechange', resolu)),
        new Promise((resolu) => setTimeout(resolu, 10_000)),
      ]);
    }
    // Le temps qu'un worker qui s'activerait et se désinscrirait le fasse.
    await new Promise((resolu) => setTimeout(resolu, 1_000));
    const racine = await navigator.serviceWorker.getRegistration('/');
    return {
      portee: inscrit.scope,
      racineActive: racine?.active?.scriptURL ?? null,
      racineEnAttente: racine?.waiting?.scriptURL ?? null,
    };
  }, CHEMIN_WORKER.replace('push/', ''));

  assert.equal(avant.portee, `${serveur.origine}/`);
  assert.ok(
    avant.racineActive?.includes('flutter_service_worker.js'),
    `Flutter doit rester actif sur / : ${avant.racineActive}`,
  );
  assert.ok(
    avant.racineEnAttente?.includes('/firebase-messaging-sw.js'),
    `l'ancien worker attend, inerte : ${avant.racineEnAttente}`,
  );

  // Au lancement suivant, le chargeur de Flutter reprend la place.
  await page.reload();
  await attendre(async () => {
    const racine = await navigator.serviceWorker.getRegistration('/');
    return (
      (racine?.active?.scriptURL.includes('flutter_service_worker.js') ?? false) &&
      !(racine?.waiting?.scriptURL.includes('firebase-messaging-sw.js') ?? false) &&
      navigator.serviceWorker.controller !== null
    );
  });
  const portees = await page.evaluate(async () =>
    (await navigator.serviceWorker.getRegistrations())
      .map((e) => new URL(e.scope).pathname)
      .sort(),
  );
  assert.deepEqual(portees, ['/', '/push/']);
});

test('aucune requête vers FCM ni vers Firebase', () => {
  // `*.googleapis.com` : FCM, l'enregistrement des jetons, les installations
  // Firebase. Le SDK, lui, a été servi depuis le paquet npm.
  const firebase = horsOrigine.filter((url) => /googleapis\.com|firebase/i.test(url));
  assert.deepEqual(firebase, []);
});
