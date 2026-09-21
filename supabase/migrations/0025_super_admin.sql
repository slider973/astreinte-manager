-- 0025 — Interface super-admin : ce que l'éditeur du produit voit, ce qu'il peut
-- faire, et surtout **ce qu'il ne peut plus faire**. Ticket 031.
-- Référence : docs/PRD.md § 3.3 et § 6.7, docs/SCHEMA.md § 2.15, 3 et 4,
-- design/031-super-admin.md.
--
-- Ce qui existait déjà et n'est pas réécrit
-- -----------------------------------------
--   - `super_admins` et `is_super_admin()` (0006, 0007, 0008) : la table n'est
--     alimentée qu'en SQL manuel, c'est voulu, et la fonction qui la lit ne
--     bouge pas.
--   - `create_invitation` (0009) : **le** chemin d'invitation. Elle gagne une
--     branche d'autorisation, pas un jumeau.
--   - `subscription_bootstrap` (0023) : toute caserne naît en essai de 60 jours.
--     La création ci-dessous n'écrit donc rien dans `subscriptions`.
--   - `station_writable()` (0007) : la seule définition du droit d'écrire. La
--     suspension manuelle passe par le statut, jamais par une exception.
--
-- Ce que cette migration change
-- -----------------------------
--   1. **Elle retire des droits.** Les trois politiques de `stations` citaient
--      `is_super_admin()` ; aucune ne le fera plus.
--   2. `super_admin_stations()` : les faits d'exploitation de toutes les
--      casernes, et rien de plus.
--   3. `super_admin_create_station()` : créer une caserne, tracé.
--   4. `super_admin_set_station_suspended()` : suspendre et réactiver, tracé.
--   5. `super_admin_support_schedules()` : la seule porte vers les données de
--      planning, tracée à chaque lecture dans l'audit de la caserne.
--   6. `create_invitation()` : le super-admin peut nommer le premier admin
--      d'une caserne, par le chemin du ticket 006 et par aucun autre.
--
-- Aucune table nouvelle, aucune colonne nouvelle, aucun enum touché.

-- ===========================================================================
-- 1. Ce que le super-admin perd — et pourquoi il devait le perdre
-- ===========================================================================
-- Constaté en base avant d'écrire une ligne (le fichier de test le rejoue) :
-- un super-admin lisait **toute** la table `stations`, `settings` compris, et
-- surtout il pouvait faire
--
--     update stations set name = '…', settings = jsonb_set(settings, …)
--       where id = <une caserne dont il n'est pas membre>;
--
-- — une ligne écrite, aucune trace. Régler l'effectif requis ou la date limite
-- de saisie d'un centre est une décision du centre. La règle du produit est que
-- **les données d'une caserne appartiennent à la caserne** (`docs/PRD.md § 3.3`) ;
-- un droit d'écriture silencieux sur ses réglages la contredit directement.
--
-- Les trois politiques sont donc ramenées au membre et à l'admin. Après cette
-- migration, une seule politique de tout le schéma cite encore
-- `is_super_admin()` : `super_admins_select_super_admin`. C'est une propriété
-- vérifiable sur `pg_policies`, et le test le fait.
--
-- L'`insert` disparaît aussi : créer une caserne passe désormais par
-- `super_admin_create_station()`, qui journalise. Un `insert` direct restait un
-- second chemin, non tracé, vers le même effet.
drop policy "stations_select_member_or_super_admin" on stations;
drop policy "stations_insert_super_admin"           on stations;
drop policy "stations_update_admin"                 on stations;

create policy "stations_select_member"
  on stations for select to authenticated
  using (is_member(id));

create policy "stations_update_admin"
  on stations for update to authenticated
  using (is_admin(id))
  with check (is_admin(id));

comment on policy "stations_select_member" on stations is
  'Une caserne n''est lisible que de ses membres (ticket 031). Le super-admin passe par super_admin_stations(), qui rend des faits d''exploitation et pas la table.';

-- `is_super_admin()` reste exécutable par un client connecté : c'est elle que la
-- PWA appelle pour savoir si elle a le droit d'ouvrir `/superadmin`. Le grant
-- est rendu explicite plutôt que laissé aux privilèges par défaut de Supabase,
-- qui ne sont pas un contrat.
grant execute on function is_super_admin() to authenticated;

-- ===========================================================================
-- 2. `super_admin_stations` — la liste, et rien que les faits d'exploitation
-- ===========================================================================
-- Aucune vue n'agrège ces informations, et c'est normal : toutes les politiques
-- cloisonnent par caserne. Il faut donc une fonction `security definer`, et la
-- seule question qui compte est **ce qu'elle laisse sortir**.
--
-- Ce qui sort : le nom, le slug, le fuseau, la date de création, le nombre de
-- membres actifs, le nombre d'administrateurs actifs, le nombre d'invitations
-- en attente, les quatre faits d'abonnement, et la date du dernier planning
-- publié.
--
-- Ce qui ne sort pas : `settings` (les réglages métier du centre), les
-- identifiants du prestataire de paiement, et **tout ce qui nomme quelqu'un** —
-- aucun e-mail, aucun nom, aucun `user_id`. Les invitations en attente sont un
-- compte, pas une liste d'adresses : l'éditeur a besoin de savoir qu'il a déjà
-- invité, pas de savoir qui.
--
-- `admins_actifs` n'est pas un ornement : c'est le fait qui décide de l'action
-- proposée sur la ligne. Une caserne à zéro administrateur est un cul-de-sac, et
-- l'écran doit pouvoir le dire.
--
-- Zéro ligne à qui n'est pas super-admin, pas une exception : une liste vide est
-- le comportement juste d'un `select`, et la PWA sait déjà par `is_super_admin()`
-- si elle a le droit d'être là.
create function super_admin_stations()
returns table (
  station_id        uuid,
  name              text,
  slug              text,
  timezone          text,
  created_at        timestamptz,
  active_members    integer,
  active_admins     integer,
  pending_invites   integer,
  status            subscription_status,
  trial_ends_at     timestamptz,
  suspended_at      timestamptz,
  writable          boolean,
  last_published_at timestamptz,
  last_published_year  integer,
  last_published_month integer
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    s.id,
    s.name,
    s.slug,
    s.timezone,
    s.created_at,
    coalesce(m.actifs, 0)::integer,
    coalesce(m.admins, 0)::integer,
    coalesce(i.attente, 0)::integer,
    sub.status,
    sub.trial_ends_at,
    sub.suspended_at,
    coalesce(sub.status is null or sub.status in ('trialing', 'active', 'past_due'), true),
    pub.published_at,
    pub.year,
    pub.month
  from stations s
  left join subscriptions sub on sub.station_id = s.id
  left join lateral (
    select
      count(*) filter (where mm.status = 'active')                          as actifs,
      count(*) filter (where mm.status = 'active' and mm.role = 'admin')    as admins
    from memberships mm
    where mm.station_id = s.id
  ) m on true
  left join lateral (
    select count(*) as attente
    from invitations inv
    where inv.station_id = s.id
      and inv.accepted_at is null
      and inv.expires_at > now()
  ) i on true
  -- Le **dernier planning publié**, au sens du produit : publié ou validé, un
  -- planning validé ayant forcément été publié d'abord (`docs/WORKFLOWS.md § 2`).
  -- Trié sur le mois couvert, pas sur la date de publication : un mois de
  -- rattrapage publié hier ne fait pas de janvier le « dernier planning ».
  left join lateral (
    select sc.published_at, p.year, p.month
    from schedules sc
    join periods p on p.id = sc.period_id
    where sc.station_id = s.id
      and sc.status in ('published', 'validated')
    order by p.year desc, p.month desc
    limit 1
  ) pub on true
  where is_super_admin()
  order by s.name;
$$;

comment on function super_admin_stations() is
  'Les faits d''exploitation de toutes les casernes, pour l''écran de l''éditeur (ticket 031) : effectifs, abonnement, dernier planning publié, création. Ni settings, ni identifiants de paiement, ni le moindre nom de personne. Zéro ligne à qui n''est pas super-admin.';

revoke execute on function super_admin_stations() from public, anon;
grant  execute on function super_admin_stations() to authenticated;

-- ===========================================================================
-- 3. Le slug, dérivé du nom
-- ===========================================================================
-- Un identifiant d'URL n'a rien à faire dans un formulaire : c'est un détail
-- technique, et le faire saisir, c'est faire porter une collision d'unicité à
-- quelqu'un qui voulait juste créer une caserne.
--
-- Pas d'`unaccent` : l'extension n'est pas garantie sur le projet hébergé, et un
-- `translate` sur les diacritiques du français fait exactement le travail
-- demandé, de façon `immutable` et sans dépendance.
create function station_slug(p_name text) returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select coalesce(
    nullif(
      btrim(
        regexp_replace(
          regexp_replace(
            lower(translate(
              coalesce(p_name, ''),
              'àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæ',
              'aaaaaaceeeeiiiinooooouuuuyyoa')),
            '[^a-z0-9]+', '-', 'g'),
          '(^-+)|(-+$)', '', 'g'),
        '-'),
      ''),
    'caserne');
$$;

comment on function station_slug(text) is
  'Dérive un slug d''URL depuis un nom de caserne : minuscules, diacritiques du français repliées, tout le reste en tirets. Rend « caserne » quand il ne reste rien.';

revoke execute on function station_slug(text) from public, anon, authenticated;

-- ===========================================================================
-- 4. `super_admin_create_station` — créer une caserne, et laisser une trace
-- ===========================================================================
-- Ni exception ni `raise` pour les refus métier : `{"ok": false, "code": …}`,
-- comme `create_invitation` (0009). Codes : `forbidden`, `invalid_name`,
-- `invalid_timezone`.
--
-- Le fuseau est vérifié contre `pg_timezone_names` plutôt que gobé tel quel :
-- un fuseau inconnu ne casse rien à l'insertion, il casse les crons de la
-- caserne trois semaines plus tard, quand personne ne fera le lien.
--
-- La ligne d'abonnement n'est pas écrite ici : `subscription_bootstrap` (0023)
-- s'en charge, avec ses 60 jours d'essai. Deux endroits qui décident de la durée
-- d'un essai, c'est un endroit de trop.
create function super_admin_create_station(
  p_name     text,
  p_timezone text default 'Europe/Paris'
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_nom     text := btrim(coalesce(p_name, ''));
  v_fuseau  text := btrim(coalesce(p_timezone, ''));
  v_base    text;
  v_slug    text;
  v_suffixe integer := 1;
  v_station stations%rowtype;
begin
  if not is_super_admin() then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if v_nom = '' or char_length(v_nom) > 80 then
    return jsonb_build_object('ok', false, 'code', 'invalid_name');
  end if;

  if v_fuseau = '' then
    v_fuseau := 'Europe/Paris';
  elsif not exists (select 1 from pg_timezone_names where name = v_fuseau) then
    return jsonb_build_object('ok', false, 'code', 'invalid_timezone');
  end if;

  v_base := station_slug(v_nom);
  v_slug := v_base;
  while exists (select 1 from stations where slug = v_slug) loop
    v_suffixe := v_suffixe + 1;
    v_slug := v_base || '-' || v_suffixe;
  end loop;

  insert into stations (name, slug, timezone)
  values (v_nom, v_slug, v_fuseau)
  returning * into v_station;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    v_station.id, auth.uid(), 'station.created', 'stations', v_station.id,
    jsonb_build_object('name', v_station.name, 'slug', v_station.slug,
                       'timezone', v_station.timezone, 'by_super_admin', true)
  );

  return jsonb_build_object(
    'ok', true,
    'station', jsonb_build_object(
      'id', v_station.id, 'name', v_station.name,
      'slug', v_station.slug, 'timezone', v_station.timezone,
      'created_at', v_station.created_at)
  );
end $$;

comment on function super_admin_create_station(text, text) is
  'Crée une caserne pour le compte de l''éditeur (ticket 031) : slug dérivé du nom, fuseau vérifié, ligne d''audit station.created. L''essai de 60 jours vient du trigger subscription_bootstrap. Rend {ok:false, code:…} pour forbidden, invalid_name, invalid_timezone.';

revoke execute on function super_admin_create_station(text, text) from public, anon;
grant  execute on function super_admin_create_station(text, text) to authenticated;

-- ===========================================================================
-- 5. `super_admin_set_station_suspended` — suspendre et réactiver à la main
-- ===========================================================================
-- Codes de refus : `forbidden`, `station_not_found`, `reason_required`.
--
-- **Suspendre** est l'exact pendant de `cron_suspend_subscriptions` : le statut
-- passe à `suspended`, `suspended_at` est posé, et `station_writable()` fait le
-- reste. Rien n'est supprimé — c'est une promesse du produit (`PRD § 6.6`,
-- § 7.6), et elle tient parce que la suspension n'est qu'un statut.
--
-- **Réactiver** doit décider vers quoi revenir, puisque le statut précédent
-- n'est mémorisé nulle part :
--   - un abonnement souscrit chez le prestataire → `active`. Le prochain
--     événement Stripe corrigera si la réalité est autre ; il fait autorité, pas
--     nous.
--   - sinon → `trialing`, **avec la fin d'essai reportée à 30 jours au moins**.
--     Sans ce report, la tâche de 03:30 re-suspendrait la caserne dans la nuit :
--     une réactivation qui se défait toute seule n'est pas une action, c'est un
--     bug. `greatest` : on ne raccourcit jamais un essai encore en cours.
--
-- La raison est obligatoire dans les deux sens, et vérifiée **ici**, pas
-- seulement dans le formulaire : une action de l'éditeur sur la caserne de
-- quelqu'un d'autre sans motif écrit n'a pas à exister.
create function super_admin_set_station_suspended(
  p_station   uuid,
  p_suspended boolean,
  p_reason    text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_raison  text := btrim(coalesce(p_reason, ''));
  v_avant   subscriptions%rowtype;
  v_apres   subscriptions%rowtype;
  v_statut  subscription_status;
  v_essai   timestamptz;
begin
  if not is_super_admin() then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if char_length(v_raison) < 10 then
    return jsonb_build_object('ok', false, 'code', 'reason_required');
  end if;

  perform 1 from stations where id = p_station;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'station_not_found');
  end if;

  -- Verrou de ligne : le webhook du prestataire écrit la même ligne, et deux
  -- décisions simultanées sur un statut d'abonnement ne doivent pas se croiser.
  -- Une caserne restaurée d'un dump antérieur au 0023 n'a pas de ligne : on la
  -- pose, plutôt que de refuser une action légitime pour une raison d'historique.
  select * into v_avant from subscriptions where station_id = p_station for update;
  if not found then
    insert into subscriptions (station_id) values (p_station)
    on conflict (station_id) do nothing;
    select * into v_avant from subscriptions where station_id = p_station for update;
  end if;

  if p_suspended then
    v_statut := 'suspended';
    v_essai  := v_avant.trial_ends_at;
  elsif v_avant.stripe_subscription_id is not null then
    v_statut := 'active';
    v_essai  := v_avant.trial_ends_at;
  else
    v_statut := 'trialing';
    v_essai  := greatest(coalesce(v_avant.trial_ends_at, now()), now() + interval '30 days');
  end if;

  update subscriptions
     set status        = v_statut,
         trial_ends_at = v_essai,
         suspended_at  = case when p_suspended
                              then coalesce(suspended_at, now())
                              else null end
   where station_id = p_station
  returning * into v_apres;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    p_station, auth.uid(),
    case when p_suspended then 'subscription.suspended' else 'subscription.reactivated' end,
    'subscriptions', p_station,
    jsonb_strip_nulls(jsonb_build_object(
      'reason',         'super_admin',
      'note',           v_raison,
      'from',           v_avant.status,
      'to',             v_apres.status,
      'trial_ends_at',  v_apres.trial_ends_at,
      'by_super_admin', true))
  );

  return jsonb_build_object(
    'ok', true,
    'station_id',    p_station,
    'status',        v_apres.status,
    'writable',      station_writable(p_station),
    'trial_ends_at', v_apres.trial_ends_at,
    'suspended_at',  v_apres.suspended_at
  );
end $$;

comment on function super_admin_set_station_suspended(uuid, boolean, text) is
  'Suspend ou réactive une caserne à la main, pour l''éditeur (ticket 031). Rien n''est supprimé : seul le statut change, et station_writable() en tire la lecture seule. La réactivation d''une caserne sans abonnement souscrit reporte la fin d''essai à 30 jours au moins, sinon la tâche de suspension la reprendrait dans la nuit. Raison obligatoire, journalisée dans l''audit de la caserne.';

revoke execute on function super_admin_set_station_suspended(uuid, boolean, text) from public, anon;
grant  execute on function super_admin_set_station_suspended(uuid, boolean, text) to authenticated;

-- ===========================================================================
-- 6. `super_admin_support_schedules` — la seule porte vers les plannings
-- ===========================================================================
-- Le point de sécurité central du ticket. Deux décisions, et elles se tiennent :
--
-- **a. Pas de session de support ouverte pour une heure.** Une lecture = une
-- ligne d'audit, avec sa raison écrite à la main, à chaque appel. Une fenêtre
-- ouverte est une fenêtre qu'on oublie de fermer ; un acte qui coûte une phrase
-- est un acte qu'on ne fait pas par curiosité. C'est aussi ce qui évite d'ajouter
-- `or has_support_access(station_id)` à huit politiques de lecture — huit
-- endroits où se tromper, contre un seul ici.
--
-- **b. La trace va dans l'audit de la caserne**, donc elle est lisible par ses
-- administrateurs (`audit_log_select_admin`, 0007). C'est ça, la garantie : la
-- caserne voit quand l'éditeur a regardé. Une trace que seul l'éditeur peut lire
-- ne protège personne.
--
-- Ce qui sort : par mois, le statut du planning, ses dates, le nombre de
-- créneaux et le décompte des attributions par statut. **Aucun nom, aucun
-- `user_id`, aucune disponibilité.** Un diagnostic d'éditeur est « où en est le
-- planning de novembre », jamais « qui est de garde le 12 ». Le jour où il
-- faudra davantage, ce sera un autre ticket et un autre débat, pas un `select *`
-- ajouté ici en passant.
create function super_admin_support_schedules(
  p_station uuid,
  p_reason  text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_raison    text := btrim(coalesce(p_reason, ''));
  v_station   stations%rowtype;
  v_plannings jsonb;
begin
  if not is_super_admin() then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;

  if char_length(v_raison) < 10 then
    return jsonb_build_object('ok', false, 'code', 'reason_required');
  end if;

  select * into v_station from stations where id = p_station;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'station_not_found');
  end if;

  select coalesce(jsonb_agg(ligne order by ligne->>'year' desc, ligne->>'month' desc), '[]'::jsonb)
    into v_plannings
  from (
    select jsonb_build_object(
             'year',          p.year,
             'month',         p.month,
             'period_status', p.status,
             'status',        sc.status,
             'published_at',  sc.published_at,
             'validated_at',  sc.validated_at,
             'shifts',        (select count(*) from shifts sh where sh.schedule_id = sc.id),
             'assignments',   (
               select coalesce(jsonb_object_agg(a.status, a.n), '{}'::jsonb)
               from (
                 select st.status, count(*) as n
                 from assignments st
                 join shifts sh on sh.id = st.shift_id
                 where sh.schedule_id = sc.id
                 group by st.status
               ) a)
           ) as ligne
    from schedules sc
    join periods p on p.id = sc.period_id
    where sc.station_id = p_station
  ) lignes;

  -- La trace est écrite **avant** de rendre quoi que ce soit : si l'insertion
  -- échoue, la transaction tombe et la lecture n'a pas lieu. Une consultation
  -- non journalisée n'est pas une consultation autorisée.
  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    p_station, auth.uid(), 'support.schedules_read', 'schedules', null,
    jsonb_build_object('note', v_raison, 'by_super_admin', true,
                       'schedules', jsonb_array_length(v_plannings))
  );

  return jsonb_build_object(
    'ok', true,
    'station', jsonb_build_object('id', v_station.id, 'name', v_station.name),
    'schedules', v_plannings
  );
end $$;

comment on function super_admin_support_schedules(uuid, text) is
  'La seule porte de l''éditeur vers les données de planning d''une caserne (ticket 031) : statuts, dates et compteurs par mois, jamais un nom ni un user_id. Raison obligatoire, et chaque lecture est inscrite dans l''audit_log de la caserne — donc visible de ses administrateurs.';

revoke execute on function super_admin_support_schedules(uuid, text) from public, anon;
grant  execute on function super_admin_support_schedules(uuid, text) to authenticated;

-- ===========================================================================
-- 7. Nommer le premier administrateur : le chemin du ticket 006, pas un second
-- ===========================================================================
-- Une caserne fraîchement créée n'a aucun membre, donc aucun admin actif :
-- `create_invitation` refusait avec `not_admin`, et c'était juste tant que
-- personne d'autre n'avait de raison d'inviter.
--
-- La branche ajoutée est **une ligne de condition**, pas une seconde fonction :
-- écrire un `super_admin_invite_admin()` aurait dupliqué la validation
-- d'adresse, le renvoi d'invitation, le contrôle de suspension, la trace — et
-- les deux copies auraient divergé au premier correctif. L'Edge Function
-- `invite-member` reste le seul appelant, et le token ne sort toujours que par
-- le courriel.
--
-- Le reste du corps est identique à 0009, y compris le contrôle de suspension :
-- on ne fait pas entrer de nouveaux membres dans une caserne en lecture seule,
-- même pour l'éditeur — s'il veut inviter, il réactive d'abord, et ça se voit.
create or replace function create_invitation(
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
  v_super      boolean;
  v_inv        invitations%rowtype;
begin
  if v_email = '' or v_email !~ '^[^@[:space:]]+@[^@[:space:].]+(\.[^@[:space:].]+)+$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_email');
  end if;

  select * into v_station from stations where id = p_station;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'station_not_found');
  end if;

  -- Le droit d'inviter : admin actif de CETTE caserne, **ou** super-admin.
  -- Le contrôle porte sur `p_invited_by` — l'identité tirée du JWT par l'Edge
  -- Function — et jamais sur un champ du corps de la requête. Le super-admin
  -- est reconnu par la table, pas par `is_super_admin()` : la fonction lirait
  -- `auth.uid()`, qui est nul sous la clé de service.
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
      return jsonb_build_object('ok', false, 'code', 'conflict');
    end;
  end if;

  select * into v_inviter from profiles where id = p_invited_by;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    p_station, p_invited_by,
    case when v_renvoi then 'invitation.resent' else 'invitation.created' end,
    'invitations', v_inv.id,
    jsonb_strip_nulls(jsonb_build_object(
      'email', v_email, 'role', p_role, 'expires_at', v_inv.expires_at,
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
  'Crée ou prolonge l''invitation d''une adresse dans une caserne. Invitant autorisé : admin actif de la caserne, ou super-admin (ticket 031, pour nommer le premier administrateur). Renvoie le token : service_role uniquement.';

-- `create or replace` conserve les privilèges de 0009 ; on les redit quand même,
-- parce qu'une fonction d'invitation ouverte à `authenticated` rendrait le token
-- lisible en RPC — c'est exactement ce que 0008 et 0009 ont fermé.
revoke all on function create_invitation(uuid, text, membership_role, uuid)
  from public, anon, authenticated;
grant execute on function create_invitation(uuid, text, membership_role, uuid) to service_role;
