// Le service worker des push, hors navigateur (ticket 074).
//
// Le script est chargé tel quel dans un contexte `vm` qui imite ce qu'un
// navigateur lui donne : `self.location` sous `push/`, `importScripts`, un
// SDK Firebase factice. Aucun réseau, aucune clé : on vérifie ce que le
// worker **calcule** — la racine de l'application un dossier au-dessus de
// lui, les destinations et les icônes qui s'y rattachent.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';

const RACINE = fileURLToPath(new URL('../../', import.meta.url));
const WORKER = readFileSync(`${RACINE}web/push/firebase-messaging-sw.js`, 'utf8');
const ANCIEN = readFileSync(`${RACINE}web/firebase-messaging-sw.js`, 'utf8');

const CONFIG = '?apiKey=cle&appId=1%3A1%3Aweb%3A1&messagingSenderId=1&projectId=essai';

/// Charge [source] comme un service worker servi à [adresse], enregistré sur
/// [portee] (par défaut, le dossier du script : ce que donne `register()`
/// sans option).
function charger(source, adresse, portee = new URL('./', adresse).href) {
  const ecouteurs = {};
  const scripts = [];
  const notifications = [];
  const fenetresOuvertes = [];
  let gestionnaireArrierePlan = null;
  const desinscriptions = [];
  const desabonnements = [];

  const self = {
    location: new URL(adresse),
    addEventListener: (type, rappel) => {
      ecouteurs[type] = rappel;
    },
    skipWaiting: () => {},
    registration: {
      scope: portee,
      showNotification: async (titre, options) => {
        notifications.push({titre, options});
      },
      unregister: async () => {
        desinscriptions.push(true);
        return true;
      },
      pushManager: {
        getSubscription: async () => ({
          unsubscribe: async () => {
            desabonnements.push(true);
            return true;
          },
        }),
      },
    },
    clients: {
      matchAll: async () => [],
      openWindow: async (cible) => {
        fenetresOuvertes.push(cible);
      },
    },
  };

  const firebase = {
    initializeApp: () => {},
    messaging: () => ({
      onBackgroundMessage: (rappel) => {
        gestionnaireArrierePlan = rappel;
      },
    }),
  };

  const contexte = vm.createContext({
    self,
    URL,
    firebase,
    importScripts: (url) => scripts.push(url),
  });
  vm.runInContext(source, contexte);

  return {
    contexte,
    ecouteurs,
    scripts,
    notifications,
    fenetresOuvertes,
    desinscriptions,
    desabonnements,
    arrierePlan: (payload) => gestionnaireArrierePlan(payload),
  };
}

/// Le déclenchement d'un clic de notification, attendu jusqu'au bout.
async function cliquer(worker, donnees) {
  let attente = Promise.resolve();
  worker.ecouteurs.notificationclick({
    notification: {data: donnees, close: () => {}},
    waitUntil: (promesse) => {
      attente = promesse;
    },
  });
  await attente;
}

test('sous push/, une destination interne vise la racine de l\'application', () => {
  const {contexte} = charger(WORKER, 'https://astreinte.test/push/firebase-messaging-sw.js');

  assert.equal(contexte.adresseInterne('/proposals'), 'https://astreinte.test/proposals');
  assert.equal(
    contexte.adresseInterne('/admin/planning'),
    'https://astreinte.test/admin/planning',
  );
});

test('un lien externe ou mal formé retombe sur l\'accueil', () => {
  const {contexte} = charger(WORKER, 'https://astreinte.test/push/firebase-messaging-sw.js');
  const accueil = 'https://astreinte.test/';

  for (const lien of [
    'https://ailleurs.test/piege',
    '//ailleurs.test/piege',
    '/\\ailleurs.test',
    'javascript:alert(1)',
    'proposals',
    undefined,
    42,
  ]) {
    assert.equal(contexte.adresseInterne(lien), accueil, `lien : ${String(lien)}`);
  }
});

test('sous un sous-chemin, tout reste sous le sous-chemin', () => {
  const {contexte} = charger(
    WORKER,
    'https://astreinte.test/caserne/push/firebase-messaging-sw.js',
  );

  assert.equal(
    contexte.adresseInterne('/proposals'),
    'https://astreinte.test/caserne/proposals',
  );
  assert.equal(contexte.adresseInterne('https://ailleurs.test/'), 'https://astreinte.test/caserne/');
});

test('l\'icône est celle de l\'application, pas un chemin sous push/', async () => {
  for (const [adresse, icone] of [
    ['https://astreinte.test/push/firebase-messaging-sw.js', '/icons/Icon-192.png'],
    ['https://astreinte.test/caserne/push/firebase-messaging-sw.js', '/caserne/icons/Icon-192.png'],
  ]) {
    const worker = charger(WORKER, adresse + CONFIG);
    await worker.arrierePlan({data: {title: 'Proposition', body: 'Samedi', route: '/proposals'}});

    const {options} = worker.notifications.at(-1);
    assert.equal(options.icon, icone);
    assert.equal(options.badge, icone);
    assert.equal(options.data.route, '/proposals');
  }
});

test('un clic, application fermée, ouvre la destination à la racine', async () => {
  const worker = charger(WORKER, `https://astreinte.test/push/firebase-messaging-sw.js${CONFIG}`);

  await cliquer(worker, {route: '/proposals'});
  await cliquer(worker, {FCM_MSG: {data: {route: '/astreintes'}}});
  await cliquer(worker, {route: 'https://ailleurs.test/'});

  assert.deepEqual(worker.fenetresOuvertes, [
    'https://astreinte.test/proposals',
    'https://astreinte.test/astreintes',
    'https://astreinte.test/',
  ]);
});

test('sans configuration, le worker ne charge rien', () => {
  const worker = charger(WORKER, 'https://astreinte.test/push/firebase-messaging-sw.js');
  assert.deepEqual(worker.scripts, []);
});

test('avec configuration, il charge le SDK à la version épinglée', () => {
  const worker = charger(WORKER, `https://astreinte.test/push/firebase-messaging-sw.js${CONFIG}`);
  const version = /const VERSION_SDK = '([^']+)'/.exec(WORKER)[1];
  assert.deepEqual(worker.scripts, [
    `https://www.gstatic.com/firebasejs/${version}/firebase-app-compat.js`,
    `https://www.gstatic.com/firebasejs/${version}/firebase-messaging-compat.js`,
  ]);
});

test('l\'ancien emplacement se désabonne puis se désinscrit, sans rien charger', async () => {
  const ancien = charger(
    ANCIEN,
    'https://astreinte.test/firebase-messaging-sw.js',
    'https://astreinte.test/firebase-cloud-messaging-push-scope',
  );
  assert.deepEqual(ancien.scripts, []);
  assert.ok(ancien.ecouteurs.install, 'il s\'active sans attendre');

  let attente = Promise.resolve();
  ancien.ecouteurs.activate({
    waitUntil: (promesse) => {
      attente = promesse;
    },
  });
  await attente;

  assert.equal(ancien.desabonnements.length, 1);
  assert.equal(ancien.desinscriptions.length, 1);
});

test('sur la portée de Flutter, l\'ancien emplacement ne fait rien', () => {
  // S'activer puis se désinscrire sur `/` emporterait le worker de Flutter.
  for (const [adresse, portee] of [
    [`https://astreinte.test/firebase-messaging-sw.js${CONFIG}`, 'https://astreinte.test/'],
    ['https://astreinte.test/caserne/firebase-messaging-sw.js', 'https://astreinte.test/caserne/'],
  ]) {
    const ancien = charger(ANCIEN, adresse, portee);
    assert.deepEqual(Object.keys(ancien.ecouteurs), [], portee);
    assert.deepEqual(ancien.scripts, []);
  }
});

test('le SDK des tests est à la version épinglée dans le worker', () => {
  const version = /const VERSION_SDK = '([^']+)'/.exec(WORKER)[1];
  const paquet = JSON.parse(
    readFileSync(new URL('./node_modules/firebase/package.json', import.meta.url), 'utf8'),
  );
  const declare = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8'))
    .devDependencies.firebase;
  assert.equal(declare, version, 'package.json → devDependencies.firebase');
  assert.equal(paquet.version, version, 'node_modules/firebase installé');
});
