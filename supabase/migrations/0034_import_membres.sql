-- 0034 — Le nom porté par l'invitation. Ticket 047, import des membres depuis un fichier.
-- Référence : docs/SCHEMA.md sections 2.4 et 3, design/047-import-membres.md section 7.
--
-- Le problème que ça résout : jusqu'ici une invitation ne portait qu'une adresse.
-- Un chef de centre qui monte une caserne de soixante pompiers à partir de sa liste
-- voyait donc, pendant les deux semaines de l'invitation, soixante adresses et aucun
-- nom — et il ne reconnaissait ses pompiers dans la matrice qu'au fur et à mesure que
-- chacun complétait son profil. Les noms existaient pourtant dans son fichier.
--
-- Trois choses, et pas une de plus :
--
--   1. `invitations.first_name` / `last_name` : le nom saisi par l'administrateur,
--      porté jusqu'à l'acceptation. Lisible par les administrateurs de la caserne
--      (l'écran « Membres » l'affiche), pas par l'invité — il n'a rien à y lire.
--   2. `create_invitation` accepte les deux noms. Sa signature change, donc elle est
--      supprimée puis recréée : ajouter deux paramètres à valeur par défaut créerait
--      une surcharge, et un appel à quatre arguments deviendrait ambigu.
--   3. `accept_invitation` **amorce** le profil avec ces noms, et seulement s'il est
--      vide. C'est la décision du ticket : le nom de l'administrateur est une
--      proposition, celui que la personne saisit sur elle-même fait foi. Un compte
--      qui existe déjà — un pompier venu d'une autre caserne, un membre réactivé —
--      ne voit jamais son profil réécrit par l'administrateur d'une caserne.
--
-- Ce que la migration ne fait pas : toucher à `memberships.display_name`. Le surnom
-- de caserne appartient à l'administrateur (ticket 009), il prime déjà dans les
-- plannings, et il se décide — il ne se déduit pas d'un tableur.

-- ===========================================================================
-- 1. Les deux colonnes
-- ===========================================================================
-- `text` et non `varchar(n)` : la borne est posée par la fonction, qui tronque, pour
-- qu'un nom trop long n'échoue pas un import de soixante personnes au motif qu'une
-- ligne porte une adresse postale dans la colonne « nom ».
alter table invitations
  add column first_name text,
  add column last_name  text;

comment on column invitations.first_name is
  'Prénom saisi par l''administrateur qui invite (import du ticket 047). Amorce le profil à l''acceptation, et seulement s''il est vide.';
comment on column invitations.last_name is
  'Nom saisi par l''administrateur qui invite (import du ticket 047). Même règle que first_name.';

-- Le grant de colonne de 0008 énumère : une colonne ajoutée n'en hérite pas. Sans
-- ces deux lignes, l'écran « Membres » ne lirait pas les noms qu'il vient d'écrire.
-- `token` reste dehors, et c'est toujours la raison pour laquelle on énumère.
grant select (first_name, last_name) on invitations to authenticated;

-- ===========================================================================
-- 2. create_invitation — le corps de 0032, plus les deux noms
-- ===========================================================================
-- La suppression est nécessaire : `create or replace` refuse un changement de
-- signature, et une surcharge à six paramètres dont deux par défaut rendrait
-- `create_invitation(uuid, text, membership_role, uuid)` ambigu à l'appel.
drop function if exists create_invitation(uuid, text, membership_role, uuid);

create function create_invitation(
  p_station    uuid,
  p_email      text,
  p_role       membership_role,
  p_invited_by uuid,
  p_first_name text default null,
  p_last_name  text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email      text := lower(btrim(coalesce(p_email, '')));
  -- Normalisation des noms : espaces réduits, bornés à 80 caractères. Une colonne
  -- décalée d'un cran met une adresse postale ici ; on la tronque plutôt que de
  -- refuser la ligne, parce que l'invitation compte plus que le nom.
  v_prenom     text := nullif(left(btrim(regexp_replace(coalesce(p_first_name, ''), '\s+', ' ', 'g')), 80), '');
  v_nom        text := nullif(left(btrim(regexp_replace(coalesce(p_last_name,  ''), '\s+', ' ', 'g')), 80), '');
  v_station    stations%rowtype;
  v_inviter    profiles%rowtype;
  v_user_id    uuid;
  v_statut     membership_status;
  v_existante  invitations%rowtype;
  v_renvoi     boolean;
  v_super      boolean;
  v_debit      jsonb;
  v_inv        invitations%rowtype;
begin
  if v_email = '' or v_email !~ '^[^@[:space:]]+@[^@[:space:].]+(\.[^@[:space:].]+)+$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_email');
  end if;

  select * into v_station from stations where id = p_station;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'station_not_found');
  end if;

  v_super := exists (select 1 from super_admins where user_id = p_invited_by);

  if not v_super and not exists (
    select 1 from memberships
    where station_id = p_station and user_id = p_invited_by
      and status = 'active' and role = 'admin'
  ) then
    return jsonb_build_object('ok', false, 'code', 'not_admin');
  end if;

  if not station_writable(p_station) then
    return jsonb_build_object('ok', false, 'code', 'station_suspended');
  end if;

  select p.id into v_user_id from profiles p where lower(p.email) = v_email;

  if v_user_id is not null then
    select m.status into v_statut
    from memberships m
    where m.station_id = p_station and m.user_id = v_user_id;

    if v_statut = 'active' then
      return jsonb_build_object('ok', false, 'code', 'already_member');
    end if;
  end if;

  -- Le verrou : compter puis écrire doit être indivisible (0032).
  perform pg_advisory_xact_lock(
    hashtext('invitation_rate_limit'),
    hashtext(case when v_super then p_invited_by::text else p_station::text end));

  v_debit := invitation_rate_limit(p_station, p_invited_by);
  if not (v_debit ->> 'allowed')::boolean then
    if not exists (
      select 1 from audit_log a
       where a.station_id = p_station
         and a.action = 'invitation.rate_limited'
         and a.created_at > now() - interval '1 hour'
    ) then
      insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
      values (
        p_station, p_invited_by, 'invitation.rate_limited', 'invitations', null,
        (v_debit - 'allowed') || jsonb_build_object('email', v_email)
      );
    end if;

    return jsonb_build_object('ok', false, 'code', 'rate_limited')
        || (v_debit - 'allowed');
  end if;

  select * into v_existante
  from invitations
  where station_id = p_station and lower(email) = v_email and accepted_at is null
  for update;
  v_renvoi := found;

  if v_renvoi then
    -- Un nom fourni corrige le précédent — c'est le sens d'un second import après
    -- correction du fichier. Un nom absent ne l'efface pas : le renvoi d'une
    -- invitation depuis l'écran « Membres » ne passe pas de noms, et il ne doit
    -- pas faire disparaître ceux qu'un import avait posés.
    update invitations
       set role       = p_role,
           invited_by = p_invited_by,
           first_name = coalesce(v_prenom, first_name),
           last_name  = coalesce(v_nom,    last_name),
           expires_at = now() + interval '14 days'
     where id = v_existante.id
    returning * into v_inv;
  else
    begin
      insert into invitations (station_id, email, role, invited_by, first_name, last_name)
      values (p_station, v_email, p_role, p_invited_by, v_prenom, v_nom)
      returning * into v_inv;
    exception when unique_violation then
      return jsonb_build_object('ok', false, 'code', 'conflict');
    end;
  end if;

  insert into invitation_rate_events (station_id, actor_id)
  values (p_station, p_invited_by);

  select * into v_inviter from profiles where id = p_invited_by;

  -- Le journal ne reçoit **pas** les noms. `audit_log` garde trois ans
  -- (docs/RGPD.md) ; l'adresse y est déjà nécessaire pour retrouver une invitation,
  -- le nom n'y ajoute qu'une donnée personnelle de plus à conserver.
  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    p_station, p_invited_by,
    case when v_renvoi then 'invitation.resent' else 'invitation.created' end,
    'invitations', v_inv.id,
    jsonb_strip_nulls(jsonb_build_object(
      'email', v_email, 'role', p_role, 'expires_at', v_inv.expires_at,
      'named', case when v_prenom is not null or v_nom is not null then true else null end,
      'by_super_admin', case when v_super then true else null end))
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
      'first_name', v_inv.first_name,
      'last_name', v_inv.last_name,
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

comment on function create_invitation(uuid, text, membership_role, uuid, text, text) is
  'Crée ou prolonge l''invitation d''une adresse dans une caserne, avec le nom que l''administrateur lui donne (ticket 047). Invitant autorisé : admin actif de la caserne, ou super-admin (ticket 031). Plafonnée à settings.invitation_hourly_limit envois par heure et par caserne, davantage pour le super-admin (ticket 038) : au-delà, code rate_limited avec retry_at. Renvoie le token : service_role uniquement.';

revoke all on function create_invitation(uuid, text, membership_role, uuid, text, text)
  from public, anon, authenticated;
grant execute on function create_invitation(uuid, text, membership_role, uuid, text, text) to service_role;

-- ===========================================================================
-- 3. accept_invitation — le nom importé amorce le profil, sans jamais l'écraser
-- ===========================================================================
-- Corps de 0009 à l'identique, plus une seule écriture, placée après la création de
-- la membership et avant le journal : les noms de l'invitation sont recopiés dans
-- `profiles` **là où il n'y a rien**. `nullif(btrim(…), '')` des deux côtés, parce
-- que le déclencheur `handle_new_user` crée le profil avec des chaînes vides et non
-- des nuls : un `coalesce` seul ne verrait jamais la place libre.
create or replace function accept_invitation(
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
  v_inviter_js := jsonb_build_object(
    'first_name', v_inviter.first_name,
    'last_name', v_inviter.last_name,
    'email', v_inviter.email
  );

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

  -- L'amorce. Deux garde-fous dans la clause `where` plutôt que dans le `set` :
  -- sans eux, la ligne serait réécrite à l'identique à chaque acceptation, pour
  -- rien, et `updated_at` bougerait sans qu'un nom change.
  if v_inv.first_name is not null or v_inv.last_name is not null then
    update profiles p
       set first_name = coalesce(nullif(btrim(p.first_name), ''), v_inv.first_name, ''),
           last_name  = coalesce(nullif(btrim(p.last_name),  ''), v_inv.last_name,  '')
     where p.id = p_user_id
       and (
         (nullif(btrim(p.first_name), '') is null and v_inv.first_name is not null)
         or (nullif(btrim(p.last_name), '') is null and v_inv.last_name is not null)
       );
  end if;

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
  'Vérifie le token et fait entrer l''invité dans la caserne, en une transaction. Amorce prénom et nom du profil avec ceux de l''invitation quand ils sont vides (ticket 047) : la saisie de la personne sur elle-même reste prioritaire. service_role uniquement.';

revoke all on function accept_invitation(text, uuid, text) from public, anon, authenticated;
grant execute on function accept_invitation(text, uuid, text) to service_role;
