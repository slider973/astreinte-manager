// Qui a le droit de faire quoi sur l'abonnement d'une caserne — fonction
// **pure**, donc testée à chaque PR (`supabase/functions/tests/`), contrairement
// à la couche HTTP qui demande une pile locale.
//
// Ce n'est pas un détail d'organisation. Le contrôle de droits d'une fonction de
// paiement est la règle la plus coûteuse à perdre au premier refactor : elle
// décide qui peut engager une dépense au nom d'une caserne, et qui peut ouvrir
// le portail où l'on change de carte et où l'on résilie. Une règle qui ne casse
// aucun test quand on la retire n'est pas une règle.
//
// Référence : docs/SCHEMA.md § 7 et 2.13, docs/STRIPE.md, ticket 029.

import type { Formule } from "../_shared/stripe.ts";

export type Action = "state" | "checkout" | "portal";

export function actionValide(valeur: unknown): Action | null {
  return valeur === "state" || valeur === "checkout" || valeur === "portal" ? valeur : null;
}

/** La ligne `subscriptions` de la caserne visée, ou `null` si elle n'en a pas. */
export type AbonnementCaserne = {
  status: string;
  stripe_customer_id: string | null;
  stripe_subscription_id: string | null;
};

export type Contexte = {
  action: Action;
  /** Établi par une requête sur `memberships`, **jamais** par le corps reçu. */
  estAdminActif: boolean;
  /** Les quatre secrets du prestataire sont-ils posés ? */
  configure: boolean;
  abonnement: AbonnementCaserne | null;
  /** Lue dans le corps, déjà validée par `formuleValide`. */
  formule: Formule | null;
};

export type Verdict =
  | { ok: true }
  | { ok: false; statut: number; code: string; message: string };

/**
 * **Un abonnement en cours ne se souscrit pas une seconde fois.**
 *
 * Le cas qui compte n'est pas la caserne déjà `active` — celle-là ne voit même
 * pas le bouton. C'est la caserne en **retard de paiement**, cas le plus banal
 * qui soit : une carte qui expire. Son statut n'est pas `active`, donc un
 * garde-fou posé sur le seul statut `active` la laisse passer — et elle repart
 * avec un **second** abonnement, prélevé en parallèle du premier, pendant que le
 * premier continue ses relances. `subscriptions.stripe_subscription_id` ne peut
 * en désigner qu'un : l'autre devient invisible, et personne ne le résilie.
 *
 * La bonne question n'est donc pas « quel est son statut » mais « existe-t-il un
 * abonnement chez le prestataire, et vit-il encore ». Un abonnement **résilié**
 * se reprend — c'est un client qui revient, et rien ne se dédouble.
 *
 * Une carte qui a expiré se change dans le **portail**, et c'est là qu'on
 * envoie : ré-souscrire ne répare rien, ça facture deux fois.
 */
export const STATUTS_ABONNEMENT_VIVANT: readonly string[] = [
  "active",
  "past_due",
  "trialing",
  // Une caserne suspendue après quatorze jours d'impayé garde son abonnement
  // chez le prestataire tant qu'il ne l'a pas résilié : elle non plus ne doit
  // pas en ouvrir un second. Sa sortie est le portail.
  "suspended",
];

/** Vrai quand la caserne a un abonnement qui vit encore chez le prestataire. */
export function abonnementVivant(abonnement: AbonnementCaserne | null): boolean {
  return abonnement !== null &&
    abonnement.stripe_subscription_id !== null &&
    STATUTS_ABONNEMENT_VIVANT.includes(abonnement.status);
}

/** Vrai quand le portail de gestion a une destination. */
export function portailOuvrable(
  abonnement: AbonnementCaserne | null,
  configure: boolean,
): boolean {
  return configure && (abonnement?.stripe_customer_id ?? null) !== null;
}

/**
 * Le verdict d'une requête, avant tout appel au prestataire.
 *
 * L'ordre des refus n'est pas indifférent : le droit d'abord — dire « caserne
 * inconnue » ou « pas encore configuré » à qui n'a rien à faire là lui
 * apprendrait quelque chose.
 */
export function autoriser(ctx: Contexte): Verdict {
  if (!ctx.estAdminActif) {
    return {
      ok: false,
      statut: 403,
      code: "not_admin",
      message: "Il faut être administrateur de cette caserne pour gérer son abonnement.",
    };
  }

  // `state` répond toujours : c'est ce qui permet à l'écran d'annoncer le tarif
  // au lieu de planter quand aucun compte n'est branché (docs/STRIPE.md).
  if (ctx.action === "state") return { ok: true };

  if (!ctx.configure) {
    return {
      ok: false,
      statut: 503, // pas 500 : rien n'est en panne, le service n'est pas ouvert
      code: "stripe_not_configured",
      message: "L'abonnement n'est pas encore ouvert sur ce projet.",
    };
  }

  if (ctx.action === "portal") {
    return portailOuvrable(ctx.abonnement, ctx.configure) ? { ok: true } : {
      ok: false,
      statut: 409,
      code: "no_customer",
      message: "Cette caserne n'a pas encore d'abonnement à gérer.",
    };
  }

  if (ctx.formule === null) {
    return {
      ok: false,
      statut: 400,
      code: "invalid_plan",
      message: "Choisis la formule mensuelle ou annuelle.",
    };
  }

  if (abonnementVivant(ctx.abonnement)) {
    return {
      ok: false,
      statut: 409,
      code: "already_subscribed",
      message: "Cette caserne a déjà un abonnement. Passe par « Gérer mon abonnement » " +
        "pour changer de carte ou de formule.",
    };
  }

  return { ok: true };
}
