// La lecture de la liste de personnes d'une requête `invite-member`.
//
// Ici plutôt que dans `invite-member/index.ts` pour une seule raison : c'est la
// partie qui décide *qui* sera invité et *avec quel nom*, donc celle qui mérite un
// test qui ne demande ni base ni réseau (`supabase/functions/tests/`). Le fichier
// d'un chef de centre n'est relu par personne avant d'arriver là.

/** Les deux rôles d'une appartenance (`docs/SCHEMA.md § 2.3`). */
export type Role = "member" | "admin";

/** Vingt adresses par appel — la borne du ticket 006, inchangée. */
export const MAX_ADRESSES = 20;

/** Une personne à inviter : son adresse, et ce que l'administrateur sait d'elle. */
export type Personne = {
  email: string;
  firstName?: string;
  lastName?: string;
  role: Role;
};

/** `null` quand la valeur n'est pas un nom utilisable — vide, ou pas une chaîne. */
function lireNom(valeur: unknown): string | undefined {
  if (typeof valeur !== "string") return undefined;
  const propre = valeur.replace(/\s+/g, " ").trim();
  return propre === "" ? undefined : propre;
}

/**
 * Normalise, déduplique et borne la liste de personnes du corps de la requête.
 *
 * Trois formes acceptées, une seule sortie. `people` porte les noms et un rôle par
 * personne (ticket 047) ; `emails` et `email` restent les formes du ticket 006, et
 * prennent alors le rôle du lot. Une entrée de `people` dont l'adresse n'est pas une
 * chaîne rend `null` : un corps mal formé est refusé en bloc, il n'est pas rattrapé
 * à moitié.
 *
 * La déduplication garde la **première** occurrence, donc le premier nom : c'est
 * l'ordre du fichier, et un doublon plus bas n'a aucune raison d'écraser ce qui
 * précède.
 */
export function lirePersonnes(
  body: Record<string, unknown>,
  roleDuLot: Role,
): Personne[] | null {
  const brut: unknown[] = Array.isArray(body.people)
    ? body.people
    : Array.isArray(body.emails)
    ? body.emails
    : typeof body.email === "string"
    ? [body.email]
    : [];
  if (brut.length === 0) return null;

  const vues = new Map<string, Personne>();
  for (const valeur of brut) {
    let email: unknown;
    let personne: Personne;

    if (typeof valeur === "string") {
      email = valeur;
      // Les deux noms sont posés même absents : la sortie a toujours la même
      // forme, quelle que soit la forme du corps.
      personne = { email: "", firstName: undefined, lastName: undefined, role: roleDuLot };
    } else if (valeur !== null && typeof valeur === "object") {
      const ligne = valeur as Record<string, unknown>;
      email = ligne.email;
      if (
        ligne.role !== undefined && ligne.role !== "admin" && ligne.role !== "member"
      ) {
        return null;
      }
      personne = {
        email: "",
        firstName: lireNom(ligne.first_name),
        lastName: lireNom(ligne.last_name),
        role: ligne.role === "admin" ? "admin" : ligne.role === "member" ? "member" : roleDuLot,
      };
    } else {
      return null;
    }

    if (typeof email !== "string") return null;
    const normalisee = email.trim().toLowerCase();
    if (normalisee === "" || vues.has(normalisee)) continue;
    vues.set(normalisee, { ...personne, email: normalisee });
  }

  if (vues.size === 0 || vues.size > MAX_ADRESSES) return null;
  return [...vues.values()];
}
