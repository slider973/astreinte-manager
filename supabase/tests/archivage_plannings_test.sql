-- Tests de l'archivage des plannings (migration 0031, ticket 044).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
-- 1. `cron_archive_schedules` appelée avec un **instant de référence** : les
--    plannings `published` et `validated` des mois passés sont archivés, le
--    mois en cours et le mois à venir ne le sont pas, et un **brouillon** d'un
--    mois écoulé reste un brouillon.
-- 2. Le fuseau, et c'est le cœur du calcul : à 02:30 UTC le 1er du mois, une
--    caserne de Polynésie est encore au dernier jour du mois précédent. Son
--    planning n'est **pas** archivé — l'archiver serait l'archiver un jour à
--    l'avance sous les yeux de pompiers encore d'astreinte — et il l'est au
--    passage suivant, vingt-quatre heures plus tard. C'est ce qui oblige la
--    tâche à être quotidienne.
-- 3. Idempotence : rejouée sur le même instant, la tâche n'archive plus rien et
--    ne touche aucune ligne.
-- 4. **Ce qu'un membre lit d'un planning archivé** — la décision du ticket :
--    tous les créneaux, toutes ses propres attributions quel que soit leur
--    statut, et les attributions **acceptées** des autres. Pas leurs
--    propositions sans réponse, pas leurs refus, pas leurs motifs.
-- 5. Cloisonnement : la caserne voisine ne lit rien de tout cela.
-- 6. Un planning archivé ne se modifie plus. Les six chemins d'écriture, y
--    compris les deux que les gardes existantes laissaient ouverts avant ce
--    ticket : l'insertion et la mise à jour d'un créneau et d'une attribution.
-- 7. Le flux calendrier garde ses quatre-vingt-dix jours d'historique par-dessus
--    l'archivage.
-- 8. La tâche est dans `cron.job`, qualifiée, sans argument ; la fonction n'est
--    appelable ni par `anon` ni par `authenticated`.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : deux casernes montées pour ce fichier, « CIS Archive »
-- (Europe/Paris) et « CIS Archive Outre-mer » (Pacific/Tahiti, UTC-10 toute
-- l'année), sur l'hiver 2028-2029. L'instant de référence de tout le fichier est
-- `2029-03-01 02:30:00+00` — l'heure et le jour où l'ordonnanceur tirerait s'il
-- était mensuel. Aucun test ne dépend du jour où il tourne.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_arc;

create function tests_arc.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

create function tests_arc.egal(p_obtenu anyelement, p_attendu anyelement, p_label text) returns void
language plpgsql as $$
begin
  if p_obtenu is distinct from p_attendu then
    raise exception 'ECHEC : % — obtenu [%], attendu [%]', p_label, p_obtenu, p_attendu;
  end if;
  raise notice '  ok   % = %', p_label, coalesce(p_obtenu::text, 'NULL');
end $$;

-- `refuse` : l'instruction doit lever l'erreur nommée, et pas une autre.
create function tests_arc.refuse(p_sql text, p_erreur text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — aucune erreur levée, % attendue', p_label, p_erreur;
exception
  when insufficient_privilege then
    if p_erreur <> '42501' then
      raise exception 'ECHEC : % — refus de privilège au lieu de [%]', p_label, p_erreur;
    end if;
    raise notice '  ok   % (refusé : %)', p_label, sqlerrm;
  when others then
    if sqlerrm <> p_erreur and sqlstate <> p_erreur then
      raise exception 'ECHEC : % — erreur [% / %] au lieu de [%]',
        p_label, sqlstate, sqlerrm, p_erreur;
    end if;
    raise notice '  ok   % (%)', p_label, sqlerrm;
end $$;

-- `sans_effet` : l'instruction passe mais ne touche aucune ligne. C'est la forme
-- que prend un refus porté par le `using` d'une politique — zéro ligne, pas une
-- exception (convention de la migration 0019).
create function tests_arc.sans_effet(p_sql text, p_label text) returns void
language plpgsql as $$
declare
  n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n > 0 then
    raise exception 'ECHEC : % — % ligne(s) touchée(s) alors que ça devait être refusé', p_label, n;
  end if;
  raise notice '  ok   % (0 ligne)', p_label;
exception
  when insufficient_privilege then
    raise notice '  ok   % (refusé : %)', p_label, sqlerrm;
end $$;

grant usage on schema tests_arc to authenticated, anon;
grant execute on all functions in schema tests_arc to authenticated, anon;

-- L'instant de référence de tout le fichier : le 1er mars 2029 à 02:30 UTC.
--   Europe/Paris  → 2029-03-01 03:30, mois courant = mars 2029.
--   Pacific/Tahiti → 2029-02-28 16:30, mois courant = février 2029.
create function tests_arc.t0() returns timestamptz
language sql immutable as $$ select '2029-03-01 02:30:00+00'::timestamptz $$;

grant execute on function tests_arc.t0() to authenticated, anon;

\echo ''
\echo '=== Archivage des plannings (0031) ==='

-- ===========================================================================
-- Fixtures
-- ===========================================================================
-- « CIS Archive » (Europe/Paris) : 1 admin, 3 membres actifs, cinq mois de
-- décembre 2028 à avril 2029. « CIS Archive Outre-mer » (Pacific/Tahiti) : 1
-- admin, le seul mois de février 2029 — elle n'existe que pour le fuseau.

insert into stations (id, name, slug, timezone, settings) values
  ('99999999-0000-4000-8000-000000000001', 'CIS Archive', 'cis-archive', 'Europe/Paris',
   '{"day_start": "07:00", "day_end": "19:00",
     "required_day": 1, "required_night": 1,
     "required_overrides": {},
     "availability_deadline_day": 15,
     "response_reminder_hours": 24, "response_email_hours": 48,
     "late_report_hours": 72}'::jsonb),
  ('9a9a9a9a-0000-4000-8000-000000000001', 'CIS Archive Outre-mer', 'cis-archive-om', 'Pacific/Tahiti',
   '{"day_start": "07:00", "day_end": "19:00",
     "required_day": 1, "required_night": 1,
     "required_overrides": {},
     "availability_deadline_day": 15,
     "response_reminder_hours": 24, "response_email_hours": 48,
     "late_report_hours": 72}'::jsonb);

insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current
)
select
  '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
  u.email, now(), '{"provider": "email", "providers": ["email"]}'::jsonb,
  jsonb_build_object('first_name', u.first_name, 'last_name', u.last_name),
  now(), now(), '', '', '', '', ''
from (values
  ('99999999-0000-4000-8000-000000000100'::uuid, 'admin@archive.test',   'Noémie', 'Aubry'),
  ('99999999-0000-4000-8000-000000000101'::uuid, 'membre1@archive.test', 'Bastien', 'Blanc'),
  ('99999999-0000-4000-8000-000000000102'::uuid, 'membre2@archive.test', 'Camille', 'Caron'),
  ('99999999-0000-4000-8000-000000000103'::uuid, 'membre3@archive.test', 'Dorian',  'Dubois'),
  ('9a9a9a9a-0000-4000-8000-000000000100'::uuid, 'admin@archive-om.test', 'Ella',   'Ehueinana')
) as u(id, email, first_name, last_name);

insert into memberships (station_id, user_id, role, status, display_name) values
  ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000100', 'admin',  'active', 'Noémie A.'),
  ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000101', 'member', 'active', 'Bastien B.'),
  ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000102', 'member', 'active', 'Camille C.'),
  ('99999999-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000103', 'member', 'active', 'Dorian D.'),
  ('9a9a9a9a-0000-4000-8000-000000000001', '9a9a9a9a-0000-4000-8000-000000000100', 'admin',  'active', 'Ella E.');

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('99999999-0000-4000-8000-000000000200', '99999999-0000-4000-8000-000000000001', 2028, 12, 'locked', '2028-11-15 23:59:59+01'),
  ('99999999-0000-4000-8000-000000000201', '99999999-0000-4000-8000-000000000001', 2029,  1, 'locked', '2028-12-15 23:59:59+01'),
  ('99999999-0000-4000-8000-000000000202', '99999999-0000-4000-8000-000000000001', 2029,  2, 'locked', '2029-01-15 23:59:59+01'),
  ('99999999-0000-4000-8000-000000000203', '99999999-0000-4000-8000-000000000001', 2029,  3, 'locked', '2029-02-15 23:59:59+01'),
  ('99999999-0000-4000-8000-000000000204', '99999999-0000-4000-8000-000000000001', 2029,  4, 'open',   '2029-03-15 23:59:59+01'),
  ('9a9a9a9a-0000-4000-8000-000000000202', '9a9a9a9a-0000-4000-8000-000000000001', 2029,  2, 'locked', '2029-01-15 23:59:59-10');

-- Cinq plannings de « CIS Archive », un par mois :
--   décembre 2028 : **brouillon** oublié — il doit le rester ;
--   janvier  2029 : publié, resté incomplet (une proposition sans réponse) ;
--   février  2029 : validé, complet ;
--   mars     2029 : publié — c'est le mois en cours à l'instant de référence ;
--   avril    2029 : publié — un mois à venir, publié en avance.
insert into schedules (id, station_id, period_id, status, published_at, validated_at, created_by) values
  ('99999999-0000-4000-8000-000000000300', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000200', 'draft',     null,                        null,
   '99999999-0000-4000-8000-000000000100'),
  ('99999999-0000-4000-8000-000000000301', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000201', 'published', '2028-12-18 09:00:00+01',    null,
   '99999999-0000-4000-8000-000000000100'),
  ('99999999-0000-4000-8000-000000000302', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000202', 'validated', '2029-01-18 09:00:00+01',    '2029-01-24 18:00:00+01',
   '99999999-0000-4000-8000-000000000100'),
  ('99999999-0000-4000-8000-000000000303', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000203', 'published', '2029-02-18 09:00:00+01',    null,
   '99999999-0000-4000-8000-000000000100'),
  ('99999999-0000-4000-8000-000000000304', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000204', 'published', '2029-02-25 09:00:00+01',    null,
   '99999999-0000-4000-8000-000000000100'),
  ('9a9a9a9a-0000-4000-8000-000000000302', '9a9a9a9a-0000-4000-8000-000000000001',
   '9a9a9a9a-0000-4000-8000-000000000202', 'published', '2029-01-18 09:00:00-10',    null,
   '9a9a9a9a-0000-4000-8000-000000000100');

insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  -- Janvier : un créneau à deux places, une seule tenue.
  ('99999999-0000-4000-8000-000000000411', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000301', '2029-01-05', 'day', 2),
  -- Février : trois créneaux, tous pourvus — d'où le statut `validated`.
  ('99999999-0000-4000-8000-000000000401', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000302', '2029-02-01', 'day', 2),
  ('99999999-0000-4000-8000-000000000402', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000302', '2029-02-02', 'day', 1),
  ('99999999-0000-4000-8000-000000000403', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000302', '2029-02-03', 'day', 1),
  -- Mars : le mois en cours, pour le contraste.
  ('99999999-0000-4000-8000-000000000421', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000303', '2029-03-10', 'day', 1),
  -- Outre-mer.
  ('9a9a9a9a-0000-4000-8000-000000000401', '9a9a9a9a-0000-4000-8000-000000000001',
   '9a9a9a9a-0000-4000-8000-000000000302', '2029-02-14', 'day', 1);

-- Les attributions. Écrites sous `postgres`, donc hors de portée de
-- `assignments_guard_reattribution` — c'est la seule façon de poser un `declined`
-- d'origine sans passer par une réponse de membre, et c'est ce que fait le seed.
insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, responded_at, decline_reason, created_by) values
  -- Janvier : Bastien a tenu la garde, Dorian n'a jamais répondu. Le planning
  -- s'est donc terminé `published`, avec une proposition en suspens — le cas
  -- que l'archivage vient clore.
  ('99999999-0000-4000-8000-000000000512', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000411', '99999999-0000-4000-8000-000000000101',
   'accepted', '2028-12-18 09:00:00+01', '2028-12-19 07:30:00+01', null,
   '99999999-0000-4000-8000-000000000100'),
  ('99999999-0000-4000-8000-000000000511', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000411', '99999999-0000-4000-8000-000000000103',
   'proposed', '2028-12-18 09:00:00+01', null, null,
   '99999999-0000-4000-8000-000000000100'),
  -- Février : les deux places du 1er tenues par Bastien et Camille.
  ('99999999-0000-4000-8000-000000000501', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000401', '99999999-0000-4000-8000-000000000101',
   'accepted', '2029-01-18 09:00:00+01', '2029-01-19 08:00:00+01', null,
   '99999999-0000-4000-8000-000000000100'),
  ('99999999-0000-4000-8000-000000000502', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000401', '99999999-0000-4000-8000-000000000102',
   'accepted', '2029-01-18 09:00:00+01', '2029-01-19 09:00:00+01', null,
   '99999999-0000-4000-8000-000000000100'),
  -- Le 2 : Camille a refusé avec un motif, Dorian a pris la garde.
  ('99999999-0000-4000-8000-000000000503', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000402', '99999999-0000-4000-8000-000000000102',
   'declined', '2029-01-18 09:00:00+01', '2029-01-19 09:05:00+01', 'rendez-vous médical',
   '99999999-0000-4000-8000-000000000100'),
  ('99999999-0000-4000-8000-000000000505', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000402', '99999999-0000-4000-8000-000000000103',
   'accepted', '2029-01-20 10:00:00+01', '2029-01-20 12:00:00+01', null,
   '99999999-0000-4000-8000-000000000100'),
  -- Le 3 : Bastien a refusé avec un motif, Camille a pris la garde.
  ('99999999-0000-4000-8000-000000000504', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000403', '99999999-0000-4000-8000-000000000101',
   'declined', '2029-01-18 09:00:00+01', '2029-01-19 08:05:00+01', 'en formation',
   '99999999-0000-4000-8000-000000000100'),
  ('99999999-0000-4000-8000-000000000506', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000403', '99999999-0000-4000-8000-000000000102',
   'accepted', '2029-01-20 10:00:00+01', '2029-01-20 11:00:00+01', null,
   '99999999-0000-4000-8000-000000000100'),
  -- Mars, mois en cours : une garde à venir pour Bastien.
  ('99999999-0000-4000-8000-000000000521', '99999999-0000-4000-8000-000000000001',
   '99999999-0000-4000-8000-000000000421', '99999999-0000-4000-8000-000000000101',
   'accepted', '2029-02-18 09:00:00+01', '2029-02-18 20:00:00+01', null,
   '99999999-0000-4000-8000-000000000100');

-- ===========================================================================
-- 1. La tâche, appelée avec une date de référence
-- ===========================================================================
\echo ''
\echo '--- 1. cron_archive_schedules(instant) : les mois passés, et eux seuls'

do $$
declare
  archives integer;
begin
  perform tests_arc.egal(
    (select count(*)::integer from schedules
      where station_id = '99999999-0000-4000-8000-000000000001'
        and status = 'archived'),
    0, 'avant la tâche, aucun planning archivé');

  archives := cron_archive_schedules(tests_arc.t0());

  -- Deux, et deux seulement : janvier (publié) et février (validé) de
  -- « CIS Archive ». Ni le brouillon de décembre, ni mars, ni avril, ni la
  -- caserne d'outre-mer — voir la section 2.
  perform tests_arc.egal(archives, 2,
    'deux plannings archivés au 1er mars 2029 à 02:30 UTC');

  perform tests_arc.egal(
    (select status::text from schedules where id = '99999999-0000-4000-8000-000000000301'),
    'archived', 'janvier 2029, publié et révolu');

  perform tests_arc.egal(
    (select status::text from schedules where id = '99999999-0000-4000-8000-000000000302'),
    'archived', 'février 2029, validé et révolu');

  -- Le mois **en cours** n'est pas du passé, même le 1er à 02:30.
  perform tests_arc.egal(
    (select status::text from schedules where id = '99999999-0000-4000-8000-000000000303'),
    'published', 'mars 2029, le mois en cours, reste publié');

  perform tests_arc.egal(
    (select status::text from schedules where id = '99999999-0000-4000-8000-000000000304'),
    'published', 'avril 2029, publié en avance, reste publié');

  -- `draft --> archived` n'est pas dans docs/WORKFLOWS.md § 2, et un brouillon
  -- oublié est la seule chose du produit qui se supprime encore : l'archiver le
  -- rendrait indestructible sans avoir jamais été lu.
  perform tests_arc.egal(
    (select status::text from schedules where id = '99999999-0000-4000-8000-000000000300'),
    'draft', 'décembre 2028, brouillon oublié, reste un brouillon');

  -- L'archivage est un changement de statut, pas une purge.
  perform tests_arc.egal(
    (select count(*)::integer from shifts
      where schedule_id = '99999999-0000-4000-8000-000000000302'),
    3, 'les créneaux du mois archivé sont toujours là');
  perform tests_arc.egal(
    (select count(*)::integer from assignments a
       join shifts sh on sh.id = a.shift_id
      where sh.schedule_id = '99999999-0000-4000-8000-000000000302'),
    6, 'les attributions du mois archivé sont toujours là');

  -- Les horodatages du planning ne sont pas réécrits par le passage.
  perform tests_arc.check(
    (select published_at = '2029-01-18 09:00:00+01'
        and validated_at = '2029-01-24 18:00:00+01'
       from schedules where id = '99999999-0000-4000-8000-000000000302'),
    'l''archivage ne réécrit ni published_at ni validated_at');
end $$;

-- ===========================================================================
-- 2. Le fuseau de chaque caserne, et pas celui du serveur
-- ===========================================================================
-- C'est le calcul qui décide, et il décide deux fois : ne pas archiver trop tôt,
-- et ne pas attendre un mois pour rattraper.
\echo ''
\echo '--- 2. Le fuseau : rien un jour trop tôt, rien un mois trop tard'

do $$
declare
  archives integer;
begin
  -- À l'instant de référence, Tahiti est le 28 février à 16:30 : février n'est
  -- pas passé, on y est. Le planning de février **ne doit pas** bouger.
  perform tests_arc.egal(
    (select (tests_arc.t0() at time zone 'Pacific/Tahiti')::date),
    '2029-02-28'::date,
    'à 02:30 UTC le 1er mars, Tahiti est encore le 28 février');

  perform tests_arc.egal(
    (select status::text from schedules where id = '9a9a9a9a-0000-4000-8000-000000000302'),
    'published',
    'outre-mer : février n''est pas archivé avec un jour d''avance');

  -- Vingt-quatre heures plus tard, Tahiti est le 1er mars à 16:30 : le mois a
  -- tourné là-bas aussi. C'est ce passage-là qui archive — et c'est pour lui que
  -- la tâche est quotidienne et non mensuelle. Une tâche qui ne tirerait que le
  -- 1er du mois laisserait ce planning publié trente jours de plus, avec ses
  -- relances qui continuent de partir.
  archives := cron_archive_schedules(tests_arc.t0() + interval '1 day');

  perform tests_arc.egal(archives, 1,
    'vingt-quatre heures plus tard, la caserne d''outre-mer est servie');

  perform tests_arc.egal(
    (select status::text from schedules where id = '9a9a9a9a-0000-4000-8000-000000000302'),
    'archived', 'outre-mer : février archivé le 1er mars local');

  -- Et le mois en cours métropolitain n'a toujours pas bougé au passage du 2.
  perform tests_arc.egal(
    (select status::text from schedules where id = '99999999-0000-4000-8000-000000000303'),
    'published', 'mars reste publié au passage du lendemain');
end $$;

-- ===========================================================================
-- 3. Idempotence
-- ===========================================================================
-- L'ordonnanceur rejoue après un redémarrage, et la tâche passe désormais tous
-- les jours : une exécution qui n'a rien à faire doit ne rien faire.
\echo ''
\echo '--- 3. Idempotence : rejouée, la tâche n''archive plus rien'

-- Le passage au mois suivant est joué dans un point de reprise et défait
-- ensuite : `archived` est un état terminal (`schedules_guard_transition`), on ne
-- « remet pas » un planning en publié, il faut annuler le passage. La suite du
-- fichier a besoin de mars vivant comme témoin.
savepoint s3;

do $$
declare
  avant  timestamptz;
  apres  timestamptz;
begin
  select updated_at into avant from schedules
   where id = '99999999-0000-4000-8000-000000000302';

  perform tests_arc.egal(cron_archive_schedules(tests_arc.t0()), 0,
    'deuxième passage sur le même instant : zéro planning archivé');

  select updated_at into apres from schedules
   where id = '99999999-0000-4000-8000-000000000302';

  perform tests_arc.egal(apres, avant,
    'aucune ligne réécrite : updated_at inchangé');

  -- Quarante jours plus tard, le 10 avril : mars est devenu un mois passé, et
  -- lui seul. Avril, mois courant, ne bouge pas.
  perform tests_arc.egal(cron_archive_schedules(tests_arc.t0() + interval '40 days'), 1,
    'au 10 avril, mars s''archive à son tour — et lui seul');

  perform tests_arc.egal(
    (select status::text from schedules where id = '99999999-0000-4000-8000-000000000303'),
    'archived', 'mars archivé');
  perform tests_arc.egal(
    (select status::text from schedules where id = '99999999-0000-4000-8000-000000000304'),
    'published', 'avril, mois courant du 10 avril, toujours publié');

  perform tests_arc.egal(cron_archive_schedules(tests_arc.t0() + interval '40 days'), 0,
    'et le passage suivant du même jour n''archive plus rien');
end $$;

rollback to savepoint s3;

-- ===========================================================================
-- 4. Ce qu'un membre lit d'un planning archivé
-- ===========================================================================
-- La décision du ticket, en base. Un planning archivé se lit comme le tableau
-- de garde du mois écoulé : les créneaux, ses propres attributions quel qu'en
-- soit le statut, et les gardes **tenues** par les autres.
\echo ''
\echo '--- 4. La lecture d''un planning archivé par un membre'

set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  -- --- Le planning lui-même : lisible, et il l'était déjà.
  perform tests_arc.egal(
    (select status::text from schedules where id = '99999999-0000-4000-8000-000000000302'),
    'archived', 'Bastien lit la ligne du planning archivé');

  -- --- Les créneaux : c'est le changement. Avant ce ticket, zéro.
  perform tests_arc.egal(
    (select count(*)::integer from shifts
      where schedule_id = '99999999-0000-4000-8000-000000000302'),
    3, 'Bastien lit les trois créneaux du mois archivé');

  perform tests_arc.egal(
    (select count(*)::integer from shifts
      where schedule_id = '99999999-0000-4000-8000-000000000301'),
    1, 'et le créneau du mois archivé précédent');

  -- --- Le brouillon reste invisible : l'archivage n'a rien ouvert par la
  -- bande. C'est la moitié de la règle qu'on casserait le plus facilement.
  perform tests_arc.egal(
    (select count(*)::integer from schedules
      where id = '99999999-0000-4000-8000-000000000300'),
    0, 'le brouillon de décembre reste invisible d''un membre');
  perform tests_arc.egal(
    (select count(*)::integer from shifts
      where schedule_id = '99999999-0000-4000-8000-000000000300'),
    0, 'et ses créneaux avec lui');

  -- --- Ses propres attributions, toutes.
  perform tests_arc.egal(
    (select count(*)::integer from assignments a
       join shifts sh on sh.id = a.shift_id
      where sh.schedule_id = '99999999-0000-4000-8000-000000000302'
        and a.user_id = '99999999-0000-4000-8000-000000000101'),
    2, 'Bastien lit ses deux attributions de février');

  perform tests_arc.check(
    exists (select 1 from assignments
             where id = '99999999-0000-4000-8000-000000000504'
               and status = 'declined'
               and decline_reason = 'en formation'),
    'y compris son propre refus, avec le motif qu''il a écrit');

  -- --- Les gardes tenues par les autres : visibles.
  perform tests_arc.egal(
    (select count(*)::integer from assignments a
       join shifts sh on sh.id = a.shift_id
      where sh.schedule_id = '99999999-0000-4000-8000-000000000302'
        and a.status = 'accepted'),
    4, 'les quatre gardes tenues en février sont lisibles de tous');

  -- --- Le refus d'un collègue : invisible. C'est la porte que l'archivage
  -- referme, et elle était ouverte sur un planning validé.
  perform tests_arc.egal(
    (select count(*)::integer from assignments
      where id = '99999999-0000-4000-8000-000000000503'),
    0, 'le refus de Camille et son motif ne sont pas lisibles de Bastien');

  -- --- La proposition sans réponse d'un collègue : invisible aussi.
  perform tests_arc.egal(
    (select count(*)::integer from assignments
      where id = '99999999-0000-4000-8000-000000000511'),
    0, 'la proposition jamais honorée de Dorian n''est pas lisible de Bastien');

  -- --- Le compte exact : cinq lignes pour février, et pas une de plus.
  perform tests_arc.egal(
    (select count(*)::integer from assignments a
       join shifts sh on sh.id = a.shift_id
      where sh.schedule_id = '99999999-0000-4000-8000-000000000302'),
    5, 'février archivé : ses deux lignes + les quatre acceptées, soit cinq');
end $$;

-- La contre-épreuve : Dorian, lui, relit sa propre proposition restée sans
-- réponse. C'est son historique, et c'est aussi ce qui oblige l'écran des
-- propositions à filtrer sur le statut du planning (voir le compte rendu).
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000103","role":"authenticated"}';

do $$
begin
  perform tests_arc.egal(
    (select status::text from assignments
      where id = '99999999-0000-4000-8000-000000000511'),
    'proposed', 'Dorian relit sa proposition de janvier, restée sans réponse');

  -- Mais il ne peut plus y répondre : la politique de réponse d'un membre ne
  -- connaît que `published` et `validated`.
  perform tests_arc.sans_effet(
    $sql$update assignments set status = 'accepted'
          where id = '99999999-0000-4000-8000-000000000511'$sql$,
    'répondre à une proposition d''un planning archivé');

  perform tests_arc.egal(
    (select status::text from assignments
      where id = '99999999-0000-4000-8000-000000000511'),
    'proposed', 'et elle reste proposed');
end $$;

-- Et l'administrateur, lui, voit tout, comme avant : c'est à lui qu'appartient
-- l'histoire complète du mois, refus et motifs compris.
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests_arc.egal(
    (select count(*)::integer from assignments a
       join shifts sh on sh.id = a.shift_id
      where sh.schedule_id = '99999999-0000-4000-8000-000000000302'),
    6, 'l''admin lit les six attributions de février, refus compris');

  perform tests_arc.egal(
    (select decline_reason from assignments
      where id = '99999999-0000-4000-8000-000000000503'),
    'rendez-vous médical', 'et le motif du refus de Camille');
end $$;

-- ===========================================================================
-- 5. Cloisonnement
-- ===========================================================================
-- Ouvrir une lecture, c'est toujours risquer d'en ouvrir une autre. L'admin de
-- la caserne d'outre-mer ne lit rien de « CIS Archive ».
\echo ''
\echo '--- 5. La caserne voisine ne lit rien de tout cela'

set local request.jwt.claims = '{"sub":"9a9a9a9a-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests_arc.egal(
    (select count(*)::integer from schedules
      where station_id = '99999999-0000-4000-8000-000000000001'),
    0, 'aucun planning de CIS Archive');

  perform tests_arc.egal(
    (select count(*)::integer from shifts
      where station_id = '99999999-0000-4000-8000-000000000001'),
    0, 'aucun créneau de CIS Archive');

  perform tests_arc.egal(
    (select count(*)::integer from assignments
      where station_id = '99999999-0000-4000-8000-000000000001'),
    0, 'aucune attribution de CIS Archive');

  -- Et son propre mois archivé, lui, se lit.
  perform tests_arc.egal(
    (select count(*)::integer from shifts
      where schedule_id = '9a9a9a9a-0000-4000-8000-000000000302'),
    1, 'mais bien le créneau de son propre mois archivé');
end $$;

reset role;

-- ===========================================================================
-- 6. Un planning archivé ne se modifie plus
-- ===========================================================================
-- Le ticket demandait de vérifier, pas de supposer. Deux des dix chemins
-- d'écriture étaient ouverts avant la migration 0031 : l'insertion et la mise à
-- jour d'un créneau, l'insertion et la mise à jour d'une attribution.
\echo ''
\echo '--- 6. Les dix chemins d''écriture vers un planning archivé'

-- 6.1 — Les transitions, et la suppression. Elles valent pour tout le monde,
-- rôle de service compris : `schedules_guard_transition` et les deux gardes de
-- suppression sont `security invoker` (0019).
do $$
begin
  perform tests_arc.refuse(
    $sql$update schedules set status = 'published'
          where id = '99999999-0000-4000-8000-000000000302'$sql$,
    'schedule_invalid_transition', 'archived -> published : refusé');

  perform tests_arc.refuse(
    $sql$update schedules set status = 'validated'
          where id = '99999999-0000-4000-8000-000000000302'$sql$,
    'schedule_invalid_transition', 'archived -> validated : refusé');

  perform tests_arc.refuse(
    $sql$update schedules set status = 'draft'
          where id = '99999999-0000-4000-8000-000000000302'$sql$,
    'schedule_invalid_transition', 'archived -> draft : refusé');

  perform tests_arc.refuse(
    $sql$delete from schedules where id = '99999999-0000-4000-8000-000000000302'$sql$,
    'schedule_delete_published', 'un planning archivé ne se supprime pas');

  perform tests_arc.refuse(
    $sql$delete from shifts where id = '99999999-0000-4000-8000-000000000401'$sql$,
    'shift_delete_published', 'un créneau d''un planning archivé ne se supprime pas');

  -- Et la cascade depuis le mois, qui ne consulte aucune politique.
  perform tests_arc.refuse(
    $sql$delete from periods where id = '99999999-0000-4000-8000-000000000202'$sql$,
    'schedule_delete_published', 'supprimer le mois n''emporte pas le planning archivé');
end $$;

-- 6.2 — Les deux fonctions de modification d'un planning vivant. Elles
-- refusaient déjà, et le test le prouve plutôt que de le supposer.
-- `reassign_shift` est réservée au rôle de service et vérifie son acteur par
-- paramètre : elle s'appelle donc ici sous `postgres`, comme le fait l'Edge
-- Function. `cancel_assignment` lit `auth.uid()` et reste ouverte à
-- `authenticated`.
do $$
declare
  r jsonb;
begin
  r := reassign_shift(
        '99999999-0000-4000-8000-000000000403',
        '99999999-0000-4000-8000-000000000103',
        '99999999-0000-4000-8000-000000000100',
        '99999999-0000-4000-8000-000000000504');
  perform tests_arc.egal(r ->> 'code', 'schedule_not_published',
    'reassign_shift refuse un planning archivé');
end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  r jsonb;
begin
  r := cancel_assignment('99999999-0000-4000-8000-000000000501', 'trop tard');
  perform tests_arc.egal(r ->> 'code', 'schedule_not_published',
    'cancel_assignment refuse un planning archivé');
end $$;

reset role;

-- 6.3 — Les quatre chemins que la migration 0031 ferme. C'est un
-- **administrateur** de la caserne qui essaie : avant 0031, tout passait.
set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  -- Ajouter un créneau à un mois archivé.
  perform tests_arc.refuse(
    $sql$insert into shifts (station_id, schedule_id, date, slot, required_count)
          values ('99999999-0000-4000-8000-000000000001',
                  '99999999-0000-4000-8000-000000000302',
                  '2029-02-04', 'day', 1)$sql$,
    '42501', 'un créneau ne s''ajoute pas à un planning archivé');

  -- Changer l'effectif requis d'un créneau archivé.
  perform tests_arc.sans_effet(
    $sql$update shifts set required_count = 5
          where id = '99999999-0000-4000-8000-000000000401'$sql$,
    'l''effectif requis d''un créneau archivé ne se modifie plus');

  -- Attribuer quelqu'un sur un mois archivé.
  perform tests_arc.refuse(
    $sql$insert into assignments (station_id, shift_id, user_id, status)
          values ('99999999-0000-4000-8000-000000000001',
                  '99999999-0000-4000-8000-000000000403',
                  '99999999-0000-4000-8000-000000000103', 'proposed')$sql$,
    '42501', 'une attribution ne s''ajoute pas à un planning archivé');

  -- Réécrire une réponse déjà donnée. Sans 0031, un refus d'il y a un an
  -- devenait une acceptation — et, depuis la section 4, une acceptation est
  -- lisible de toute la caserne.
  perform tests_arc.sans_effet(
    $sql$update assignments set status = 'accepted'
          where id = '99999999-0000-4000-8000-000000000504'$sql$,
    'la réponse d''un membre sur un mois archivé ne se réécrit plus');

  -- Déplacer une attribution vivante **vers** un créneau archivé : fermé par le
  -- `with check`, là où le `using` ne voyait qu'un planning publié.
  perform tests_arc.refuse(
    $sql$update assignments set shift_id = '99999999-0000-4000-8000-000000000401'
          where id = '99999999-0000-4000-8000-000000000521'$sql$,
    '42501', 'une attribution vivante ne se déplace pas vers un créneau archivé');

  -- Le témoin : sur le mois en cours, l'administrateur écrit toujours.
  perform tests_arc.check(
    (select count(*) from shifts
      where schedule_id = '99999999-0000-4000-8000-000000000303') = 1,
    'témoin : le planning de mars est bien publié');

  update shifts set required_count = 2
   where id = '99999999-0000-4000-8000-000000000421';
  perform tests_arc.egal(
    (select required_count from shifts where id = '99999999-0000-4000-8000-000000000421'),
    2, 'témoin : l''effectif d''un créneau publié se modifie toujours');
end $$;

reset role;

-- ===========================================================================
-- 7. Le flux calendrier garde son historique
-- ===========================================================================
-- `ics_feed_events` promet quatre-vingt-dix jours en arrière. Sans le
-- changement de 0031, l'archivage aurait ramené cette promesse à « depuis le 1er
-- du mois » sans qu'aucune requête n'échoue.
\echo ''
\echo '--- 7. ics_feed_events : quatre-vingt-dix jours, archivage compris'

do $$
declare
  jeton text;
  flux  jsonb;
  dates text[];
begin
  select ics_token into jeton from profiles
   where id = '99999999-0000-4000-8000-000000000101';

  flux := ics_feed_events(jeton, '2029-03-15'::date);
  perform tests_arc.check((flux ->> 'ok')::boolean, 'le flux répond');

  select array_agg(e ->> 'date' order by e ->> 'date')
    into dates
    from jsonb_array_elements(flux -> 'evenements') as e;

  -- Janvier et février sont archivés, mars est publié : les trois gardes
  -- acceptées de Bastien sont là.
  perform tests_arc.egal(dates,
    array['2029-01-05', '2029-02-01', '2029-03-10'],
    'les trois gardes acceptées, dont deux sur des plannings archivés');
end $$;

-- ===========================================================================
-- 8. La tâche planifiée et les droits
-- ===========================================================================
\echo ''
\echo '--- 8. cron.job et fermeture de la fonction'

do $$
declare
  ligne record;
begin
  select jobname, schedule, command, active into ligne
    from cron.job where jobname = 'archive_schedules';

  perform tests_arc.check(ligne.jobname is not null,
    'la tâche archive_schedules est planifiée');
  perform tests_arc.egal(ligne.schedule, '30 2 * * *',
    'quotidienne à 02:30 — voir l''écart assumé de la migration 0031');
  perform tests_arc.egal(btrim(ligne.command),
    'select public.cron_archive_schedules();',
    'commande qualifiée et sans argument');
  perform tests_arc.check(ligne.active, 'et active');
end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"99999999-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests_arc.refuse(
    $sql$select cron_archive_schedules()$sql$,
    '42501', 'un administrateur n''archive pas la Terre entière en RPC');
end $$;

reset role;

do $$
begin
  perform tests_arc.check(
    not has_function_privilege('authenticated', 'cron_archive_schedules(timestamptz)', 'execute'),
    'cron_archive_schedules fermée à authenticated');
  perform tests_arc.check(
    not has_function_privilege('anon', 'cron_archive_schedules(timestamptz)', 'execute'),
    'cron_archive_schedules fermée à anon');
  perform tests_arc.check(
    not has_function_privilege('authenticated', 'ics_feed_events(text, date)', 'execute'),
    'ics_feed_events reste fermée à authenticated après son remplacement');
  perform tests_arc.check(
    has_function_privilege('service_role', 'ics_feed_events(text, date)', 'execute'),
    'et toujours ouverte au rôle de service');
end $$;

\echo ''
\echo '=== Archivage des plannings : OK ==='

rollback;
