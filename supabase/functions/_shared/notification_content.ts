// Le texte français des notifications, type par type.
//
// Règle qui commande tout le fichier : **une notification se lit hors contexte**.
// Un pompier qui déverrouille son téléphone en manœuvre lit une ligne et doit
// savoir de quoi il s'agit. « Astreinte proposée le 12 octobre, nuit », pas
// « Nouvelle notification ». Le titre porte le fait, le corps porte le détail et
// ce qu'on attend de lui.
//
// Tout est pur : aucune entrée-sortie, aucune dépendance au réseau ni à la base.
// C'est ce qui rend ce fichier testable en CI alors que l'Edge Function, elle, ne
// l'est pas (supabase/functions/README.md, § Tests).
//
// Référence : docs/WORKFLOWS.md § 8 (canaux, regroupement, liens profonds),
// docs/SCHEMA.md § 2.12.

export type TypeNotification =
  | "invitation"
  | "availability_reminder"
  | "assignment_proposed"
  | "assignment_reminder"
  | "assignment_declined"
  | "assignment_changed"
  | "assignment_cancelled"
  | "schedule_validated"
  | "schedule_all_accepted"
  | "late_responders"
  | "subscription_trial_ending"
  | "subscription_suspended"
  | "exchange_requested"
  | "exchange_accepted"
  | "exchange_approved"
  | "exchange_rejected"
  | "exchange_closed";

export type Canal = "push" | "email" | "inapp";

export type Slot = "day" | "night";

/** Un créneau d'astreinte : « le 12 octobre, nuit ». */
export type Creneau = {
  date: string; // AAAA-MM-JJ
  slot: Slot;
  assignment_id?: string;
};

export type ChargeUtile = Record<string, unknown>;

export type Destinataire = {
  user_id: string;
  payload: ChargeUtile;
};

export type Contexte = {
  /** Nom de la caserne, quand il est connu. Les textes s'en passent sinon. */
  stationName?: string;
  /** Fuseau de la caserne, pour les dates qui portent une heure. */
  timezone?: string;
};

export type Contenu = {
  titre: string;
  corps: string;
  /** `notifications.data.route`, un des quatre liens de docs/WORKFLOWS.md § 8. */
  route: string;
};

export const TOUS_LES_TYPES: readonly TypeNotification[] = [
  "invitation",
  "availability_reminder",
  "assignment_proposed",
  "assignment_reminder",
  "assignment_declined",
  "assignment_changed",
  "assignment_cancelled",
  "schedule_validated",
  "schedule_all_accepted",
  "late_responders",
  "subscription_trial_ending",
  "subscription_suspended",
  "exchange_requested",
  "exchange_accepted",
  "exchange_approved",
  "exchange_rejected",
  "exchange_closed",
];

export function estTypeNotification(valeur: unknown): valeur is TypeNotification {
  return typeof valeur === "string" &&
    (TOUS_LES_TYPES as readonly string[]).includes(valeur);
}

/**
 * Canaux par défaut, colonne « Canaux » de docs/WORKFLOWS.md § 8.
 *
 * L'appelant peut les forcer : `availability_reminder` part en push à J-3 et en
 * courriel à J-1, c'est le cron du ticket 015 qui le dit, pas cette table.
 */
export const CANAUX_PAR_DEFAUT: Record<TypeNotification, Canal[]> = {
  invitation: ["email"],
  availability_reminder: ["push", "inapp"],
  assignment_proposed: ["push", "inapp"],
  assignment_reminder: ["push", "inapp"],
  assignment_declined: ["push", "inapp"],
  assignment_changed: ["push", "inapp"],
  assignment_cancelled: ["push", "inapp"],
  schedule_validated: ["push", "inapp"],
  schedule_all_accepted: ["push", "inapp"],
  late_responders: ["push", "inapp"],
  // Courriel d'abord, et c'est la seule famille du produit où c'est le cas : un
  // abonnement ne se règle pas depuis l'écran verrouillé d'un téléphone, et le
  // courriel est le seul canal qui atteigne un chef de centre qui n'a pas ouvert
  // l'application depuis trois semaines — le cas nominal d'une fin d'essai
  // (ticket 030, migration 0024).
  subscription_trial_ending: ["email", "inapp"],
  subscription_suspended: ["email", "inapp"],
  // Échanges d'astreintes (ticket 073, migration 0041) : des faits qui
  // concernent une personne, au moment où ils arrivent. La tâche d'expiration
  // force `inapp` seul hors de la fenêtre horaire locale de la caserne.
  exchange_requested: ["push", "inapp"],
  exchange_accepted: ["push", "inapp"],
  exchange_approved: ["push", "inapp"],
  exchange_rejected: ["push", "inapp"],
  exchange_closed: ["push", "inapp"],
};

/**
 * Les types que `profiles.push_enabled` ne peut pas couper.
 *
 * Un seul, et c'est une décision produit écrite noir sur blanc : « Le membre peut
 * désactiver les push non critiques dans son profil. Les propositions d'astreinte
 * ne sont pas désactivables » (docs/PRD.md § 6.5). L'écran de réglage le dit au
 * membre au lieu de le lui cacher (`AppStrings.notifReglageToujours`).
 *
 * Le rappel de réponse, lui, reste désactivable : il repart en courriel à 48 h
 * (docs/WORKFLOWS.md § 6), donc couper le push ne fait perdre personne.
 */
export const TYPES_CRITIQUES: ReadonlySet<TypeNotification> = new Set<TypeNotification>([
  "assignment_proposed",
]);

/**
 * Les types dont la colonne « Regroupement » de docs/WORKFLOWS.md § 8 dit
 * autre chose que « non ».
 *
 * Concrètement : une publication de planning n'envoie pas sept notifications au
 * membre qui a sept créneaux, elle en envoie une qui les résume. Les types absents
 * de cet ensemble décrivent un fait unique et daté — un refus, une annulation —
 * qu'on ne fusionne pas sans mentir.
 */
export const TYPES_REGROUPES: ReadonlySet<TypeNotification> = new Set<TypeNotification>([
  "availability_reminder",
  "assignment_proposed",
  "assignment_reminder",
  "schedule_validated",
  "late_responders",
]);

// ---------------------------------------------------------------------------
// Regroupement
// ---------------------------------------------------------------------------

/**
 * Fusionne les entrées d'un même destinataire quand le type le permet.
 *
 * Les créneaux sont concaténés et dédoublonnés (date + créneau), les autres clés
 * de la charge utile sont fusionnées, la dernière écrite gagne. L'ordre des
 * destinataires est celui de la première apparition : un envoi est rejouable à
 * l'identique, ce qui compte pour les tests comme pour les journaux.
 *
 * Pour un type non regroupé, chaque entrée reste une notification : deux refus
 * le même jour sont deux faits, et les fondre en un seul ferait disparaître une
 * information que l'admin doit voir.
 */
export function regrouper(
  type: TypeNotification,
  destinataires: readonly Destinataire[],
): Destinataire[] {
  if (!TYPES_REGROUPES.has(type)) {
    return destinataires.map((d) => ({ user_id: d.user_id, payload: { ...d.payload } }));
  }

  const parMembre = new Map<string, Destinataire>();
  for (const entree of destinataires) {
    const existant = parMembre.get(entree.user_id);
    if (!existant) {
      parMembre.set(entree.user_id, {
        user_id: entree.user_id,
        payload: { ...entree.payload },
      });
      continue;
    }
    existant.payload = fusionnerCharges(existant.payload, entree.payload);
  }
  return [...parMembre.values()];
}

function fusionnerCharges(a: ChargeUtile, b: ChargeUtile): ChargeUtile {
  const fusion: ChargeUtile = { ...a, ...b };
  const creneaux = [...lireCreneaux(a), ...lireCreneaux(b)];
  if (creneaux.length > 0) fusion.shifts = dedoublonner(creneaux);
  return fusion;
}

function dedoublonner(creneaux: readonly Creneau[]): Creneau[] {
  const vus = new Set<string>();
  const sortie: Creneau[] = [];
  for (const c of creneaux) {
    const cle = `${c.date}|${c.slot}`;
    if (vus.has(cle)) continue;
    vus.add(cle);
    sortie.push(c);
  }
  return sortie;
}

/** Les créneaux d'une charge utile, triés par date puis jour avant nuit. */
export function lireCreneaux(payload: ChargeUtile): Creneau[] {
  const brut = payload.shifts;
  if (!Array.isArray(brut)) return [];
  const creneaux: Creneau[] = [];
  for (const entree of brut) {
    if (typeof entree !== "object" || entree === null) continue;
    const objet = entree as Record<string, unknown>;
    const date = typeof objet.date === "string" ? objet.date : null;
    const slot = objet.slot === "day" || objet.slot === "night" ? objet.slot : null;
    if (!date || !slot) continue;
    creneaux.push({
      date,
      slot,
      assignment_id: typeof objet.assignment_id === "string" ? objet.assignment_id : undefined,
    });
  }
  return creneaux.sort((a, b) =>
    a.date === b.date
      ? (a.slot === b.slot ? 0 : a.slot === "day" ? -1 : 1)
      : a.date < b.date
      ? -1
      : 1
  );
}

// ---------------------------------------------------------------------------
// Liens profonds — docs/WORKFLOWS.md § 8
// ---------------------------------------------------------------------------
// Quatre destinations, et pas une de plus. Elles sont traduites côté client par
// `lib/features/notifications/domain/destination_push.dart` : toute autre forme
// n'ouvre rien, et le membre retombe sur l'accueil sans message d'erreur.

export const PERIODE_VALIDE = /^\d{4}-(0[1-9]|1[0-2])$/;

/** La période d'une charge utile, si elle est bien formée (`AAAA-MM`). */
export function lirePeriode(payload: ChargeUtile): string | null {
  const brut = payload.period;
  if (typeof brut === "string" && PERIODE_VALIDE.test(brut)) return brut;
  // À défaut, le mois du premier créneau : une notification d'astreinte sait
  // toujours de quel mois elle parle, même si l'appelant a oublié de le dire.
  const creneaux = lireCreneaux(payload);
  if (creneaux.length > 0) {
    const mois = creneaux[0].date.slice(0, 7);
    if (PERIODE_VALIDE.test(mois)) return mois;
  }
  return null;
}

/**
 * Le lien profond d'un type.
 *
 * Les routes qui portent un mois retombent sur `/proposals` quand la période est
 * absente ou mal formée. C'est volontaire : une notification ne se perd pas pour
 * un détail d'itinéraire. Le membre arrive à un endroit utile, et le défaut de
 * l'appelant se voit dans les journaux, pas dans une notification manquante.
 *
 * **`invitation` fait exception et sort des quatre destinations.** `/connexion`
 * n'est pas un lien profond : `destination_push.dart` ne le connaît pas et le
 * rejette, donc un push qui le porterait n'ouvrirait rien. C'est sans conséquence
 * parce que ce type ne part **que** par courriel — où le lien est une adresse
 * complète, pas une destination interne — et parce que `lireDemande` refuse le
 * canal push pour ce type, plutôt que de laisser un appelant fabriquer un lien
 * mort.
 */
export function routePour(type: TypeNotification, payload: ChargeUtile): string {
  const periode = lirePeriode(payload);

  switch (type) {
    case "invitation":
      return "/connexion";
    case "availability_reminder":
      return periode ? `/availability/${periode}` : "/proposals";
    case "assignment_proposed":
    case "assignment_reminder":
    case "assignment_changed":
      return "/proposals";
    case "assignment_cancelled":
    case "schedule_validated":
      return periode ? `/schedule/${periode}` : "/proposals";
    case "assignment_declined":
    case "schedule_all_accepted":
    case "late_responders":
      return periode ? `/admin/schedule/${periode}` : "/proposals";
    // La cinquième destination publique (docs/WORKFLOWS.md § 8). Elle ne porte
    // pas de mois : un abonnement n'a pas de période de saisie.
    case "subscription_trial_ending":
    case "subscription_suspended":
      return "/admin/subscription";
    // Échanges d'astreintes (ticket 073) : deux destinations publiques de plus,
    // sans mois — une demande vit dans une liste, pas dans un planning.
    // `/exchanges` : les demandes reçues, à reprendre et envoyées du pompier ;
    // `/admin/exchanges` : la file des échanges à valider.
    case "exchange_requested":
    case "exchange_rejected":
    case "exchange_closed":
      return "/exchanges";
    case "exchange_accepted":
      return "/admin/exchanges";
    // Validé : le pompier va voir son planning, là où la garde a changé de
    // main ; l'administrateur informé d'une validation automatique va à sa file.
    case "exchange_approved":
      if (payload.audience === "admin") return "/admin/exchanges";
      return periode ? `/schedule/${periode}` : "/exchanges";
  }
}

// ---------------------------------------------------------------------------
// Mise en forme du français
// ---------------------------------------------------------------------------

const MOIS = [
  "janvier",
  "février",
  "mars",
  "avril",
  "mai",
  "juin",
  "juillet",
  "août",
  "septembre",
  "octobre",
  "novembre",
  "décembre",
];

const JOURS = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"];

/**
 * « 12 octobre ».
 *
 * La date d'un créneau est un `date` SQL, pas un instant : elle se formate sans
 * fuseau, sinon « le 12 octobre » devient « le 11 octobre » pour qui se trouve à
 * l'ouest de Greenwich (docs/SCHEMA.md, conventions).
 */
export function jourCourt(date: string): string {
  const d = new Date(`${date}T12:00:00Z`);
  if (Number.isNaN(d.getTime())) return date;
  return `${d.getUTCDate()} ${MOIS[d.getUTCMonth()]}`;
}

/** « lundi 12 octobre ». */
export function jourLong(date: string): string {
  const d = new Date(`${date}T12:00:00Z`);
  if (Number.isNaN(d.getTime())) return date;
  return `${JOURS[d.getUTCDay()]} ${d.getUTCDate()} ${MOIS[d.getUTCMonth()]}`;
}

/** « octobre » à partir de `2026-10`. */
export function moisSeul(periode: string): string {
  const index = Number(periode.slice(5, 7)) - 1;
  return MOIS[index] ?? periode;
}

/** « octobre 2026 » à partir de `2026-10`. */
export function moisAnnee(periode: string): string {
  const index = Number(periode.slice(5, 7)) - 1;
  return MOIS[index] ? `${MOIS[index]} ${periode.slice(0, 4)}` : periode;
}

/** « d'octobre » / « de septembre » : l'élision, qui trahit un texte bâclé. */
export function deMois(nom: string): string {
  return /^[aeiouâéèêîôû]/i.test(nom) ? `d'${nom}` : `de ${nom}`;
}

/** « nuit » / « jour ». */
export function creneauCourt(slot: Slot): string {
  return slot === "night" ? "nuit" : "jour";
}

/** « de nuit » / « de jour ». */
export function creneauLong(slot: Slot): string {
  return slot === "night" ? "de nuit" : "de jour";
}

/** « 3 octobre (jour), 5 octobre (nuit) et 2 autres ». */
export function listerCreneaux(creneaux: readonly Creneau[], maximum = 3): string {
  const visibles = creneaux.slice(0, maximum).map(
    (c) => `le ${jourCourt(c.date)} (${creneauCourt(c.slot)})`,
  );
  const reste = creneaux.length - visibles.length;
  if (reste > 0) visibles.push(reste === 1 ? "un autre" : `${reste} autres`);
  return enumerer(visibles);
}

/** « a, b et c ». */
export function enumerer(elements: readonly string[]): string {
  if (elements.length === 0) return "";
  if (elements.length === 1) return elements[0];
  return `${elements.slice(0, -1).join(", ")} et ${elements[elements.length - 1]}`;
}

/**
 * « vendredi 20 novembre », dans le fuseau de la caserne.
 *
 * Une échéance d'abonnement n'a pas d'heure utile : personne ne règle un
 * abonnement à la minute près, et « jusqu'au 20 novembre à 03:36 » ferait lire
 * une précision que la tâche quotidienne n'a pas.
 */
export function jourInstant(iso: string, fuseau = "Europe/Paris"): string | null {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  try {
    return new Intl.DateTimeFormat("fr-FR", {
      weekday: "long",
      day: "numeric",
      month: "long",
      timeZone: fuseau,
    }).format(d);
  } catch {
    return null;
  }
}

/** « mercredi 15 septembre à 23:59 », dans le fuseau de la caserne. */
export function instantLong(iso: string, fuseau = "Europe/Paris"): string | null {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  try {
    const jour = new Intl.DateTimeFormat("fr-FR", {
      weekday: "long",
      day: "numeric",
      month: "long",
      timeZone: fuseau,
    }).format(d);
    const heure = new Intl.DateTimeFormat("fr-FR", {
      hour: "2-digit",
      minute: "2-digit",
      timeZone: fuseau,
    }).format(d);
    return `${jour} à ${heure}`;
  } catch {
    return null;
  }
}

function texte(payload: ChargeUtile, cle: string): string | null {
  const valeur = payload[cle];
  return typeof valeur === "string" && valeur.trim() !== "" ? valeur.trim() : null;
}

function nombre(payload: ChargeUtile, cle: string): number | null {
  const valeur = payload[cle];
  return typeof valeur === "number" && Number.isFinite(valeur) ? valeur : null;
}

/**
 * Les motifs que la **base** connaît, rendus en français ici.
 *
 * `reassign_shift` (migration 0020) annule la garde du pompier remplacé et doit
 * lui en donner la raison. Elle envoie un **code**, pas une phrase : le français
 * des notifications vit dans ce fichier, où il est testé et relu d'un seul
 * endroit. Une phrase écrite dans une migration aurait échappé au système de
 * chaînes et vieilli seule.
 *
 * Un code inconnu ne rend rien : la notification perd une ligne, elle ne perd
 * pas son sens.
 */
const MOTIFS: Record<string, string> = {
  reassigned: "le créneau a été confié à un autre pompier",
};

/**
 * Pourquoi un échange n'a pas pu se faire : la liste fermée de
 * `shift_exchanges.reason_code` pour une demande `failed` (migration 0041).
 * Les codes `peer_*` parlent du repreneur, `requester_*` du demandeur.
 */
export const MOTIFS_ECHEC_ECHANGE: Record<string, string> = {
  station_suspended: "la caserne est en lecture seule",
  assignment_changed: "l'astreinte a été modifiée par le chef de centre",
  assignment_not_accepted: "l'astreinte cédée n'est plus acquise",
  return_assignment_not_accepted: "l'astreinte donnée en retour n'est plus acquise",
  schedule_not_published: "le planning n'est plus modifiable",
  requester_not_active: "le demandeur n'est plus membre actif de la caserne",
  peer_not_active: "le remplaçant n'est plus membre actif de la caserne",
  peer_already_assigned: "le remplaçant est déjà sur ce créneau",
  peer_shift_quota_reached: "le remplaçant a atteint son plafond d'astreintes du mois",
  peer_weekend_quota_reached: "le remplaçant a atteint son plafond de weekends du mois",
  peer_taken_elsewhere: "le remplaçant est déjà pris dans une autre caserne",
  requester_already_assigned: "le demandeur est déjà sur le créneau rendu",
  requester_shift_quota_reached: "le demandeur a atteint son plafond d'astreintes du mois",
  requester_weekend_quota_reached: "le demandeur a atteint son plafond de weekends du mois",
  requester_taken_elsewhere: "le demandeur est déjà pris dans une autre caserne",
};

function motifCode(payload: ChargeUtile): string | null {
  const code = texte(payload, "reason_code");
  return code === null ? null : MOTIFS[code] ?? null;
}

// ---------------------------------------------------------------------------
// Envoi abandonné — la trace du ticket 040
// ---------------------------------------------------------------------------

/**
 * La clé que `notify_trace_echec` (migration `0022`) pose dans la charge utile
 * commune d'une demande de trace.
 *
 * Une demande de notification qui a épuisé ses cinq tentatives est abandonnée.
 * Sans rien de plus, l'abandon est une ligne de `notification_outbox` que seul
 * le rôle de service voit : le pompier à qui on proposait une astreinte, lui, ne
 * l'apprend jamais. La base remet donc la même demande en file, avec cette clé
 * et le seul canal `inapp` : on n'envoie plus rien, on écrit la ligne du centre
 * de notifications avec son `error`, et l'écran affiche sa mention (ticket 026).
 *
 * Le titre et le corps sortent de `construireContenu` comme d'habitude — c'est
 * tout l'intérêt de passer par ici plutôt que d'écrire la ligne en SQL : le
 * français des notifications ne vit qu'à un seul endroit.
 */
export const CLE_ECHEC_LIVRAISON = "delivery_failure";

export type EchecLivraison = {
  /** Motif **technique**, rangé tel quel dans `notifications.error`. */
  motif: string;
  /** La demande abandonnée, pour retrouver l'incident en exploitation. */
  outboxId: string | null;
  tentatives: number | null;
};

/**
 * Lit la marque d'une demande de trace, ou `null` pour un envoi ordinaire.
 *
 * `motif` n'est jamais vide : c'est lui qui remplit `notifications.error`, et
 * c'est le fait que cette colonne soit renseignée — pas son contenu — qui fait
 * apparaître la mention côté client.
 */
export function lireEchecLivraison(payload: ChargeUtile): EchecLivraison | null {
  const brut = payload[CLE_ECHEC_LIVRAISON];
  if (typeof brut !== "object" || brut === null || Array.isArray(brut)) return null;
  const objet = brut as ChargeUtile;
  return {
    motif: texte(objet, "error") ?? CLE_ECHEC_LIVRAISON,
    outboxId: texte(objet, "outbox_id"),
    tentatives: nombre(objet, "attempts"),
  };
}

// ---------------------------------------------------------------------------
// Le contenu, type par type
// ---------------------------------------------------------------------------

/**
 * Titre, corps et lien profond d'une notification.
 *
 * Ne lève jamais : un appelant qui oublie la moitié de sa charge utile obtient un
 * texte plus pauvre, pas une exception. Une notification dégradée vaut mieux
 * qu'une notification perdue — c'est la même règle que pour les liens profonds.
 */
export function construireContenu(
  type: TypeNotification,
  payload: ChargeUtile,
  contexte: Contexte = {},
): Contenu {
  const caserne = contexte.stationName?.trim() || null;
  const fuseau = contexte.timezone || "Europe/Paris";
  const creneaux = lireCreneaux(payload);
  const periode = lirePeriode(payload);
  const route = routePour(type, payload);

  switch (type) {
    case "invitation": {
      const nom = caserne ?? texte(payload, "station_name") ?? "ta caserne";
      const inviteur = texte(payload, "inviter_name");
      return {
        titre: `Invitation à rejoindre ${nom}`,
        corps: inviteur
          ? `${inviteur} t'invite à rejoindre ${nom} sur Astreinte SP.`
          : `Tu es invité à rejoindre ${nom} sur Astreinte SP.`,
        route,
      };
    }

    case "availability_reminder": {
      const mois = periode ? moisSeul(periode) : null;
      const moisComplet = periode ? moisAnnee(periode) : "le mois à venir";
      const limite = texte(payload, "deadline_at");
      const quand = limite ? instantLong(limite, fuseau) : null;
      return {
        titre: mois ? `Dispos ${deMois(mois)} à saisir` : "Dispos du mois à saisir",
        corps: [
          `Tu n'as pas encore dit quand tu es disponible ${
            periode ? `en ${moisComplet}` : "le mois prochain"
          }.`,
          quand ? `Date limite : ${quand}.` : "Renseigne ta grille avant la date limite.",
        ].join(" "),
        route,
      };
    }

    case "assignment_proposed": {
      if (creneaux.length === 1) {
        const c = creneaux[0];
        return {
          titre: `Astreinte proposée le ${jourCourt(c.date)}, ${creneauCourt(c.slot)}`,
          corps: `${caserne ?? "Ta caserne"} te propose une astreinte le ${jourLong(c.date)}, ${
            creneauLong(c.slot)
          }. Accepte ou refuse depuis l'application.`,
          route,
        };
      }
      if (creneaux.length === 0) {
        return {
          titre: "Des astreintes te sont proposées",
          corps: `${
            caserne ?? "Ta caserne"
          } te propose des astreintes. Ouvre l'application pour les voir et répondre.`,
          route,
        };
      }
      return {
        titre: `${creneaux.length} astreintes proposées${
          periode ? ` en ${moisSeul(periode)}` : ""
        }`,
        corps: `${caserne ?? "Ta caserne"} te propose ${creneaux.length} astreintes : ${
          listerCreneaux(creneaux)
        }. Accepte ou refuse chacune depuis l'application.`,
        route,
      };
    }

    case "assignment_reminder": {
      if (creneaux.length === 1) {
        const c = creneaux[0];
        return {
          titre: `Réponse attendue : astreinte du ${jourCourt(c.date)}, ${creneauCourt(c.slot)}`,
          corps: `Tu n'as pas encore répondu à l'astreinte du ${jourLong(c.date)}, ${
            creneauLong(c.slot)
          }. Sans ta réponse, ${caserne ?? "la caserne"} ne peut pas boucler le planning.`,
          route,
        };
      }
      if (creneaux.length === 0) {
        return {
          titre: "Des astreintes attendent ta réponse",
          corps:
            `Tu n'as pas encore répondu aux astreintes qui te sont proposées. Ouvre l'application pour accepter ou refuser.`,
          route,
        };
      }
      return {
        titre: `${creneaux.length} astreintes attendent ta réponse`,
        corps: `Tu n'as pas encore répondu à ${creneaux.length} astreintes : ${
          listerCreneaux(creneaux)
        }. Sans ta réponse, ${caserne ?? "la caserne"} ne peut pas boucler le planning.`,
        route,
      };
    }

    case "assignment_declined": {
      const membre = texte(payload, "member_name") ?? "Un membre";
      const motif = texte(payload, "decline_reason");
      const c = creneaux[0];
      return {
        titre: c
          ? `Astreinte refusée : ${jourCourt(c.date)}, ${creneauCourt(c.slot)}`
          : "Astreinte refusée",
        corps: [
          c
            ? `${membre} a refusé l'astreinte du ${jourLong(c.date)}, ${creneauLong(c.slot)}.`
            : `${membre} a refusé une astreinte.`,
          motif ? `Motif : ${motif}.` : null,
          "Le créneau est à repourvoir.",
        ].filter((p): p is string => p !== null).join(" "),
        route,
      };
    }

    case "assignment_changed": {
      const c = creneaux[0];
      return {
        titre: c
          ? `Astreinte modifiée : ${jourCourt(c.date)}, ${creneauCourt(c.slot)}`
          : "Astreinte modifiée",
        corps: c
          ? `Ton astreinte du ${jourLong(c.date)}, ${
            creneauLong(c.slot)
          }, a changé. Ouvre l'application pour voir le détail.`
          : `Une de tes astreintes a changé. Ouvre l'application pour voir le détail.`,
        route,
      };
    }

    case "assignment_cancelled": {
      const c = creneaux[0];
      const motif = texte(payload, "reason") ?? motifCode(payload);
      return {
        titre: c
          ? `Astreinte annulée : ${jourCourt(c.date)}, ${creneauCourt(c.slot)}`
          : "Astreinte annulée",
        corps: [
          c
            ? `Ton astreinte du ${jourLong(c.date)}, ${creneauLong(c.slot)}, est annulée.`
            : "Une de tes astreintes est annulée.",
          motif ? `Motif : ${motif}.` : null,
          "Tu n'as rien à faire.",
        ].filter((p): p is string => p !== null).join(" "),
        route,
      };
    }

    case "schedule_validated": {
      const mois = periode ? moisSeul(periode) : null;
      const moisComplet = periode ? moisAnnee(periode) : "du mois";
      return {
        titre: mois ? `Planning ${deMois(mois)} validé` : "Planning validé",
        corps: [
          `Le planning ${periode ? deMois(moisComplet) : "du mois"}${
            caserne ? ` de ${caserne}` : ""
          } est validé.`,
          creneaux.length > 0
            ? `Tu as ${creneaux.length} ${creneaux.length === 1 ? "astreinte" : "astreintes"} : ${
              listerCreneaux(creneaux)
            }.`
            : "Tu peux consulter tes astreintes dans l'application.",
        ].join(" "),
        route,
      };
    }

    case "schedule_all_accepted": {
      const mois = periode ? moisSeul(periode) : null;
      const moisComplet = periode ? moisAnnee(periode) : "du mois";
      return {
        titre: mois ? `Planning ${deMois(mois)} complet` : "Planning complet",
        corps: `Toutes les astreintes du planning ${periode ? deMois(moisComplet) : "du mois"}${
          caserne ? ` de ${caserne}` : ""
        } ont été acceptées. Le planning est validé.`,
        route,
      };
    }

    case "late_responders": {
      const attente = nombre(payload, "pending_count") ?? creneaux.length;
      const heures = nombre(payload, "hours");
      const membres = Array.isArray(payload.members)
        ? (payload.members as unknown[]).filter((m): m is string => typeof m === "string")
        : [];
      const moisComplet = periode ? moisAnnee(periode) : null;
      return {
        titre: attente > 0
          ? `${attente} ${attente === 1 ? "astreinte" : "astreintes"} sans réponse`
          : "Des astreintes sans réponse",
        corps: [
          `${attente > 0 ? attente : "Des"} ${
            attente === 1 ? "proposition" : "propositions"
          } du planning${moisComplet ? ` ${deMois(moisComplet)}` : ""} ${
            attente === 1 ? "attend" : "attendent"
          } une réponse${heures ? ` depuis plus de ${heures} h` : ""}.`,
          membres.length > 0
            ? `${enumerer(membres)} ${membres.length === 1 ? "n'a" : "n'ont"} pas répondu.`
            : null,
          "Relance-les ou réattribue les créneaux.",
        ].filter((p): p is string => p !== null).join(" "),
        route,
      };
    }

    case "subscription_trial_ending": {
      const fin = texte(payload, "trial_ends_at");
      const quand = fin ? jourInstant(fin, fuseau) : null;
      const jours = nombre(payload, "days_left") ?? 7;
      return {
        titre: `Essai ${caserne ? `de ${caserne} ` : ""}bientôt terminé`,
        corps: [
          quand
            ? `La période d'essai se termine le ${quand}.`
            : `La période d'essai se termine dans ${jours} jours.`,
          "Sans abonnement, la caserne passera en lecture seule : tout restera",
          "consultable, rien ne sera supprimé, mais plus personne ne pourra saisir",
          "ses disponibilités ni publier un planning.",
        ].join(" "),
        route,
      };
    }

    case "subscription_suspended": {
      const depuis = texte(payload, "suspended_at");
      const quand = depuis ? jourInstant(depuis, fuseau) : null;
      // Le motif reste **hors du texte** : « essai expiré » et « impayé de plus
      // de quatorze jours » mènent au même écran et au même geste. Le dire
      // ajouterait un reproche sans ajouter une sortie.
      return {
        titre: `${caserne ?? "La caserne"} est en lecture seule`,
        corps: [
          quand ? `L'abonnement est suspendu depuis le ${quand}.` : "L'abonnement est suspendu.",
          "Rien n'a été supprimé : les plannings, les disponibilités et",
          "l'historique restent consultables. La saisie rouvrira dès la reprise",
          "de l'abonnement.",
        ].join(" "),
        route,
      };
    }

    case "exchange_requested":
    case "exchange_accepted":
    case "exchange_approved":
    case "exchange_rejected":
    case "exchange_closed":
      return contenuEchange(type, payload, route);
  }
}

/** Le créneau rendu d'un échange (`return_shift`), s'il est bien formé. */
function creneauRendu(payload: ChargeUtile): Creneau | null {
  const brut = payload.return_shift;
  if (typeof brut !== "object" || brut === null || Array.isArray(brut)) return null;
  return lireCreneaux({ shifts: [brut] })[0] ?? null;
}

/** « l'astreinte du lundi 12 octobre, de nuit ». */
function astreinteDu(c: Creneau | null | undefined): string {
  return c ? `l'astreinte du ${jourLong(c.date)}, ${creneauLong(c.slot)}` : "une astreinte";
}

/** « celle du mardi 13 octobre, de jour ». */
function celleDu(c: Creneau): string {
  return `celle du ${jourLong(c.date)}, ${creneauLong(c.slot)}`;
}

/** « Échange validé : 12 octobre, nuit ». */
function titreCreneau(prefixe: string, c: Creneau | undefined): string {
  return c ? `${prefixe} : ${jourCourt(c.date)}, ${creneauCourt(c.slot)}` : prefixe;
}

type TypeEchange =
  | "exchange_requested"
  | "exchange_accepted"
  | "exchange_approved"
  | "exchange_rejected"
  | "exchange_closed";

/**
 * Le français des échanges d'astreintes (ticket 073, migration 0041).
 *
 * La charge utile commune vient de `exchange_payload` : `kind` (`give` |
 * `swap`), `broadcast`, `shifts[0]` (la garde cédée), `return_shift` (la garde
 * rendue d'un échange), `requester_name`, `taker_name`. S'y ajoutent
 * `expires_at` à la demande, `outcome`, `reason_code` et `reason` à la clôture,
 * `audience` et `auto_approved` à la validation.
 */
function contenuEchange(type: TypeEchange, payload: ChargeUtile, route: string): Contenu {
  const c = lireCreneaux(payload)[0];
  const rendu = creneauRendu(payload);
  const demandeur = texte(payload, "requester_name") ?? "Un collègue";
  const repreneur = texte(payload, "taker_name");

  switch (type) {
    case "exchange_requested": {
      if (payload.broadcast === true) {
        return {
          titre: titreCreneau("Remplaçant cherché", c),
          corps: `${demandeur} cherche quelqu'un pour ${
            astreinteDu(c)
          }. Tu t'es déclaré disponible : le premier qui accepte la reprend.`,
          route,
        };
      }
      if (payload.kind === "swap" && rendu) {
        return {
          titre: titreCreneau("Échange proposé", c),
          corps: `${demandeur} te propose ${astreinteDu(c)}, contre ta garde du ${
            jourLong(rendu.date)
          }, ${creneauLong(rendu.slot)}. Accepte ou décline depuis l'application.`,
          route,
        };
      }
      return {
        titre: titreCreneau("Astreinte à reprendre", c),
        corps: `${demandeur} te propose de reprendre ${
          astreinteDu(c)
        }. Accepte ou décline depuis l'application.`,
        route,
      };
    }

    case "exchange_accepted": {
      const contre = payload.kind === "swap" && rendu ? `, contre ${celleDu(rendu)}` : "";
      return {
        titre: titreCreneau("Échange à valider", c),
        corps:
          `${repreneur ?? "Un collègue"} reprend ${astreinteDu(c)} de ${demandeur}${contre}. ` +
          "Valide ou refuse depuis l'application.",
        route,
      };
    }

    case "exchange_approved": {
      const qui = repreneur ?? "Le remplaçant";
      const faits = payload.kind === "swap" && rendu
        ? `${qui} tient ${astreinteDu(c)} et ${demandeur} ${celleDu(rendu)}.`
        : `${qui} tient désormais ${astreinteDu(c)}, à la place de ${demandeur}.`;
      if (payload.audience === "admin") {
        return {
          titre: titreCreneau("Échange validé automatiquement", c),
          corps: `${faits} Le remplaçant s'était déclaré disponible : tu n'as rien à faire.`,
          route,
        };
      }
      return {
        titre: titreCreneau("Échange validé", c),
        corps: `${faits} Le planning est à jour.`,
        route,
      };
    }

    case "exchange_rejected": {
      if (texte(payload, "reason_code") === "peer_declined") {
        return {
          titre: titreCreneau("Échange décliné", c),
          corps: `${repreneur ?? "Ton collègue"} a décliné ta demande pour ${
            astreinteDu(c)
          }. Tu gardes cette astreinte.`,
          route,
        };
      }
      const motif = texte(payload, "reason");
      return {
        titre: titreCreneau("Échange refusé", c),
        corps: [
          `Le chef de centre a refusé l'échange de ${astreinteDu(c)}.`,
          motif ? `Motif : ${motif}.` : null,
          "Rien ne change dans le planning.",
        ].filter((p): p is string => p !== null).join(" "),
        route,
      };
    }

    case "exchange_closed": {
      const issue = texte(payload, "outcome");
      if (issue === "cancelled") {
        return {
          titre: titreCreneau("Demande d'échange retirée", c),
          corps: `${demandeur} a retiré sa demande pour ${astreinteDu(c)}. Tu n'as rien à faire.`,
          route,
        };
      }
      if (issue === "failed") {
        const code = texte(payload, "reason_code");
        const motif = code ? MOTIFS_ECHEC_ECHANGE[code] ?? null : null;
        return {
          titre: titreCreneau("Échange impossible", c),
          corps: `L'échange de ${astreinteDu(c)} n'a pas pu se faire${
            motif ? ` : ${motif}` : ""
          }. Rien ne change dans le planning.`,
          route,
        };
      }
      return {
        titre: titreCreneau("Demande d'échange expirée", c),
        corps: `La demande pour ${
          astreinteDu(c)
        } n'a pas abouti à temps. Rien ne change dans le planning : ${demandeur} garde cette astreinte.`,
        route,
      };
    }
  }
}

/**
 * Étiquette de regroupement côté navigateur (`Notification.tag`).
 *
 * Deux notifications de même étiquette se remplacent au lieu de s'empiler : un
 * rappel qui repart n'ajoute pas une ligne de plus dans le centre de
 * notifications du système.
 *
 * **La caserne en fait partie** depuis le ticket 072 : sans elle, les
 * propositions d'octobre de B remplaçaient sur l'écran verrouillé celles
 * d'octobre de A, pour un pompier des deux. Les huit premiers caractères de
 * l'identifiant suffisent à séparer les casernes d'un même compte et gardent
 * l'étiquette sous les 64 octets d'`apns-collapse-id` (fcm.ts).
 */
export function etiquette(
  type: TypeNotification,
  payload: ChargeUtile,
  stationId?: string | null,
): string {
  // Une demande d'échange est un fait à elle seule (ticket 073) : deux demandes
  // du même mois ne se remplacent pas, elles appellent deux réponses. Son
  // identifiant tient lieu de mois. « exchange_requested:<8>:<8> » : 36 octets.
  const echange = type.startsWith("exchange_") ? texte(payload, "exchange_id") : null;
  const periode = lirePeriode(payload);
  const base = echange
    ? `${type}:${echange.toLowerCase().slice(0, 8)}`
    : periode
    ? `${type}:${periode}`
    : type;
  const caserne = stationId?.trim().toLowerCase().slice(0, 8);
  return caserne ? `${base}:${caserne}` : base;
}
