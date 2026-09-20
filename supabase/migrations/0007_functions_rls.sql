-- 0007 — Fonctions d'accès, politiques Row Level Security et trigger de transition.
-- Référence : docs/SCHEMA.md sections 3, 4 et 5.
--
-- Principes appliqués ici :
--   * les quatre fonctions d'accès sont `security definer` : elles lisent `memberships`,
--     `super_admins` et `subscriptions` en tant que propriétaire (postgres, qui a
--     `bypassrls`). C'est ce qui évite la récursion infinie quand une politique de
--     `memberships` appelle `is_member()` / `is_admin()` ;
--   * toutes les politiques sont posées `to authenticated`. `anon` n'a aucune politique
--     donc ne lit rien ; `service_role` et `postgres` ont `bypassrls` et ne sont pas
--     concernés (Edge Functions, webhooks, cron) ;
--   * les politiques membre et admin sont séparées (politiques permissives : OR), et
--     select / insert / update / delete sont distingués dès que la condition diffère ;
--   * `station_writable()` conditionne toutes les écritures métier : une caserne
--     suspendue passe en lecture seule.

-- ===========================================================================
-- 3. Fonctions utilitaires
-- ===========================================================================

-- Vrai si l'utilisateur courant est membre actif de la caserne.
create function is_member(p_station uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships
    where station_id = p_station and user_id = auth.uid() and status = 'active'
  );
$$;

comment on function is_member(uuid) is
  'Vrai si auth.uid() est membre actif de la caserne. security definer : contourne la RLS de memberships et évite la récursion des politiques.';

-- Vrai si l'utilisateur courant est admin actif de la caserne.
create function is_admin(p_station uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships
    where station_id = p_station and user_id = auth.uid()
      and status = 'active' and role = 'admin'
  );
$$;

comment on function is_admin(uuid) is
  'Vrai si auth.uid() est admin actif de la caserne. Implique is_member().';

create function is_super_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from super_admins where user_id = auth.uid());
$$;

comment on function is_super_admin() is
  'Vrai si auth.uid() est opérateur de la plateforme (table super_admins).';

-- Vrai si la caserne n'est pas suspendue (écriture autorisée).
create function station_writable(p_station uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select status in ('trialing', 'active', 'past_due') from subscriptions where station_id = p_station),
    true
  );
$$;

comment on function station_writable(uuid) is
  'Vrai si l''abonnement de la caserne autorise l''écriture (absent, trialing, active ou past_due). Une caserne suspended ou cancelled passe en lecture seule.';

-- ===========================================================================
-- Fonctions trigger : jamais appelables depuis l'API
-- ===========================================================================
revoke execute on function set_updated_at() from public, anon, authenticated;
revoke execute on function handle_new_user() from public, anon, authenticated;

-- ===========================================================================
-- 4. Row Level Security
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- stations — lecture : membre ou super-admin. Écriture : admin (update),
-- super-admin (insert). Pas de delete : suppression en SQL manuel uniquement.
-- ---------------------------------------------------------------------------
create policy "stations_select_member_or_super_admin"
  on stations for select to authenticated
  using (is_member(id) or is_super_admin());

create policy "stations_insert_super_admin"
  on stations for insert to authenticated
  with check (is_super_admin());

create policy "stations_update_admin"
  on stations for update to authenticated
  using (is_admin(id) or is_super_admin())
  with check (is_admin(id) or is_super_admin());

-- ---------------------------------------------------------------------------
-- profiles — lecture : soi-même et les membres de ses casernes. Écriture : soi-même.
-- La création est faite par le trigger handle_new_user (security definer).
-- ---------------------------------------------------------------------------
create policy "profiles_select_self_or_same_station"
  on profiles for select to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1 from memberships m
      where m.user_id = profiles.id
        and m.status = 'active'
        and is_member(m.station_id)
    )
  );

create policy "profiles_insert_self"
  on profiles for insert to authenticated
  with check (id = auth.uid());

create policy "profiles_update_self"
  on profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- memberships — lecture : membre de la caserne, plus toujours ses propres lignes
-- (un compte invité ou désactivé doit pouvoir constater son état).
-- Écriture : admin de la caserne, sauf son propre rôle.
-- Point critique : ces politiques ne lisent memberships que via is_member/is_admin,
-- qui sont security definer. Aucune sous-requête directe sur memberships ici, sinon
-- récursion infinie.
-- ---------------------------------------------------------------------------
create policy "memberships_select_station_or_self"
  on memberships for select to authenticated
  using (user_id = auth.uid() or is_member(station_id));

create policy "memberships_insert_admin"
  on memberships for insert to authenticated
  with check (is_admin(station_id) and station_writable(station_id));

-- with check : sur sa propre ligne, un admin ne peut pas se retirer le rôle admin.
create policy "memberships_update_admin"
  on memberships for update to authenticated
  using (is_admin(station_id))
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and (user_id <> auth.uid() or role = 'admin')
  );

create policy "memberships_delete_admin"
  on memberships for delete to authenticated
  using (is_admin(station_id) and station_writable(station_id));

-- Volontairement, aucune politique d'update pour un membre sur sa propre ligne :
-- elle ouvrirait une escalade de privilèges (role = 'admin' sur soi-même). Le
-- display_name est modifié par un admin.

-- ---------------------------------------------------------------------------
-- invitations — admin de la caserne en lecture comme en écriture.
-- L'acceptation d'une invitation passe par l'Edge Function accept-invitation
-- (service role). Cette politique expose toutes les colonnes, token compris :
-- la colonne token est retirée du grant de select en 0008.
-- ---------------------------------------------------------------------------
create policy "invitations_select_admin"
  on invitations for select to authenticated
  using (is_admin(station_id));

create policy "invitations_insert_admin"
  on invitations for insert to authenticated
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and invited_by = auth.uid()
  );

create policy "invitations_update_admin"
  on invitations for update to authenticated
  using (is_admin(station_id))
  with check (is_admin(station_id) and station_writable(station_id));

create policy "invitations_delete_admin"
  on invitations for delete to authenticated
  using (is_admin(station_id) and station_writable(station_id));

-- ---------------------------------------------------------------------------
-- periods — lecture : membre. Écriture : admin.
-- ---------------------------------------------------------------------------
create policy "periods_select_member"
  on periods for select to authenticated
  using (is_member(station_id));

create policy "periods_insert_admin"
  on periods for insert to authenticated
  with check (is_admin(station_id) and station_writable(station_id));

create policy "periods_update_admin"
  on periods for update to authenticated
  using (is_admin(station_id))
  with check (is_admin(station_id) and station_writable(station_id));

create policy "periods_delete_admin"
  on periods for delete to authenticated
  using (is_admin(station_id) and station_writable(station_id));

-- ---------------------------------------------------------------------------
-- availabilities — lecture : les siennes ; admin : toute la caserne.
-- Écriture membre : les siennes, période `open` et caserne writable.
-- Écriture admin : toutes, sans condition de période.
-- ---------------------------------------------------------------------------
create policy "availabilities_select_own_or_admin"
  on availabilities for select to authenticated
  using (user_id = auth.uid() or is_admin(station_id));

create policy "availabilities_insert_member"
  on availabilities for insert to authenticated
  with check (
    user_id = auth.uid()
    and is_member(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from periods p
      where p.station_id = availabilities.station_id
        and p.year = extract(year from availabilities.date)
        and p.month = extract(month from availabilities.date)
        and p.status = 'open'
    )
  );

create policy "availabilities_update_member"
  on availabilities for update to authenticated
  using (
    user_id = auth.uid()
    and is_member(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from periods p
      where p.station_id = availabilities.station_id
        and p.year = extract(year from availabilities.date)
        and p.month = extract(month from availabilities.date)
        and p.status = 'open'
    )
  )
  with check (
    user_id = auth.uid()
    and is_member(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from periods p
      where p.station_id = availabilities.station_id
        and p.year = extract(year from availabilities.date)
        and p.month = extract(month from availabilities.date)
        and p.status = 'open'
    )
  );

create policy "availabilities_delete_member"
  on availabilities for delete to authenticated
  using (
    user_id = auth.uid()
    and is_member(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from periods p
      where p.station_id = availabilities.station_id
        and p.year = extract(year from availabilities.date)
        and p.month = extract(month from availabilities.date)
        and p.status = 'open'
    )
  );

create policy "availabilities_insert_admin"
  on availabilities for insert to authenticated
  with check (is_admin(station_id) and station_writable(station_id));

create policy "availabilities_update_admin"
  on availabilities for update to authenticated
  using (is_admin(station_id))
  with check (is_admin(station_id) and station_writable(station_id));

create policy "availabilities_delete_admin"
  on availabilities for delete to authenticated
  using (is_admin(station_id) and station_writable(station_id));

-- ---------------------------------------------------------------------------
-- availability_preferences — même logique, la période est référencée directement.
-- ---------------------------------------------------------------------------
create policy "availability_preferences_select_own_or_admin"
  on availability_preferences for select to authenticated
  using (user_id = auth.uid() or is_admin(station_id));

create policy "availability_preferences_insert_member"
  on availability_preferences for insert to authenticated
  with check (
    user_id = auth.uid()
    and is_member(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from periods p
      where p.id = availability_preferences.period_id
        and p.station_id = availability_preferences.station_id
        and p.status = 'open'
    )
  );

create policy "availability_preferences_update_member"
  on availability_preferences for update to authenticated
  using (
    user_id = auth.uid()
    and is_member(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from periods p
      where p.id = availability_preferences.period_id
        and p.station_id = availability_preferences.station_id
        and p.status = 'open'
    )
  )
  with check (
    user_id = auth.uid()
    and is_member(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from periods p
      where p.id = availability_preferences.period_id
        and p.station_id = availability_preferences.station_id
        and p.status = 'open'
    )
  );

create policy "availability_preferences_delete_member"
  on availability_preferences for delete to authenticated
  using (
    user_id = auth.uid()
    and is_member(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from periods p
      where p.id = availability_preferences.period_id
        and p.station_id = availability_preferences.station_id
        and p.status = 'open'
    )
  );

create policy "availability_preferences_insert_admin"
  on availability_preferences for insert to authenticated
  with check (is_admin(station_id) and station_writable(station_id));

create policy "availability_preferences_update_admin"
  on availability_preferences for update to authenticated
  using (is_admin(station_id))
  with check (is_admin(station_id) and station_writable(station_id));

create policy "availability_preferences_delete_admin"
  on availability_preferences for delete to authenticated
  using (is_admin(station_id) and station_writable(station_id));

-- ---------------------------------------------------------------------------
-- schedules — lecture : membre si status <> 'draft', admin toujours.
-- Écriture : admin.
-- ---------------------------------------------------------------------------
create policy "schedules_select_member_published"
  on schedules for select to authenticated
  using (is_member(station_id) and status <> 'draft');

create policy "schedules_select_admin"
  on schedules for select to authenticated
  using (is_admin(station_id));

create policy "schedules_insert_admin"
  on schedules for insert to authenticated
  with check (is_admin(station_id) and station_writable(station_id));

create policy "schedules_update_admin"
  on schedules for update to authenticated
  using (is_admin(station_id))
  with check (is_admin(station_id) and station_writable(station_id));

create policy "schedules_delete_admin"
  on schedules for delete to authenticated
  using (is_admin(station_id) and station_writable(station_id));

-- ---------------------------------------------------------------------------
-- shifts — lecture : membre si le planning est publié ou validé, admin toujours.
-- Écriture : admin.
-- ---------------------------------------------------------------------------
create policy "shifts_select_member_published"
  on shifts for select to authenticated
  using (
    is_member(station_id)
    and exists (
      select 1 from schedules s
      where s.id = shifts.schedule_id
        and s.status in ('published', 'validated')
    )
  );

create policy "shifts_select_admin"
  on shifts for select to authenticated
  using (is_admin(station_id));

create policy "shifts_insert_admin"
  on shifts for insert to authenticated
  with check (is_admin(station_id) and station_writable(station_id));

create policy "shifts_update_admin"
  on shifts for update to authenticated
  using (is_admin(station_id))
  with check (is_admin(station_id) and station_writable(station_id));

create policy "shifts_delete_admin"
  on shifts for delete to authenticated
  using (is_admin(station_id) and station_writable(station_id));

-- ---------------------------------------------------------------------------
-- assignments — lecture : les siennes si le planning est publié, toutes celles de
-- la caserne si le planning est validé, admin toutes.
-- Écriture membre : status seulement, de `proposed` vers `accepted` ou `declined`,
-- sur les siennes (le reste est verrouillé par le trigger ci-dessous).
-- ---------------------------------------------------------------------------
create policy "assignments_select_own_published"
  on assignments for select to authenticated
  using (
    user_id = auth.uid()
    and exists (
      select 1 from shifts sh
      join schedules sc on sc.id = sh.schedule_id
      where sh.id = assignments.shift_id
        and sc.status in ('published', 'validated')
    )
  );

create policy "assignments_select_station_validated"
  on assignments for select to authenticated
  using (
    is_member(station_id)
    and exists (
      select 1 from shifts sh
      join schedules sc on sc.id = sh.schedule_id
      where sh.id = assignments.shift_id
        and sc.status = 'validated'
    )
  );

create policy "assignments_select_admin"
  on assignments for select to authenticated
  using (is_admin(station_id));

create policy "assignments_update_member_response"
  on assignments for update to authenticated
  using (
    user_id = auth.uid()
    and status = 'proposed'
    and is_member(station_id)
    and station_writable(station_id)
  )
  with check (
    user_id = auth.uid()
    and status in ('accepted', 'declined')
  );

create policy "assignments_insert_admin"
  on assignments for insert to authenticated
  with check (is_admin(station_id) and station_writable(station_id));

create policy "assignments_update_admin"
  on assignments for update to authenticated
  using (is_admin(station_id))
  with check (is_admin(station_id) and station_writable(station_id));

create policy "assignments_delete_admin"
  on assignments for delete to authenticated
  using (is_admin(station_id) and station_writable(station_id));

-- ---------------------------------------------------------------------------
-- push_tokens — soi-même, lecture comme écriture.
-- ---------------------------------------------------------------------------
create policy "push_tokens_select_self"
  on push_tokens for select to authenticated
  using (user_id = auth.uid());

create policy "push_tokens_insert_self"
  on push_tokens for insert to authenticated
  with check (user_id = auth.uid());

create policy "push_tokens_update_self"
  on push_tokens for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "push_tokens_delete_self"
  on push_tokens for delete to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- notifications — lecture : soi-même. Écriture : `read_at` uniquement, via un
-- grant de colonne (pas de politique capable d'exprimer « cette colonne seule »).
-- L'insertion est réservée au service role (Edge Function send-notification).
-- ---------------------------------------------------------------------------
create policy "notifications_select_self"
  on notifications for select to authenticated
  using (user_id = auth.uid());

create policy "notifications_update_self_read_at"
  on notifications for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

revoke insert, update, delete, truncate on notifications from anon, authenticated;
grant update (read_at) on notifications to authenticated;

-- ---------------------------------------------------------------------------
-- subscriptions — lecture : admin de la caserne. Écriture : service role
-- (webhook Stripe) uniquement.
-- ---------------------------------------------------------------------------
create policy "subscriptions_select_admin"
  on subscriptions for select to authenticated
  using (is_admin(station_id));

revoke insert, update, delete, truncate on subscriptions from anon, authenticated;

-- ---------------------------------------------------------------------------
-- audit_log — lecture : admin de la caserne. Écriture : service role et triggers
-- (les triggers d'audit du ticket 019 seront `security definer`).
-- ---------------------------------------------------------------------------
create policy "audit_log_select_admin"
  on audit_log for select to authenticated
  using (is_admin(station_id));

revoke insert, update, delete, truncate on audit_log from anon, authenticated;

-- ---------------------------------------------------------------------------
-- super_admins — lecture : super-admin. Écriture : SQL manuel uniquement.
-- ---------------------------------------------------------------------------
create policy "super_admins_select_super_admin"
  on super_admins for select to authenticated
  using (is_super_admin());

revoke insert, update, delete, truncate on super_admins from anon, authenticated;

-- ===========================================================================
-- 5. Trigger : transition de statut d'une attribution par un membre
-- ===========================================================================
-- Écart assumé avec docs/SCHEMA.md section 4 : un garde-fou saute le contrôle pour
-- les rôles privilégiés (service_role, postgres, cron). Sans lui, publish-schedule
-- et reassign-shift, qui passent par le service role, seraient bloqués par
-- « invalid transition ». Voir docs/SCHEMA.md section 5.
create function assignments_member_transition() returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Écritures serveur : service role, migrations, cron, Edge Functions.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if is_admin(new.station_id) then return new; end if;

  if old.user_id <> auth.uid() then raise exception 'forbidden'; end if;

  if old.status <> 'proposed' or new.status not in ('accepted', 'declined') then
    raise exception 'invalid transition';
  end if;

  -- un membre ne modifie rien d'autre que status, responded_at, decline_reason
  if new.shift_id <> old.shift_id or new.user_id <> old.user_id then
    raise exception 'forbidden';
  end if;

  new.responded_at := now();
  return new;
end $$;

comment on function assignments_member_transition() is
  'Verrouille la réponse d''un membre à une attribution : proposed -> accepted|declined, sur ses propres lignes, sans toucher à shift_id ni user_id.';

-- Nommé pour passer avant assignments_set_updated_at (ordre alphabétique).
create trigger assignments_member_transition
  before update on assignments
  for each row execute function assignments_member_transition();

revoke execute on function assignments_member_transition() from public, anon, authenticated;
