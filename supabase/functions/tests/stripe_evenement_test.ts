// Les quatre événements du ticket 029, traduits en conséquences sur
// `subscriptions` — `stripe-webhook/evenement.ts`.
// Lancement : deno test supabase/functions/tests/ --allow-env
//
// Les charges utiles ci-dessous sont réduites aux champs que la fonction lit,
// mais **leur forme est celle de Stripe** : `data.object`, dates en secondes,
// identifiants parfois étendus en objet. Ce qui est vérifié n'est pas Stripe,
// c'est notre lecture de Stripe.

import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  dateStripe,
  formuleDepuisAbonnement,
  interpreter,
  statutDepuisStripe,
} from "../stripe-webhook/evenement.ts";

const CASERNE = "aaaaaaaa-0000-4000-8000-000000000001";

function evenement(type: string, objet: Record<string, unknown>) {
  return { id: "evt_test", type, data: { object: objet } };
}

// ---------------------------------------------------------------------------
// 1. checkout.session.completed
// ---------------------------------------------------------------------------

Deno.test("checkout.session.completed : la caserne devient abonnée", () => {
  const lu = interpreter(evenement("checkout.session.completed", {
    client_reference_id: CASERNE,
    customer: "cus_A",
    subscription: "sub_A",
    payment_status: "paid",
    metadata: { station_id: CASERNE, plan: "monthly" },
  }));

  assert(lu.traite);
  assertEquals(lu.consequence.station, CASERNE);
  assertEquals(lu.consequence.customer, "cus_A");
  assertEquals(lu.consequence.subscription, "sub_A");
  assertEquals(lu.consequence.statut, "active");
  assertEquals(lu.consequence.formule, "monthly");
});

Deno.test("checkout.session.completed : un paiement différé n'ouvre pas les droits", () => {
  // Prélèvement SEPA : la session aboutit, l'argent n'est pas passé. La caserne
  // reste en essai jusqu'à `invoice.paid` — on n'ouvre rien sur une promesse.
  const lu = interpreter(evenement("checkout.session.completed", {
    client_reference_id: CASERNE,
    customer: "cus_A",
    subscription: "sub_A",
    payment_status: "unpaid",
  }));

  assert(lu.traite);
  assertEquals(lu.consequence.statut, null);
  // Le client et l'abonnement sont retenus quand même : le portail doit les
  // retrouver, et `invoice.paid` arrivera avec le seul `customer`.
  assertEquals(lu.consequence.customer, "cus_A");
  assertEquals(lu.consequence.subscription, "sub_A");
});

Deno.test("checkout.session.completed : les métadonnées suppléent à client_reference_id", () => {
  const lu = interpreter(evenement("checkout.session.completed", {
    customer: { id: "cus_A", object: "customer" },
    subscription: { id: "sub_A" },
    payment_status: "paid",
    metadata: { station_id: CASERNE, plan: "yearly" },
  }));

  assert(lu.traite);
  assertEquals(lu.consequence.station, CASERNE);
  // Stripe rend parfois l'objet étendu là où il rendait un identifiant.
  assertEquals(lu.consequence.customer, "cus_A");
  assertEquals(lu.consequence.subscription, "sub_A");
  assertEquals(lu.consequence.formule, "yearly");
});

// ---------------------------------------------------------------------------
// 2. invoice.paid
// ---------------------------------------------------------------------------

Deno.test("invoice.paid : active, période repoussée, caserne retrouvée par le client", () => {
  const lu = interpreter(evenement("invoice.paid", {
    customer: "cus_A",
    subscription: "sub_A",
    period_end: 1_800_000_000,
  }));

  assert(lu.traite);
  // **Aucune caserne nommée** : c'est le cas réel de tous les renouvellements.
  // La base la retrouve par `stripe_customer_id`.
  assertEquals(lu.consequence.station, null);
  assertEquals(lu.consequence.customer, "cus_A");
  assertEquals(lu.consequence.statut, "active");
  assertEquals(lu.consequence.finPeriode, new Date(1_800_000_000 * 1000).toISOString());
  // La formule n'est pas dans la facture : elle reste nulle, donc elle n'écrase
  // rien en base (`coalesce` de `subscription_sync`).
  assertEquals(lu.consequence.formule, null);
});

Deno.test("invoice.paid : la période de la ligne l'emporte sur celle de la facture", () => {
  const lu = interpreter(evenement("invoice.paid", {
    customer: "cus_A",
    period_end: 1_700_000_000,
    lines: { data: [{ period: { end: 1_800_000_000 } }] },
    parent: { subscription_details: { subscription: "sub_A" } },
  }));

  assert(lu.traite);
  assertEquals(lu.consequence.finPeriode, new Date(1_800_000_000 * 1000).toISOString());
  // L'abonnement des versions récentes de l'API vit sous `parent`.
  assertEquals(lu.consequence.subscription, "sub_A");
});

// ---------------------------------------------------------------------------
// 3. invoice.payment_failed
// ---------------------------------------------------------------------------

Deno.test("invoice.payment_failed : past_due, et rien n'est coupé", () => {
  const lu = interpreter(evenement("invoice.payment_failed", {
    customer: "cus_A",
    subscription: "sub_A",
  }));

  assert(lu.traite);
  assertEquals(lu.consequence.statut, "past_due");
  // **La période payée n'est pas touchée** : c'est elle qui date le retard, et
  // c'est sur elle que la tâche planifiée compte les quatorze jours. L'écraser
  // repousserait la suspension à chaque relance de carte.
  assertEquals(lu.consequence.finPeriode, null);
});

// ---------------------------------------------------------------------------
// 4. customer.subscription.updated / deleted
// ---------------------------------------------------------------------------

Deno.test("customer.subscription.updated : changement de formule", () => {
  const lu = interpreter(evenement("customer.subscription.updated", {
    id: "sub_A",
    customer: "cus_A",
    status: "active",
    current_period_end: 1_800_000_000,
    items: { data: [{ price: { recurring: { interval: "year" } } }] },
    metadata: { station_id: CASERNE },
  }));

  assert(lu.traite);
  assertEquals(lu.consequence.subscription, "sub_A");
  assertEquals(lu.consequence.statut, "active");
  assertEquals(lu.consequence.formule, "yearly");
  assertEquals(lu.consequence.finPeriode, new Date(1_800_000_000 * 1000).toISOString());
});

Deno.test("customer.subscription.updated : un impayé remonté par l'abonnement", () => {
  const lu = interpreter(evenement("customer.subscription.updated", {
    id: "sub_A",
    customer: "cus_A",
    status: "past_due",
    items: { data: [{ price: { recurring: { interval: "month" } } }] },
  }));

  assert(lu.traite);
  assertEquals(lu.consequence.statut, "past_due");
  assertEquals(lu.consequence.formule, "monthly");
});

Deno.test("customer.subscription.updated : un état transitoire n'écrase rien", () => {
  // `incomplete` : la première facture n'est pas encore payée. Passer la caserne
  // dans cet état couperait l'écriture à quelqu'un qui vient de payer.
  const lu = interpreter(evenement("customer.subscription.updated", {
    id: "sub_A",
    customer: "cus_A",
    status: "incomplete",
  }));

  assert(lu.traite);
  assertEquals(lu.consequence.statut, null);
});

Deno.test("customer.subscription.deleted : résilié, sans période payée", () => {
  const lu = interpreter(evenement("customer.subscription.deleted", {
    id: "sub_A",
    customer: "cus_A",
    status: "canceled",
    current_period_end: 1_800_000_000,
    items: { data: [{ price: { recurring: { interval: "month" } } }] },
  }));

  assert(lu.traite);
  assertEquals(lu.consequence.statut, "cancelled");
  // Une résiliation ne repousse aucune période : la caserne passe en lecture
  // seule tout de suite (`station_writable`, migration 0007).
  assertEquals(lu.consequence.finPeriode, null);
});

// ---------------------------------------------------------------------------
// Ce qui n'est pas traité
// ---------------------------------------------------------------------------

Deno.test("un type inconnu est ignoré, jamais une erreur", () => {
  // Un compte Stripe en émet des dizaines. Les refuser ferait rejouer Stripe
  // pendant trois jours, puis désactiver le point de terminaison.
  for (const type of ["payment_intent.succeeded", "customer.created", "charge.refunded"]) {
    const lu = interpreter(evenement(type, { customer: "cus_A" }));
    assertFalse(lu.traite);
    assertEquals(lu.traite ? "" : lu.raison, "type_ignore");
  }
});

Deno.test("une facture sans client ni caserne ne concerne pas ce produit", () => {
  const lu = interpreter(evenement("invoice.paid", { period_end: 1_800_000_000 }));

  assertFalse(lu.traite);
  assertEquals(lu.traite ? "" : lu.raison, "sans_client");
});

Deno.test("une caserne nommée avec un identifiant mal formé est traitée comme absente", () => {
  // `client_reference_id` vient du dehors : un lien de paiement public l'accepte
  // en paramètre d'URL. Une valeur illisible partirait telle quelle dans une RPC
  // typée `uuid`, où elle deviendrait une erreur de requête traduite en 500 — et
  // Stripe rejouerait trois jours durant un événement qui ne passera jamais.
  for (const brut of ["pas-un-uuid", "", "  ", "aaaaaaaa-0000-4000-8000", 42]) {
    const lu = interpreter(evenement("checkout.session.completed", {
      client_reference_id: brut,
      customer: "cus_A",
      payment_status: "paid",
    }));

    assert(lu.traite, `« ${brut} » ne doit pas faire échouer l'événement`);
    // La caserne se retrouvera par le client, chemin normal de tous les
    // événements sauf le premier.
    assertEquals(lu.consequence.station, null);
    assertEquals(lu.consequence.customer, "cus_A");
  }
});

Deno.test("un identifiant de caserne bien formé est conservé", () => {
  const lu = interpreter(evenement("checkout.session.completed", {
    client_reference_id: CASERNE,
    customer: "cus_A",
    payment_status: "paid",
  }));

  assert(lu.traite);
  assertEquals(lu.consequence.station, CASERNE);
});

Deno.test("un événement sans type ni données ne fait pas tomber la fonction", () => {
  assertFalse(interpreter({}).traite);
  assertFalse(interpreter({ type: "invoice.paid" }).traite);
  assertFalse(interpreter({ type: 42, data: null }).traite);
});

// ---------------------------------------------------------------------------
// Les briques
// ---------------------------------------------------------------------------

Deno.test("dateStripe traduit les secondes, et refuse le reste", () => {
  assertEquals(dateStripe(1_800_000_000), "2027-01-15T08:00:00.000Z");
  assertEquals(dateStripe("1800000000"), "2027-01-15T08:00:00.000Z");
  assertEquals(dateStripe(0), null);
  assertEquals(dateStripe(null), null);
  assertEquals(dateStripe("bientôt"), null);
});

Deno.test("statutDepuisStripe ramène les statuts Stripe aux cinq du produit", () => {
  assertEquals(statutDepuisStripe("active"), "active");
  assertEquals(statutDepuisStripe("trialing"), "trialing");
  assertEquals(statutDepuisStripe("past_due"), "past_due");
  assertEquals(statutDepuisStripe("unpaid"), "past_due");
  assertEquals(statutDepuisStripe("canceled"), "cancelled");
  assertEquals(statutDepuisStripe("incomplete_expired"), "cancelled");
  // `suspended` n'est jamais rendu : c'est un état que ce produit décide seul,
  // par sa tâche planifiée. Stripe ne sait rien de nos quatorze jours.
  assertEquals(statutDepuisStripe("paused"), null);
  assertEquals(statutDepuisStripe("incomplete"), null);
  assertEquals(statutDepuisStripe(undefined), null);
});

Deno.test("formuleDepuisAbonnement lit l'intervalle, et retombe sur les métadonnées", () => {
  assertEquals(
    formuleDepuisAbonnement({ items: { data: [{ price: { recurring: { interval: "month" } } }] } }),
    "monthly",
  );
  assertEquals(
    formuleDepuisAbonnement({ items: { data: [{ price: { recurring: { interval: "year" } } }] } }),
    "yearly",
  );
  // Un prix à la semaine n'est pas une formule du produit : on ne devine pas.
  assertEquals(
    formuleDepuisAbonnement({ items: { data: [{ price: { recurring: { interval: "week" } } }] } }),
    null,
  );
  assertEquals(formuleDepuisAbonnement({ metadata: { plan: "yearly" } }), "yearly");
  assertEquals(formuleDepuisAbonnement({}), null);
});
