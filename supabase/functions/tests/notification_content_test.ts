// Les libellés français, le regroupement et les liens profonds (ticket 025).
//
//   deno test supabase/functions/tests/
//
// Ce qui est vérifié ici n'a besoin ni de base, ni de réseau, ni de clés Firebase :
// c'est du texte construit à partir d'une charge utile. C'est aussi ce qu'un
// pompier lit sur son écran verrouillé, donc la partie du ticket qui se voit.

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";

import {
  CANAUX_PAR_DEFAUT,
  construireContenu,
  deMois,
  enumerer,
  etiquette,
  jourCourt,
  jourLong,
  lireCreneaux,
  lirePeriode,
  listerCreneaux,
  regrouper,
  routePour,
  TOUS_LES_TYPES,
  TYPES_CRITIQUES,
  TYPES_REGROUPES,
} from "../_shared/notification_content.ts";

const CASERNE = { stationName: "CIS Saint-Martin", timezone: "Europe/Paris" };

// ---------------------------------------------------------------------------
// Mise en forme
// ---------------------------------------------------------------------------

Deno.test("une date de créneau ne glisse pas d'un jour selon le fuseau du serveur", () => {
  assertEquals(jourCourt("2026-10-12"), "12 octobre");
  assertEquals(jourLong("2026-10-12"), "lundi 12 octobre");
  assertEquals(jourCourt("2026-01-01"), "1 janvier");
  assertEquals(jourLong("2026-12-31"), "jeudi 31 décembre");
});

Deno.test("l'élision distingue « d'octobre » de « de septembre »", () => {
  assertEquals(deMois("octobre"), "d'octobre");
  assertEquals(deMois("avril"), "d'avril");
  assertEquals(deMois("août"), "d'août");
  assertEquals(deMois("septembre"), "de septembre");
  assertEquals(deMois("mai"), "de mai");
});

Deno.test("une énumération française se termine par « et »", () => {
  assertEquals(enumerer([]), "");
  assertEquals(enumerer(["a"]), "a");
  assertEquals(enumerer(["a", "b"]), "a et b");
  assertEquals(enumerer(["a", "b", "c"]), "a, b et c");
});

Deno.test("une longue liste de créneaux est tronquée plutôt qu'illisible", () => {
  const creneaux = [
    { date: "2026-10-03", slot: "day" as const },
    { date: "2026-10-05", slot: "night" as const },
    { date: "2026-10-12", slot: "night" as const },
    { date: "2026-10-19", slot: "day" as const },
    { date: "2026-10-26", slot: "day" as const },
  ];
  assertEquals(
    listerCreneaux(creneaux),
    "le 3 octobre (jour), le 5 octobre (nuit), le 12 octobre (nuit) et 2 autres",
  );
  assertEquals(
    listerCreneaux(creneaux.slice(0, 4)),
    "le 3 octobre (jour), le 5 octobre (nuit), le 12 octobre (nuit) et un autre",
  );
});

Deno.test("les créneaux sont triés par date, puis jour avant nuit", () => {
  const creneaux = lireCreneaux({
    shifts: [
      { date: "2026-10-12", slot: "night" },
      { date: "2026-10-03", slot: "night" },
      { date: "2026-10-03", slot: "day" },
      { date: "2026-10-05", slot: "bidon" },
      "pas un objet",
    ],
  });
  assertEquals(creneaux.map((c) => `${c.date}/${c.slot}`), [
    "2026-10-03/day",
    "2026-10-03/night",
    "2026-10-12/night",
  ]);
});

// ---------------------------------------------------------------------------
// Les libellés, type par type
// ---------------------------------------------------------------------------

Deno.test("tout type produit un titre et un corps non vides, même sans charge utile", () => {
  for (const type of TOUS_LES_TYPES) {
    const contenu = construireContenu(type, {}, CASERNE);
    assert(contenu.titre.trim().length > 0, `${type} : titre vide`);
    assert(contenu.corps.trim().length > 0, `${type} : corps vide`);
    assert(contenu.route.startsWith("/"), `${type} : lien profond invalide`);
    assert(
      !contenu.titre.toLowerCase().includes("undefined"),
      `${type} : « undefined » dans le titre`,
    );
    assert(
      !contenu.corps.toLowerCase().includes("undefined"),
      `${type} : « undefined » dans le corps`,
    );
  }
});

Deno.test("assignment_proposed, un créneau : « Astreinte proposée le 12 octobre, nuit »", () => {
  const contenu = construireContenu(
    "assignment_proposed",
    { period: "2026-10", shifts: [{ date: "2026-10-12", slot: "night" }] },
    CASERNE,
  );
  assertEquals(contenu.titre, "Astreinte proposée le 12 octobre, nuit");
  assertEquals(
    contenu.corps,
    "CIS Saint-Martin te propose une astreinte le lundi 12 octobre, de nuit. " +
      "Accepte ou refuse depuis l'application.",
  );
  assertEquals(contenu.route, "/proposals");
});

Deno.test("assignment_proposed, sept créneaux : un seul texte qui les résume", () => {
  const shifts = [
    { date: "2026-10-03", slot: "day" },
    { date: "2026-10-05", slot: "night" },
    { date: "2026-10-12", slot: "night" },
    { date: "2026-10-14", slot: "day" },
    { date: "2026-10-19", slot: "day" },
    { date: "2026-10-22", slot: "night" },
    { date: "2026-10-26", slot: "day" },
  ];
  const contenu = construireContenu(
    "assignment_proposed",
    { period: "2026-10", shifts },
    CASERNE,
  );
  assertEquals(contenu.titre, "7 astreintes proposées en octobre");
  assertStringIncludes(contenu.corps, "te propose 7 astreintes");
  assertStringIncludes(contenu.corps, "le 3 octobre (jour)");
  assertStringIncludes(contenu.corps, "et 4 autres");
});

Deno.test("availability_reminder nomme le mois et la date limite, dans le fuseau de la caserne", () => {
  const contenu = construireContenu(
    "availability_reminder",
    { period: "2026-10", deadline_at: "2026-09-15T21:59:59Z" },
    CASERNE,
  );
  assertEquals(contenu.titre, "Dispos d'octobre à saisir");
  assertStringIncludes(contenu.corps, "en octobre 2026");
  // 21:59:59 UTC = 23:59:59 à Paris : le rappel ne doit pas annoncer la veille.
  assertStringIncludes(contenu.corps, "mardi 15 septembre à 23:59");
  assertEquals(contenu.route, "/availability/2026-10");
});

Deno.test("assignment_reminder dit ce qui est attendu, au singulier comme au pluriel", () => {
  const un = construireContenu(
    "assignment_reminder",
    { shifts: [{ date: "2026-10-12", slot: "night" }] },
    CASERNE,
  );
  assertEquals(un.titre, "Réponse attendue : astreinte du 12 octobre, nuit");
  assertStringIncludes(un.corps, "lundi 12 octobre, de nuit");

  const trois = construireContenu(
    "assignment_reminder",
    {
      shifts: [
        { date: "2026-10-03", slot: "day" },
        { date: "2026-10-05", slot: "night" },
        { date: "2026-10-12", slot: "night" },
      ],
    },
    CASERNE,
  );
  assertEquals(trois.titre, "3 astreintes attendent ta réponse");
});

Deno.test("assignment_declined nomme le membre, le créneau et le motif", () => {
  const contenu = construireContenu(
    "assignment_declined",
    {
      period: "2026-10",
      member_name: "Jean Dupont",
      decline_reason: "en congés",
      shifts: [{ date: "2026-10-12", slot: "night" }],
    },
    CASERNE,
  );
  assertEquals(contenu.titre, "Astreinte refusée : 12 octobre, nuit");
  assertStringIncludes(contenu.corps, "Jean Dupont a refusé");
  assertStringIncludes(contenu.corps, "Motif : en congés.");
  assertStringIncludes(contenu.corps, "à repourvoir");
  assertEquals(contenu.route, "/admin/schedule/2026-10");
});

Deno.test("assignment_cancelled rassure : il n'y a rien à faire", () => {
  const contenu = construireContenu(
    "assignment_cancelled",
    { period: "2026-10", shifts: [{ date: "2026-10-12", slot: "day" }] },
    CASERNE,
  );
  assertEquals(contenu.titre, "Astreinte annulée : 12 octobre, jour");
  assertStringIncludes(contenu.corps, "Tu n'as rien à faire.");
  assertEquals(contenu.route, "/schedule/2026-10");
});

// La base envoie un **code**, jamais une phrase : le français des notifications
// vit dans `_shared/notification_content.ts`, où il est relu et testé d'un seul
// endroit. `reassign_shift` (migration 0020) s'en sert pour dire au pompier
// remplacé pourquoi sa garde disparaît.
Deno.test("assignment_cancelled traduit le motif que la base donne en code", () => {
  const contenu = construireContenu(
    "assignment_cancelled",
    {
      period: "2026-10",
      reason_code: "reassigned",
      shifts: [{ date: "2026-10-12", slot: "night" }],
    },
    CASERNE,
  );
  assertStringIncludes(contenu.corps, "Motif : le créneau a été confié à un autre pompier.");
});

Deno.test("un motif en clair l'emporte sur le code, et un code inconnu ne rend rien", () => {
  const explicite = construireContenu(
    "assignment_cancelled",
    {
      period: "2026-10",
      reason: "manœuvre annulée",
      reason_code: "reassigned",
      shifts: [{ date: "2026-10-12", slot: "night" }],
    },
    CASERNE,
  );
  assertStringIncludes(explicite.corps, "Motif : manœuvre annulée.");

  // Une notification dégradée vaut mieux qu'une notification perdue : le code
  // inconnu retire une ligne, il ne casse rien.
  const inconnu = construireContenu(
    "assignment_cancelled",
    {
      period: "2026-10",
      reason_code: "quelque_chose_de_neuf",
      shifts: [{ date: "2026-10-12", slot: "night" }],
    },
    CASERNE,
  );
  assertStringIncludes(inconnu.corps, "est annulée.");
  assertEquals(inconnu.corps.includes("Motif"), false);
});

Deno.test("schedule_validated compte les astreintes du membre", () => {
  const contenu = construireContenu(
    "schedule_validated",
    {
      period: "2026-10",
      shifts: [
        { date: "2026-10-03", slot: "day" },
        { date: "2026-10-12", slot: "night" },
      ],
    },
    CASERNE,
  );
  assertEquals(contenu.titre, "Planning d'octobre validé");
  assertStringIncludes(contenu.corps, "Le planning d'octobre 2026 de CIS Saint-Martin est validé");
  assertStringIncludes(contenu.corps, "Tu as 2 astreintes");
  assertEquals(contenu.route, "/schedule/2026-10");
});

Deno.test("late_responders donne le nombre, le délai et les noms", () => {
  const contenu = construireContenu(
    "late_responders",
    {
      period: "2026-10",
      pending_count: 3,
      hours: 72,
      members: ["Jean Dupont", "Marie Martin"],
    },
    CASERNE,
  );
  assertEquals(contenu.titre, "3 astreintes sans réponse");
  assertStringIncludes(contenu.corps, "du planning d'octobre 2026");
  assertStringIncludes(contenu.corps, "depuis plus de 72 h");
  assertStringIncludes(contenu.corps, "Jean Dupont et Marie Martin n'ont pas répondu.");
  assertEquals(contenu.route, "/admin/schedule/2026-10");
});

Deno.test("schedule_all_accepted élide le mois comme le reste", () => {
  const contenu = construireContenu("schedule_all_accepted", { period: "2026-10" }, CASERNE);
  assertEquals(contenu.titre, "Planning d'octobre complet");
  assertStringIncludes(
    contenu.corps,
    "Toutes les astreintes du planning d'octobre 2026 de CIS Saint-Martin ont été acceptées.",
  );

  const septembre = construireContenu("schedule_all_accepted", { period: "2026-09" }, CASERNE);
  assertStringIncludes(septembre.corps, "du planning de septembre 2026");
});

Deno.test("sans nom de caserne, le texte reste lisible", () => {
  const contenu = construireContenu(
    "assignment_proposed",
    { shifts: [{ date: "2026-10-12", slot: "night" }] },
    {},
  );
  assertStringIncludes(contenu.corps, "Ta caserne te propose une astreinte");
});

// ---------------------------------------------------------------------------
// Liens profonds — la forme exacte du ticket 024
// ---------------------------------------------------------------------------

Deno.test("chaque type porte une des cinq destinations de docs/WORKFLOWS.md § 8", () => {
  const charge = { period: "2026-10" };
  assertEquals(routePour("availability_reminder", charge), "/availability/2026-10");
  assertEquals(routePour("assignment_proposed", charge), "/proposals");
  assertEquals(routePour("assignment_reminder", charge), "/proposals");
  assertEquals(routePour("assignment_changed", charge), "/proposals");
  assertEquals(routePour("assignment_cancelled", charge), "/schedule/2026-10");
  assertEquals(routePour("schedule_validated", charge), "/schedule/2026-10");
  assertEquals(routePour("assignment_declined", charge), "/admin/schedule/2026-10");
  assertEquals(routePour("schedule_all_accepted", charge), "/admin/schedule/2026-10");
  assertEquals(routePour("late_responders", charge), "/admin/schedule/2026-10");
  // La cinquième, ticket 030 : elle ignore le mois, un abonnement n'en a pas.
  assertEquals(routePour("subscription_trial_ending", charge), "/admin/subscription");
  assertEquals(routePour("subscription_suspended", charge), "/admin/subscription");
});

Deno.test("la période se déduit des créneaux quand l'appelant l'a oubliée", () => {
  assertEquals(
    lirePeriode({ shifts: [{ date: "2026-10-12", slot: "night" }] }),
    "2026-10",
  );
  assertEquals(lirePeriode({ period: "2026-13" }), null);
  assertEquals(lirePeriode({}), null);
});

Deno.test("une période absente n'annule pas la notification : elle dégrade le lien", () => {
  assertEquals(routePour("schedule_validated", {}), "/proposals");
  assertEquals(routePour("late_responders", { period: "octobre" }), "/proposals");
});

Deno.test("l'étiquette regroupe les notifications d'un même mois", () => {
  assertEquals(
    etiquette("assignment_proposed", { period: "2026-10" }),
    "assignment_proposed:2026-10",
  );
  assertEquals(etiquette("invitation", {}), "invitation");
});

// ---------------------------------------------------------------------------
// Regroupement — docs/WORKFLOWS.md § 8, colonne « Regroupement »
// ---------------------------------------------------------------------------

Deno.test("une publication de sept créneaux ne fait qu'une notification par membre", () => {
  const brut = Array.from({ length: 7 }, (_, i) => ({
    user_id: "11111111-1111-4111-8111-111111111111",
    payload: { period: "2026-10", shifts: [{ date: `2026-10-0${i + 1}`, slot: "night" }] },
  }));
  brut.push({
    user_id: "22222222-2222-4222-8222-222222222222",
    payload: { period: "2026-10", shifts: [{ date: "2026-10-09", slot: "day" }] },
  });

  const groupe = regrouper("assignment_proposed", brut);
  assertEquals(groupe.length, 2);
  assertEquals(lireCreneaux(groupe[0].payload).length, 7);
  assertEquals(lireCreneaux(groupe[1].payload).length, 1);

  const contenu = construireContenu("assignment_proposed", groupe[0].payload, CASERNE);
  assertEquals(contenu.titre, "7 astreintes proposées en octobre");
});

Deno.test("le regroupement dédoublonne les créneaux identiques", () => {
  const groupe = regrouper("assignment_proposed", [
    {
      user_id: "11111111-1111-4111-8111-111111111111",
      payload: { shifts: [{ date: "2026-10-12", slot: "night" }] },
    },
    {
      user_id: "11111111-1111-4111-8111-111111111111",
      payload: { shifts: [{ date: "2026-10-12", slot: "night" }] },
    },
  ]);
  assertEquals(groupe.length, 1);
  assertEquals(lireCreneaux(groupe[0].payload).length, 1);
});

Deno.test("un type non regroupé garde une notification par fait", () => {
  const brut = [
    {
      user_id: "11111111-1111-4111-8111-111111111111",
      payload: { shifts: [{ date: "2026-10-12", slot: "night" }] },
    },
    {
      user_id: "11111111-1111-4111-8111-111111111111",
      payload: { shifts: [{ date: "2026-10-13", slot: "day" }] },
    },
  ];
  assertEquals(regrouper("assignment_declined", brut).length, 2);
  assertEquals(regrouper("assignment_cancelled", brut).length, 2);
  assertEquals(regrouper("assignment_changed", brut).length, 2);
});

Deno.test("la table de regroupement suit docs/WORKFLOWS.md § 8", () => {
  for (
    const type of [
      "availability_reminder",
      "assignment_proposed",
      "assignment_reminder",
      "schedule_validated",
      "late_responders",
    ] as const
  ) {
    assert(TYPES_REGROUPES.has(type), `${type} devrait être regroupé`);
  }
  for (
    const type of [
      "invitation",
      "assignment_declined",
      "assignment_changed",
      "assignment_cancelled",
      "schedule_all_accepted",
    ] as const
  ) {
    assert(!TYPES_REGROUPES.has(type), `${type} ne devrait pas être regroupé`);
  }
});

Deno.test("seules les propositions d'astreinte échappent au réglage du membre", () => {
  assertEquals([...TYPES_CRITIQUES], ["assignment_proposed"]);
});

Deno.test("l'invitation ne part que par courriel", () => {
  assertEquals(CANAUX_PAR_DEFAUT.invitation, ["email"]);
  for (const type of TOUS_LES_TYPES) {
    if (type === "invitation") continue;
    assert(CANAUX_PAR_DEFAUT[type].includes("inapp"), `${type} doit alimenter le centre`);
  }
});

// ---------------------------------------------------------------------------
// Abonnement — ticket 030
// ---------------------------------------------------------------------------

Deno.test("fin d'essai : l'objet nomme la caserne, le corps nomme la date et la conséquence", () => {
  const contenu = construireContenu(
    "subscription_trial_ending",
    { trial_ends_at: "2026-11-20T02:36:11Z", days_left: 7 },
    CASERNE,
  );
  assertEquals(contenu.titre, "Essai de CIS Saint-Martin bientôt terminé");
  assert(contenu.corps.includes("20 novembre"), contenu.corps);
  assert(contenu.corps.includes("lecture seule"), contenu.corps);
  assert(contenu.corps.includes("rien ne sera supprimé"), contenu.corps);
  assertEquals(contenu.route, "/admin/subscription");
});

Deno.test("fin d'essai sans date : le corps retombe sur le nombre de jours", () => {
  const contenu = construireContenu("subscription_trial_ending", { days_left: 7 }, CASERNE);
  assert(contenu.corps.includes("dans 7 jours"), contenu.corps);
});

Deno.test("suspension : « rien n'a été supprimé » est dans le corps", () => {
  const contenu = construireContenu(
    "subscription_suspended",
    { suspended_at: "2026-12-04T03:30:00Z", reason: "trial_expired" },
    CASERNE,
  );
  assertEquals(contenu.titre, "CIS Saint-Martin est en lecture seule");
  assert(contenu.corps.includes("4 décembre"), contenu.corps);
  assert(contenu.corps.includes("Rien n'a été supprimé"), contenu.corps);
  // Le motif ne se reproche pas : il mène au même écran et au même geste.
  assert(!contenu.corps.includes("trial_expired"), contenu.corps);
  assertEquals(contenu.route, "/admin/subscription");
});

Deno.test("les deux types d'abonnement partent par courriel, pas en push", () => {
  for (const type of ["subscription_trial_ending", "subscription_suspended"] as const) {
    assertEquals(CANAUX_PAR_DEFAUT[type], ["email", "inapp"]);
    assert(!CANAUX_PAR_DEFAUT[type].includes("push"), `${type} ne part pas en push`);
    assert(!TYPES_REGROUPES.has(type), `${type} décrit un fait unique`);
  }
});
