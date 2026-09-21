// reassign-shift — un refus ne coûte qu'un créneau.
// Référence : docs/SCHEMA.md § 7, docs/WORKFLOWS.md § 2, 3 et 5,
// supabase/functions/README.md, design/020-reattribution.md § 7, ticket 020.
//
// POST /functions/v1/reassign-shift
// En-têtes : Authorization: Bearer <access_token de l'admin>, apikey: <clé anon>
// Corps    : {
//   "shift_id": uuid,                  // le créneau à repourvoir
//   "user_id": uuid,                   // le pompier qui le reprend
//   "previous_assignment_id": uuid?    // l'attribution remplacée, si elle est connue
// }
//
// Un seul appel, et il fait tout
// ------------------------------
// `reassign_shift` (SQL, service_role) écrit **dans la même transaction** : la
// nouvelle attribution, le statut et le lien de l'ancienne, le journal d'audit,
// la réévaluation du planning et les **demandes de notification** posées dans
// `notification_outbox` (migration 0014).
//
// **Pourquoi cette fonction n'appelle pas `send-notification`, contrairement à
// `publish-schedule`.** Une publication groupe trente pompiers et sept créneaux
// chacun : le regroupement se fait en SQL, puis l'envoi part d'ici, après la
// transaction, pour ne pas pouvoir défaire une publication acquise. Une
// réattribution, elle, vise **une** personne et **un** créneau : il n'y a rien à
// grouper, et la file de `notify(...)` — avec son rejeu par
// `cron_dispatch_notifications` — garantit l'envoi même si ce processus meurt
// entre la transaction et l'appel HTTP. Un pompier qui ignore qu'il est
// d'astreinte est le seul défaut que ce ticket n'a pas le droit de produire.
//
// Ce que cette fonction apporte, et que la RPC directe n'apporterait pas :
// l'identité réelle de l'appelant établie auprès de GoTrue (`caller()`), et la
// traduction des refus métier en statuts HTTP et en phrases françaises.

import { errorResponse, jsonResponse, preflight, readJsonBody } from "../_shared/http.ts";
import { type AdminClient, adminClient, caller } from "../_shared/supabase.ts";

/** Ce que rend `reassign_shift` (migration 0020). */
type ResultatReattribution = {
  ok: boolean;
  code?: string;
  status?: string;
  /** Places occupées et places demandées, quand le créneau est déjà pourvu. */
  filled?: number;
  required?: number;
  assignment_id?: string;
  shift_id?: string;
  user_id?: string;
  was_available?: boolean;
  proposed_at?: string;
  previous_id?: string | null;
  previous_user?: string | null;
  previous_status?: string | null;
  previous_notified?: boolean;
  schedule_id?: string;
  station_id?: string;
  schedule_status?: string;
  period?: string;
};

/** Messages rendus au client, en français, jamais de détail technique. */
const MESSAGES: Record<string, string> = {
  shift_not_found: "Ce créneau n'existe pas.",
  not_admin: "Il faut être administrateur de cette caserne pour réattribuer un créneau.",
  station_suspended:
    "L'abonnement de la caserne est suspendu : l'application est en lecture seule.",
  schedule_not_published:
    "Ce planning n'est pas publié : les attributions s'y posent et s'y retirent directement.",
  member_not_active: "Ce pompier n'est pas un membre actif de la caserne.",
  already_assigned: "Ce pompier est déjà attribué à ce créneau.",
  shift_already_filled:
    "Ce créneau est déjà pourvu. Augmente son effectif requis pour y ajouter quelqu'un.",
  assignment_not_found: "L'attribution à remplacer n'existe pas sur ce créneau.",
  assignment_not_replaceable: "Cette attribution a déjà été remplacée.",
};

/** Le statut HTTP de chaque refus métier. */
const STATUTS: Record<string, number> = {
  shift_not_found: 404,
  not_admin: 403,
  station_suspended: 403,
  schedule_not_published: 409,
  member_not_active: 422,
  already_assigned: 409,
  shift_already_filled: 409,
  assignment_not_found: 404,
  assignment_not_replaceable: 409,
};

function message(code: string): string {
  return MESSAGES[code] ?? "La réattribution a échoué.";
}

/** Un uuid lisible dans le corps, ou `null`. Aucune validation de forme : la
 * base a des clés étrangères et des types, et elle les fait respecter mieux
 * qu'une expression régulière recopiée. */
function identifiant(valeur: unknown): string | null {
  if (typeof valeur !== "string") return null;
  const propre = valeur.trim();
  return propre === "" ? null : propre;
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
  // `caller()` qui établit l'identité réelle, et `reassign_shift` qui établit
  // le droit.
  const utilisateur = await caller(req, admin);
  if (!utilisateur) {
    return errorResponse(401, "unauthenticated", "Il faut être connecté.");
  }

  const body = await readJsonBody(req);
  if (!body) {
    return errorResponse(400, "invalid_body", "Corps de requête invalide.");
  }

  const shiftId = identifiant(body.shift_id);
  const userId = identifiant(body.user_id);
  if (shiftId === null || userId === null) {
    return errorResponse(
      400,
      "invalid_body",
      "Les champs shift_id et user_id sont obligatoires.",
    );
  }

  const { data, error } = await admin.rpc("reassign_shift", {
    p_shift: shiftId,
    p_user: userId,
    p_actor: utilisateur.id,
    // `undefined` et non `null` : le paramètre a une valeur par défaut en SQL,
    // et `postgrest-js` omet les clés absentes au lieu d'envoyer un `null` qui
    // effacerait cette valeur par défaut.
    p_previous: identifiant(body.previous_assignment_id) ?? undefined,
  });

  if (error) {
    console.error("reassign_shift", error.message);
    return errorResponse(500, "internal_error", "La réattribution a échoué.");
  }

  const resultat = data as unknown as ResultatReattribution;
  if (!resultat?.ok) {
    const code = resultat?.code ?? "internal_error";
    return errorResponse(STATUTS[code] ?? 500, code, message(code), {
      status: resultat?.status,
      filled: resultat?.filled,
      required: resultat?.required,
    });
  }

  return jsonResponse({
    ok: true,
    assignment_id: resultat.assignment_id,
    shift_id: resultat.shift_id,
    user_id: resultat.user_id,
    /** Faux quand le pompier avait déclaré ne pas pouvoir : l'écran l'a déjà dit
     * avant le geste, la réponse le confirme et la base l'a journalisé. */
    was_available: resultat.was_available ?? true,
    proposed_at: resultat.proposed_at,
    /** L'attribution remplacée, quand il y en avait une — désignée par l'écran
     * ou retrouvée par la base parmi les refus non encore couverts. */
    previous: resultat.previous_id === null || resultat.previous_id === undefined ? null : {
      id: resultat.previous_id,
      user_id: resultat.previous_user,
      status: resultat.previous_status,
      /** Vrai seulement si sa garde était **acquise** : c'est la seule personne
       * à qui on retire quelque chose. Celui qui avait refusé sait déjà. */
      notified: resultat.previous_notified ?? false,
    },
    schedule: {
      id: resultat.schedule_id,
      /** « published » quand une acceptation vient de disparaître d'un planning
       * validé : la caserne ne doit pas lire « Validé » sur un mois à trou. */
      status: resultat.schedule_status,
    },
    period: resultat.period,
  });
});
