// Lecture bornée du corps d'une requête — `_shared/http.ts`.
// Lancement : deno test supabase/functions/tests/ --allow-env
//
// `stripe-webhook` est la **seule fonction publique** du projet, et elle lit le
// corps avant toute authentification : il le faut pour vérifier la signature.
// Sans plafond, un anonyme qui connaît l'adresse fait allouer autant de mémoire
// qu'il veut, puis fait calculer l'empreinte HMAC de l'ensemble.

import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import { estUuid, lireCorpsBorne, TAILLE_CORPS_MAX } from "../_shared/http.ts";

function requete(corps: BodyInit | null, entetes: HeadersInit = {}): Request {
  return new Request("https://exemple.test/", { method: "POST", body: corps, headers: entetes });
}

/** Un corps envoyé morceau par morceau, **sans `Content-Length`** — c'est ce que
 * produit un envoi en `chunked`, et c'est le cas que l'en-tête ne couvre pas. */
function fluxDe(morceaux: string[]): ReadableStream<Uint8Array> {
  const encodeur = new TextEncoder();
  let index = 0;
  return new ReadableStream<Uint8Array>({
    pull(controleur) {
      if (index >= morceaux.length) {
        controleur.close();
        return;
      }
      controleur.enqueue(encodeur.encode(morceaux[index++]));
    },
  });
}

Deno.test("un corps normal est lu tel quel, à l'octet près", async () => {
  const corps = JSON.stringify({ id: "evt_1", type: "invoice.paid" });

  assertEquals(await lireCorpsBorne(requete(corps)), corps);
});

Deno.test("les accents survivent : le corps est signé tel qu'il arrive", async () => {
  const corps = '{"nom":"CIS Saint-Martin — créneau nuit"}';

  assertEquals(await lireCorpsBorne(requete(corps)), corps);
});

Deno.test("un corps vide rend une chaîne vide, pas null", async () => {
  // `null` veut dire « refusé » : un corps absent ne doit pas s'y confondre.
  assertEquals(await lireCorpsBorne(requete(null)), "");
});

Deno.test("un Content-Length au-dessus du plafond refuse **sans rien lire**", async () => {
  const req = requete("court", { "content-length": String(TAILLE_CORPS_MAX + 1) });

  assertEquals(await lireCorpsBorne(req), null);
});

Deno.test("un corps trop gros est refusé même **sans** Content-Length", async () => {
  // La barrière qui compte : l'en-tête n'est pas obligatoire et peut mentir.
  // Seul le compte réel des octets lus tranche.
  const bloc = "a".repeat(64);
  const morceaux = Array.from({ length: 10 }, () => bloc);

  assertEquals(await lireCorpsBorne(requete(fluxDe(morceaux)), 100), null);
});

Deno.test("un Content-Length qui ment ne fait pas passer un gros corps", async () => {
  const req = new Request("https://exemple.test/", {
    method: "POST",
    body: fluxDe(["a".repeat(500)]),
    headers: { "content-length": "10" },
  });

  assertEquals(await lireCorpsBorne(req, 100), null);
});

Deno.test("un corps trop gros est **vidé sans rien garder**, pas seulement annulé", async () => {
  // Se contenter d'annuler laisse l'émetteur écrire dans une connexion que plus
  // personne ne lit : la passerelle coupe, et l'appelant voit une erreur réseau
  // au lieu du 413 qu'on vient de composer. Vider coûte de la bande passante,
  // jamais de la mémoire — et c'est la mémoire qu'on protège.
  let termine = false;
  const flux = new ReadableStream<Uint8Array>({
    start(controleur) {
      controleur.enqueue(new Uint8Array(500));
      controleur.close();
    },
    cancel() {
      termine = true;
    },
  });

  assertEquals(await lireCorpsBorne(requete(flux), 100), null);
  // Le flux est allé jusqu'au bout tout seul : il n'a pas eu à être coupé.
  assertFalse(termine);
});

Deno.test("un corps sans fin est coupé : le vidage est lui-même borné", async () => {
  // Sinon un envoi infini tiendrait le processus aussi sûrement que l'allocation
  // qu'on vient d'empêcher.
  let blocs = 0;
  const bloc = new Uint8Array(64 * 1024);
  const flux = new ReadableStream<Uint8Array>({
    pull(controleur) {
      blocs++;
      controleur.enqueue(bloc.slice());
    },
  });

  assertEquals(await lireCorpsBorne(requete(flux), 100), null);
  // 8 Mo de purge par blocs de 64 ko : 128 blocs, et pas un de plus.
  assert(blocs < 200, `${blocs} blocs lus : le vidage n'est pas borné`);
});

Deno.test("un corps pile à la limite passe", async () => {
  const corps = "a".repeat(100);

  assertEquals(await lireCorpsBorne(requete(corps), 100), corps);
});

Deno.test("le plafond par défaut laisse largement passer un événement réel", () => {
  // Un événement Stripe dépasse rarement 100 ko.
  assertEquals(TAILLE_CORPS_MAX, 1024 * 1024);
});

Deno.test("estUuid refuse ce qui n'a pas la forme d'un identifiant", () => {
  assert(estUuid("aaaaaaaa-0000-4000-8000-000000000001"));
  assert(estUuid("AAAAAAAA-0000-4000-8000-000000000001"));
  assert(estUuid("  aaaaaaaa-0000-4000-8000-000000000001  "));

  // Le cas qui comptait : ces valeurs partaient dans une requête PostgREST et en
  // revenaient en « incident serveur », pour une faute de frappe.
  for (const valeur of ["", "   ", "pas-un-uuid", "aaaaaaaa-0000-4000-8000", 42, null, undefined]) {
    assert(!estUuid(valeur), `« ${valeur} » ne doit pas passer`);
  }
});
