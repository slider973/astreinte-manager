// ics-feed — le flux calendrier d'un membre, derrière un jeton à lui.
// Référence : docs/PRD.md § 5.5, docs/SCHEMA.md § 7, migration 0029,
// design/028-export-ics.md, ticket 028.
//
// GET /functions/v1/ics-feed/<jeton>.ics      (forme canonique)
// GET /functions/v1/ics-feed?token=<jeton>    (acceptée aussi)
//
// **Aucun en-tête d'authentification, et c'est le sujet de cette fonction.**
// L'appelant n'est pas l'application : c'est Google Agenda, c'est iCloud, c'est
// Outlook, qui vont chercher l'adresse toutes les heures depuis leurs serveurs.
// Aucun d'eux ne sait porter un jeton d'accès Supabase, et aucun ne renouvelle
// une session. Le secret est donc **dans l'URL** — d'où `verify_jwt = false`
// dans `supabase/config.toml`, comme `stripe-webhook`, et pour la même raison :
// ce qui authentifie l'appelant n'est pas le portier, c'est ce qu'il apporte.
//
// Ce qui protège cette adresse, puisqu'elle voyage
// ------------------------------------------------
//   - 192 bits tirés au sort (`profiles.ics_token`, 24 octets en hexadécimal).
//     Il n'y a rien à deviner, et rien à énumérer.
//   - `ics_feed_events` ne rend que les astreintes **acceptées** de son porteur,
//     dans les casernes où il est **encore actif**. Pas ses disponibilités, pas
//     son profil, pas le nom d'un équipier, rien d'une autre caserne — la
//     frontière est tenue par la forme de la requête SQL, pas par cette
//     fonction (migration 0029).
//   - Un jeton régénéré (`rotate_ics_token`) ne désigne plus personne
//     immédiatement : cette fonction répond alors `404`, comme à un inconnu.
//   - **La fonction ne pose aucun en-tête CORS.** Un agenda va chercher le
//     fichier depuis son serveur ; il n'a pas de politique d'origine à
//     satisfaire. (La passerelle, elle, ajoute son propre
//     `Access-Control-Allow-Origin: *` — c'est son réglage à elle, pas une
//     ouverture décidée ici, et rien de ce flux n'est lisible sans le jeton.)
//   - `Cache-Control: no-store` : le contenu est privé, il n'a rien à faire dans
//     le cache d'un intermédiaire.
//
// Ce que cette fonction ne fait pas
// ---------------------------------
// Elle ne décide rien du contenu : la liste vient de `ics_feed_events`
// (migration 0029), la mise en forme de `calendrier.ts` (RFC 5545). Il ne reste
// ici que la lecture du jeton dans l'URL et le choix du code de statut.

import { type AdminClient, adminClient } from "../_shared/supabase.ts";
import { composerCalendrier, type EvenementAstreinte } from "./calendrier.ts";
import { lireJeton } from "./jeton.ts";

/** Ce que rend `ics_feed_events` (migration 0029). */
type FluxResult = {
  ok: boolean;
  code?: string;
  membre?: string;
  evenements?: EvenementAstreinte[];
};

/**
 * Le nom du fichier annoncé, quand quelqu'un ouvre l'adresse dans un navigateur
 * plutôt que dans un agenda. `inline` : le but reste que le client de calendrier
 * le lise, pas qu'il atterrisse dans un dossier de téléchargements.
 */
const DISPOSITION = 'inline; filename="astreintes.ics"';

const ENTETES_CALENDRIER: Record<string, string> = {
  "Content-Type": "text/calendar; charset=utf-8",
  "Content-Disposition": DISPOSITION,
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

Deno.serve(async (req: Request): Promise<Response> => {
  // Ni `POST`, ni `OPTIONS` : une adresse d'abonnement se lit, et il n'y a pas
  // de requête préalable à satisfaire puisqu'il n'y a pas de CORS.
  if (req.method !== "GET" && req.method !== "HEAD") {
    return texte(405, "Méthode non autorisée.");
  }

  const jeton = lireJeton(req.url);
  if (jeton === "") {
    return texte(404, "Lien d'abonnement invalide.");
  }

  let admin: AdminClient;
  try {
    admin = adminClient();
  } catch (cause) {
    console.error(cause);
    return texte(500, "Configuration serveur incomplète.");
  }

  const { data, error } = await admin.rpc("ics_feed_events", { p_token: jeton });

  if (error) {
    // Jamais le jeton dans le journal : il vaut mot de passe.
    console.error("ics_feed_events", error.message);
    return texte(500, "Erreur serveur.");
  }

  const resultat = data as unknown as FluxResult;

  if (!resultat.ok) {
    // Un jeton inconnu et un jeton révoqué se répondent pareil, et c'est voulu :
    // distinguer les deux apprendrait à qui tâtonne lesquels ont existé.
    return texte(404, "Lien d'abonnement invalide ou révoqué.");
  }

  // Un flux **vide** est une réponse valide : un membre désactivé, ou qui n'a
  // pas encore d'astreinte acceptée, a un calendrier sans événement. Répondre
  // une erreur ferait clignoter un avertissement dans son agenda pour un état
  // parfaitement normal.
  const calendrier = composerCalendrier(resultat.evenements ?? []);

  return new Response(calendrier, { status: 200, headers: ENTETES_CALENDRIER });
});

/** Une réponse en texte brut : ce qui suit ne sera pas lu par un humain. */
function texte(status: number, message: string): Response {
  return new Response(message, {
    status,
    headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
  });
}
