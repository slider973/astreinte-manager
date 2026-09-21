// export-user-data — le membre récupère tout ce que l'application sait de lui.
// Référence : docs/PRD.md § 8 (RGPD), docs/SCHEMA.md section 7, migration 0027,
// docs/RGPD.md, design/034-rgpd-export.md § 5.1, ticket 034.
//
// POST /functions/v1/export-user-data
// En-têtes : Authorization: Bearer <access_token du membre>, apikey: <clé anon>
// Corps    : aucun — **et un corps envoyé quand même est ignoré**.
//
// **L'identité vient du JWT, jamais de la requête.** C'est la même règle que
// `delete-account`, et pour une raison plus forte encore : un `user_id` accepté
// ici ne détruirait rien, il **livrerait** le dossier complet de quelqu'un
// d'autre — profil, adresse, téléphone, disponibilités, astreintes. `verify_jwt`
// ne dit rien du *qui* : la clé anon est un JWT valide et publique. C'est
// `caller()` qui établit l'identité auprès de GoTrue, et `export_own_data` est
// fermée à `anon` comme à `authenticated` (migration 0027).
//
// Ce que cette fonction ajoute à la fonction SQL
// ----------------------------------------------
// Une seule chose : la section `compte`, qui vient de `auth.users` et que le SQL
// du projet ne lit pas — le schéma `auth` n'est touché que par l'API
// d'administration (même règle qu'à la § 2.2 du schéma, où `profiles.email` est
// dupliqué « sans toucher au schéma auth »). Date de création, dernière
// connexion, confirmation de l'adresse : trois faits que la personne ne trouve
// nulle part ailleurs.
//
// Le fichier n'est pas fabriqué ici
// ---------------------------------
// La réponse est du JSON, pas une pièce jointe. C'est le client qui compose le
// nom du fichier et déclenche l'enregistrement (`core/plateforme/telechargement`).
// Servir un `Content-Disposition` obligerait le navigateur à visiter l'URL
// lui-même, donc à porter le jeton d'accès **dans l'URL**, donc dans
// l'historique et dans les journaux de la passerelle. Le détour par le SDK garde
// le jeton dans un en-tête.

import { errorResponse, jsonResponse, preflight } from "../_shared/http.ts";
import { type AdminClient, adminClient, caller } from "../_shared/supabase.ts";

/** Ce que rend `export_own_data` (migration 0027). */
type ExportResult = {
  ok: boolean;
  code?: string;
  donnees?: Record<string, unknown>;
  inventaire?: Record<string, number>;
};

/** Version du format du fichier. Un lecteur écrit dans dix ans saura quoi lire. */
const VERSION_FORMAT = 1;

/** La phrase que porte le fichier lui-même, pour qui l'ouvre sans contexte. */
const A_LIRE = "Export des données personnelles détenues par Astreinte SP. " +
  "Les autres membres de ta caserne n'y figurent pas : quand un acte les " +
  "implique, seul le fait est conservé, jamais leur identité. " +
  "Politique de confidentialité : /legal/confidentialite";

/** Code métier → statut HTTP et message français. */
const ERREURS: Record<string, { status: number; message: string }> = {
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
      "Reconnecte-toi pour exporter tes données.",
    );
  }

  const { data, error } = await admin.rpc("export_own_data", {
    p_user_id: utilisateur.id,
  });

  if (error) {
    console.error("export_own_data", error.message);
    return errorResponse(500, "internal_error", "Erreur serveur.");
  }

  const resultat = data as unknown as ExportResult;

  if (!resultat.ok) {
    const code = resultat.code ?? "internal_error";
    const connu = ERREURS[code];
    return errorResponse(
      connu?.status ?? 500,
      code,
      connu?.message ?? "Impossible de préparer ton export.",
    );
  }

  const donnees = resultat.donnees ?? {};
  const inventaire = { ...(resultat.inventaire ?? {}) };

  // La section `compte` est facultative **par construction** : un profil
  // anonymisé survit à son compte d'authentification (migration 0026), et un
  // export demandé depuis une session encore valide sur un compte déjà supprimé
  // ne doit pas tomber en panne pour autant.
  const compte = await lireCompte(admin, utilisateur.id);
  if (compte !== null) {
    inventaire.compte = 1;
  }

  return jsonResponse({
    export: {
      produit: "Astreinte SP",
      version_format: VERSION_FORMAT,
      genere_le: new Date().toISOString(),
      personne: utilisateur.id,
      a_lire: A_LIRE,
      inventaire,
    },
    donnees: { compte, ...donnees },
  });
});

/** Les trois faits du compte d'authentification, ou `null` s'il n'existe plus. */
async function lireCompte(
  admin: AdminClient,
  userId: string,
): Promise<Record<string, unknown> | null> {
  try {
    const { data, error } = await admin.auth.admin.getUserById(userId);
    if (error || !data.user) return null;

    return {
      adresse_de_connexion: data.user.email ?? null,
      cree_le: data.user.created_at ?? null,
      adresse_confirmee_le: data.user.email_confirmed_at ?? null,
      derniere_connexion_le: data.user.last_sign_in_at ?? null,
      // `providers` dit « par quoi je me connecte » : dans ce produit, toujours
      // le code à six chiffres envoyé par courriel.
      moyens_de_connexion: data.user.app_metadata?.providers ?? [],
    };
  } catch (cause) {
    // Aucune identité dans le journal : seulement le fait que la lecture a raté.
    console.error("getUserById", cause);
    return null;
  }
}
