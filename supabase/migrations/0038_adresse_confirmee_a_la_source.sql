-- 0038 — L'adresse confirmée se lit à la source, pas dans les métadonnées. Ticket 058.
-- Référence : docs/SCHEMA.md sections 3 et 10 ; migration 0036 (ticket 051).
--
-- Relevé par la revue du ticket 051. `my_pending_invitations()` décidait si
-- l'adresse de la session était vérifiée en lisant une revendication du jeton :
-- `email_verified` au premier niveau, sinon `user_metadata.email_verified`, et
-- « vrai » par défaut. Mesuré sur ce projet, GoTrue ne pose pas la première pour
-- un compte né de `invite-member` : c'est donc `user_metadata` qui tranchait. Or
-- `user_metadata` n'est pas une autorité — le titulaire l'écrit lui-même par
-- `auth.updateUser({ data: … })`. Aujourd'hui ce n'était qu'un auto-blocage (se
-- déclarer non vérifié pour ne plus voir ses invitations), jamais une escalade ;
-- mais une fonction `security definer` a accès à l'autorité réelle, et n'a
-- aucune raison de consulter autre chose.
--
-- L'autorité réelle : `auth.users.email_confirmed_at`. Aucune API ouverte à
-- l'utilisateur ne l'écrit ; GoTrue la pose quand l'adresse est prouvée (code à
-- six chiffres, lien du courriel), et l'API d'administration quand on lui passe
-- `email_confirm: true` — ce que fait `invite-member` à la création du compte :
-- c'est alors l'administrateur de la caserne qui se porte garant de l'adresse,
-- et la session, elle, n'existe qu'après un code reçu dans cette boîte.
--
-- Ce qui change, et rien d'autre :
--
--   my_pending_invitations()    — la lecture des revendications est remplacée
--                                 par « la ligne `auth.users` de `auth.uid()` a
--                                 une adresse confirmée ». Pas de ligne, pas de
--                                 confirmation, pas de session : zéro ligne,
--                                 jamais une exception ;
--   accept_invitation_by_id()   — même contrôle, en tête, sur `p_user_id`. La
--                                 fonction est réservée à `service_role` : elle
--                                 est appelée par l'Edge Function
--                                 accept-invitation, avec la clé de service, et
--                                 `auth.uid()` y est nul. L'utilisateur de la
--                                 session est `p_user_id`, que l'Edge Function tire
--                                 de `auth.getUser(jwt)` et jamais du corps de la
--                                 requête. Un compte non confirmé reçoit
--                                 `email_mismatch`, exactement la réponse d'un
--                                 identifiant inconnu : pas de quatrième cas
--                                 discernable, pas d'oracle.
--
-- Signatures, `security definer`, `search_path` figé (`public, pg_temp`),
-- volatilité, droits d'exécution : inchangés. `create or replace` conserve l'ACL
-- des deux fonctions ; les `revoke` / `grant` de 0036 sont néanmoins rejoués en
-- fin de fichier, pour que ce fichier se lise seul.
--
-- ---------------------------------------------------------------------------
-- Pourquoi ce contrôle suffit, et ce qui le rendrait insuffisant
--
-- Le contrôle porte sur « l'adresse de ce compte est confirmée », pas sur « ce
-- compte est né d'une invitation » ni sur « cette session a lu la boîte ». Il
-- est sûr **parce que** personne ne peut obtenir un compte confirmé pour une
-- adresse qu'il ne contrôle pas, et cela ne tient pas dans ce fichier : cela
-- tient dans `supabase/config.toml`.
--
--   [auth] enable_signup = false
--       Seule l'Edge Function `invite-member`, avec la clé de service, fait
--       naître un compte. Un compte confirmé existe donc parce qu'un
--       administrateur a invité cette adresse, et on ne s'y connecte qu'avec le
--       code à six chiffres envoyé à cette adresse.
--
--   [auth] enable_anonymous_sign_ins = false
--       Aucune session sans adresse. Une session anonyme sortirait de toute
--       façon sur la comparaison d'adresse (elle n'en a pas) et sur
--       `email_confirmed_at` (nul) ; mais un compte anonyme peut ensuite se
--       donner une adresse (`updateUser({ email })`), et c'est une porte de
--       création de comptes de plus qu'on n'a pas à raisonner.
--
-- **Ce qui se rouvrirait si l'inscription libre était activée.** `signUp`
-- avec un mot de passe crée un compte à n'importe quelle adresse, et la
-- confirmation dépend alors d'un seul réglage, `[auth.email]
-- enable_confirmations`. À faux — la valeur du bloc de base, donc de la pile
-- locale —, GoTrue confirme l'adresse d'office : un inconnu pourrait ouvrir un
-- compte à l'adresse d'un pompier invité, être « confirmé » sans avoir jamais
-- lu cette boîte, voir son invitation et l'accepter par identifiant. À vrai —
-- la valeur de `[remotes.production.auth.email]` —, il resterait bloqué au
-- lien de confirmation, et c'est la **seule** serrure qui resterait. La
-- production en a deux aujourd'hui ; ouvrir l'inscription en retirerait une,
-- sans bruit, et rien dans ce fichier ne le verrait.
--
-- C'est pourquoi `scripts/verifier_production.sh` (section 4) fait désormais
-- un écart nommé d'une inscription libre ou d'une connexion anonyme activée en
-- production, lues dans `GET /v1/projects/{ref}/config/auth` (`disable_signup`,
-- `external_anonymous_users_enabled`) — et ne se contente plus de la
-- comparaison générale de `config diff`.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- my_pending_invitations — tout le reste est la définition de 0036, à l'identique.
-- ---------------------------------------------------------------------------
create or replace function my_pending_invitations()
returns table (
  id              uuid,
  station_name    text,
  invited_by_name text,
  expires_at      timestamptz,
  status          text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    i.id,
    s.name,
    -- Recomposé côté serveur, comme le fait déjà `accept_invitation` dans son
    -- objet `inviter`. Un profil sans nom rend `null` : l'écran omet la ligne,
    -- il n'affiche pas une adresse à la place.
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    i.expires_at,
    case when i.expires_at <= now() then 'expired' else 'pending' end
  from invitations i
  join stations s on s.id = i.station_id
  left join profiles p on p.id = i.invited_by
  where i.accepted_at is null
    -- `lower(email)` : la même comparaison que l'index partiel
    -- `invitations_pending_uniq`, donc la même notion d'« adresse déjà invitée ».
    and lower(i.email) = lower(nullif(btrim(coalesce(auth.jwt() ->> 'email', '')), ''))
    -- L'adresse de la session est confirmée **à la source**. Ni la revendication
    -- `email_verified`, ni `user_metadata` : le titulaire écrit la seconde, et la
    -- première n'est pas posée par GoTrue sur ce projet. `auth.uid()` nul (pas de
    -- session) : aucune ligne ne correspond, zéro ligne.
    and exists (
      select 1
      from auth.users u
      where u.id = auth.uid()
        and u.email_confirmed_at is not null
    )
  order by i.expires_at desc
  limit 10;
$$;

comment on function my_pending_invitations() is
  'Les invitations en attente adressées à l''adresse de la session, si auth.users.email_confirmed_at est posé : id, caserne, invitant, échéance, statut. Sans paramètre, sans jeton, zéro ligne à qui n''a rien.';

-- ---------------------------------------------------------------------------
-- accept_invitation_by_id — tout le reste est la définition de 0036, à l'identique.
-- ---------------------------------------------------------------------------
create or replace function accept_invitation_by_id(
  p_invitation uuid,
  p_user_id    uuid,
  p_email      text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_token text;
begin
  if p_invitation is null or v_email = '' then
    return jsonb_build_object('ok', false, 'code', 'email_mismatch');
  end if;

  -- L'adresse du compte est confirmée à la source, quelles que soient ses
  -- métadonnées. Même réponse qu'un identifiant inconnu : rien à apprendre.
  if not exists (
    select 1
    from auth.users u
    where u.id = p_user_id
      and u.email_confirmed_at is not null
  ) then
    return jsonb_build_object('ok', false, 'code', 'email_mismatch');
  end if;

  select i.token into v_token
  from invitations i
  where i.id = p_invitation and lower(i.email) = v_email;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'email_mismatch');
  end if;

  return accept_invitation(v_token, p_user_id, v_email);
end;
$$;

comment on function accept_invitation_by_id(uuid, uuid, text) is
  'Accepte une invitation désignée par son identifiant : adresse du compte confirmée (auth.users.email_confirmed_at), contrôle d''adresse en amont, jeton résolu en base, puis accept_invitation. service_role uniquement.';

-- ---------------------------------------------------------------------------
-- Droits d'exécution : ceux de 0036, rejoués à l'identique (voir 0009 pour la
-- raison des `revoke` nommés à `anon` et `authenticated`).
-- ---------------------------------------------------------------------------
revoke all on function my_pending_invitations() from public, anon, authenticated;
grant execute on function my_pending_invitations() to authenticated;

revoke all on function accept_invitation_by_id(uuid, uuid, text) from public, anon, authenticated;
grant execute on function accept_invitation_by_id(uuid, uuid, text) to service_role;
