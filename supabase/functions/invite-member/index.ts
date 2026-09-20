// invite-member — un admin invite une ou plusieurs adresses dans SA caserne.
// Référence : docs/SCHEMA.md section 7, ticket 006.
//
// POST /functions/v1/invite-member
// En-têtes : Authorization: Bearer <access_token de l'admin>, apikey: <clé anon>
// Corps    : { "station_id": uuid, "email": string }
//         ou { "station_id": uuid, "emails": string[], "role": "member" | "admin" }
//
// Enchaînement, pour une adresse :
//   1. create_invitation (SQL, service_role) — contrôle du droit d'inviter, création
//      ou prolongation de la ligne invitations, journal d'audit, le tout atomique ;
//   2. création du compte auth s'il n'existe pas (les inscriptions libres sont
//      fermées : un compte ne naît que d'ici, avec la clé de service) ;
//   3. envoi du courriel et trace dans `notifications`.
//
// Le token d'invitation ne sort jamais de cette fonction : il part uniquement dans
// le lien du courriel, vers l'adresse invitée.

import { errorResponse, jsonResponse, preflight, readJsonBody } from "../_shared/http.ts";
import { type AdminClient, adminClient, caller } from "../_shared/supabase.ts";
import { sendMail } from "../_shared/mailer.ts";
import { invitationUrl, renderInvitationEmail } from "../_shared/invitation_email.ts";

const MAX_ADRESSES = 20;

type Role = "member" | "admin";

type CreateInvitationResult = {
  ok: boolean;
  code?: string;
  resent?: boolean;
  token?: string;
  account_exists?: boolean;
  invitee_id?: string | null;
  invitation?: {
    id: string;
    station_id: string;
    email: string;
    role: Role;
    expires_at: string;
    created_at: string;
  };
  station?: { id: string; name: string; slug: string };
  inviter?: {
    id: string;
    first_name: string;
    last_name: string;
    email: string;
  };
};

type ResultatAdresse = {
  email: string;
  status: "invited" | "resent" | "error";
  code?: string;
  message?: string;
  invitation_id?: string;
  role?: Role;
  expires_at?: string;
  email_sent?: boolean;
  email_provider?: string;
};

/** Messages rendus au client, en français, jamais de détail technique. */
const MESSAGES: Record<string, string> = {
  invalid_email: "Cette adresse e-mail n'est pas valide.",
  already_member: "Cette personne est déjà membre actif de la caserne.",
  conflict: "Une invitation pour cette adresse est en cours de création. Réessaie.",
  account_failed: "Le compte n'a pas pu être créé. Réessaie dans un instant.",
  station_not_found: "Cette caserne n'existe pas.",
  not_admin: "Il faut être administrateur de cette caserne pour inviter.",
  station_suspended: "L'abonnement de la caserne est suspendu : les invitations sont bloquées.",
};

function message(code: string): string {
  return MESSAGES[code] ?? "L'invitation a échoué.";
}

/** Normalise, déduplique et borne la liste d'adresses du corps de la requête. */
function lireAdresses(body: Record<string, unknown>): string[] | null {
  const brut: unknown[] = Array.isArray(body.emails)
    ? body.emails
    : typeof body.email === "string"
    ? [body.email]
    : [];
  if (brut.length === 0) return null;

  const vues = new Set<string>();
  for (const valeur of brut) {
    if (typeof valeur !== "string") return null;
    const normalisee = valeur.trim().toLowerCase();
    if (normalisee !== "") vues.add(normalisee);
  }
  if (vues.size === 0 || vues.size > MAX_ADRESSES) return null;
  return [...vues];
}

/**
 * Trace l'envoi dans `notifications` (type `invitation`, canal `email`, voir
 * docs/WORKFLOWS.md section 8). Best effort : une trace manquante ne doit pas
 * faire échouer une invitation déjà créée et déjà envoyée.
 */
async function tracerNotification(
  admin: AdminClient,
  params: {
    userId: string;
    stationId: string;
    stationName: string;
    subject: string;
    sent: boolean;
    error?: string;
  },
): Promise<void> {
  const { error } = await admin.from("notifications").insert({
    station_id: params.stationId,
    user_id: params.userId,
    type: "invitation",
    channel: "email",
    title: params.subject,
    body: `Invitation à rejoindre ${params.stationName}.`,
    data: { route: "/connexion" },
    sent_at: params.sent ? new Date().toISOString() : null,
    delivered: params.sent,
    error: params.error ?? null,
  });
  if (error) console.error("notification invitation non tracée", error.message);
}

async function inviterUneAdresse(
  admin: AdminClient,
  stationId: string,
  email: string,
  role: Role,
  invitedBy: string,
): Promise<ResultatAdresse> {
  const { data, error } = await admin.rpc("create_invitation", {
    p_station: stationId,
    p_email: email,
    p_role: role,
    p_invited_by: invitedBy,
  });

  if (error) {
    console.error("create_invitation", error.message);
    return {
      email,
      status: "error",
      code: "internal_error",
      message: message("internal_error"),
    };
  }

  const resultat = data as unknown as CreateInvitationResult;
  if (!resultat.ok) {
    const code = resultat.code ?? "internal_error";
    return { email, status: "error", code, message: message(code) };
  }

  const invitation = resultat.invitation!;
  const station = resultat.station!;
  const inviter = resultat.inviter!;
  const resent = resultat.resent === true;

  // Le compte de l'invité. auth.enable_signup = false : personne ne peut se créer
  // un compte depuis l'écran de connexion, c'est ici que les comptes naissent.
  let inviteeId = resultat.invitee_id ?? null;
  let accountCreated = false;
  if (!inviteeId) {
    const { data: cree, error: erreurCompte } = await admin.auth.admin.createUser(
      {
        email: invitation.email,
        email_confirm: true,
        user_metadata: { invited_station_id: station.id },
      },
    );
    if (erreurCompte || !cree?.user) {
      console.error(
        "création du compte invité",
        erreurCompte?.message ?? "réponse vide",
      );
      // Sans compte, l'invité ne pourra pas se connecter : on ne laisse pas une
      // invitation orpheline derrière nous, sauf si elle préexistait (renvoi).
      if (!resent) {
        await admin.from("invitations").delete().eq("id", invitation.id);
      }
      return {
        email,
        status: "error",
        code: "account_failed",
        message: message("account_failed"),
      };
    }
    inviteeId = cree.user.id;
    accountCreated = true;
  }

  const courriel = renderInvitationEmail({
    stationName: station.name,
    inviterName: `${inviter.first_name} ${inviter.last_name}`.trim(),
    inviterEmail: inviter.email,
    inviteUrl: invitationUrl(resultat.token!),
    expiresAt: invitation.expires_at,
    role: invitation.role,
    resent,
  });

  const envoi = await sendMail({
    to: invitation.email,
    subject: courriel.subject,
    html: courriel.html,
    text: courriel.text,
  });
  if (!envoi.sent) console.error("envoi de l'invitation", envoi.error);

  await tracerNotification(admin, {
    userId: inviteeId,
    stationId: station.id,
    stationName: station.name,
    subject: courriel.subject,
    sent: envoi.sent,
    error: envoi.error,
  });

  return {
    email: invitation.email,
    status: resent ? "resent" : "invited",
    invitation_id: invitation.id,
    role: invitation.role,
    expires_at: invitation.expires_at,
    email_sent: envoi.sent,
    email_provider: envoi.provider,
  };
}

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
    return errorResponse(401, "unauthenticated", "Il faut être connecté.");
  }

  const body = await readJsonBody(req);
  if (!body) {
    return errorResponse(400, "invalid_body", "Corps de requête invalide.");
  }

  const stationId = typeof body.station_id === "string" ? body.station_id.trim() : "";
  if (stationId === "") {
    return errorResponse(400, "invalid_body", "Le champ station_id est obligatoire.");
  }

  const role: Role = body.role === "admin" ? "admin" : "member";
  if (body.role !== undefined && body.role !== "admin" && body.role !== "member") {
    return errorResponse(400, "invalid_body", "Le rôle doit être « member » ou « admin ».");
  }

  const adresses = lireAdresses(body);
  if (!adresses) {
    return errorResponse(
      400,
      "invalid_body",
      `Donne une adresse (email) ou une liste d'adresses (emails), ${MAX_ADRESSES} au plus.`,
    );
  }

  // Contrôle du droit d'inviter avant tout travail, pour rendre un 403 franc plutôt
  // qu'une liste de résultats en erreur. create_invitation le refait de son côté :
  // c'est elle qui fait autorité, ceci n'est qu'un raccourci de présentation.
  const { data: station, error: erreurStation } = await admin
    .from("stations")
    .select("id")
    .eq("id", stationId)
    .maybeSingle();
  if (erreurStation) {
    console.error("lecture station", erreurStation.message);
    return errorResponse(500, "internal_error", "Erreur serveur.");
  }
  if (!station) {
    return errorResponse(404, "station_not_found", message("station_not_found"));
  }

  const { data: membership, error: erreurMembership } = await admin
    .from("memberships")
    .select("role, status")
    .eq("station_id", stationId)
    .eq("user_id", utilisateur.id)
    .maybeSingle();
  if (erreurMembership) {
    console.error("lecture membership", erreurMembership.message);
    return errorResponse(500, "internal_error", "Erreur serveur.");
  }
  if (!membership || membership.status !== "active" || membership.role !== "admin") {
    return errorResponse(403, "not_admin", message("not_admin"));
  }

  const resultats: ResultatAdresse[] = [];
  for (const adresse of adresses) {
    resultats.push(
      await inviterUneAdresse(admin, stationId, adresse, role, utilisateur.id),
    );
  }

  // Un refus qui vaut pour toute la requête (caserne suspendue, droit perdu entre
  // deux appels) est rendu comme tel plutôt que noyé dans la liste.
  const global = resultats.find(
    (r) =>
      r.status === "error" &&
      (r.code === "station_suspended" || r.code === "not_admin"),
  );
  if (global && resultats.every((r) => r.code === global.code)) {
    return errorResponse(403, global.code!, message(global.code!));
  }

  const invited = resultats.filter((r) => r.status !== "error").length;
  return jsonResponse({
    ok: resultats.every((r) => r.status !== "error"),
    invited,
    failed: resultats.length - invited,
    results: resultats,
  });
});
