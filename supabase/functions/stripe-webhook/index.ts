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

import { errorResponse, jsonResponse, lireCorpsBorne, TAILLE_CORPS_MAX } from "../_shared/http.ts";
import { secretWebhook, verifierSignature } from "../_shared/stripe.ts";
import { type AdminClient, adminClient } from "../_shared/supabase.ts";
import { interpreter } from "./evenement.ts";

/** Ce que rend `subscription_sync` (migration 0023). */
type ResultatSync = {
  ok: boolean;
  duplicate?: boolean;
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

  // **Le corps d'abord, et sous plafond.**
  //
  // Avant même de regarder si un secret est configuré : toute réponse rendue
  // sans avoir consommé le corps laisse l'émetteur écrire dans une connexion que
  // plus personne ne lit, et la passerelle coupe — l'appelant voit une erreur
  // réseau au lieu du statut qu'on vient de composer. Lire en premier, une fois,
  // supprime cette classe d'oubli pour tous les retours qui suivent.
  //
  // **Le corps brut, jamais ré-sérialisé, et jamais sans plafond.**
  //
  // Brut : `JSON.parse` puis `JSON.stringify` change l'ordre des clés et les
  // espaces, et la signature ne correspondrait plus à un octet près.
  //
  // Borné : c'est la seule fonction publique du projet, et cette lecture arrive
  // **avant** toute authentification — par construction, puisqu'il faut le corps
  // pour vérifier la signature. Sans plafond, un anonyme qui connaît l'adresse
  // fait allouer autant de mémoire qu'il veut, puis fait calculer l'empreinte
  // HMAC de l'ensemble. Un événement réel dépasse rarement 100 ko.
  const corps = await lireCorpsBorne(req, TAILLE_CORPS_MAX);
  if (corps === null) {
    console.error("stripe-webhook : corps trop volumineux, rejeté sans être analysé.");
    return errorResponse(413, "payload_too_large", "Corps de requête trop volumineux.");
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

  const identifiant = typeof evenement.id === "string" && evenement.id !== "" ? evenement.id : null;
  const interpretation = interpreter(evenement);

  if (!interpretation.traite) {
    // 200 : sans quoi Stripe rejouerait trois jours durant un événement qu'on
    // n'a jamais eu l'intention de traiter. Rien n'est écrit dans
    // `stripe_events` : un type ignoré n'a pas d'effet à dédoublonner.
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

  // **`p_event_id` est ce qui rend le traitement « une fois et une seule ».**
  // La signature dit que l'événement vient de Stripe, pas qu'il est neuf : un
  // même événement authentique réémis dans la fenêtre de cinq minutes repasse la
  // vérification. `subscription_sync` s'appuie sur la clé primaire de
  // `stripe_events` (migration 0023) et non sur un test suivi d'une écriture :
  // deux livraisons simultanées ne peuvent pas passer toutes les deux.
  const { data, error } = await admin.rpc("subscription_sync", {
    p_station: consequence.station ?? undefined,
    p_customer: consequence.customer ?? undefined,
    p_subscription: consequence.subscription ?? undefined,
    p_status: consequence.statut ?? undefined,
    p_plan: consequence.formule ?? undefined,
    p_period_end: consequence.finPeriode ?? undefined,
    p_event: interpretation.type,
    p_event_id: identifiant ?? undefined,
  });

  if (error) {
    console.error("subscription_sync", error.message);

    // La transaction de `subscription_sync` a été annulée : la ligne qu'elle
    // avait posée dans `stripe_events` est partie avec elle. On en pose une
    // seconde, dans sa propre transaction, **parce qu'un événement valide qui
    // échoue finit sinon par disparaître** — Stripe abandonne ses rejeux au bout
    // de trois jours, et il ne reste plus qu'une ligne de journal à rétention
    // courte. `select * from stripe_events where status = 'failed'` la montre.
    if (identifiant !== null) {
      const { error: echecTrace } = await admin.rpc("stripe_event_fail", {
        p_event_id: identifiant,
        p_type: interpretation.type,
        p_error: error.message,
      });
      if (echecTrace) console.error("stripe_event_fail", echecTrace.message);
    }

    // 500 : Stripe rejouera, et c'est ce qu'on veut — la base était
    // indisponible, l'événement reste valable. Le statut `failed` est le seul
    // que le dédoublonnage laisse reprendre.
    return errorResponse(500, "internal_error", "Mise à jour de l'abonnement en échec.");
  }

  const resultat = data as unknown as ResultatSync;

  // Déjà traité. 200 sans rien réécrire : c'est exactement ce qu'on attend d'un
  // rejeu, et Stripe n'a pas à insister.
  if (resultat?.duplicate) {
    return jsonResponse({
      ok: true,
      event_id: identifiant,
      type: interpretation.type,
      skipped: "duplicate",
    });
  }

  if (!resultat?.ok) {
    // Trois refus, une seule réponse : une caserne introuvable (un autre projet
    // branché sur le même compte), une formule inconnue, et un **client qui ne
    // correspond pas à la caserne nommée** — la seule protection contre un
    // `client_reference_id` posé depuis une URL. 200, sinon Stripe rejoue
    // jusqu'à désactiver le point de terminaison ; la ligne `skipped` de
    // `stripe_events` garde la trace.
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
