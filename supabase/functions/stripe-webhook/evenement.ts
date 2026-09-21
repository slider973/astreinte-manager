// Traduction d'un événement Stripe en paramètres de `subscription_sync`
// (migration 0023). Fonction **pure** : aucun réseau, aucune base, et c'est ce
// qui permet de vérifier les quatre événements du ticket 029 en quelques
// millisecondes (supabase/functions/tests/stripe_evenement_test.ts).
//
// Référence : docs/SCHEMA.md § 2.13, docs/STRIPE.md, ticket 029.

import { estUuid } from "../_shared/http.ts";
import { type Formule, formuleValide } from "../_shared/stripe.ts";

/** Les statuts de `subscription_status` (docs/SCHEMA.md § 1). */
export type StatutAbonnement =
  | "trialing"
  | "active"
  | "past_due"
  | "suspended"
  | "cancelled";

/** Ce que l'Edge Function passera à `subscription_sync`. */
export type Consequence = {
  /** La caserne, quand l'événement la nomme (`client_reference_id`). */
  station: string | null;
  /** L'identifiant client chez Stripe : la clé de rattachement des autres événements. */
  customer: string | null;
  subscription: string | null;
  statut: StatutAbonnement | null;
  formule: Formule | null;
  /** Fin de la période payée, en ISO 8601, ou `null`. */
  finPeriode: string | null;
};

export type Interpretation =
  | { traite: true; type: string; consequence: Consequence }
  | { traite: false; type: string; raison: "type_ignore" | "sans_client" };

/** **Les quatre événements du ticket 029**, et eux seuls. */
export const TYPES_TRAITES: readonly string[] = [
  "checkout.session.completed",
  "invoice.paid",
  "invoice.payment_failed",
  "customer.subscription.updated",
  "customer.subscription.deleted",
];

/**
 * La caserne nommée par l'événement, **si elle a la forme d'un identifiant**.
 *
 * `client_reference_id` et les métadonnées viennent du dehors : un lien de
 * paiement public accepte le premier en paramètre d'URL. Une valeur mal formée
 * partirait telle quelle dans une RPC typée `uuid`, où PostgREST lèverait une
 * erreur de requête que la fonction traduirait en `500` — et Stripe rejouerait
 * trois jours durant un événement qui ne passera jamais. Une valeur illisible
 * est donc traitée comme **absente** : la caserne se retrouve par le client,
 * qui est le chemin normal de tous les événements sauf le premier.
 */
function caserne(valeur: unknown): string | null {
  const brut = texte(valeur);
  return brut !== null && estUuid(brut) ? brut : null;
}

function objet(valeur: unknown): Record<string, unknown> {
  return valeur !== null && typeof valeur === "object" && !Array.isArray(valeur)
    ? valeur as Record<string, unknown>
    : {};
}

/** Une chaîne non vide, ou `null`. Stripe rend parfois un objet étendu là où il
 * rendait un identifiant : on ne garde que la forme identifiant. */
function texte(valeur: unknown): string | null {
  if (typeof valeur === "string" && valeur.trim() !== "") return valeur.trim();
  if (valeur !== null && typeof valeur === "object") {
    const id = (valeur as Record<string, unknown>).id;
    return typeof id === "string" && id !== "" ? id : null;
  }
  return null;
}

/** Une date Stripe (secondes depuis l'époque) en ISO 8601. */
export function dateStripe(valeur: unknown): string | null {
  const secondes = typeof valeur === "number"
    ? valeur
    : typeof valeur === "string"
    ? Number.parseInt(valeur, 10)
    : Number.NaN;
  if (!Number.isFinite(secondes) || secondes <= 0) return null;
  return new Date(secondes * 1000).toISOString();
}

/**
 * La formule, déduite du prix d'une ligne d'abonnement.
 *
 * `price.recurring.interval` vaut `month` ou `year` : c'est Stripe qui le dit,
 * et c'est plus sûr que de comparer l'identifiant du prix à une variable
 * d'environnement — le jour où le propriétaire crée un second prix mensuel
 * (promotion, tarif association), la comparaison d'identifiants échouerait et la
 * formule deviendrait nulle.
 */
export function formuleDepuisAbonnement(abonnement: Record<string, unknown>): Formule | null {
  const lignes = objet(abonnement.items).data;
  const premiere = Array.isArray(lignes) ? objet(lignes[0]) : {};
  const recurrence = objet(objet(premiere.price).recurring);

  switch (recurrence.interval) {
    case "month":
      return "monthly";
    case "year":
      return "yearly";
    default:
      // Repli : une formule écrite dans les métadonnées au moment de la
      // souscription (`create-checkout` les pose).
      return formuleValide(objet(abonnement.metadata).plan);
  }
}

/**
 * Traduit un événement en conséquence sur `subscriptions`.
 *
 * **Aucun événement inconnu n'est une erreur.** Un compte Stripe émet des
 * dizaines de types ; les ignorer en répondant 200 est la seule façon d'éviter
 * que Stripe ne rejoue indéfiniment ce qu'on ne traitera jamais.
 */
export function interpreter(evenement: Record<string, unknown>): Interpretation {
  const type = typeof evenement.type === "string" ? evenement.type : "";
  const donnees = objet(objet(evenement.data).object);

  if (!TYPES_TRAITES.includes(type)) {
    return { traite: false, type, raison: "type_ignore" };
  }

  const consequence = traduire(type, donnees);

  // Sans caserne **ni** client, il n'y a rien à rattacher. C'est le cas d'une
  // facture ponctuelle, sans abonnement, émise à la main dans le tableau de
  // bord : elle ne concerne pas ce produit.
  if (consequence.station === null && consequence.customer === null) {
    return { traite: false, type, raison: "sans_client" };
  }

  return { traite: true, type, consequence };
}

function traduire(type: string, donnees: Record<string, unknown>): Consequence {
  switch (type) {
    // --- 1. La souscription vient d'aboutir --------------------------------
    // `client_reference_id` porte la caserne : c'est **nous** qui l'avons mis
    // en ouvrant la session (`create-checkout`). C'est le seul événement où la
    // caserne est nommée ; tous les suivants passent par `customer`.
    case "checkout.session.completed": {
      const metadonnees = objet(donnees.metadata);
      return {
        station: caserne(donnees.client_reference_id) ?? caserne(metadonnees.station_id),
        customer: texte(donnees.customer),
        subscription: texte(donnees.subscription),
        // `payment_status` vaut `paid` quand l'argent est passé. Un paiement
        // différé (prélèvement SEPA) laisse `unpaid` : la caserne reste alors
        // en essai jusqu'à `invoice.paid`, ce qui est le comportement juste —
        // on n'ouvre pas les droits sur une promesse.
        statut: donnees.payment_status === "paid" ? "active" : null,
        formule: formuleValide(metadonnees.plan),
        finPeriode: null,
      };
    }

    // --- 2. Une facture est payée ------------------------------------------
    // L'événement du renouvellement mensuel ou annuel. Il ramène la caserne en
    // `active` : c'est lui qui répare un `past_due`.
    case "invoice.paid": {
      return {
        station: caserne(objet(donnees.metadata).station_id),
        customer: texte(donnees.customer),
        subscription: texte(donnees.subscription) ??
          texte(objet(objet(donnees.parent).subscription_details).subscription),
        statut: "active",
        formule: null,
        // `period_end` de la facture, ou la fin de période de la ligne : les
        // deux existent selon la version d'API, et la seconde est la plus
        // précise quand la facture couvre plusieurs lignes.
        finPeriode: dateStripe(finDeLigne(donnees) ?? donnees.period_end),
      };
    }

    // --- 3. Un paiement échoue ---------------------------------------------
    // **Rien n'est coupé.** La caserne passe en `past_due` et continue d'écrire
    // (`station_writable`, migration 0007) : c'est la tâche planifiée qui
    // suspendra, quatorze jours plus tard, si rien n'est réglé.
    case "invoice.payment_failed": {
      return {
        station: caserne(objet(donnees.metadata).station_id),
        customer: texte(donnees.customer),
        subscription: texte(donnees.subscription) ??
          texte(objet(objet(donnees.parent).subscription_details).subscription),
        statut: "past_due",
        formule: null,
        finPeriode: null,
      };
    }

    // --- 4. L'abonnement change ou disparaît -------------------------------
    case "customer.subscription.updated":
    case "customer.subscription.deleted": {
      const supprime = type === "customer.subscription.deleted";
      return {
        station: caserne(objet(donnees.metadata).station_id),
        customer: texte(donnees.customer),
        subscription: texte(donnees.id),
        statut: supprime ? "cancelled" : statutDepuisStripe(donnees.status),
        formule: formuleDepuisAbonnement(donnees),
        finPeriode: supprime ? null : dateStripe(finDeLigne(donnees) ?? donnees.current_period_end),
      };
    }

    default:
      return {
        station: null,
        customer: null,
        subscription: null,
        statut: null,
        formule: null,
        finPeriode: null,
      };
  }
}

/** La fin de période portée par la première ligne, quand elle existe. */
function finDeLigne(donnees: Record<string, unknown>): unknown {
  const lignes = objet(donnees.lines).data ?? objet(donnees.items).data;
  if (!Array.isArray(lignes) || lignes.length === 0) return null;
  const premiere = objet(lignes[0]);
  return objet(premiere.period).end ?? premiere.current_period_end ?? null;
}

/**
 * Les statuts d'abonnement de Stripe, ramenés aux cinq du produit.
 *
 * `suspended` n'en fait **pas** partie : c'est un état que ce produit décide
 * seul, par sa tâche planifiée. Stripe ne sait rien de nos quatorze jours.
 */
export function statutDepuisStripe(valeur: unknown): StatutAbonnement | null {
  switch (valeur) {
    case "active":
      return "active";
    case "trialing":
      return "trialing";
    case "past_due":
    case "unpaid":
      return "past_due";
    case "canceled":
    case "incomplete_expired":
      return "cancelled";
    // `incomplete` et `paused` : rien ne change tant qu'on ne sait pas. Écraser
    // un `active` par un état transitoire couperait l'écriture à une caserne qui
    // a payé.
    default:
      return null;
  }
}
