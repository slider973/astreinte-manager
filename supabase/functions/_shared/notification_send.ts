// L'enchaînement d'un envoi de notification, sans base ni réseau.
//
// Pourquoi ce fichier existe séparément de `send-notification/index.ts` : la CI
// démarre la pile sans `edge-runtime` ni `kong` (.github/workflows/ci.yml), donc
// aucune Edge Function n'y est joignable. Tout ce qui décide vit donc ici, derrière
// une poignée de dépendances injectées, et se teste en quelques millisecondes avec
// `deno test`. `index.ts` ne fait plus que brancher le vrai client Supabase, le
// vrai FCM et le vrai transporteur de courriel sur ces dépendances.
//
// L'ordre des opérations n'est pas négociable :
//
//   1. **la ligne interne d'abord**, avant tout envoi. C'est le centre de
//      notifications (ticket 026), et c'est la seule trace qui survit à une panne
//      de FCM comme de Resend. Une notification dont l'envoi échoue doit rester
//      lisible dans l'application ;
//   2. le push ensuite, appareil par appareil, avec suppression des jetons
//      définitivement rejetés ;
//   3. le courriel enfin, si le canal est demandé **ou** si le membre n'a aucun
//      appareil enregistré — le repli qui fait qu'un pompier sans téléphone
//      compatible apprend quand même qu'on lui propose une astreinte.
//
// Rien ne lève : chaque destinataire a son sort, et un destinataire en échec
// n'empêche pas les autres d'être servis.

import {
  type Canal,
  CANAUX_PAR_DEFAUT,
  type ChargeUtile,
  construireContenu,
  type Contenu,
  type Destinataire,
  etiquette,
  regrouper,
  type TypeNotification,
  TYPES_CRITIQUES,
} from "./notification_content.ts";
import type { ResultatPush } from "./fcm.ts";
import { lienApplication } from "./notification_email.ts";
import type { MailResult } from "./mailer.ts";

// ---------------------------------------------------------------------------
// Ce que l'appelant demande
// ---------------------------------------------------------------------------

export type DemandeEnvoi = {
  type: TypeNotification;
  station_id: string | null;
  /** Un objet par destinataire, avec sa charge utile propre. */
  recipients: Destinataire[];
  /** Charge utile commune, fusionnée sous celle de chaque destinataire. */
  payload: ChargeUtile;
  /** Canaux forcés. `null` ⇒ ceux du type (docs/WORKFLOWS.md § 8). */
  channels: Canal[] | null;
};

// ---------------------------------------------------------------------------
// Ce dont l'enchaînement a besoin
// ---------------------------------------------------------------------------

export type Profil = {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  /** `profiles.push_enabled` : les push **non critiques** sont-ils acceptés ? */
  push_enabled: boolean;
};

export type Jeton = { token: string; platform: string };

export type Caserne = { name: string; timezone: string };

export type LigneNotification = {
  station_id: string | null;
  user_id: string;
  type: TypeNotification;
  channel: Canal;
  title: string;
  body: string;
  data: Record<string, unknown>;
  sent_at: string | null;
  delivered: boolean | null;
  error: string | null;
};

export type Deps = {
  lireCaserne(stationId: string | null): Promise<Caserne | null>;
  lireProfils(userIds: string[]): Promise<Profil[]>;
  lireJetons(userIds: string[]): Promise<Map<string, Jeton[]>>;
  /** Insère une ligne `notifications` et rend son identifiant, ou `null`. */
  ecrireNotification(ligne: LigneNotification): Promise<string | null>;
  supprimerJetons(jetons: string[]): Promise<void>;
  envoyerPush(
    jetons: string[],
    message: {
      titre: string;
      corps: string;
      donnees: Record<string, string>;
      lien?: string;
      etiquette?: string;
    },
  ): Promise<ResultatPush>;
  envoyerCourriel(
    destinataire: string,
    contenu: Contenu,
    caserne: Caserne | null,
  ): Promise<MailResult>;
  maintenant(): Date;
};

// ---------------------------------------------------------------------------
// Ce que l'enchaînement rend
// ---------------------------------------------------------------------------

export type MotifSautPush =
  | "channel" // le push n'était pas demandé
  | "push_disabled" // profiles.push_enabled = false, type non critique
  | "no_token" // aucun appareil enregistré
  | "unavailable"; // FCM non configuré ou identifiants refusés

export type ResultatDestinataire = {
  user_id: string;
  /** Faux uniquement si rien n'a pu être fait pour ce membre. */
  ok: boolean;
  code?: string;
  title?: string;
  body?: string;
  route?: string;
  notification_id?: string | null;
  inapp?: boolean;
  push?: {
    attempted: number;
    delivered: number;
    removed_tokens: number;
    skipped?: MotifSautPush;
    error?: string;
  };
  email?: {
    sent: boolean;
    provider: string;
    fallback: boolean;
    error?: string;
  };
};

export type ResultatEnvoi = {
  ok: boolean;
  type: TypeNotification;
  recipients: number;
  delivered: number;
  failed: number;
  results: ResultatDestinataire[];
};

// ---------------------------------------------------------------------------
// L'enchaînement
// ---------------------------------------------------------------------------

export async function traiterEnvoi(
  deps: Deps,
  demande: DemandeEnvoi,
): Promise<ResultatEnvoi> {
  // Le regroupement d'abord : c'est lui qui fixe le nombre de notifications.
  // Une publication de planning arrive ici avec une entrée par créneau ; elle en
  // ressort avec une entrée par membre (docs/WORKFLOWS.md § 8).
  const destinataires = regrouper(
    demande.type,
    demande.recipients.map((d) => ({
      user_id: d.user_id,
      payload: { ...demande.payload, ...d.payload },
    })),
  );

  const ids = [...new Set(destinataires.map((d) => d.user_id))];
  const caserne = await deps.lireCaserne(demande.station_id);
  const profils = new Map((await deps.lireProfils(ids)).map((p) => [p.id, p]));
  const canaux = demande.channels ?? CANAUX_PAR_DEFAUT[demande.type];

  // Les jetons ne sont lus que si le push est au programme : un rappel J-1 par
  // courriel n'a aucune raison de parcourir `push_tokens`.
  const jetons = canaux.includes("push") ? await deps.lireJetons(ids) : new Map<string, Jeton[]>();

  const resultats: ResultatDestinataire[] = [];
  for (const destinataire of destinataires) {
    resultats.push(
      await servirUnDestinataire(deps, demande, destinataire, {
        caserne,
        profil: profils.get(destinataire.user_id) ?? null,
        jetons: jetons.get(destinataire.user_id) ?? [],
        canaux,
      }),
    );
  }

  const delivered = resultats.filter((r) => r.ok).length;
  return {
    ok: resultats.every((r) => r.ok),
    type: demande.type,
    recipients: resultats.length,
    delivered,
    failed: resultats.length - delivered,
    results: resultats,
  };
}

async function servirUnDestinataire(
  deps: Deps,
  demande: DemandeEnvoi,
  destinataire: Destinataire,
  contexte: {
    caserne: Caserne | null;
    profil: Profil | null;
    jetons: Jeton[];
    canaux: Canal[];
  },
): Promise<ResultatDestinataire> {
  const { caserne, profil, jetons, canaux } = contexte;

  // Sans profil, il n'y a personne à notifier : `notifications.user_id` référence
  // `profiles`, l'insertion échouerait de toute façon. On le dit franchement
  // plutôt que de faire semblant.
  if (!profil) {
    return { user_id: destinataire.user_id, ok: false, code: "profile_not_found" };
  }

  const contenu = construireContenu(demande.type, destinataire.payload, {
    stationName: caserne?.name,
    timezone: caserne?.timezone,
  });
  const maintenant = deps.maintenant().toISOString();

  const donnees: Record<string, unknown> = {
    route: contenu.route,
    type: demande.type,
  };
  if (demande.station_id) donnees.station_id = demande.station_id;
  const periode = destinataire.payload.period;
  if (typeof periode === "string") donnees.period = periode;

  const resultat: ResultatDestinataire = {
    user_id: profil.id,
    ok: true,
    title: contenu.titre,
    body: contenu.corps,
    route: contenu.route,
  };

  // 1. La ligne interne, avant tout envoi.
  let notificationId: string | null = null;
  if (canaux.includes("inapp")) {
    notificationId = await deps.ecrireNotification({
      station_id: demande.station_id,
      user_id: profil.id,
      type: demande.type,
      channel: "inapp",
      title: contenu.titre,
      body: contenu.corps,
      data: donnees,
      sent_at: maintenant,
      delivered: true,
      error: null,
    });
    // Écrite, ou pas. `ecrireNotification` rend `null` quand l'insertion a
    // échoué, et poser `inapp: true` sans regarder ferait compter le destinataire
    // comme servi, clore la demande en `sent`, et faire disparaître la
    // notification sans trace ni reprise — précisément ce que la file d'attente
    // existe pour rendre impossible.
    resultat.inapp = notificationId !== null;
    resultat.notification_id = notificationId;
  }

  // 2. Le push.
  let replisurCourriel = false;
  if (canaux.includes("push")) {
    const critique = TYPES_CRITIQUES.has(demande.type);

    if (!profil.push_enabled && !critique) {
      // Le réglage du membre, respecté sans repli courriel : « ne me préviens
      // pas » veut dire « ne me préviens pas », pas « préviens-moi autrement ».
      resultat.push = {
        attempted: 0,
        delivered: 0,
        removed_tokens: 0,
        skipped: "push_disabled",
      };
    } else if (jetons.length === 0) {
      // Aucun appareil : c'est le cas du repli par courriel.
      resultat.push = { attempted: 0, delivered: 0, removed_tokens: 0, skipped: "no_token" };
      replisurCourriel = true;
    } else {
      const envoi = await deps.envoyerPush(jetons.map((j) => j.token), {
        titre: contenu.titre,
        corps: contenu.corps,
        donnees: aplatir({ ...donnees, notification_id: notificationId }),
        // Adresse **complète**, pas le chemin : `webpush.fcm_options.link` est
        // validé comme une URL par l'API v1, et un chemin relatif ferait échouer
        // le message entier. `lienPubliable` (fcm.ts) l'écarte si l'origine n'est
        // pas en `https` — en local, le push part alors sans ce champ, et le
        // service worker retrouve la destination dans `data.route`.
        lien: lienApplication(contenu.route),
        etiquette: etiquette(demande.type, destinataire.payload),
      });

      // Les jetons définitivement rejetés partent. Un échec temporaire ne
      // supprime rien : l'appareil du pompier ne paie pas une panne de Google.
      if (envoi.jetonsMorts.length > 0) {
        await deps.supprimerJetons(envoi.jetonsMorts);
      }

      const erreurs = envoi.resultats.filter((r) => !r.ok).map((r) => r.error).filter(Boolean);
      await deps.ecrireNotification({
        station_id: demande.station_id,
        user_id: profil.id,
        type: demande.type,
        channel: "push",
        title: contenu.titre,
        body: contenu.corps,
        data: { ...donnees, tokens: envoi.tentes, delivered: envoi.delivres },
        sent_at: maintenant,
        delivered: envoi.delivres > 0,
        error: envoi.indisponible ??
          (erreurs.length > 0 ? erreurs.join(" | ").slice(0, 500) : null),
      });

      resultat.push = {
        attempted: envoi.tentes,
        delivered: envoi.delivres,
        removed_tokens: envoi.jetonsMorts.length,
        skipped: envoi.indisponible ? "unavailable" : undefined,
        error: envoi.indisponible ?? (erreurs.length > 0 ? String(erreurs[0]) : undefined),
      };

      // Push demandé, appareils connus, rien de délivré : le courriel prend le
      // relais. C'est le même raisonnement que l'absence de jeton — ce qui compte
      // est que le pompier soit prévenu, pas le chemin emprunté.
      if (envoi.delivres === 0) replisurCourriel = true;
    }
  }

  // 3. Le courriel.
  const courrielDemande = canaux.includes("email");
  if (courrielDemande || replisurCourriel) {
    const envoi = await deps.envoyerCourriel(profil.email, contenu, caserne);
    await deps.ecrireNotification({
      station_id: demande.station_id,
      user_id: profil.id,
      type: demande.type,
      channel: "email",
      title: contenu.titre,
      body: contenu.corps,
      data: { ...donnees, fallback: !courrielDemande },
      sent_at: envoi.sent ? maintenant : null,
      delivered: envoi.sent,
      error: envoi.error ?? null,
    });
    resultat.email = {
      sent: envoi.sent,
      provider: envoi.provider,
      fallback: !courrielDemande,
      error: envoi.error,
    };
  }

  // Un destinataire est servi dès qu'un canal a abouti. La ligne interne compte :
  // elle est vue au prochain lancement de l'application, et c'est mieux que rien.
  resultat.ok = Boolean(resultat.inapp) ||
    (resultat.push?.delivered ?? 0) > 0 ||
    (resultat.email?.sent ?? false);
  if (!resultat.ok) resultat.code = "no_channel_delivered";

  return resultat;
}

/** FCM n'accepte que des chaînes dans `data`. */
function aplatir(donnees: Record<string, unknown>): Record<string, string> {
  const sortie: Record<string, string> = {};
  for (const [cle, valeur] of Object.entries(donnees)) {
    if (valeur === null || valeur === undefined) continue;
    sortie[cle] = typeof valeur === "string" ? valeur : JSON.stringify(valeur);
  }
  return sortie;
}

// ---------------------------------------------------------------------------
// Lecture d'une demande venue du réseau
// ---------------------------------------------------------------------------

export type ErreurDemande = { code: string; message: string };

/**
 * Valide et normalise le corps d'une requête.
 *
 * Deux formes acceptées, décrites dans supabase/functions/README.md :
 *
 *   - `{ type, user_ids, station_id, payload, channels? }` — tout le monde reçoit
 *     la même chose, c'est la forme du ticket ;
 *   - `{ type, recipients: [{ user_id, payload }], station_id, payload?, channels? }`
 *     — une charge utile par membre, c'est la forme du regroupement.
 */
export function lireDemande(
  corps: Record<string, unknown>,
): { demande: DemandeEnvoi } | { erreur: ErreurDemande } {
  const type = corps.type;
  if (!estType(type)) {
    return { erreur: { code: "invalid_type", message: "Type de notification inconnu." } };
  }

  const stationId = typeof corps.station_id === "string" && corps.station_id.trim() !== ""
    ? corps.station_id.trim()
    : null;

  const payload = estObjet(corps.payload) ? corps.payload : {};

  let destinataires: Destinataire[] = [];
  if (Array.isArray(corps.recipients)) {
    for (const entree of corps.recipients) {
      if (!estObjet(entree)) {
        return {
          erreur: {
            code: "invalid_recipients",
            message: "Chaque destinataire doit être un objet { user_id, payload }.",
          },
        };
      }
      const userId = entree.user_id;
      if (typeof userId !== "string" || userId.trim() === "") {
        return {
          erreur: { code: "invalid_recipients", message: "Destinataire sans user_id." },
        };
      }
      destinataires.push({
        user_id: userId.trim(),
        payload: estObjet(entree.payload) ? entree.payload : {},
      });
    }
  } else if (Array.isArray(corps.user_ids)) {
    for (const id of corps.user_ids) {
      if (typeof id !== "string" || id.trim() === "") {
        return { erreur: { code: "invalid_recipients", message: "user_ids : uuid attendus." } };
      }
      destinataires.push({ user_id: id.trim(), payload: {} });
    }
  } else if (typeof corps.user_id === "string" && corps.user_id.trim() !== "") {
    destinataires = [{ user_id: corps.user_id.trim(), payload: {} }];
  }

  if (destinataires.length === 0) {
    return {
      erreur: {
        code: "invalid_recipients",
        message: "Donner user_ids (uuid[]) ou recipients ([{ user_id, payload }]).",
      },
    };
  }

  let channels: Canal[] | null = null;
  if (corps.channels !== undefined && corps.channels !== null) {
    if (!Array.isArray(corps.channels)) {
      return { erreur: { code: "invalid_channels", message: "channels : tableau attendu." } };
    }
    const lus: Canal[] = [];
    for (const canal of corps.channels) {
      if (canal !== "push" && canal !== "email" && canal !== "inapp") {
        return {
          erreur: {
            code: "invalid_channels",
            message: "Canaux acceptés : push, email, inapp.",
          },
        };
      }
      if (!lus.includes(canal)) lus.push(canal);
    }
    if (lus.length === 0) {
      return { erreur: { code: "invalid_channels", message: "Au moins un canal est attendu." } };
    }
    // `invitation` porte `/connexion`, qui n'est pas un des quatre liens profonds
    // de docs/WORKFLOWS.md § 8 : le client le rejette. Un push le portant
    // n'ouvrirait rien. Plutôt que de livrer un lien mort, on refuse le canal —
    // l'appelant s'en aperçoit au développement, pas le pompier sur le terrain.
    if (type === "invitation" && lus.includes("push")) {
      return {
        erreur: {
          code: "invalid_channels",
          message:
            "Une invitation ne part que par courriel : elle n'a pas de destination dans l'application.",
        },
      };
    }
    channels = lus;
  }

  return {
    demande: { type, station_id: stationId, recipients: destinataires, payload, channels },
  };
}

function estObjet(valeur: unknown): valeur is Record<string, unknown> {
  return typeof valeur === "object" && valeur !== null && !Array.isArray(valeur);
}

function estType(valeur: unknown): valeur is TypeNotification {
  return typeof valeur === "string" && valeur in CANAUX_PAR_DEFAUT;
}
