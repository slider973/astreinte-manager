// Clients Supabase des Edge Functions.
//
// Règle qui ne souffre pas d'exception : la clé de service ne quitte jamais le
// serveur. Elle sert à ouvrir le client administrateur ci-dessous et n'apparaît
// dans aucune réponse, aucun journal, aucun message d'erreur renvoyé au client.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "../../types/database.types.ts";

export type AdminClient = SupabaseClient<Database>;

export function env(name: string, fallback?: string): string {
  const value = Deno.env.get(name) ?? fallback;
  if (value === undefined) {
    throw new Error(`Variable d'environnement manquante : ${name}`);
  }
  return value;
}

/** Client `service_role` : contourne la RLS, réservé au code serveur. */
export function adminClient(): AdminClient {
  return createClient<Database>(
    env("SUPABASE_URL"),
    env("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

export type Caller = { id: string; email: string };

/**
 * Identité de l'appelant, vérifiée auprès de GoTrue à partir du jeton porteur.
 *
 * `verify_jwt = true` ne suffit pas : la clé anon est un JWT valide et publique,
 * donc n'importe qui franchit ce filtre. C'est cette fonction qui distingue un
 * utilisateur connecté d'un porteur de clé anon — et c'est elle, jamais le corps
 * de la requête, qui dit *qui* appelle.
 */
export async function caller(
  req: Request,
  admin: AdminClient,
): Promise<Caller | null> {
  const header = req.headers.get("Authorization") ?? "";
  const jwt = header.toLowerCase().startsWith("bearer ") ? header.slice(7).trim() : "";
  if (jwt === "") return null;

  const { data, error } = await admin.auth.getUser(jwt);
  if (error || !data.user || !data.user.email) return null;
  return { id: data.user.id, email: data.user.email };
}
