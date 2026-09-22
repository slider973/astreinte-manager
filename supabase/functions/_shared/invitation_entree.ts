// Les deux entrées d'`accept-invitation`, lues avant toute décision. Ticket 051.
//
// Une invitation s'accepte de deux façons, et une seule Edge Function les sert :
//
//   { "token": "<jeton du lien du courriel>" }   — le parcours du ticket 006 ;
//   { "invitation_id": "<uuid>" }                — le parcours du ticket 051,
//                                                  depuis l'écran « Aucune caserne ».
//
// **Exactement l'un des deux.** Les deux ensemble ne sont pas une requête plus
// riche, c'est une requête ambiguë : il faudrait décider laquelle gagne, et cette
// décision-là appartient à l'appelant, pas au serveur. On refuse en `invalid_body`
// plutôt que de choisir à sa place.
//
// Pourquoi un module à part : c'est la seule partie d'`accept-invitation` qui se
// teste sans base ni réseau, et c'est celle qui décide ce que le serveur va aller
// chercher. Elle est couverte par supabase/functions/tests/invitation_entree_test.ts.

import { estUuid } from "./http.ts";

/** Ce que le corps de la requête désigne, une fois tranché. */
export type EntreeInvitation =
  | { mode: "jeton"; jeton: string }
  | { mode: "identifiant"; identifiant: string };

export type LectureEntree =
  | { ok: true; entree: EntreeInvitation }
  | { ok: false; message: string };

/**
 * Lit le corps d'`accept-invitation` et dit lequel des deux chemins il demande.
 *
 * Un refus est toujours un `invalid_body` (400) : ces cas-là relèvent de la forme
 * de la requête, pas de l'état de l'invitation. Aucun d'eux ne renseigne sur
 * l'existence de quoi que ce soit.
 */
export function lireEntreeInvitation(body: Record<string, unknown> | null): LectureEntree {
  const jeton = typeof body?.token === "string" ? body.token.trim() : "";
  const brutIdentifiant = body?.invitation_id;
  const identifiantFourni = brutIdentifiant !== undefined && brutIdentifiant !== null &&
    !(typeof brutIdentifiant === "string" && brutIdentifiant.trim() === "");

  if (jeton !== "" && identifiantFourni) {
    return {
      ok: false,
      message: "Envoie un jeton ou un identifiant d'invitation, pas les deux.",
    };
  }

  if (identifiantFourni) {
    // Le contrôle de forme sert à rendre un refus honnête (400) plutôt qu'un
    // incident serveur (500) traduit d'une erreur de cast PostgREST.
    if (!estUuid(brutIdentifiant)) {
      return { ok: false, message: "L'identifiant d'invitation est invalide." };
    }
    return {
      ok: true,
      entree: { mode: "identifiant", identifiant: (brutIdentifiant as string).trim() },
    };
  }

  if (jeton !== "") {
    return { ok: true, entree: { mode: "jeton", jeton } };
  }

  return { ok: false, message: "Le champ token ou invitation_id est obligatoire." };
}
