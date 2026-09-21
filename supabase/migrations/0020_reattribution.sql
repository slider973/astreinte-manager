-- 0020 — Réattribuer un créneau refusé, annuler une astreinte acceptée.
-- Ticket 020. Référence : docs/SCHEMA.md sections 2.8 à 2.10, 3, 4, 5 et 7 ;
-- docs/WORKFLOWS.md sections 2, 3, 5 et 8 ; docs/PRD.md sections 5.4, 7.2, 7.3
-- et 7.6 ; supabase/functions/README.md ; design/020-reattribution.md § 3 et § 7.
--
-- Le principe qui commande toute la migration
-- -------------------------------------------
--   **Un changement d'état qui ne se dit pas est un mensonge.** Un pompier dont
--   l'attribution acceptée passe à `replaced` sans notification continue de se
--   croire d'astreinte : il notera la date, refusera un déplacement, et ne
--   viendra pas parce que personne ne l'attend. Ce n'est pas un défaut
--   d'affichage, c'est un trou opérationnel.
--
--   D'où la forme retenue : la transition, le lien et la **demande de
--   notification** sont écrits dans la même transaction, et un client ne peut
--   pas écrire ces statuts autrement.
--
-- Ce que cette migration ajoute
-- -----------------------------
--   1. `assignments_guard_reattribution` : ni `replaced`, ni `cancelled`, ni
--      `replaced_by` ne s'écrivent depuis un client. Ces trois écritures
--      passent par les deux fonctions ci-dessous, qui notifient.
--   2. `reassign_shift(créneau, membre, acteur, ancienne)` : la réattribution,
--      **en une transaction**. Réservée au rôle de service, appelée par l'Edge
--      Function `reassign-shift`.
--   3. `cancel_assignment(attribution, motif)` : l'annulation d'une astreinte,
--      ouverte à `authenticated` comme `remind_schedule` (0019).
--   4. Le déclencheur d'auto-validation, **rouvert dans l'autre sens** : une
--      acceptation qui disparaît ramène un planning validé en publié.
--
-- Ce qui existait déjà et n'est pas réécrit
-- -----------------------------------------
--   - `schedules_guard_transition` (0019) autorise déjà `validated ->
--     published`, efface `validated_at` et **conserve** `published_at`. Ce
--     ticket lui apporte son appelant, pas une règle de plus.
--   - `schedule_reevaluer` (0019) traite déjà les deux sens.
--   - `notify(...)` (0014) : le point d'entrée des notifications depuis la
--     base, avec sa file et son rejeu.
--   - `assignments_active_uniq` (0004) : un membre n'a qu'une attribution
--     active par créneau. C'est elle qui rend `already_assigned` inévitable
--     plutôt que seulement poli.

-- ===========================================================================
-- 1. Les statuts terminaux et le lien de remplacement, hors de portée du client
-- ===========================================================================
-- `assignments_update_admin` et `assignments_insert_admin` (0008) laissent un
-- administrateur écrire **n'importe quel statut** sur n'importe quelle
-- attribution de sa caserne, `replaced` et `cancelled` compris, et
-- `assignments_member_transition` (0008) le laisse passer dès sa première ligne
-- (`if is_admin(...) then return new`). Une requête PostgREST suffisait donc à
-- retirer sa garde à un pompier **sans que rien ne parte**.
--
-- Le déclencheur ferme cette porte. Quatre règles, et chacune a été franchie en
-- revue avant d'être écrite :
--
--   1. **Aucune entrée dans un état terminal.** La garde ne portait d'abord que
--      sur la mise à jour : un client insérait alors directement une ligne
--      `declined` ou `cancelled`, avec son lien de remplacement, et fabriquait
--      un refus que personne n'avait prononcé. Un statut terminal se **rejoint**
--      par une transition notifiée, il ne s'écrit pas d'un coup.
--   2. **Aucune sortie d'un état terminal.** La garde regardait le nouveau
--      statut et jamais l'ancien : ramener un refus à `proposed` en effaçant son
--      motif faisait disparaître le refus du suivi et redonnait au pompier une
--      proposition sans rien lui envoyer ; ramener un `replaced` à `accepted`
--      ressuscitait une garde qui gardait son lien et pouvait valider le
--      planning. **L'historique n'est jamais réécrit** (docs/PRD.md § 7.6) : la
--      suppression était déjà fermée (0018, 0019), l'aller-retour ne l'était
--      pas.
--   3. **Le motif d'un refus est gelé.** Il appartient au pompier qui l'a écrit.
--      `assignments_member_transition` ne l'autorise que dans la transition
--      `proposed -> declined` ; un administrateur passait à travers.
--   4. **`replaced_by` ne se pose pas à la main, et ne désigne pas n'importe
--      quoi.** Le client fournissant l'identifiant de la ligne qu'il insère, il
--      pouvait relier une attribution à elle-même, ou à une attribution d'un
--      autre créneau — voire d'une autre caserne, que nulle contrainte
--      n'empêchait. Ces deux dernières vérifications valent pour **tout le
--      monde**, rôle de service compris : ce n'est pas une règle d'interface,
--      c'est la cohérence du fil de l'histoire.
--
-- Même construction que `assignments_trace_disponibilite` (0018) :
--
--   - **security invoker**, et c'est structurel. En `security definer`,
--     `current_user` vaudrait le propriétaire de la fonction et le test
--     « écriture serveur ? » répondrait oui pour tout le monde : la garde ne
--     s'appliquerait à personne.
--   - nommé pour passer **avant** `assignments_member_transition` (ordre
--     alphabétique des déclencheurs) : un refus doit se lire sur la règle la
--     plus précise, pas sur le `forbidden` générique de la liste blanche.
create function assignments_guard_reattribution() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  terminaux constant assignment_status[] :=
    array['declined', 'replaced', 'cancelled']::assignment_status[];
  client boolean := current_user in ('authenticated', 'anon');
begin
  -- ----------------------------------------------------------------
  -- Ce qui vaut pour tout le monde : la cohérence du lien.
  -- ----------------------------------------------------------------
  if new.replaced_by is not null then
    if new.replaced_by = new.id then
      raise exception 'assignment_link_self'
        using hint = 'Une attribution ne se remplace pas elle-même.';
    end if;

    if not exists (
      select 1 from assignments a
       where a.id = new.replaced_by
         and a.shift_id = new.shift_id
    ) then
      raise exception 'assignment_link_foreign_shift'
        using hint = 'Le remplacement d''une attribution se trouve sur le même créneau qu''elle : un lien vers un autre créneau, ou une autre caserne, ne raconte aucune histoire.';
    end if;
  end if;

  -- Écritures serveur : `reassign_shift`, `cancel_assignment`, le seed, les
  -- migrations. Elles savent ce qu'elles écrivent, et elles notifient.
  if not client then
    return new;
  end if;

  -- ----------------------------------------------------------------
  -- Ce qui vaut pour un client : on n'entre, on ne sort et on ne relie pas.
  -- ----------------------------------------------------------------
  if tg_op = 'INSERT' then
    if new.status = any(terminaux) then
      raise exception 'assignment_transition_reserved'
        using hint = 'Une attribution ne naît pas refusée, remplacée ni annulée : ces états se rejoignent par une transition que quelqu''un reçoit.';
    end if;

    if new.replaced_by is not null then
      raise exception 'assignment_link_reserved'
        using hint = 'Le lien entre une attribution et celle qui la remplace est posé par reassign_shift.';
    end if;

    return new;
  end if;

  if new.status is distinct from old.status then
    if new.status in ('replaced', 'cancelled') then
      raise exception 'assignment_transition_reserved'
        using hint = 'Remplacer ou annuler une attribution passe par reassign_shift ou cancel_assignment : le pompier concerné doit être prévenu dans la même transaction.';
    end if;

    if old.status = any(terminaux) then
      raise exception 'assignment_transition_terminal'
        using hint = format(
          'Une attribution %s ne repart pas : l''historique de la caserne ne se réécrit pas (docs/PRD.md § 7.6). Pour repourvoir le créneau, réattribuer.',
          old.status);
    end if;
  end if;

  -- Le motif appartient à qui l'a écrit. Une fois le refus prononcé, il est
  -- l'information la plus utile du suivi : l'effacer ferait disparaître la
  -- raison de chercher quelqu'un d'autre.
  if old.status = 'declined'
     and new.decline_reason is distinct from old.decline_reason then
    raise exception 'assignment_reason_frozen'
      using hint = 'Le motif d''un refus appartient au pompier qui l''a écrit.';
  end if;

  if new.replaced_by is distinct from old.replaced_by then
    raise exception 'assignment_link_reserved'
      using hint = 'Le lien entre une attribution et celle qui la remplace est posé par reassign_shift.';
  end if;

  return new;
end $$;

comment on function assignments_guard_reattribution() is
  'Tient les statuts terminaux et le lien replaced_by hors de portée d''un client : on n''y entre pas par une insertion, on n''en sort pas par une mise à jour, le motif d''un refus est gelé, et un lien de remplacement désigne toujours une autre attribution du même créneau. Un changement d''état qui ne se dit pas est un mensonge.';

revoke execute on function assignments_guard_reattribution() from public, anon, authenticated;

create trigger assignments_guard_reattribution
  before insert or update on assignments
  for each row execute function assignments_guard_reattribution();

-- ===========================================================================
-- 2. reassign_shift — la réattribution, en une transaction
-- ===========================================================================
-- Réservée au rôle de service : appelée par l'Edge Function `reassign-shift`,
-- jamais par un client. Même forme que `publish_schedule` (0019) et
-- `create_invitation` (0009) — l'acteur est passé en paramètre et vérifié ici,
-- les refus métier sortent en `{"ok": false, "code": …}`, et rien ne lève pour
-- un refus attendu.
--
-- **Deux verrous, dans l'ordre d'une réponse de membre : l'attribution, puis le
-- planning.** L'ordre n'est pas un détail de style. Un pompier qui accepte
-- verrouille sa ligne d'`assignments`, puis — par `schedule_auto_validate` —
-- celle de `schedules`. Une réattribution qui prendrait les deux dans l'autre
-- sens produirait un interblocage dès qu'un pompier accepte à l'instant où un
-- adjoint remplace sa proposition : PostgreSQL en tuerait une au hasard, et le
-- chef lirait une panne là où il n'y a qu'une simultanéité. Les refus métier
-- sont donc établis sur une lecture **sans verrou**, et les deux verrous sont
-- pris ensuite, dans le même ordre que partout ailleurs.
--
-- Ce que le verrou du planning sérialise : deux adjoints qui repourvoient le
-- même créneau en même temps. Sans lui, chacun lit son instantané, crée une
-- attribution, et deux téléphones sonnent pour une place. La contrainte
-- `assignments_active_uniq` n'arrêterait que deux tentatives sur **la même**
-- personne ; elle ne dit rien de deux personnes différentes.
--
-- **Et le verrou ne suffit pas : il faut compter.** Sérialiser deux
-- transactions ne sert à rien si la seconde ne regarde pas ce que la première a
-- écrit. Le compte des attributions actives contre l'effectif requis est fait
-- après le verrou, et c'est lui — pas le verrou — qui tient la promesse
-- « aucune notification en trop ».
--
-- **`p_previous` est facultatif, et les trois cas sont réels** :
--   - l'identifiant d'un refus, d'une annulation ou d'une attribution vivante à
--     remplacer — le geste du ticket ;
--   - `null` sur un créneau qui porte un trou non encore comblé : la fonction
--     rattache la nouvelle attribution au **plus ancien** d'entre eux. C'est ce
--     que le chef fait dans sa tête, et le laisser vide obligerait l'historique
--     à se reconstruire par la chronologie ;
--   - `null` sur un créneau simplement vide : on pourvoit, sans rien remplacer.
--
-- **Ce que la fonction écrit elle-même, et pourquoi.** `created_by` et
-- `was_available` sont posés par `assignments_trace_disponibilite` (0018) pour
-- les écritures **clientes** seulement : sous le rôle de service, le
-- déclencheur rend la ligne telle quelle. La trace se pose donc ici, à la main,
-- ou elle ne se pose pas — et une attribution forcée disparaîtrait du journal
-- de la caserne.
create function reassign_shift(
  p_shift    uuid,
  p_user     uuid,
  p_actor    uuid,
  p_previous uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  creneau        shifts;
  planning       schedules;
  periode        periods;
  cle_periode    text;
  ancienne       assignments;
  nouvelle       assignments;
  dispo          boolean;
  actives        integer;
  ancien_statut  assignment_status;
  prevenu_ancien boolean := false;
begin
  -- ------------------------------------------------------------------
  -- Les refus métier, sur une lecture **sans verrou**.
  -- ------------------------------------------------------------------
  -- Un appelant sans droit ne doit pas faire attendre une transaction qui, elle,
  -- travaille — et surtout, rien ne doit être verrouillé avant que l'ordre des
  -- verrous ne soit tenu (voir l'en-tête).
  select * into creneau from shifts where id = p_shift;
  if creneau.id is null then
    return jsonb_build_object('ok', false, 'code', 'shift_not_found');
  end if;

  select * into planning from schedules where id = creneau.schedule_id;
  if planning.id is null then
    return jsonb_build_object('ok', false, 'code', 'shift_not_found');
  end if;

  -- L'acteur est vérifié ici, pas cru sur parole : `is_admin` lit `auth.uid()`
  -- et cette fonction tourne sous le rôle de service, où il est nul.
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

  -- Un brouillon se construit par insertion et suppression (ticket 017) : rien
  -- n'est parti, il n'y a ni ancien à prévenir ni nouveau à notifier. Un
  -- planning archivé, lui, ne se modifie plus du tout.
  if planning.status not in ('published', 'validated') then
    return jsonb_build_object('ok', false, 'code', 'schedule_not_published',
                              'status', planning.status);
  end if;

  if not exists (
    select 1 from memberships m
    where m.station_id = planning.station_id
      and m.user_id    = p_user
      and m.status     = 'active'
  ) then
    return jsonb_build_object('ok', false, 'code', 'member_not_active');
  end if;

  -- ------------------------------------------------------------------
  -- L'ancienne attribution : désignée, devinée, ou absente. **Premier verrou.**
  -- ------------------------------------------------------------------
  if p_previous is not null then
    select * into ancienne from assignments a
     where a.id = p_previous and a.shift_id = p_shift
       for update;

    if ancienne.id is null then
      return jsonb_build_object('ok', false, 'code', 'assignment_not_found');
    end if;

    -- Quatre statuts se remplacent : les deux vivants (`proposed`,
    -- `accepted`), et les deux qui laissent un trou (`declined`, `cancelled`).
    -- Une annulation se repourvoit exactement comme un refus : c'est la même
    -- histoire — une garde qui manque, quelqu'un qui la reprend —, et la
    -- refuser ici obligerait l'écran à distinguer deux gestes identiques.
    --
    -- `replaced` est le seul exclu, et la condition sur `replaced_by` dit
    -- pourquoi : ce qui a déjà trouvé son remplaçant ne s'en cherche pas un
    -- second, sinon le fil de l'histoire pointerait deux fois ailleurs.
    if ancienne.status not in ('proposed', 'accepted', 'declined', 'cancelled')
       or ancienne.replaced_by is not null then
      return jsonb_build_object('ok', false, 'code', 'assignment_not_replaceable',
                                'status', ancienne.status);
    end if;
  else
    -- Le plus ancien trou non encore comblé de ce créneau — un refus ou une
    -- annulation. `order by` sur la réponse puis sur la création : deux refus
    -- dans la même seconde restent départagés. **L'écran applique exactement le
    -- même ordre** (`CreneauSuivi.aRemplacer`), pour que le nom annoncé dans le
    -- bandeau soit celui que la base reliera.
    --
    -- Une transaction concurrente qui aurait comblé ce trou pendant l'attente du
    -- verrou fait sortir la ligne de la qualification : `ancienne` est alors
    -- nulle, et c'est le compte des places ci-dessous qui refuse.
    select * into ancienne from assignments a
     where a.shift_id    = p_shift
       and a.status in ('declined', 'cancelled')
       and a.replaced_by is null
     order by a.responded_at nulls last, a.created_at
     limit 1
       for update;
  end if;

  ancien_statut := ancienne.status;

  -- ------------------------------------------------------------------
  -- **Second verrou** : le planning. Ordre tenu, on peut compter.
  -- ------------------------------------------------------------------
  select * into planning from schedules where id = creneau.schedule_id for update;

  -- Relus sous verrou : l'adjoint a pu publier, valider, ou changer l'effectif
  -- requis pendant qu'on attendait.
  select * into creneau from shifts where id = p_shift;

  if planning.status not in ('published', 'validated') then
    return jsonb_build_object('ok', false, 'code', 'schedule_not_published',
                              'status', planning.status);
  end if;

  -- Déjà en place sur ce créneau : ce n'est pas une panne, c'est l'autre
  -- administrateur — ou le même, deux fois. La contrainte d'unicité le dirait
  -- en `23505` ; un code métier se traduit mieux à l'écran.
  if exists (
    select 1 from assignments a
    where a.shift_id = p_shift
      and a.user_id  = p_user
      and a.status in ('proposed', 'accepted')
  ) then
    return jsonb_build_object('ok', false, 'code', 'already_assigned');
  end if;

  -- ------------------------------------------------------------------
  -- **Le compte des places.** C'est lui qui tient « aucune notification en trop ».
  -- ------------------------------------------------------------------
  -- Une réattribution remplace ; elle n'ajoute pas. Le créneau gagne une
  -- attribution active et en perd une — sauf quand l'ancienne était déjà sortie
  -- du jeu (un refus, une annulation), auquel cas elle ne libérait rien de plus
  -- qu'elle n'avait déjà libéré.
  --
  -- Sans ce test, deux appels identiques sur un créneau d'une place créaient
  -- deux attributions actives et faisaient sonner deux téléphones ; et remplacer
  -- une garde **acquise** sans désigner l'ancienne ajoutait une personne au lieu
  -- d'en remplacer une, la recherche implicite ne regardant que les trous.
  --
  -- Renforcer un créneau publié reste possible : cela s'appelle augmenter son
  -- effectif requis, et le panneau le propose juste au-dessus de la liste des
  -- candidats. Le dire ainsi vaut mieux que de laisser une réattribution faire
  -- en douce ce qu'un réglage dit en clair.
  select count(*) into actives
    from assignments a
   where a.shift_id = p_shift
     and a.status in ('proposed', 'accepted');

  if actives + 1
     - (case when ancien_statut in ('proposed', 'accepted') then 1 else 0 end)
     > creneau.required_count then
    return jsonb_build_object(
      'ok', false, 'code', 'shift_already_filled',
      'filled', actives, 'required', creneau.required_count);
  end if;

  select * into periode from periods where id = planning.period_id;
  cle_periode := to_char(make_date(periode.year, periode.month, 1), 'YYYY-MM');

  -- ------------------------------------------------------------------
  -- 1. La nouvelle attribution : proposée, et **déjà horodatée**.
  -- ------------------------------------------------------------------
  -- `proposed_at` est le signal « c'est parti » (docs/WORKFLOWS.md § 3) : les
  -- crons de relance ignorent `null`, et `v_schedule_progress` n'appellerait
  -- jamais cette proposition « en retard ». Une réattribution sans horodatage
  -- serait une garde que personne ne relancerait jamais.
  dispo := exists (
    select 1 from availabilities av
    where av.station_id = planning.station_id
      and av.user_id    = p_user
      and av.date       = creneau.date
      and av.slot       = creneau.slot
      and av.status     = 'available'
  );

  insert into assignments (
    station_id, shift_id, user_id, status, was_available, proposed_at, created_by)
  values (
    planning.station_id, p_shift, p_user, 'proposed', dispo, now(), p_actor)
  returning * into nouvelle;

  -- ------------------------------------------------------------------
  -- 2. L'ancienne : le statut selon ce qu'elle était, le lien dans tous les cas.
  -- ------------------------------------------------------------------
  -- docs/WORKFLOWS.md § 3 et § 5 :
  --   accepted  -> replaced   (avec notification)
  --   proposed  -> replaced   (sans notification : rien n'était acquis)
  --   declined  -> declined   (le refus **reste** un refus ; il est l'histoire)
  --   cancelled -> cancelled  (l'annulation aussi : elle est déjà dite)
  -- et `replaced_by` pointe la nouvelle dans les quatre cas : c'est le fil qui
  -- dit « ce trou-là a été comblé par cette attribution-là ». Un statut
  -- terminal ne se réécrit pas — il a déjà été notifié sous ce nom.
  if ancienne.id is not null then
    update assignments a
       set status = case
                      when a.status in ('declined', 'cancelled') then a.status
                      else 'replaced'
                    end,
           replaced_by = nouvelle.id
     where a.id = ancienne.id;
  end if;

  -- ------------------------------------------------------------------
  -- 3. Les notifications. **Une, sauf quand une garde acquise disparaît.**
  -- ------------------------------------------------------------------
  -- Le critère du ticket : un refus suivi d'une réattribution produit
  -- exactement **une** notification, au nouveau membre. Le refus a déjà produit
  -- la sienne — aux administrateurs — au moment où il a été prononcé.
  perform notify(
    'assignment_proposed',
    p_station    => planning.station_id,
    p_payload    => jsonb_build_object('period', cle_periode),
    p_recipients => jsonb_build_array(jsonb_build_object(
      'user_id', p_user,
      'payload', jsonb_build_object(
        'shifts', jsonb_build_array(jsonb_build_object(
          'date',          creneau.date,
          'slot',          creneau.slot,
          'assignment_id', nouvelle.id))))));

  -- `assignment_cancelled` et non `assignment_changed` : du point de vue du
  -- pompier remplacé, rien n'a « changé », il n'a plus cette garde. Le texte et
  -- le lien profond d'`assignment_cancelled` sont les siens — le planning du
  -- mois, là où il vérifiera —, là où `assignment_changed` mène à l'écran des
  -- propositions, où il n'a plus rien à faire.
  if ancien_statut = 'accepted' then
    perform notify(
      'assignment_cancelled',
      p_user_ids => array[ancienne.user_id],
      p_station  => planning.station_id,
      p_payload  => jsonb_build_object(
        'period', cle_periode,
        -- **Un code, pas une phrase.** Le français des notifications vit dans
        -- `_shared/notification_content.ts`, où il est testé et relu d'un seul
        -- endroit ; une phrase écrite ici aurait échappé au système de chaînes
        -- et vieilli seule dans une migration.
        'reason_code', 'reassigned',
        'shifts', jsonb_build_array(jsonb_build_object(
          'date', creneau.date,
          'slot', creneau.slot))));
    prevenu_ancien := true;
  end if;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    planning.station_id, p_actor,
    'assignment.reassigned', 'assignment', nouvelle.id,
    jsonb_build_object(
      'period',          cle_periode,
      'shift_id',        p_shift,
      'date',            creneau.date,
      'slot',            creneau.slot,
      'to_user',         p_user,
      'was_available',   dispo,
      'previous_id',     ancienne.id,
      'previous_user',   ancienne.user_id,
      'previous_status', ancien_statut));

  -- ------------------------------------------------------------------
  -- 4. Le planning se réévalue.
  -- ------------------------------------------------------------------
  -- Remplacer une acceptation retire une acceptation : un planning validé
  -- redevient publié (docs/WORKFLOWS.md § 2), sans notifier personne — la
  -- conséquence est déjà partie, à la personne concernée. Le déclencheur du § 4
  -- couvre déjà ce cas ; l'appel explicite couvre les autres et ne coûte qu'un
  -- test de complétude, parce que `schedule_reevaluer` est idempotente.
  perform schedule_reevaluer(planning.id);
  select * into planning from schedules where id = planning.id;

  return jsonb_build_object(
    'ok',              true,
    'assignment_id',   nouvelle.id,
    'shift_id',        p_shift,
    'user_id',         p_user,
    'was_available',   dispo,
    'proposed_at',     nouvelle.proposed_at,
    'previous_id',     ancienne.id,
    'previous_user',   ancienne.user_id,
    'previous_status', ancien_statut,
    'previous_notified', prevenu_ancien,
    'schedule_id',     planning.id,
    'station_id',      planning.station_id,
    'schedule_status', planning.status,
    'period',          cle_periode);
end $$;

comment on function reassign_shift(uuid, uuid, uuid, uuid) is
  'Réattribue un créneau d''un planning publié : nouvelle attribution proposée et horodatée, ancienne marquée replaced (ou laissée declined), lien replaced_by posé, notification au nouveau membre et à l''ancien si sa garde était acquise, puis réévaluation du planning. Réservée au rôle de service.';

revoke execute on function reassign_shift(uuid, uuid, uuid, uuid) from public, anon, authenticated;

-- ===========================================================================
-- 3. cancel_assignment — retirer une astreinte, en le disant
-- ===========================================================================
-- Ouverte à `authenticated`, comme `remind_schedule` (0019) : l'administrateur
-- l'appelle en RPC et la fonction vérifie `is_admin` et `station_writable`
-- elle-même. Pas d'Edge Function — il n'y a ni identité à établir autrement que
-- par `auth.uid()`, ni regroupement à faire, et `docs/SCHEMA.md § 7` n'en nomme
-- aucune pour ce geste.
--
-- `accepted -> cancelled` notifie ; `proposed -> cancelled` ne notifie pas
-- (docs/WORKFLOWS.md § 3 : « admin retire avant réponse », sans notification).
-- Une proposition retirée avant réponse disparaît de l'écran « Propositions »
-- du membre : il n'a rien à faire, et un push pour une garde qu'il n'avait pas
-- acquise serait du bruit.
--
-- Le motif voyage dans la notification. « Annulée » sans raison, c'est
-- exactement le coup de téléphone que cette application doit éviter.
--
-- **Il s'écrit aussi dans `decline_reason`, et c'est un élargissement assumé**
-- de la colonne (docs/SCHEMA.md § 2.10, mis à jour) : elle porte « pourquoi
-- cette garde n'est pas tenue », et `status` dit déjà qui l'a écrit — le membre
-- sur un `declined`, l'administrateur sur un `cancelled`. Sans cela, le suivi
-- afficherait « annulé » sans jamais pouvoir dire pourquoi, et le motif ne
-- vivrait que dans un journal d'audit que l'écran ne lit pas.
create function cancel_assignment(p_assignment uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  attribution  assignments;
  creneau      shifts;
  planning     schedules;
  periode      periods;
  cle_periode  text;
  motif        text;
  prevenu      boolean := false;
begin
  -- **L'attribution d'abord, le planning ensuite** : le même ordre qu'une
  -- réponse de membre et que `reassign_shift`. Pris dans l'autre sens, un
  -- pompier qui accepte à l'instant où un adjoint annule sa garde produirait un
  -- interblocage, rendu au chef comme une panne.
  select * into attribution from assignments where id = p_assignment for update;
  if attribution.id is null then
    return jsonb_build_object('ok', false, 'code', 'assignment_not_found');
  end if;

  if not is_admin(attribution.station_id) then
    return jsonb_build_object('ok', false, 'code', 'not_admin');
  end if;

  if not station_writable(attribution.station_id) then
    return jsonb_build_object('ok', false, 'code', 'station_suspended');
  end if;

  select * into creneau  from shifts    where id = attribution.shift_id;
  select * into planning from schedules where id = creneau.schedule_id for update;

  if planning.status not in ('published', 'validated') then
    return jsonb_build_object('ok', false, 'code', 'schedule_not_published',
                              'status', planning.status);
  end if;

  if attribution.status not in ('proposed', 'accepted') then
    return jsonb_build_object('ok', false, 'code', 'assignment_not_active',
                              'status', attribution.status);
  end if;

  select * into periode from periods where id = planning.period_id;
  cle_periode := to_char(make_date(periode.year, periode.month, 1), 'YYYY-MM');
  motif := nullif(btrim(coalesce(p_reason, '')), '');

  update assignments a
     set status = 'cancelled', decline_reason = coalesce(motif, a.decline_reason)
   where a.id = p_assignment;

  if attribution.status = 'accepted' then
    perform notify(
      'assignment_cancelled',
      p_user_ids => array[attribution.user_id],
      p_station  => attribution.station_id,
      p_payload  => jsonb_strip_nulls(jsonb_build_object(
        'period', cle_periode,
        'reason', motif,
        'shifts', jsonb_build_array(jsonb_build_object(
          'date', creneau.date,
          'slot', creneau.slot)))));
    prevenu := true;
  end if;

  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    attribution.station_id, auth.uid(),
    'assignment.cancelled', 'assignment', p_assignment,
    jsonb_strip_nulls(jsonb_build_object(
      'period',          cle_periode,
      'shift_id',        attribution.shift_id,
      'date',            creneau.date,
      'slot',            creneau.slot,
      'user_id',         attribution.user_id,
      'previous_status', attribution.status,
      'reason',          motif)));

  perform schedule_reevaluer(planning.id);
  select * into planning from schedules where id = planning.id;

  return jsonb_build_object(
    'ok',              true,
    'assignment_id',   p_assignment,
    'user_id',         attribution.user_id,
    'previous_status', attribution.status,
    'notified',        prevenu,
    'schedule_id',     planning.id,
    'schedule_status', planning.status,
    'period',          cle_periode);
end $$;

comment on function cancel_assignment(uuid, text) is
  'Annule une attribution d''un planning publié : statut cancelled, motif conservé, notification au membre si sa garde était acquise, audit, puis réévaluation du planning. Ouverte à authenticated : la fonction vérifie elle-même is_admin et station_writable.';

revoke execute on function cancel_assignment(uuid, text) from public, anon;
grant  execute on function cancel_assignment(uuid, text) to authenticated;

-- ===========================================================================
-- 4. La complétude se juge aussi quand une acceptation disparaît
-- ===========================================================================
-- Le déclencheur du 019 ne se réveillait qu'à une acceptation : « une réponse
-- de plus, le planning est-il complet ? ». C'est la moitié de la question.
--
-- L'autre moitié arrive avec ce ticket : remplacer ou annuler une attribution
-- **acceptée** retire une acceptation. Un planning validé cesse d'être complet
-- et doit repasser en `published` (docs/WORKFLOWS.md § 2), sans quoi la caserne
-- lirait « Validé » sur un mois qui a un trou — et `schedule_validated` serait
-- parti pour rien.
--
-- Une seule clause `when`, les deux sens. La fonction appelée ne change pas :
-- `schedule_reevaluer` traite déjà `validated -> published` depuis le 019, elle
-- n'avait simplement aucun appelant pour ce cas.
--
-- `new.status is distinct from old.status` en tête : une réécriture à
-- l'identique (`update … set status = status`) n'est pas un changement d'état
-- et n'a aucune raison de reverrouiller la ligne du planning.
drop trigger schedule_auto_validate on assignments;

create trigger schedule_auto_validate
  after update on assignments
  for each row
  when (
    new.status is distinct from old.status
    and (new.status = 'accepted' or old.status = 'accepted')
  )
  execute function schedule_auto_validate();

comment on function schedule_auto_validate() is
  'Réévalue la complétude du planning quand une attribution entre en accepted ou en sort (docs/WORKFLOWS.md § 2 et § 4) : une acceptation de plus peut valider le planning, une acceptation de moins doit le ramener en published.';
