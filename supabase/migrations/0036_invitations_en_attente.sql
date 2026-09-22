-- 0036 — Les invitations en attente, vues par l'invité. Ticket 051.
-- Référence : docs/SCHEMA.md sections 2.4, 3 et 7 ; design/051-invitation-en-attente-ignoree.md.
--
-- Le défaut corrigé, constaté en production le 21 septembre 2026 : `invite-member`
-- fait naître le compte, `accept_invitation` fait naître l'appartenance. Entre les
-- deux vit un compte sans caserne, et l'écran « Aucune caserne » lui affirme qu'il
-- n'est attendu nulle part — sans l'avoir jamais vérifié. C'est faux dès qu'on se
-- connecte sans passer par le lien du courriel, c'est-à-dire par le chemin le plus
-- court entre l'invitation et l'application.
--
-- Pourquoi une fonction et non une politique RLS : `invitations_select_admin`
-- (0008) ouvre la table à l'administrateur de la caserne et à personne d'autre.
-- L'élargir à « l'adresse invitée » donnerait à un compte sans appartenance un
-- droit de lecture sur une table d'une caserne où il n'est pas encore entré, et
-- ouvrirait la porte au `select` libre — filtres choisis par l'appelant, colonnes
-- choisies par l'appelant. La RLS d'`invitations` n'est donc **pas** touchée : une
-- fonction `security definer` rend cinq champs, et rien d'autre.
--
-- Deux fonctions ici, et une seule est ouverte au client :
--
--   my_pending_invitations()        → `authenticated`, lecture, cinq champs ;
--   accept_invitation_by_id(...)    → `service_role`, appelée par l'Edge Function
--                                     accept-invitation quand le corps porte un
--                                     identifiant au lieu d'un jeton.

-- ---------------------------------------------------------------------------
-- my_pending_invitations — « qui m'attend ? », posée par l'invité lui-même.
--
-- **Sans paramètre, et c'est la contrainte principale.** L'adresse vient de
-- `auth.jwt() ->> 'email'`, jamais d'un argument. Une fonction qui accepterait une
-- adresse serait un oracle d'énumération : n'importe quel compte connecté saurait,
-- adresse par adresse, qui est invité où. Sans paramètre, il n'y a pas de vecteur —
-- un compte ne peut interroger que sa propre session.
--
-- **Zéro ligne, jamais une exception.** « Pas d'invitation » et « pas le droit »
-- doivent être indiscernables : une exception apprendrait à l'appelant la
-- différence entre les deux.
--
-- Cinq champs, et rien de plus (design § 6) :
--
--   id              — désigner laquelle on rejoint, et la passer à l'acceptation.
--                     Ce n'est pas un porteur de droits : seul le compte dont
--                     l'adresse correspond peut en faire quelque chose, et
--                     `accept_invitation_by_id` le revérifie ;
--   station_name    — le point focal de l'écran. Personne ne rejoint « une
--                     caserne », on rejoint le CS Maurepas ;
--   invited_by_name — « Invitation envoyée par Marc Dubois. », et **qui nommer**
--                     quand elle a expiré. `null` quand le profil n'a pas de nom,
--                     jamais un repli sur l'adresse de l'invitant ;
--   expires_at      — « Expire le 5 octobre » / « Expirée le 1er octobre » ;
--   status          — `pending` | `expired`, **tranché ici**. L'horloge d'un
--                     appareil dérive, et celle d'un téléphone de caserne prêté
--                     davantage. Ce ticket existe parce que l'application a
--                     affirmé ce qu'elle n'avait pas vérifié : elle ne va pas
--                     recommencer sur une soustraction de dates locale. C'est
--                     aussi la garantie que l'écran et `accept_invitation` placent
--                     la frontière d'expiration au même endroit.
--
-- Ce qu'elle ne rend pas, et pourquoi : `token` (porteur de droits, retiré du
-- `grant` de select par 0008 — une fonction `security definer` qui le rendrait
-- rouvrirait par la fenêtre la porte que la migration a fermée), `station_id`
-- (une prise sur un tenant dont l'invité n'est pas membre), `role` (aucun geste
-- n'en dépend sur cet écran), l'adresse invitée (c'est celle de la session, le
-- client l'a déjà), `email_sent_at` / `email_error` (le diagnostic de
-- l'administrateur, ticket 048), les noms saisis par l'administrateur (ticket 047)
-- et l'état d'abonnement de la caserne (refusé à l'acceptation, avec sa propre fin
-- de parcours).
--
-- Tri par échéance **décroissante** : les invitations encore valables d'abord, les
-- expirées en dernier — c'est l'ordre que l'écran affiche. Plafond de dix lignes :
-- personne n'est invité par quarante casernes, et une réponse dont la taille dépend
-- de l'appelant est une réponse à borner.
--
-- La revendication de vérification d'adresse est exigée **quand elle est là** : avec
-- la connexion par code à six chiffres elle est vraie par construction, mais un JWT
-- qui dirait explicitement « adresse non vérifiée » ne doit pas ouvrir une caserne.
-- Absente, elle ne bloque rien — sinon la fonction rendrait zéro ligne sur un projet
-- dont GoTrue ne pose pas la claim, et l'écran se remettrait à mentir.
-- Une session anonyme n'a pas d'adresse : elle sort sur la comparaison.
-- ---------------------------------------------------------------------------
create function my_pending_invitations()
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
    and coalesce(
          auth.jwt() ->> 'email_verified',
          auth.jwt() #>> '{user_metadata,email_verified}',
          'true'
        ) <> 'false'
  order by i.expires_at desc
  limit 10;
$$;

comment on function my_pending_invitations() is
  'Les invitations en attente adressées à l''adresse de la session : id, caserne, invitant, échéance, statut. Sans paramètre, sans jeton, zéro ligne à qui n''a rien.';

-- ---------------------------------------------------------------------------
-- accept_invitation_by_id — la même acceptation, désignée par identifiant.
--
-- L'écran « Aucune caserne » connaît l'identifiant de l'invitation (il vient de
-- `my_pending_invitations`), jamais son jeton. Cette fonction résout le jeton
-- **en base**, puis rejoue exactement `accept_invitation` : mêmes contrôles, même
-- transaction, mêmes six codes de refus. Pas de second vocabulaire d'erreurs, pas
-- de seconde définition de « qui peut entrer ».
--
-- Le contrôle d'adresse vient **avant tout le reste**, et il est doublé : ici sur
-- la ligne résolue, puis à nouveau dans `accept_invitation` (`p_email`). Le jeton
-- est un porteur transférable — il circule par courriel, il se copie ; une session
-- dont l'adresse a été vérifiée par un code à six chiffres, non. Le contrôle n'est
-- pas remplacé, il est redoublé.
--
-- Identifiant inconnu et identifiant d'une autre personne rendent **la même
-- chose** : `email_mismatch`, sans caserne, sans adresse masquée, sans date. Les
-- distinguer ferait de cette fonction un oracle d'existence, et l'adresse masquée
-- du chemin par jeton n'a pas lieu d'être ici — elle existe parce qu'un lien se
-- transfère et que son porteur doit reconnaître de quelle boîte il s'agit. Un
-- identifiant, lui, ne se transfère pas : il n'a été donné qu'à la session qu'il
-- concerne.
--
-- Le jeton ne sort pas de la base : il n'est lu que dans cette variable locale, ne
-- traverse pas PostgREST et n'apparaît dans aucune réponse.
-- ---------------------------------------------------------------------------
create function accept_invitation_by_id(
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
  'Accepte une invitation désignée par son identifiant : contrôle d''adresse en amont, jeton résolu en base, puis accept_invitation. service_role uniquement.';

-- ---------------------------------------------------------------------------
-- Droits d'exécution.
--
-- `revoke ... from public` ne suffit pas : `api.auto_expose_new_tables` pose des
-- privilèges par défaut qui accordent nommément `execute` à `anon` et
-- `authenticated` sur toute fonction créée dans `public` par `postgres` (voir 0009).
-- Les deux rôles sont donc révoqués explicitement avant tout `grant`.
--
-- `my_pending_invitations` est ouverte au seul rôle `authenticated` : `anon` n'a
-- pas de session, donc pas d'adresse, et une fonction appelable sans jeton est une
-- fonction qu'on finit par appeler en boucle.
--
-- `accept_invitation_by_id` rejoue `accept_invitation`, qui écrit : elle reste
-- réservée à `service_role`, comme les deux fonctions de 0009.
-- ---------------------------------------------------------------------------
revoke all on function my_pending_invitations() from public, anon, authenticated;
grant execute on function my_pending_invitations() to authenticated;

revoke all on function accept_invitation_by_id(uuid, uuid, text) from public, anon, authenticated;
grant execute on function accept_invitation_by_id(uuid, uuid, text) to service_role;
