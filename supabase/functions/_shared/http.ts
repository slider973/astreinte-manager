// Réponses HTTP communes aux Edge Functions.
//
// Une seule forme d'erreur pour toute l'API : { error: { code, message, ...détails } }.
// `code` est stable et destiné au code Flutter ; `message` est en français et
// affichable tel quel si l'app n'a pas de texte plus précis.

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const JSON_HEADERS = {
  ...CORS_HEADERS,
  "Content-Type": "application/json; charset=utf-8",
  // Une réponse d'invitation ne se met jamais en cache : elle porte l'état d'un jeton.
  "Cache-Control": "no-store",
};

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

export function errorResponse(
  status: number,
  code: string,
  message: string,
  details: Record<string, unknown> = {},
): Response {
  return jsonResponse({ error: { code, message, ...details } }, status);
}

export function preflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  return null;
}

export async function readJsonBody(
  req: Request,
): Promise<Record<string, unknown> | null> {
  try {
    const body = await req.json();
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      return null;
    }
    return body as Record<string, unknown>;
  } catch {
    return null;
  }
}

/**
 * Taille maximale d'un corps de requête accepté sans authentification, en
 * octets. Un événement Stripe réel dépasse rarement 100 ko.
 */
export const TAILLE_CORPS_MAX = 1024 * 1024;

/**
 * Lit le corps **brut** d'une requête, en refusant au-delà de [max] octets.
 *
 * `req.text()` lit tout ce qu'on lui envoie. Sur une fonction publique — et
 * `stripe-webhook` est la seule du projet —, cela veut dire qu'un anonyme qui
 * connaît l'adresse peut faire allouer autant de mémoire qu'il veut, **avant**
 * toute vérification de signature, puis nous faire calculer l'empreinte HMAC de
 * l'ensemble. Le plafond vient donc avant la lecture, pas après.
 *
 * Deux barrières, parce qu'une seule ne suffit pas : l'en-tête `Content-Length`
 * n'est pas obligatoire — un envoi en `chunked` n'en a pas — et il peut mentir.
 * Le compte réel des octets lus est ce qui tranche ; l'en-tête ne sert qu'à
 * refuser sans rien lire quand il est présent et honnête.
 *
 * Rend `null` quand le plafond est franchi, **après avoir vidé le reste sans
 * rien en garder**. Se contenter d'annuler le flux laisse l'émetteur en train
 * d'écrire dans une connexion que plus personne ne lit : la passerelle coupe, et
 * l'appelant voit une erreur réseau au lieu du `413` qu'on vient de composer.
 * Vider coûte de la bande passante, jamais de la mémoire — c'est exactement ce
 * qu'on cherchait à protéger. Et le vidage est lui-même borné : une tentative
 * qui persiste au-delà de [PURGE_MAX] est coupée pour de bon.
 */
export async function lireCorpsBorne(
  req: Request,
  max: number = TAILLE_CORPS_MAX,
): Promise<string | null> {
  const annoncee = Number.parseInt(req.headers.get("content-length") ?? "", 10);
  if (Number.isFinite(annoncee) && annoncee > max) {
    await purger(req.body);
    return null;
  }

  const flux = req.body;
  if (flux === null) return "";

  const lecteur = flux.getReader();
  const morceaux: Uint8Array[] = [];
  let total = 0;

  try {
    while (true) {
      const { done, value } = await lecteur.read();
      if (done) break;
      total += value.byteLength;
      if (total > max) {
        // Les morceaux déjà lus sont relâchés ici : rien de ce qui suit n'est
        // conservé, et ce qui précède cesse d'être référencé.
        morceaux.length = 0;
        lecteur.releaseLock();
        await purger(flux);
        return null;
      }
      morceaux.push(value);
    }
  } finally {
    // `releaseLock` a déjà pu être appelé sur le chemin du dépassement.
    try {
      lecteur.releaseLock();
    } catch {
      // Verrou déjà relâché : rien à faire.
    }
  }

  const tout = new Uint8Array(total);
  let position = 0;
  for (const morceau of morceaux) {
    tout.set(morceau, position);
    position += morceau.byteLength;
  }
  return new TextDecoder().decode(tout);
}

/** Ce qu'on accepte encore de lire, et de jeter, après un dépassement. Au-delà,
 * la connexion est coupée : ce n'est plus un envoi maladroit. */
const PURGE_MAX = 8 * 1024 * 1024;

/** Vide un flux sans rien en garder, puis le ferme. */
async function purger(flux: ReadableStream<Uint8Array> | null): Promise<void> {
  if (flux === null) return;
  const lecteur = flux.getReader();
  let jetes = 0;
  try {
    while (jetes < PURGE_MAX) {
      const { done, value } = await lecteur.read();
      if (done) return;
      jetes += value.byteLength;
    }
    await lecteur.cancel();
  } catch {
    // Connexion déjà fermée par l'émetteur : c'est le cas normal.
  } finally {
    try {
      lecteur.releaseLock();
    } catch {
      // Verrou déjà relâché.
    }
  }
}

/** Vrai si la chaîne a la forme d'un UUID. La base a des types et les fait
 * respecter ; ce contrôle existe pour que la réponse soit un refus honnête
 * (400) plutôt qu'un incident serveur (500) traduit d'une erreur PostgREST. */
export function estUuid(valeur: unknown): boolean {
  return typeof valeur === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(valeur.trim());
}
