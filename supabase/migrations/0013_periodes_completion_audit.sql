-- 0013 — Taux de saisie en base, cycle de vie d'une période tracé de bout en
-- bout, date limite qui ne recule plus dans le passé. Revue du ticket 014.
-- Référence : docs/SCHEMA.md sections 2.5, 5, 6 et 8 ; docs/WORKFLOWS.md § 1.
--
-- Trois défauts trouvés en revue, tous en base.
--
-- 1. Le taux de saisie était faux sans le dire
-- --------------------------------------------
-- L'écran « Périodes » comptait les membres ayant saisi en rapatriant la colonne
-- `user_id` des disponibilités du mois, puis en comptant les valeurs distinctes.
-- PostgREST plafonne une réponse à mille lignes (`db-max-rows`) et rend **200**,
-- sans en-tête d'alerte : rien, dans la réponse, ne dit qu'elle est tronquée.
--
-- Un mois plein coûte ~62 lignes par membre (31 jours × 2 créneaux). Le compte
-- devient donc faux à partir de 17 membres et plafonne autour de 16 quel que
-- soit l'effectif réel. Pour la caserne de 60 membres de `PRODUCT.md`, l'écran
-- affichait « 16 membres sur 60 ont saisi » alors que les 60 avaient saisi — et
-- l'admin rouvrait un mois qui n'avait aucune raison de l'être. Une erreur de
-- lecture qui provoque une mauvaise décision, sans jamais lever d'exception :
-- c'est le pire genre.
--
-- Le compte descend donc en base, dans la vue `v_period_completion` que
-- `design/014 § 7` annonçait pour le ticket 016. Sous sa forme définitive tout
-- de suite : une ligne par période, deux nombres, rien à recalculer ensuite.
--
-- 2. La trace de réouverture se contournait sans rien laisser
-- -----------------------------------------------------------
-- 0012 refuse de rouvrir une période sans repousser sa date limite, et journalise
-- toute réouverture. Mais un admin pouvait *supprimer* la période, la recréer par
-- `create_period`, puis repousser sa date limite : le mois se retrouvait ouvert et
-- `audit_log` restait vide. Rien ne rattachant les disponibilités à la période
-- (`availabilities` porte une date, pas un `period_id`), la manœuvre ne coûtait
-- même pas les données saisies.
--
-- C'est exactement l'exigence que 0012 défend pour `availabilities.set_by` :
-- ce qui est sensible doit résister à celui qui a les droits. La suppression et
-- la création d'une période sont donc journalisées comme l'est la réouverture.
-- La suppression reste permise — un admin doit pouvoir défaire un mois ouvert par
-- erreur — mais elle n'est plus silencieuse, et la trace compte les
-- disponibilités du mois qui lui survivent, ce qui rend la manœuvre lisible.
--
-- 3. Une date limite pouvait reculer dans le passé
-- ------------------------------------------------
-- 0012 interdit de *rouvrir* avec une date limite passée. Rien n'empêchait de
-- ramener dans le passé la date limite d'une période **déjà ouverte** : le mois
-- restait affiché comme ouvert, refusait les écritures au prochain regard, et se
-- verrouillait à l'heure ronde suivante. Même raisonnement, même refus.

-- ===========================================================================
-- 1. v_period_completion — le taux de saisie d'un mois
-- ===========================================================================
-- Une ligne par période, toujours : une caserne sans membre actif y figure avec
-- 0 et 0, parce que l'écran doit pouvoir dire « aucun membre actif » plutôt que
-- d'afficher une ligne vide ou « 0 % ».
--
-- `active_members` est le dénominateur : les appartenances `active` de la
-- caserne. Un membre désactivé ne le gonfle pas — et, comme le numérateur se
-- construit **à partir** de ce même ensemble, un pompier désactivé depuis qu'il a
-- saisi ne produit pas non plus « 10 membres sur 9 », qui était l'autre piège du
-- comptage côté client.
--
-- `members_with_availability` compte ceux qui ont au moins une ligne sur le mois,
-- par `exists` et non par `count(distinct)` : la question est « a-t-il saisi ? »,
-- pas « combien de créneaux ? ». L'index `availabilities (user_id, date)` la
-- tranche sans lire les 62 lignes.
--
-- `security_invoker` : la vue n'accorde aucun droit, elle est lue sous la RLS de
-- celui qui la lit, comme `v_member_last_availability` (0010).
--
--   - un **admin** lit `availabilities_select_own_or_admin` branche `is_admin` :
--     les deux nombres sont justes, et c'est son écran ;
--   - un **membre** ne voit dans `availabilities` que ses propres lignes : son
--     numérateur vaut 0 ou 1, selon qu'il a saisi. Ce n'est pas une fuite, c'est
--     une vue partielle — il n'apprend rien qu'il ne puisse déjà lire ligne à
--     ligne. L'écran qui consomme cette vue est réservé aux admins ;
--   - `anon` n'a aucune politique et ne lit rien.
create view v_period_completion
with (security_invoker = true) as
  select
    p.id         as period_id,
    p.station_id as station_id,
    p.year       as year,
    p.month      as month,
    count(m.user_id)                          as active_members,
    count(*) filter (where saisie.a_saisi)    as members_with_availability
  from periods p
  left join memberships m
    on m.station_id = p.station_id
   and m.status = 'active'
  left join lateral (
    select exists (
      select 1
      from availabilities a
      where a.user_id = m.user_id
        and a.station_id = p.station_id
        and a.date >= make_date(p.year, p.month, 1)
        and a.date <  (make_date(p.year, p.month, 1) + interval '1 month')::date
    ) as a_saisi
  ) saisie on true
  group by p.id, p.station_id, p.year, p.month;

comment on view v_period_completion is
  'Par période : nombre de membres actifs de la caserne et nombre de ceux qui ont saisi au moins un créneau du mois. security_invoker : les deux nombres ne sont justes que pour un admin, seul à lire toutes les disponibilités de sa caserne.';

revoke all on v_period_completion from anon;
grant select on v_period_completion to authenticated;

-- ===========================================================================
-- 2. Une date limite ne recule pas dans le passé
-- ===========================================================================
-- `create or replace` : la fonction de 0012, plus une règle. Les privilèges
-- révoqués survivent au remplacement, ils sont repris plus bas par prudence.
--
-- La règle ne s'applique qu'aux écritures **clients** (`authenticated`, `anon`).
-- Le recalcul des dates limites de 0011 (`stations_recalcule_deadlines`) est
-- `security definer` : `current_user` y vaut le propriétaire de la fonction, et
-- il passe donc à travers — volontairement. Un admin qui ramène le jour limite de
-- sa caserne du 25 au 5 alors qu'on est le 10 décide de fermer les mois en cours,
-- et refuser son réglage entier pour une période dérivée serait un contresens :
-- la tâche horaire verrouillera, ce qui est la bonne suite. Ce que l'on refuse,
-- c'est une date limite **écrite directement sur une période**, qui ne peut être
-- qu'une erreur de saisie ou une réouverture déguisée.
create or replace function periods_guard_transition() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.station_id <> old.station_id
     or new.year <> old.year
     or new.month <> old.month then
    raise exception 'period_key_immutable'
      using hint = 'La caserne et le mois d''une période ne se modifient pas : créer la bonne période et supprimer l''autre.';
  end if;

  if old.status = 'open' and new.status = 'locked' then
    new.locked_at := coalesce(new.locked_at, now());

  elsif old.status = 'locked' and new.status = 'open' then
    if new.deadline_at <= now() then
      raise exception 'period_reopen_deadline_passed'
        using hint = 'Rouvrir une période demande de repousser sa date limite : sinon la tâche horaire la reverrouille dans l''heure.';
    end if;
    new.locked_at := null;

  elsif old.status = 'open' and new.status = 'open'
        and new.deadline_at is distinct from old.deadline_at
        and new.deadline_at <= now()
        and current_user in ('authenticated', 'anon') then
    -- Un mois ouvert dont la date limite est déjà passée n'existe que jusqu'à
    -- l'heure ronde suivante : l'écran l'annonce ouvert, la base refuse les
    -- écritures des membres, et la tâche le referme. Autant le refuser ici.
    raise exception 'period_deadline_in_past'
      using hint = 'La date limite d''un mois ouvert doit rester dans le futur : pour fermer ce mois, le verrouiller.';
  end if;

  return new;
end $$;

comment on function periods_guard_transition() is
  'Tient locked_at à jour, gèle la clé (caserne, année, mois), refuse une réouverture dont la date limite est déjà passée et une date limite ramenée dans le passé sur un mois ouvert (docs/WORKFLOWS.md § 1).';

revoke execute on function periods_guard_transition() from public, anon, authenticated;

-- ===========================================================================
-- 3. Création et suppression d'une période : tracées comme la réouverture
-- ===========================================================================
create function periods_audit_cycle_de_vie() returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  survivantes integer;
begin
  if tg_op = 'INSERT' then
    insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
    values (
      new.station_id, auth.uid(), 'period.created', 'period', new.id,
      jsonb_build_object(
        'year', new.year, 'month', new.month,
        'status', new.status, 'deadline_at', new.deadline_at)
    );
    return null;
  end if;

  -- Supprimer une caserne emporte ses périodes en cascade. La ligne d'audit
  -- référencerait alors une caserne déjà disparue : la clé étrangère de
  -- `audit_log.station_id` échouerait et bloquerait la suppression entière.
  if not exists (select 1 from stations where id = old.station_id) then
    return null;
  end if;

  -- Rien ne rattache une disponibilité à une période : supprimer le mois ne
  -- supprime pas les saisies. Les compter rend la manœuvre lisible dans le
  -- journal — « il a supprimé un mois que 47 personnes avaient rempli » n'est
  -- pas la même phrase que « il a supprimé un mois vide ».
  select count(*) into survivantes
    from availabilities a
   where a.station_id = old.station_id
     and a.date >= make_date(old.year, old.month, 1)
     and a.date <  (make_date(old.year, old.month, 1) + interval '1 month')::date;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    old.station_id, auth.uid(), 'period.deleted', 'period', old.id,
    jsonb_build_object(
      'year', old.year, 'month', old.month,
      'status', old.status,
      'deadline_at', old.deadline_at,
      'locked_at', old.locked_at,
      'disponibilites_conservees', survivantes)
  );
  return null;
end $$;

comment on function periods_audit_cycle_de_vie() is
  'Journalise period.created et period.deleted. Sans elle, supprimer puis recréer une période rouvrait un mois verrouillé sans laisser de trace (revue du ticket 014).';

revoke execute on function periods_audit_cycle_de_vie() from public, anon, authenticated;

-- `when (auth.uid() is not null)` : la tâche `create_periods` et le seed créent
-- des périodes par dizaines sans acteur humain. Le journal d'audit est celui des
-- actions des administrateurs (docs/SCHEMA.md § 2.14), pas celui de la machine.
create trigger periods_audit_creation
  after insert on periods
  for each row
  when (auth.uid() is not null)
  execute function periods_audit_cycle_de_vie();

-- Pas de clause `when` sur la suppression : une suppression faite en SQL par un
-- opérateur, sans `auth.uid()`, doit laisser une ligne elle aussi. C'est une
-- perte de données, elle se trace toujours.
create trigger periods_audit_suppression
  after delete on periods
  for each row execute function periods_audit_cycle_de_vie();
