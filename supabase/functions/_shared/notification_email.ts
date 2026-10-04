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
 * Le chemin est une variable d'environnement, comme `APP_INVITE_PATH` : la
 * stratégie d'URL de la PWA peut changer sans redéployer les fonctions.
 *
 * Depuis le ticket 046, la route est le chemin de l'adresse, **sans dièse** :
 * le fragment appartient au fournisseur d'authentification, qui y dépose ses
 * jetons.
 *
 * **La caserne voyage dans le lien** depuis le ticket 072 (décision 2 du
 * propriétaire) : `?station=<uuid>`. Un pompier de deux casernes qui touche le
 * lien d'un courriel de B alors que l'app est ouverte sur A doit arriver dans B.
 * Le chemin, lui, ne change pas d'un caractère — les liens publics de
 * `docs/WORKFLOWS.md § 8` restent ce qu'ils sont, et un client qui ignore le
 * paramètre lit le même chemin qu'avant (`destinationInterne` ne lit que les
 * segments). Un identifiant qui n'a pas la forme d'un uuid est omis plutôt que
 * recopié dans une adresse.
 */
export function lienApplication(route: string, stationId?: string | null): string {
  const base = (Deno.env.get("APP_BASE_URL") ?? "http://127.0.0.1:3000").replace(/\/+$/, "");
  const modele = Deno.env.get("APP_LINK_PATH") ?? "{route}";
  return base +
    modele.replace("{route}", avecCaserne(route.startsWith("/") ? route : `/${route}`, stationId));
}

const FORME_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** La route, plus `station=<uuid>` quand la caserne est connue et bien formée. */
export function avecCaserne(route: string, stationId?: string | null): string {
  if (!stationId || !FORME_UUID.test(stationId)) return route;
  const separateur = route.includes("?") ? "&" : "?";
  return `${route}${separateur}station=${stationId.toLowerCase()}`;
}

/** Le libellé du bouton, adapté à la destination. */
function libelleBouton(route: string): string {
  if (route.startsWith("/proposals")) return "Voir mes propositions";
  if (route.startsWith("/availability")) return "Saisir mes disponibilités";
  if (route.startsWith("/admin/schedule")) return "Ouvrir le suivi du planning";
  if (route.startsWith("/admin/subscription")) return "Gérer l'abonnement";
  if (route.startsWith("/admin/exchanges")) return "Ouvrir les échanges à valider";
  if (route.startsWith("/exchanges")) return "Voir mes échanges";
  if (route.startsWith("/schedule")) return "Voir le planning";
  return "Ouvrir Astreinte SP";
}

export function renderNotificationEmail(
  contenu: Contenu,
  options: { stationName?: string | null; stationId?: string | null } = {},
): CourrielNotification {
  const titre = escapeHtml(contenu.titre);
  const corps = escapeHtml(contenu.corps);
  const url = lienApplication(contenu.route, options.stationId);
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
