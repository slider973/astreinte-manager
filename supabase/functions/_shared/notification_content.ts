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
  | "late_responders";

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
      const motif = texte(payload, "reason");
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
  }
}

/**
 * Étiquette de regroupement côté navigateur (`Notification.tag`).
 *
 * Deux notifications de même étiquette se remplacent au lieu de s'empiler : un
 * rappel qui repart n'ajoute pas une ligne de plus dans le centre de
 * notifications du système.
 */
export function etiquette(type: TypeNotification, payload: ChargeUtile): string {
  const periode = lirePeriode(payload);
  return periode ? `${type}:${periode}` : type;
}
