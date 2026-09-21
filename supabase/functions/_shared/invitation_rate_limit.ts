// La phrase du refus de débit, en français (ticket 038).
//
// `create_invitation` (migration 0032) rend un code `rate_limited` et les faits :
// le plafond, ce qui a été consommé, la portée, et **quand** un envoi redevient
// possible. Traduire ces faits en une phrase est le travail de cette fonction,
// et il vit ici plutôt que dans `invite-member/index.ts` pour une seule raison :
// c'est la partie qu'un administrateur lit, donc celle qui mérite un test qui ne
// demande ni base ni réseau (`supabase/functions/tests/`).
//
// Le délai n'est pas arrondi à l'heure. Dire « réessaie dans une heure » quand la
// place se libère dans trois minutes fait fermer l'écran pour la journée.

/** Ce que `create_invitation` joint au code `rate_limited`. */
export type DetailDebit = {
  /** `station` pour un administrateur, `actor` pour le super-administrateur. */
  scope?: string;
  limit?: number;
  used?: number;
  remaining?: number;
  window_minutes?: number;
  retry_at?: string;
  retry_after_seconds?: number;
};

/** Les clés du détail, telles qu'elles sont recopiées dans la réponse HTTP. */
export const CLES_DEBIT = [
  "scope",
  "limit",
  "used",
  "remaining",
  "window_minutes",
  "retry_at",
  "retry_after_seconds",
] as const;

/**
 * Un délai en secondes, dit comme on le dit à l'oral.
 *
 * Arrondi **au-dessus** : annoncer « 9 minutes » pour 9 minutes et 40 secondes
 * ferait réessayer trop tôt, donc échouer une seconde fois.
 */
export function delaiEnFrancais(secondes: number): string {
  if (!Number.isFinite(secondes) || secondes <= 60) return "moins d'une minute";

  const minutes = Math.ceil(secondes / 60);
  if (minutes === 1) return "une minute";
  if (minutes < 60) return `${minutes} minutes`;

  const heures = Math.ceil(minutes / 60);
  return heures === 1 ? "une heure" : `${heures} heures`;
}

/** « 60 par heure », ou la vraie fenêtre si elle change un jour. */
function cadence(detail: DetailDebit): string | null {
  if (typeof detail.limit !== "number" || detail.limit <= 0) return null;

  const fenetre = detail.window_minutes === 60 || detail.window_minutes === undefined
    ? "par heure"
    : `par ${detail.window_minutes} minutes`;
  const ou = detail.scope === "actor" ? "pour ton compte" : "pour cette caserne";
  return `${detail.limit} ${fenetre} ${ou}`;
}

/**
 * La phrase affichable du refus, avec le délai avant de pouvoir réessayer.
 *
 * Sans détail — un vieux client, une réponse tronquée —, la phrase reste vraie,
 * seulement moins précise : on ne prétend jamais connaître un délai qu'on n'a pas.
 */
export function messageDebitDepasse(detail: DetailDebit | null | undefined): string {
  const faits = detail ?? {};
  const combien = cadence(faits);
  const debut = combien === null
    ? "Limite d'invitations atteinte."
    : `Limite d'invitations atteinte (${combien}).`;

  if (typeof faits.retry_after_seconds !== "number") {
    return `${debut} Réessaie plus tard.`;
  }
  return `${debut} Réessaie dans ${delaiEnFrancais(faits.retry_after_seconds)}.`;
}

/** Extrait du résultat SQL les seules clés de débit, sans rien inventer. */
export function lireDetailDebit(source: Record<string, unknown>): DetailDebit {
  const detail: Record<string, unknown> = {};
  for (const cle of CLES_DEBIT) {
    const valeur = source[cle];
    if (valeur !== undefined && valeur !== null) detail[cle] = valeur;
  }
  return detail as DetailDebit;
}
