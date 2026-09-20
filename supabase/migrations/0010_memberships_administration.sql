-- 0010 — Administration des membres : garde-fous serveur et dernière saisie.
-- Référence : docs/SCHEMA.md sections 2.3, 2.6, 5 et 6. Ticket 009.
--
-- Ce que 0007 et 0008 laissent passer
-- -----------------------------------
-- `memberships_update_admin` autorise un admin à écrire toutes les lignes de sa
-- caserne, et ne refuse qu'une chose : qu'il change son **propre rôle**
-- (`user_id <> auth.uid() or role = 'admin'`). Deux trous restent ouverts :
--
--   1. un admin met son propre `status` à `disabled` — la clause `with check` ne
--      regarde que `role`. Il se ferme lui-même la porte, sans recours dans l'app ;
--   2. un admin rétrograde ou désactive **le dernier autre admin** de la caserne.
--      La caserne se retrouve sans administrateur : plus personne ne publie de
--      planning, n'invite, ne réactive. Aucune politique RLS ne sait exprimer
--      « il doit rester au moins une ligne qui… » : c'est une contrainte sur
--      l'ensemble de la table, pas sur la ligne écrite. D'où un déclencheur.
--
-- Le déclencheur laisse passer le rôle de service, exactement comme
-- `assignments_member_transition()` (0008) : `accept_invitation`, les migrations, le
-- cron et les Edge Functions doivent pouvoir écrire sans être arbitrés par une règle
-- écrite pour l'interface d'administration.
--
-- Pourquoi la fonction n'est **pas** `security definer` : dans une fonction
-- `security definer`, `current_user` vaut le propriétaire (postgres) et le test
-- « est-ce une écriture serveur ? » répondrait toujours oui. Le comptage des admins
-- restants est donc fait sous la RLS de l'appelant — ce qui est exact, puisque
-- `memberships_select_station_or_self` montre à un admin **toutes** les lignes de sa
-- caserne. Dans le pire des cas (une politique future plus étroite), le comptage
-- sous-estime et le déclencheur refuse : il échoue fermé.

-- ===========================================================================
-- 1. Déclencheur : il reste toujours un admin actif, et on ne se retire pas soi-même
-- ===========================================================================
create function memberships_guard_admin() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  suppression constant boolean := (tg_op = 'DELETE');
  perd_admin boolean;
  restants integer;
begin
  -- `disabled_at` suit le statut, quel que soit l'auteur de l'écriture : la date de
  -- sortie est une donnée du dossier (docs/SCHEMA.md § 2.3), pas un champ que
  -- l'interface pense à renseigner.
  if not suppression and new.status is distinct from old.status then
    new.disabled_at := case when new.status = 'disabled' then now() else null end;
  end if;

  -- Écritures serveur : service role, migrations, cron, Edge Functions.
  if current_user not in ('authenticated', 'anon') then
    if suppression then return old; else return new; end if;
  end if;

  -- Seule la perte d'un admin actif est arbitrée ici. Renommer, promouvoir,
  -- réactiver : rien à protéger.
  if old.role <> 'admin' or old.status <> 'active' then
    if suppression then return old; else return new; end if;
  end if;

  perd_admin := suppression or new.role <> 'admin' or new.status <> 'active';
  if not perd_admin then return new; end if;

  select count(*) into restants
  from memberships m
  where m.station_id = old.station_id
    and m.id <> old.id
    and m.role = 'admin'
    and m.status = 'active';

  -- « Dernier admin » avant « soi-même », et dans cet ordre : le seul appelant qui
  -- puisse atteindre ce code est un admin actif de la caserne, donc `restants = 0`
  -- implique qu'il se vise lui-même. C'est le cas réel du chef de centre seul à bord,
  -- et c'est la phrase « nomme quelqu'un d'abord » qui l'aide, pas « demande à un
  -- autre administrateur » — il n'y en a pas.
  if restants = 0 then
    raise exception 'membership_last_admin'
      using hint = 'Une caserne garde au moins un administrateur actif.';
  end if;

  -- Soi-même, alors qu'un autre admin existe. La RLS couvre déjà le changement de
  -- rôle ; elle ne couvre ni la désactivation ni la suppression de sa propre ligne.
  if old.user_id = auth.uid() then
    raise exception 'membership_self_admin_change'
      using hint = 'Un administrateur ne peut pas retirer son propre accès.';
  end if;

  if suppression then return old; else return new; end if;
end $$;

comment on function memberships_guard_admin() is
  'Refuse la rétrogradation, la désactivation ou la suppression du dernier administrateur actif d''une caserne, et celles qu''un administrateur s''appliquerait à lui-même. Laisse passer le rôle de service. Tient aussi disabled_at à jour.';

-- Une fonction de déclencheur n'a rien à faire dans l'API : comme pour
-- set_updated_at et handle_new_user (0007), l'exécution est révoquée des rôles
-- clients. `api.auto_expose_new_tables` pose des grants nominatifs sur anon et
-- authenticated que `revoke from public` ne retire pas : ils sont nommés.
revoke execute on function memberships_guard_admin() from public, anon, authenticated;

-- `before` : refuser avant d'écrire, et pouvoir corriger `disabled_at` dans `new`.
-- `for each row` sur update et delete — un insert ne peut pas retirer un admin.
create trigger memberships_guard_admin
  before update or delete on memberships
  for each row execute function memberships_guard_admin();

-- ===========================================================================
-- 2. Vue : dernière saisie de disponibilités par membre
-- ===========================================================================
-- L'écran « Membres » affiche, par membre, la date de la ligne de `availabilities`
-- la plus récemment écrite pour cette caserne. Sans cette vue il faudrait rapatrier
-- toutes les lignes du mois (60 membres × 62 créneaux) pour n'en garder qu'un
-- maximum par membre : les agrégats PostgREST sont désactivés sur ce projet
-- (`PGRST123`), et le groupement doit donc vivre dans la base.
--
-- `security_invoker` : la vue n'accorde aucun droit nouveau, elle est lue sous la
-- RLS de `availabilities` (`availabilities_select_own_or_admin`). Un admin y voit sa
-- caserne, un membre n'y voit que lui-même, `anon` rien.
create view v_member_last_availability
with (security_invoker = true) as
  select station_id,
         user_id,
         max(updated_at) as last_set_at
  from availabilities
  group by station_id, user_id;

comment on view v_member_last_availability is
  'Par (caserne, membre) : date de la ligne de disponibilité la plus récemment écrite. security_invoker : lue sous la RLS de availabilities.';

revoke all on v_member_last_availability from anon;
grant select on v_member_last_availability to authenticated;
