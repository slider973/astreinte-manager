-- 0008 — Durcissement des politiques RLS posées en 0007 (revue du ticket 008).
-- Référence : docs/SCHEMA.md sections 3, 4 et 5.
--
-- Quatre failles trouvées en revue, toutes reproduites sur la base locale :
--
--   1. Escalade de privilèges par `pg_temp`. Quand `pg_temp` n'est pas nommé dans le
--      `search_path` d'une fonction, PostgreSQL le consulte *en premier*. Un rôle
--      `authenticated` créait `pg_temp.memberships`, y insérait une ligne `admin` et
--      `is_admin()` renvoyait `true` pour n'importe quelle caserne. Correction :
--      `set search_path = public, pg_temp` sur toutes les fonctions, `pg_temp` en
--      dernière position.
--
--   2. Un membre déplaçait son attribution dans une autre caserne : le `with check` de
--      `assignments_update_member_response` ne contrôlait pas `station_id`.
--
--   3. Le trigger ne gelait que `shift_id` et `user_id`. Un membre écrivait
--      `was_available`, `reminder_count`, `proposed_at` ou `replaced_by` en même temps
--      qu'une transition valide, et sortait ainsi du rapport des retardataires (ticket
--      022). Le contrôle passe d'une liste noire à une liste blanche.
--
--   4. Aucune politique ne vérifiait la caserne de la ligne parente. Un admin de A
--      insérait un créneau dans un planning de B, ou une attribution visant un membre de
--      B. Les politiques d'écriture contrôlent maintenant la cohérence du `station_id`
--      avec celui du parent (`schedule_id`, `shift_id`, `period_id`, `user_id`).
--
-- Les politiques RLS ne sont pas concernées par la faille 1 : leur expression est
-- analysée à la création et stockée avec les OID résolus, comme une vue. Un test de
-- non-régression le vérifie quand même (`pg_temp.periods` ne déverrouille pas une
-- période `locked`).

-- ===========================================================================
-- 1. search_path : pg_temp nommé explicitement, en dernier
-- ===========================================================================
-- 0002 est déjà sur main : handle_new_user et set_updated_at sont corrigés par alter.
alter function set_updated_at()                set search_path = public, pg_temp;
alter function handle_new_user()               set search_path = public, pg_temp;
alter function is_member(uuid)                 set search_path = public, pg_temp;
alter function is_admin(uuid)                  set search_path = public, pg_temp;
alter function is_super_admin()                set search_path = public, pg_temp;
alter function station_writable(uuid)          set search_path = public, pg_temp;

-- ===========================================================================
-- 2 et 3. Trigger de transition : liste blanche de colonnes, station_id gelé
-- ===========================================================================
create or replace function assignments_member_transition() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  -- Colonnes qu'un membre a le droit de voir changer en répondant.
  colonnes_libres constant text[] := array['status', 'responded_at', 'decline_reason', 'updated_at'];
  gele_avant jsonb;
  gele_apres jsonb;
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

  -- Contrôles explicites, pour un message d'erreur lisible sur les cas les plus graves.
  if new.station_id <> old.station_id
     or new.shift_id <> old.shift_id
     or new.user_id <> old.user_id then
    raise exception 'forbidden';
  end if;

  new.responded_at := now();

  -- Liste blanche : toute autre colonne modifiée (was_available, reminder_count,
  -- proposed_at, replaced_by, last_reminder_at, created_by…) est refusée.
  gele_avant := to_jsonb(old) - colonnes_libres;
  gele_apres := to_jsonb(new) - colonnes_libres;
  if gele_apres is distinct from gele_avant then
    raise exception 'forbidden';
  end if;

  return new;
end $$;

comment on function assignments_member_transition() is
  'Verrouille la réponse d''un membre à une attribution : proposed -> accepted|declined, sur ses propres lignes, sans modifier aucune colonne hors status, responded_at et decline_reason.';

-- ===========================================================================
-- 2 et amélioration 1. Politique de réponse d'un membre
-- ===========================================================================
-- using : la caserne et le planning sont vérifiés, un membre ne répond pas à
--   l'aveugle à une attribution d'un planning `draft` qu'il ne peut pas lire.
--   (Sans clause where citant une colonne, un update ne déclenche pas les politiques
--   de select : la condition doit être portée par la politique d'update elle-même.)
-- with check : la ligne reste dans la même caserne, dont le membre est membre.
drop policy "assignments_update_member_response" on assignments;

create policy "assignments_update_member_response"
  on assignments for update to authenticated
  using (
    user_id = auth.uid()
    and status = 'proposed'
    and is_member(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from shifts sh
      join schedules sc on sc.id = sh.schedule_id
      where sh.id = assignments.shift_id
        and sh.station_id = assignments.station_id
        and sc.status in ('published', 'validated')
    )
  )
  with check (
    user_id = auth.uid()
    and status in ('accepted', 'declined')
    and is_member(station_id)
    and station_writable(station_id)
  );

-- ===========================================================================
-- 4. Cohérence du station_id avec la ligne parente
-- ===========================================================================

-- schedules : la période appartient à la même caserne.
drop policy "schedules_insert_admin" on schedules;
create policy "schedules_insert_admin"
  on schedules for insert to authenticated
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from periods p
      where p.id = schedules.period_id and p.station_id = schedules.station_id
    )
  );

drop policy "schedules_update_admin" on schedules;
create policy "schedules_update_admin"
  on schedules for update to authenticated
  using (is_admin(station_id))
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from periods p
      where p.id = schedules.period_id and p.station_id = schedules.station_id
    )
  );

-- shifts : le planning appartient à la même caserne.
drop policy "shifts_insert_admin" on shifts;
create policy "shifts_insert_admin"
  on shifts for insert to authenticated
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from schedules s
      where s.id = shifts.schedule_id and s.station_id = shifts.station_id
    )
  );

drop policy "shifts_update_admin" on shifts;
create policy "shifts_update_admin"
  on shifts for update to authenticated
  using (is_admin(station_id))
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from schedules s
      where s.id = shifts.schedule_id and s.station_id = shifts.station_id
    )
  );

-- assignments : le créneau et le membre appartiennent à la même caserne.
-- Le membre est cherché sans filtre de statut : une attribution reste modifiable
-- après la désactivation du membre (annulation, remplacement).
drop policy "assignments_insert_admin" on assignments;
create policy "assignments_insert_admin"
  on assignments for insert to authenticated
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from shifts sh
      where sh.id = assignments.shift_id and sh.station_id = assignments.station_id
    )
    and exists (
      select 1 from memberships m
      where m.user_id = assignments.user_id and m.station_id = assignments.station_id
    )
  );

drop policy "assignments_update_admin" on assignments;
create policy "assignments_update_admin"
  on assignments for update to authenticated
  using (is_admin(station_id))
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from shifts sh
      where sh.id = assignments.shift_id and sh.station_id = assignments.station_id
    )
    and exists (
      select 1 from memberships m
      where m.user_id = assignments.user_id and m.station_id = assignments.station_id
    )
  );

-- availabilities : l'admin n'écrit que pour un membre de sa caserne.
drop policy "availabilities_insert_admin" on availabilities;
create policy "availabilities_insert_admin"
  on availabilities for insert to authenticated
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from memberships m
      where m.user_id = availabilities.user_id and m.station_id = availabilities.station_id
    )
  );

drop policy "availabilities_update_admin" on availabilities;
create policy "availabilities_update_admin"
  on availabilities for update to authenticated
  using (is_admin(station_id))
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from memberships m
      where m.user_id = availabilities.user_id and m.station_id = availabilities.station_id
    )
  );

-- availability_preferences : la période et le membre appartiennent à la même caserne.
drop policy "availability_preferences_insert_admin" on availability_preferences;
create policy "availability_preferences_insert_admin"
  on availability_preferences for insert to authenticated
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from periods p
      where p.id = availability_preferences.period_id
        and p.station_id = availability_preferences.station_id
    )
    and exists (
      select 1 from memberships m
      where m.user_id = availability_preferences.user_id
        and m.station_id = availability_preferences.station_id
    )
  );

drop policy "availability_preferences_update_admin" on availability_preferences;
create policy "availability_preferences_update_admin"
  on availability_preferences for update to authenticated
  using (is_admin(station_id))
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from periods p
      where p.id = availability_preferences.period_id
        and p.station_id = availability_preferences.station_id
    )
    and exists (
      select 1 from memberships m
      where m.user_id = availability_preferences.user_id
        and m.station_id = availability_preferences.station_id
    )
  );

-- ===========================================================================
-- Amélioration 2. Le token d'invitation n'est pas lisible par l'API
-- ===========================================================================
-- Le commentaire de 0007 affirmait que le token n'était jamais lisible par
-- `authenticated` ; c'était faux, `invitations_select_admin` exposait toutes les
-- colonnes. Le token est un porteur de droits : seul le service role (Edge Functions
-- invite-member et accept-invitation) doit le voir. Conséquence côté client : ne
-- jamais faire `select *` sur invitations, toujours énumérer les colonnes.
revoke select on invitations from anon, authenticated;
grant select (id, station_id, email, role, invited_by, expires_at, accepted_at, created_at)
  on invitations to authenticated;

comment on column invitations.token is
  'Porteur de droits. Non lisible par le rôle authenticated (grant de colonne) : seul le service role y accède.';
