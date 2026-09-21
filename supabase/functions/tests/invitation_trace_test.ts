// La trace d'envoi écrite sur l'invitation (ticket 048, migration 0035).
//
//   deno test supabase/functions/tests/
//
// Ni base ni réseau : `traceEnvoi` transforme le verdict de `sendMail` en colonnes
// à écrire. Ce qui se joue ici, c'est ce que l'écran « Invitations en attente »
// pourra dire — et ce qu'il ne devra pas dire.

import { assert, assertEquals } from "jsr:@std/assert@1";

import { MOTIF_MAX, traceEnvoi } from "../_shared/invitation_trace.ts";

Deno.test("un envoi réussi pose la date et efface le motif d'échec précédent", () => {
  const trace = traceEnvoi(
    { sent: true, provider: "resend" },
    new Date("2026-09-21T14:03:00.000Z"),
  );
  assertEquals(trace.email_sent_at, "2026-09-21T14:03:00.000Z");
  // `null` explicite, pas une clé absente : c'est l'effacement qui compte. Une
  // invitation repartie ne doit plus afficher l'échec d'avant-hier.
  assertEquals(trace.email_error, null);
});

Deno.test("un échec pose le motif sans toucher à la date du dernier envoi réussi", () => {
  const trace = traceEnvoi({
    sent: false,
    provider: "mailpit",
    error: "mailpit 500 connexion refusée",
  });
  assertEquals(trace.email_error, "mailpit 500 connexion refusée");
  // La clé est absente : la colonne n'est pas écrite. Une invitation partie le 12
  // dont le renvoi du 21 échoue garde sa date du 12.
  assert(!("email_sent_at" in trace));
});

Deno.test("l'incident de production du 21 septembre 2026 laisse une trace lisible", () => {
  // Aucun fournisseur configuré : l'invitation existe, personne n'a été prévenu.
  const trace = traceEnvoi({
    sent: false,
    provider: "none",
    error: "aucun fournisseur de courriel configuré",
  });
  assertEquals(trace.email_error, "aucun fournisseur de courriel configuré");
  assert(!("email_sent_at" in trace));
});

Deno.test("un échec sans raison reste un échec, jamais un « on ne sait pas »", () => {
  // Les deux colonnes nulles veulent dire « on ne sait pas » : écrire un motif
  // vide reviendrait à effacer ce qu'on vient d'apprendre.
  const trace = traceEnvoi({ sent: false, provider: "none" });
  assertEquals(trace.email_error, "envoi impossible (none)");

  const blanc = traceEnvoi({ sent: false, provider: "resend", error: "   " });
  assertEquals(blanc.email_error, "envoi impossible (resend)");
});

Deno.test("le motif est borné", () => {
  const trace = traceEnvoi({
    sent: false,
    provider: "resend",
    error: `resend 422 ${"x".repeat(500)}`,
  });
  assertEquals(trace.email_error!.length, MOTIF_MAX);
});
