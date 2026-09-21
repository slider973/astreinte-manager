-- 0026 — Suppression de compte : anonymiser sans jamais effacer l'histoire.
-- Référence : docs/PRD.md § 7 règle 6 et § 8 (RGPD), docs/SCHEMA.md § 2.2, 2.3,
-- 2.10, 3 et 7, design/007-profil.md § 5.3 et 5.4. Ticket 007.
--
-- Le mur que cette migration abat
-- -------------------------------
-- `profiles.id references auth.users(id) on delete cascade` (0002) et
-- `assignments.user_id references profiles(id) on delete cascade` (0004) forment
-- une chaîne : supprimer le compte d'authentification efface le profil, qui
-- efface **les attributions passées**. Le critère du ticket — « la suppression
-- conserve les attributions passées sous “Membre supprimé” » — était donc
-- inatteignable tant que la première contrainte existait, et le produit se
-- serait contredit lui-même (« l'historique n'est jamais supprimé »).
--
-- La contrainte est retirée, pas assouplie : il n'existe pas d'action référentielle
-- qui dise « garde la ligne fille en effaçant ce qu'elle a de nominatif ».
-- `set null` est impossible (la colonne est la clé primaire), `restrict` bloquerait
-- la suppression du compte auth qu'on veut justement obtenir.
--
-- Ce qu'on perd : la garantie qu'un `profiles.id` désigne un compte joignable.
-- C'est exactement l'état qu'on cherche à produire. La création reste, elle,
-- impossible à falsifier : `handle_new_user` est le seul chemin nominal, et
-- `profiles_insert_self` n'autorise que `id = auth.uid()`.
--
-- Aucune colonne n'est ajoutée. `first_name`, `last_name`, `email` et `phone`
-- portent déjà tout ce qu'il faut pour écrire « Membre supprimé », et le fait de
-- la suppression est tracé là où le produit trace tout le reste : `audit_log`
-- pour la caserne, `memberships.status = 'disabled'` + `disabled_at` pour l'état.

-- ===========================================================================
-- 1. Le profil survit à son compte d'authentification
-- ===========================================================================
alter table profiles drop constraint profiles_id_fkey;

comment on column profiles.id is
  'auth.users.id à la création (trigger handle_new_user). Aucune contrainte de clé étrangère : un profil anonymisé survit à la suppression de son compte d''authentification, c''est ce qui reste du membre dans l''histoire de la caserne (migration 0026, ticket 007).';

-- ===========================================================================
-- 2. delete_own_account — anonymise, désactive, efface le personnel
-- ===========================================================================
-- Appelée par l'Edge Function `delete-account` **avec l'identifiant tiré du JWT**,
-- jamais du corps de la requête. Elle n'est donc pas ouverte à `authenticated` :
-- même règle que `accept_invitation` (0009), et pour la même raison — un paramètre
-- `p_user_id` exposé aux clients serait une porte pour supprimer le compte d'un
-- autre.
--
-- Trois catégories, et la frontière est le produit, pas la technique :
--
--   - **ce qui reste, anonymisé** : le profil et ses appartenances. `assignments`
--     y pend, et c'est l'histoire de la caserne — qui était d'astreinte le 14
--     juillet reste une question à laquelle la base doit savoir répondre
--     (`docs/PRD.md § 8`, « les astreintes restent pour les statistiques ») ;
--   - **ce qui part** : disponibilités, préférences de charge, appareils,
--     notifications reçues, invitations en attente à son adresse. Ce sont ses
--     données à lui, elles ne décrivent aucune garde tenue ;
--   - **ce qui ne bouge pas** : `audit_log.actor_id`, `assignments.created_by`,
--     `schedules.created_by`, `invitations.invited_by`, `availabilities.set_by`.
--     Ces colonnes désignent maintenant un profil anonyme — c'est précisément le
--     comportement voulu, et c'est pourquoi aucune d'elles n'est en cascade.
--
-- Retour : `{"ok": true, "stations": [...], "memberships": n}` ou
-- `{"ok": false, "code": "...", "station": "..."}`. Jamais d'exception pour un
-- refus métier : l'Edge Function doit pouvoir traduire le code en phrase française.
create function delete_own_account(p_user_id uuid) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email      text;
  v_caserne    record;
  v_stations   uuid[] := array[]::uuid[];
  v_appartenances integer;
begin
  select email into v_email from profiles where id = p_user_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'profile_missing');
  end if;

  -- ------------------------------------------------------------------
  -- Garde : une caserne ne se retrouve pas sans administrateur
  -- ------------------------------------------------------------------
  -- `memberships_guard_admin` (0010) laisse passer les écritures serveur, et
  -- celle-ci en est une : la règle doit donc être rejouée ici, explicitement.
  -- Sans elle, le chef de centre seul à bord emporte sa caserne en partant —
  -- plus personne pour publier un planning, et personne ne s'en aperçoit avant
  -- le mois suivant.
  for v_caserne in
    select m.station_id, s.name
    from memberships m
    join stations s on s.id = m.station_id
    where m.user_id = p_user_id
      and m.role = 'admin'
      and m.status = 'active'
  loop
    if not exists (
      select 1 from memberships autre
      where autre.station_id = v_caserne.station_id
        and autre.user_id <> p_user_id
        and autre.role = 'admin'
        and autre.status = 'active'
    ) then
      return jsonb_build_object(
        'ok', false,
        'code', 'last_admin',
        'station', v_caserne.name
      );
    end if;
  end loop;

  select array_agg(station_id) into v_stations
  from memberships where user_id = p_user_id;
  v_stations := coalesce(v_stations, array[]::uuid[]);

  -- ------------------------------------------------------------------
  -- La trace, écrite **avant** l'anonymisation
  -- ------------------------------------------------------------------
  -- `actor_id` désigne le profil, qui existe encore et existera toujours ; ce
  -- qu'on ne garde pas, c'est son nom dans `data`. Une trace RGPD qui recopierait
  -- l'adresse supprimée annulerait la suppression.
  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  select m.station_id, p_user_id, 'account.deleted', 'profile', p_user_id,
         jsonb_build_object('role', m.role, 'status', m.status)
  from memberships m
  where m.user_id = p_user_id;

  -- ------------------------------------------------------------------
  -- Ce qui part
  -- ------------------------------------------------------------------
  delete from push_tokens              where user_id = p_user_id;
  delete from notifications            where user_id = p_user_id;
  delete from availabilities           where user_id = p_user_id;
  delete from availability_preferences where user_id = p_user_id;
  delete from super_admins             where user_id = p_user_id;
  -- Une invitation en attente porte l'adresse supprimée, et plus personne ne
  -- pourra l'accepter : le compte qui l'a reçue n'existera plus.
  delete from invitations
  where accepted_at is null and lower(email) = lower(v_email);

  -- ------------------------------------------------------------------
  -- Ce qui reste, anonymisé
  -- ------------------------------------------------------------------
  -- « Membre supprimé » est composé de `first_name` et `last_name` parce que
  -- c'est ainsi que l'application compose un nom partout ailleurs
  -- (`MembreCaserne.libelle`, `AttributionSuivi._nom`) : rien à changer côté
  -- écran pour que la mention apparaisse.
  --
  -- L'adresse est une constante non routable (`.invalid`, RFC 2606), identique
  -- pour tous les comptes supprimés : rien ne s'y raccroche, et `profiles.email`
  -- n'a pas d'index unique.
  update profiles set
    first_name   = 'Membre',
    last_name    = 'supprimé',
    email        = 'supprime@astreinte.invalid',
    phone        = null,
    push_enabled = false
  where id = p_user_id;

  -- Le surnom de caserne est un nom, lui aussi. `disabled_at` est posé par
  -- `memberships_guard_admin`, qui suit le statut quel que soit l'auteur.
  update memberships set
    status       = 'disabled',
    display_name = null
  where user_id = p_user_id;
  get diagnostics v_appartenances = row_count;

  return jsonb_build_object(
    'ok', true,
    'stations', to_jsonb(v_stations),
    'memberships', v_appartenances
  );
end $$;

comment on function delete_own_account(uuid) is
  'Suppression de compte (ticket 007) : anonymise le profil en « Membre supprimé », désactive ses appartenances, efface disponibilités, préférences, appareils, notifications et invitations en attente. Les attributions passées restent. Refuse si l''appelant est le dernier administrateur actif d''une caserne. Réservée au rôle de service : l''identité vient du JWT, pas du paramètre.';

-- Une fonction qui prend un `user_id` en paramètre n'a rien à faire dans l'API
-- cliente. `revoke from public` ne suffit pas : `api.auto_expose_new_tables`
-- pose des grants nominatifs sur anon et authenticated (voir 0009).
revoke all on function delete_own_account(uuid) from public, anon, authenticated;
grant execute on function delete_own_account(uuid) to service_role;
