-- 0019 — La publication d'un planning, son suivi et sa validation.
-- Ticket 019. Référence : docs/SCHEMA.md sections 2.8 à 2.10, 4, 5, 6, 7 et 9 ;
-- docs/WORKFLOWS.md sections 2, 3, 4 et 8 ; docs/PRD.md sections 5.4, 6.4 et 7 ;
-- supabase/functions/README.md (§ send-notification) ;
-- design/019-publication-suivi.md sections 7.1 et 7.2.
--
-- Ce que cette migration ajoute, et pourquoi
-- ------------------------------------------
--   1. `schedules_guard_transition` : la machine à états de docs/WORKFLOWS.md
--      § 2, imposée en base. **C'est la condition d'entrée du ticket** : sans
--      elle, un retour en brouillon puis une suppression d'attribution
--      effaçaient une proposition déjà partie.
--   2. `schedules_guard_suppression` + politique restreinte : un planning ne se
--      supprime qu'en brouillon, **cascade comprise**.
--   3. `publish_schedule(planning, acteur)` : la publication, atomique, avec les
--      destinataires **déjà groupés par membre**.
--   4. `schedule_auto_validate` : la validation sans action d'administrateur,
--      annoncée par docs/SCHEMA.md § 5 et laissée en attente du ticket 025.
--   5. `remind_schedule(planning)` : la relance manuelle des retardataires,
--      celle du bouton « Relancer maintenant ».
--   6. L'inscription de `schedules` dans la publication `supabase_realtime`.
--
-- Ce qui existait déjà et n'est pas réécrit
-- -----------------------------------------
--   - `v_schedule_progress` (0018) : la vue du suivi est livrée, ce ticket la
--     **lit** pour la première fois et n'y touche pas.
--   - `assignments_member_transition` (0008) : la réponse d'un membre, déjà
--     verrouillée. C'est elle qui déclenche l'auto-validation, pas l'inverse.
--   - `notify(...)` (0014) : le point d'entrée des notifications depuis la
--     base. `schedule_auto_validate` et `remind_schedule` l'appellent tel quel.
--   - `assignments_delete_admin` (0018), déjà bornée au brouillon. Elle ne
--     tenait que parce que rien ne ramenait un planning en brouillon : c'est
--     exactement ce que le point 1 vient garantir.

-- ===========================================================================
-- 1. La machine à états des plannings
-- ===========================================================================
-- docs/WORKFLOWS.md § 2, en toutes lettres :
--
--     draft     --> published   (admin publie)
--     published --> validated   (toutes les attributions requises acceptées)
--     validated --> published   (admin modifie un créneau)
--     published --> archived    (cron, mois passé)
--     validated --> archived    (cron, mois passé)
--
-- Rien en base ne l'imposait. `schedules_update_admin` (0007, durcie en 0008)
-- laisse un administrateur écrire **n'importe quel** statut, y compris
-- `published -> draft`. Enchaîné avec `assignments_delete_admin` — que le 017 a
-- restreinte au brouillon — l'exploit tient en deux écritures : ramener le
-- planning en brouillon, supprimer l'attribution qu'un pompier a déjà reçue,
-- republier. La règle produit « l'historique n'est jamais supprimé »
-- (docs/PRD.md § 7.6) ne tenait qu'à la discipline des écrans.
--
-- **Security invoker, et la règle vaut aussi pour le rôle de service.** Même
-- position que `periods_guard_transition` (0012) : une machine à états est une
-- propriété du domaine, pas une règle d'interface. Les trois écritures serveur
-- qui existent — `publish_schedule`, `schedule_auto_validate`,
-- `archive_schedules` (ticket 022) — sont toutes dans le tableau ci-dessus. Une
-- écriture serveur qui voudrait en sortir est un bogue, et il doit s'entendre.
--
-- Les deux horodatages ne sont pas des colonnes libres :
--   - `published_at` est posé à la **première** publication et jamais réécrit.
--     Un retour de `validated` vers `published` (modification d'un créneau,
--     ticket 020) ne réécrit pas l'histoire du mois.
--   - `validated_at` est posé à la validation et **effacé** au retour en
--     `published` : un planning qui n'est plus validé n'a pas de date de
--     validation.
create function schedules_guard_transition() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.station_id <> old.station_id or new.period_id <> old.period_id then
    raise exception 'schedule_key_immutable'
      using hint = 'La caserne et le mois d''un planning ne se modifient pas.';
  end if;

  if new.status is distinct from old.status then
    -- Le tableau de docs/WORKFLOWS.md § 2, lu de gauche à droite. Tout ce qui
    -- n'y figure pas est refusé, à commencer par tout retour en brouillon.
    if not (
         (old.status = 'draft'     and new.status = 'published')
      or (old.status = 'published' and new.status in ('validated', 'archived'))
      or (old.status = 'validated' and new.status in ('published', 'archived'))
    ) then
      raise exception 'schedule_invalid_transition'
        using hint = format(
          'Transition interdite : %s vers %s (docs/WORKFLOWS.md § 2).',
          old.status, new.status);
    end if;

    if new.status = 'published' then
      -- `coalesce` dans cet ordre : la première publication gagne, toujours.
      new.published_at := coalesce(old.published_at, new.published_at, now());
      new.validated_at := null;
    elsif new.status = 'validated' then
      new.validated_at := coalesce(new.validated_at, now());
    end if;
  else
    -- Statut inchangé : les horodatages ne se réécrivent pas davantage. Sans
    -- cette branche, un simple `update schedules set published_at = null`
    -- effacerait la date de publication sans changer d'état.
    new.published_at := old.published_at;
    new.validated_at := old.validated_at;
  end if;

  return new;
end $$;

comment on function schedules_guard_transition() is
  'Impose la machine à états des plannings (docs/WORKFLOWS.md § 2), gèle la clé (caserne, période) et tient published_at / validated_at. Aucun retour en brouillon n''est possible, pour personne.';

revoke execute on function schedules_guard_transition() from public, anon, authenticated;

create trigger schedules_guard_transition
  before update on schedules
  for each row execute function schedules_guard_transition();

-- ===========================================================================
-- 2. Supprimer un planning : en brouillon, et nulle part ailleurs
-- ===========================================================================
-- Supprimer un planning publié, c'est supprimer ses créneaux et **toutes ses
-- attributions** par cascade : l'historique disparaît sans laisser de trace, et
-- c'est un raccourci plus court encore que le retour en brouillon.
--
-- La garde est **double**, et les deux moitiés sont nécessaires :
--
--   1. la politique, pour que le § 4 de docs/SCHEMA.md reste vrai table par
--      table et pour que le refus d'un client soit lisible (0 ligne, pas une
--      exception) ;
--   2. le **déclencheur**, parce qu'une suppression en cascade ne consulte
--      aucune politique RLS — elle s'exécute sous l'identité du propriétaire de
--      la table. `periods` cascade vers `schedules` : sans ce déclencheur,
--      supprimer le **mois** emporte le planning publié par la bande. Les
--      actions d'intégrité référentielle, elles, déclenchent bien les triggers
--      de ligne de la table enfant : c'est le seul mécanisme que la cascade
--      consulte, donc le seul qui puisse l'arrêter.
create function schedules_guard_suppression() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if old.status <> 'draft' then
    raise exception 'schedule_delete_published'
      using hint = 'Un planning publié ne se supprime pas : il s''archive. Ses attributions sont l''historique de la caserne (docs/PRD.md § 7.6).';
  end if;
  return old;
end $$;

comment on function schedules_guard_suppression() is
  'Refuse la suppression d''un planning qui n''est plus en brouillon, y compris quand elle arrive en cascade depuis periods ou stations.';

revoke execute on function schedules_guard_suppression() from public, anon, authenticated;

create trigger schedules_guard_suppression
  before delete on schedules
  for each row execute function schedules_guard_suppression();

drop policy "schedules_delete_admin" on schedules;

create policy "schedules_delete_admin"
  on schedules for delete to authenticated
  using (
    is_admin(station_id)
    and station_writable(station_id)
    and status = 'draft'
  );

-- ===========================================================================
-- 3. publish_schedule — la publication, en une transaction
-- ===========================================================================
-- Réservée au rôle de service : elle est appelée par l'Edge Function
-- `publish-schedule`, jamais par un client. Même forme que `create_invitation`
-- (0009) — l'acteur est passé en paramètre et vérifié ici, les refus métier
-- sortent en `{"ok": false, "code": …}` que l'Edge Function traduit en statut
-- HTTP, et rien ne lève pour un refus attendu.
--
-- **Pourquoi du SQL plutôt que trois requêtes depuis Deno** : le statut, les
-- horodatages des attributions et la ligne d'audit doivent être tout ou rien.
-- Une publication à moitié faite — des attributions horodatées sur un planning
-- resté en brouillon — ne se rattrape par aucune reprise. Une fonction plpgsql
-- s'exécute dans une transaction implicite ; trois appels PostgREST, non.
--
-- **Les destinataires sortent d'ici déjà groupés par membre**, un objet par
-- pompier avec tous ses créneaux. `send-notification` sait regrouper — c'est sa
-- promesse et elle est testée chez elle — mais faire le travail ici le rend
-- vérifiable par `scripts/test_rls.sh`, qui tourne en CI là où les Edge
-- Functions ne sont pas joignables (supabase/functions/README.md § Tests). Et le
-- nombre annoncé à l'administrateur (« 18 pompiers notifiés ») vient alors du
-- même comptage que l'envoi, jamais d'un second.
--
-- L'envoi, lui, n'est **pas** fait ici. Il vient après, depuis l'Edge Function,
-- et il ne peut donc pas défaire une publication déjà acquise : une notification
-- perdue se rattrape (file de `notify`, relance manuelle, crons du 022), une
-- publication à moitié faite ne se rattrape pas.
create function publish_schedule(p_schedule uuid, p_actor uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  planning     schedules;
  periode      periods;
  cle_periode  text;
  horodatage   timestamptz := now();
  attribuees   integer;
  destinataires jsonb;
begin
  select * into planning from schedules where id = p_schedule;
  if planning.id is null then
    return jsonb_build_object('ok', false, 'code', 'schedule_not_found');
  end if;

  -- L'acteur est vérifié ici, pas cru sur parole : `is_admin` lit `auth.uid()`
  -- et cette fonction tourne sous le rôle de service, où il est nul. Le test
  -- est donc écrit explicitement sur `memberships`.
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

  if planning.status <> 'draft' then
    return jsonb_build_object(
      'ok', false, 'code', 'schedule_not_draft', 'status', planning.status);
  end if;

  select * into periode from periods where id = planning.period_id;
  -- La clé `AAAA-MM` que lit `send-notification` (supabase/functions/README.md).
  cle_periode := to_char(make_date(periode.year, periode.month, 1), 'YYYY-MM');

  -- 1. Le planning passe en publié. Le déclencheur pose `published_at`.
  update schedules
     set status = 'published'
   where id = planning.id
   returning * into planning;

  -- 2. Chaque attribution du brouillon est horodatée. `proposed_at` est le
  --    signal « c'est parti » : les crons de relance ignorent `null`
  --    (docs/WORKFLOWS.md § 3), et `v_schedule_progress` n'appelle jamais un
  --    brouillon « en retard ». Les attributions déjà horodatées — il ne peut
  --    pas y en avoir sur un brouillon, mais la requête ne le suppose pas —
  --    gardent leur date.
  with horodatees as (
    update assignments a
       set proposed_at = horodatage
      from shifts sh
     where sh.id = a.shift_id
       and sh.schedule_id = planning.id
       and a.station_id = planning.station_id
       and a.status = 'proposed'
       and a.proposed_at is null
     returning a.id
  )
  select count(*)::integer into attribuees from horodatees;

  -- 3. Les destinataires, **un objet par membre**, créneaux triés par date puis
  --    jour avant nuit — l'ordre dans lequel `send-notification` les rendra.
  select coalesce(jsonb_agg(d.entree order by d.user_id), '[]'::jsonb)
    into destinataires
    from (
      select
        a.user_id,
        jsonb_build_object(
          'user_id', a.user_id,
          'payload', jsonb_build_object(
            'shifts', jsonb_agg(
              jsonb_build_object(
                'date',          sh.date,
                'slot',          sh.slot,
                'assignment_id', a.id)
              order by sh.date, sh.slot))
        ) as entree
      from assignments a
      join shifts sh on sh.id = a.shift_id
     where sh.schedule_id = planning.id
       and a.station_id = planning.station_id
       and a.status = 'proposed'
       and a.proposed_at is not null
     group by a.user_id
    ) d;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    planning.station_id, p_actor,
    'schedule.published', 'schedule', planning.id,
    jsonb_build_object(
      'period',      cle_periode,
      'assignments', attribuees,
      'recipients',  jsonb_array_length(destinataires))
  );

  return jsonb_build_object(
    'ok',            true,
    'schedule_id',   planning.id,
    'station_id',    planning.station_id,
    'status',        planning.status,
    'published_at',  planning.published_at,
    'period',        cle_periode,
    'assignments',   attribuees,
    'recipients',    destinataires);
end $$;

comment on function publish_schedule(uuid, uuid) is
  'Publie un planning en une transaction : statut, proposed_at de chaque attribution, audit. Rend les destinataires déjà groupés par membre, prêts pour send-notification. Réservée au rôle de service.';

revoke execute on function publish_schedule(uuid, uuid) from public, anon, authenticated;

-- ===========================================================================
-- 4. schedule_auto_validate — la validation sans personne
-- ===========================================================================
-- docs/SCHEMA.md § 5 : « après update d'un `assignment`, si tous les créneaux du
-- planning ont `count(accepted) >= required_count`, passe le planning en
-- `validated` et insère une notification `schedule_validated` ».
--
-- **La validation se juge sur les acceptations seules**, jamais sur
-- `v_schedule_progress.shifts_filled`, qui compte les attributions *actives*.
-- Deux questions, deux chiffres (docs/SCHEMA.md § 6) : un créneau couvert par
-- une proposition sans réponse est *pourvu* du point de vue de la construction
-- et *pas encore acquis* du point de vue de la validation.
--
-- **Une seule fois, quoi qu'il arrive.** L'`update … where status = 'published'
-- returning` prend un verrou de ligne : deux acceptations simultanées qui voient
-- toutes deux le planning complet ne rendent qu'une ligne, donc **une** salve de
-- notifications. Arbitrer sur l'ordre d'arrivée aurait donné deux « Planning
-- validé » à soixante personnes.
--
-- La clause `when` du déclencheur porte le test : la fonction n'est pas appelée
-- pour les refus, les annulations, ni pour les mises à jour ordinaires.
create function schedule_auto_validate() returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  planning  schedules;
  periode   periods;
  valide    uuid;
  membres   uuid[];
begin
  select sc.* into planning
    from shifts sh
    join schedules sc on sc.id = sh.schedule_id
   where sh.id = new.shift_id;

  if planning.id is null or planning.status <> 'published' then
    return null;
  end if;

  -- Un seul créneau en défaut suffit à répondre non : `exists` s'arrête au
  -- premier, là où un `count(*) = 0` parcourrait les soixante-deux.
  if exists (
    select 1
      from shifts sh
     where sh.schedule_id = planning.id
       and sh.required_count > (
         select count(*)
           from assignments a
          where a.shift_id = sh.id
            and a.station_id = sh.station_id
            and a.status = 'accepted')
  ) then
    return null;
  end if;

  update schedules
     set status = 'validated'
   where id = planning.id
     and status = 'published'
   returning id into valide;

  -- Quelqu'un d'autre a validé dans la même milliseconde : il a notifié.
  if valide is null then
    return null;
  end if;

  select * into periode from periods where id = planning.period_id;

  -- docs/WORKFLOWS.md § 8 : `schedule_validated`, tous les membres, regroupé.
  -- Les administrateurs sont des membres et le reçoivent aussi : ils n'ont pas
  -- déclenché la transition, ils ont le droit de l'apprendre.
  select array_agg(m.user_id order by m.user_id) into membres
    from memberships m
   where m.station_id = planning.station_id
     and m.status = 'active';

  if membres is null or array_length(membres, 1) = 0 then
    return null;
  end if;

  perform notify(
    'schedule_validated',
    p_user_ids => membres,
    p_station  => planning.station_id,
    p_payload  => jsonb_build_object('period', to_char(make_date(periode.year, periode.month, 1), 'YYYY-MM')),
    -- La clé porte l'instant de validation : un planning revalidé après une
    -- modification de créneau (ticket 020) est un **second** fait, et il doit
    -- repartir. Ce que la clé écarte, ce sont deux appels dans la même
    -- transaction, pas deux validations successives.
    p_dedupe_key => format('schedule_validated:%s:%s',
                           planning.id, extract(epoch from now())::bigint));

  return null;
end $$;

comment on function schedule_auto_validate() is
  'Passe un planning publié en validé dès que chaque créneau atteint son effectif requis en attributions acceptées, et notifie tous les membres actifs (docs/WORKFLOWS.md § 4).';

revoke execute on function schedule_auto_validate() from public, anon, authenticated;

create trigger schedule_auto_validate
  after update on assignments
  for each row
  when (new.status = 'accepted' and old.status is distinct from new.status)
  execute function schedule_auto_validate();

-- ===========================================================================
-- 5. remind_schedule — la relance manuelle des retardataires
-- ===========================================================================
-- Le bouton « Relancer maintenant » de l'écran de suivi. Les crons de relance
-- automatique sont le ticket 022 ; celui-ci livre le geste qu'on fait en
-- regardant la liste.
--
-- **Le retard a une seule définition dans tout le produit** : celle de
-- `v_schedule_progress.assignments_late` — `proposed`, `proposed_at` non nul et
-- plus vieux que `settings.late_report_hours`. La vue compte, cette fonction
-- relance, et aucune des deux ne redéfinit le retard pour son compte.
--
-- **Idempotente à l'heure.** `p_dedupe_key` porte l'heure courante : un double
-- clic, ou deux adjoints qui appuient ensemble, ne coûtent rien —
-- `notification_outbox_dedupe_uniq` écarte la seconde ligne et `notify` rend
-- l'identifiant de la première. C'est l'idiome du projet
-- (`cron_availability_reminders`, 0016), et il vaut mieux qu'un compteur d'état.
--
-- `reminder_count` et `last_reminder_at` sont mis à jour pour les attributions
-- réellement relancées : les crons du 022 verront qu'un palier est déjà passé,
-- et l'écran peut dire « relancé il y a 20 min » au lieu de laisser croire que
-- rien n'est parti.
create function remind_schedule(p_schedule uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  planning      schedules;
  caserne       stations;
  periode       periods;
  cle_periode   text;
  seuil         timestamptz;
  destinataires jsonb;
  relancees     integer := 0;
  file          uuid;
begin
  select * into planning from schedules where id = p_schedule;
  if planning.id is null then
    raise exception 'schedule_not_found'
      using hint = 'Ce planning n''existe pas.';
  end if;

  if not is_admin(planning.station_id) then
    raise exception 'forbidden'
      using hint = 'Seul un administrateur de la caserne relance ses pompiers.';
  end if;

  if not station_writable(planning.station_id) then
    raise exception 'station_suspended'
      using hint = 'L''abonnement de la caserne est suspendu : l''application est en lecture seule.';
  end if;

  if planning.status <> 'published' then
    return jsonb_build_object('ok', false, 'code', 'schedule_not_published',
                              'status', planning.status);
  end if;

  select * into caserne from stations where id = planning.station_id;
  select * into periode from periods where id = planning.period_id;
  cle_periode := to_char(make_date(periode.year, periode.month, 1), 'YYYY-MM');

  seuil := now() - make_interval(
    hours => coalesce((caserne.settings ->> 'late_report_hours')::int, 72));

  with tardives as (
    select a.id, a.user_id, sh.date, sh.slot
      from assignments a
      join shifts sh on sh.id = a.shift_id
     where sh.schedule_id = planning.id
       and a.station_id = planning.station_id
       and a.status = 'proposed'
       and a.proposed_at is not null
       and a.proposed_at < seuil
  ),
  marquees as (
    update assignments a
       set reminder_count   = a.reminder_count + 1,
           last_reminder_at = now()
      from tardives t
     where a.id = t.id
     returning a.id
  )
  select
    coalesce(jsonb_agg(g.entree order by g.user_id), '[]'::jsonb),
    (select count(*)::integer from marquees)
    into destinataires, relancees
    from (
      select
        t.user_id,
        jsonb_build_object(
          'user_id', t.user_id,
          'payload', jsonb_build_object(
            'shifts', jsonb_agg(
              jsonb_build_object('date', t.date, 'slot', t.slot)
              order by t.date, t.slot))
        ) as entree
      from tardives t
     group by t.user_id
    ) g;

  if jsonb_array_length(destinataires) = 0 then
    return jsonb_build_object('ok', true, 'members', 0, 'assignments', 0,
                              'outbox_id', null);
  end if;

  file := notify(
    'assignment_reminder',
    p_station    => planning.station_id,
    p_payload    => jsonb_build_object('period', cle_periode),
    p_recipients => destinataires,
    p_dedupe_key => format('assignment_reminder:%s:manuel:%s',
                           planning.id,
                           to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24')));

  return jsonb_build_object(
    'ok',          true,
    'members',     jsonb_array_length(destinataires),
    'assignments', relancees,
    'outbox_id',   file);
end $$;

comment on function remind_schedule(uuid) is
  'Relance en une notification par membre les attributions sans réponse depuis plus de late_report_hours. Idempotente à l''heure par sa clé de dédoublonnage.';

revoke execute on function remind_schedule(uuid) from public, anon;
grant  execute on function remind_schedule(uuid) to authenticated;

-- ===========================================================================
-- 6. Le temps réel sur les plannings
-- ===========================================================================
-- docs/SCHEMA.md § 9 : « Realtime activé sur `assignments`, `schedules`,
-- `notifications` uniquement ». `assignments` y est entrée au 017 ; `schedules`
-- entre ici, parce que **la validation automatique est un `update` que personne
-- ne déclenche depuis l'écran de suivi**. Sans ce canal, le chef verrait les
-- réponses arriver une à une et ne verrait jamais le planning se valider.
--
-- Les trois vérifications du 017 § 7.2, refaites pour cette table :
--
--   1. **Aucun `grant` de colonne restrictif** sur `schedules` : ce que
--      `authenticated` lit par `select`, il peut le recevoir ici. Les huit
--      colonnes sont des identifiants, un statut et des dates ; aucune n'est un
--      porteur de droits, contrairement à `invitations.token`.
--   2. **Le filtrage ligne à ligne suffit** :
--      `schedules_select_member_published` ne donne un planning à un membre que
--      si `status <> 'draft'`. Un brouillon ne part donc à personne, y compris
--      par ce canal — et c'est l'événement `draft -> published` lui-même qui
--      ouvre la porte, ce qui est exactement le comportement voulu.
--   3. **L'identité de réplique reste `default`** : une suppression ne diffuse
--      que la clé primaire. Et depuis le point 2 de cette migration, une
--      suppression de planning publié n'existe plus du tout.
alter table schedules replica identity default;

do $publication$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'Publication supabase_realtime absente : rien à inscrire.';
    return;
  end if;

  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'schedules'
  ) then
    return;
  end if;

  alter publication supabase_realtime add table schedules;
exception
  -- Sur un projet hébergé, la publication appartient à `supabase_admin`. Même
  -- garde-fou qu'au 018 : un canal de confort ne bloque pas un déploiement.
  when insufficient_privilege then
    raise notice 'Droits insuffisants pour inscrire schedules dans supabase_realtime.';
end $publication$;
