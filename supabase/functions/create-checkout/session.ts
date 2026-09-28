// Les paramètres de la session Checkout de `create-checkout`, sans réseau.
// Référence : docs/STRIPE.md, tickets 029 et 069.
//
// Isolés ici pour être testés (`supabase/functions/tests/`) : une session
// refusée par Stripe ne se voit qu'en production, sous les yeux d'un chef de
// centre, comme au ticket 069.

import type { Formule } from "../_shared/stripe.ts";

export type EntreeSession = {
  /** Le client Stripe de la caserne, **toujours** existant à ce stade. */
  client: string;
  prix: string;
  stationId: string;
  formule: Formule;
  succes: string;
  annulation: string;
};

export function parametresSession(
  { client, prix, stationId, formule, succes, annulation }: EntreeSession,
): Record<string, unknown> {
  return {
    mode: "subscription",
    customer: client,
    line_items: [{ price: prix, quantity: 1 }],
    // **La caserne voyage avec la session.** C'est ce champ que le webhook
    // relit dans `checkout.session.completed` : sans lui, le premier
    // événement d'une caserne ne saurait pas à qui il appartient.
    client_reference_id: stationId,
    metadata: { station_id: stationId, plan: formule },
    // Recopiées sur l'abonnement créé : les événements suivants
    // (`customer.subscription.*`) les portent à leur tour.
    subscription_data: { metadata: { station_id: stationId, plan: formule } },
    success_url: succes,
    cancel_url: annulation,
    locale: "fr",
    // Le numéro de TVA d'une amicale, quand elle en a un.
    tax_id_collection: { enabled: true },
    // Exigé par Stripe dès qu'un client existant accompagne la collecte du
    // numéro de TVA : sans lui, toute session est refusée (ticket 069).
    customer_update: { name: "auto" },
    allow_promotion_codes: true,
  };
}
