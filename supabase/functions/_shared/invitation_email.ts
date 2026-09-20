// Gabarit du courriel d'invitation, en français.
//
// Pourquoi ici et non dans supabase/templates/ avec magic_link.html : ce dernier est
// rendu par GoTrue, qui ne connaît que ses propres variables ({{ .Token }},
// {{ .ConfirmationURL }}). Le courriel d'invitation est rendu et envoyé par cette
// Edge Function, avec des données qui viennent de la base (caserne, inviteur, date
// d'expiration). Il reprend volontairement la mise en forme, la palette et le
// tutoiement de supabase/templates/magic_link.html : pour l'invité, les deux messages
// viennent du même produit.

export type InvitationEmailData = {
  stationName: string;
  inviterName: string;
  inviterEmail: string;
  inviteUrl: string;
  expiresAt: string; // ISO 8601
  role: "member" | "admin";
  resent: boolean;
};

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

/** « 4 octobre 2026 », dans le fuseau de Paris. */
function formatDate(iso: string): string {
  try {
    return new Intl.DateTimeFormat("fr-FR", {
      day: "numeric",
      month: "long",
      year: "numeric",
      timeZone: "Europe/Paris",
    }).format(new Date(iso));
  } catch {
    return iso;
  }
}

export function renderInvitationEmail(data: InvitationEmailData): {
  subject: string;
  html: string;
  text: string;
} {
  const station = escapeHtml(data.stationName);
  const inviter = escapeHtml(data.inviterName.trim() || data.inviterEmail);
  const inviterEmail = escapeHtml(data.inviterEmail);
  const url = escapeHtml(data.inviteUrl);
  const echeance = formatDate(data.expiresAt);
  const roleLabel = data.role === "admin" ? "comme administrateur" : "comme membre";

  const subject = data.resent
    ? `Rappel : rejoins ${data.stationName} sur Astreinte SP`
    : `${data.stationName} t'invite sur Astreinte SP`;

  const html = `<!doctype html>
<html lang="fr">
  <head>
    <meta charset="utf-8" />
    <title>${escapeHtml(subject)}</title>
  </head>
  <body style="margin:0;padding:24px;background:#F1F4F6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#131C23;">
    <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="max-width:480px;margin:0 auto;background:#FFFFFF;border:1px solid #C3CDD3;border-radius:8px;">
      <tr>
        <td style="padding:24px;">
          <h1 style="margin:0 0 8px;font-size:22px;line-height:28px;font-weight:700;">Rejoins ${station}</h1>
          <p style="margin:0 0 24px;font-size:16px;line-height:24px;color:#45535C;">
            ${inviter} t'invite ${roleLabel} sur Astreinte SP, l'application qui gère les
            astreintes de la caserne : tu y déclares tes disponibilités du mois et tu y
            reçois les créneaux qui te sont proposés.
          </p>

          <p style="margin:0 0 24px;">
            <a href="${url}" style="display:inline-block;padding:14px 20px;background:#16212A;color:#FFFFFF;border-radius:8px;font-size:16px;line-height:24px;font-weight:600;text-decoration:none;">
              Rejoindre ${station}
            </a>
          </p>

          <p style="margin:0 0 24px;font-size:16px;line-height:24px;color:#45535C;">
            Tu recevras un code à six chiffres pour ouvrir ta session : pas de mot de passe
            à retenir. Cette invitation est valable jusqu'au <strong style="color:#131C23;">${echeance}</strong>.
          </p>

          <p style="margin:0 0 8px;font-size:14px;line-height:20px;color:#45535C;">
            Le bouton ne fonctionne pas&nbsp;? Copie ce lien dans ton navigateur&nbsp;:
          </p>
          <p style="margin:0 0 24px;font-size:13px;line-height:18px;word-break:break-all;">
            <a href="${url}" style="color:#16212A;">${url}</a>
          </p>

          <p style="margin:0;font-size:14px;line-height:20px;color:#45535C;">
            Tu n'attendais rien d'Astreinte SP&nbsp;? Ignore ce message, ou réponds à
            <a href="mailto:${inviterEmail}" style="color:#45535C;">${inviterEmail}</a>.
          </p>
        </td>
      </tr>
    </table>

    <p style="max-width:480px;margin:16px auto 0;font-size:13px;line-height:18px;color:#45535C;text-align:center;">
      Astreinte SP — la gestion des astreintes de ta caserne.
    </p>
  </body>
</html>`;

  const text = [
    `Rejoins ${data.stationName}`,
    "",
    `${data.inviterName.trim() || data.inviterEmail} t'invite ${roleLabel} sur Astreinte SP,`,
    "l'application qui gère les astreintes de la caserne.",
    "",
    `Rejoindre ${data.stationName} : ${data.inviteUrl}`,
    "",
    `Tu recevras un code à six chiffres pour ouvrir ta session.`,
    `Cette invitation est valable jusqu'au ${echeance}.`,
    "",
    `Tu n'attendais rien d'Astreinte SP ? Ignore ce message, ou réponds à ${data.inviterEmail}.`,
    "",
    "Astreinte SP — la gestion des astreintes de ta caserne.",
  ].join("\n");

  return { subject, html, text };
}

/**
 * Lien d'invitation. Le chemin est une variable d'environnement : la PWA peut
 * basculer entre `/invite/{token}` et `/#/invite/{token}` selon la stratégie
 * d'URL retenue côté go_router, sans redéployer la fonction.
 */
export function invitationUrl(token: string): string {
  const base = (Deno.env.get("APP_BASE_URL") ?? "http://127.0.0.1:3000")
    .replace(/\/+$/, "");
  const path = Deno.env.get("APP_INVITE_PATH") ?? "/#/invite/{token}";
  return base + path.replace("{token}", encodeURIComponent(token));
}
