// Le classement des erreurs FCM et la forme du message (ticket 025).
//
// Sans clés Firebase, rien ne part pour de vrai : le transport est remplacé par
// un faux. Ce qui est vérifié ici est précisément ce qui ne se voit pas à l'œil
// nu et qui coûte cher quand c'est faux — un jeton supprimé à tort débranche un
// pompier jusqu'à ce qu'il rouvre l'application ; un jeton gardé à tort encombre
// la table pour toujours.

import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  classerErreurFcm,
  corpsMessage,
  envoyerPush,
  lienPubliable,
  oublierJetonOAuth,
  type Transport,
} from "../_shared/fcm.ts";

/**
 * Un compte de service jetable, avec une vraie paire RSA engendrée à la volée.
 *
 * Une fausse clé ne suffirait pas : `jetonOAuth` la passe à WebCrypto, et un PEM
 * illisible ferait échouer l'import avant le premier appel réseau — le test
 * passerait au vert sans avoir rien vérifié du chemin d'envoi.
 */
async function compteJetable() {
  const paire = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", paire.privateKey));
  let binaire = "";
  for (const octet of pkcs8) binaire += String.fromCharCode(octet);
  const base64 = btoa(binaire).replace(/(.{64})/g, "$1\n");
  return {
    project_id: "astreinte-sp-test",
    client_email: "essai@astreinte-sp-test.iam.gserviceaccount.com",
    private_key: `-----BEGIN PRIVATE KEY-----\n${base64}\n-----END PRIVATE KEY-----\n`,
  };
}

/** Corps que FCM renvoie pour un jeton qui n'existe plus. */
const UNREGISTERED = JSON.stringify({
  error: {
    code: 404,
    message: "Requested entity was not found.",
    status: "NOT_FOUND",
    details: [{
      "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
      errorCode: "UNREGISTERED",
    }],
  },
});

/** Corps que FCM renvoie pour un jeton mal formé. */
const JETON_INVALIDE = JSON.stringify({
  error: {
    code: 400,
    message: "The registration token is not a valid FCM registration token",
    status: "INVALID_ARGUMENT",
    details: [{
      "@type": "type.googleapis.com/google.rpc.BadRequest",
      fieldViolations: [{ field: "message.token", description: "Invalid registration token" }],
    }],
  },
});

/** Corps que FCM renvoie quand c'est *notre* message qui est mal formé. */
const MESSAGE_INVALIDE = JSON.stringify({
  error: {
    code: 400,
    message: "Invalid value at 'message.android.ttl'",
    status: "INVALID_ARGUMENT",
  },
});

Deno.test("un jeton inconnu de FCM est définitivement rejeté", () => {
  assertEquals(classerErreurFcm(404, UNREGISTERED), "permanent");
});

Deno.test("un jeton mal formé est définitivement rejeté", () => {
  assertEquals(classerErreurFcm(400, JETON_INVALIDE), "permanent");
});

Deno.test("un jeton émis pour un autre projet Firebase est définitivement rejeté", () => {
  assertEquals(
    classerErreurFcm(
      403,
      JSON.stringify({ error: { details: [{ errorCode: "SENDER_ID_MISMATCH" }] } }),
    ),
    "permanent",
  );
});

Deno.test("un 400 qui accuse notre message, pas le jeton, reste temporaire", () => {
  // La règle qui évite la catastrophe : une régression dans le corps du message
  // produirait un 400 sur *tous* les jetons. Les supprimer déconnecterait la
  // caserne entière pour un bogue de notre côté.
  assertEquals(classerErreurFcm(400, MESSAGE_INVALIDE), "temporaire");
});

Deno.test("les pannes et les limites de débit ne coûtent aucun jeton", () => {
  for (const statut of [401, 403, 429, 500, 502, 503]) {
    assertEquals(
      classerErreurFcm(statut, "{}"),
      "temporaire",
      `statut ${statut} classé permanent à tort`,
    );
  }
});

Deno.test("un corps vide ou illisible ne fait supprimer aucun jeton", () => {
  assertEquals(classerErreurFcm(400, ""), "temporaire");
  assertEquals(classerErreurFcm(418, "<html>"), "temporaire");
});

type CorpsFcm = {
  message: {
    token: string;
    notification: { title: string; body: string };
    data: Record<string, string>;
    webpush: { fcm_options?: { link: string } };
  };
};

Deno.test("le message porte les blocs notification ET data attendus par le client", () => {
  const corps = corpsMessage("JETON", {
    titre: "Astreinte proposée le 12 octobre, nuit",
    corps: "CIS Saint-Martin te propose une astreinte.",
    donnees: { route: "/proposals", type: "assignment_proposed" },
    lien: "https://app.astreinte-sp.fr/#/proposals",
    etiquette: "assignment_proposed:2026-10",
  }) as CorpsFcm;

  assertEquals(corps.message.token, "JETON");
  // Premier plan : messagerie_push.dart lit notification.title / notification.body.
  assertEquals(corps.message.notification.title, "Astreinte proposée le 12 octobre, nuit");
  // Arrière-plan « data only » : firebase-messaging-sw.js lit data.title / data.body.
  assertEquals(corps.message.data.title, "Astreinte proposée le 12 octobre, nuit");
  assertEquals(corps.message.data.route, "/proposals");
  assertEquals(corps.message.data.tag, "assignment_proposed:2026-10");
  // Le lien du message est une adresse complète, jamais le chemin interne.
  assertEquals(corps.message.webpush.fcm_options?.link, "https://app.astreinte-sp.fr/#/proposals");
});

Deno.test("seule une adresse complète en https est acceptée comme lien", () => {
  assert(lienPubliable("https://app.astreinte-sp.fr/#/proposals"));
  // Le chemin interne : c'est lui qui aurait fait échouer tous les messages.
  assert(!lienPubliable("/proposals"));
  // La pile locale : `webpush.fcm_options.link` impose https.
  assert(!lienPubliable("http://127.0.0.1:3000/#/proposals"));
  assert(!lienPubliable(""));
  assert(!lienPubliable(undefined));
  assert(!lienPubliable("javascript:alert(1)"));
});

Deno.test("un lien inutilisable est omis, pas envoyé — le message part quand même", () => {
  // Sans ce filtre, l'API v1 renverrait un 400 INVALID_ARGUMENT sur *chaque*
  // jeton. `classerErreurFcm` le rangerait en incident temporaire — donc aucun
  // jeton perdu, mais aucun push jamais délivré et tout en courriel de secours.
  // Un silence parfait, invisible tant que les clés Firebase manquent.
  const relatif = corpsMessage("JETON", {
    titre: "t",
    corps: "c",
    donnees: { route: "/proposals" },
    lien: "/proposals",
  }) as CorpsFcm;
  assertEquals(relatif.message.webpush.fcm_options, undefined);
  // La destination, elle, voyage toujours : le service worker lit `data.route`.
  assertEquals(relatif.message.data.route, "/proposals");

  const local = corpsMessage("JETON", {
    titre: "t",
    corps: "c",
    donnees: {},
    lien: "http://127.0.0.1:3000/#/proposals",
  }) as CorpsFcm;
  assertEquals(local.message.webpush.fcm_options, undefined);
});

Deno.test("sans compte de service, le push est indisponible et non en échec", async () => {
  const resultat = await envoyerPush(["JETON"], {
    titre: "t",
    corps: "c",
    donnees: {},
  }, { compte: null });

  assertEquals(resultat.tentes, 0);
  assertEquals(resultat.jetonsMorts, []);
  assert(resultat.indisponible !== undefined);
});

Deno.test("un envoi mixte supprime le jeton mort et garde l'autre", async () => {
  oublierJetonOAuth();

  const transport: Transport = (url, init) => {
    if (url.startsWith("https://oauth2.googleapis.com/")) {
      return Promise.resolve(
        new Response(JSON.stringify({ access_token: "faux-jeton", expires_in: 3600 }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    }
    const corps = JSON.parse(String(init.body)) as { message: { token: string } };
    switch (corps.message.token) {
      case "MORT":
        return Promise.resolve(new Response(UNREGISTERED, { status: 404 }));
      case "PANNE":
        return Promise.resolve(new Response("{}", { status: 503 }));
      default:
        return Promise.resolve(new Response(JSON.stringify({ name: "projects/x/messages/1" })));
    }
  };

  const resultat = await envoyerPush(
    ["VIVANT", "MORT", "PANNE"],
    { titre: "t", corps: "c", donnees: {} },
    { compte: await compteJetable(), transport },
  );

  assertEquals(resultat.tentes, 3);
  assertEquals(resultat.delivres, 1);
  assertEquals(resultat.jetonsMorts, ["MORT"]);
  assertEquals(resultat.resultats.find((r) => r.token === "PANNE")?.verdict, "temporaire");

  oublierJetonOAuth();
});

Deno.test("des identifiants refusés n'emportent aucun jeton", async () => {
  oublierJetonOAuth();

  const transport: Transport = (url) => {
    if (url.startsWith("https://oauth2.googleapis.com/")) {
      return Promise.resolve(new Response('{"error":"invalid_grant"}', { status: 400 }));
    }
    throw new Error("l'envoi ne doit pas être tenté sans jeton d'accès");
  };

  const resultat = await envoyerPush(
    ["VIVANT"],
    { titre: "t", corps: "c", donnees: {} },
    { compte: await compteJetable(), transport },
  );

  assertEquals(resultat.tentes, 0);
  assertEquals(resultat.jetonsMorts, []);
  assert(resultat.indisponible?.startsWith("oauth 400"));

  oublierJetonOAuth();
});
