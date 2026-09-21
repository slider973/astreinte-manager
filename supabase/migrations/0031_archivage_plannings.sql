-- 0031 — Archiver les plannings des mois passés, et dire ce qu'il en reste
-- visible. Ticket 044.
-- Référence : docs/SCHEMA.md § 4 et § 8 ; docs/WORKFLOWS.md § 2 et § 7.
--
-- Pourquoi cette migration existe
-- --------------------------------
-- docs/WORKFLOWS.md § 7 annonce « 1er de M+1 : planning archivé ». La transition
-- est permise en base depuis le ticket 019 (`schedules_guard_transition` la
-- nomme deux fois) et **personne ne l'appelle** : aucune ligne `archive_schedules`
-- dans `cron.job`, aucune fonction. Un planning de janvier 2026 est encore
-- `published` en septembre — donc encore « en cours » pour tout ce qui lit ce
-- statut.
--
-- Ce n'est pas qu'un statut qui vieillit mal. Trois conséquences mesurables :
--
--   1. `cron_assignment_reminders` et `cron_late_responders_report` (0021) ne
--      travaillent que sur les plannings `published`. Une proposition restée
--      sans réponse sur un mois écoulé continue donc de relancer son pompier,
--      indéfiniment, pour une garde qui n'aura pas lieu.
--   2. L'écran de suivi de l'admin ne sait pas distinguer le mois qu'il
--      construit du mois qu'il a fini de vivre : les deux sont `published`.
--   3. `v_schedule_progress`, `remind_schedule` et le bouton « Relancer
--      maintenant » restent actifs sur un passé qu'aucune relance ne changera.
--
-- Le point de fond du ticket : ce qu'un membre lit d'un planning archivé
-- ---------------------------------------------------------------------------
-- La revue du ticket 008 l'avait relevé et rien ne l'avait tranché, faute
-- d'archivage réel pour l'observer. L'état des politiques **avant** cette
-- migration :
--
--   | Table                                  | `archived` |
--   |----------------------------------------|------------|
--   | `schedules_select_member_published`    | lisible (`status <> 'draft'`) |
--   | `shifts_select_member_published`       | **invisible** (`in ('published','validated')`) |
--   | `assignments_select_own_published`     | **invisible** |
--   | `assignments_select_station_validated` | **invisible** (`= 'validated'`) |
--
-- Un membre lirait donc la ligne de planning et rien dedans : un mois vide.
-- C'était un effet de bord de trois énumérations écrites séparément, pas une
-- décision. Et c'est un effet de bord qui contredit le produit, dont la
-- règle 6 dit que l'historique n'est jamais supprimé (docs/PRD.md § 7) : un
-- historique que personne ne peut lire n'est pas conservé, il est enterré.
--
-- **La décision, en une phrase : un planning archivé se lit comme le tableau de
-- garde du mois écoulé, punaisé au mur de la caserne.** C'est-à-dire, pour un
-- membre :
--
--   - **les créneaux du mois**, tous ;
--   - **toutes ses propres attributions**, quel que soit leur statut — accepté,
--     refusé, annulé, remplacé. C'est son historique à lui, et le motif de son
--     refus est sa phrase ;
--   - **les attributions `accepted` de tous les autres membres** : qui a tenu
--     la garde. Rien d'autre.
--
-- Ce que ce choix ferme, et pourquoi. Sur un planning `validated`,
-- `assignments_select_station_validated` ouvre à tout membre **toutes** les
-- lignes d'`assignments` du mois, sans filtre de statut : les propositions
-- restées sans réponse, les refus, et `decline_reason` avec eux. Les écrans ne
-- montrent que les acceptées (`lib/features/astreintes/data/…`), mais une
-- politique n'est pas un écran. L'archivage **referme** cette porte : passé le
-- mois, qui a refusé quoi et en quels termes ne regarde plus que
-- l'administration, qui garde `assignments_select_admin` sans condition. Le
-- refus du 12 mars est un fait d'organisation tant qu'il faut combler le trou ;
-- le 1er avril, ce n'est plus qu'une phrase sur un collègue.
--
-- Ce que ce choix ouvre : un planning archivé depuis `published` — un mois qui
-- s'est terminé sans que toutes les propositions soient acceptées — laisse
-- désormais voir les gardes tenues par les autres, là où `published` ne
-- montrait à chacun que les siennes. C'est volontaire : le mois a été vécu, tout
-- le monde était là, et qui était d'astreinte le 14 n'est un secret pour
-- personne dans une caserne de soixante personnes. La visibilité d'un planning
-- en construction protège une décision qui n'est pas encore prise ; il n'y a
-- plus rien à protéger dans un mois révolu.
--
-- Autrement dit l'archivage **ne dépend pas de l'état d'où il vient**. C'est
-- délibéré : faire dépendre la lecture de « était-ce validé le 31 au soir ? »
-- demanderait de mémoriser cet état dans une colonne que docs/SCHEMA.md § 2.8
-- ne prévoit pas, pour rendre un mois passé plus ou moins lisible selon qu'un
-- pompier avait ou non cliqué « j'accepte » avant la fin du mois. La règle
-- serait plus difficile à dire qu'à coder, et une règle de visibilité qu'on ne
-- sait pas dire en une phrase finit par être contournée par un écran.
--
-- Ce qui ne bouge pas : `schedules_select_member_published` laissait déjà passer
-- `archived`, elle reste telle quelle ; l'admin voyait déjà tout, il voit
-- toujours tout.
--
-- Ce que cette migration ajoute
-- -----------------------------
--   1. `cron_archive_schedules(p_reference)` et la tâche `archive_schedules`.
--   2. Les trois politiques de lecture de la décision ci-dessus.
--   3. Le gel des écritures sur un planning archivé — vérifié plutôt que
--      supposé, et il manquait (section 3).
--   4. `ics_feed_events` recréée : ses quatre-vingt-dix jours d'historique
--      passaient par `sc.status in ('published','validated')` et seraient
--      tombés à zéro le jour où l'archivage entre en service.
--
-- Écart assumé avec docs/SCHEMA.md § 8, reporté dans le document
-- ---------------------------------------------------------------------------
-- Le tableau annonçait `archive_schedules` « 1er du mois ». La tâche est
-- **quotidienne** (02:30). La raison est celle du fuseau, et elle est la même
-- qu'aux tickets 014 et 015, en plus contraignante :
--
-- Le mois de référence se calcule caserne par caserne, dans son fuseau. Une
-- tâche qui ne tire que le 1er à 02:30 UTC trouve une caserne de Polynésie
-- (UTC-10) encore au **dernier jour du mois précédent** : son planning n'est
-- pas archivable, et c'est juste — l'archiver serait l'archiver un jour à
-- l'avance, sous les yeux de pompiers encore d'astreinte. Mais comme la tâche
-- ne repasse que le mois suivant, ce planning resterait publié **trente jours
-- de plus**, avec ses relances qui continuent de partir. Une exécution
-- quotidienne archive chaque caserne dans les vingt-quatre heures de son propre
-- 1er du mois, jamais avant. Le coût est un `update` nocturne sur une table qui
-- compte une ligne par caserne et par mois, et l'idempotence est acquise par
-- construction (`status in ('published','validated')`).

-- ===========================================================================
-- 1. La tâche : archiver les plannings des mois passés
-- ===========================================================================
-- Deux états seulement passent en `archived`, et ce sont ceux de
-- docs/WORKFLOWS.md § 2 : `published` et `validated`. **Un brouillon d'un mois
-- écoulé reste un brouillon** — `draft --> archived` n'est pas dans la machine à
-- états, `schedules_guard_transition` le refuserait, et surtout un brouillon
-- oublié est la seule chose du produit qui se supprime encore
-- (`schedules_delete_admin`, 0019) : l'archiver le rendrait indestructible sans
-- jamais avoir été lu par personne.
--
-- « Mois passé » se juge **dans le fuseau de la caserne**. `make_date(p.year,
-- p.month, 1)` est le mois du planning, `date_trunc('month', instant at time
-- zone s.timezone)` le mois courant de la caserne : la comparaison stricte dit
-- « strictement avant le mois en cours », donc jamais le mois courant, jamais un
-- mois à venir.
--
-- Idempotente : après le premier passage les lignes sont `archived` et ne
-- satisfont plus le `where`. Une seconde exécution sur le même instant rend 0.
--
-- Les casernes suspendues sont traitées comme les autres, même raison qu'en
-- 0012 : la suspension met l'application en lecture seule, elle n'arrête pas le
-- temps.
--
-- Pas d'entrée dans `audit_log` : ce n'est pas un acte d'administration, il n'y
-- a pas d'acteur, et l'`audit_log` sert à répondre « qui a fait ça » sur les
-- données d'un membre (voir le raisonnement de 0030). Le calendrier n'est pas
-- quelqu'un. L'ordonnanceur garde le compte dans `cron.job_run_details`.
--
-- `security definer` et `revoke` comme toutes les tâches du § 8 : la fonction
-- écrit dans toutes les casernes à la fois, ce qu'aucune politique n'exprime, et
-- aucun client ne peut la déclencher.
create function cron_archive_schedules(p_reference timestamptz default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  instant  timestamptz := coalesce(p_reference, now());
  archives integer;
begin
  update schedules sc
     set status = 'archived'
    from periods p, stations s
   where p.id = sc.period_id
     and s.id = sc.station_id
     and sc.status in ('published', 'validated')
     and make_date(p.year, p.month, 1)
         < date_trunc('month', instant at time zone s.timezone)::date;

  get diagnostics archives = row_count;
  return archives;
end $$;

comment on function cron_archive_schedules(timestamptz) is
  'Tâche archive_schedules (docs/SCHEMA.md § 8) : passe en archived les plannings published ou validated dont le mois est strictement antérieur au mois courant de leur caserne, calculé dans le fuseau de la caserne. Un brouillon n''est jamais archivé. Idempotente. Renvoie le nombre de plannings archivés.';

revoke execute on function cron_archive_schedules(timestamptz)
  from public, anon, authenticated;

-- ===========================================================================
-- 2. Ce qu'un membre lit d'un planning archivé
-- ===========================================================================
-- La décision est en tête de migration. Ici, sa traduction en trois politiques.
--
-- **Les noms ne changent pas.** `shifts_select_member_published` et
-- `assignments_select_own_published` porteront désormais un « published » qui
-- ne dit plus toute leur portée, et c'est le moindre mal : ces deux noms sont
-- cités dans docs/SCHEMA.md § 4, dans la migration 0029 et dans les commentaires
-- de quatre fichiers Dart qui expliquent pourquoi tel écran ne filtre pas ce que
-- la base filtre déjà. Renommer ferait de ces références des mensonges muets,
-- là où une politique élargie reste trouvable sous son nom.

-- --- Les créneaux ----------------------------------------------------------
-- Sans eux il n'y a pas de mois : la grille de l'écran « La caserne » est faite
-- de `shifts`, et une attribution sans son créneau n'a ni date ni tranche.
drop policy "shifts_select_member_published" on shifts;

create policy "shifts_select_member_published"
  on shifts for select to authenticated
  using (
    is_member(station_id)
    and exists (
      select 1 from schedules s
      where s.id = shifts.schedule_id
        and s.status in ('published', 'validated', 'archived')
    )
  );

-- --- Ses propres attributions, tout son historique -------------------------
-- Aucun filtre de statut d'attribution : un membre relit ses refus et ses
-- annulations comme ses gardes tenues. C'est déjà le cas sur un planning
-- publié ou validé ; l'archivage n'a aucune raison de le lui retirer.
drop policy "assignments_select_own_published" on assignments;

create policy "assignments_select_own_published"
  on assignments for select to authenticated
  using (
    user_id = auth.uid()
    and exists (
      select 1 from shifts sh
      join schedules sc on sc.id = sh.schedule_id
      where sh.id = assignments.shift_id
        and sc.status in ('published', 'validated', 'archived')
    )
  );

-- --- Les gardes tenues par les autres --------------------------------------
-- Politique **nouvelle** plutôt qu'élargissement d'`assignments_select_station_validated` :
-- les deux branches n'ont pas la même portée. Sur un planning validé, un membre
-- lit toutes les lignes ; sur un planning archivé, les acceptées seulement. Une
-- seule politique aurait porté un `or` dont la lecture ne dirait plus la règle.
--
-- `status = 'accepted'` et rien d'autre : `proposed` est une conversation qui
-- n'a pas eu lieu, `declined` et `cancelled` sont des phrases sur un collègue,
-- `replaced` est une ligne de plomberie. Ce qui reste — qui était d'astreinte —
-- est exactement ce que l'écran du ticket 023 affiche.
create policy "assignments_select_station_archived"
  on assignments for select to authenticated
  using (
    is_member(station_id)
    and status = 'accepted'
    and exists (
      select 1 from shifts sh
      join schedules sc on sc.id = sh.schedule_id
      where sh.id = assignments.shift_id
        and sc.status = 'archived'
    )
  );

-- ===========================================================================
-- 3. Un planning archivé ne se modifie plus
-- ===========================================================================
-- Le ticket demandait de **vérifier** que les gardes existantes le
-- garantissaient. Elles ne le garantissaient qu'à moitié. L'inventaire complet
-- des chemins d'écriture vers un planning archivé, et leur état avant cette
-- section :
--
--   | Chemin                                   | Avant | Pourquoi |
--   |------------------------------------------|-------|----------|
--   | `schedules` update de statut             | fermé | `schedules_guard_transition` (0019) : rien ne sort d'`archived` |
--   | `schedules` update d'horodatage          | fermé | même déclencheur, branche « statut inchangé » |
--   | `schedules` delete                       | fermé | `schedules_guard_suppression` + politique : brouillon seulement |
--   | `shifts` delete                          | fermé | `shifts_guard_suppression` + politique : brouillon seulement |
--   | `assignments` delete                     | fermé | `assignments_delete_admin` (0018) : brouillon seulement |
--   | réponse d'un membre                      | fermé | `assignments_update_member_response` (0008) : `published`/`validated` |
--   | `reassign_shift`, `cancel_assignment`    | fermé | `schedule_not_published` (0020) |
--   | `apply_auto_proposal`, `publish_schedule`| fermé | brouillon seulement (0028, 0019) |
--   | **`shifts` insert et update**            | **OUVERT** | `shifts_*_admin` ne regardent que la caserne et le planning parent, jamais son statut |
--   | **`assignments` insert et update**       | **OUVERT** | idem |
--
-- Les deux lignes ouvertes ne sont pas théoriques : un administrateur pouvait
-- ajouter un créneau à un mois archivé, y attribuer quelqu'un, ou faire passer
-- une attribution de `declined` à `accepted` sur un mois vieux d'un an — et,
-- depuis la section 2, cette réécriture serait désormais **visible de toute la
-- caserne**. Une décision de lecture ne se pose pas sur une table qu'on peut
-- encore réécrire.
--
-- La condition est portée par le `using` **et** par le `with check` des
-- `update` : le `using` refuse en zéro ligne — ce qu'un client lit comme « rien
-- n'a bougé » plutôt que comme une erreur, convention de 0019 —, le `with check`
-- ferme le déplacement d'une ligne vivante **vers** un planning archivé par
-- changement de `schedule_id` ou de `shift_id`.
--
-- `<> 'archived'` et non `in ('draft','published','validated')` : les deux
-- disent la même chose aujourd'hui, mais la première continue de dire ce qu'elle
-- veut dire le jour où un état s'ajoute à l'énumération.

drop policy "shifts_insert_admin" on shifts;
create policy "shifts_insert_admin"
  on shifts for insert to authenticated
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from schedules s
      where s.id = shifts.schedule_id
        and s.station_id = shifts.station_id
        and s.status <> 'archived'
    )
  );

drop policy "shifts_update_admin" on shifts;
create policy "shifts_update_admin"
  on shifts for update to authenticated
  using (
    is_admin(station_id)
    and exists (
      select 1 from schedules s
      where s.id = shifts.schedule_id
        and s.status <> 'archived'
    )
  )
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from schedules s
      where s.id = shifts.schedule_id
        and s.station_id = shifts.station_id
        and s.status <> 'archived'
    )
  );

drop policy "assignments_insert_admin" on assignments;
create policy "assignments_insert_admin"
  on assignments for insert to authenticated
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from shifts sh
      join schedules sc on sc.id = sh.schedule_id
      where sh.id = assignments.shift_id
        and sh.station_id = assignments.station_id
        and sc.status <> 'archived'
    )
    and exists (
      select 1 from memberships m
      where m.user_id = assignments.user_id and m.station_id = assignments.station_id
    )
  );

drop policy "assignments_update_admin" on assignments;
create policy "assignments_update_admin"
  on assignments for update to authenticated
  using (
    is_admin(station_id)
    and exists (
      select 1 from shifts sh
      join schedules sc on sc.id = sh.schedule_id
      where sh.id = assignments.shift_id
        and sc.status <> 'archived'
    )
  )
  with check (
    is_admin(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from shifts sh
      join schedules sc on sc.id = sh.schedule_id
      where sh.id = assignments.shift_id
        and sh.station_id = assignments.station_id
        and sc.status <> 'archived'
    )
    and exists (
      select 1 from memberships m
      where m.user_id = assignments.user_id and m.station_id = assignments.station_id
    )
  );

-- ===========================================================================
-- 4. Le flux calendrier suit la même règle
-- ===========================================================================
-- `ics_feed_events` (0029) recopie les politiques de lecture dans ses filtres,
-- et elle le dit en commentaire : `sc.status in ('published','validated')` y est
-- annoncé comme le miroir de `shifts_select_member_published`. Le miroir doit
-- donc suivre, et il le doit d'autant plus que la fonction promet **quatre-vingt-
-- dix jours d'historique** : sans ce changement, le jour où l'archivage entre en
-- service, ces quatre-vingt-dix jours tombent à « depuis le 1er du mois » —
-- entre zéro et trente et un — et l'agenda d'un pompier perdrait ses gardes
-- passées à chaque changement de mois, sans qu'aucune requête n'échoue.
--
-- Seul le filtre de statut change. Les quatre autres, la forme de la requête et
-- les droits sont ceux de 0029, recopiés à l'identique : `create or replace`
-- remplace un corps, il ne dispense pas de relire ce qu'on réécrit.
create or replace function ics_feed_events(p_token text, p_reference date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user       uuid;
  v_evenements jsonb;
begin
  if p_token is null or btrim(p_token) = '' then
    return jsonb_build_object('ok', false, 'code', 'unknown_token');
  end if;

  select p.id into v_user from profiles p where p.ics_token = p_token;

  if v_user is null then
    return jsonb_build_object('ok', false, 'code', 'unknown_token');
  end if;

  select coalesce(jsonb_agg(ligne order by tri_date, tri_creneau), '[]'::jsonb)
    into v_evenements
  from (
    select sh.date as tri_date,
           sh.slot as tri_creneau,
           jsonb_build_object(
             'id',         a.id,
             'date',       sh.date,
             'creneau',    sh.slot,
             'caserne',    st.name,
             'fuseau',     st.timezone,
             'debut_jour', coalesce(st.settings ->> 'day_start', '07:00'),
             'fin_jour',   coalesce(st.settings ->> 'day_end',   '19:00'),
             'modifie_le', a.updated_at
           ) as ligne
      from assignments a
      join shifts    sh on sh.id = a.shift_id
      join schedules sc on sc.id = sh.schedule_id
      join stations  st on st.id = a.station_id
      join memberships m on m.station_id = a.station_id
                        and m.user_id    = a.user_id
     where a.user_id  = v_user
       and a.status   = 'accepted'
       and sc.status in ('published', 'validated', 'archived')
       and m.status   = 'active'
       and sh.date   >= p_reference - 90
  ) t;

  return jsonb_build_object(
    'ok', true,
    'membre', v_user,
    'evenements', v_evenements
  );
end $$;

comment on function ics_feed_events(text, date) is
  'Le contenu du flux calendrier d''un membre, désigné par son jeton d''abonnement (ticket 028) : ses astreintes acceptées sur un planning publié, validé ou archivé (ticket 044), dans les casernes où il est encore actif, à partir de p_reference - 90 jours, avec le nom, le fuseau et les heures d''affichage de chaque caserne. Rien d''un autre membre, rien d''une autre caserne. Rend {"ok": false, "code": "unknown_token"} pour un jeton inconnu. Réservée au rôle de service : le jeton est un secret, pas un paramètre de client.';

-- `create or replace` conserve les droits existants ; on les réaffirme, parce
-- que c'est la troisième fois que ce dépôt se fait prendre par
-- `api.auto_expose_new_tables` (voir 0009 et 0029) et qu'une ligne de plus coûte
-- moins qu'une fonction à jeton porteur ouverte à `anon`.
revoke all on function ics_feed_events(text, date) from public, anon, authenticated;
grant execute on function ics_feed_events(text, date) to service_role;

-- ===========================================================================
-- 5. La tâche planifiée (docs/SCHEMA.md § 8)
-- ===========================================================================
-- Même forme que 0012, 0014, 0016, 0021, 0023, 0024 et 0030 : `cron.schedule`
-- est un upsert depuis pg_cron 1.4, la commande est qualifiée et sans argument,
-- et le garde-fou `insufficient_privilege` évite qu'un projet hébergé où le
-- schéma `cron` appartient à `supabase_admin` fasse échouer tout le déploiement.
--
-- 02:30 tous les jours : entre `create_periods` (02:00 le 1er) et les tâches
-- d'abonnement (03:20 et 03:30), dans le creux de la nuit. Quotidienne et non
-- mensuelle — voir l'écart assumé en tête de migration.
do $planif$
begin
  perform cron.schedule(
    'archive_schedules', '30 2 * * *',
    $cmd$select public.cron_archive_schedules();$cmd$);
exception
  when insufficient_privilege then
    raise notice 'pg_cron : droits insuffisants pour planifier archive_schedules, à faire à la main.';
end $planif$;
