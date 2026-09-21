// auto-propose — remplir soixante-deux créneaux sans les remplir à la main.
// Référence : docs/SCHEMA.md § 7, docs/PRD.md § 6.4, docs/WORKFLOWS.md § 3,
// supabase/functions/README.md, design/018-proposition-automatique.md § 4,
// ticket 018.
//
// POST /functions/v1/auto-propose
// En-têtes : Authorization: Bearer <access_token de l'admin>, apikey: <clé anon>
// Corps    : {
//   "schedule_id": uuid,
//   "picks": [{"shift_id": uuid, "user_id": uuid}, …]   // dans l'ordre du mois
// }
//
// Ce que cette fonction fait, et ce qu'elle ne fait pas
// ----------------------------------------------------
// Elle **applique** un plan, elle ne le compose pas. Le classement des
// candidats est celui que le chef de centre lit dans le panneau d'un créneau
// (ticket 017) : il est calculé dans l'application, sur des nombres que la base
// vient de rendre, et le récapitulatif qu'il valide est donc **exactement** ce
// qui part. Recomposer le plan ici en donnerait un second, calculé ailleurs,
// qui pourrait ne pas être celui qu'il a approuvé.
//
// Ce que l'application ne peut pas garantir, la base le garantit :
// `apply_auto_proposal` (migration 0028) revérifie chaque ligne — membre actif,
// disponibilité déclarée, plafonds, effectif requis, doublons — dans une seule
// transaction, et écarte celles qui ne passent pas au lieu de tout refuser.
//
// Aucune notification ne part : un brouillon ne sort pas du bureau
// (docs/WORKFLOWS.md § 3). C'est « Publier » qui fait sonner les téléphones.

import { errorResponse, jsonResponse, preflight, readJsonBody } from "../_shared/http.ts";
import { type AdminClient, adminClient, caller } from "../_shared/supabase.ts";

/** Une ligne écartée par la base, avec son motif. */
type LigneEcartee = {
  shift_id: string | null;
  user_id: string | null;
  code: string;
};

/** Ce que rend `apply_auto_proposal` (migration 0028). */
type ResultatProposition = {
  ok: boolean;
  code?: string;
  status?: string;
  maximum?: number;
  schedule_id?: string;
  station_id?: string;
  applied?: number;
  skipped?: LigneEcartee[];
  shifts_short?: number;
};

/** Messages rendus au client, en français, jamais de détail technique. */
const MESSAGES: Record<string, string> = {
  schedule_not_found: "Ce planning n'existe pas.",
  not_admin: "Il faut être administrateur de cette caserne pour remplir son planning.",
  station_suspended:
    "L'abonnement de la caserne est suspendu : l'application est en lecture seule.",
  schedule_not_draft:
    "Ce planning n'est plus un brouillon : les créneaux s'y repourvoient un par un.",
  invalid_picks: "La proposition est vide ou mal formée.",
  too_many_picks: "La proposition dépasse ce qu'un mois peut contenir.",
};

/** Le statut HTTP de chaque refus métier. */
const STATUTS: Record<string, number> = {
  schedule_not_found: 404,
  not_admin: 403,
  station_suspended: 403,
  schedule_not_draft: 409,
  invalid_picks: 400,
  too_many_picks: 400,
};

function message(code: string): string {
  return MESSAGES[code] ?? "La proposition automatique a échoué.";
}

/** Un uuid lisible dans le corps, ou `null`. Aucune validation de forme : la
 * base a des clés étrangères et des types, et elle les fait respecter mieux
 * qu'une expression régulière recopiée. */
function identifiant(valeur: unknown): string | null {
  if (typeof valeur !== "string") return null;
  const propre = valeur.trim();
  return propre === "" ? null : propre;
}

/** Le plan, nettoyé mais **jamais réordonné** : l'ordre est celui du mois, et
 * c'est lui qui décide qui prend la dernière place d'un quota. */
function plan(valeur: unknown): { shift_id: string; user_id: string }[] | null {
  if (!Array.isArray(valeur)) return null;

  const lignes: { shift_id: string; user_id: string }[] = [];
  for (const ligne of valeur) {
    if (typeof ligne !== "object" || ligne === null) return null;
    const shift = identifiant((ligne as Record<string, unknown>).shift_id);
    const membre = identifiant((ligne as Record<string, unknown>).user_id);
    if (shift === null || membre === null) return null;
    lignes.push({ shift_id: shift, user_id: membre });
  }
  return lignes;
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

  // `verify_jwt = true` n'est qu'un portier : la clé anon le franchit. C'est
  // `caller()` qui établit l'identité réelle, et `apply_auto_proposal` qui
  // établit le droit.
  const utilisateur = await caller(req, admin);
  if (!utilisateur) {
    return errorResponse(401, "unauthenticated", "Il faut être connecté.");
  }

  const body = await readJsonBody(req);
  if (!body) {
    return errorResponse(400, "invalid_body", "Corps de requête invalide.");
  }

  const scheduleId = identifiant(body.schedule_id);
  const picks = plan(body.picks);
  if (scheduleId === null || picks === null) {
    return errorResponse(
      400,
      "invalid_body",
      "Les champs schedule_id et picks sont obligatoires.",
    );
  }

  const { data, error } = await admin.rpc("apply_auto_proposal", {
    p_schedule: scheduleId,
    p_actor: utilisateur.id,
    p_picks: picks,
  });

  if (error) {
    console.error("apply_auto_proposal", error.message);
    return errorResponse(500, "internal_error", "La proposition automatique a échoué.");
  }

  const resultat = data as unknown as ResultatProposition;
  if (!resultat?.ok) {
    const code = resultat?.code ?? "internal_error";
    return errorResponse(STATUTS[code] ?? 500, code, message(code), {
      status: resultat?.status,
      maximum: resultat?.maximum,
    });
  }

  return jsonResponse({
    ok: true,
    schedule_id: resultat.schedule_id,
    /** Attributions réellement posées. Peut être inférieur au plan : l'adjoint
     * a pu remplir un créneau entre la lecture et l'appui. L'écran annonce ce
     * nombre-là, jamais celui qu'il espérait. */
    applied: resultat.applied ?? 0,
    /** Les lignes écartées, avec leur motif. La liste est bornée par la taille
     * du plan, elle-même bornée à 500 par la base. */
    skipped: resultat.skipped ?? [],
    /** Créneaux encore à découvert après coup, comptés en base. */
    shifts_short: resultat.shifts_short ?? 0,
  });
});
