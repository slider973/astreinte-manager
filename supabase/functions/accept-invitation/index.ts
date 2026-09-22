// accept-invitation — l'invité connecté entre dans la caserne.
// Référence : docs/SCHEMA.md section 7, ticket 006.
//
// POST /functions/v1/accept-invitation
// En-têtes : Authorization: Bearer <access_token de l'invité>, apikey: <clé anon>
// Corps    : { "token": "<jeton du lien d'invitation>" }
//        ou : { "invitation_id": "<uuid>" }   — ticket 051, exactement l'un des deux
//
// Deux identités sont confrontées : celle du lien (le jeton, qui se transfère) et
// celle de la session (le JWT, qui ne se transfère pas). L'adresse de la session
// doit être celle qui a été invitée. Le contrôle est fait en SQL, dans la même
// transaction que la création de la membership.
//
// L'entrée par identifiant (ticket 051) sert l'écran « Aucune caserne », qui
// connaît l'identifiant rendu par `my_pending_invitations()` et **jamais** le
// jeton. `accept_invitation_by_id` (migration 0036) confronte l'adresse de la
// session à celle de l'invitation avant toute autre chose, résout le jeton en base
// et rejoue `accept_invitation` : mêmes contrôles, mêmes codes, mêmes réponses. Le
// jeton ne traverse ni le réseau ni cette fonction.

import { errorResponse, jsonResponse, preflight, readJsonBody } from "../_shared/http.ts";
import { lireEntreeInvitation } from "../_shared/invitation_entree.ts";
import { type AdminClient, adminClient, caller } from "../_shared/supabase.ts";

type AcceptResult = {
  ok: boolean;
  code?: string;
  already_accepted?: boolean;
  accepted_at?: string;
  expires_at?: string;
  invited_email_masked?: string;
  membership?: Record<string, unknown>;
  station?: Record<string, unknown>;
  inviter?: Record<string, unknown>;
};

/** Code métier → statut HTTP et message français. */
const ERREURS: Record<string, { status: number; message: string }> = {
  invitation_not_found: {
    status: 404,
    message: "Ce lien d'invitation n'existe pas ou n'est plus valable.",
  },
  invitation_expired: {
    status: 410,
    message: "Cette invitation a expiré. Demande à ton administrateur de te la renvoyer.",
  },
  invitation_already_accepted: {
    status: 409,
    message: "Cette invitation a déjà été utilisée.",
  },
  email_mismatch: {
    status: 403,
    message: "Cette invitation ne concerne pas l'adresse avec laquelle tu es connecté.",
  },
  station_suspended: {
    status: 403,
    message: "L'abonnement de la caserne est suspendu : impossible de la rejoindre.",
  },
  profile_missing: {
    status: 409,
    message: "Ton profil est introuvable. Reconnecte-toi puis réessaie.",
  },
};

Deno.serve(async (req: Request): Promise<Response> => {
  const options = preflight(req);
  if (options) return options;

  if (req.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Méthode non autorisée.");
  }

  let admin: AdminClient;
  try {
    admin = adminClient();
  } catch (cause) {
    console.error(cause);
    return errorResponse(500, "internal_error", "Configuration serveur incomplète.");
  }

  const utilisateur = await caller(req, admin);
  if (!utilisateur) {
    return errorResponse(
      401,
      "unauthenticated",
      "Connecte-toi avec l'adresse qui a reçu l'invitation.",
    );
  }

  const lecture = lireEntreeInvitation(await readJsonBody(req));
  if (!lecture.ok) {
    return errorResponse(400, "invalid_body", lecture.message);
  }

  // Un seul appel, deux portes d'entrée. Les deux fonctions SQL rendent le même
  // objet et le même vocabulaire de codes : la suite ne sait pas par où on est
  // entré, et n'a pas à le savoir.
  const { data, error } = lecture.entree.mode === "jeton"
    ? await admin.rpc("accept_invitation", {
      p_token: lecture.entree.jeton,
      p_user_id: utilisateur.id,
      p_email: utilisateur.email,
    })
    : await admin.rpc("accept_invitation_by_id", {
      p_invitation: lecture.entree.identifiant,
      p_user_id: utilisateur.id,
      p_email: utilisateur.email,
    });

  if (error) {
    console.error("accept_invitation", error.message);
    return errorResponse(500, "internal_error", "Erreur serveur.");
  }

  const resultat = data as unknown as AcceptResult;

  if (!resultat.ok) {
    const code = resultat.code ?? "internal_error";
    const connu = ERREURS[code];
    // Le contexte (caserne, inviteur, date d'expiration) accompagne l'erreur :
    // c'est ce qui permet à l'écran de proposer « contacter ton administrateur »
    // au lieu d'un cul-de-sac.
    return errorResponse(
      connu?.status ?? 500,
      code,
      connu?.message ?? "Impossible d'accepter cette invitation.",
      {
        ...(resultat.station ? { station: resultat.station } : {}),
        ...(resultat.inviter ? { inviter: resultat.inviter } : {}),
        ...(resultat.expires_at ? { expires_at: resultat.expires_at } : {}),
        ...(resultat.accepted_at ? { accepted_at: resultat.accepted_at } : {}),
        ...(resultat.invited_email_masked
          ? { invited_email_masked: resultat.invited_email_masked }
          : {}),
        ...(code === "email_mismatch" ? { current_email: utilisateur.email } : {}),
      },
    );
  }

  return jsonResponse({
    ok: true,
    already_accepted: resultat.already_accepted === true,
    membership: resultat.membership,
    station: resultat.station,
    inviter: resultat.inviter,
  });
});
