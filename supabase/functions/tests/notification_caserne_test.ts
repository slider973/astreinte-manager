// La caserne dans les liens et les courriels (ticket 072, décision 2).
//
// Un pompier de deux casernes ouvre un lien de courriel de B alors que l'app est
// sur A : le lien doit dire B. `?station=<uuid>` s'ajoute au chemin public sans
// le changer — un client qui ignore le paramètre lit le même chemin qu'avant.

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";

import {
  avecCaserne,
  lienApplication,
  renderNotificationEmail,
} from "../_shared/notification_email.ts";
import { etiquette } from "../_shared/notification_content.ts";

const B = "bbbbbbbb-0000-4000-8000-000000000001";

Deno.test("avecCaserne ajoute station= au chemin, sans toucher au chemin", () => {
  assertEquals(avecCaserne("/proposals", B), `/proposals?station=${B}`);
  assertEquals(
    avecCaserne("/admin/schedule/2026-10", B),
    `/admin/schedule/2026-10?station=${B}`,
  );
  // Une route qui porterait déjà une requête garde la sienne.
  assertEquals(avecCaserne("/x?a=1", B), `/x?a=1&station=${B}`);
});

Deno.test("avecCaserne omet un identifiant absent ou mal formé", () => {
  assertEquals(avecCaserne("/proposals", null), "/proposals");
  assertEquals(avecCaserne("/proposals", undefined), "/proposals");
  assertEquals(avecCaserne("/proposals", ""), "/proposals");
  // Rien de libre ne se recopie dans une adresse.
  assertEquals(avecCaserne("/proposals", "x&route=/admin"), "/proposals");
  assertEquals(avecCaserne("/proposals", B.toUpperCase()), `/proposals?station=${B}`);
});

Deno.test("lienApplication garde la base et le modèle, caserne comprise", () => {
  const lien = lienApplication("/proposals", B);
  assert(lien.startsWith("http"), lien);
  assert(lien.endsWith(`/proposals?station=${B}`), lien);
  assert(lienApplication("/proposals").endsWith("/proposals"));
});

Deno.test("le bouton du courriel mène à la caserne de la notification", () => {
  const courriel = renderNotificationEmail(
    { titre: "Astreinte proposée", corps: "Le 12 octobre, nuit.", route: "/proposals" },
    { stationName: "CIS Bravo", stationId: B },
  );
  assertStringIncludes(courriel.html, `/proposals?station=${B}`);
  assertStringIncludes(courriel.text, `/proposals?station=${B}`);
  assertStringIncludes(courriel.text, "CIS Bravo");
});

Deno.test("etiquette : la caserne sépare, et l'étiquette tient dans apns-collapse-id", () => {
  assertEquals(
    etiquette("assignment_proposed", { period: "2026-10" }, B),
    "assignment_proposed:2026-10:bbbbbbbb",
  );
  assertEquals(
    etiquette("assignment_proposed", { period: "2026-10" }),
    "assignment_proposed:2026-10",
  );
  assertEquals(etiquette("invitation", {}, B), "invitation:bbbbbbbb");
  // Le type le plus long, avec période et caserne : sous 64 octets.
  const longue = etiquette("subscription_trial_ending", { period: "2026-10" }, B);
  assert(new TextEncoder().encode(longue).length <= 64, longue);
});
