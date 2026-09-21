// Le contrôle de droits de `create-checkout` — `create-checkout/acces.ts`.
// Lancement : deno test supabase/functions/tests/ --allow-env
//
// C'est la règle la plus coûteuse à perdre au premier refactor : elle décide qui
// peut engager une dépense au nom d'une caserne, et qui peut ouvrir le portail
// où l'on change de carte et où l'on résilie. Avant ce fichier, elle ne vivait
// que dans `scripts/test_functions.sh`, qui ne tourne pas en CI faute de pile
// locale — donc elle ne cassait aucun test quand on la retirait.

import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  type AbonnementCaserne,
  abonnementVivant,
  type Action,
  actionValide,
  autoriser,
  portailOuvrable,
} from "../create-checkout/acces.ts";

function abonnement(
  statut: string,
  { client = "cus_A", sub = "sub_A" }: { client?: string | null; sub?: string | null } = {},
): AbonnementCaserne {
  return { status: statut, stripe_customer_id: client, stripe_subscription_id: sub };
}

function verdict(
  {
    action = "checkout" as Action,
    admin = true,
    configure = true,
    abo = null,
    formule = "monthly",
  }: {
    action?: Action;
    admin?: boolean;
    configure?: boolean;
    abo?: AbonnementCaserne | null;
    formule?: "monthly" | "yearly" | null;
  } = {},
) {
  return autoriser({
    action,
    estAdminActif: admin,
    configure,
    abonnement: abo,
    formule,
  });
}

function code(v: ReturnType<typeof autoriser>): string {
  return v.ok ? "" : v.code;
}

// ---------------------------------------------------------------------------
// Le droit d'abord
// ---------------------------------------------------------------------------

Deno.test("sans rôle d'administrateur actif, les trois actions sont refusées", () => {
  for (const action of ["state", "checkout", "portal"] as Action[]) {
    const v = verdict({ action, admin: false });
    assertFalse(v.ok, `« ${action} » ne doit pas passer`);
    assertEquals(code(v), "not_admin");
    assertEquals(v.ok ? 0 : v.statut, 403);
  }
});

Deno.test("le refus ne dit pas si la caserne existe, ni si Stripe est branché", () => {
  // Un membre ordinaire qui vise une caserne inconnue et un projet sans compte
  // reçoit exactement la même chose qu'un membre ordinaire de sa propre caserne.
  const v = verdict({ admin: false, configure: false, abo: null });
  assertEquals(code(v), "not_admin");
});

// ---------------------------------------------------------------------------
// `state` répond toujours — c'est ce qui tient l'écran debout sans compte
// ---------------------------------------------------------------------------

Deno.test("« state » passe même sans compte chez le prestataire", () => {
  assert(verdict({ action: "state", configure: false }).ok);
  assert(verdict({ action: "state", configure: true, abo: abonnement("active") }).ok);
});

// ---------------------------------------------------------------------------
// Bloquant 1 : un abonnement en cours ne se souscrit pas deux fois
// ---------------------------------------------------------------------------

Deno.test("**une caserne en retard de paiement ne peut pas souscrire à nouveau**", () => {
  // Le cas qui compte, et le plus banal : une carte qui expire. Son statut
  // n'est pas « active », donc un garde-fou posé sur le seul statut « active »
  // la laisserait repartir avec un second abonnement, prélevé en parallèle du
  // premier, pendant que le premier continue ses relances.
  const v = verdict({ abo: abonnement("past_due") });

  assertFalse(v.ok);
  assertEquals(code(v), "already_subscribed");
  assertEquals(v.ok ? 0 : v.statut, 409);
  // Et le message envoie là où l'on change vraiment de carte.
  assert(v.ok ? false : v.message.includes("Gérer mon abonnement"));
});

Deno.test("les quatre statuts d'un abonnement encore vivant refusent la souscription", () => {
  for (const statut of ["active", "past_due", "trialing", "suspended"]) {
    const v = verdict({ abo: abonnement(statut) });
    assertFalse(v.ok, `« ${statut} » ne doit pas pouvoir souscrire`);
    assertEquals(code(v), "already_subscribed");
  }
});

Deno.test("une résiliation, elle, se reprend", () => {
  // C'est un client qui revient : rien ne se dédouble, l'abonnement d'avant est
  // mort chez le prestataire.
  assert(verdict({ abo: abonnement("cancelled") }).ok);
});

Deno.test("un essai sans abonnement souscrit peut souscrire", () => {
  // Le cas nominal. Le client peut exister — `create-checkout` le pose avant
  // d'ouvrir la session — sans qu'aucun abonnement n'ait été créé.
  assert(verdict({ abo: abonnement("trialing", { sub: null }) }).ok);
  assert(verdict({ abo: abonnement("trialing", { client: null, sub: null }) }).ok);
  assert(verdict({ abo: null }).ok);
});

Deno.test("une caserne suspendue pour essai expiré peut souscrire", () => {
  // Elle n'a jamais rien souscrit : c'est sa sortie de la lecture seule.
  assert(verdict({ abo: abonnement("suspended", { client: null, sub: null }) }).ok);
});

Deno.test("abonnementVivant ne se laisse pas avoir par le statut seul", () => {
  assertFalse(abonnementVivant(null));
  assertFalse(abonnementVivant(abonnement("active", { sub: null })));
  assertFalse(abonnementVivant(abonnement("cancelled")));
  assert(abonnementVivant(abonnement("past_due")));
});

// ---------------------------------------------------------------------------
// La configuration et la formule
// ---------------------------------------------------------------------------

Deno.test("sans compte configuré, souscrire et gérer sont refusés en 503", () => {
  for (const action of ["checkout", "portal"] as Action[]) {
    const v = verdict({ action, configure: false, abo: abonnement("trialing", { sub: null }) });
    assertFalse(v.ok);
    assertEquals(code(v), "stripe_not_configured");
    // 503 et non 500 : rien n'est en panne, le service n'est pas encore ouvert.
    assertEquals(v.ok ? 0 : v.statut, 503);
  }
});

Deno.test("souscrire sans formule, ou avec une formule inconnue, est refusé", () => {
  const v = verdict({ formule: null, abo: null });
  assertFalse(v.ok);
  assertEquals(code(v), "invalid_plan");
  assertEquals(v.ok ? 0 : v.statut, 400);
});

Deno.test("la formule est vérifiée **avant** le garde-fou du doublon", () => {
  // Sinon une caserne déjà abonnée qui envoie une formule inconnue recevrait
  // « déjà abonnée », et corrigerait la mauvaise chose.
  const v = verdict({ formule: null, abo: abonnement("active") });
  assertEquals(code(v), "invalid_plan");
});

// ---------------------------------------------------------------------------
// Le portail
// ---------------------------------------------------------------------------

Deno.test("le portail demande un client, pas un abonnement", () => {
  // Une caserne résiliée garde son client : elle doit pouvoir rouvrir ses
  // factures.
  assert(verdict({ action: "portal", abo: abonnement("cancelled") }).ok);
  assert(verdict({ action: "portal", abo: abonnement("trialing", { sub: null }) }).ok);

  const v = verdict({ action: "portal", abo: abonnement("trialing", { client: null, sub: null }) });
  assertFalse(v.ok);
  assertEquals(code(v), "no_customer");
  assertEquals(v.ok ? 0 : v.statut, 409);
});

Deno.test("portailOuvrable exige le compte **et** le client", () => {
  assertFalse(portailOuvrable(abonnement("active"), false));
  assertFalse(portailOuvrable(abonnement("active", { client: null }), true));
  assertFalse(portailOuvrable(null, true));
  assert(portailOuvrable(abonnement("active"), true));
});

// ---------------------------------------------------------------------------
// Les actions
// ---------------------------------------------------------------------------

Deno.test("actionValide n'accepte que les trois actions du contrat", () => {
  assertEquals(actionValide("state"), "state");
  assertEquals(actionValide("checkout"), "checkout");
  assertEquals(actionValide("portal"), "portal");
  for (const valeur of ["resilier", "", "STATE", 42, null, undefined]) {
    assertEquals(actionValide(valeur), null, `« ${valeur} » ne doit pas passer`);
  }
});
