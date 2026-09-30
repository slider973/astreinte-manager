// Un serveur statique qui rejoue `vercel.json` sur une construction Flutter
// (ticket 074), pour que le test de bout en bout voie les en-têtes de la
// production — `Cross-Origin-Embedder-Policy` compris, qui s'applique aussi
// aux `importScripts` du service worker.
//
// Une seule entorse, et voulue : `Content-Encoding` et `Vary` ne sont pas
// posés. La CI construit par `flutter build web --wasm`, sans la compression
// brotli de `scripts/build_web.sh` ; annoncer `br` sur des octets en clair
// empêcherait le moteur de démarrer, et ce test ne porte pas là-dessus
// (`scripts/servir_web.py` le fait, pour une construction de production).
import {createServer} from 'node:http';
import {readFile, stat} from 'node:fs/promises';
import {extname, join, normalize, sep} from 'node:path';

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.symbols': 'text/plain; charset=utf-8',
};

const ECARTES = new Set(['content-encoding', 'vary']);

/// La source de `vercel.json` (`/(.*)`, `/canvaskit/(.*)`…) en expression
/// régulière. Vercel lit ces sources comme des motifs `path-to-regexp` ; les
/// nôtres n'utilisent que des groupes `(.*)` et des points littéraux.
function motif(source) {
  const morceaux = source
    .split('(.*)')
    .map((morceau) => morceau.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  return new RegExp(`^${morceaux.join('(.*)')}$`);
}

function entetesPour(vercel, chemin) {
  const entetes = {};
  for (const regle of vercel.headers ?? []) {
    if (!motif(regle.source).test(chemin)) continue;
    for (const {key, value} of regle.headers) {
      if (!ECARTES.has(key.toLowerCase())) entetes[key] = value;
    }
  }
  return entetes;
}

async function fichier(racine, chemin) {
  const cible = normalize(join(racine, decodeURIComponent(chemin)));
  if (cible !== racine && !cible.startsWith(racine + sep)) return null;
  try {
    const info = await stat(cible);
    return info.isFile() ? cible : null;
  } catch {
    return null;
  }
}

/// Sert [racine] sur 127.0.0.1, port libre. Rend `{origine, fermer}`.
export async function servir(racine, vercel) {
  const serveur = createServer(async (requete, reponse) => {
    const chemin = new URL(requete.url, 'http://local').pathname;
    // La réécriture de `vercel.json` : toute adresse inconnue rend
    // `index.html`, comme en production.
    const trouve =
      (await fichier(racine, chemin)) ?? join(racine, 'index.html');
    const corps = await readFile(trouve);
    reponse.writeHead(200, {
      ...entetesPour(vercel, chemin),
      'Content-Type': TYPES[extname(trouve)] ?? 'application/octet-stream',
      'Content-Length': corps.length,
    });
    reponse.end(corps);
  });
  await new Promise((resolu) => serveur.listen(0, '127.0.0.1', resolu));
  const {port} = serveur.address();
  return {
    origine: `http://127.0.0.1:${port}`,
    fermer: () => new Promise((resolu) => serveur.close(resolu)),
  };
}
