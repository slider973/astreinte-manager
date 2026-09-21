// stripe-webhook — la seule porte par laquelle un paiement change un statut.
// Référence : docs/SCHEMA.md § 7 et § 2.13, docs/STRIPE.md,
// supabase/functions/README.md, design/029-stripe-abonnement.md, ticket 029.
//
// POST /functions/v1/stripe-webhook
// En-têtes : Stripe-Signature: t=…,v1=…
// Corps    : l'événement Stripe, tel quel
//
// `verify_jwt = false`, et il ne peut pas en être autrement : Stripe appelle
// sans jeton. **C'est donc la signature, et elle seule, qui authentifie
// l'appelant.** Un événement non signé, mal signé, trop vieux, ou arrivé alors
// qu'aucun secret n'est configuré est rejeté sans être lu. Sans cette
// vérification, n'importe qui connaissant l'URL passerait une caserne en
// `active` — ou en `suspended`, ce qui la mettrait en lecture seule.
//
// Deux règles de réponse, et elles ne se ressemblent pas
// ------------------------------------------------------
//   * **4xx sur une signature** : Stripe marque l'envoi en échec et le montre
//     dans son tableau de bord. C'est exactement ce qu'on veut : un secret mal
//     recopié doit se voir chez le propriétaire, pas se perdre en silence.
//   * **200 sur un événement qu'on ne traite pas**, ou dont la caserne est
//     introuvable. Un 4xx ferait rejouer Stripe pendant trois jours un
//     événement qui ne sera jamais traitable, puis désactiverait le point de
//     terminaison — et les vrais événements cesseraient d'arriver.
//
// Ce que cette fonction n'écrit pas elle-même : rien. Tout passe par
// `subscription_sync` (migration 0023), qui verrouille la ligne, applique les
// paramètres non nuls, tient `suspended_at` et journalise dans `audit_log`.

import { errorResponse, jsonResponse } from "../_shared/http.ts";
import { secretWebhook, verifierSignature } from "../_shared/stripe.ts";
import { type AdminClient, adminClient } from "../_shared/supabase.ts";
import { interpreter } from "./evenement.ts";

/** Ce que rend `subscription_sync` (migration 0023). */
type ResultatSync = {
  ok: boolean;
  code?: string;
  station_id?: string;
  previous_status?: string;
  status?: string;
};

/** Le statut HTTP de chaque refus de signature. Tous en 4xx : Stripe doit voir. */
const STATUTS_SIGNATURE: Record<string, number> = {
  missing_signature: 400,
  malformed_signature: 400,
  timestamp_out_of_tolerance: 400,
  signature_mismatch: 400,
};

/** Messages, en français comme le reste de l'API. Ils ne sont lus que par le
 * propriétaire, dans le tableau de bord de Stripe. */
const MESSAGES_SIGNATURE: Record<string, string> = {
  missing_signature: "En-tête Stripe-Signature absent.",
  malformed_signature: "En-tête Stripe-Signature illisible.",
  timestamp_out_of_tolerance:
    "Événement hors de la fenêtre de tolérance : horloge décalée, ou rejeu.",
  signature_mismatch: "Signature invalide.",
};

Deno.serve(async (req: Request): Promise<Response> => {
  // Pas de préflight CORS : aucun navigateur n'appelle cette fonction. Lui
  // ouvrir les origines croisées n'ajouterait qu'une surface.
  if (req.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Méthode non autorisée.");
  }

  // Aucun secret configuré : **rien n'est traité**. Le repli n'est pas
  // « accepter sans vérifier », ce serait ouvrir la porte en grand ; c'est
  // refuser, et le dire. Tant que le propriétaire n'a pas branché son compte
  // (docs/STRIPE.md), les casernes restent en essai et l'application tourne.
  const secret = secretWebhook();
  if (secret === null) {
    console.error("stripe-webhook : STRIPE_WEBHOOK_SECRET absent, événement refusé.");
    return errorResponse(
      503,
      "stripe_not_configured",
      "Le prestataire de paiement n'est pas configuré sur ce projet.",
    );
  }

  // **Le corps brut, jamais ré-sérialisé.** `JSON.parse` puis `JSON.stringify`
  // change l'ordre des clés et les espaces : la signature ne correspondrait
  // plus à un seul octet près, et tous les événements seraient rejetés.
  const corps = await req.text();

  const signature = await verifierSignature(
    corps,
    req.headers.get("Stripe-Signature"),
    secret,
  );

  if (!signature.ok) {
    // Le corps n'est **pas** analysé : on ne lit pas ce qu'on n'a pas
    // authentifié. Le journal ne porte que le motif, jamais la charge utile.
    console.error(`stripe-webhook : ${signature.code}`);
    return errorResponse(
      STATUTS_SIGNATURE[signature.code] ?? 400,
      signature.code,
      MESSAGES_SIGNATURE[signature.code] ?? "Signature invalide.",
    );
  }

  let evenement: Record<string, unknown>;
  try {
    const analyse = JSON.parse(corps);
    if (typeof analyse !== "object" || analyse === null || Array.isArray(analyse)) {
      throw new Error("corps non objet");
    }
    evenement = analyse as Record<string, unknown>;
  } catch {
    // Signé mais illisible : c'est notre secret qui a servi, donc l'anomalie est
    // sérieuse. 400, pour qu'elle se voie.
    return errorResponse(400, "invalid_body", "Événement illisible.");
  }

  const identifiant = typeof evenement.id === "string" ? evenement.id : null;
  const interpretation = interpreter(evenement);

  if (!interpretation.traite) {
    // 200 : sans quoi Stripe rejouerait trois jours durant un événement qu'on
    // n'a jamais eu l'intention de traiter.
    return jsonResponse({
      ok: true,
      event_id: identifiant,
      type: interpretation.type,
      skipped: interpretation.raison,
    });
  }

  let admin: AdminClient;
  try {
    admin = adminClient();
  } catch (cause) {
    console.error(cause);
    return errorResponse(500, "internal_error", "Configuration serveur incomplète.");
  }

  const { consequence } = interpretation;
  const { data, error } = await admin.rpc("subscription_sync", {
    p_station: consequence.station ?? undefined,
    p_customer: consequence.customer ?? undefined,
    p_subscription: consequence.subscription ?? undefined,
    p_status: consequence.statut ?? undefined,
    p_plan: consequence.formule ?? undefined,
    p_period_end: consequence.finPeriode ?? undefined,
    p_event: interpretation.type,
  });

  if (error) {
    console.error("subscription_sync", error.message);
    // 500 : Stripe rejouera, et c'est ce qu'on veut — la base était
    // indisponible, l'événement reste valable.
    return errorResponse(500, "internal_error", "Mise à jour de l'abonnement en échec.");
  }

  const resultat = data as unknown as ResultatSync;

  if (!resultat?.ok) {
    // Une caserne introuvable n'est pas notre affaire : un autre projet branché
    // sur le même compte Stripe, ou un client créé à la main. 200, sinon Stripe
    // rejoue jusqu'à désactiver le point de terminaison.
    console.warn(`stripe-webhook : ${interpretation.type} non appliqué (${resultat?.code})`);
    return jsonResponse({
      ok: true,
      event_id: identifiant,
      type: interpretation.type,
      skipped: resultat?.code ?? "not_applied",
    });
  }

  return jsonResponse({
    ok: true,
    event_id: identifiant,
    type: interpretation.type,
    station_id: resultat.station_id,
    previous_status: resultat.previous_status,
    status: resultat.status,
  });
});
