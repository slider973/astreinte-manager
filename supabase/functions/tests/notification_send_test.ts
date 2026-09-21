// L'enchaînement d'un envoi : ligne interne, push, courriel (ticket 025).
//
// Les dépendances sont fausses — pas de base, pas de FCM, pas de Resend — mais
// l'enchaînement testé est exactement celui qui tourne en production : c'est le
// même `traiterEnvoi`, `send-notification/index.ts` ne fait que lui brancher les
// vraies implémentations.
//
// Les sept promesses vérifiées ici sont celles du ticket, plus celle que la revue
// a trouvée manquante (la septième) :
//   1. la ligne interne est écrite même quand tout envoi échoue ;
//   2. un membre sans appareil reçoit un courriel ;
//   3. `push_enabled = false` coupe le push des types non critiques…
//   4. …et ne coupe pas les propositions d'astreinte ;
//   5. un jeton définitivement rejeté est supprimé, un jeton en panne passagère
//      est conservé ;
//   6. une publication ne produit qu'une notification par membre ;
//   7. une ligne interne qui n'a pas pu s'écrire n'est jamais comptée comme
//      délivrée — sans quoi la demande serait close en « sent » et la
//      notification disparaîtrait sans trace ni reprise.

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";

import {
  type Caserne,
  type DemandeEnvoi,
  type Deps,
  type Jeton,
  type LigneNotification,
  lireDemande,
  type Profil,
  traiterEnvoi,
} from "../_shared/notification_send.ts";
import type { ResultatPush } from "../_shared/fcm.ts";
import type { MailResult } from "../_shared/mailer.ts";

const CASERNE: Caserne = { name: "CIS Saint-Martin", timezone: "Europe/Paris" };

const MEMBRE = "11111111-1111-4111-8111-111111111111";
const AUTRE = "22222222-2222-4222-8222-222222222222";

function profil(id: string, push_enabled = true): Profil {
  return {
    id,
    email: `${id.slice(0, 8)}@caserne-a.test`,
    first_name: "Jean",
    last_name: "Dupont",
    push_enabled,
  };
}

type Journal = {
  notifications: LigneNotification[];
  jetonsSupprimes: string[];
  courriels: { to: string; titre: string }[];
  pushEnvoyes: {
    jetons: string[];
    titre: string;
    donnees: Record<string, string>;
    lien?: string;
  }[];
};

function faussesDeps(options: {
  profils?: Profil[];
  jetons?: Record<string, Jeton[]>;
  push?: (jetons: string[]) => ResultatPush;
  mail?: MailResult;
  echecEcriture?: boolean;
}): { deps: Deps; journal: Journal } {
  const journal: Journal = {
    notifications: [],
    jetonsSupprimes: [],
    courriels: [],
    pushEnvoyes: [],
  };

  const deps: Deps = {
    lireCaserne: () => Promise.resolve(CASERNE),
    lireProfils: () => Promise.resolve(options.profils ?? [profil(MEMBRE)]),
    lireJetons: () => {
      const carte = new Map<string, Jeton[]>();
      for (const [id, jetons] of Object.entries(options.jetons ?? {})) {
        carte.set(id, jetons);
      }
      return Promise.resolve(carte);
    },
    ecrireNotification: (ligne) => {
      journal.notifications.push(ligne);
      return Promise.resolve(
        options.echecEcriture ? null : `notif-${journal.notifications.length}`,
      );
    },
    supprimerJetons: (jetons) => {
      journal.jetonsSupprimes.push(...jetons);
      return Promise.resolve();
    },
    envoyerPush: (jetons, message) => {
      journal.pushEnvoyes.push({
        jetons,
        titre: message.titre,
        donnees: message.donnees,
        lien: message.lien,
      });
      return Promise.resolve(
        options.push?.(jetons) ??
          {
            tentes: jetons.length,
            delivres: jetons.length,
            jetonsMorts: [],
            resultats: jetons.map((token) => ({ token, ok: true })),
          },
      );
    },
    envoyerCourriel: (destinataire, contenu) => {
      journal.courriels.push({ to: destinataire, titre: contenu.titre });
      return Promise.resolve(options.mail ?? { sent: true, provider: "mailpit" });
    },
    maintenant: () => new Date("2026-09-20T08:00:00Z"),
  };

  return { deps, journal };
}

function demande(partiel: Partial<DemandeEnvoi> = {}): DemandeEnvoi {
  return {
    type: "assignment_proposed",
    station_id: "aaaaaaaa-0000-4000-8000-000000000001",
    recipients: [{
      user_id: MEMBRE,
      payload: { period: "2026-10", shifts: [{ date: "2026-10-12", slot: "night" }] },
    }],
    payload: {},
    channels: null,
    ...partiel,
  };
}

// ---------------------------------------------------------------------------
// 1. La ligne interne survit à tout
// ---------------------------------------------------------------------------

Deno.test("la ligne interne est écrite avant l'envoi, et reste quand tout échoue", async () => {
  const { deps, journal } = faussesDeps({
    jetons: { [MEMBRE]: [{ token: "MORT", platform: "web" }] },
    push: () => ({
      tentes: 1,
      delivres: 0,
      jetonsMorts: [],
      resultats: [{ token: "MORT", ok: false, verdict: "temporaire", error: "fcm 503" }],
    }),
    mail: { sent: false, provider: "none", error: "aucun fournisseur" },
  });

  const resultat = await traiterEnvoi(deps, demande());

  const inapp = journal.notifications.filter((n) => n.channel === "inapp");
  assertEquals(inapp.length, 1);
  assertEquals(inapp[0].delivered, true);
  assertEquals(inapp[0].title, "Astreinte proposée le 12 octobre, nuit");
  // Elle est écrite en premier : le centre de notifications ne dépend d'aucun envoi.
  assertEquals(journal.notifications[0].channel, "inapp");

  // Le push en échec est tracé avec son erreur, pas passé sous silence.
  const push = journal.notifications.find((n) => n.channel === "push");
  assertEquals(push?.delivered, false);
  assertStringIncludes(String(push?.error), "fcm 503");

  // Et le destinataire reste « servi » : il verra la notification dans l'app.
  assertEquals(resultat.ok, true);
  assertEquals(resultat.delivered, 1);
});

Deno.test("une ligne interne qui échoue à s'écrire n'est pas comptée comme délivrée", async () => {
  // C'est le point que la revue a relevé : l'insertion peut échouer (contrainte,
  // base indisponible) et rendre `null`. Poser `inapp: true` sans regarder faisait
  // compter le membre comme servi, clore la demande en « sent », et la
  // notification disparaissait — sans ligne à lire, sans reprise, sans trace.
  const { deps, journal } = faussesDeps({
    echecEcriture: true,
    jetons: {},
    mail: { sent: false, provider: "none", error: "aucun fournisseur" },
  });

  const resultat = await traiterEnvoi(deps, demande());

  // L'insertion a bien été tentée…
  assertEquals(journal.notifications.filter((n) => n.channel === "inapp").length, 1);
  // …mais elle n'a rien produit, et le résultat le dit.
  assertEquals(resultat.results[0].inapp, false);
  assertEquals(resultat.results[0].notification_id, null);
  assertEquals(resultat.results[0].ok, false);
  assertEquals(resultat.results[0].code, "no_channel_delivered");
  // Donc la demande n'est pas close comme réussie : la file la reprendra.
  assertEquals(resultat.ok, false);
  assertEquals(resultat.failed, 1);
});

Deno.test("une ligne interne perdue reste rattrapée par un canal qui, lui, aboutit", async () => {
  const { deps } = faussesDeps({ echecEcriture: true, jetons: {} });

  const resultat = await traiterEnvoi(deps, demande());

  // Le courriel de repli est parti : le membre est prévenu, même si le centre de
  // notifications n'a rien reçu. Inutile de rejouer l'envoi.
  assertEquals(resultat.results[0].inapp, false);
  assertEquals(resultat.results[0].email?.sent, true);
  assertEquals(resultat.ok, true);
});

Deno.test("le lien du push est une adresse complète, pas le chemin interne", async () => {
  const { deps, journal } = faussesDeps({
    jetons: { [MEMBRE]: [{ token: "T1", platform: "web" }] },
  });

  await traiterEnvoi(deps, demande());

  const lien = journal.pushEnvoyes[0].lien;
  assert(lien !== undefined && lien.endsWith("/#/proposals"), `lien inattendu : ${lien}`);
  assert(
    lien.startsWith("http://") || lien.startsWith("https://"),
    "le lien doit être une adresse complète",
  );
});

// ---------------------------------------------------------------------------
// 2. Le repli par courriel
// ---------------------------------------------------------------------------

Deno.test("un membre sans appareil reçoit un courriel", async () => {
  const { deps, journal } = faussesDeps({ jetons: {} });

  const resultat = await traiterEnvoi(deps, demande());

  assertEquals(resultat.results[0].push?.skipped, "no_token");
  assertEquals(journal.courriels.length, 1);
  assertEquals(journal.courriels[0].to, "11111111@caserne-a.test");
  assertEquals(journal.courriels[0].titre, "Astreinte proposée le 12 octobre, nuit");
  assertEquals(resultat.results[0].email?.fallback, true);

  // Le courriel de repli est tracé, comme tout envoi.
  const trace = journal.notifications.find((n) => n.channel === "email");
  assertEquals(trace?.delivered, true);
  assertEquals((trace?.data as Record<string, unknown>).fallback, true);
});

Deno.test("un push qui n'atteint aucun appareil bascule aussi sur le courriel", async () => {
  const { deps, journal } = faussesDeps({
    jetons: { [MEMBRE]: [{ token: "MORT", platform: "web" }] },
    push: () => ({
      tentes: 1,
      delivres: 0,
      jetonsMorts: ["MORT"],
      resultats: [{ token: "MORT", ok: false, verdict: "permanent", error: "fcm 404" }],
    }),
  });

  await traiterEnvoi(deps, demande());
  assertEquals(journal.courriels.length, 1);
});

// ---------------------------------------------------------------------------
// 3 et 4. Le réglage du membre
// ---------------------------------------------------------------------------

Deno.test("push_enabled = false coupe le push d'un type non critique, sans repli courriel", async () => {
  const { deps, journal } = faussesDeps({
    profils: [profil(MEMBRE, false)],
    jetons: { [MEMBRE]: [{ token: "VIVANT", platform: "web" }] },
  });

  const resultat = await traiterEnvoi(
    deps,
    demande({
      type: "schedule_validated",
      recipients: [{ user_id: MEMBRE, payload: { period: "2026-10" } }],
    }),
  );

  assertEquals(resultat.results[0].push?.skipped, "push_disabled");
  assertEquals(journal.pushEnvoyes.length, 0);
  // « Ne me préviens pas » ne veut pas dire « préviens-moi autrement ».
  assertEquals(journal.courriels.length, 0);
  // La ligne interne, elle, est écrite : le centre de notifications reste complet.
  assertEquals(journal.notifications.filter((n) => n.channel === "inapp").length, 1);
});

Deno.test("push_enabled = false ne coupe pas une proposition d'astreinte", async () => {
  const { deps, journal } = faussesDeps({
    profils: [profil(MEMBRE, false)],
    jetons: { [MEMBRE]: [{ token: "VIVANT", platform: "web" }] },
  });

  const resultat = await traiterEnvoi(deps, demande());

  // docs/PRD.md § 6.5 : « Les propositions d'astreinte ne sont pas désactivables ».
  assertEquals(resultat.results[0].push?.delivered, 1);
  assertEquals(journal.pushEnvoyes.length, 1);
});

Deno.test("le réglage ne concerne pas le courriel demandé explicitement", async () => {
  const { deps, journal } = faussesDeps({ profils: [profil(MEMBRE, false)] });

  await traiterEnvoi(
    deps,
    demande({
      type: "availability_reminder",
      channels: ["email", "inapp"],
      recipients: [{ user_id: MEMBRE, payload: { period: "2026-10" } }],
    }),
  );

  assertEquals(journal.courriels.length, 1);
  assertEquals(journal.pushEnvoyes.length, 0);
});

// ---------------------------------------------------------------------------
// 5. Le nettoyage des jetons
// ---------------------------------------------------------------------------

Deno.test("un jeton définitivement rejeté est supprimé, un jeton en panne est conservé", async () => {
  const { deps, journal } = faussesDeps({
    jetons: {
      [MEMBRE]: [
        { token: "VIVANT", platform: "web" },
        { token: "MORT", platform: "android" },
        { token: "PANNE", platform: "ios" },
      ],
    },
    push: () => ({
      tentes: 3,
      delivres: 1,
      jetonsMorts: ["MORT"],
      resultats: [
        { token: "VIVANT", ok: true },
        { token: "MORT", ok: false, verdict: "permanent", error: "fcm 404 UNREGISTERED" },
        { token: "PANNE", ok: false, verdict: "temporaire", error: "fcm 503" },
      ],
    }),
  });

  await traiterEnvoi(deps, demande());

  assertEquals(journal.jetonsSupprimes, ["MORT"]);
  assert(!journal.jetonsSupprimes.includes("PANNE"));
  assert(!journal.jetonsSupprimes.includes("VIVANT"));
});

Deno.test("tous les appareils d'un membre sont visés", async () => {
  const { deps, journal } = faussesDeps({
    jetons: {
      [MEMBRE]: [
        { token: "TEL", platform: "android" },
        { token: "ORDI", platform: "web" },
      ],
    },
  });

  await traiterEnvoi(deps, demande());

  assertEquals(journal.pushEnvoyes.length, 1);
  assertEquals(journal.pushEnvoyes[0].jetons, ["TEL", "ORDI"]);
  // Le lien profond voyage avec la notification (ticket 024).
  assertEquals(journal.pushEnvoyes[0].donnees.route, "/proposals");
  assertEquals(journal.pushEnvoyes[0].donnees.notification_id, "notif-1");
});

// ---------------------------------------------------------------------------
// 6. Le regroupement, vu du bout en bout
// ---------------------------------------------------------------------------

Deno.test("une publication de sept créneaux n'écrit qu'une notification par membre", async () => {
  const { deps, journal } = faussesDeps({
    profils: [profil(MEMBRE), profil(AUTRE)],
    jetons: { [MEMBRE]: [{ token: "T1", platform: "web" }] },
  });

  const recipients = [
    ...Array.from({ length: 7 }, (_, i) => ({
      user_id: MEMBRE,
      payload: { shifts: [{ date: `2026-10-0${i + 1}`, slot: "night" }] },
    })),
    { user_id: AUTRE, payload: { shifts: [{ date: "2026-10-09", slot: "day" }] } },
  ];

  const resultat = await traiterEnvoi(
    deps,
    demande({ payload: { period: "2026-10" }, recipients }),
  );

  assertEquals(resultat.recipients, 2);
  assertEquals(journal.notifications.filter((n) => n.channel === "inapp").length, 2);
  assertEquals(journal.pushEnvoyes.length, 1);
  assertEquals(
    journal.notifications.find((n) => n.user_id === MEMBRE)?.title,
    "7 astreintes proposées en octobre",
  );
  assertEquals(
    journal.notifications.find((n) => n.user_id === AUTRE)?.title,
    "Astreinte proposée le 9 octobre, jour",
  );
});

Deno.test("un membre sans profil est signalé, sans faire tomber les autres", async () => {
  const { deps } = faussesDeps({ profils: [profil(MEMBRE)] });

  const resultat = await traiterEnvoi(
    deps,
    demande({
      recipients: [
        { user_id: MEMBRE, payload: { shifts: [{ date: "2026-10-12", slot: "night" }] } },
        { user_id: AUTRE, payload: {} },
      ],
    }),
  );

  assertEquals(resultat.recipients, 2);
  assertEquals(resultat.delivered, 1);
  assertEquals(resultat.failed, 1);
  assertEquals(resultat.ok, false);
  assertEquals(resultat.results[1].code, "profile_not_found");
});

// ---------------------------------------------------------------------------
// Lecture du corps de la requête
// ---------------------------------------------------------------------------

Deno.test("les deux formes du corps sont acceptées", () => {
  const court = lireDemande({
    type: "schedule_validated",
    user_ids: [MEMBRE, AUTRE],
    station_id: "aaaaaaaa-0000-4000-8000-000000000001",
    payload: { period: "2026-10" },
  });
  assert("demande" in court);
  assertEquals(court.demande.recipients.length, 2);
  assertEquals(court.demande.channels, null);

  const groupe = lireDemande({
    type: "assignment_proposed",
    recipients: [{ user_id: MEMBRE, payload: { shifts: [] } }],
    channels: ["push", "push", "inapp"],
  });
  assert("demande" in groupe);
  assertEquals(groupe.demande.channels, ["push", "inapp"]);
  assertEquals(groupe.demande.station_id, null);
});

Deno.test("un corps mal formé est refusé avec un code stable", () => {
  const cas: Array<[Record<string, unknown>, string]> = [
    [{ type: "inconnu", user_ids: [MEMBRE] }, "invalid_type"],
    [{ type: "schedule_validated" }, "invalid_recipients"],
    [{ type: "schedule_validated", user_ids: [] }, "invalid_recipients"],
    [{ type: "schedule_validated", recipients: [{}] }, "invalid_recipients"],
    [{ type: "schedule_validated", user_ids: [MEMBRE], channels: ["sms"] }, "invalid_channels"],
    [{ type: "schedule_validated", user_ids: [MEMBRE], channels: [] }, "invalid_channels"],
    // `/connexion` n'est pas un des quatre liens profonds : un push le portant
    // n'ouvrirait rien. Le canal est refusé plutôt que le lien livré mort.
    [{ type: "invitation", user_ids: [MEMBRE], channels: ["push"] }, "invalid_channels"],
  ];
  for (const [corps, code] of cas) {
    const lu = lireDemande(corps);
    assert("erreur" in lu, `${JSON.stringify(corps)} aurait dû être refusé`);
    assertEquals(lu.erreur.code, code);
  }
});

Deno.test("une invitation part par courriel, et seulement par courriel", () => {
  const courriel = lireDemande({ type: "invitation", user_ids: [MEMBRE], channels: ["email"] });
  assert("demande" in courriel);
  assertEquals(courriel.demande.channels, ["email"]);
});

Deno.test("la charge utile commune est fusionnée sous celle de chaque membre", async () => {
  const { deps, journal } = faussesDeps({ jetons: {} });

  await traiterEnvoi(
    deps,
    demande({
      type: "schedule_validated",
      payload: { period: "2026-10" },
      recipients: [{ user_id: MEMBRE, payload: {} }],
    }),
  );

  assertEquals(journal.notifications[0].title, "Planning d'octobre validé");
  assertEquals(
    (journal.notifications[0].data as Record<string, unknown>).route,
    "/schedule/2026-10",
  );
});

// ---------------------------------------------------------------------------
// Le mode « trace » d'un envoi abandonné (ticket 040)
// ---------------------------------------------------------------------------

Deno.test("une demande abandonnée n'écrit que la ligne interne, avec sa mention d'échec", async () => {
  // La demande de trace posée par `notify_trace_echec` (migration 0022) : même
  // type, mêmes destinataires, même charge utile, plus la marque. On lui donne
  // ici un appareil et des canaux généreux pour vérifier que rien ne part
  // malgré tout — c'est l'enchaînement qui décide, pas l'appelant.
  const { deps, journal } = faussesDeps({
    jetons: { [MEMBRE]: [{ token: "VIVANT", platform: "web" }] },
  });

  const resultat = await traiterEnvoi(
    deps,
    demande({
      channels: ["push", "email", "inapp"],
      payload: {
        delivery_failure: {
          outbox_id: "cccccccc-0000-4000-8000-000000000004",
          attempts: 5,
          error: "abandon après 5 tentatives sans réponse",
        },
      },
    }),
  );

  // Une seule ligne, sur le seul canal qui reste utile.
  assertEquals(journal.notifications.length, 1);
  assertEquals(journal.notifications[0].channel, "inapp");
  assertEquals(journal.pushEnvoyes.length, 0);
  assertEquals(journal.courriels.length, 0);

  // Elle est écrite en échec : c'est `error` non nulle que l'écran regarde pour
  // afficher « L'envoi a échoué, tu ne l'as peut-être pas reçue » (ticket 026).
  assertEquals(journal.notifications[0].delivered, false);
  assertEquals(journal.notifications[0].sent_at, null);
  assertStringIncludes(String(journal.notifications[0].error), "abandon après 5 tentatives");

  // Et surtout : le membre lit ce qu'il a failli ne jamais apprendre, dans les
  // mots habituels. Le français ne s'écrit pas une seconde fois en SQL.
  assertEquals(journal.notifications[0].title, "Astreinte proposée le 12 octobre, nuit");
  assertStringIncludes(journal.notifications[0].body, "12 octobre");
  assertEquals(
    (journal.notifications[0].data as Record<string, unknown>).route,
    "/proposals",
  );

  // La demande de trace, elle, a abouti : la file la clôt et ne la rejoue pas.
  assertEquals(resultat.ok, true);
  assertEquals(resultat.delivery_failure, true);
  assertEquals(resultat.delivered, 1);
});

Deno.test("la trace d'un envoi groupé garde une ligne par membre, avec ses créneaux", async () => {
  const { deps, journal } = faussesDeps({
    profils: [profil(MEMBRE), profil(AUTRE)],
    jetons: {},
  });

  await traiterEnvoi(
    deps,
    demande({
      type: "schedule_validated",
      payload: {
        period: "2026-10",
        delivery_failure: { error: "abandon après 5 tentatives sans réponse" },
      },
      recipients: [
        { user_id: MEMBRE, payload: { shifts: [{ date: "2026-10-03", slot: "day" }] } },
        { user_id: AUTRE, payload: { shifts: [{ date: "2026-10-09", slot: "night" }] } },
      ],
    }),
  );

  assertEquals(journal.notifications.length, 2);
  for (const ligne of journal.notifications) {
    assertEquals(ligne.channel, "inapp");
    assertEquals(ligne.delivered, false);
    assert(ligne.error !== null);
    assertEquals(ligne.title, "Planning d'octobre validé");
  }
  assertStringIncludes(journal.notifications[0].body, "3 octobre");
  assertStringIncludes(journal.notifications[1].body, "9 octobre");
});

Deno.test("une marque d'échec vide ou mal formée ne laisse jamais « error » vide", async () => {
  // `notifications.error` est le seul signal de l'écran : une marque présente
  // mais sans motif doit quand même renseigner la colonne, sinon la ligne
  // ressemble à un envoi réussi et la mention disparaît.
  const { deps, journal } = faussesDeps({ jetons: {} });

  await traiterEnvoi(deps, demande({ payload: { delivery_failure: {} } }));

  assertEquals(journal.notifications.length, 1);
  assertEquals(journal.notifications[0].error, "delivery_failure");

  // Une valeur qui n'est pas un objet n'est pas une marque : envoi ordinaire.
  const ordinaire = faussesDeps({ jetons: {} });
  await traiterEnvoi(
    ordinaire.deps,
    demande({ channels: ["inapp"], payload: { delivery_failure: "oui" } }),
  );
  assertEquals(ordinaire.journal.notifications[0].error, null);
  assertEquals(ordinaire.journal.notifications[0].delivered, true);
});
