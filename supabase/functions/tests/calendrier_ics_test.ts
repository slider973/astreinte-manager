// Composition du flux calendrier — `ics-feed/calendrier.ts` et la lecture du
// jeton dans l'URL. Ticket 028, critère « l'abonnement affiche les astreintes ».
// Lancement : deno test supabase/functions/tests/ --allow-env
//
// Ce que ce fichier garde
// -----------------------
// Un calendrier mal formé ne se voit pas : l'agenda n'affiche simplement rien,
// sans un mot. Les erreurs qui coûtent le plus cher ici sont muettes — une heure
// décalée d'une heure au changement d'horaire, une virgule non échappée qui
// coupe un intitulé, une ligne de plus de 75 octets coupée au milieu d'un
// accent. D'où des assertions sur le **texte produit**, caractère par caractère.

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  composerCalendrier,
  description,
  echapper,
  type EvenementAstreinte,
  horodatage,
  instantUtc,
  intitule,
  plier,
} from "../ics-feed/calendrier.ts";
import { lireJeton } from "../ics-feed/jeton.ts";

const GENERE_LE = new Date("2026-09-21T10:00:00.000Z");

const JOUR: EvenementAstreinte = {
  id: "11111111-1111-4111-8111-111111111111",
  date: "2026-11-14",
  creneau: "day",
  caserne: "CIS Saint-Martin",
  fuseau: "Europe/Paris",
  debut_jour: "07:00",
  fin_jour: "19:00",
  modifie_le: "2026-09-20T08:30:00.000Z",
};

const NUIT: EvenementAstreinte = {
  ...JOUR,
  id: "22222222-2222-4222-8222-222222222222",
  creneau: "night",
};

// ---------------------------------------------------------------------------
// L'enveloppe
// ---------------------------------------------------------------------------

Deno.test("un calendrier vide reste un calendrier valide", () => {
  const ics = composerCalendrier([], { genereLe: GENERE_LE });

  assert(ics.startsWith("BEGIN:VCALENDAR\r\n"));
  assert(ics.endsWith("END:VCALENDAR\r\n"));
  assertStringIncludes(ics, "VERSION:2.0");
  assertStringIncludes(ics, "X-WR-CALNAME:Mes astreintes");
  // Un membre désactivé, ou qui n'a pas encore d'astreinte : son agenda ne doit
  // pas afficher d'erreur pour un état parfaitement normal.
  assertEquals(ics.includes("BEGIN:VEVENT"), false);
});

Deno.test("toutes les lignes se terminent par CRLF", () => {
  const ics = composerCalendrier([JOUR], { genereLe: GENERE_LE });
  assertEquals(ics.includes("\n\n"), false);
  for (const ligne of ics.split("\r\n")) {
    assertEquals(ligne.includes("\n"), false);
  }
});

// ---------------------------------------------------------------------------
// Le contenu d'un événement — le § 4 du brief de design
// ---------------------------------------------------------------------------

Deno.test("l'événement de jour dit tout ce qu'il a à dire", () => {
  const ics = composerCalendrier([JOUR], { genereLe: GENERE_LE });

  assertStringIncludes(ics, `UID:${JOUR.id}@astreinte-sp`);
  assertStringIncludes(ics, "SUMMARY:Astreinte jour — CIS Saint-Martin");
  assertStringIncludes(
    ics,
    "DESCRIPTION:Créneau de jour\\, de 07:00 à 19:00. Astreinte acceptée.",
  );
  assertStringIncludes(ics, "LOCATION:CIS Saint-Martin");
  assertStringIncludes(ics, "STATUS:CONFIRMED");
  assertStringIncludes(ics, "DTSTAMP:20260921T100000Z");
  assertStringIncludes(ics, "LAST-MODIFIED:20260920T083000Z");
  // 14 novembre : heure d'hiver, UTC+1. 07:00 locale = 06:00 UTC.
  assertStringIncludes(ics, "DTSTART:20261114T060000Z");
  assertStringIncludes(ics, "DTEND:20261114T180000Z");
  // Pas d'alarme : l'application a déjà ses rappels (ticket 022).
  assertEquals(ics.includes("BEGIN:VALARM"), false);
});

Deno.test("la nuit est l'intervalle complémentaire et finit le lendemain", () => {
  const ics = composerCalendrier([NUIT], { genereLe: GENERE_LE });

  assertStringIncludes(ics, "SUMMARY:Astreinte nuit — CIS Saint-Martin");
  assertStringIncludes(
    ics,
    "DESCRIPTION:Créneau de nuit\\, de 19:00 à 07:00. Astreinte acceptée.",
  );
  assertStringIncludes(ics, "DTSTART:20261114T180000Z");
  assertStringIncludes(ics, "DTEND:20261115T060000Z");
});

Deno.test("aucune identité de collègue ne peut entrer dans le fichier", () => {
  // Le module ne reçoit que ce que `ics_feed_events` rend : il n'a aucun champ
  // où loger un nom de personne. Le test le constate sur le texte produit.
  const ics = composerCalendrier([JOUR, NUIT], { genereLe: GENERE_LE });
  assertEquals(ics.includes("ATTENDEE"), false);
  assertEquals(ics.includes("ORGANIZER"), false);
  assertEquals(ics.includes("@caserne"), false);
});

Deno.test("chaque caserne garde ses heures et son fuseau", () => {
  const ailleurs: EvenementAstreinte = {
    ...JOUR,
    id: "33333333-3333-4333-8333-333333333333",
    caserne: "CIS Saint-Denis",
    fuseau: "Indian/Reunion",
    debut_jour: "06:00",
    fin_jour: "18:00",
  };

  const ics = composerCalendrier([ailleurs], { genereLe: GENERE_LE });
  // La Réunion est à UTC+4 toute l'année : 06:00 locale = 02:00 UTC.
  assertStringIncludes(ics, "DTSTART:20261114T020000Z");
  assertStringIncludes(ics, "DTEND:20261114T140000Z");
});

// ---------------------------------------------------------------------------
// Les heures : le changement d'horaire, et rien d'approximatif
// ---------------------------------------------------------------------------

Deno.test("l'heure d'été et l'heure d'hiver ne se confondent pas", () => {
  // 14 juillet, Paris : UTC+2.
  assertEquals(
    horodatage(instantUtc("2026-07-14", "07:00", "Europe/Paris")),
    "20260714T050000Z",
  );
  // 14 janvier, Paris : UTC+1.
  assertEquals(
    horodatage(instantUtc("2026-01-14", "07:00", "Europe/Paris")),
    "20260114T060000Z",
  );
  // La nuit du passage à l'heure d'hiver 2026 : le 25 octobre à 03:00 locale,
  // l'horloge est déjà revenue à UTC+1.
  assertEquals(
    horodatage(instantUtc("2026-10-25", "03:00", "Europe/Paris")),
    "20261025T020000Z",
  );
  // La veille au soir, elle, est encore à UTC+2.
  assertEquals(
    horodatage(instantUtc("2026-10-24", "19:00", "Europe/Paris")),
    "20261024T170000Z",
  );
});

Deno.test("un fuseau que le système ne connaît pas sert de l'UTC plutôt que rien", () => {
  assertEquals(
    horodatage(instantUtc("2026-11-14", "07:00", "Mars/Olympus_Mons")),
    "20261114T070000Z",
  );
});

// ---------------------------------------------------------------------------
// L'échappement et le pliage : les pannes muettes
// ---------------------------------------------------------------------------

Deno.test("les caractères de structure sont échappés", () => {
  assertEquals(echapper("CIS Saint-Martin, annexe"), "CIS Saint-Martin\\, annexe");
  assertEquals(echapper("a;b"), "a\\;b");
  assertEquals(echapper("a\\b"), "a\\\\b");
  assertEquals(echapper("deux\nlignes"), "deux\\nlignes");
  // La barre oblique inverse d'abord : sinon on échapperait ses propres ajouts.
  assertEquals(echapper("a\\,b"), "a\\\\\\,b");
});

Deno.test("une virgule dans le nom d'une caserne ne coupe pas l'intitulé", () => {
  const ics = composerCalendrier(
    [{ ...JOUR, caserne: "CIS Saint-Martin, annexe des Prés" }],
    { genereLe: GENERE_LE },
  );
  assertStringIncludes(ics, "Astreinte jour — CIS Saint-Martin\\, annexe des Prés");
});

Deno.test("aucune ligne ne dépasse 75 octets", () => {
  const encodeur = new TextEncoder();
  const ics = composerCalendrier(
    [{ ...JOUR, caserne: "Centre d'incendie et de secours de Saint-Étienne-du-Rouvray" }],
    { genereLe: GENERE_LE },
  );

  for (const ligne of ics.split("\r\n")) {
    assert(
      encodeur.encode(ligne).length <= 75,
      `ligne de ${encodeur.encode(ligne).length} octets : ${ligne}`,
    );
  }
});

Deno.test("le pliage ne coupe jamais un caractère accentué en deux", () => {
  // Que des « é » : chaque caractère pèse deux octets, donc une coupe naïve à
  // 75 octets tomberait au milieu de l'un d'eux.
  const plie = plier("X:" + "é".repeat(80));
  const morceaux = plie.split("\r\n ");
  assert(morceaux.length > 1, "la ligne devait être pliée");
  // Recollée, elle doit redonner l'originale : rien de perdu, rien d'abîmé.
  assertEquals(morceaux.join(""), "X:" + "é".repeat(80));
  assertEquals(plie.includes("�"), false);
});

Deno.test("une ligne courte n'est pas pliée", () => {
  assertEquals(plier("SUMMARY:Astreinte jour"), "SUMMARY:Astreinte jour");
});

// ---------------------------------------------------------------------------
// Les deux phrases, prises isolément
// ---------------------------------------------------------------------------

Deno.test("l'intitulé nomme le créneau puis la caserne", () => {
  assertEquals(intitule(false, "CIS Saint-Martin"), "Astreinte jour — CIS Saint-Martin");
  assertEquals(intitule(true, "CIS Saint-Martin"), "Astreinte nuit — CIS Saint-Martin");
  // Sans caserne lisible, l'intitulé ne finit pas par un tiret orphelin.
  assertEquals(intitule(true, ""), "Astreinte nuit");
});

Deno.test("la description porte le mot jour ou nuit, qu'un intitulé tronqué perdrait", () => {
  assertStringIncludes(description(false, "07:00", "19:00"), "Créneau de jour");
  assertStringIncludes(description(true, "19:00", "07:00"), "Créneau de nuit");
  assertStringIncludes(description(true, "19:00", "07:00"), "de 19:00 à 07:00");
});

// ---------------------------------------------------------------------------
// Le jeton dans l'URL
// ---------------------------------------------------------------------------

const JETON = "a".repeat(48);

Deno.test("le jeton se lit dans le chemin comme dans la requête", () => {
  assertEquals(lireJeton(`https://x.fr/functions/v1/ics-feed/${JETON}.ics`), JETON);
  assertEquals(lireJeton(`https://x.fr/functions/v1/ics-feed/${JETON}`), JETON);
  assertEquals(lireJeton(`https://x.fr/functions/v1/ics-feed?token=${JETON}`), JETON);
  assertEquals(lireJeton(`https://x.fr/functions/v1/ics-feed/?token=${JETON}`), JETON);
});

Deno.test("ce qui n'a pas la forme d'un jeton n'atteint pas la base", () => {
  assertEquals(lireJeton("https://x.fr/functions/v1/ics-feed"), "");
  assertEquals(lireJeton("https://x.fr/functions/v1/ics-feed/.ics"), "");
  assertEquals(lireJeton("https://x.fr/functions/v1/ics-feed?token="), "");
  assertEquals(lireJeton("https://x.fr/functions/v1/ics-feed/court.ics"), "");
  assertEquals(
    lireJeton("https://x.fr/functions/v1/ics-feed/' or 1=1 --.ics"),
    "",
  );
});
