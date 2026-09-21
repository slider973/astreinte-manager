// Composition d'un calendrier iCalendar (RFC 5545) à partir d'astreintes.
// Ticket 028, `design/028-export-ics.md § 4`. Module pur : aucune base, aucun
// réseau, aucune variable d'environnement — c'est ce qui le rend testable en CI,
// où les Edge Functions ne sont pas joignables (`supabase/functions/tests/`).
//
// Ce que ce fichier décide, et pourquoi
// -------------------------------------
// **Les heures partent en UTC, pas en heure locale.** Un `DTSTART` sans fuseau
// est une heure « flottante » : elle glisse avec l'appareil qui l'affiche, donc
// une garde de 7 h vue depuis un téléphone resté à l'heure d'un autre pays
// s'affiche à 8 h. La seule autre façon de rester exact serait un bloc
// `VTIMEZONE` complet par fuseau, avec ses règles de changement d'heure — du
// code à maintenir pour dire ce que la base de données du système sait déjà.
// L'instant est donc résolu ici, dans le fuseau de la caserne, à la date de
// chaque garde : le passage à l'heure d'hiver est compris, sans table.
//
// **La nuit est l'intervalle complémentaire du jour** (`day_end → day_start`),
// exactement comme `HeuresAffichage` au ticket 027. Un créneau qui franchit
// minuit finit le lendemain — et c'est vrai aussi d'une caserne qui réglerait
// son « jour » de 19:00 à 07:00.
//
// **Pas de `VALARM`.** L'application a ses rappels (ticket 022) ; un second
// système de notification que personne n'a demandé se règle dans un troisième
// outil (`design/028-export-ics.md § 4`).

/** Une astreinte telle que `ics_feed_events` (migration 0029) la rend. */
export type EvenementAstreinte = {
  id: string;
  date: string;
  creneau: string;
  caserne: string;
  fuseau: string;
  debut_jour: string;
  fin_jour: string;
  modifie_le?: string | null;
};

/** Le nom du calendrier, tel que Google et Apple l'affichent dans leur liste. */
export const NOM_CALENDRIER = "Mes astreintes";

/**
 * Fréquence de rafraîchissement suggérée aux agendas qui la lisent
 * (`REFRESH-INTERVAL`, `X-PUBLISHED-TTL`).
 *
 * Six heures : un planning se publie une fois par mois et une réattribution est
 * doublée d'une notification push, qui arrive en secondes. Demander moins ferait
 * battre le flux pour rien ; demander beaucoup plus ferait attendre une soirée
 * la personne qui vient d'accepter une garde et regarde son agenda.
 */
export const RAFRAICHISSEMENT = "PT6H";

/** Identifiant de produit, obligatoire dans un `VCALENDAR`. */
const PRODID = "-//Astreinte SP//Flux calendrier//FR";

/** Les octets d'une ligne pliée, continuation comprise (RFC 5545 § 3.1). */
const LIGNE_MAX = 75;

/**
 * Le calendrier complet, prêt à être servi en `text/calendar`.
 *
 * `genereLe` est injectable pour que le test puisse comparer un fichier entier
 * à un fichier attendu : un `DTSTAMP` tiré de l'horloge rendrait toute
 * comparaison impossible.
 */
export function composerCalendrier(
  evenements: EvenementAstreinte[],
  options: { genereLe?: Date } = {},
): string {
  const genereLe = options.genereLe ?? new Date();

  const lignes: string[] = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    `PRODID:${PRODID}`,
    "CALSCALE:GREGORIAN",
    // `PUBLISH` : ce flux se lit, il ne demande pas de réponse. Sans cette
    // méthode, certains clients traitent les événements comme des invitations
    // et proposent « Accepter / Refuser » — la réponse se donne dans
    // l'application (ticket 021), pas dans un agenda.
    "METHOD:PUBLISH",
    `X-WR-CALNAME:${echapper(NOM_CALENDRIER)}`,
    `REFRESH-INTERVAL;VALUE=DURATION:${RAFRAICHISSEMENT}`,
    `X-PUBLISHED-TTL:${RAFRAICHISSEMENT}`,
  ];

  for (const evenement of evenements) {
    lignes.push(...composerEvenement(evenement, genereLe));
  }

  lignes.push("END:VCALENDAR");

  // CRLF, et une ligne vide finale : la RFC ne connaît pas le saut de ligne seul,
  // et plusieurs clients refusent un fichier qui ne se termine pas par un CRLF.
  return lignes.map(plier).join("\r\n") + "\r\n";
}

/** Les lignes d'un `VEVENT`, non pliées. */
function composerEvenement(
  evenement: EvenementAstreinte,
  genereLe: Date,
): string[] {
  const nuit = evenement.creneau === "night";
  const debut = nuit ? evenement.fin_jour : evenement.debut_jour;
  const fin = nuit ? evenement.debut_jour : evenement.fin_jour;

  const depart = instantUtc(evenement.date, debut, evenement.fuseau);
  const arrivee = instantUtc(
    // Un créneau qui franchit minuit finit le lendemain. La nuit toujours, le
    // jour quand une caserne a réglé des horaires qui débordent.
    minutes(fin) <= minutes(debut) ? lendemain(evenement.date) : evenement.date,
    fin,
    evenement.fuseau,
  );

  const lignes = [
    "BEGIN:VEVENT",
    // L'identifiant est celui de l'attribution : c'est ce qui fait que le
    // fichier unique du détail (ticket 028, côté Dart) et ce flux désignent le
    // **même** événement. Qui a fait les deux gestes n'a pas deux lignes dans
    // son agenda.
    `UID:${evenement.id}@astreinte-sp`,
    `DTSTAMP:${horodatage(genereLe)}`,
    `DTSTART:${horodatage(depart)}`,
    `DTEND:${horodatage(arrivee)}`,
    `SUMMARY:${echapper(intitule(nuit, evenement.caserne))}`,
    `DESCRIPTION:${echapper(description(nuit, debut, fin))}`,
    // `docs/SCHEMA.md § 2.1` n'a pas de colonne d'adresse, et ce ticket n'en
    // invente pas : le lieu est le nom de la caserne. Le jour où une adresse
    // arrive, c'est cette ligne, et elle seule, qui change.
    `LOCATION:${echapper(evenement.caserne)}`,
    // Une astreinte acceptée occupe : elle doit rendre son porteur « occupé »
    // dans les agendas partagés, pas « disponible ».
    "STATUS:CONFIRMED",
    "TRANSP:OPAQUE",
  ];

  const modifie = instant(evenement.modifie_le);
  if (modifie) lignes.push(`LAST-MODIFIED:${horodatage(modifie)}`);

  lignes.push("END:VEVENT");
  return lignes;
}

/** « Astreinte nuit — CIS Saint-Martin ». */
export function intitule(nuit: boolean, caserne: string): string {
  const creneau = nuit ? "nuit" : "jour";
  return caserne === "" ? `Astreinte ${creneau}` : `Astreinte ${creneau} — ${caserne}`;
}

/**
 * « Créneau de nuit, de 19:00 à 07:00. Astreinte acceptée. »
 *
 * Un intitulé se tronque dans une vue mensuelle ; la description, elle, survit.
 * C'est elle qui doit porter le mot *jour* ou *nuit* et les heures.
 */
export function description(nuit: boolean, debut: string, fin: string): string {
  return `Créneau de ${nuit ? "nuit" : "jour"}, de ${debut} à ${fin}. ` +
    "Astreinte acceptée.";
}

/**
 * L'instant UTC d'une heure locale (`HH:MM`) un jour donné, dans un fuseau donné.
 *
 * Deux passes, et la seconde n'est pas une précaution de style : au changement
 * d'heure, le décalage à appliquer n'est pas celui qu'on lit à la date supposée.
 * On pose une première approximation, on relit le décalage **à cet instant-là**,
 * et on corrige. Un fuseau inconnu ferait lever `Intl` : la valeur vient de
 * `stations.timezone`, que le déclencheur `stations_check_timezone` (`0001`)
 * vérifie contre `pg_timezone_names`, et le repli est UTC.
 */
export function instantUtc(date: string, heure: string, fuseau: string): Date {
  const [annee, mois, jour] = date.split("-").map(Number);
  const [heures, minutes] = heure.split(":").map(Number);
  const nominal = Date.UTC(annee, mois - 1, jour, heures, minutes, 0);

  let instant = nominal;
  for (let passe = 0; passe < 2; passe++) {
    instant = nominal - decalageMinutes(new Date(instant), fuseau) * 60_000;
  }
  return new Date(instant);
}

/** Le décalage du fuseau, en minutes, à cet instant précis. */
function decalageMinutes(instant: Date, fuseau: string): number {
  let parties: Intl.DateTimeFormatPart[];
  try {
    parties = new Intl.DateTimeFormat("en-US", {
      timeZone: fuseau,
      hour12: false,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    }).formatToParts(instant);
  } catch {
    // Fuseau refusé par `Intl` : on sert de l'UTC plutôt que rien. Une heure
    // décalée se corrige d'un coup d'œil ; un flux en panne ne se voit pas.
    return 0;
  }

  const lu = (type: string) => Number(parties.find((partie) => partie.type === type)?.value ?? "0");
  // `hour12: false` rend minuit en « 24 » sur certaines implémentations.
  const heures = lu("hour") % 24;

  const local = Date.UTC(
    lu("year"),
    lu("month") - 1,
    lu("day"),
    heures,
    lu("minute"),
    lu("second"),
  );
  return (local - trancherSecondes(instant)) / 60_000;
}

/** L'instant, à la seconde : `formatToParts` n'a pas les millisecondes. */
function trancherSecondes(instant: Date): number {
  return Math.floor(instant.getTime() / 1000) * 1000;
}

/** `YYYYMMDDTHHMMSSZ` — la seule forme d'horodatage de ce fichier. */
export function horodatage(instant: Date): string {
  return instant.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

/** Le jour suivant, en `YYYY-MM-DD`. */
function lendemain(date: string): string {
  const [annee, mois, jour] = date.split("-").map(Number);
  return new Date(Date.UTC(annee, mois - 1, jour + 1))
    .toISOString()
    .slice(0, 10);
}

/** `HH:MM` en minutes depuis minuit. */
function minutes(heure: string): number {
  const [h, m] = heure.split(":").map(Number);
  return h * 60 + m;
}

/** Une date ISO, ou `null` si la valeur n'en est pas une. */
function instant(valeur: string | null | undefined): Date | null {
  if (!valeur) return null;
  const lu = new Date(valeur);
  return Number.isNaN(lu.getTime()) ? null : lu;
}

/**
 * Échappe une valeur de type TEXT (RFC 5545 § 3.3.11).
 *
 * L'ordre compte : la barre oblique inverse d'abord, sans quoi on échapperait
 * les barres qu'on vient d'ajouter. Le nom d'une caserne peut contenir une
 * virgule (« CIS Saint-Martin, annexe ») ; sans échappement, elle couperait la
 * propriété en deux valeurs et l'intitulé arriverait tronqué.
 */
export function echapper(valeur: string): string {
  return valeur
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r\n|\r|\n/g, "\\n");
}

/**
 * Plie une ligne à 75 octets (RFC 5545 § 3.1), continuation préfixée d'une
 * espace.
 *
 * Le compte est en **octets**, pas en caractères : « Caserne de Saint-Étienne »
 * pèse plus que sa longueur. Et la coupe ne tombe jamais au milieu d'un
 * caractère — un `É` coupé en deux donne deux octets invalides, et le client
 * affiche un losange noir au milieu du nom d'une caserne.
 */
export function plier(ligne: string): string {
  const encodeur = new TextEncoder();
  if (encodeur.encode(ligne).length <= LIGNE_MAX) return ligne;

  const morceaux: string[] = [];
  let courant = "";
  let octets = 0;
  // La continuation commence par une espace, qui compte dans ses 75 octets.
  let plafond = LIGNE_MAX;

  for (const caractere of ligne) {
    const taille = encodeur.encode(caractere).length;
    if (octets + taille > plafond) {
      morceaux.push(courant);
      courant = "";
      octets = 0;
      plafond = LIGNE_MAX - 1;
    }
    courant += caractere;
    octets += taille;
  }
  if (courant !== "") morceaux.push(courant);

  return morceaux.join("\r\n ");
}
