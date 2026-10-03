// Envoi de courriel, avec deux fournisseurs et un repli.
//
//   1. Resend, dès que RESEND_API_KEY est présente (projet hébergé) ;
//   2. sinon Mailpit, le serveur de courriel de la pile locale, joint par son API
//      HTTP (http://supabase_inbucket_pompier:8025/api/v1/send). Rien n'est envoyé
//      pour de vrai, tout est lisible sur http://127.0.0.1:54324 ;
//   3. sinon rien n'est envoyé : la fonction renvoie `sent: false` avec la raison.
//      L'invitation reste créée et renvoyable. Un courriel qui ne part pas est un
//      incident d'envoi, pas une raison de perdre l'invitation.
//
// Avant tout fournisseur : une adresse dont le domaine finit par `.invalid`
// (RFC 2606, RFC 6761 § 6.4) n'est jamais distribuable. Elle ne part pas, sans
// appel au fournisseur — un rebond par adresse fictive abîme la réputation du
// compte Resend, qui porte aussi les invitations (ticket 076 : les membres
// fictifs de la caserne de démonstration ont de telles adresses).
//
// Aucune clé n'est journalisée ni renvoyée.

export type Mail = {
  to: string;
  subject: string;
  html: string;
  text: string;
};

export type MailResult = {
  sent: boolean;
  provider: "resend" | "mailpit" | "none";
  error?: string;
};

const DEFAULT_FROM = "Astreinte SP <invitations@astreinte-sp.local>";
const DEFAULT_MAILPIT = "http://supabase_inbucket_pompier:8025";

/** « Nom <adresse> » → { name, email }, pour l'API de Mailpit. */
function splitFrom(from: string): { name: string; email: string } {
  const match = from.match(/^\s*(.*?)\s*<([^>]+)>\s*$/);
  if (match) return { name: match[1], email: match[2] };
  return { name: "", email: from.trim() };
}

async function sendWithResend(
  mail: Mail,
  from: string,
  apiKey: string,
): Promise<MailResult> {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [mail.to],
      subject: mail.subject,
      html: mail.html,
      text: mail.text,
    }),
  });

  if (!response.ok) {
    // Le corps de Resend peut contenir des détails, jamais la clé : on le garde.
    const body = await response.text();
    return {
      sent: false,
      provider: "resend",
      error: `resend ${response.status} ${body.slice(0, 300)}`,
    };
  }
  return { sent: true, provider: "resend" };
}

async function sendWithMailpit(
  mail: Mail,
  from: string,
  baseUrl: string,
): Promise<MailResult> {
  const sender = splitFrom(from);
  const response = await fetch(`${baseUrl.replace(/\/+$/, "")}/api/v1/send`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      From: { Email: sender.email, Name: sender.name },
      To: [{ Email: mail.to }],
      Subject: mail.subject,
      HTML: mail.html,
      Text: mail.text,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    return {
      sent: false,
      provider: "mailpit",
      error: `mailpit ${response.status} ${body.slice(0, 300)}`,
    };
  }
  return { sent: true, provider: "mailpit" };
}

/** Vrai si le domaine du destinataire est `invalid` ou finit par `.invalid`. */
export function adresseNonDistribuable(adresse: string): boolean {
  const arobase = adresse.lastIndexOf("@");
  const domaine = adresse.slice(arobase + 1).trim().toLowerCase().replace(/\.+$/, "");
  return domaine === "invalid" || domaine.endsWith(".invalid");
}

export async function sendMail(mail: Mail): Promise<MailResult> {
  if (adresseNonDistribuable(mail.to)) {
    return { sent: false, provider: "none", error: "adresse non distribuable (.invalid)" };
  }
  const from = Deno.env.get("MAIL_FROM") ?? DEFAULT_FROM;
  const resendKey = Deno.env.get("RESEND_API_KEY");
  const mailpitUrl = Deno.env.get("MAILPIT_URL") ?? DEFAULT_MAILPIT;

  try {
    if (resendKey && resendKey.trim() !== "") {
      return await sendWithResend(mail, from, resendKey.trim());
    }
    if (mailpitUrl && mailpitUrl.trim() !== "") {
      return await sendWithMailpit(mail, from, mailpitUrl.trim());
    }
    return {
      sent: false,
      provider: "none",
      error: "aucun fournisseur de courriel configuré",
    };
  } catch (cause) {
    return {
      sent: false,
      provider: resendKey ? "resend" : "mailpit",
      error: cause instanceof Error ? cause.message : String(cause),
    };
  }
}
