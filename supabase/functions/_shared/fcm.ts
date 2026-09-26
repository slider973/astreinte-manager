// Envoi push par Firebase Cloud Messaging, API HTTP v1.
//
// L'API v1 n'accepte pas de clé statique : il faut un jeton OAuth2 Google, obtenu
// en signant une assertion JWT avec la clé privée du compte de service
// (`FIREBASE_SERVICE_ACCOUNT`, docs/FIREBASE.md § 5). Tout est fait ici avec
// WebCrypto — aucune dépendance, aucun paquet à auditer pour signer un RS256.
//
// La clé privée ne quitte jamais cette fonction : ni journal, ni réponse HTTP,
// ni message d'erreur.
//
// Ce que ce fichier promet, et qui est testé sans réseau :
//
//   - `classerErreurFcm` distingue un jeton mort d'un incident passager. Un jeton
//     définitivement rejeté est supprimé ; un 503 ne fait perdre l'appareil de
//     personne. Se tromper de côté, c'est soit garder des jetons morts pour
//     toujours, soit débrancher un pompier parce que Google a eu une mauvaise
//     minute ;
//   - le transport est injectable : les tests passent un faux, le code de
//     production passe `fetch`.

export type CompteDeService = {
  project_id: string;
  client_email: string;
  private_key: string;
};

/** Ce qu'on demande à FCM d'afficher. */
export type MessagePush = {
  titre: string;
  corps: string;
  /** Paires de chaînes : FCM refuse tout ce qui n'est pas une chaîne. */
  donnees: Record<string, string>;
  /**
   * Le lien ouvert au clic, côté web (`webpush.fcm_options.link`).
   *
   * **Adresse complète en `https://` uniquement.** L'API v1 valide ce champ comme
   * une URL et refuse tout le reste par un `400 INVALID_ARGUMENT` — donc un chemin
   * relatif (`/proposals`) fait échouer le message entier. Une valeur non conforme
   * est écartée ici plutôt qu'envoyée : la notification part sans ce champ, et le
   * service worker retrouve la destination dans `data.route` (ticket 024).
   */
  lien?: string;
  /** `Notification.tag` : deux notifications de même étiquette se remplacent. */
  etiquette?: string;
};

export type VerdictJeton = "permanent" | "temporaire";

export type ResultatJeton = {
  token: string;
  ok: boolean;
  /** Renseigné quand `ok` est faux. `permanent` ⇒ le jeton est à supprimer. */
  verdict?: VerdictJeton;
  error?: string;
};

export type ResultatPush = {
  /** Jetons visés. */
  tentes: number;
  delivres: number;
  /** Jetons définitivement rejetés, à retirer de `push_tokens`. */
  jetonsMorts: string[];
  resultats: ResultatJeton[];
  /** Renseigné quand rien n'a pu être tenté (pas de compte de service…). */
  indisponible?: string;
};

/** Le transport HTTP, injectable pour les tests. */
export type Transport = (url: string, init: RequestInit) => Promise<Response>;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/**
 * Le compte de service, lu dans `FIREBASE_SERVICE_ACCOUNT` (le fichier JSON
 * téléchargé depuis la console Firebase, tel quel).
 *
 * Renvoie `null` si la variable est absente ou illisible : sans clés, le push est
 * *indisponible*, ce qui n'est pas une panne. La notification part quand même en
 * courriel et la ligne interne est écrite. C'est exactement l'état du projet tant
 * que docs/FIREBASE.md § 5 n'a pas été fait.
 */
export function compteDeService(): CompteDeService | null {
  const brut = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!brut || brut.trim() === "") return null;
  try {
    const objet = JSON.parse(brut) as Partial<CompteDeService>;
    if (!objet.project_id || !objet.client_email || !objet.private_key) return null;
    return {
      project_id: objet.project_id,
      client_email: objet.client_email,
      // Les clés recopiées à la main portent souvent des \n littéraux.
      private_key: objet.private_key.replace(/\\n/g, "\n"),
    };
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Jeton OAuth2
// ---------------------------------------------------------------------------

const PORTEE_FCM = "https://www.googleapis.com/auth/firebase.messaging";
const JETON_URL = "https://oauth2.googleapis.com/token";

let cache: { jeton: string; expire: number } | null = null;

/** Remet le cache à zéro. Réservé aux tests. */
export function oublierJetonOAuth(): void {
  cache = null;
}

function base64url(octets: Uint8Array): string {
  let binaire = "";
  for (const o of octets) binaire += String.fromCharCode(o);
  return btoa(binaire).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function base64urlTexte(valeur: string): string {
  return base64url(new TextEncoder().encode(valeur));
}

/** PEM PKCS#8 → clé RSASSA-PKCS1-v1_5 SHA-256 importable par WebCrypto. */
async function importerCle(pem: string): Promise<CryptoKey> {
  const corps = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binaire = atob(corps);
  const octets = new Uint8Array(binaire.length);
  for (let i = 0; i < binaire.length; i++) octets[i] = binaire.charCodeAt(i);
  return await crypto.subtle.importKey(
    "pkcs8",
    octets,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

/**
 * Jeton d'accès Google, mis en cache jusqu'à cinq minutes avant son échéance.
 *
 * Une publication de planning, c'est une centaine d'envois : les faire précéder
 * chacun d'un aller-retour OAuth serait un gaspillage et un facteur de limitation
 * de débit.
 */
export async function jetonOAuth(
  compte: CompteDeService,
  transport: Transport = fetch,
  maintenant: () => number = Date.now,
): Promise<string> {
  const instant = Math.floor(maintenant() / 1000);
  if (cache && cache.expire - 300 > instant) return cache.jeton;

  const entete = base64urlTexte(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const charge = base64urlTexte(JSON.stringify({
    iss: compte.client_email,
    scope: PORTEE_FCM,
    aud: JETON_URL,
    iat: instant,
    exp: instant + 3600,
  }));
  const cle = await importerCle(compte.private_key);
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      cle,
      new TextEncoder().encode(`${entete}.${charge}`),
    ),
  );
  const assertion = `${entete}.${charge}.${base64url(signature)}`;

  const reponse = await transport(JETON_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!reponse.ok) {
    // Le corps de Google ne contient jamais la clé privée : on le garde pour le
    // diagnostic, tronqué.
    const corps = await reponse.text();
    throw new Error(`oauth ${reponse.status} ${corps.slice(0, 200)}`);
  }

  const jetonReponse = await reponse.json() as {
    access_token?: string;
    expires_in?: number;
  };
  if (!jetonReponse.access_token) throw new Error("oauth : réponse sans access_token");

  cache = {
    jeton: jetonReponse.access_token,
    expire: instant + (jetonReponse.expires_in ?? 3600),
  };
  return cache.jeton;
}

// ---------------------------------------------------------------------------
// Classement des erreurs — le cœur du nettoyage des jetons
// ---------------------------------------------------------------------------

/**
 * Un jeton mort ou une mauvaise minute ?
 *
 * `permanent` ⇒ l'appareil ne recevra plus jamais rien avec ce jeton : il est
 * supprimé de `push_tokens`. `temporaire` ⇒ on n'y touche pas.
 *
 * Le doute profite au jeton. Un `400 INVALID_ARGUMENT` n'est réputé permanent que
 * si la réponse désigne le jeton (`message.token`, « registration token ») :
 * le même code sort d'un message mal formé, c'est-à-dire d'un bogue de *notre*
 * côté, et le traiter comme permanent effacerait tous les jetons de la caserne
 * à la première régression.
 */
export function classerErreurFcm(statut: number, corps: string): VerdictJeton {
  const texte = (corps ?? "").toLowerCase();

  // Jeton inconnu de FCM : désinstallation, cache navigateur vidé, jeton périmé.
  if (statut === 404) return "permanent";

  // Jeton émis pour un autre projet Firebase : il ne marchera jamais ici.
  if (statut === 403 && texte.includes("sender_id_mismatch")) return "permanent";

  if (statut === 400) {
    const viseLeJeton = texte.includes("message.token") ||
      texte.includes("registration token") ||
      texte.includes("unregistered");
    return viseLeJeton ? "permanent" : "temporaire";
  }

  // 401 (nos identifiants), 403 sans plus de précision, 429, 5xx, réseau :
  // rien de tout cela n'accuse l'appareil du pompier.
  return "temporaire";
}

// ---------------------------------------------------------------------------
// Envoi
// ---------------------------------------------------------------------------

/**
 * Le corps d'un message FCM HTTP v1.
 *
 * Les blocs `notification` **et** `data` sont envoyés tous les deux, et ce n'est
 * pas de la ceinture-bretelles : le client du ticket 024 lit les deux selon la
 * situation. Au premier plan, `messagerie_push.dart` lit `notification.title` et
 * `notification.body` ; en arrière-plan, le SDK affiche la notification tout seul
 * et `web/firebase-messaging-sw.js` retrouve la destination dans
 * `FCM_MSG.data.route` ; en repli « data only », le même service worker lit
 * `data.title`, `data.body` et `data.route`. Retirer l'un des deux blocs casse
 * l'un des trois chemins.
 */
/**
 * Ce champ accepte-t-il cette valeur ?
 *
 * `webpush.fcm_options.link` doit être une adresse **complète** et **sécurisée** :
 * l'API v1 la valide comme une URL et impose `https`. Un chemin relatif ou une
 * origine en `http://` (la pile locale) provoquent un `400 INVALID_ARGUMENT` qui
 * fait échouer tout le message — et `classerErreurFcm` le rangerait en incident
 * temporaire, donc aucun jeton ne serait perdu mais aucun push ne partirait jamais,
 * tout basculant en courriel de secours. Le silence parfait.
 *
 * L'omettre est sans conséquence : le service worker lit `data.route`, pas ce
 * champ (`web/firebase-messaging-sw.js`). En développement, où `APP_BASE_URL` est
 * en `http://127.0.0.1:3000`, le push part donc simplement sans lui.
 */
export function lienPubliable(lien: string | undefined): boolean {
  if (!lien) return false;
  try {
    return new URL(lien).protocol === "https:";
  } catch {
    return false;
  }
}

/** Plafond d'Apple pour l'en-tête `apns-collapse-id`, en octets. */
const COLLAPSE_ID_MAX_OCTETS = 64;

/**
 * Tronque une chaîne à `max` octets UTF-8 sans couper un caractère en deux.
 *
 * `apns-collapse-id` se mesure en octets, pas en caractères : une étiquette
 * accentuée de 64 caractères dépasserait la limite et APNs refuserait le message.
 */
export function tronquerOctets(valeur: string, max: number): string {
  const encodeur = new TextEncoder();
  if (encodeur.encode(valeur).length <= max) return valeur;
  let resultat = "";
  let octets = 0;
  for (const caractere of valeur) {
    const taille = encodeur.encode(caractere).length;
    if (octets + taille > max) break;
    resultat += caractere;
    octets += taille;
  }
  return resultat;
}

/**
 * Le bloc `apns`, lu par les appareils iOS (app native Foco, ticket 066).
 *
 * Sans lui, iOS affiche la notification **sans son** : un pompier qui a rangé
 * son téléphone ne l'entend pas. L'étiquette, quand elle existe, regroupe
 * (`thread-id`) et remplace (`apns-collapse-id`) comme `Notification.tag` côté
 * web. La clé `headers` est omise plutôt que mise à `undefined` : l'API v1
 * refuse un `headers` nul ou vide.
 */
function blocApns(etiquette: string | undefined): Record<string, unknown> {
  const aps: Record<string, string> = { sound: "default" };
  if (!etiquette) return { payload: { aps } };
  aps["thread-id"] = etiquette;
  return {
    headers: { "apns-collapse-id": tronquerOctets(etiquette, COLLAPSE_ID_MAX_OCTETS) },
    payload: { aps },
  };
}

export function corpsMessage(jeton: string, message: MessagePush): Record<string, unknown> {
  const donnees: Record<string, string> = {
    ...message.donnees,
    title: message.titre,
    body: message.corps,
  };
  if (message.etiquette) donnees.tag = message.etiquette;

  return {
    message: {
      token: jeton,
      notification: { title: message.titre, body: message.corps },
      data: donnees,
      webpush: {
        notification: {
          title: message.titre,
          body: message.corps,
          tag: message.etiquette,
        },
        fcm_options: lienPubliable(message.lien) ? { link: message.lien } : undefined,
      },
      apns: blocApns(message.etiquette),
    },
  };
}

/**
 * Envoie un message à une liste de jetons, un appel par jeton.
 *
 * FCM v1 a retiré l'envoi par lot (`batch`) en 2024 : un appel par appareil est
 * la forme supportée. Les appels sont séquentiels, ce qui suffit largement — un
 * membre a un à trois appareils.
 *
 * N'échoue jamais en bloc : chaque jeton a son sort, et la liste des jetons morts
 * revient à l'appelant qui les supprimera.
 */
export async function envoyerPush(
  jetons: readonly string[],
  message: MessagePush,
  options: {
    compte?: CompteDeService | null;
    transport?: Transport;
  } = {},
): Promise<ResultatPush> {
  const compte = options.compte === undefined ? compteDeService() : options.compte;
  const transport = options.transport ?? fetch;

  if (jetons.length === 0) {
    return { tentes: 0, delivres: 0, jetonsMorts: [], resultats: [] };
  }
  if (!compte) {
    return {
      tentes: 0,
      delivres: 0,
      jetonsMorts: [],
      resultats: [],
      indisponible: "FIREBASE_SERVICE_ACCOUNT absent : push non configuré",
    };
  }

  let acces: string;
  try {
    acces = await jetonOAuth(compte, transport);
  } catch (cause) {
    // Nos identifiants, pas ceux du pompier : aucun jeton n'est supprimé.
    return {
      tentes: 0,
      delivres: 0,
      jetonsMorts: [],
      resultats: [],
      indisponible: cause instanceof Error ? cause.message : String(cause),
    };
  }

  const url = `https://fcm.googleapis.com/v1/projects/${compte.project_id}/messages:send`;
  const resultats: ResultatJeton[] = [];
  const jetonsMorts: string[] = [];
  let delivres = 0;

  for (const jeton of jetons) {
    try {
      const reponse = await transport(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${acces}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(corpsMessage(jeton, message)),
      });

      if (reponse.ok) {
        // Le corps est consommé pour libérer la connexion, jamais journalisé.
        await reponse.text();
        delivres += 1;
        resultats.push({ token: jeton, ok: true });
        continue;
      }

      const corps = await reponse.text();
      const verdict = classerErreurFcm(reponse.status, corps);
      if (verdict === "permanent") jetonsMorts.push(jeton);
      resultats.push({
        token: jeton,
        ok: false,
        verdict,
        error: `fcm ${reponse.status} ${corps.slice(0, 200)}`,
      });
    } catch (cause) {
      // Panne réseau : temporaire par construction, le jeton reste.
      resultats.push({
        token: jeton,
        ok: false,
        verdict: "temporaire",
        error: cause instanceof Error ? cause.message : String(cause),
      });
    }
  }

  return { tentes: jetons.length, delivres, jetonsMorts, resultats };
}
