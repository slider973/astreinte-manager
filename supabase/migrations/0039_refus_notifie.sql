-- 0039 — Un refus met en file la notification du chef de centre, et une
-- réattribution dit ce qu'elle a mis en file pour l'entrant. Ticket 055.
-- Référence : docs/SCHEMA.md § 5 (« Ce que garantit la réponse d'un membre »)
-- et § 3 (`reassign_shift`) ; docs/WORKFLOWS.md § 5 et § 8.
--
-- Le défaut trouvé
-- ----------------
-- `docs/WORKFLOWS.md § 5` dessine « DB ->> N : assignment_declined à l'admin »
-- depuis le ticket 020, `send-notification` sait composer ce type depuis le 025,
-- et l'écran des propositions affichait « Ton chef de centre est prévenu ». Mais
-- **aucune migration n'appelait `notify('assignment_declined', …)`** : le type
-- existait dans l'énumération, sa phrase dans `notification_content.ts`, et rien
-- dans la base ne le produisait. Un refus ne prévenait personne, file en panne
-- ou pas. Le ticket supposait une notification non prouvée ; elle n'existait
-- pas du tout.
--
-- 1. `assignments_notifier_refus` — le refus et sa demande, une seule transaction
-- --------------------------------------------------------------------------------
-- Un déclencheur `after update` sur la transition `proposed -> declined`. Il
-- appelle `notify(...)` (0014), qui **insère la demande dans
-- `notification_outbox` dans la transaction du `PATCH`** du membre : le refus
-- existe avec sa demande de notification, ou n'existe pas. C'est ce qui rend
-- vraie, dès que le `PATCH … status=eq.proposed&select=id` rend une ligne, la
-- phrase « Ton chef de centre sera prévenu » — au futur : une ligne en file
-- n'est pas une notification livrée (§ 5 de docs/SCHEMA.md).
--
-- **La forme de la réponse ne change pas.** La PWA et l'app iOS (`foco/`) font
-- exactement le même `PATCH` et lisent la même chose : une ligne touchée ou
-- aucune. Faire rendre un accusé par la requête aurait forcé un chantier iOS
-- pour une information que la transaction garantit déjà.
--
-- Destinataires : les administrateurs **actifs** de la caserne, **sauf celui dont
-- c'est l'attribution et sauf celui qui écrit** (`auth.uid()`). Un chef de centre
-- qui refuse sa propre astreinte n'a pas à l'apprendre par push ; un
-- administrateur qui enregistre un refus **à la place** d'un membre
-- (`assignments_update_admin`, un pompier qui a téléphoné) non plus : c'est son
-- propre geste. S'il n'en reste aucun, rien n'est mis en file (`notify` refuse
-- une liste vide) : l'écran ne promet donc rien quand le rôle d'administrateur
-- n'est pas écarté par la base (`AppStrings.propositionsRefuseeNeutre`).
--
-- Seul un refus **d'une proposition partie** (`proposed_at` non nul) prévient :
-- un brouillon n'a rien demandé à personne (docs/WORKFLOWS.md § 3), et la RLS
-- ne le montre de toute façon pas au membre.
--
-- `dedupe_key` = l'identifiant de l'attribution : un statut terminal ne se
-- quitte pas (0020), donc un refus ne se prononce qu'une fois ; la clé le dit
-- aussi à la file, pour le cas où une écriture serveur rejouerait la ligne.
--
-- **security definer**, par nécessité : `notify` est retirée à `authenticated`
-- (0014), et c'est le membre qui écrit. Le déclencheur ne lit rien qui ne soit
-- déjà sur la ligne ou dans sa caserne, et n'écrit que la file.
--
-- 2. `reassign_shift` rend `notified` pour l'entrant
-- ----------------------------------------------------
-- La fonction rendait `previous_notified` pour le sortant et rien pour
-- l'entrant, si bien que l'écran de suivi affirmait « <membre> est prévenu »
-- sans preuve. Elle rend désormais `notified` : vrai quand `notify(...)` a rendu
-- la ligne de file de l'entrant. **Même sens que `previous_notified` : mis en
-- file, pas livré** — les deux demandes partent par la même file. Le corps est
-- celui de 0020, à trois lignes près (`file_entrant`, son affectation, la clé
-- `notified`).

-- ===========================================================================
-- 1. Le refus d'un membre met en file la notification des administrateurs
-- ===========================================================================
create function assignments_notifier_refus() returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  creneau      shifts;
  cle_periode  text;
  admins       uuid[];
  nom          text;
begin
  select array_agg(m.user_id order by m.user_id)
    into admins
    from memberships m
   where m.station_id = new.station_id
     and m.role       = 'admin'
     and m.status     = 'active'
     and m.user_id   <> new.user_id
     -- L'acteur : nul pour une écriture serveur, qui n'écarte alors personne.
     and m.user_id is distinct from auth.uid();

  -- Personne à prévenir : `notify` refuserait une liste vide, et faire échouer
  -- le refus pour ça reviendrait à interdire de refuser.
  if admins is null or cardinality(admins) = 0 then
    return new;
  end if;

  select * into creneau from shifts where id = new.shift_id;

  select to_char(make_date(p.year, p.month, 1), 'YYYY-MM')
    into cle_periode
    from schedules sc
    join periods p on p.id = sc.period_id
   where sc.id = creneau.schedule_id;

  -- Le nom de la caserne d'abord, celui du profil en repli : la même règle que
  -- le rapport des retardataires (0021).
  select coalesce(
           nullif(btrim(m.display_name), ''),
           nullif(btrim(coalesce(pr.first_name, '') || ' ' || coalesce(pr.last_name, '')), ''),
           pr.email,
           'Un membre')
    into nom
    from profiles pr
    left join memberships m
      on m.station_id = new.station_id and m.user_id = pr.id
   where pr.id = new.user_id;

  perform notify(
    'assignment_declined',
    p_user_ids   => admins,
    p_station    => new.station_id,
    p_payload    => jsonb_build_object(
      'period',         cle_periode,
      'member_name',    coalesce(nom, 'Un membre'),
      'decline_reason', nullif(btrim(coalesce(new.decline_reason, '')), ''),
      'shifts', jsonb_build_array(jsonb_build_object(
        'date',          creneau.date,
        'slot',          creneau.slot,
        'assignment_id', new.id))),
    p_dedupe_key => 'declined:' || new.id::text);

  return new;
end $$;

comment on function assignments_notifier_refus() is
  'Met en file assignment_declined aux administrateurs actifs de la caserne (sauf le titulaire de l''attribution et l''acteur auth.uid()) quand une proposition partie passe à declined, dans la transaction de la réponse. Ticket 055.';

revoke execute on function assignments_notifier_refus() from public, anon, authenticated;

create trigger assignments_notifier_refus
  after update of status on assignments
  for each row
  when (old.status = 'proposed'
        and new.status = 'declined'
        and new.proposed_at is not null)
  execute function assignments_notifier_refus();

-- ===========================================================================
-- 2. reassign_shift — la même, qui rend `notified` pour l'entrant
-- ===========================================================================
create or replace function reassign_shift(
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
  -- 0039 : la ligne de file de l'entrant, rendue comme `notified`.
  file_entrant   uuid;
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
  file_entrant := notify(
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
    -- 0039 : la demande de l'entrant est **en file** — pas livrée.
    'notified',        file_entrant is not null,
    'schedule_id',     planning.id,
    'station_id',      planning.station_id,
    'schedule_status', planning.status,
    'period',          cle_periode);
end $$;

comment on function reassign_shift(uuid, uuid, uuid, uuid) is
  'Réattribue un créneau d''un planning publié : nouvelle attribution proposée et horodatée, ancienne marquée replaced (ou laissée declined), lien replaced_by posé, notification au nouveau membre et à l''ancien si sa garde était acquise, puis réévaluation du planning. Rend notified (entrant) et previous_notified (sortant) : des demandes mises en file, pas des livraisons. Réservée au rôle de service.';

revoke execute on function reassign_shift(uuid, uuid, uuid, uuid) from public, anon, authenticated;
