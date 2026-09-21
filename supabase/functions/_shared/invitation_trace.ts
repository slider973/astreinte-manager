// Ce qu'on écrit sur l'invitation après avoir tenté l'envoi du courriel.
// Migration 0035, ticket 048 — colonnes `invitations.email_sent_at` / `email_error`.
//
// Pourquoi une fonction pure et pas trois lignes dans `invite-member` : la règle
// tient en deux phrases, mais chacune corrige un mensonge possible de l'écran
// « Invitations en attente », et une règle qui ment se teste.
//
//   - un envoi réussi pose la date **et efface le motif d'échec précédent** : une
//     invitation partie ne doit pas continuer à afficher l'échec d'avant-hier ;
//   - un échec pose le motif **sans toucher à la date** : une invitation partie le
//     12 dont le renvoi du 21 a échoué garde ses deux faits, qui ne se
//     contredisent pas.
//
// Et ce qu'on n'écrit jamais : « pas envoyé » par défaut. Les deux colonnes nulles
// veulent dire « on ne sait pas », c'est l'état des invitations antérieures à la
// migration, et le confondre avec un échec serait le défaut que ce ticket corrige.

import type { MailResult } from "./mailer.ts";

/** Les colonnes à écrire. Une clé absente est une colonne qu'on ne touche pas. */
export type TraceEnvoi = {
  email_sent_at?: string;
  email_error: string | null;
};

/**
 * Le motif d'échec est borné : le mailer tronque déjà le corps rendu par le
 * fournisseur à 300 caractères, et ce qui sert au diagnostic tient dans la
 * première phrase. La colonne est en `text`, la borne est ici, comme celle des
 * noms importés est dans `create_invitation`.
 */
export const MOTIF_MAX = 300;

export function traceEnvoi(
  envoi: MailResult,
  maintenant: Date = new Date(),
): TraceEnvoi {
  if (envoi.sent) {
    return { email_sent_at: maintenant.toISOString(), email_error: null };
  }
  // `sendMail` renseigne toujours la raison d'un échec ; le repli couvre un
  // fournisseur futur qui l'oublierait, plutôt que d'écrire un motif vide, qui
  // ressemblerait à « on ne sait pas » alors qu'on sait que ce n'est pas parti.
  const motif = (envoi.error ?? "").trim() === ""
    ? `envoi impossible (${envoi.provider})`
    : envoi.error!.trim();
  return { email_error: motif.slice(0, MOTIF_MAX) };
}
