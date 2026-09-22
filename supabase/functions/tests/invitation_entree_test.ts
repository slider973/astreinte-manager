// Les deux entrées d'`accept-invitation` (ticket 051).
//
//   deno test supabase/functions/tests/
//
// Ni base ni réseau : `lireEntreeInvitation` décide ce que le serveur va aller
// chercher, à partir du seul corps de la requête. C'est la dernière frontière
// avant l'appel SQL, et le seul endroit où un corps mal formé doit s'arrêter.

import { assert, assertEquals } from "jsr:@std/assert@1";

import { lireEntreeInvitation } from "../_shared/invitation_entree.ts";

const ID = "51510000-0000-4000-8000-000000000001";

Deno.test("le jeton du lien du courriel reste le chemin du ticket 006", () => {
  const lecture = lireEntreeInvitation({ token: "  abc123  " });
  assert(lecture.ok);
  assertEquals(lecture.entree, { mode: "jeton", jeton: "abc123" });
});

Deno.test("un identifiant d'invitation ouvre le chemin de l'écran « Aucune caserne »", () => {
  const lecture = lireEntreeInvitation({ invitation_id: ID });
  assert(lecture.ok);
  assertEquals(lecture.entree, { mode: "identifiant", identifiant: ID });
});

Deno.test("les deux à la fois ne sont pas une requête plus riche, mais une requête ambiguë", () => {
  // Choisir à la place de l'appelant reviendrait à deviner lequel des deux
  // chemins il croyait emprunter. On refuse, il tranche.
  const lecture = lireEntreeInvitation({ token: "abc123", invitation_id: ID });
  assert(!lecture.ok);
  assertEquals(lecture.message, "Envoie un jeton ou un identifiant d'invitation, pas les deux.");
});

Deno.test("un identifiant qui n'est pas un UUID est un refus honnête, pas un incident serveur", () => {
  // Sans ce contrôle, PostgREST rend une erreur de cast et la fonction la
  // traduirait en 500 : un corps malformé n'est pas une panne.
  for (const valeur of ["pas-un-uuid", "51510000-0000-4000-8000", 42, true, { id: ID }, [ID]]) {
    const lecture = lireEntreeInvitation({ invitation_id: valeur });
    assert(!lecture.ok, `refusé : ${JSON.stringify(valeur)}`);
    assertEquals(lecture.message, "L'identifiant d'invitation est invalide.");
  }
});

Deno.test("un corps vide, absent ou sans champ utile dit lequel des deux il manque", () => {
  for (const corps of [null, {}, { token: "   " }, { token: 42 }, { invitation_id: "  " }]) {
    const lecture = lireEntreeInvitation(corps as Record<string, unknown> | null);
    assert(!lecture.ok, `refusé : ${JSON.stringify(corps)}`);
    assertEquals(lecture.message, "Le champ token ou invitation_id est obligatoire.");
  }
});

Deno.test("un identifiant explicitement nul laisse la place au jeton", () => {
  // Un client qui envoie toujours les deux clés, dont une à null, emprunte le
  // chemin de celle qui est renseignée — ce n'est pas l'ambiguïté du cas ci-dessus.
  const lecture = lireEntreeInvitation({ token: "abc123", invitation_id: null });
  assert(lecture.ok);
  assertEquals(lecture.entree, { mode: "jeton", jeton: "abc123" });
});
