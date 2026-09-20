-- 0009 — Fonctions d'invitation, appelées par les Edge Functions avec la clé de service.
-- Référence : docs/SCHEMA.md sections 2.4, 3 et 7. Ticket 006.
--
-- Pourquoi du SQL plutôt que trois requêtes depuis Deno : chaque parcours touche
-- plusieurs tables (invitations, memberships, audit_log) et doit être tout ou rien.
-- Une fonction plpgsql s'exécute dans une transaction implicite ; trois appels
-- PostgREST, non. Une invitation marquée acceptée sans membership créée, ou
-- l'inverse, laisserait un invité dehors sans moyen de recommencer.
--
-- Les deux fonctions sont `security definer` mais ne sont **pas** exposées au rôle
-- `authenticated` : l'exécution est révoquée de `public` et accordée au seul
-- `service_role`. Le token d'invitation est un porteur de droits (voir 0008) et
-- `create_invitation` le renvoie : il ne doit jamais traverser PostgREST côté client.
--
-- Le droit d'inviter est décidé ici, à partir de `p_invited_by` (l'identité tirée du
-- JWT par l'Edge Function) et de `p_station`, jamais à partir d'un champ du corps de
-- la requête HTTP.

-- ---------------------------------------------------------------------------
-- Masque une adresse pour la renvoyer à un porteur de token qui n'est pas le
-- destinataire : « marie.lefebvre@caserne-a.test » → « m••••••••e@caserne-a.test ».
-- Assez pour que l'invité reconnaisse sa propre adresse, pas assez pour l'apprendre.
-- ---------------------------------------------------------------------------
create function mask_email(p_email text) returns text
language sql immutable security invoker set search_path = public, pg_temp as $$
  select case
    when p_email is null or position('@' in p_email) = 0 then '•••'
    else (
      with parts as (
        select split_part(p_email, '@', 1) as locale, split_part(p_email, '@', 2) as domaine
      )
      select case
               when length(locale) <= 2 then repeat('•', greatest(length(locale), 1))
               else left(locale, 1) || repeat('•', length(locale) - 2) || right(locale, 1)
             end || '@' || domaine
      from parts
    )
  end;
$$;

comment on function mask_email(text) is
  'Masque la partie locale d''une adresse e-mail, pour les messages d''erreur rendus à un tiers.';

-- ---------------------------------------------------------------------------
-- create_invitation — crée ou rafraîchit l'invitation d'une adresse dans une caserne.
--
-- Renvoie un objet JSON, jamais une exception métier : l'Edge Function traduit le
-- code en statut HTTP. `ok = false` avec `code` parmi :
--   invalid_email | station_not_found | not_admin | station_suspended |
--   already_member | conflict
-- `ok = true` renvoie le token — d'où la restriction d'exécution au service_role.
--
-- Renvoi d'une invitation déjà en attente : la ligne est réutilisée (l'index partiel
-- invitations_pending_uniq n'en autorise qu'une par caserne et par adresse), son
-- expiration repart à 14 jours et le rôle est remis à jour. Le **token est conservé** :
-- le lien déjà envoyé, éventuellement déjà ouvert dans un onglet, doit continuer à
-- fonctionner. Un renvoi prolonge l'invitation, il ne la remplace pas.
-- ---------------------------------------------------------------------------
create function create_invitation(
  p_station    uuid,
  p_email      text,
  p_role       membership_role,
  p_invited_by uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email      text := lower(btrim(coalesce(p_email, '')));
  v_station    stations%rowtype;
  v_inviter    profiles%rowtype;
  v_user_id    uuid;
  v_statut     membership_status;
  v_existante  invitations%rowtype;
  v_renvoi     boolean;
  v_inv        invitations%rowtype;
begin
  -- Contrôle volontairement permissif : la validation fine d'une adresse e-mail est
  -- un piège, seul l'envoi la tranche. On n'écarte que ce qui ne peut pas être une
  -- adresse (vide, sans arobase, avec des espaces).
  if v_email = '' or v_email !~ '^[^@[:space:]]+@[^@[:space:].]+(\.[^@[:space:].]+)+$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_email');
  end if;

  select * into v_station from stations where id = p_station;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'station_not_found');
  end if;

  -- Le droit d'inviter : admin actif de CETTE caserne. Un admin de la caserne B
  -- n'obtient rien en visant la caserne A, quel que soit le corps de la requête.
  if not exists (
    select 1 from memberships
    where station_id = p_station and user_id = p_invited_by
      and status = 'active' and role = 'admin'
  ) then
    return jsonb_build_object('ok', false, 'code', 'not_admin');
  end if;

  -- Caserne suspendue : lecture seule, on n'y fait pas entrer de nouveaux membres.
  if not station_writable(p_station) then
    return jsonb_build_object('ok', false, 'code', 'station_suspended');
  end if;

  select p.id into v_user_id from profiles p where lower(p.email) = v_email;

  if v_user_id is not null then
    select m.status into v_statut
    from memberships m
    where m.station_id = p_station and m.user_id = v_user_id;

    -- Déjà membre actif : rien à inviter. Un membre désactivé, lui, peut être
    -- réinvité — accept_invitation réactivera sa ligne.
    if v_statut = 'active' then
      return jsonb_build_object('ok', false, 'code', 'already_member');
    end if;
  end if;

  select * into v_existante
  from invitations
  where station_id = p_station and lower(email) = v_email and accepted_at is null
  for update;
  v_renvoi := found;

  if v_renvoi then
    update invitations
       set role       = p_role,
           invited_by = p_invited_by,
           expires_at = now() + interval '14 days'
     where id = v_existante.id
    returning * into v_inv;
  else
    begin
      insert into invitations (station_id, email, role, invited_by)
      values (p_station, v_email, p_role, p_invited_by)
      returning * into v_inv;
    exception when unique_violation then
      -- Deux invitations simultanées pour la même adresse : l'index partiel a
      -- tranché. L'appelant réessaie, le second appel tombera sur le renvoi.
      return jsonb_build_object('ok', false, 'code', 'conflict');
    end;
  end if;

  select * into v_inviter from profiles where id = p_invited_by;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    p_station, p_invited_by,
    case when v_renvoi then 'invitation.resent' else 'invitation.created' end,
    'invitations', v_inv.id,
    jsonb_build_object('email', v_email, 'role', p_role, 'expires_at', v_inv.expires_at)
  );

  return jsonb_build_object(
    'ok', true,
    'resent', v_renvoi,
    'token', v_inv.token,
    'account_exists', v_user_id is not null,
    'invitee_id', v_user_id,
    'invitation', jsonb_build_object(
      'id', v_inv.id,
      'station_id', v_inv.station_id,
      'email', v_inv.email,
      'role', v_inv.role,
      'expires_at', v_inv.expires_at,
      'created_at', v_inv.created_at
    ),
    'station', jsonb_build_object(
      'id', v_station.id, 'name', v_station.name, 'slug', v_station.slug
    ),
    'inviter', jsonb_build_object(
      'id', v_inviter.id,
      'first_name', v_inviter.first_name,
      'last_name', v_inviter.last_name,
      'email', v_inviter.email
    )
  );
end;
$$;

comment on function create_invitation(uuid, text, membership_role, uuid) is
  'Crée ou prolonge l''invitation d''une adresse dans une caserne. Renvoie le token : service_role uniquement.';

-- ---------------------------------------------------------------------------
-- accept_invitation — vérifie le token et fait entrer l'invité dans la caserne.
--
-- Tout ou rien : la membership est créée et l'invitation marquée acceptée dans la
-- même transaction, ou rien n'est écrit.
--
-- `ok = false` avec `code` parmi :
--   invitation_not_found | email_mismatch | invitation_already_accepted |
--   invitation_expired | station_suspended | profile_missing
-- ---------------------------------------------------------------------------
create function accept_invitation(
  p_token   text,
  p_user_id uuid,
  p_email   text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_token      text := btrim(coalesce(p_token, ''));
  v_email      text := lower(btrim(coalesce(p_email, '')));
  v_inv        invitations%rowtype;
  v_station    stations%rowtype;
  v_inviter    profiles%rowtype;
  v_membership memberships%rowtype;
  v_station_js jsonb;
  v_inviter_js jsonb;
begin
  if v_token = '' then
    return jsonb_build_object('ok', false, 'code', 'invitation_not_found');
  end if;

  -- for update : deux onglets qui suivent le même lien ne créent pas deux membres.
  select * into v_inv from invitations where token = v_token for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'invitation_not_found');
  end if;

  select * into v_station from stations where id = v_inv.station_id;
  select * into v_inviter from profiles  where id = v_inv.invited_by;

  v_station_js := jsonb_build_object(
    'id', v_station.id, 'name', v_station.name,
    'slug', v_station.slug, 'timezone', v_station.timezone
  );
  -- L'invité doit pouvoir écrire à celui qui l'a invité quand ça coince
  -- (invitation expirée) : c'est la seule sortie de secours du parcours.
  v_inviter_js := jsonb_build_object(
    'first_name', v_inviter.first_name,
    'last_name', v_inviter.last_name,
    'email', v_inviter.email
  );

  -- Le porteur du lien n'est pas forcément le destinataire : un lien se transfère,
  -- se retrouve dans un historique, se colle dans une conversation de groupe.
  -- C'est l'adresse de la session, pas le lien, qui fait entrer dans la caserne.
  if lower(v_inv.email) <> v_email then
    return jsonb_build_object(
      'ok', false, 'code', 'email_mismatch',
      'invited_email_masked', mask_email(v_inv.email),
      'station', v_station_js
    );
  end if;

  if v_inv.accepted_at is not null then
    select * into v_membership
    from memberships
    where station_id = v_inv.station_id and user_id = p_user_id;

    -- Même lien rejoué (retour arrière, double onglet, relance de l'app) : on ne
    -- casse pas un onboarding qui a déjà réussi.
    if found and v_membership.status = 'active' then
      return jsonb_build_object(
        'ok', true, 'already_accepted', true,
        'membership', jsonb_build_object(
          'id', v_membership.id, 'station_id', v_membership.station_id,
          'user_id', v_membership.user_id, 'role', v_membership.role,
          'status', v_membership.status, 'display_name', v_membership.display_name
        ),
        'station', v_station_js,
        'inviter', v_inviter_js
      );
    end if;

    return jsonb_build_object(
      'ok', false, 'code', 'invitation_already_accepted',
      'accepted_at', v_inv.accepted_at, 'station', v_station_js, 'inviter', v_inviter_js
    );
  end if;

  if v_inv.expires_at <= now() then
    return jsonb_build_object(
      'ok', false, 'code', 'invitation_expired',
      'expires_at', v_inv.expires_at, 'station', v_station_js, 'inviter', v_inviter_js
    );
  end if;

  if not station_writable(v_inv.station_id) then
    return jsonb_build_object(
      'ok', false, 'code', 'station_suspended',
      'station', v_station_js, 'inviter', v_inviter_js
    );
  end if;

  -- memberships.user_id référence profiles : sans profil, pas de membership. Le
  -- trigger handle_new_user le crée à l'inscription ; s'il manque, on le dit.
  if not exists (select 1 from profiles where id = p_user_id) then
    return jsonb_build_object('ok', false, 'code', 'profile_missing');
  end if;

  insert into memberships (station_id, user_id, role, status)
  values (v_inv.station_id, p_user_id, v_inv.role, 'active')
  on conflict (station_id, user_id) do update
    set role        = excluded.role,
        status      = 'active',
        disabled_at = null
  returning * into v_membership;

  update invitations set accepted_at = now() where id = v_inv.id;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    v_inv.station_id, p_user_id, 'invitation.accepted', 'invitations', v_inv.id,
    jsonb_build_object('email', v_inv.email, 'role', v_inv.role, 'membership_id', v_membership.id)
  );

  return jsonb_build_object(
    'ok', true, 'already_accepted', false,
    'membership', jsonb_build_object(
      'id', v_membership.id, 'station_id', v_membership.station_id,
      'user_id', v_membership.user_id, 'role', v_membership.role,
      'status', v_membership.status, 'display_name', v_membership.display_name
    ),
    'station', v_station_js,
    'inviter', v_inviter_js
  );
end;
$$;

comment on function accept_invitation(text, uuid, text) is
  'Vérifie un token d''invitation et fait entrer l''invité dans la caserne, en une transaction. service_role uniquement.';

-- ---------------------------------------------------------------------------
-- Exécution réservée au service_role (Edge Functions invite-member et
-- accept-invitation). Sans ce revoke, un client authentifié appellerait
-- create_invitation en RPC PostgREST et lirait le token, que 0008 lui a
-- justement retiré.
--
-- `revoke ... from public` ne suffit pas : `api.auto_expose_new_tables` (vrai par
-- défaut, comme sur le projet hébergé) pose des privilèges par défaut qui
-- accordent explicitement `execute` à `anon` et `authenticated` sur toute
-- fonction créée dans `public` par `postgres`. Un `revoke from public` laisse ces
-- deux grants nominatifs en place — vérifié en local, le test 7 de
-- supabase/tests/invitations_test.sql le reproduit. Les deux rôles sont donc
-- nommés explicitement.
-- ---------------------------------------------------------------------------
revoke all on function create_invitation(uuid, text, membership_role, uuid)
  from public, anon, authenticated;
revoke all on function accept_invitation(text, uuid, text)
  from public, anon, authenticated;
grant execute on function create_invitation(uuid, text, membership_role, uuid) to service_role;
grant execute on function accept_invitation(text, uuid, text)                  to service_role;
