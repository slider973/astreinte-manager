-- 0040 — Un pompier dans plusieurs casernes : jamais proposé deux fois au même
-- moment. Ticket 072, décision 1 du propriétaire (28 septembre 2026).
-- Référence : docs/SCHEMA.md § 3 (« Plusieurs casernes »), § 6
-- (`availability_matrix`) et § 10 ; docs/WORKFLOWS.md § 3.
--
-- Le défaut trouvé
-- ----------------
-- `memberships unique (station_id, user_id)` permet depuis toujours d'être membre
-- de deux casernes, mais rien ne les faisait se parler : `apply_auto_proposal`
-- (0028) ne regardait que la caserne du planning. La même personne pouvait donc
-- être proposée le 12 octobre de nuit à A **et** à B, et l'administrateur de A
-- n'avait aucun moyen de le savoir — la RLS lui ferme, à juste titre, tout ce
-- qui se passe à B.
--
-- La décision
-- -----------
-- « Le planning automatique ne la propose pas si elle est déjà proposée ou
-- acceptée ailleurs sur un créneau qui chevauche ; l'admin voit qu'elle est
-- prise ailleurs, sans voir le détail de l'autre caserne. »
--
-- Ce que cette migration ajoute
-- -----------------------------
-- 1. `shift_window` — l'intervalle **réel** d'un créneau. Deux casernes n'ont pas
--    forcément les mêmes heures (`day_start`, `day_end`) ni le même fuseau : le
--    jour de A (07:00–19:00) et la nuit de B qui commence à 18:00 se chevauchent,
--    alors qu'ils ne portent ni la même date ni le même créneau. Comparer
--    `(date, slot)` aurait laissé passer ce cas et bloqué à tort deux casernes
--    dont les heures se suivent. L'intervalle est celui que sert déjà le flux
--    calendrier (`ics-feed/calendrier.ts`, ticket 028) : la nuit est le
--    complément du jour, un créneau qui franchit minuit finit le lendemain, le
--    tout résolu dans le fuseau de la caserne. Bornes `[)` : une garde qui finit
--    à 19:00 et une autre qui commence à 19:00 ne se chevauchent pas — c'est la
--    relève, pas un doublon.
--
-- 2. `member_taken_elsewhere` — **le** booléen « pris ailleurs ». `security
--    definer`, parce qu'il lit des attributions d'une caserne que l'appelant ne
--    voit pas ; **réservé au rôle de service** et aux fonctions de la base,
--    parce qu'ouvert à `authenticated` il deviendrait un oracle : n'importe quel
--    administrateur pourrait interroger l'agenda de n'importe quel identifiant.
--    Il ne rend **qu'un booléen** : ni la caserne, ni l'heure, ni le statut de
--    l'attribution de l'autre côté.
--
-- 3. `apply_auto_proposal` redéfinie : un motif d'écart de plus,
--    `taken_elsewhere`, son compte dans la réponse (clé `taken_elsewhere`, un
--    entier), et un verrou par pompier. Le corps est celui de 0028 à ces ajouts
--    près ; la signature et les droits ne changent pas, et la réponse ne perd
--    aucune clé.
--
--    **Le verrou par pompier.** Le verrou du planning (0028) sérialise deux
--    administrateurs **d'une même caserne** ; il ne dit rien à l'administrateur
--    de B, qui verrouille un autre planning. Sans plus, A et B appuyant au même
--    instant liraient chacun « pas pris ailleurs » avant que l'autre n'ait validé,
--    et poseraient tous deux la même personne. Un verrou consultatif de
--    transaction par pompier (`pg_advisory_xact_lock`), pris **avant** toute
--    lecture et **dans l'ordre des identifiants** — deux remplissages qui se
--    disputent deux pompiers les prennent dans le même ordre, donc ne
--    s'interbloquent pas —, fait attendre le second jusqu'à la validation du
--    premier, après quoi il lit l'attribution posée et écarte la ligne.
--
-- 4. `availability_matrix` redéfinie avec deux colonnes de plus,
--    `day_taken_elsewhere` et `night_taken_elsewhere` : la même forme que
--    `day_slots` / `night_slots`, un caractère par jour du mois, `.` libre et `X`
--    pris ailleurs. C'est ce que l'administrateur voit dans la grille et dans le
--    panneau d'un créneau, et c'est ce qui permet à l'application de ne pas
--    composer un plan que la base écarterait. Le type de retour change : la
--    fonction est supprimée puis recréée, avec les mêmes droits. Les colonnes
--    existantes ne bougent pas ; un client qui ne lit pas les nouvelles n'y voit
--    aucune différence.
--
-- Ce que cette migration ne touche pas
-- ------------------------------------
-- **Aucune politique RLS, aucune table, aucune colonne de table.** Une
-- attribution posée **à la main** par l'administrateur reste permise même sur un
-- pompier pris ailleurs (docs/PRD.md § 6.4 : l'administrateur garde la main) ;
-- il le voit dans la grille, c'est à lui de décider. La règle de la décision 1
-- est celle du planning **automatique**.

-- ===========================================================================
-- 1. shift_window — l'intervalle réel d'un créneau
-- ===========================================================================
-- Pure : elle ne lit aucune table, on lui passe le fuseau et les réglages de la
-- caserne. `stable` et non `immutable` : la conversion de fuseau dépend de la
-- base des fuseaux du serveur, qui peut changer avec une mise à jour.
create function shift_window(
  p_date     date,
  p_slot     slot_type,
  p_timezone text,
  p_settings jsonb
) returns tstzrange
language sql
stable
set search_path = public, pg_temp
as $$
  with heures as (
    select
      coalesce(p_settings ->> 'day_start', '07:00')::time as debut_jour,
      coalesce(p_settings ->> 'day_end',   '19:00')::time as fin_jour
  ),
  bornes as (
    select
      case when p_slot = 'day' then debut_jour else fin_jour   end as debut,
      case when p_slot = 'day' then fin_jour   else debut_jour end as fin
    from heures
  )
  select tstzrange(
    (p_date + debut) at time zone p_timezone,
    ((case when fin <= debut then p_date + 1 else p_date end) + fin) at time zone p_timezone,
    '[)')
  from bornes;
$$;

comment on function shift_window(date, slot_type, text, jsonb) is
  'Intervalle réel d''un créneau (date, jour ou nuit) dans le fuseau et aux heures d''une caserne : la nuit est le complément du jour, un créneau qui franchit minuit finit le lendemain, bornes [). Même calcul que le flux calendrier (ics-feed/calendrier.ts).';

revoke execute on function shift_window(date, slot_type, text, jsonb) from public, anon, authenticated;

-- ===========================================================================
-- 2. member_taken_elsewhere — le booléen « pris ailleurs »
-- ===========================================================================
-- Vrai si `p_user` a, dans une **autre** caserne que `p_station`, une
-- attribution `proposed` ou `accepted` dont le créneau chevauche le créneau
-- `(p_date, p_slot)` de `p_station`, aux heures de chacune des deux casernes.
--
-- **Proposée compte, brouillon compris** : c'est « déjà proposée » dans la
-- décision du propriétaire, et une proposition de brouillon est celle que l'autre
-- administrateur s'apprête à publier. Premier posé, premier servi.
--
-- **L'appartenance à l'autre caserne n'est pas relue.** Une attribution active
-- est un engagement tant que l'administrateur de l'autre caserne ne l'a pas
-- annulée, désactivation ou pas. Le doute bloque la machine, jamais
-- l'administrateur, qui peut toujours attribuer à la main.
--
-- La fenêtre de dates (± 2 jours) ne sert qu'à l'index : un créneau dure au plus
-- vingt-quatre heures, et deux fuseaux ne s'écartent pas de plus de vingt-six.
create function member_taken_elsewhere(
  p_station uuid,
  p_user    uuid,
  p_date    date,
  p_slot    slot_type
) returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from stations ici
      join assignments a
        on a.user_id    = p_user
       and a.station_id <> ici.id
       and a.status in ('proposed', 'accepted')
      join shifts s
        on s.id = a.shift_id
       and s.date between p_date - 2 and p_date + 2
      join stations la on la.id = s.station_id
     where ici.id = p_station
       and shift_window(s.date, s.slot, la.timezone, la.settings)
           && shift_window(p_date, p_slot, ici.timezone, ici.settings)
  );
$$;

comment on function member_taken_elsewhere(uuid, uuid, date, slot_type) is
  'Vrai si le membre a, dans une autre caserne, une attribution proposée ou acceptée dont le créneau chevauche celui-ci (heures et fuseau de chaque caserne). Ne rend qu''un booléen : rien de l''autre caserne n''en sort. Réservée au rôle de service et aux fonctions de la base (ticket 072, décision 1).';

revoke execute on function member_taken_elsewhere(uuid, uuid, date, slot_type) from public, anon, authenticated;

-- ===========================================================================
-- 3. apply_auto_proposal — le motif `taken_elsewhere` et le verrou par pompier
-- ===========================================================================
-- Corps de 0028, commentaires abrégés : la justification de chaque limite y
-- reste. Ce qui est nouveau est marqué « 0040 ».
create or replace function apply_auto_proposal(p_schedule uuid, p_actor uuid, p_picks jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  maximum   constant integer := 500;
  motif_uuid constant text :=
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

  planning  schedules;
  periode   periods;
  creneau   shifts;
  ligne     jsonb;
  v_shift   uuid;
  v_user    uuid;
  premier   date;
  suivant   date;
  unite     date;
  plafond_astreintes integer;
  plafond_weekends   integer;
  poses     integer := 0;
  ecartes   jsonb := '[]'::jsonb;
  motif     text;
  restants  integer;
begin
  if jsonb_typeof(p_picks) is distinct from 'array' then
    return jsonb_build_object('ok', false, 'code', 'invalid_picks');
  end if;

  if jsonb_array_length(p_picks) > maximum then
    return jsonb_build_object('ok', false, 'code', 'too_many_picks',
                              'maximum', maximum);
  end if;

  select * into planning from schedules where id = p_schedule;
  if planning.id is null then
    return jsonb_build_object('ok', false, 'code', 'schedule_not_found');
  end if;

  -- L'acteur n'est pas cru sur parole : `is_admin` lit `auth.uid()`, nul ici.
  if not exists (
    select 1 from memberships m
    where m.station_id = planning.station_id
      and m.user_id    = p_actor
      and m.role       = 'admin'
      and m.status     = 'active'
  ) then
    return jsonb_build_object('ok', false, 'code', 'not_admin');
  end if;

  if not station_writable(planning.station_id) then
    return jsonb_build_object('ok', false, 'code', 'station_suspended');
  end if;

  -- Le verrou du planning, puis la relecture du statut.
  select * into planning from schedules where id = p_schedule for update;

  if planning.status <> 'draft' then
    return jsonb_build_object('ok', false, 'code', 'schedule_not_draft',
                              'status', planning.status);
  end if;

  -- 0040 — Un verrou par pompier du plan, **dans l'ordre des identifiants** :
  -- c'est ce qui sérialise deux casernes qui remplissent en même temps (voir
  -- l'en-tête) sans qu'elles puissent s'interbloquer. Pris avant toute lecture,
  -- pour que le test « pris ailleurs » lise ce que l'autre a validé.
  -- Une boucle et non un `perform … from (… order by)` : l'ordre d'exécution
  -- d'un `perform` sur une sous-requête triée n'est pas garanti, celui d'une
  -- boucle l'est. Identifiants normalisés par `::uuid`, pour qu'une casse
  -- différente ne donne pas deux verrous pour le même pompier.
  for v_user in
    select distinct (e ->> 'user_id')::uuid
      from jsonb_array_elements(p_picks) e
     where jsonb_typeof(e) = 'object'
       and coalesce(e ->> 'user_id', '') ~* motif_uuid
     order by 1
  loop
    perform pg_advisory_xact_lock(
      hashtextextended('apply_auto_proposal:user:' || v_user::text, 0));
  end loop;

  select * into periode from periods where id = planning.period_id;
  premier := make_date(periode.year, periode.month, 1);
  suivant := (premier + interval '1 month')::date;

  for ligne in select * from jsonb_array_elements(p_picks)
  loop
    motif := null;

    if jsonb_typeof(ligne) is distinct from 'object'
       or coalesce(ligne ->> 'shift_id', '') !~* motif_uuid
       or coalesce(ligne ->> 'user_id',  '') !~* motif_uuid then
      ecartes := ecartes || jsonb_build_object(
        'shift_id', ligne -> 'shift_id',
        'user_id',  ligne -> 'user_id',
        'code',     'invalid_pick');
      continue;
    end if;

    v_shift := (ligne ->> 'shift_id')::uuid;
    v_user  := (ligne ->> 'user_id')::uuid;

    -- 1. Le créneau appartient bien à **ce** planning, donc à cette caserne.
    select * into creneau from shifts
     where id = v_shift
       and schedule_id = p_schedule
       and station_id  = planning.station_id;

    if creneau.id is null then
      motif := 'shift_not_in_schedule';

    -- 2. Un pompier désactivé, ou d'une autre caserne, n'est pas attribuable.
    elsif not exists (
      select 1 from memberships m
      where m.station_id = planning.station_id
        and m.user_id    = v_user
        and m.status     = 'active'
    ) then
      motif := 'member_not_active';

    -- 3. Disponible, et déclaré tel : ni l'absent ni celui qui n'a rien saisi.
    elsif not exists (
      select 1 from availabilities a
      where a.station_id = planning.station_id
        and a.user_id    = v_user
        and a.date       = creneau.date
        and a.slot       = creneau.slot
        and a.status     = 'available'
    ) then
      motif := 'not_available';

    -- 4. Déjà sur ce créneau.
    elsif exists (
      select 1 from assignments a
      where a.shift_id = v_shift
        and a.user_id  = v_user
        and a.status in ('proposed', 'accepted')
    ) then
      motif := 'already_assigned';

    -- 4 bis (0040). Déjà proposé ou accepté **dans une autre caserne** sur un
    -- créneau qui chevauche. Le motif ne dit rien de plus : ni où, ni quand.
    elsif member_taken_elsewhere(planning.station_id, v_user, creneau.date, creneau.slot) then
      motif := 'taken_elsewhere';

    -- 5. Les places : le remplissage complète, il ne renforce pas.
    elsif (
      select count(*) from assignments a
       where a.shift_id = v_shift
         and a.status in ('proposed', 'accepted')
    ) >= creneau.required_count then
      motif := 'shift_already_filled';
    end if;

    if motif is null then
      -- 6. Les deux plafonds du mois. `null` vaut illimité, jamais zéro.
      select prefs.max_shifts, prefs.max_weekends
        into plafond_astreintes, plafond_weekends
        from availability_preferences prefs
       where prefs.station_id = planning.station_id
         and prefs.user_id    = v_user
         and prefs.period_id  = planning.period_id;

      -- Relu à chaque ligne : les attributions posées par cet appel comptent.
      if plafond_astreintes is not null and (
        select count(*)
          from assignments a
          join shifts s on s.id = a.shift_id and s.station_id = planning.station_id
         where a.user_id    = v_user
           and a.station_id = planning.station_id
           and a.status in ('proposed', 'accepted')
           and s.date >= premier
           and s.date <  suivant
      ) >= plafond_astreintes then
        motif := 'shift_quota_reached';
      end if;
    end if;

    if motif is null and plafond_weekends is not null then
      unite := unite_weekend(creneau.date);

      if unite is not null and not exists (
        select 1
          from assignments a
          join shifts s on s.id = a.shift_id and s.station_id = planning.station_id
         where a.user_id    = v_user
           and a.station_id = planning.station_id
           and a.status in ('proposed', 'accepted')
           and s.date >= premier
           and s.date <  suivant
           and unite_weekend(s.date) = unite
      ) and (
        select count(distinct unite_weekend(s.date))
          from assignments a
          join shifts s on s.id = a.shift_id and s.station_id = planning.station_id
         where a.user_id    = v_user
           and a.station_id = planning.station_id
           and a.status in ('proposed', 'accepted')
           and s.date >= premier
           and s.date <  suivant
      ) >= plafond_weekends then
        motif := 'weekend_quota_reached';
      end if;
    end if;

    if motif is not null then
      ecartes := ecartes || jsonb_build_object(
        'shift_id', v_shift, 'user_id', v_user, 'code', motif);
      continue;
    end if;

    -- `was_available` établi par le test 3, `created_by` = l'administrateur,
    -- `proposed_at` nul : le brouillon n'a rien envoyé.
    insert into assignments (
      station_id, shift_id, user_id, status, was_available, created_by)
    values (
      planning.station_id, v_shift, v_user, 'proposed', true, p_actor);

    poses := poses + 1;
  end loop;

  select count(*) into restants
    from shifts s
   where s.schedule_id = p_schedule
     and (
       select count(*) from assignments a
        where a.shift_id = s.id
          and a.status in ('proposed', 'accepted')
     ) < s.required_count;

  return jsonb_build_object(
    'ok',            true,
    'schedule_id',   p_schedule,
    'station_id',    planning.station_id,
    'applied',       poses,
    'skipped',       ecartes,
    'shifts_short',  restants,
    -- 0040 — Le compte des lignes écartées parce que le pompier est pris
    -- ailleurs, prêt à afficher : l'écran le dit à part (« Astreinte
    -- ailleurs »), il ne le confond pas avec un quota atteint.
    'taken_elsewhere', (
      select count(*)::int from jsonb_array_elements(ecartes) e
       where e ->> 'code' = 'taken_elsewhere'));
end $$;

comment on function apply_auto_proposal(uuid, uuid, jsonb) is
  'Applique un plan de remplissage (liste ordonnée de couples créneau / pompier) sur un planning en brouillon, dans une seule transaction : membre actif et déclaré disponible, jamais pris ailleurs sur un créneau qui chevauche (taken_elsewhere, ticket 072), plafonds d''astreintes et de weekends jamais dépassés, effectif requis jamais dépassé, attributions déjà posées jamais touchées. Une ligne refusée est écartée avec son motif, les autres passent. Le choix des pompiers, lui, est fait par l''application (ticket 017). Réservée au rôle de service.';

-- `create or replace` garde les droits de 0028 ; on les réaffirme quand même,
-- pour que ce fichier se lise seul.
revoke execute on function apply_auto_proposal(uuid, uuid, jsonb) from public, anon, authenticated;

-- ===========================================================================
-- 4. availability_matrix — deux colonnes « pris ailleurs »
-- ===========================================================================
-- Corps de 0017, plus deux chaînes. Le type de retour change : `create or
-- replace` le refuserait, d'où `drop` puis `create`, et les droits re-posés.
drop function availability_matrix(uuid, uuid);

create function availability_matrix(p_station uuid, p_period uuid)
returns table (
  user_id               uuid,
  display_name          text,
  first_name            text,
  last_name             text,
  comment               text,
  max_shifts            integer,
  max_weekends          integer,
  shifts_count          integer,
  weekend_units         integer,
  shifts_left           integer,
  weekends_left         integer,
  accepted_previous     integer,
  day_slots             text,
  night_slots           text,
  day_taken_elsewhere   text,
  night_taken_elsewhere text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  periode   periods;
  premier   date;
  suivant   date;
begin
  if not is_admin(p_station) then
    raise exception 'forbidden'
      using hint = 'La matrice des disponibilités est un écran d''administration de la caserne.';
  end if;

  select * into periode from periods where id = p_period and station_id = p_station;
  if periode.id is null then
    raise exception 'period_not_found'
      using hint = 'Cette période n''existe pas ou n''appartient pas à cette caserne.';
  end if;

  premier := make_date(periode.year, periode.month, 1);
  suivant := (premier + interval '1 month')::date;

  return query
  with membres as (
    -- Les membres **actifs** seulement.
    select
      m.user_id,
      coalesce(nullif(btrim(m.display_name), ''),
               btrim(pr.first_name || ' ' || pr.last_name)) as affiche,
      pr.first_name,
      pr.last_name
    from memberships m
    join profiles pr on pr.id = m.user_id
    where m.station_id = p_station and m.status = 'active'
  ),
  jours as (
    select
      j::date                       as jour,
      (j::date - premier + 1)::int  as rang
    from generate_series(premier, suivant - 1, interval '1 day') j
  ),
  -- Une seule lecture d'`availabilities` pour tout le mois et toute la caserne.
  saisies as (
    select
      a.user_id,
      a.date,
      a.slot,
      case
        when a.set_by is not null and a.set_by <> a.user_id
          then case a.status when 'available' then 'd' else 'a' end
        else case a.status when 'available' then 'D' else 'A' end
      end as code
    from availabilities a
    where a.station_id = p_station
      and a.date >= premier
      and a.date <  suivant
  ),
  -- 0040 — Les attributions actives des membres **dans les autres casernes**,
  -- réduites à leur intervalle. Rien d'autre n'en sort : ni la caserne, ni le
  -- statut, ni l'identifiant. Même règle que `member_taken_elsewhere`, écrite en
  -- ensemble pour ne pas l'appeler 62 fois par membre ; la parité des deux est
  -- vérifiée par `supabase/tests/plusieurs_casernes_test.sql`.
  ici as (
    select st.timezone, st.settings from stations st where st.id = p_station
  ),
  ailleurs as (
    select
      a.user_id,
      s.date as jour_ailleurs,
      shift_window(s.date, s.slot, la.timezone, la.settings) as fenetre
    from assignments a
    join shifts s    on s.id = a.shift_id
    join stations la on la.id = s.station_id
    where a.user_id in (select mb.user_id from membres mb)
      and a.station_id <> p_station
      and a.status in ('proposed', 'accepted')
      and s.date >= premier - 2
      and s.date <  suivant + 2
  ),
  pris as (
    select distinct x.user_id, j.jour, c.slot
    from ailleurs x
    join jours j on j.jour between x.jour_ailleurs - 2 and x.jour_ailleurs + 2
    cross join (values ('day'::slot_type), ('night'::slot_type)) as c(slot)
    cross join ici
    where x.fenetre && shift_window(j.jour, c.slot, ici.timezone, ici.settings)
  ),
  grille as (
    select
      mb.user_id,
      string_agg(coalesce(sj.code, '.'), '' order by j.rang) as day_slots,
      string_agg(coalesce(sn.code, '.'), '' order by j.rang) as night_slots,
      string_agg(case when pj.user_id is null then '.' else 'X' end, '' order by j.rang)
        as day_taken_elsewhere,
      string_agg(case when pn.user_id is null then '.' else 'X' end, '' order by j.rang)
        as night_taken_elsewhere
    from membres mb
    cross join jours j
    left join saisies sj
      on sj.user_id = mb.user_id and sj.date = j.jour and sj.slot = 'day'
    left join saisies sn
      on sn.user_id = mb.user_id and sn.date = j.jour and sn.slot = 'night'
    left join pris pj
      on pj.user_id = mb.user_id and pj.jour = j.jour and pj.slot = 'day'
    left join pris pn
      on pn.user_id = mb.user_id and pn.jour = j.jour and pn.slot = 'night'
    group by mb.user_id
  )
  select
    mb.user_id,
    mb.affiche,
    mb.first_name,
    mb.last_name,
    prefs.comment,
    charge.max_shifts,
    charge.max_weekends,
    charge.shifts_count,
    charge.weekend_units,
    charge.shifts_left,
    charge.weekends_left,
    charge.accepted_previous,
    g.day_slots,
    g.night_slots,
    g.day_taken_elsewhere,
    g.night_taken_elsewhere
  from membres mb
  join grille g on g.user_id = mb.user_id
  left join availability_preferences prefs
    on prefs.station_id = p_station
   and prefs.period_id = p_period
   and prefs.user_id = mb.user_id
  left join v_member_load charge
    on charge.station_id = p_station
   and charge.period_id = p_period
   and charge.user_id = mb.user_id
  order by mb.affiche, mb.user_id;
end $$;

comment on function availability_matrix(uuid, uuid) is
  'Matrice des disponibilités d''un mois pour un admin : une ligne par membre actif, le mois encodé en chaînes d''un caractère par jour (day_slots / night_slots : « . » non saisi, « D » disponible, « A » absent ; day_taken_elsewhere / night_taken_elsewhere : « . » libre, « X » proposé ou accepté dans une autre caserne sur un créneau qui chevauche), les plafonds et restes de v_member_load, et le commentaire du mois. Lève forbidden si l''appelant n''est pas admin de la caserne.';

revoke execute on function availability_matrix(uuid, uuid) from public, anon;
grant  execute on function availability_matrix(uuid, uuid) to authenticated;
