// create-checkout — ouvrir une session de paiement, ou le portail de gestion.
// Référence : docs/SCHEMA.md § 7 et § 2.13, docs/PRD.md § 6.6, docs/STRIPE.md,
// design/029-stripe-abonnement.md, ticket 029.
//
// POST /functions/v1/create-checkout
// En-têtes : Authorization: Bearer <access_token de l'admin>, apikey: <clé anon>
// Corps    : { "station_id": uuid, "action": "state" | "checkout" | "portal",
//              "plan": "monthly" | "yearly" }   // plan requis pour "checkout"
//
// Trois actions, une seule fonction
// ---------------------------------
// `docs/SCHEMA.md § 7` n'en nomme qu'une, et c'est volontairement resté une :
// les trois gestes partagent **exactement** le même contrôle de droits, la même
// lecture de `subscriptions` et la même configuration. Trois fonctions auraient
// donné trois copies de la vérification « est-ce un admin actif de cette
// caserne ? », c'est-à-dire trois endroits où elle peut diverger.
//
//   * `state`    — ce que l'écran affiche : configuration présente ou non,
//                  tarifs, et si un portail de gestion est ouvrable. **Elle
//                  répond même sans compte Stripe**, et c'est tout l'intérêt :
//                  l'écran annonce le tarif au lieu de planter.
//   * `checkout` — crée le client s'il n'existe pas, ouvre la session, rend
//                  l'adresse de redirection.
//   * `portal`   — ouvre le portail client (carte, factures, résiliation).
//
// Ce que la fonction ne croit jamais
// -----------------------------------
// `verify_jwt = true` n'est qu'un portier : la clé anon est un JWT valide et
// publique. C'est `caller()` qui établit l'identité réelle auprès de GoTrue, et
// une requête sur `memberships` qui établit le rôle. **`station_id` sert à
// choisir la caserne visée, jamais à prouver un droit** — sans quoi n'importe
// quel membre connecté ouvrirait une session de paiement au nom d'une caserne
// qui n'est pas la sienne, et surtout ouvrirait son **portail**, où l'on peut
// résilier.

import { errorResponse, estUuid, jsonResponse, preflight, readJsonBody } from "../_shared/http.ts";
import {
  appelStripe,
  configuration,
  EchecStripe,
  type Formule,
  formuleValide,
  tarifs,
} from "../_shared/stripe.ts";
import { type AdminClient, adminClient, caller } from "../_shared/supabase.ts";
import {
  type AbonnementCaserne,
  type Action,
  actionValide,
  autoriser,
  portailOuvrable,
} from "./acces.ts";

/** Où Stripe renvoie le navigateur. Le chemin suit la stratégie de hash de
 * go_router, en vigueur dans l'application (même choix qu'`APP_INVITE_PATH`). */
const CHEMIN_RETOUR_DEFAUT = "/#/admin/abonnement";

function lienRetour(resultat: "ok" | "annule"): string {
  const base = (Deno.env.get("APP_BASE_URL") ?? "http://127.0.0.1:3000").replace(/\/+$/, "");
  const chemin = Deno.env.get("APP_SUBSCRIPTION_PATH") ?? CHEMIN_RETOUR_DEFAUT;
  const separateur = chemin.includes("?") ? "&" : "?";
  return `${base}${chemin}${separateur}paiement=${resultat}`;
}

/** Un uuid lisible dans le corps, ou `null`.
 *
 * La forme est vérifiée ici — contrairement aux autres fonctions du projet, où
 * l'identifiant part vers une RPC qui le type. Ici il part dans un `.eq()`
 * PostgREST, et un uuid mal formé y devient une erreur de requête que la
 * fonction traduisait en `500 internal_error` : un incident serveur annoncé pour
 * une faute de frappe. Un refus honnête vaut mieux. */
function identifiant(valeur: unknown): string | null {
  if (typeof valeur !== "string") return null;
  const propre = valeur.trim();
  return estUuid(propre) ? propre : null;
}

type Abonnement = AbonnementCaserne & {
  plan: string | null;
  trial_ends_at: string | null;
  current_period_end: string | null;
};

Deno.serve(async (req: Request): Promise<Response> => {
  const options = preflight(req);
  if (options) return options;

  if (req.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Méthode non autorisée.");
  }

  let admin: AdminClient;
  try {
    admin = adminClient();
  } catch (cause) {
    console.error(cause);
    return errorResponse(500, "internal_error", "Configuration serveur incomplète.");
  }

  const utilisateur = await caller(req, admin);
  if (!utilisateur) {
    return errorResponse(401, "unauthenticated", "Il faut être connecté.");
  }

  const body = await readJsonBody(req);
  if (!body) {
    return errorResponse(400, "invalid_body", "Corps de requête invalide.");
  }

  const stationId = identifiant(body.station_id);
  if (stationId === null) {
    return errorResponse(
      400,
      "invalid_body",
      "Le champ station_id est obligatoire et doit être un identifiant de caserne.",
    );
  }

  const action: Action | null = actionValide(body.action ?? "state");
  if (action === null) {
    return errorResponse(400, "invalid_body", "Action inconnue.");
  }

  // --- Le droit, établi en base et nulle part ailleurs ---------------------
  const { data: appartenance, error: echecRole } = await admin
    .from("memberships")
    .select("id")
    .eq("station_id", stationId)
    .eq("user_id", utilisateur.id)
    .eq("role", "admin")
    .eq("status", "active")
    .maybeSingle();

  if (echecRole) {
    console.error("memberships", echecRole.message);
    return errorResponse(500, "internal_error", "Lecture des droits en échec.");
  }

  const { data: ligne, error: echecLecture } = await admin
    .from("subscriptions")
    .select(
      "status, stripe_customer_id, stripe_subscription_id, plan, trial_ends_at, current_period_end",
    )
    .eq("station_id", stationId)
    .maybeSingle();

  if (echecLecture) {
    console.error("subscriptions", echecLecture.message);
    return errorResponse(500, "internal_error", "Lecture de l'abonnement en échec.");
  }

  const abonnement = (ligne ?? null) as Abonnement | null;
  const config = configuration();
  const montants = tarifs();
  const formule = formuleValide(body.plan);

  // **Toute la décision de droits tient ici**, dans une fonction pure testée à
  // chaque PR (`acces.ts`). Le reste du fichier ne fait que rassembler les faits
  // et exécuter. Le message d'un refus ne dit jamais si la caserne existe : le
  // dire à qui n'y a pas droit le lui apprendrait.
  const verdict = autoriser({
    action,
    estAdminActif: appartenance !== null,
    configure: config !== null,
    abonnement,
    formule,
  });
  if (!verdict.ok) {
    return errorResponse(verdict.statut, verdict.code, verdict.message);
  }

  // --- `state` : ce que l'écran affiche -----------------------------------
  // **Répond toujours**, configuration ou pas. C'est la règle du ticket 024
  // appliquée au paiement : l'application ne se casse pas faute de clés, elle
  // dit ce qui manque.
  if (action === "state") {
    return jsonResponse({
      ok: true,
      station_id: stationId,
      configured: config !== null,
      prices: {
        monthly: montants.mensuel,
        yearly: montants.annuel,
        currency: montants.devise,
      },
      /** Vrai quand un portail de gestion est ouvrable : il faut un compte
       * configuré **et** un client déjà créé. */
      portal_available: portailOuvrable(abonnement, config !== null),
      subscription: abonnement === null ? null : {
        status: abonnement.status,
        plan: abonnement.plan,
        trial_ends_at: abonnement.trial_ends_at,
        current_period_end: abonnement.current_period_end,
        has_customer: abonnement.stripe_customer_id !== null,
        /** **Ce que l'écran doit savoir pour ne pas proposer un second
         * abonnement.** Le statut ne suffit pas : une caserne en retard de
         * paiement n'est pas `active` et a pourtant déjà tout ce qu'il faut. */
        has_subscription: abonnement.stripe_subscription_id !== null,
      },
    });
  }

  // `autoriser` a déjà garanti les deux : la configuration est complète pour
  // `checkout` et `portal`, et la formule est valide pour `checkout`.
  const stripe = config!;

  try {
    if (action === "portal") {
      const session = await appelStripe("/billing_portal/sessions", stripe.cleSecrete, {
        customer: abonnement!.stripe_customer_id,
        return_url: lienRetour("ok"),
      });

      return jsonResponse({ ok: true, action, url: session.url });
    }

    // --- `checkout` -------------------------------------------------------
    const client = abonnement?.stripe_customer_id ??
      await creerClient(admin, stripe.cleSecrete, stationId, utilisateur.email);

    const session = await appelStripe("/checkout/sessions", stripe.cleSecrete, {
      mode: "subscription",
      customer: client,
      line_items: [{ price: prix(stripe, formule!), quantity: 1 }],
      // **La caserne voyage avec la session.** C'est ce champ que le webhook
      // relit dans `checkout.session.completed` : sans lui, le premier
      // événement d'une caserne ne saurait pas à qui il appartient.
      client_reference_id: stationId,
      metadata: { station_id: stationId, plan: formule },
      // Recopiées sur l'abonnement créé : les événements suivants
      // (`customer.subscription.*`) les portent à leur tour.
      subscription_data: { metadata: { station_id: stationId, plan: formule } },
      success_url: lienRetour("ok"),
      cancel_url: lienRetour("annule"),
      locale: "fr",
      // Le numéro de TVA d'une amicale, quand elle en a un.
      tax_id_collection: { enabled: true },
      allow_promotion_codes: true,
    });

    return jsonResponse({
      ok: true,
      action,
      plan: formule!,
      session_id: session.id,
      url: session.url,
    });
  } catch (cause) {
    if (cause instanceof EchecStripe) {
      // Le message de Stripe est en anglais et technique : il reste au journal.
      console.error(`stripe ${cause.statut} ${cause.codeStripe} : ${cause.message}`);
      return errorResponse(
        502,
        "stripe_error",
        "Le paiement n'a pas pu s'ouvrir. Réessaie dans un instant.",
      );
    }
    console.error(cause);
    return errorResponse(500, "internal_error", "L'ouverture du paiement a échoué.");
  }
});

function prix(config: { prixMensuel: string; prixAnnuel: string }, formule: Formule): string {
  return formule === "monthly" ? config.prixMensuel : config.prixAnnuel;
}

/**
 * Crée le client chez Stripe **et le retient en base** avant toute session.
 *
 * L'ordre compte : si l'on créait la session d'abord, un incident réseau entre
 * les deux laisserait un client orphelin chez Stripe, et la tentative suivante
 * en créerait un second. Le portail de gestion, lui, n'en retrouverait qu'un —
 * pas forcément celui qui porte l'abonnement.
 *
 * La clé d'idempotence est la caserne : deux appuis sur « S'abonner » à une
 * seconde d'intervalle rendent **le même** client.
 */
async function creerClient(
  admin: AdminClient,
  cleSecrete: string,
  stationId: string,
  email: string,
): Promise<string> {
  const { data: caserne } = await admin
    .from("stations")
    .select("name")
    .eq("id", stationId)
    .maybeSingle();

  const client = await appelStripe(
    "/customers",
    cleSecrete,
    {
      email,
      name: caserne?.name ?? undefined,
      metadata: { station_id: stationId, app: "astreinte-sp" },
    },
    { cleIdempotence: `station-customer-${stationId}` },
  );

  const identifiantClient = typeof client.id === "string" ? client.id : "";
  if (identifiantClient === "") {
    throw new Error("Stripe n'a pas rendu d'identifiant client.");
  }

  const { error } = await admin.rpc("subscription_set_customer", {
    p_station: stationId,
    p_customer: identifiantClient,
  });
  if (error) {
    // Ne pas retenir le client est un défaut qui se paie plus tard : on refuse
    // d'ouvrir la session plutôt que de laisser un client orphelin.
    console.error("subscription_set_customer", error.message);
    throw new Error("Impossible de retenir le client de paiement.");
  }

  return identifiantClient;
}
