// Mesure le coût d'une transition de route : du clic au départ de la première
// requête de l'écran (ticket 042).
//
//   flutter build web --profile --no-web-resources-cdn \
//       --dart-define-from-file=env/dev.json
//   supabase start                       # la base de dev, avec son seed
//   node --experimental-websocket scripts/mesurer_transition.mjs [build/web] [tours] [bridage]
//
// `--experimental-websocket` : Node 20 n'expose `WebSocket` qu'avec ce drapeau,
// et c'est par là que passe le protocole de débogage de Chrome. Aucune
// dépendance npm — le dépôt n'en a pas et ce script n'en introduit pas.
//
// Ce qu'il fait, dans un vrai Chrome sans interface :
//
//   1. sert la construction sur 127.0.0.1 ;
//   2. ouvre une session avec un compte du seed (`admin@caserne-a.test`) et la
//      dépose dans `localStorage` là où `supabase_flutter` la relit, pour
//      mesurer une application connectée sans jouer la saisie du code ;
//   3. pose une instrumentation **avant** le démarrage de l'application :
//      `pointerdown`, `pushState`, `fetch` et les tâches longues, tous
//      horodatés par `performance.now()` — une seule horloge, aucune
//      conversion ;
//   4. par tour : recharge l'accueil, attend le calme, clique « Admin » puis
//      « Membres », et relève pour chaque transition le relâchement du clic, le
//      changement d'URL et le départ de la première requête vers l'API.
//
// Deux pièges rencontrés en écrivant ce script, et gardés ici :
//
//   - **repartir de l'accueil à chaque tour**. Le tour précédent laisse l'URL
//     sur `/#/admin/membres` : recharger là mesurerait une autre transition que
//     celle qu'on croit, avec d'autres données déjà en cache ;
//   - **compter les requêtes**. Un préchargement mal retenu fait partir chaque
//     requête deux fois ; le compte par transition doit rester identique avant
//     et après, et le script l'affiche.
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {mkdtempSync} from 'node:fs';
import {readFile, stat} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, extname, normalize, dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const RACINE_PROJET = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SORTIE = resolve(process.argv[2] ?? join(RACINE_PROJET, 'build/web'));
const TOURS = Number(process.argv[3] ?? 5);
const BRIDAGE = Number(process.argv[4] ?? 1);
const PORT = 8097;
const PORT_DEBOGAGE = 9333;
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const env = JSON.parse(readFileSync(join(RACINE_PROJET, 'env/dev.json'), 'utf8'));
const API = env.SUPABASE_URL;

// Le compte de mesure vient de l'environnement, jamais du dépôt : même un mot de
// passe de jeu de test n'a pas sa place dans un fichier versionné, et l'analyse
// de secrets de l'intégration continue le refuse à juste titre.
//   MESURE_EMAIL=… MESURE_MOTDEPASSE=… node scripts/mesurer_transition.mjs
const COMPTE = process.env.MESURE_EMAIL ?? 'admin@caserne-a.test';
const MOT_DE_PASSE = process.env.MESURE_MOTDEPASSE;
if (!MOT_DE_PASSE) {
  console.error(
    "MESURE_MOTDEPASSE manquant. Le mot de passe du compte de mesure se passe par\n" +
    "l'environnement : MESURE_MOTDEPASSE=<le mot de passe du seed local> node scripts/mesurer_transition.mjs",
  );
  process.exit(1);
}

// Les deux transitions mesurées, et où cliquer dans une fenêtre 1440 × 900 :
// la destination « Admin » du rail, puis l'icône « Membres » de la barre.
const TRANSITIONS = [
  {nom: 'accueil → matrice', x: 46, y: 348, route: '/admin/planning'},
  {nom: 'matrice → membres', x: 1272, y: 28, route: '/admin/membres'},
];

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript',
  '.mjs': 'application/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.bin': 'application/octet-stream',
};

// Instrumentation posée avant le démarrage de l'application.
const INSTRUMENTATION = `(() => {
  const marques = [];
  globalThis.__marques = marques;
  const t = () => performance.now();
  for (const nom of ['pointerdown', 'pointerup']) {
    addEventListener(nom, () => marques.push({type: nom, t: t()}), true);
  }
  for (const nom of ['pushState', 'replaceState']) {
    const original = history[nom].bind(history);
    history[nom] = function (etat, titre, url) {
      marques.push({type: nom, t: t(), url: String(url)});
      return original(etat, titre, url);
    };
  }
  const fetchOriginal = globalThis.fetch;
  globalThis.fetch = function (entree) {
    const url = typeof entree === 'string' ? entree : (entree && entree.url) || String(entree);
    const marque = {type: 'fetch', t: t(), url, fin: null, statut: null};
    marques.push(marque);
    return fetchOriginal.apply(this, arguments).then(
      (r) => { marque.fin = t(); marque.statut = r.status; return r; },
      (e) => { marque.fin = t(); marque.statut = 'échec'; throw e; },
    );
  };
  try {
    new PerformanceObserver((liste) => {
      for (const e of liste.getEntries()) marques.push({type: 'tache', t: e.startTime, duree: e.duration});
    }).observe({entryTypes: ['longtask']});
  } catch {}
})();`;

const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

function servir(racine, port) {
  const serveur = createServer(async (req, res) => {
    const chemin = decodeURIComponent(req.url.split('?')[0]);
    let fichier = join(racine, normalize(chemin));
    try {
      if ((await stat(fichier)).isDirectory()) fichier = join(fichier, 'index.html');
    } catch {
      fichier = join(racine, 'index.html'); // go_router résout côté client
    }
    try {
      const octets = await readFile(fichier);
      res.writeHead(200, {
        'Content-Type': TYPES[extname(fichier)] ?? 'application/octet-stream',
        'Content-Length': octets.length,
        'Cache-Control': 'no-store',
      });
      res.end(octets);
    } catch (erreur) {
      res.writeHead(404).end(String(erreur));
    }
  });
  return new Promise((r) => serveur.listen(port, '127.0.0.1', () => r(serveur)));
}

async function session() {
  const reponse = await fetch(`${API}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: {apikey: env.SUPABASE_ANON_KEY, 'Content-Type': 'application/json'},
    body: JSON.stringify({email: COMPTE, password: MOT_DE_PASSE}),
  });
  if (!reponse.ok) {
    throw new Error(
      `connexion impossible (${reponse.status}). La base de dev tourne-t-elle ? ` +
        `\`supabase start\` puis \`supabase db reset\`.`,
    );
  }
  return reponse.json();
}

class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.id = 0;
    this.attente = new Map();
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      const p = this.attente.get(msg.id);
      if (!p) return;
      this.attente.delete(msg.id);
      msg.error ? p.rej(new Error(msg.error.message)) : p.res(msg.result);
    });
  }

  static async ouvrir(url) {
    const ws = new WebSocket(url);
    await new Promise((res, rej) => {
      ws.addEventListener('open', res, {once: true});
      ws.addEventListener('error', rej, {once: true});
    });
    return new Cdp(ws);
  }

  envoyer(methode, params = {}, sessionId) {
    const id = ++this.id;
    return new Promise((res, rej) => {
      this.attente.set(id, {res, rej});
      this.ws.send(JSON.stringify({id, method: methode, params, ...(sessionId ? {sessionId} : {})}));
    });
  }
}

async function lancerChrome() {
  const profil = mkdtempSync(join(tmpdir(), 'chrome-mesure-'));
  const processus = spawn(
    CHROME,
    [
      '--headless=new',
      `--remote-debugging-port=${PORT_DEBOGAGE}`,
      `--user-data-dir=${profil}`,
      '--window-size=1440,900',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-extensions',
      '--disable-background-networking',
      '--disable-component-update',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      'about:blank',
    ],
    {stdio: ['ignore', 'ignore', 'ignore']},
  );
  for (let essai = 0; essai < 100; essai++) {
    try {
      const version = await (await fetch(`http://127.0.0.1:${PORT_DEBOGAGE}/json/version`)).json();
      return {processus, version};
    } catch {
      await dormir(100);
    }
  }
  throw new Error('Chrome ne répond pas sur le port de débogage.');
}

const mediane = (valeurs) => {
  const v = [...valeurs].sort((a, b) => a - b);
  return v.length % 2 ? v[(v.length - 1) / 2] : (v[v.length / 2 - 1] + v[v.length / 2]) / 2;
};

async function mesurer() {
  const serveur = await servir(SORTIE, PORT);
  const jeton = await session();
  const chrome = await lancerChrome();
  const cdp = await Cdp.ouvrir(chrome.version.webSocketDebuggerUrl);
  const {targetId} = await cdp.envoyer('Target.createTarget', {url: 'about:blank'});
  const {sessionId} = await cdp.envoyer('Target.attachToTarget', {targetId, flatten: true});
  const envoyer = (m, p) => cdp.envoyer(m, p, sessionId);

  await envoyer('Page.enable');
  await envoyer('Runtime.enable');
  await envoyer('Emulation.setDeviceMetricsOverride', {
    width: 1440,
    height: 900,
    deviceScaleFactor: 1,
    mobile: false,
  });
  await envoyer('Page.navigate', {url: `http://127.0.0.1:${PORT}/`});
  await dormir(2000);
  // `sb-127-auth-token` : la clé que `supabase_flutter` dérive de l'hôte de
  // `SUPABASE_URL` (`Supabase.initialize`), et la session telle qu'il l'écrit.
  await envoyer('Runtime.evaluate', {
    expression: `localStorage.setItem('sb-127-auth-token', ${JSON.stringify(JSON.stringify(jeton))}); 'ok'`,
  });
  await envoyer('Page.addScriptToEvaluateOnNewDocument', {source: INSTRUMENTATION});

  const marques = async () => {
    const r = await envoyer('Runtime.evaluate', {
      expression: 'JSON.stringify(globalThis.__marques ?? [])',
      returnByValue: true,
    });
    return JSON.parse(r.result.value);
  };

  const maintenant = async () =>
    (await envoyer('Runtime.evaluate', {expression: 'performance.now()', returnByValue: true}))
      .result.value;

  // Attend qu'il ne se passe plus rien : ni requête, ni tâche longue.
  async function calme(repos = 1500, plafond = 30000) {
    const debut = Date.now();
    let precedent = 0;
    for (;;) {
      const liste = await marques();
      const actifs = liste.filter((m) => m.type === 'fetch' || m.type === 'tache');
      const fin = actifs.length ? Math.max(...actifs.map((m) => m.t + (m.duree ?? 0))) : 0;
      if (fin === precedent && fin > 0 && (await maintenant()) - fin > repos) return liste;
      precedent = fin;
      if (Date.now() - debut > plafond) return liste;
      await dormir(250);
    }
  }

  async function cliquer(x, y) {
    await envoyer('Input.dispatchMouseEvent', {type: 'mouseMoved', x, y, button: 'none'});
    await envoyer('Input.dispatchMouseEvent', {type: 'mousePressed', x, y, button: 'left', clickCount: 1});
    await dormir(30);
    await envoyer('Input.dispatchMouseEvent', {type: 'mouseReleased', x, y, button: 'left', clickCount: 1});
  }

  const releves = [];
  for (let tour = 0; tour < TOURS; tour++) {
    await envoyer('Emulation.setCPUThrottlingRate', {rate: 1});
    // Repartir de l'accueil : le tour précédent a laissé l'URL ailleurs.
    await envoyer('Page.navigate', {url: `http://127.0.0.1:${PORT}/#/`});
    await dormir(200);
    await envoyer('Page.reload');
    await dormir(1200);
    await calme();
    await envoyer('Emulation.setCPUThrottlingRate', {rate: BRIDAGE});
    await dormir(300);

    for (const transition of TRANSITIONS) {
      const depart = (await marques()).length;
      await cliquer(transition.x, transition.y);
      await dormir(400);
      const nouvelles = (await calme()).slice(depart);

      const relache = nouvelles.find((m) => m.type === 'pointerup');
      const route = nouvelles.find(
        (m) => (m.type === 'pushState' || m.type === 'replaceState') && m.url.includes(transition.route),
      );
      const requetes = nouvelles.filter(
        (m) => m.type === 'fetch' && m.url.startsWith(API) && m.t >= relache?.t,
      );
      if (!relache) throw new Error(`clic non reçu (${transition.nom})`);
      if (!route) throw new Error(`le clic n'a pas changé de route (${transition.nom})`);
      if (requetes.length === 0) throw new Error(`aucune requête après ${transition.nom}`);

      releves.push({
        tour,
        nom: transition.nom,
        url: requetes[0].url.replace(API, ''),
        relacheVersRoute: route.t - relache.t,
        routeVersRequete: requetes[0].t - route.t,
        relacheVersRequete: requetes[0].t - relache.t,
        requetes: requetes.length,
      });
    }
    await envoyer('Emulation.setCPUThrottlingRate', {rate: 1});
    const dernier = releves.slice(-TRANSITIONS.length);
    console.log(
      `tour ${tour + 1}/${TOURS} : ` +
        dernier.map((r) => `${r.nom} ${r.relacheVersRequete.toFixed(0)} ms`).join(' | '),
    );
  }

  console.log(`\n${SORTIE} — ${TOURS} tours — processeur bridé ×${BRIDAGE}`);
  for (const transition of TRANSITIONS) {
    const tours = releves.filter((r) => r.nom === transition.nom);
    const ligne = (cle) => {
      const valeurs = tours.map((r) => r[cle]);
      return `${mediane(valeurs).toFixed(0).padStart(5)} ms  (min ${Math.min(...valeurs).toFixed(0)}, max ${Math.max(...valeurs).toFixed(0)})`;
    };
    console.log(`\n${transition.nom}  →  ${tours[0].url.slice(0, 60)}`);
    console.log(`  relâchement → changement de route : ${ligne('relacheVersRoute')}`);
    console.log(`  changement de route → requête     : ${ligne('routeVersRequete')}`);
    console.log(`  relâchement → requête             : ${ligne('relacheVersRequete')}`);
    console.log(`  requêtes par transition           : ${tours.map((r) => r.requetes).join(' ')}`);
  }

  chrome.processus.kill();
  serveur.close();
  process.exit(0);
}

mesurer().catch((erreur) => {
  console.error(`erreur : ${erreur.message}`);
  process.exit(1);
});
