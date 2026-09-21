// Stripe — configuration, appels API et **vérification de signature**.
//
// Référence : docs/STRIPE.md, docs/SCHEMA.md § 2.13 et § 7, ticket 029.
//
// Aucun SDK. Trois raisons :
//   1. l'API de Stripe utilisée ici tient en quatre appels `POST` en
//      `application/x-www-form-urlencoded` ;
//   2. le SDK Node ne tourne pas tel quel sous Deno, et son portage tire une
//      arborescence entière pour un webhook de cinquante lignes ;
//   3. la vérification de signature est **le** point de sécurité de ce ticket.
//      L'écrire ici, en clair et testé (supabase/functions/tests/), vaut mieux
//      que de la déléguer à une dépendance qu'on ne relit jamais.
//
// **Rien n'est obligatoire.** Tant qu'aucune clé n'est posée, `configuration()`
// rend `null`, `create-checkout` répond `stripe_not_configured` et
// `stripe-webhook` refuse tout. L'application, elle, continue de tourner : une
// caserne sans abonnement configuré reste en essai et pleinement utilisable
// (`station_writable()`, migration 0007).

/** Ce qu'il faut pour ouvrir une session de paiement. */
export type ConfigurationStripe = {
  /** Clé secrète du compte (`sk_live_…` ou `sk_test_…`). Ne sort jamais d'ici. */
  cleSecrete: string;
  /** Identifiant du prix mensuel (`price_…`). */
  prixMensuel: string;
  /** Identifiant du prix annuel (`price_…`). */
  prixAnnuel: string;
  /** Secret de signature du point de terminaison webhook (`whsec_…`). */
  secretWebhook: string;
};

/** Les tarifs annoncés par l'application, en centimes. */
export type Tarifs = {
  mensuel: number;
  annuel: number;
  devise: string;
};

/** `docs/PRD.md § 6.6` : 12 €/mois, 120 €/an. Affichés même sans compte Stripe,
 * parce qu'un chef de centre en essai a le droit de savoir ce que ça coûtera. */
export const TARIFS_PAR_DEFAUT: Tarifs = { mensuel: 1200, annuel: 12000, devise: "eur" };

export type Formule = "monthly" | "yearly";

export function formuleValide(valeur: unknown): Formule | null {
  return valeur === "monthly" || valeur === "yearly" ? valeur : null;
}

function variable(nom: string): string {
  return (Deno.env.get(nom) ?? "").trim();
}

function entier(nom: string, defaut: number): number {
  const brut = variable(nom);
  if (brut === "") return defaut;
  const valeur = Number.parseInt(brut, 10);
  return Number.isFinite(valeur) && valeur > 0 ? valeur : defaut;
}

/**
 * Les tarifs à afficher. Réglables par variables d'environnement pour que
 * l'écran suive un changement de prix **sans recompilation de la PWA**, et pour
 * qu'ils restent justes même quand Stripe n'est pas encore configuré.
 */
export function tarifs(): Tarifs {
  return {
    mensuel: entier("STRIPE_AMOUNT_MONTHLY", TARIFS_PAR_DEFAUT.mensuel),
    annuel: entier("STRIPE_AMOUNT_YEARLY", TARIFS_PAR_DEFAUT.annuel),
    devise: (variable("STRIPE_CURRENCY") || TARIFS_PAR_DEFAUT.devise).toLowerCase(),
  };
}

/**
 * La configuration complète, ou `null` si **une seule** valeur manque.
 *
 * Même règle qu'au ticket 024 pour Firebase : une configuration à moitié
 * remplie est traitée comme absente. Une clé secrète sans identifiant de prix
 * produirait une session de paiement vide, et l'échec arriverait sous les yeux
 * d'un chef de centre plutôt que sous ceux du propriétaire.
 */
export function configuration(): ConfigurationStripe | null {
  const config: ConfigurationStripe = {
    cleSecrete: variable("STRIPE_SECRET_KEY"),
    prixMensuel: variable("STRIPE_PRICE_MONTHLY"),
    prixAnnuel: variable("STRIPE_PRICE_YEARLY"),
    secretWebhook: variable("STRIPE_WEBHOOK_SECRET"),
  };
  const manquantes = Object.values(config).filter((valeur) => valeur === "");
  return manquantes.length === 0 ? config : null;
}

/** Vrai dès que le secret de signature est posé — la seule valeur dont le
 * webhook a besoin. Il peut donc être branché avant les prix. */
export function secretWebhook(): string | null {
  const secret = variable("STRIPE_WEBHOOK_SECRET");
  return secret === "" ? null : secret;
}

// ===========================================================================
// Vérification de signature — le point de sécurité du ticket
// ===========================================================================
//
// `stripe-webhook` est **publique par nature** : Stripe l'appelle sans jeton, de
// n'importe où. La signature est donc la seule chose qui distingue un événement
// de Stripe d'un événement forgé par le premier venu qui connaît l'URL. Et un
// événement forgé, ici, vaut « cette caserne est active » ou « cette caserne est
// suspendue » sans qu'un euro ait circulé.
//
// Le schéma de Stripe, tel qu'il arrive dans l'en-tête `Stripe-Signature` :
//
//   t=1730000000,v1=5257a869e7…,v1=… ,v0=…
//
// La signature est `HMAC-SHA256(secret, "<t>.<corps brut>")` en hexadécimal. Il
// peut y avoir **plusieurs** `v1` pendant une rotation de secret : il suffit
// qu'un seul corresponde. Les `v0` sont un ancien schéma, ignoré.
//
// Trois pièges, tous traités ici :
//   * **Le corps brut.** `JSON.parse` puis `JSON.stringify` change les espaces
//     et l'ordre des clés : la signature ne correspondrait plus. Le corps est
//     donc lu en texte, signé en texte, et analysé seulement après.
//   * **La fenêtre de tolérance.** Sans elle, un événement authentique capté
//     une fois peut être rejoué indéfiniment. Cinq minutes, la valeur de Stripe.
//   * **La comparaison à temps constant.** Une comparaison `===` sur des
//     chaînes sort au premier octet différent, ce qui laisse mesurer la
//     progression d'une signature devinée octet par octet.

export type EchecSignature =
  | "missing_signature"
  | "malformed_signature"
  | "timestamp_out_of_tolerance"
  | "signature_mismatch";

export type ResultatSignature =
  | { ok: true; horodatage: number }
  | { ok: false; code: EchecSignature };

/** Tolérance par défaut, en secondes. Valeur de Stripe. */
export const TOLERANCE_SECONDES = 300;

/** Analyse l'en-tête `Stripe-Signature` sans rien vérifier. */
export function analyserEnteteSignature(
  entete: string,
): { horodatage: number; signatures: string[] } | null {
  let horodatage = Number.NaN;
  const signatures: string[] = [];

  for (const morceau of entete.split(",")) {
    const separateur = morceau.indexOf("=");
    if (separateur < 0) continue;
    const cle = morceau.slice(0, separateur).trim();
    const valeur = morceau.slice(separateur + 1).trim();
    if (cle === "t") horodatage = Number.parseInt(valeur, 10);
    else if (cle === "v1" && valeur !== "") signatures.push(valeur);
  }

  if (!Number.isFinite(horodatage) || signatures.length === 0) return null;
  return { horodatage, signatures };
}

/** Comparaison à temps constant de deux chaînes hexadécimales. */
export function memeSignature(a: string, b: string): boolean {
  // Une longueur différente n'est pas un secret : les signatures de Stripe font
  // toutes 64 caractères hexadécimaux. Sortir ici évite surtout de comparer sur
  // la longueur de la plus courte et de déclarer égales deux chaînes préfixes.
  if (a.length !== b.length) return false;
  let ecart = 0;
  for (let i = 0; i < a.length; i++) ecart |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return ecart === 0;
}

/** `HMAC-SHA256(secret, message)` en hexadécimal minuscule. */
export async function signer(secret: string, message: string): Promise<string> {
  const encodeur = new TextEncoder();
  const cle = await crypto.subtle.importKey(
    "raw",
    encodeur.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", cle, encodeur.encode(message));
  return Array.from(new Uint8Array(signature))
    .map((octet) => octet.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Vérifie la signature d'un événement.
 *
 * @param corps      le corps **brut** de la requête, tel qu'il est arrivé
 * @param entete     l'en-tête `Stripe-Signature`, ou `null` s'il est absent
 * @param secret     le secret du point de terminaison (`whsec_…`)
 * @param instant    l'instant de référence, en secondes — paramétré pour les tests
 * @param tolerance  la fenêtre acceptée, en secondes
 */
export async function verifierSignature(
  corps: string,
  entete: string | null,
  secret: string,
  { instant = Math.floor(Date.now() / 1000), tolerance = TOLERANCE_SECONDES } = {},
): Promise<ResultatSignature> {
  if (entete === null || entete.trim() === "") {
    return { ok: false, code: "missing_signature" };
  }

  const analyse = analyserEnteteSignature(entete);
  if (analyse === null) return { ok: false, code: "malformed_signature" };

  if (Math.abs(instant - analyse.horodatage) > tolerance) {
    return { ok: false, code: "timestamp_out_of_tolerance" };
  }

  const attendue = await signer(secret, `${analyse.horodatage}.${corps}`);
  // Toutes les signatures sont comparées, sans court-circuit : pendant une
  // rotation de secret, Stripe en envoie deux.
  let trouvee = false;
  for (const candidate of analyse.signatures) {
    if (memeSignature(candidate, attendue)) trouvee = true;
  }

  return trouvee
    ? { ok: true, horodatage: analyse.horodatage }
    : { ok: false, code: "signature_mismatch" };
}

// ===========================================================================
// Appels à l'API Stripe
// ===========================================================================

export class EchecStripe extends Error {
  constructor(readonly statut: number, readonly codeStripe: string, message: string) {
    super(message);
    this.name = "EchecStripe";
  }
}

/**
 * Sérialise un objet en `application/x-www-form-urlencoded`, avec la notation
 * en crochets attendue par Stripe (`line_items[0][price]`, `metadata[x]`).
 */
export function encoderFormulaire(
  valeurs: Record<string, unknown>,
  prefixe = "",
): string {
  const morceaux: string[] = [];

  for (const [cle, valeur] of Object.entries(valeurs)) {
    if (valeur === undefined || valeur === null) continue;
    const nom = prefixe === "" ? cle : `${prefixe}[${cle}]`;

    if (Array.isArray(valeur)) {
      valeur.forEach((element, index) => {
        if (element !== null && typeof element === "object") {
          morceaux.push(
            encoderFormulaire(element as Record<string, unknown>, `${nom}[${index}]`),
          );
        } else {
          morceaux.push(
            `${encodeURIComponent(`${nom}[${index}]`)}=${encodeURIComponent(String(element))}`,
          );
        }
      });
    } else if (typeof valeur === "object") {
      morceaux.push(encoderFormulaire(valeur as Record<string, unknown>, nom));
    } else {
      morceaux.push(`${encodeURIComponent(nom)}=${encodeURIComponent(String(valeur))}`);
    }
  }

  return morceaux.filter((morceau) => morceau !== "").join("&");
}

const API_STRIPE = "https://api.stripe.com/v1";

/** Un `POST` vers l'API Stripe. La clé secrète ne quitte pas cette fonction. */
export async function appelStripe(
  chemin: string,
  cleSecrete: string,
  corps: Record<string, unknown>,
  { cleIdempotence }: { cleIdempotence?: string } = {},
): Promise<Record<string, unknown>> {
  const entetes: Record<string, string> = {
    "Authorization": `Bearer ${cleSecrete}`,
    "Content-Type": "application/x-www-form-urlencoded",
    "Stripe-Version": "2024-06-20",
  };
  if (cleIdempotence) entetes["Idempotency-Key"] = cleIdempotence;

  const reponse = await fetch(`${API_STRIPE}${chemin}`, {
    method: "POST",
    headers: entetes,
    body: encoderFormulaire(corps),
  });

  const donnees = await reponse.json().catch(() => ({})) as Record<string, unknown>;

  if (!reponse.ok) {
    const erreur = (donnees.error ?? {}) as Record<string, unknown>;
    throw new EchecStripe(
      reponse.status,
      String(erreur.code ?? erreur.type ?? "stripe_error"),
      // Le message de Stripe est en anglais et technique : il part au journal,
      // jamais à l'écran d'un chef de centre.
      String(erreur.message ?? "Appel Stripe en échec."),
    );
  }

  return donnees;
}
