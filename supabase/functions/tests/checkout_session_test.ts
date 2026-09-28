// Les paramètres de la session Checkout — `create-checkout/session.ts`.
// Lancement : deno test supabase/functions/tests/ --allow-env
//
// Ticket 069 : Stripe refusait **toute** session, parce que la collecte du
// numéro de TVA accompagnait un client existant sans `customer_update[name]`.
// Le refus n'apparaissait qu'en production ; ce test le rattrape en CI.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { encoderFormulaire } from "../_shared/stripe.ts";
import { parametresSession } from "../create-checkout/session.ts";

const entree = {
  client: "cus_A",
  prix: "price_mensuel",
  stationId: "c1ad75e2-e6be-4f81-a562-bae2238b9975",
  formule: "monthly" as const,
  succes: "https://app.example/admin/abonnement?paiement=ok",
  annulation: "https://app.example/admin/abonnement?paiement=annule",
};

function morceaux(): string[] {
  return encoderFormulaire(parametresSession(entree)).split("&");
}

function champ(nom: string, valeur: string): string {
  return `${encodeURIComponent(nom)}=${encodeURIComponent(valeur)}`;
}

Deno.test("un client existant et la collecte de TVA portent customer_update[name]=auto", () => {
  const envoye = morceaux();
  assert(envoye.includes("customer=cus_A"));
  assert(envoye.includes(champ("tax_id_collection[enabled]", "true")));
  assert(
    envoye.includes(champ("customer_update[name]", "auto")),
    "sans lui, Stripe refuse la session (400 invalid_request_error)",
  );
});

Deno.test("la session garde la caserne, la formule et les liens de retour", () => {
  const envoye = morceaux();
  assert(envoye.includes("mode=subscription"));
  assert(envoye.includes(champ("line_items[0][price]", "price_mensuel")));
  assert(envoye.includes(champ("client_reference_id", entree.stationId)));
  assert(envoye.includes(champ("metadata[station_id]", entree.stationId)));
  assert(envoye.includes(champ("subscription_data[metadata][plan]", "monthly")));
  assert(envoye.includes(champ("success_url", entree.succes)));
  assert(envoye.includes(champ("cancel_url", entree.annulation)));
  assertEquals(
    envoye.filter((morceau) => morceau.startsWith(encodeURIComponent("customer_update["))),
    [champ("customer_update[name]", "auto")],
    "seul le nom est mis à jour : l'adresse n'est pas collectée",
  );
});
