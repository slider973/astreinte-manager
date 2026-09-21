// delete-account — le membre supprime son propre compte.
// Référence : docs/PRD.md § 8 (RGPD), docs/SCHEMA.md section 7, migration 0026,
// design/007-profil.md § 5.3 et 5.4, ticket 007.
//
// POST /functions/v1/delete-account
// En-têtes : Authorization: Bearer <access_token du membre>, apikey: <clé anon>
// Corps    : aucun
//
// **Le corps est vide, et c'est la règle de sécurité de cette fonction.** Il n'y a
// qu'une identité en jeu et elle vient du JWT, vérifiée auprès de GoTrue par
// `caller()`. Un `user_id` accepté dans le corps ferait de cette fonction une porte
// pour supprimer le compte d'un autre — `verify_jwt` ne dit rien du *qui*, la clé
// anon étant elle-même un JWT valide et publique.
//
// Deux temps, dans cet ordre, et l'ordre est le sujet
// ---------------------------------------------------
//   1. `delete_own_account` (SQL, atomique) : le profil devient « Membre supprimé »,
//      ses appartenances passent `disabled`, tout ce qui est personnel est effacé.
//      Les attributions passées restent — c'est l'histoire de la caserne.
//   2. Le compte d'authentification est supprimé.
//
// Si le second échoue, il reste un compte qui se connecte encore sur un profil déjà
// vidé : désagréable, mais **rien de nominatif n'est resté en base**. L'ordre inverse
// produirait la panne symétrique et pire : un compte supprimé, un nom toujours en
// clair, et plus personne pour le nettoyer puisque l'appelant ne peut plus se
// connecter. La réponse dit laquelle des deux étapes a abouti.

import { errorResponse, jsonResponse, preflight } from "../_shared/http.ts";
import { type AdminClient, adminClient, caller } from "../_shared/supabase.ts";

type DeleteResult = {
  ok: boolean;
  code?: string;
  station?: string;
  stations?: string[];
  memberships?: number;
};

/** Code métier → statut HTTP et message français. */
const ERREURS: Record<string, { status: number; message: string }> = {
  last_admin: {
    status: 409,
    message:
      "Tu es le seul administrateur de ta caserne. Nomme quelqu'un d'autre avant de supprimer ton compte.",
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
      "Reconnecte-toi pour supprimer ton compte.",
    );
  }

  const { data, error } = await admin.rpc("delete_own_account", {
    p_user_id: utilisateur.id,
  });

  if (error) {
    console.error("delete_own_account", error.message);
    return errorResponse(500, "internal_error", "Erreur serveur.");
  }

  const resultat = data as unknown as DeleteResult;

  if (!resultat.ok) {
    const code = resultat.code ?? "internal_error";
    const connu = ERREURS[code];
    return errorResponse(
      connu?.status ?? 500,
      code,
      connu?.message ?? "Impossible de supprimer ce compte.",
      resultat.station ? { station: resultat.station } : {},
    );
  }

  // Le profil est anonymisé, quoi qu'il arrive maintenant. Aucune identité ne
  // traîne dans les journaux : ni l'adresse, ni le nom — seulement l'identifiant.
  const suppression = await admin.auth.admin.deleteUser(utilisateur.id);
  if (suppression.error) {
    console.error("deleteUser", utilisateur.id, suppression.error.message);
    return errorResponse(
      500,
      "auth_delete_failed",
      "Tes données ont été effacées, mais ton accès n'a pas pu être fermé. " +
        "Préviens ton administrateur.",
      { anonymized: true },
    );
  }

  return jsonResponse({
    ok: true,
    stations: resultat.stations ?? [],
    memberships: resultat.memberships ?? 0,
  });
});
