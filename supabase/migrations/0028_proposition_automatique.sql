-- 0028 — La proposition automatique de remplissage du brouillon.
-- Ticket 018. Référence : docs/PRD.md sections 5.3, 6.4 et 7.4 ;
-- docs/SCHEMA.md sections 2.6, 2.9, 2.10 et 7 ; docs/WORKFLOWS.md section 3 ;
-- design/018-proposition-automatique.md sections 3, 4 et 8 ;
-- supabase/functions/README.md.
--
-- Ce que cette migration ajoute, et ce qu'elle n'ajoute pas
-- --------------------------------------------------------
-- Elle ajoute **une** fonction, `apply_auto_proposal`, et rien d'autre : ni
-- vue, ni index, ni colonne. Elle applique un plan de remplissage — une liste
-- de couples (créneau, pompier) — dans une seule transaction, en revérifiant
-- chaque ligne.
--
-- **Elle ne choisit personne.** Le classement des candidats est celui du
-- ticket 017 (`comparerCandidats`, Dart) : c'est lui que le chef de centre lit
-- dans le panneau d'un créneau, et la machine doit choisir comme le panneau
-- montre. Le réécrire ici donnerait deux classements de la même liste, et le
-- jour où ils divergeraient, la proposition automatique désignerait le
-- troisième nom du panneau sans que personne ne puisse dire pourquoi
-- (design/018 § 3 et § 4).
--
-- Ce que la base garde donc pour elle, ce ne sont pas des préférences, ce sont
-- des **limites** — celles que le ticket écrit en toutes lettres :
--
--   1. jamais un membre absent, ni un membre qui n'a rien saisi ;
--   2. jamais au-delà d'un plafond déclaré (astreintes et weekends) ;
--   3. jamais au-delà de l'effectif requis d'un créneau ;
--   4. jamais deux fois le même membre sur le même créneau ;
--   5. jamais une attribution déjà posée qui bouge.
--
-- Un plan qui enfreint l'une d'elles n'échoue pas : la ligne fautive est
-- **écartée**, avec son motif, et les autres passent. C'est la forme des refus
-- métier de tout ce schéma (`publish_schedule`, `reassign_shift`) — rien ne
-- lève pour un refus attendu.

-- ===========================================================================
-- apply_auto_proposal — appliquer un remplissage, en une transaction
-- ===========================================================================
-- Réservée au rôle de service : appelée par l'Edge Function `auto-propose`
-- (docs/SCHEMA.md § 7), jamais par un client. Même forme que `reassign_shift`
-- (0020) et `publish_schedule` (0019) : l'acteur est passé en paramètre et
-- **vérifié ici**, `auth.uid()` étant nul sous le rôle de service.
--
-- `p_picks` est un tableau JSON d'objets `{"shift_id": uuid, "user_id": uuid}`,
-- **dans l'ordre où ils doivent être posés**. L'ordre compte : c'est celui du
-- mois, et c'est lui qui rend le résultat reproductible quand deux lignes se
-- disputent la dernière place d'un quota.
--
-- **Un verrou, celui du planning.** Il sérialise deux administrateurs qui
-- appuieraient sur le bouton en même temps. Sans lui, chacun lirait « il reste
-- une place » sur le même créneau et deux pompiers seraient posés là où un seul
-- est demandé : la contrainte `assignments_active_uniq` ne l'interdit pas, elle
-- ne parle que du même membre deux fois. C'est le même verrou, sur la même
-- ligne, que celui de `reassign_shift`.
create function apply_auto_proposal(p_schedule uuid, p_actor uuid, p_picks jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  -- Le plafond de lignes acceptées en un appel. Un mois de 31 jours compte
  -- 62 créneaux ; à trois pompiers par créneau on est encore sous 200. 500
  -- laisse de la marge et refuse une charge utile qui n'aurait aucun sens.
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

  -- Le verrou, puis la relecture du statut : l'adjoint a pu publier pendant
  -- qu'on attendait. Une proposition automatique ne s'applique qu'à un
  -- **brouillon** — après publication, un créneau se repourvoit un par un, et
  -- chaque geste fait sonner un téléphone (ticket 020).
  select * into planning from schedules where id = p_schedule for update;

  if planning.status <> 'draft' then
    return jsonb_build_object('ok', false, 'code', 'schedule_not_draft',
                              'status', planning.status);
  end if;

  select * into periode from periods where id = planning.period_id;
  premier := make_date(periode.year, periode.month, 1);
  suivant := (premier + interval '1 month')::date;

  for ligne in select * from jsonb_array_elements(p_picks)
  loop
    motif := null;

    -- Une forme d'uuid vérifiée avant la conversion : un `::uuid` sur une
    -- chaîne libre lèverait, et une ligne mal formée doit être écartée comme
    -- les autres, pas faire tomber le reste du mois.
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

    -- 3. **Disponible, et déclaré tel.** Un seul test écarte les deux cas que
    -- le ticket sépare : l'absent a une ligne `absent`, celui qui n'a rien
    -- saisi n'a pas de ligne du tout. Ni l'un ni l'autre n'a dit oui, et une
    -- machine ne désigne que ceux qui ont dit oui. L'administrateur, lui, garde
    -- le droit d'attribuer hors disponibilité (docs/PRD.md § 6.4) : à la main,
    -- avec l'avertissement et la trace d'audit du ticket 017.
    elsif not exists (
      select 1 from availabilities a
      where a.station_id = planning.station_id
        and a.user_id    = v_user
        and a.date       = creneau.date
        and a.slot       = creneau.slot
        and a.status     = 'available'
    ) then
      motif := 'not_available';

    -- 4. Déjà sur ce créneau : la contrainte le dirait en 23505, un motif se
    -- lit mieux.
    elsif exists (
      select 1 from assignments a
      where a.shift_id = v_shift
        and a.user_id  = v_user
        and a.status in ('proposed', 'accepted')
    ) then
      motif := 'already_assigned';

    -- 5. **Les places.** Le remplissage complète, il ne renforce pas : un
    -- créneau déjà pourvu est refusé, exactement comme dans `reassign_shift`.
    -- C'est ce test qui tient la règle des créneaux à plusieurs — la deuxième
    -- place s'ouvre parce que `required_count` vaut deux, pas parce que
    -- quelqu'un l'a demandé.
    elsif (
      select count(*) from assignments a
       where a.shift_id = v_shift
         and a.status in ('proposed', 'accepted')
    ) >= creneau.required_count then
      motif := 'shift_already_filled';
    end if;

    if motif is null then
      -- 6. Les deux plafonds du mois, lus dans les préférences du membre pour
      -- cette période (docs/SCHEMA.md § 2.7). `null` vaut **illimité**, jamais
      -- zéro.
      select prefs.max_shifts, prefs.max_weekends
        into plafond_astreintes, plafond_weekends
        from availability_preferences prefs
       where prefs.station_id = planning.station_id
         and prefs.user_id    = v_user
         and prefs.period_id  = planning.period_id;

      -- Le compte du mois est **relu à chaque ligne**, donc il inclut les
      -- attributions posées par cet appel : c'est ce qui fait qu'un quota de
      -- trois ne devient jamais quatre au cours du même remplissage. Il compte
      -- comme `v_member_load` compte — proposées et acceptées, la caserne
      -- seule, le mois de la période.
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

      -- Un créneau de semaine ne coûte aucun weekend. Un créneau qui tombe dans
      -- une unité que le membre **couvre déjà** ne lui en coûte pas un de plus :
      -- le samedi et le dimanche d'un même weekend font une unité, et quatre
      -- créneaux de ce weekend en font toujours une (ticket 011, fonction
      -- `unite_weekend`, migration 0017).
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

    -- `was_available` vaut vrai parce que le test 3 vient de l'établir sur la
    -- table des disponibilités, et `created_by` porte l'administrateur qui a
    -- appuyé — pas le rôle de service. Le déclencheur
    -- `assignments_trace_disponibilite` (0018) ne repasse pas derrière une
    -- écriture serveur : c'est donc ici, et nulle part ailleurs, que ces deux
    -- colonnes se posent pour cette voie.
    --
    -- `proposed_at` reste nul : le brouillon n'a rien envoyé
    -- (docs/WORKFLOWS.md § 3).
    insert into assignments (
      station_id, shift_id, user_id, status, was_available, created_by)
    values (
      planning.station_id, v_shift, v_user, 'proposed', true, p_actor);

    poses := poses + 1;
  end loop;

  -- Ce qui reste à découvert **après** coup, compté sur la base et non sur ce
  -- que le client croyait : c'est ce nombre-là que l'écran annonce.
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
    'shifts_short',  restants);
end $$;

comment on function apply_auto_proposal(uuid, uuid, jsonb) is
  'Applique un plan de remplissage (liste ordonnée de couples créneau / pompier) sur un planning en brouillon, dans une seule transaction : membre actif et déclaré disponible, plafonds d''astreintes et de weekends jamais dépassés, effectif requis jamais dépassé, attributions déjà posées jamais touchées. Une ligne refusée est écartée avec son motif, les autres passent. Le choix des pompiers, lui, est fait par l''application (ticket 017). Réservée au rôle de service.';

revoke execute on function apply_auto_proposal(uuid, uuid, jsonb) from public, anon, authenticated;
