// Gabarit du courriel d'une notification, en français.
//
// Même mise en forme, même palette et même tutoiement que
// `_shared/invitation_email.ts` et `supabase/templates/magic_link.html` : pour le
// pompier, tout vient du même produit.
//
// Le courriel ne redit pas la notification, il la porte : le titre devient l'objet
// et le titre du message, le corps devient le paragraphe, et le lien profond
// devient le bouton. Un seul texte à écrire, dans
// `_shared/notification_content.ts`, et trois canaux qui s'en servent.

import type { Contenu } from "./notification_content.ts";

export type CourrielNotification = {
  subject: string;
  html: string;
  text: string;
};

function escapeHtml(valeur: string): string {
  return valeur
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

/**
 * L'adresse d'une destination de l'application.
 *
 * Le chemin est une variable d'environnement, comme `APP_INVITE_PATH` : la PWA
 * sert ses routes derrière un dièse (stratégie par défaut de go_router), et ce
 * choix peut changer sans redéployer les fonctions.
 */
export function lienApplication(route: string): string {
  const base = (Deno.env.get("APP_BASE_URL") ?? "http://127.0.0.1:3000").replace(/\/+$/, "");
  const modele = Deno.env.get("APP_LINK_PATH") ?? "/#{route}";
  return base + modele.replace("{route}", route.startsWith("/") ? route : `/${route}`);
}

/** Le libellé du bouton, adapté à la destination. */
function libelleBouton(route: string): string {
  if (route.startsWith("/proposals")) return "Voir mes propositions";
  if (route.startsWith("/availability")) return "Saisir mes disponibilités";
  if (route.startsWith("/admin/schedule")) return "Ouvrir le suivi du planning";
  if (route.startsWith("/schedule")) return "Voir le planning";
  return "Ouvrir Astreinte SP";
}

export function renderNotificationEmail(
  contenu: Contenu,
  options: { stationName?: string | null } = {},
): CourrielNotification {
  const titre = escapeHtml(contenu.titre);
  const corps = escapeHtml(contenu.corps);
  const url = lienApplication(contenu.route);
  const urlEchappee = escapeHtml(url);
  const bouton = escapeHtml(libelleBouton(contenu.route));
  const caserne = options.stationName?.trim() ? escapeHtml(options.stationName.trim()) : null;

  const html = `<!doctype html>
<html lang="fr">
  <head>
    <meta charset="utf-8" />
    <title>${titre}</title>
  </head>
  <body style="margin:0;padding:24px;background:#F1F4F6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#131C23;">
    <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="max-width:480px;margin:0 auto;background:#FFFFFF;border:1px solid #C3CDD3;border-radius:8px;">
      <tr>
        <td style="padding:24px;">
          <h1 style="margin:0 0 8px;font-size:22px;line-height:28px;font-weight:700;">${titre}</h1>
          <p style="margin:0 0 24px;font-size:16px;line-height:24px;color:#45535C;">${corps}</p>

          <p style="margin:0 0 24px;">
            <a href="${urlEchappee}" style="display:inline-block;padding:14px 20px;background:#16212A;color:#FFFFFF;border-radius:8px;font-size:16px;line-height:24px;font-weight:600;text-decoration:none;">
              ${bouton}
            </a>
          </p>

          <p style="margin:0 0 8px;font-size:14px;line-height:20px;color:#45535C;">
            Le bouton ne fonctionne pas&nbsp;? Copie ce lien dans ton navigateur&nbsp;:
          </p>
          <p style="margin:0;font-size:13px;line-height:18px;word-break:break-all;">
            <a href="${urlEchappee}" style="color:#16212A;">${urlEchappee}</a>
          </p>
        </td>
      </tr>
    </table>

    <p style="max-width:480px;margin:16px auto 0;font-size:13px;line-height:18px;color:#45535C;text-align:center;">
      ${caserne ? `${caserne} — ` : ""}Astreinte SP, la gestion des astreintes de ta caserne.
    </p>
  </body>
</html>`;

  const text = [
    contenu.titre,
    "",
    contenu.corps,
    "",
    `${libelleBouton(contenu.route)} : ${url}`,
    "",
    `${
      options.stationName?.trim() ? `${options.stationName.trim()} — ` : ""
    }Astreinte SP, la gestion des astreintes de ta caserne.`,
  ].join("\n");

  return { subject: contenu.titre, html, text };
}
