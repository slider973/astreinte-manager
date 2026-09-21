// Lecture du jeton d'abonnement dans l'URL du flux calendrier. Ticket 028.
//
// Module à part, et pas une fonction privée d'`index.ts` : ce dernier appelle
// `Deno.serve` au chargement, donc l'importer depuis un test lèverait un serveur
// à chaque exécution. Tout ce qui se teste sans réseau vit dans un module pur
// (même règle que `_shared/`, voir `.github/workflows/ci.yml`).

/**
 * Le jeton, lu dans le chemin ou dans la requête. Chaîne vide s'il n'y en a pas.
 *
 * La forme canonique est `/ics-feed/<jeton>.ics` : plusieurs clients — Outlook
 * en tête — décident du type de contenu d'après le suffixe de l'URL avant même
 * de lire l'en-tête. `?token=` est accepté parce que c'est la forme qu'on écrit
 * spontanément, et refuser un lien qui marcherait serait une punition sans objet.
 */
export function lireJeton(url: string): string {
  const adresse = new URL(url);

  const dernier = adresse.pathname.split("/").filter((part) => part !== "").pop() ?? "";
  if (dernier !== "" && dernier !== "ics-feed") {
    return nettoyer(dernier.replace(/\.ics$/i, ""));
  }

  return nettoyer(adresse.searchParams.get("token") ?? "");
}

/**
 * Ce qui a la forme d'un jeton, ou rien.
 *
 * Le contrôle existe pour que la réponse soit un refus honnête (404) plutôt
 * qu'un aller-retour en base pour une valeur qui ne peut être celle de personne
 * — même raisonnement qu'`estUuid` dans `_shared/http.ts`. `profiles.ics_token`
 * fait 48 caractères hexadécimaux ; la fourchette est large pour qu'un jour où
 * la longueur change, ce filtre ne devienne pas le mur qu'on a oublié.
 */
function nettoyer(valeur: string): string {
  const jeton = valeur.trim();
  return /^[0-9a-f]{32,128}$/i.test(jeton) ? jeton : "";
}
