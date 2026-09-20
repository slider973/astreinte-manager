-- 0012 — Cycle de vie des périodes : création mensuelle, verrouillage horaire,
-- réouverture tracée et saisie d'un admin pour un membre. Ticket 014.
-- Référence : docs/SCHEMA.md sections 2.5, 2.6, 3, 5 et 8 ; docs/WORKFLOWS.md 1 et 7.
--
-- Ce qui existait déjà et n'est pas réécrit
-- -----------------------------------------
--   - `period_deadline_at(year, month, jour, fuseau)` (0011) : la règle de la date
--     limite, jour limite du mois précédent à 23:59:59 dans le fuseau de la
--     caserne. Elle borne déjà le jour au dernier jour du mois précédent, ce qui
--     règle le cas d'un jour limite absent d'un mois court (30 → 28 en février).
--   - `periods_update_admin` / `periods_insert_admin` (0007) : un admin verrouille
--     et rouvre déjà une période de sa caserne. La réouverture était **permise**
--     mais **non tracée** : c'est ce qui manquait.
--   - `availabilities_insert_admin` / `availabilities_update_admin` (0007, durcies
--     par 0008) : un admin écrit déjà pour un membre de sa caserne, période
--     verrouillée ou non. Manquaient la trace de l'auteur dans `set_by` et
--     l'entrée d'audit.
--
-- Ce que cette migration ajoute
-- -----------------------------
--   1. `cron_create_periods(instant)` et `cron_lock_periods(instant)`, les deux
--      corps des tâches de docs/SCHEMA.md § 8, paramétrés par une date de
--      référence pour être testables sans attendre un mois.
--   2. `create_period(caserne, année, mois)`, l'action « créer un mois » de
--      l'écran d'administration : même calcul de date limite que le cron, sous
--      contrôle explicite de `is_admin`.
--   3. `periods_guard_transition` : normalise `locked_at`, gèle la clé
--      (caserne, année, mois) et **refuse une réouverture dont la date limite est
--      déjà passée** — sans quoi la tâche horaire reverrouillerait la période
--      dans l'heure, sous les yeux de l'admin qui vient de la rouvrir.
--   4. `periods_audit_reouverture` : `period.reopen` dans `audit_log`.
--   5. `availabilities_trace_auteur` + `availabilities_audit_saisie_admin` :
--      `set_by` imposé à l'auteur réel, audit quand l'auteur n'est pas le
--      titulaire.
--   6. Les deux tâches `pg_cron`.
--
-- Écart assumé avec docs/SCHEMA.md § 5, documenté dans le document : le trigger
-- unique `audit_admin_actions` y était annoncé pour trois tables aux sémantiques
-- très différentes (périodes, disponibilités, attributions). Il est éclaté en
-- déclencheurs par table, avec une clause `when` qui évite d'appeler la fonction
-- sur les écritures ordinaires — une saisie de mois complet, c'est soixante
-- lignes par membre.

-- ===========================================================================
-- 1. Corps des tâches planifiées
-- ===========================================================================
-- Les deux fonctions prennent un instant de référence, `now()` par défaut. Ce
-- paramètre n'est pas une commodité de test : c'est la seule façon de vérifier
-- en CI, en quelques millisecondes, un comportement dont la période est le mois.
-- L'ordonnanceur, lui, appelle toujours la forme sans argument.
--
-- `security definer` : les tâches tournent sous le rôle qui les a planifiées
-- (`postgres`) et doivent écrire dans toutes les casernes à la fois, ce
-- qu'aucune politique RLS n'exprime. En contrepartie, leur `search_path` est
-- figé (`public, pg_temp` en dernier, docs/SCHEMA.md § 3) et leur exécution est
-- retirée à `public`, `anon` et `authenticated` : un client ne peut pas
-- déclencher un verrouillage général en RPC.

-- Crée les périodes M+1 et M+2 manquantes de chaque caserne.
--
-- Le mois de référence est calculé **dans le fuseau de chaque caserne**, pas
-- dans celui du serveur. L'ordonnanceur tire à 02:00 UTC le 1er du mois : pour
-- une caserne à UTC-11, il est encore le dernier jour du mois précédent, et un
-- calcul en UTC lui créerait M+2 et M+3 en sautant un mois de saisie.
--
-- Idempotente par construction : `on conflict do nothing` sur la contrainte
-- d'unicité (station_id, year, month). Une seconde exécution ne crée rien et,
-- surtout, ne réécrit ni le statut ni la date limite d'une période existante —
-- une période rouverte à dessein n'est pas ramenée à son état d'origine.
--
-- Les casernes suspendues sont servies comme les autres : la suspension met
-- l'application en lecture seule pour ses utilisateurs, elle n'arrête pas le
-- temps. À la régularisation, les mois attendus sont là.
create function cron_create_periods(p_reference timestamptz default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant timestamptz := coalesce(p_reference, now());
  crees   integer;
begin
  with cible as (
    select
      s.id                                              as station_id,
      s.timezone                                        as fuseau,
      (s.settings ->> 'availability_deadline_day')::int as jour_limite,
      (date_trunc('month', instant at time zone s.timezone)
         + make_interval(months => g.n))::date          as premier_jour
    from stations s
    cross join generate_series(1, 2) as g(n)
  )
  insert into periods (station_id, year, month, deadline_at)
  select
    c.station_id,
    m.annee,
    m.mois,
    period_deadline_at(m.annee, m.mois, c.jour_limite, c.fuseau)
  from cible c
  cross join lateral (
    select extract(year  from c.premier_jour)::int as annee,
           extract(month from c.premier_jour)::int as mois
  ) m
  on conflict (station_id, year, month) do nothing;

  get diagnostics crees = row_count;
  return crees;
end $$;

comment on function cron_create_periods(timestamptz) is
  'Tâche create_periods (docs/SCHEMA.md § 8) : crée les périodes M+1 et M+2 manquantes de chaque caserne, mois de référence calculé dans le fuseau de la caserne. Idempotente. Renvoie le nombre de périodes créées.';

revoke execute on function cron_create_periods(timestamptz) from public, anon, authenticated;

-- Verrouille les périodes dont la date limite est passée.
--
-- `deadline_at` est un `timestamptz` : la comparaison à l'instant courant est
-- juste quel que soit le fuseau de la caserne, sans conversion.
--
-- Idempotente : la clause `status = 'open'` fait qu'une seconde exécution ne
-- touche aucune ligne et n'écrase pas un `locked_at` déjà posé. Une période
-- rouverte n'est pas reverrouillée parce que la réouverture impose une date
-- limite future (`periods_guard_transition` ci-dessous) : les deux moitiés de
-- la garantie sont ici et là, aucune ne suffit seule.
create function cron_lock_periods(p_reference timestamptz default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant      timestamptz := coalesce(p_reference, now());
  verrouillees integer;
begin
  update periods
     set status    = 'locked',
         locked_at = instant
   where status = 'open'
     and deadline_at < instant;

  get diagnostics verrouillees = row_count;
  return verrouillees;
end $$;

comment on function cron_lock_periods(timestamptz) is
  'Tâche lock_periods (docs/SCHEMA.md § 8) : passe en locked les périodes open dont deadline_at est dépassée. Idempotente. Renvoie le nombre de périodes verrouillées.';

revoke execute on function cron_lock_periods(timestamptz) from public, anon, authenticated;

-- ===========================================================================
-- 2. Créer un mois à la demande (écran d'administration)
-- ===========================================================================
-- docs/SCHEMA.md § 2.5 : une période est créée « cron mensuel ou à la demande ».
-- L'action à la demande passe par une fonction et non par un insert direct,
-- parce que la date limite se calcule à partir du document `settings` et du
-- fuseau de la caserne : laisser le client la calculer, c'est écrire la règle
-- une deuxième fois, et accepter qu'elle diverge.
--
-- `security definer` pour lire `stations` sans dépendre de la politique de
-- lecture, donc `is_admin` et `station_writable` sont vérifiés **explicitement**
-- et en premier : la fonction n'hérite d'aucune protection de la RLS.
create function create_period(
  p_station uuid, p_year integer, p_month integer
) returns periods
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caserne   stations;
  resultat  periods;
  mois_cible date;
begin
  if not is_admin(p_station) then
    raise exception 'forbidden'
      using hint = 'Seul un administrateur de la caserne ouvre un mois à la saisie.';
  end if;

  if not station_writable(p_station) then
    raise exception 'station_suspended'
      using hint = 'L''abonnement de la caserne est suspendu : l''application est en lecture seule.';
  end if;

  if p_month is null or p_month not between 1 and 12
     or p_year is null or p_year not between 2000 and 2100 then
    raise exception 'period_month_invalid'
      using hint = 'Mois attendu entre 1 et 12, année entre 2000 et 2100.';
  end if;

  select * into caserne from stations where id = p_station;

  -- Un mois écoulé ne peut plus être saisi : l'ouvrir ferait apparaître dans la
  -- grille des membres un passé qu'ils ne peuvent plus renseigner utilement.
  -- « Écoulé » se juge dans le fuseau de la caserne, pas dans celui du serveur.
  mois_cible := make_date(p_year, p_month, 1);
  if mois_cible < date_trunc('month', now() at time zone caserne.timezone)::date then
    raise exception 'period_month_in_past'
      using hint = 'Un mois déjà écoulé ne peut plus être ouvert à la saisie.';
  end if;

  insert into periods (station_id, year, month, deadline_at)
  values (
    p_station, p_year, p_month,
    period_deadline_at(
      p_year, p_month,
      (caserne.settings ->> 'availability_deadline_day')::int,
      caserne.timezone)
  )
  on conflict (station_id, year, month) do nothing
  returning * into resultat;

  -- Le mois existait déjà : on renvoie la période en place plutôt qu'une erreur.
  -- Deux admins qui cliquent en même temps obtiennent le même résultat.
  if resultat.id is null then
    select * into resultat from periods
     where station_id = p_station and year = p_year and month = p_month;
  end if;

  return resultat;
end $$;

comment on function create_period(uuid, integer, integer) is
  'Ouvre un mois à la saisie pour une caserne (action « créer un mois »). Date limite calculée par period_deadline_at. Idempotente : renvoie la période existante le cas échéant.';

revoke execute on function create_period(uuid, integer, integer) from public, anon;
grant execute on function create_period(uuid, integer, integer) to authenticated;

-- ===========================================================================
-- 3. Transitions de `periods` : garde-fou et audit
-- ===========================================================================
-- docs/WORKFLOWS.md § 1 : open → locked (cron ou admin), locked → open (admin,
-- avec audit). Ce que la RLS ne sait pas dire, et que le déclencheur dit :
--
--   - `locked_at` suit le statut sans que personne ait à y penser ;
--   - la clé (caserne, année, mois) ne change pas : une période est un mois, pas
--     un objet qu'on déplace ;
--   - une réouverture exige une date limite future.
--
-- Ce dernier point est le cœur du ticket. Sans lui, « rouvrir » est une action
-- qui s'annule toute seule à la prochaine heure ronde, et l'admin en accuse le
-- logiciel. Avec lui, rouvrir, c'est nécessairement dire jusqu'à quand.
--
-- Security invoker, comme `assignments_member_transition` : il n'y a ici aucune
-- lecture privilégiée, et la règle vaut pour tout le monde — y compris le rôle
-- de service. Une période `open` dont la date limite est passée est un état que
-- la tâche horaire défait aussitôt ; nul n'a de raison de le créer.
create function periods_guard_transition() returns trigger
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
  end if;

  return new;
end $$;

comment on function periods_guard_transition() is
  'Tient locked_at à jour, gèle la clé (caserne, année, mois) et refuse une réouverture dont la date limite est déjà passée (docs/WORKFLOWS.md § 1).';

revoke execute on function periods_guard_transition() from public, anon, authenticated;

create trigger periods_guard_transition
  before update on periods
  for each row execute function periods_guard_transition();

-- La réouverture est une décision qui déplace une échéance déjà annoncée aux
-- membres : elle se justifie, donc elle se trace (règle 7 du produit).
create function periods_audit_reouverture() returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    new.station_id,
    auth.uid(),
    'period.reopen',
    'period',
    new.id,
    jsonb_build_object(
      'year',            new.year,
      'month',           new.month,
      'locked_at',       old.locked_at,
      'deadline_avant',  old.deadline_at,
      'deadline_apres',  new.deadline_at
    )
  );
  return null;
end $$;

comment on function periods_audit_reouverture() is
  'Journalise period.reopen quand un administrateur rouvre une période verrouillée (docs/SCHEMA.md § 5).';

revoke execute on function periods_audit_reouverture() from public, anon, authenticated;

create trigger periods_audit_reouverture
  after update on periods
  for each row
  when (old.status = 'locked' and new.status = 'open')
  execute function periods_audit_reouverture();

-- ===========================================================================
-- 4. Saisie d'un administrateur pour un membre
-- ===========================================================================
-- docs/WORKFLOWS.md § 1 : « L'admin écrit toujours, avec `set_by` renseigné et
-- audit si `set_by <> user_id` ».
--
-- `set_by` est **imposé**, pas suggéré : laissé au client, un admin pourrait y
-- écrire l'identifiant du membre et faire disparaître son intervention de
-- l'écran comme du journal. C'est précisément la colonne qui doit résister à
-- celui qui a les droits.
--
-- Les écritures serveur (seed, rôle de service, migrations) gardent la valeur
-- qu'elles fournissent : elles n'ont pas d'`auth.uid()` et savent ce qu'elles
-- écrivent. Même convention que `memberships_guard_admin` (0010) et
-- `assignments_member_transition` (0008).
create function availabilities_trace_auteur() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.set_by := auth.uid();
  end if;
  return new;
end $$;

comment on function availabilities_trace_auteur() is
  'Impose availabilities.set_by = auth.uid() pour toute écriture client : la trace de l''auteur ne se choisit pas.';

revoke execute on function availabilities_trace_auteur() from public, anon, authenticated;

create trigger availabilities_trace_auteur
  before insert or update on availabilities
  for each row execute function availabilities_trace_auteur();

-- L'audit ne se déclenche que si l'auteur n'est pas le titulaire : la clause
-- `when` porte le test, la fonction n'est pas appelée pour les saisies
-- ordinaires — un mois complet, c'est une soixantaine de lignes par membre.
create function availabilities_audit_saisie_admin() returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  statut_avant availability_status;
begin
  if tg_op = 'DELETE' then
    insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
    values (
      old.station_id, auth.uid(),
      'availability.cleared_for_member', 'availability', old.id,
      jsonb_build_object(
        'user_id', old.user_id, 'date', old.date,
        'slot', old.slot, 'status', old.status)
    );
    return null;
  end if;

  if tg_op = 'UPDATE' then
    statut_avant := old.status;
  end if;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    new.station_id, new.set_by,
    'availability.set_for_member', 'availability', new.id,
    jsonb_build_object(
      'user_id', new.user_id, 'date', new.date,
      'slot', new.slot, 'status', new.status,
      'statut_avant', statut_avant)
  );
  return null;
end $$;

comment on function availabilities_audit_saisie_admin() is
  'Journalise availability.set_for_member / availability.cleared_for_member quand l''auteur de la saisie n''est pas le titulaire (docs/SCHEMA.md § 5).';

revoke execute on function availabilities_audit_saisie_admin() from public, anon, authenticated;

create trigger availabilities_audit_saisie_admin
  after insert or update on availabilities
  for each row
  when (new.set_by is not null and new.set_by is distinct from new.user_id)
  execute function availabilities_audit_saisie_admin();

-- Décocher une case, c'est supprimer la ligne (docs/SCHEMA.md § 2.6). Une
-- suppression faite par quelqu'un d'autre que le titulaire se trace aussi :
-- sans cela, l'admin qui efface la disponibilité d'un membre ne laisse rien.
create trigger availabilities_audit_effacement_admin
  after delete on availabilities
  for each row
  when (auth.uid() is not null and auth.uid() is distinct from old.user_id)
  execute function availabilities_audit_saisie_admin();

-- ===========================================================================
-- 5. Les deux tâches planifiées (docs/SCHEMA.md § 8)
-- ===========================================================================
-- `cron.schedule(nom, …)` est un upsert depuis pg_cron 1.4 : rejouer la
-- migration remplace la définition au lieu d'empiler les doublons.
--
-- Les commandes sont **qualifiées** (`public.`) et ne prennent aucun argument :
-- rien n'y est interpolé, il n'y a donc rien à y injecter. Le travail réel est
-- dans les deux fonctions ci-dessus, dont le `search_path` est figé.
--
-- Le garde-fou `insufficient_privilege` reprend celui de 0001 : sur un projet
-- hébergé, le schéma `cron` appartient à `supabase_admin` et les droits sont
-- posés par un event trigger. Une migration qui échouerait là bloquerait tout
-- le déploiement pour une tâche de confort.
do $planif$
begin
  -- 1er du mois, 02:00 (heure du serveur) : le mois de référence est ensuite
  -- recalculé caserne par caserne dans son propre fuseau.
  perform cron.schedule(
    'create_periods', '0 2 1 * *', $cmd$select public.cron_create_periods();$cmd$);

  -- Toutes les heures : le critère d'acceptation du ticket dit « dans l'heure
  -- suivant sa deadline ».
  perform cron.schedule(
    'lock_periods', '0 * * * *', $cmd$select public.cron_lock_periods();$cmd$);
exception
  when insufficient_privilege then
    raise notice 'pg_cron : droits insuffisants pour planifier create_periods / lock_periods, à faire à la main.';
end $planif$;
