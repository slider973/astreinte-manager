// La lecture de la liste de personnes d'une requête `invite-member` (ticket 047).
//
//   deno test supabase/functions/tests/
//
// Ni base ni réseau. Ce que ces cas protègent : un fichier de chef de centre
// arrive ici sans avoir été relu par personne, et c'est cette fonction qui décide
// qui sera invité, sous quel nom et avec quel rôle.

import { assertEquals } from "jsr:@std/assert@1";

import { lirePersonnes } from "../_shared/invitation_people.ts";

Deno.test("les trois formes de corps donnent la même sortie normalisée", () => {
  assertEquals(lirePersonnes({ email: " Marie@Exemple.FR " }, "member"), [
    { email: "marie@exemple.fr", firstName: undefined, lastName: undefined, role: "member" },
  ]);

  assertEquals(lirePersonnes({ emails: ["A@x.fr", "b@X.fr"] }, "admin"), [
    { email: "a@x.fr", firstName: undefined, lastName: undefined, role: "admin" },
    { email: "b@x.fr", firstName: undefined, lastName: undefined, role: "admin" },
  ]);

  assertEquals(
    lirePersonnes({ people: [{ email: "A@x.fr" }] }, "member"),
    [{ email: "a@x.fr", firstName: undefined, lastName: undefined, role: "member" }],
  );
});

Deno.test("un rôle par personne, le rôle du lot en repli", () => {
  const lues = lirePersonnes({
    people: [
      { email: "chef@x.fr", role: "admin" },
      { email: "pompier@x.fr" },
      { email: "autre@x.fr", role: "member" },
    ],
  }, "member");

  assertEquals(lues?.map((p) => [p.email, p.role]), [
    ["chef@x.fr", "admin"],
    ["pompier@x.fr", "member"],
    ["autre@x.fr", "member"],
  ]);
});

Deno.test("les noms sont resserrés, et un nom vide n'en est pas un", () => {
  const lues = lirePersonnes({
    people: [
      { email: "a@x.fr", first_name: "  Marie  ", last_name: "Le\tFèbvre" },
      { email: "b@x.fr", first_name: "   ", last_name: "" },
      { email: "c@x.fr", first_name: 42, last_name: null },
    ],
  }, "member");

  assertEquals(lues?.map((p) => [p.firstName, p.lastName]), [
    ["Marie", "Le Fèbvre"],
    [undefined, undefined],
    [undefined, undefined],
  ]);
});

Deno.test("un doublon garde la première occurrence, donc le premier nom", () => {
  // L'ordre du fichier fait foi : une seconde ligne pour la même adresse n'a
  // aucune raison d'écraser ce que la première disait.
  const lues = lirePersonnes({
    people: [
      { email: "marie@x.fr", first_name: "Marie" },
      { email: "MARIE@x.fr", first_name: "Marion" },
    ],
  }, "member");

  assertEquals(lues?.length, 1);
  assertEquals(lues?.[0].firstName, "Marie");
});

Deno.test("un corps mal formé est refusé en bloc, jamais rattrapé à moitié", () => {
  assertEquals(lirePersonnes({}, "member"), null);
  assertEquals(lirePersonnes({ emails: [] }, "member"), null);
  assertEquals(lirePersonnes({ people: [{ email: 12 }] }, "member"), null);
  assertEquals(lirePersonnes({ people: ["ok@x.fr", 12] }, "member"), null);
  assertEquals(
    lirePersonnes({ people: [{ email: "a@x.fr", role: "chef" }] }, "member"),
    null,
  );
});

Deno.test("le plafond de vingt adresses reste celui de l'appel", () => {
  const vingt = Array.from({ length: 20 }, (_, i) => ({ email: `p${i}@x.fr` }));
  assertEquals(lirePersonnes({ people: vingt }, "member")?.length, 20);
  assertEquals(
    lirePersonnes({ people: [...vingt, { email: "p20@x.fr" }] }, "member"),
    null,
  );

  // Vingt et une lignes dont un doublon comptent pour vingt : on déduplique
  // avant de compter, sinon un fichier propre serait refusé pour rien.
  assertEquals(
    lirePersonnes({ people: [...vingt, { email: "P0@x.fr" }] }, "member")?.length,
    20,
  );
});
