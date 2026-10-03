// Le filtre des adresses non distribuables (ticket 076).
//
// La caserne de démonstration a des membres fictifs en `.invalid` (RFC 2606,
// RFC 6761 § 6.4). Leurs courriels ne doivent jamais atteindre Resend : chaque
// rebond abîme la réputation du compte qui porte aussi les invitations.

import { assert, assertEquals } from "jsr:@std/assert@1";

import { adresseNonDistribuable, sendMail } from "../_shared/mailer.ts";

const courriel = (to: string) => ({ to, subject: "Sujet", html: "<p>Corps</p>", text: "Corps" });

Deno.test("adresseNonDistribuable : .invalid et seulement lui", () => {
  assert(adresseNonDistribuable("membre1@demo.astreinte-sp.invalid"));
  assert(adresseNonDistribuable("Chef@Demo.Astreinte-SP.INVALID"));
  assert(adresseNonDistribuable("x@invalid"));
  assert(adresseNonDistribuable("x@demo.invalid."), "point final du nom de domaine");
  assert(!adresseNonDistribuable("revue-apple@astreinte-sp.fr"));
  assert(!adresseNonDistribuable("membre1@caserne-a.test"));
  assert(!adresseNonDistribuable("x@invalid.fr"));
  assert(!adresseNonDistribuable("x@notinvalid"));
});

Deno.test("sendMail : une adresse .invalid ne part pas, sans appel au fournisseur", async () => {
  const fetchOriginal = globalThis.fetch;
  const avant = Deno.env.get("RESEND_API_KEY");
  let appels = 0;
  globalThis.fetch = (() => {
    appels++;
    return Promise.resolve(new Response("{}", { status: 200 }));
  }) as typeof fetch;
  Deno.env.set("RESEND_API_KEY", "re_cle_de_test");
  try {
    const resultat = await sendMail(courriel("membre1@demo.astreinte-sp.invalid"));
    assertEquals(resultat, {
      sent: false,
      provider: "none",
      error: "adresse non distribuable (.invalid)",
    });
    assertEquals(appels, 0);

    // Une vraie adresse part toujours par Resend.
    const reelle = await sendMail(courriel("revue-apple@astreinte-sp.fr"));
    assertEquals(reelle, { sent: true, provider: "resend" });
    assertEquals(appels, 1);
  } finally {
    globalThis.fetch = fetchOriginal;
    if (avant === undefined) Deno.env.delete("RESEND_API_KEY");
    else Deno.env.set("RESEND_API_KEY", avant);
  }
});
