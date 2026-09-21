// La phrase du refus de débit (ticket 038).
//
//   deno test supabase/functions/tests/
//
// Ni base ni réseau : c'est du texte construit à partir des faits que rend
// `create_invitation` (migration 0032). C'est aussi la partie du ticket qu'un
// administrateur voit, et le critère d'acceptation porte dessus — « le message
// affiché à l'admin indique le délai avant de pouvoir réessayer ».

import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";

import {
  CLES_DEBIT,
  delaiEnFrancais,
  lireDetailDebit,
  messageDebitDepasse,
} from "../_shared/invitation_rate_limit.ts";

Deno.test("delaiEnFrancais : une minute entamée est une minute annoncée", () => {
  // Arrondi au-dessus : annoncer 9 minutes pour 9 min 40 ferait réessayer trop tôt.
  assertEquals(delaiEnFrancais(580), "10 minutes");
  assertEquals(delaiEnFrancais(600), "10 minutes");
  assertEquals(delaiEnFrancais(601), "11 minutes");
});

Deno.test("delaiEnFrancais : les bornes", () => {
  assertEquals(delaiEnFrancais(0), "moins d'une minute");
  assertEquals(delaiEnFrancais(45), "moins d'une minute");
  assertEquals(delaiEnFrancais(60), "moins d'une minute");
  assertEquals(delaiEnFrancais(61), "2 minutes");
  assertEquals(delaiEnFrancais(3540), "59 minutes");
  assertEquals(delaiEnFrancais(3600), "une heure");
  assertEquals(delaiEnFrancais(Number.NaN), "moins d'une minute");
});

Deno.test("messageDebitDepasse : une phrase, avec le plafond et le délai", () => {
  const phrase = messageDebitDepasse({
    scope: "station",
    limit: 60,
    used: 60,
    remaining: 0,
    window_minutes: 60,
    retry_after_seconds: 730,
  });

  assertEquals(
    phrase,
    "Limite d'invitations atteinte (60 par heure pour cette caserne). " +
      "Réessaie dans 13 minutes.",
  );
});

Deno.test("messageDebitDepasse : le super-administrateur est plafonné sur son compte", () => {
  const phrase = messageDebitDepasse({
    scope: "actor",
    limit: 200,
    window_minutes: 60,
    retry_after_seconds: 120,
  });

  assertStringIncludes(phrase, "200 par heure pour ton compte");
  assertStringIncludes(phrase, "Réessaie dans 2 minutes.");
});

Deno.test("messageDebitDepasse : sans délai connu, on ne l'invente pas", () => {
  assertEquals(
    messageDebitDepasse({ limit: 60, window_minutes: 60 }),
    "Limite d'invitations atteinte (60 par heure pour cette caserne). Réessaie plus tard.",
  );
  assertEquals(
    messageDebitDepasse({}),
    "Limite d'invitations atteinte. Réessaie plus tard.",
  );
  assertEquals(
    messageDebitDepasse(null),
    "Limite d'invitations atteinte. Réessaie plus tard.",
  );
});

Deno.test("messageDebitDepasse : une fenêtre autre qu'une heure se dit telle quelle", () => {
  assertStringIncludes(
    messageDebitDepasse({ limit: 10, window_minutes: 15, retry_after_seconds: 300 }),
    "10 par 15 minutes pour cette caserne",
  );
});

Deno.test("messageDebitDepasse : la phrase se termine par un point, comme les autres refus", () => {
  for (const secondes of [1, 59, 60, 61, 599, 3600, 7200]) {
    const phrase = messageDebitDepasse({
      limit: 60,
      window_minutes: 60,
      retry_after_seconds: secondes,
    });
    assertEquals(phrase.endsWith("."), true, `manque le point final : ${phrase}`);
    assertStringIncludes(phrase, "Réessaie dans ");
  }
});

Deno.test("lireDetailDebit : les faits du SQL, et rien d'autre", () => {
  const detail = lireDetailDebit({
    ok: false,
    code: "rate_limited",
    scope: "station",
    limit: 5,
    used: 5,
    remaining: 0,
    window_minutes: 60,
    retry_at: "2026-09-21T15:12:00+00:00",
    retry_after_seconds: 240,
    // Ce qui ne doit jamais traverser : un jeton d'invitation n'est pas un fait
    // de débit, et une réponse qui le recopierait le livrerait au client.
    token: "jamais-ici",
  });

  assertEquals(Object.keys(detail).sort(), [...CLES_DEBIT].sort());
  assertEquals((detail as Record<string, unknown>).token, undefined);
  assertEquals(detail.retry_after_seconds, 240);
});

Deno.test("lireDetailDebit : les clés absentes restent absentes", () => {
  assertEquals(lireDetailDebit({ ok: false, code: "rate_limited" }), {});
  assertEquals(lireDetailDebit({ limit: 3, used: null, scope: undefined }), {
    limit: 3,
  });
});
