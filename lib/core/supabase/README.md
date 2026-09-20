# core/supabase

Initialisation de `supabase_flutter` avec `Env.supabaseUrl` et `Env.supabaseAnonKey`, et
provider du client (`supabase_bootstrap.dart`, ticket 005).

`demarrerSupabase` ne lève jamais : elle rend `configurationAbsente` quand l'URL ou la clé
manquent, `echec` si le client refuse de se créer, `pret` sinon. Le routeur envoie les deux
premiers cas sur un écran qui l'explique.

Les erreurs d'authentification sont nommées dans `core/session/auth_erreur.dart`.

Jamais de clé service ici : toute écriture passe par RLS.
