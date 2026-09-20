// publish-schedule — le planning quitte le bureau du chef de centre.
// Référence : docs/SCHEMA.md § 7, docs/WORKFLOWS.md § 2, 3 et 4,
// supabase/functions/README.md (§ send-notification), ticket 019.
//
// POST /functions/v1/publish-schedule
// En-têtes : Authorization: Bearer <access_token de l'admin>, apikey: <clé anon>
// Corps    : { "schedule_id": uuid }
//
// Enchaînement, et son ordre n'est pas négociable
// -----------------------------------------------
//   1. `publish_schedule` (SQL, service_role) — droit de l'appelant, statut du
//      planning, `proposed_at` de chaque attribution et journal d'audit, le tout
//      **atomique**. Une publication à moitié faite — des attributions horodatées
//      sur un planning resté en brouillon — ne se rattrape par aucune reprise.
//   2. `send-notification` — **une** notification par membre, avec tous ses
//      créneaux. La fonction SQL rend déjà les destinataires groupés ; l'envoi
//      vient après la transaction et **ne peut donc pas la défaire**. Une
//      notification perdue se rattrape (la relance manuelle, les crons du 022) ;
//      une publication à moitié faite, non.
//
// Un envoi en échec n'annule donc pas la publication : la réponse dit `ok: true`
// pour le planning et rend le compte rendu d'envoi tel quel, avec `notified` à
// jour. L'écran d'administration le montre à l'admin qui vient de cliquer.

import { errorResponse, jsonResponse, preflight, readJsonBody } from "../_shared/http.ts";
import { type AdminClient, adminClient, caller, env } from "../_shared/supabase.ts";

/** Ce que rend `publish_schedule` (migration 0019). */
type ResultatPublication = {
  ok: boolean;
  code?: string;
  status?: string;
  schedule_id?: string;
  station_id?: string;
  published_at?: string;
  period?: string;
  assignments?: number;
  recipients?: { user_id: string; payload: Record<string, unknown> }[];
};

/** Messages rendus au client, en français, jamais de détail technique. */
const MESSAGES: Record<string, string> = {
  schedule_not_found: "Ce planning n'existe pas.",
  not_admin: "Il faut être administrateur de cette caserne pour publier son planning.",
  station_suspended: "L'abonnement de la caserne est suspendu : la publication est bloquée.",
  schedule_not_draft: "Ce planning a déjà été publié.",
};

/** Le statut HTTP de chaque refus métier. */
const STATUTS: Record<string, number> = {
  schedule_not_found: 404,
  not_admin: 403,
  station_suspended: 403,
  schedule_not_draft: 409,
};

function message(code: string): string {
  return MESSAGES[code] ?? "La publication a échoué.";
}

/**
 * Poste la demande groupée à `send-notification`, avec la clé de service en
 * jeton porteur — le seul appelant qu'elle accepte en plus de `x-notify-secret`
 * (supabase/functions/README.md).
 *
 * Ne lève jamais : l'envoi est postérieur à la publication et ne doit pas
 * inventer un échec de publication. Le compte rendu part tel quel dans la
 * réponse.
 */
async function notifier(
  publication: ResultatPublication,
): Promise<Record<string, unknown>> {
  const destinataires = publication.recipients ?? [];
  if (destinataires.length === 0) {
    // Publier un planning sans aucune attribution est légal : c'est en ouvrir
    // la lecture aux membres. Il n'y a simplement personne à prévenir.
    return { ok: true, recipients: 0, delivered: 0, failed: 0, skipped: "no_recipients" };
  }

  try {
    const reponse = await fetch(`${env("SUPABASE_URL")}/functions/v1/send-notification`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${env("SUPABASE_SERVICE_ROLE_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        type: "assignment_proposed",
        station_id: publication.station_id,
        // Fusionnée sous chaque destinataire par `send-notification` : le mois
        // est le même pour tout le monde, les créneaux ne le sont pas.
        payload: { period: publication.period },
        recipients: destinataires,
      }),
    });

    const corps = await reponse.json().catch(() => null);
    if (!reponse.ok) {
      console.error("send-notification", reponse.status, JSON.stringify(corps));
      return {
        ok: false,
        recipients: destinataires.length,
        delivered: 0,
        failed: destinataires.length,
        error: "send_failed",
      };
    }
    return corps as Record<string, unknown>;
  } catch (cause) {
    const detail = cause instanceof Error ? cause.message : String(cause);
    console.error("send-notification injoignable", detail);
    return {
      ok: false,
      recipients: destinataires.length,
      delivered: 0,
      failed: destinataires.length,
      error: "unreachable",
    };
  }
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
    env("SUPABASE_SERVICE_ROLE_KEY");
  } catch (cause) {
    console.error(cause);
    return errorResponse(500, "internal_error", "Configuration serveur incomplète.");
  }

  // `verify_jwt = true` n'est qu'un portier : la clé anon le franchit. C'est
  // `caller()` qui établit l'identité réelle auprès de GoTrue, et
  // `publish_schedule` qui établit le droit.
  const utilisateur = await caller(req, admin);
  if (!utilisateur) {
    return errorResponse(401, "unauthenticated", "Il faut être connecté.");
  }

  const body = await readJsonBody(req);
  if (!body) {
    return errorResponse(400, "invalid_body", "Corps de requête invalide.");
  }

  const scheduleId = typeof body.schedule_id === "string" ? body.schedule_id.trim() : "";
  if (scheduleId === "") {
    return errorResponse(400, "invalid_body", "Le champ schedule_id est obligatoire.");
  }

  const { data, error } = await admin.rpc("publish_schedule", {
    p_schedule: scheduleId,
    p_actor: utilisateur.id,
  });

  if (error) {
    console.error("publish_schedule", error.message);
    return errorResponse(500, "internal_error", "La publication a échoué.");
  }

  const publication = data as unknown as ResultatPublication;
  if (!publication?.ok) {
    const code = publication?.code ?? "internal_error";
    return errorResponse(STATUTS[code] ?? 500, code, message(code), {
      status: publication?.status,
    });
  }

  const envoi = await notifier(publication);

  return jsonResponse({
    ok: true,
    schedule_id: publication.schedule_id,
    station_id: publication.station_id,
    status: publication.status,
    published_at: publication.published_at,
    period: publication.period,
    /** Attributions horodatées `proposed_at` par cette publication. */
    assignments: publication.assignments ?? 0,
    /** **Membres**, pas attributions : sept créneaux font une notification. */
    notified: publication.recipients?.length ?? 0,
    notification: envoi,
  });
});
