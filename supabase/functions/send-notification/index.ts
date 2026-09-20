// send-notification — la pièce maîtresse des notifications (ticket 025).
// Référence : docs/SCHEMA.md § 7, docs/WORKFLOWS.md § 6 et 8, docs/FIREBASE.md.
//
// Elle reçoit un type, des destinataires, une caserne et des données ; elle écrit
// la ligne interne, envoie le push à tous les appareils du membre et envoie le
// courriel quand le canal est demandé ou quand le membre n'a aucun appareil.
//
// Deux façons de l'appeler, et c'est volontaire
// ---------------------------------------------
//
//   1. **Depuis la base** — un déclencheur ou une tâche planifiée appelle
//      `public.notify(...)` (migration 0014), qui écrit la demande dans
//      `notification_outbox` puis la poste ici par pg_net. Le corps ne porte alors
//      que `{ "outbox_id": uuid }` : la fonction relit la demande par
//      `notify_claim` et la clôt par `notify_complete`. Si elle ne répond pas, la
//      demande reste en file et la tâche `dispatch_notifications` la reprend.
//      C'est le chemin des tickets 015 et 022.
//
//   2. **Depuis une autre Edge Function** — `publish-schedule` (019) et
//      `reassign-shift` (020) ont déjà la clé de service et rendent un compte
//      rendu à l'admin qui vient de cliquer. Elles postent la demande complète et
//      lisent la réponse. Pas de file, pas d'attente.
//
// Authentification
// ----------------
// `verify_jwt = false` dans supabase/config.toml, et ce n'est pas un relâchement :
// pg_net ne porte aucun JWT, et la seule alternative aurait été de ranger la clé
// de service en clair dans la base pour qu'il la recopie. À la place, la migration
// 0014 engendre un secret aléatoire dans Vault ; cette fonction va le lire avec sa
// clé de service et le compare à l'en-tête `x-notify-secret`. Rien à recopier,
// rien dans le dépôt, et la comparaison est à temps constant.
//
// L'appel par une autre Edge Function, lui, présente la clé de service en jeton
// porteur. Tout le reste est rejeté en 401 — la fonction n'est jamais appelable
// par un client, même connecté : elle écrirait des notifications pour n'importe
// qui, dans n'importe quelle caserne.

import { errorResponse, jsonResponse, preflight, readJsonBody } from "../_shared/http.ts";
import { type AdminClient, adminClient, env } from "../_shared/supabase.ts";
import { sendMail } from "../_shared/mailer.ts";
import { type Contenu, type TypeNotification } from "../_shared/notification_content.ts";
import { renderNotificationEmail } from "../_shared/notification_email.ts";
import { envoyerPush } from "../_shared/fcm.ts";
import {
  type Caserne,
  type DemandeEnvoi,
  type Deps,
  type Jeton,
  type LigneNotification,
  lireDemande,
  type Profil,
  traiterEnvoi,
} from "../_shared/notification_send.ts";

// ---------------------------------------------------------------------------
// Authentification de l'appelant
// ---------------------------------------------------------------------------

/** Comparaison à temps constant : la longueur ne renseigne pas, le contenu non plus. */
function memeSecret(a: string, b: string): boolean {
  const encodeur = new TextEncoder();
  const x = encodeur.encode(a);
  const y = encodeur.encode(b);
  // Longueurs différentes : on compare quand même, pour ne pas révéler laquelle.
  const taille = Math.max(x.length, y.length);
  let difference = x.length ^ y.length;
  for (let i = 0; i < taille; i++) {
    difference |= (x[i] ?? 0) ^ (y[i] ?? 0);
  }
  return difference === 0;
}

/**
 * Le secret interne, gardé en mémoire pour ne pas interroger Vault à chaque
 * notification — une publication de planning, c'est une centaine d'appels.
 *
 * Le cache est **relu en cas de non-correspondance**, et une seule fois par
 * requête : le jour où le secret tourne, l'instance déjà chaude refuserait sinon
 * tous les appels venus de la base jusqu'à son recyclage, et les notifications
 * s'accumuleraient en file pour une raison invisible. Un attaquant qui présente
 * un mauvais secret provoque une lecture de Vault, pas davantage.
 */
let secretInterne: string | null = null;

async function lireSecretInterne(admin: AdminClient): Promise<string | null> {
  const { data, error } = await admin.rpc("notify_internal_secret");
  if (error || typeof data !== "string" || data === "") {
    console.error("notify_internal_secret", error?.message ?? "secret absent de Vault");
    return null;
  }
  secretInterne = data;
  return data;
}

async function appelAutorise(req: Request, admin: AdminClient): Promise<boolean> {
  const entete = req.headers.get("Authorization") ?? "";
  const porteur = entete.toLowerCase().startsWith("bearer ") ? entete.slice(7).trim() : "";
  const cleService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (porteur !== "" && cleService !== "" && memeSecret(porteur, cleService)) return true;

  const propose = req.headers.get("x-notify-secret");
  if (!propose) return false;

  const enCache = secretInterne ?? await lireSecretInterne(admin);
  if (enCache !== null && memeSecret(propose, enCache)) return true;

  // Ça ne correspond pas : le secret a peut-être tourné depuis le démarrage de
  // cette instance. On relit une fois, et une seule.
  if (enCache === null) return false;
  const frais = await lireSecretInterne(admin);
  return frais !== null && memeSecret(propose, frais);
}

// ---------------------------------------------------------------------------
// Les dépendances réelles
// ---------------------------------------------------------------------------

function dependances(admin: AdminClient): Deps {
  return {
    async lireCaserne(stationId: string | null): Promise<Caserne | null> {
      if (!stationId) return null;
      const { data, error } = await admin
        .from("stations")
        .select("name, timezone")
        .eq("id", stationId)
        .maybeSingle();
      if (error) {
        console.error("lecture caserne", error.message);
        return null;
      }
      return data ? { name: data.name, timezone: data.timezone } : null;
    },

    async lireProfils(userIds: string[]): Promise<Profil[]> {
      if (userIds.length === 0) return [];
      const { data, error } = await admin
        .from("profiles")
        .select("id, email, first_name, last_name, push_enabled")
        .in("id", userIds);
      if (error) {
        console.error("lecture profils", error.message);
        return [];
      }
      return data ?? [];
    },

    async lireJetons(userIds: string[]): Promise<Map<string, Jeton[]>> {
      const parMembre = new Map<string, Jeton[]>();
      if (userIds.length === 0) return parMembre;
      const { data, error } = await admin
        .from("push_tokens")
        .select("user_id, token, platform")
        .in("user_id", userIds);
      if (error) {
        console.error("lecture jetons", error.message);
        return parMembre;
      }
      for (const ligne of data ?? []) {
        const liste = parMembre.get(ligne.user_id) ?? [];
        liste.push({ token: ligne.token, platform: ligne.platform });
        parMembre.set(ligne.user_id, liste);
      }
      return parMembre;
    },

    async ecrireNotification(ligne: LigneNotification): Promise<string | null> {
      const { data, error } = await admin
        .from("notifications")
        .insert({
          station_id: ligne.station_id,
          user_id: ligne.user_id,
          type: ligne.type,
          channel: ligne.channel,
          title: ligne.title,
          body: ligne.body,
          data: ligne.data as never,
          sent_at: ligne.sent_at,
          delivered: ligne.delivered,
          error: ligne.error,
        })
        .select("id")
        .single();
      if (error) {
        console.error("écriture notification", error.message);
        return null;
      }
      return data?.id ?? null;
    },

    async supprimerJetons(jetons: string[]): Promise<void> {
      if (jetons.length === 0) return;
      const { error } = await admin.from("push_tokens").delete().in("token", jetons);
      if (error) console.error("suppression jetons", error.message);
    },

    envoyerPush(jetons, message) {
      return envoyerPush(jetons, message);
    },

    async envoyerCourriel(destinataire: string, contenu: Contenu, caserne: Caserne | null) {
      const courriel = renderNotificationEmail(contenu, { stationName: caserne?.name ?? null });
      return await sendMail({
        to: destinataire,
        subject: courriel.subject,
        html: courriel.html,
        text: courriel.text,
      });
    },

    maintenant: () => new Date(),
  };
}

// ---------------------------------------------------------------------------
// La demande, lue du corps ou de la file
// ---------------------------------------------------------------------------

type DemandeLue =
  | { demande: DemandeEnvoi; outboxId: string | null }
  | { erreur: { statut: number; code: string; message: string } }
  | { deja: true };

async function demandeDepuisCorps(
  admin: AdminClient,
  corps: Record<string, unknown>,
): Promise<DemandeLue> {
  const outboxId = typeof corps.outbox_id === "string" ? corps.outbox_id.trim() : null;

  if (!outboxId) {
    const lu = lireDemande(corps);
    if ("erreur" in lu) {
      return { erreur: { statut: 400, ...lu.erreur } };
    }
    return { demande: lu.demande, outboxId: null };
  }

  const { data, error } = await admin.rpc("notify_claim", { p_outbox: outboxId });
  if (error) {
    console.error("notify_claim", error.message);
    return {
      erreur: { statut: 500, code: "internal_error", message: "File de notifications illisible." },
    };
  }
  // `notify_claim` rend NULL quand la ligne n'est plus en attente : la reprise a
  // reposté une demande déjà traitée. Rien à faire, et surtout pas deux fois.
  if (!data || data.id === null) {
    return { deja: true };
  }

  const ligne = data as unknown as {
    id: string;
    station_id: string | null;
    type: TypeNotification;
    recipients: unknown;
    payload: unknown;
    channels: string[] | null;
  };

  const lu = lireDemande({
    type: ligne.type,
    station_id: ligne.station_id,
    recipients: ligne.recipients,
    payload: ligne.payload,
    channels: ligne.channels,
  });
  if ("erreur" in lu) {
    await admin.rpc("notify_complete", {
      p_outbox: outboxId,
      p_ok: false,
      p_error: `${lu.erreur.code} : ${lu.erreur.message}`,
    });
    return { erreur: { statut: 400, ...lu.erreur } };
  }
  return { demande: lu.demande, outboxId };
}

// ---------------------------------------------------------------------------
// Point d'entrée
// ---------------------------------------------------------------------------

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

  if (!await appelAutorise(req, admin)) {
    return errorResponse(401, "unauthenticated", "Appel interne uniquement.");
  }

  const corps = await readJsonBody(req);
  if (!corps) {
    return errorResponse(400, "invalid_body", "Corps de requête invalide.");
  }

  const lu = await demandeDepuisCorps(admin, corps);
  if ("erreur" in lu) {
    return errorResponse(lu.erreur.statut, lu.erreur.code, lu.erreur.message);
  }
  if ("deja" in lu) {
    return jsonResponse({ ok: true, skipped: "already_processed" });
  }

  const { demande, outboxId } = lu;

  let resultat;
  try {
    resultat = await traiterEnvoi(dependances(admin), demande);
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);
    console.error("traiterEnvoi", message);
    if (outboxId) {
      await admin.rpc("notify_complete", {
        p_outbox: outboxId,
        p_ok: false,
        p_error: message.slice(0, 500),
      });
    }
    return errorResponse(500, "internal_error", "L'envoi des notifications a échoué.");
  }

  if (outboxId) {
    // La demande est traitée, même si un destinataire a résisté : son sort est
    // dans `notifications.error`, pas dans un statut de file qui reviendrait
    // marteler les autres.
    await admin.rpc("notify_complete", {
      p_outbox: outboxId,
      p_ok: true,
      p_error: resultat.failed > 0 ? `${resultat.failed} destinataire(s) en échec` : undefined,
      p_result: {
        recipients: resultat.recipients,
        delivered: resultat.delivered,
        failed: resultat.failed,
      },
    });
  }

  return jsonResponse({ ...resultat, outbox_id: outboxId });
});
