// invite-member — un admin invite une ou plusieurs adresses dans SA caserne.
// Référence : docs/SCHEMA.md section 7, ticket 006.
//
// POST /functions/v1/invite-member
// En-têtes : Authorization: Bearer <access_token de l'admin>, apikey: <clé anon>
// Corps    : { "station_id": uuid, "email": string }
//         ou { "station_id": uuid, "emails": string[], "role": "member" | "admin" }
//         ou { "station_id": uuid, "people": [{ email, first_name?, last_name?, role? }] }
//
// La troisième forme est celle de l'import de fichier (ticket 047) : elle porte le
// nom que l'administrateur a saisi pour chaque personne, et un rôle par personne
// plutôt qu'un rôle par lot — un fichier a une colonne « rôle », et obliger à
// importer deux fois pour deux rôles serait une limite de l'API, pas du métier.
// Les deux premières formes restent valides : l'écran d'invitation à la main et le
// renvoi d'une invitation ne connaissent que des adresses.
//
// Enchaînement, pour une adresse :
//   1. create_invitation (SQL, service_role) — contrôle du droit d'inviter, création
//      ou prolongation de la ligne invitations, journal d'audit, le tout atomique ;
//   2. création du compte auth s'il n'existe pas (les inscriptions libres sont
//      fermées : un compte ne naît que d'ici, avec la clé de service) ;
//   3. envoi du courriel, trace sur l'invitation (`email_sent_at` / `email_error`,
//      migration 0035) et trace dans `notifications`.
//
// Le token d'invitation ne sort jamais de cette fonction : il part uniquement dans
// le lien du courriel, vers l'adresse invitée.
//
// Plafond de débit (ticket 038) : vingt adresses par appel bornaient un appel, pas
// leur nombre. `create_invitation` compte désormais les courriels réellement partis,
// par caserne et par heure (migration 0032), et refuse avec le code `rate_limited`.
// Dès qu'une adresse du lot est refusée pour cette raison, **les suivantes ne sont
// même pas tentées** : le budget est épuisé pour tout le monde, et vingt allers-retours
// pour s'entendre dire vingt fois la même chose ne servent personne.

import { errorResponse, jsonResponse, preflight, readJsonBody } from "../_shared/http.ts";
import {
  type DetailDebit,
  lireDetailDebit,
  messageDebitDepasse,
} from "../_shared/invitation_rate_limit.ts";
import {
  lirePersonnes,
  MAX_ADRESSES,
  type Personne,
  type Role,
} from "../_shared/invitation_people.ts";
import { type AdminClient, adminClient, caller } from "../_shared/supabase.ts";
import { type MailResult, sendMail } from "../_shared/mailer.ts";
import { traceEnvoi } from "../_shared/invitation_trace.ts";
import { invitationUrl, renderInvitationEmail } from "../_shared/invitation_email.ts";

type CreateInvitationResult = {
  ok: boolean;
  code?: string;
  resent?: boolean;
  // Joints au code `rate_limited` (migration 0032).
  scope?: string;
  limit?: number;
  used?: number;
  remaining?: number;
  window_minutes?: number;
  retry_at?: string;
  retry_after_seconds?: number;
  token?: string;
  account_exists?: boolean;
  invitee_id?: string | null;
  invitation?: {
    id: string;
    station_id: string;
    email: string;
    role: Role;
    first_name: string | null;
    last_name: string | null;
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
  /** Renseigné pour le seul code `rate_limited` : de quoi afficher le délai. */
  rate_limit?: DetailDebit;
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
  // `rate_limited` n'est pas ici : sa phrase porte le délai avant de pouvoir
  // réessayer, elle se compose à partir des faits (voir messageDebitDepasse).
};

function message(code: string): string {
  return MESSAGES[code] ?? "L'invitation a échoué.";
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

/**
 * Trace l'envoi **sur l'invitation elle-même** (migration 0035, ticket 048).
 *
 * `tracerNotification` ci-dessus écrit la même chose, mais sur une ligne rattachée
 * au destinataire : l'administrateur n'a aucune raison de pouvoir la lire, et il ne
 * la lit pas. Sans cette seconde trace, une invitation dont le courriel n'est jamais
 * parti ressemble, dans « Invitations en attente », à une invitation partie que le
 * destinataire tarde à accepter.
 *
 * Un succès pose la date et efface le motif d'échec précédent. Un échec pose le
 * motif **sans toucher à la date** : une invitation partie le 12 dont le renvoi du
 * 21 a échoué garde les deux faits, et ils ne se contredisent pas.
 *
 * Best effort, comme la trace de `notifications` : le courriel est déjà parti (ou
 * déjà perdu) quand on arrive ici, et une trace manquante ne doit pas transformer
 * une invitation réussie en erreur. Elle retombe alors sur « on ne sait pas », ce
 * que les deux colonnes nulles veulent précisément dire.
 */
async function tracerEnvoiSurInvitation(
  admin: AdminClient,
  invitationId: string,
  envoi: MailResult,
): Promise<void> {
  const { error } = await admin
    .from("invitations")
    .update(traceEnvoi(envoi))
    .eq("id", invitationId);
  if (error) console.error("envoi d'invitation non tracé", error.message);
}

/**
 * Le refus de débit d'une adresse, avec sa phrase et ses faits.
 *
 * Le message est composé ici plutôt que pris dans MESSAGES : il porte le délai
 * avant de pouvoir réessayer, et ce délai change à chaque seconde.
 */
function refusDebit(email: string, detail: DetailDebit): ResultatAdresse {
  return {
    email,
    status: "error",
    code: "rate_limited",
    message: messageDebitDepasse(detail),
    rate_limit: detail,
  };
}

async function inviterUneAdresse(
  admin: AdminClient,
  stationId: string,
  personne: Personne,
  invitedBy: string,
): Promise<ResultatAdresse> {
  const email = personne.email;
  const { data, error } = await admin.rpc("create_invitation", {
    p_station: stationId,
    p_email: email,
    p_role: personne.role,
    p_invited_by: invitedBy,
    // La migration 0034 les normalise et les borne à son tour : ce qui arrive ici
    // vient d'un fichier que personne n'a relu, pas d'un formulaire.
    p_first_name: personne.firstName,
    p_last_name: personne.lastName,
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
    if (code === "rate_limited") {
      return refusDebit(
        email,
        lireDetailDebit(resultat as unknown as Record<string, unknown>),
      );
    }
    return { email, status: "error", code, message: message(code) };
  }

  const invitation = resultat.invitation!;
  const station = resultat.station!;
  const inviter = resultat.inviter!;
  const resent = resultat.resent === true;

  // Le compte de l'invité. auth.enable_signup = false : personne ne peut se créer
  // un compte depuis l'écran de connexion, c'est ici que les comptes naissent.
  let inviteeId = resultat.invitee_id ?? null;
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

  await tracerEnvoiSurInvitation(admin, invitation.id, envoi);

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

  const personnes = lirePersonnes(body, role);
  if (!personnes) {
    return errorResponse(
      400,
      "invalid_body",
      `Donne une adresse (email), une liste d'adresses (emails) ou une liste de ` +
        `personnes (people), ${MAX_ADRESSES} au plus.`,
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

  const estAdmin = membership?.status === "active" && membership.role === "admin";

  // L'éditeur du produit nomme le premier administrateur d'une caserne qu'il
  // vient de créer (ticket 031) : elle n'a alors aucun membre, donc aucun admin.
  // Le contrôle qui fait autorité reste celui de `create_invitation` ; ceci n'est
  // que le raccourci de présentation, et il doit connaître le même droit.
  let estSuperAdmin = false;
  if (!estAdmin) {
    const { data: superAdmin, error: erreurSuper } = await admin
      .from("super_admins")
      .select("user_id")
      .eq("user_id", utilisateur.id)
      .maybeSingle();
    if (erreurSuper) {
      console.error("lecture super_admins", erreurSuper.message);
      return errorResponse(500, "internal_error", "Erreur serveur.");
    }
    estSuperAdmin = superAdmin !== null;
  }

  if (!estAdmin && !estSuperAdmin) {
    return errorResponse(403, "not_admin", message("not_admin"));
  }

  const resultats: ResultatAdresse[] = [];
  let debitEpuise: DetailDebit | null = null;
  for (const personne of personnes) {
    if (debitEpuise !== null) {
      resultats.push(refusDebit(personne.email, debitEpuise));
      continue;
    }

    const resultat = await inviterUneAdresse(
      admin,
      stationId,
      personne,
      utilisateur.id,
    );
    resultats.push(resultat);
    // Le plafond vaut pour la caserne entière : la place ne reviendra pas d'une
    // adresse à l'autre du même lot.
    if (resultat.code === "rate_limited") debitEpuise = resultat.rate_limit ?? {};
  }

  // Un refus qui vaut pour toute la requête (caserne suspendue, droit perdu entre
  // deux appels, plafond de débit) est rendu comme tel plutôt que noyé dans la
  // liste. Le plafond n'est global que si **aucune** adresse n'est passée : un lot
  // à moitié envoyé garde sa liste, sinon l'administrateur réessaierait des
  // adresses déjà invitées.
  const global = resultats.find(
    (r) =>
      r.status === "error" &&
      (r.code === "station_suspended" || r.code === "not_admin" ||
        r.code === "rate_limited"),
  );
  if (global && resultats.every((r) => r.code === global.code)) {
    if (global.code === "rate_limited") {
      return errorResponse(429, "rate_limited", global.message!, {
        ...(global.rate_limit ?? {}),
      });
    }
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
