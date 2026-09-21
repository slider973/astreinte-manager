// Vérification de la signature des événements Stripe — `_shared/stripe.ts`.
// Ticket 029, critère d'acceptation « Signature du webhook vérifiée, rejet
// sinon ». Lancement : deno test supabase/functions/tests/ --allow-env
//
// C'est **le** point de sécurité du ticket. `stripe-webhook` est publique : la
// signature est tout ce qui distingue un événement de Stripe d'un événement
// forgé par le premier venu qui connaît l'URL. Et un événement forgé vaut
// « cette caserne est active » — ou « cette caserne est suspendue », donc en
// lecture seule pour tous ses pompiers.

import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  analyserEnteteSignature,
  encoderFormulaire,
  memeSignature,
  signer,
  TOLERANCE_SECONDES,
  verifierSignature,
} from "../_shared/stripe.ts";

const SECRET = "whsec_un_secret_de_test_quelconque";
const CORPS = JSON.stringify({
  id: "evt_1",
  type: "invoice.paid",
  data: { object: { customer: "cus_A" } },
});
const INSTANT = 1_760_000_000;

/** Un en-tête `Stripe-Signature` authentique pour ce corps et ce secret. */
async function enteteValide(
  corps = CORPS,
  horodatage = INSTANT,
  secret = SECRET,
): Promise<string> {
  return `t=${horodatage},v1=${await signer(secret, `${horodatage}.${corps}`)}`;
}

Deno.test("un événement signé par Stripe est accepté", async () => {
  const resultat = await verifierSignature(CORPS, await enteteValide(), SECRET, {
    instant: INSTANT,
  });

  assert(resultat.ok, "la signature authentique doit passer");
  assertEquals(resultat.horodatage, INSTANT);
});

Deno.test("un événement forgé est rejeté", async () => {
  // Le scénario réel : quelqu'un connaît l'URL, lit la documentation de Stripe,
  // fabrique un en-tête à la bonne forme, et espère que personne ne vérifie.
  const forge = `t=${INSTANT},v1=${"f".repeat(64)}`;

  const resultat = await verifierSignature(CORPS, forge, SECRET, { instant: INSTANT });

  assertFalse(resultat.ok);
  assertEquals(resultat.ok ? "" : resultat.code, "signature_mismatch");
});

Deno.test("un événement signé avec un autre secret est rejeté", async () => {
  const entete = await enteteValide(CORPS, INSTANT, "whsec_secret_d_un_autre_projet");

  const resultat = await verifierSignature(CORPS, entete, SECRET, { instant: INSTANT });

  assertFalse(resultat.ok);
  assertEquals(resultat.ok ? "" : resultat.code, "signature_mismatch");
});

Deno.test("un corps modifié après signature est rejeté", async () => {
  // La signature authentique d'un autre corps : c'est ce que produirait une
  // attaque par rejeu où l'on remplace `cus_A` par `cus_B`.
  const entete = await enteteValide();
  const altere = CORPS.replace("cus_A", "cus_B");

  const resultat = await verifierSignature(altere, entete, SECRET, { instant: INSTANT });

  assertFalse(resultat.ok);
  assertEquals(resultat.ok ? "" : resultat.code, "signature_mismatch");
});

Deno.test("le corps est signé **à l'octet près**, pas après re-sérialisation", async () => {
  // Le piège classique : `JSON.parse` puis `JSON.stringify` change l'ordre des
  // clés et les espaces. La signature d'un corps « équivalent » ne vaut rien.
  const espace = JSON.stringify(JSON.parse(CORPS), null, 2);
  const entete = await enteteValide();

  const resultat = await verifierSignature(espace, entete, SECRET, { instant: INSTANT });

  assertFalse(resultat.ok, "un corps ré-indenté n'est plus le corps signé");
});

Deno.test("sans en-tête de signature, rien ne passe", async () => {
  for (const entete of [null, "", "   "]) {
    const resultat = await verifierSignature(CORPS, entete, SECRET, { instant: INSTANT });
    assertFalse(resultat.ok);
    assertEquals(resultat.ok ? "" : resultat.code, "missing_signature");
  }
});

Deno.test("un en-tête illisible est rejeté sans être interprété", async () => {
  for (const entete of ["bonjour", "t=abc,v1=ff", `t=${INSTANT}`, "v1=ff"]) {
    const resultat = await verifierSignature(CORPS, entete, SECRET, { instant: INSTANT });
    assertFalse(resultat.ok, `« ${entete} » ne doit pas passer`);
    assertEquals(resultat.ok ? "" : resultat.code, "malformed_signature");
  }
});

Deno.test("un événement trop vieux est rejeté : une signature captée ne se rejoue pas", async () => {
  const entete = await enteteValide();

  const limite = await verifierSignature(CORPS, entete, SECRET, {
    instant: INSTANT + TOLERANCE_SECONDES,
  });
  assert(limite.ok, "à la seconde près, la tolérance tient encore");

  const trop = await verifierSignature(CORPS, entete, SECRET, {
    instant: INSTANT + TOLERANCE_SECONDES + 1,
  });
  assertFalse(trop.ok);
  assertEquals(trop.ok ? "" : trop.code, "timestamp_out_of_tolerance");
});

Deno.test("un événement daté du futur est rejeté aussi", async () => {
  // Une horloge décalée d'un côté ou de l'autre produit le même symptôme, et la
  // fenêtre doit être symétrique : sans ça, un horodatage à l'an 3000 passerait.
  const entete = await enteteValide(CORPS, INSTANT + 3600);

  const resultat = await verifierSignature(CORPS, entete, SECRET, { instant: INSTANT });

  assertFalse(resultat.ok);
  assertEquals(resultat.ok ? "" : resultat.code, "timestamp_out_of_tolerance");
});

Deno.test("plusieurs v1 : une rotation de secret en cours passe", async () => {
  // Pendant une rotation, Stripe signe avec l'ancien **et** le nouveau secret.
  const bonne = await signer(SECRET, `${INSTANT}.${CORPS}`);
  const entete = `t=${INSTANT},v1=${"a".repeat(64)},v1=${bonne},v0=ignoree`;

  const resultat = await verifierSignature(CORPS, entete, SECRET, { instant: INSTANT });

  assert(resultat.ok, "il suffit qu'une des signatures corresponde");
});

Deno.test("un v0 seul ne suffit pas : c'est l'ancien schéma", async () => {
  const entete = `t=${INSTANT},v0=${await signer(SECRET, `${INSTANT}.${CORPS}`)}`;

  const resultat = await verifierSignature(CORPS, entete, SECRET, { instant: INSTANT });

  assertFalse(resultat.ok);
  assertEquals(resultat.ok ? "" : resultat.code, "malformed_signature");
});

Deno.test("analyserEnteteSignature lit t et les v1, et ignore le reste", () => {
  const analyse = analyserEnteteSignature("t=42, v1=aa , v1=bb,v0=cc,inconnu");

  assertEquals(analyse?.horodatage, 42);
  assertEquals(analyse?.signatures, ["aa", "bb"]);
});

Deno.test("memeSignature ne se laisse pas avoir par un préfixe", () => {
  assert(memeSignature("abcdef", "abcdef"));
  assertFalse(memeSignature("abcdef", "abcde"));
  assertFalse(memeSignature("abc", "abcdef"));
  assertFalse(memeSignature("abcdef", "abcdeg"));
});

Deno.test("encoderFormulaire produit la notation en crochets de Stripe", () => {
  const encode = encoderFormulaire({
    mode: "subscription",
    line_items: [{ price: "price_123", quantity: 1 }],
    metadata: { station_id: "aaaa-bbbb" },
    subscription_data: { metadata: { plan: "monthly" } },
    absent: null,
  });

  const morceaux = encode.split("&");
  assert(morceaux.includes("mode=subscription"));
  assert(morceaux.includes(encodeURIComponent("line_items[0][price]") + "=price_123"));
  assert(morceaux.includes(encodeURIComponent("line_items[0][quantity]") + "=1"));
  assert(morceaux.includes(encodeURIComponent("metadata[station_id]") + "=aaaa-bbbb"));
  assert(
    morceaux.includes(encodeURIComponent("subscription_data[metadata][plan]") + "=monthly"),
  );
  assertFalse(encode.includes("absent"), "une valeur nulle n'est pas envoyée");
});
