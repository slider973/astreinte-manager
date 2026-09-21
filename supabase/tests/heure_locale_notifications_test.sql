-- Tests de l'heure locale d'envoi des notifications (migration 0033, ticket 041).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
-- 1. Le réglage `notification_hour` : facultatif, borné 6–20, entier, et une
--    caserne qui ne le porte pas reste enregistrable — le piège du ticket 038.
-- 2. `station_notification_window` : la fenêtre locale d'une caserne très
--    décalée, heure par heure sur vingt-quatre heures.
-- 3. **Le critère d'acceptation du ticket.** Une caserne de Kiritimati (UTC+14)
--    reçoit son rappel de saisie à l'heure locale visée, et une seule fois,
--    alors que la tâche est tirée vingt-quatre fois dans sa journée.
-- 4. La valeur par défaut — 9 — pour une caserne qui n'a rien réglé, et l'heure
--    choisie pour une caserne qui a réglé.
-- 5. Les trois tâches qui écrivent aux membres partagent le même mécanisme :
--    rappels de saisie, relances d'attribution, rapport aux administrateurs.
-- 6. Les tâches qui n'écrivent à personne — purges, archivage, périodes — ne
--    dépendent pas de l'heure locale : elles tournent la nuit sans rien devoir
--    à ce ticket.
-- 7. La tâche `availability_reminders` est planifiée toutes les heures, et les
--    deux fonctions de réglage ne sont appelables ni par `anon` ni par
--    `authenticated`.
--
-- Rien ici n'appelle l'Edge Function : `notify_post` est remplacée, le temps du
-- test, par une version qui ne fait pas d'appel HTTP — même procédé que
-- `notifications_test.sql` et `availability_reminders_test.sql`.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : le seed (caserne A = aaaaaaaa-…-001, caserne B = bbbbbbbb-…-001,
-- neuf appartenances actives chacune), dont le fuseau est déplacé ici, plus des
-- périodes en 2032, une année que le seed ne touche jamais.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_hl;

create function tests_hl.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

create function tests_hl.egal(p_valeur anyelement, p_attendu anyelement, p_label text)
returns void language plpgsql as $$
begin
  if p_valeur is distinct from p_attendu then
    raise exception 'ECHEC : % — attendu %, obtenu %', p_label, p_attendu, p_valeur;
  end if;
  raise notice '  ok   % (%)', p_label, p_valeur;
end $$;

create function tests_hl.refuse(p_sql text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — l''écriture a été acceptée', p_label;
exception
  when check_violation then
    raise notice '  ok   % (refusé par la contrainte)', p_label;
end $$;

-- L'appel HTTP est coupé, son effet de bord est gardé.
create or replace function notify_post(p_outbox uuid) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  ligne notification_outbox;
begin
  select * into ligne from notification_outbox where id = p_outbox;
  if not found or ligne.status <> 'pending' then
    return false;
  end if;

  update notification_outbox
     set attempts     = attempts + 1,
         locked_until = now() + interval '2 minutes'
   where id = p_outbox;

  return true;
end $$;

\set caserne_a '''aaaaaaaa-0000-4000-8000-000000000001'''
\set caserne_b '''bbbbbbbb-0000-4000-8000-000000000001'''

-- ===========================================================================
-- 1. Le réglage : facultatif, borné, entier
-- ===========================================================================
\echo ''
\echo '--- 1. settings.notification_hour'

-- Le point qui a coûté une revue au ticket 038, et qui vaut pour toute clé
-- ajoutée après coup : la contrainte `stations_settings_valide` est rejouée à
-- **chaque** écriture d'une ligne `stations`. Une caserne du seed, qui ne porte
-- pas la clé, doit pouvoir continuer d'enregistrer ses réglages.
select tests_hl.check(
  not ((select settings from stations where id = :caserne_a) ? 'notification_hour'),
  'décor : la caserne A ne porte pas la clé');

savepoint s1;

update stations set settings = settings || '{"required_day": 2}'::jsonb
 where id = :caserne_a;

select tests_hl.check(
  (select (settings ->> 'required_day')::int from stations where id = :caserne_a) = 2,
  'une caserne sans la clé enregistre toujours ses autres réglages');

rollback to savepoint s1;

savepoint s1b;

-- Les bornes. 6 et 20 passent, 5 et 21 non.
update stations set settings = settings || '{"notification_hour": 6}'::jsonb
 where id = :caserne_a;
select tests_hl.egal(
  station_notification_hour(:caserne_a), 6, '6 est accepté (borne basse)');

update stations set settings = settings || '{"notification_hour": 20}'::jsonb
 where id = :caserne_a;
select tests_hl.egal(
  station_notification_hour(:caserne_a), 20, '20 est accepté (borne haute)');

rollback to savepoint s1b;

savepoint s1c;

select tests_hl.refuse(
  $$update stations set settings = settings || '{"notification_hour": 5}'::jsonb
     where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  '5 est refusé : avant six heures, on réveille');

select tests_hl.refuse(
  $$update stations set settings = settings || '{"notification_hour": 21}'::jsonb
     where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  '21 est refusé : la fenêtre se ferme à 20, elle serait vide');

select tests_hl.refuse(
  $$update stations set settings = settings || '{"notification_hour": "09:00"}'::jsonb
     where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'une chaîne « HH:MM » est refusée : la fenêtre porte sur l''heure, pas la minute');

select tests_hl.refuse(
  $$update stations set settings = settings || '{"notification_hour": 9.5}'::jsonb
     where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'une demi-heure est refusée : ce n''est pas un entier d''horloge');

select tests_hl.refuse(
  $$update stations set settings = settings || '{"notification_hours": 9}'::jsonb
     where id = 'aaaaaaaa-0000-4000-8000-000000000001'$$,
  'la clé mal orthographiée reste refusée : la liste blanche tient');

rollback to savepoint s1c;

-- ===========================================================================
-- 2. La fenêtre, heure locale par heure locale
-- ===========================================================================
\echo ''
\echo '--- 2. station_notification_window sur vingt-quatre heures locales'

savepoint s2;

-- Kiritimati, UTC+14 : le fuseau le plus en avance du monde, et le décalage le
-- plus brutal qu'une caserne française puisse connaître est du même ordre
-- (Wallis UTC+12, Papeete UTC-10).
update stations set timezone = 'Pacific/Kiritimati' where id = :caserne_a;

do $$
declare
  h integer;
  dedans integer[] := '{}';
begin
  for h in 0..23 loop
    if station_notification_window(
         'aaaaaaaa-0000-4000-8000-000000000001',
         make_timestamptz(2032, 6, 12, h, 0, 0, 'Pacific/Kiritimati')) then
      dedans := dedans || h;
    end if;
  end loop;

  perform tests_hl.egal(
    dedans,
    array[9,10,11,12,13,14,15,16,17,18,19,20],
    'la fenêtre par défaut va de 9 h à 20 h locales incluses');
end $$;

-- Le réglage déplace la borne basse, jamais la borne haute : celle-ci n'est pas
-- une préférence de caserne mais une limite de politesse.
update stations set settings = settings || '{"notification_hour": 7}'::jsonb
 where id = :caserne_a;

do $$
declare
  h integer;
  dedans integer[] := '{}';
begin
  for h in 0..23 loop
    if station_notification_window(
         'aaaaaaaa-0000-4000-8000-000000000001',
         make_timestamptz(2032, 6, 12, h, 0, 0, 'Pacific/Kiritimati')) then
      dedans := dedans || h;
    end if;
  end loop;

  perform tests_hl.egal(
    dedans,
    array[7,8,9,10,11,12,13,14,15,16,17,18,19,20],
    'réglée à 7, la fenêtre s''ouvre à 7 h et se ferme toujours à 20 h');
end $$;

-- Un fuseau à la demi-heure : la fenêtre porte sur l'heure, l'heure locale des
-- Marquises est donc lue telle quelle, sans cas particulier.
update stations set timezone = 'Pacific/Marquesas' where id = :caserne_a;  -- UTC-09:30
update stations set settings = settings - 'notification_hour' where id = :caserne_a;

select tests_hl.check(
  station_notification_window(:caserne_a,
    make_timestamptz(2032, 6, 12, 9, 30, 0, 'Pacific/Marquesas')),
  'Marquises (UTC-09:30) : 9 h 30 locales est dans la fenêtre');

select tests_hl.check(
  not station_notification_window(:caserne_a,
    make_timestamptz(2032, 6, 12, 8, 59, 0, 'Pacific/Marquesas')),
  'Marquises : 8 h 59 locales ne l''est pas');

rollback to savepoint s2;

-- ===========================================================================
-- 3. Le critère d'acceptation : une caserne très décalée, un seul rappel
-- ===========================================================================
\echo ''
\echo '--- 3. Kiritimati (UTC+14) : le rappel part à 9 h locales, et une seule fois'

savepoint s3;

-- La caserne A part à l'autre bout du monde. Sa période de juillet 2032 ferme
-- le 15 juin 2032 à 23:59:59 **chez elle** : le 12 juin local est donc son J-3.
update stations set timezone = 'Pacific/Kiritimati' where id = :caserne_a;

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('eeeeeeee-0000-4000-8000-000000000041', :caserne_a, 2032, 7, 'open',
   make_timestamptz(2032, 6, 15, 23, 59, 59, 'Pacific/Kiritimati'));

select tests_hl.egal(
  (select count(*)::int from memberships
    where station_id = :caserne_a and status = 'active'),
  9, 'décor : neuf appartenances actives');

-- Vingt-quatre tirs, un par heure de la journée locale du 12 juin 2032, dans
-- l'ordre. On note ce que chacun a mis en file.
do $$
declare
  h        integer;
  n        integer;
  envois   jsonb := '{}'::jsonb;
  total    integer := 0;
begin
  for h in 0..23 loop
    n := cron_availability_reminders(
           make_timestamptz(2032, 6, 12, h, 0, 0, 'Pacific/Kiritimati'));
    total := total + n;
    if n > 0 then
      envois := envois || jsonb_build_object(h::text, n);
    end if;
  end loop;

  -- **Le cœur du ticket.** Un seul des vingt-quatre tirs a envoyé quelque
  -- chose, et c'est celui de 9 h locales. Les huit premiers sont la nuit et le
  -- petit matin de Kiritimati — 19:00 à 02:00 UTC la veille —, c'est-à-dire
  -- exactement les heures où la tâche quotidienne de 0016 tirait.
  perform tests_hl.egal(envois, jsonb_build_object('9', 9),
    'un seul tir a envoyé, celui de 9 h locales, et il a envoyé les neuf rappels');

  -- Et la clé de dédoublonnage a bien absorbé les quinze tirs suivants : ce
  -- n'est pas « on n'a pas regardé », c'est « on a regardé et on n'a rien
  -- reposté ».
  perform tests_hl.egal(total, 9, 'neuf rappels au total sur vingt-quatre tirs');
end $$;

select tests_hl.egal(
  (select count(*)::int from notification_outbox
    where type = 'availability_reminder'
      and dedupe_key like 'availability_reminder:' || :caserne_a || ':2032-07:j-3:%'),
  9, 'neuf lignes en file, une par membre : aucun doublon');

select tests_hl.check(
  (select bool_and(attempts = 1) from notification_outbox
    where type = 'availability_reminder'),
  'et aucune demande n''a été reposée : les tirs suivants n''ont rien touché');

-- Le lendemain local, l'échéance a changé (J-2) : plus rien, à aucune heure.
do $$
declare
  h integer;
  total integer := 0;
begin
  for h in 0..23 loop
    total := total + cron_availability_reminders(
      make_timestamptz(2032, 6, 13, h, 0, 0, 'Pacific/Kiritimati'));
  end loop;
  perform tests_hl.egal(total, 0,
    'le lendemain local, J-2 : vingt-quatre tirs, rien du tout');
end $$;

rollback to savepoint s3;

-- ===========================================================================
-- 4. Le défaut, et le réglage
-- ===========================================================================
\echo ''
\echo '--- 4. 9 h par défaut, l''heure choisie sinon'

savepoint s4;

-- La caserne A n'a rien réglé : 9 h. La caserne B règle 7 h. Les deux sont à
-- Midway (UTC-11), l'autre extrême, pour que la démonstration ne doive rien au
-- fuseau du serveur.
update stations set timezone = 'Pacific/Midway' where id in (:caserne_a, :caserne_b);
update stations set settings = settings || '{"notification_hour": 7}'::jsonb
 where id = :caserne_b;

select tests_hl.egal(
  station_notification_hour(:caserne_a), 9,
  'caserne sans réglage : 9 h, le défaut documenté');
select tests_hl.egal(
  station_notification_hour(:caserne_b), 7,
  'caserne réglée : 7 h');

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('eeeeeeee-0000-4000-8000-000000000042', :caserne_a, 2032, 7, 'open',
   make_timestamptz(2032, 6, 15, 23, 59, 59, 'Pacific/Midway')),
  ('eeeeeeee-0000-4000-8000-000000000043', :caserne_b, 2032, 7, 'open',
   make_timestamptz(2032, 6, 15, 23, 59, 59, 'Pacific/Midway'));

-- 7 h locales : seule la caserne B est servie.
select tests_hl.egal(
  cron_availability_reminders(make_timestamptz(2032, 6, 12, 7, 0, 0, 'Pacific/Midway')),
  9, 'à 7 h locales, seule la caserne réglée à 7 h reçoit');

select tests_hl.egal(
  (select count(*)::int from notification_outbox
    where type = 'availability_reminder' and station_id = :caserne_a::uuid),
  0, 'la caserne au défaut n''a encore rien reçu');

-- 9 h locales : la caserne A est servie à son tour, la B ne l'est pas deux fois.
select tests_hl.egal(
  cron_availability_reminders(make_timestamptz(2032, 6, 12, 9, 0, 0, 'Pacific/Midway')),
  9, 'à 9 h locales, c''est au tour de la caserne au défaut');

select tests_hl.egal(
  (select count(*)::int from notification_outbox where type = 'availability_reminder'),
  18, 'dix-huit au total : neuf par caserne, chacune à son heure');

rollback to savepoint s4;

-- ===========================================================================
-- 5. Les trois tâches qui écrivent aux membres, un seul mécanisme
-- ===========================================================================
\echo ''
\echo '--- 5. Le même mécanisme pour les trois tâches'

savepoint s5;

-- Chaque tâche appelle bien `station_notification_window` : c'est ce qui
-- garantit qu'il n'y a pas deux règles de politesse dans la base, dont une
-- qu'on oublierait de corriger. Le ticket 022 avait écrit la sienne en dur
-- (`between 8 and 20`) ; elle a disparu.
do $$
declare
  nom text;
  corps text;
begin
  foreach nom in array array[
    'cron_availability_reminders',
    'cron_assignment_reminders',
    'cron_late_responders_report']
  loop
    select pg_get_functiondef(p.oid) into corps
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = nom;

    perform tests_hl.check(
      corps like '%station_notification_window%',
      format('%s passe par la fenêtre commune', nom));

    perform tests_hl.check(
      corps not like '%between 8 and 20%',
      format('%s ne porte plus de fenêtre écrite en dur', nom));
  end loop;
end $$;

rollback to savepoint s5;

-- ===========================================================================
-- 6. Les tâches qui n'écrivent à personne tournent la nuit
-- ===========================================================================
\echo ''
\echo '--- 6. Purges, archivage, périodes : pas concernés'

savepoint s6;

-- Aucune de ces fonctions n'appelle `notify` : aucune ne réveille personne,
-- aucune n'a de raison d'attendre le matin. La vérification est faite sur le
-- texte des fonctions, à la source, plutôt que sur une liste tenue à la main.
do $$
declare
  nom text;
  corps text;
begin
  foreach nom in array array[
    'cron_create_periods',
    'cron_lock_periods',
    'cron_archive_schedules',
    'cron_prune_notifications',
    'cron_prune_retention']
  loop
    select pg_get_functiondef(p.oid) into corps
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = nom;

    perform tests_hl.check(corps is not null, format('%s existe', nom));
    perform tests_hl.check(
      corps not like '%perform notify(%' and corps not like '%station_notification_window%',
      format('%s n''écrit à personne et ne dépend pas de l''heure locale', nom));
  end loop;
end $$;

-- Et elles marchent pour de vrai au milieu de la nuit de n'importe quelle
-- caserne : 03:00 UTC, soit 17:00 à Kiritimati et 16:00 à Midway — la nuit
-- quelque part, toujours.
update stations set timezone = 'Pacific/Kiritimati' where id = :caserne_a;

select tests_hl.check(
  cron_archive_schedules('2032-06-12 03:00:00+00') >= 0,
  'l''archivage tourne à 3 h du matin sans rien demander à personne');

select tests_hl.check(
  cron_prune_notifications('2032-06-12 04:00:00+00') >= 0,
  'la purge des notifications aussi');

select tests_hl.check(
  cron_prune_retention('2032-06-12 04:20:00+00') is not null,
  'et celle des durées de conservation');

select tests_hl.egal(
  (select count(*)::int from notification_outbox
    where created_at > now() - interval '1 minute'),
  0, 'et aucune d''elles n''a mis quoi que ce soit en file');

rollback to savepoint s6;

-- ===========================================================================
-- 7. La planification et les droits
-- ===========================================================================
\echo ''
\echo '--- 7. pg_cron et exécution réservée'

select tests_hl.egal(
  (select schedule from cron.job where jobname = 'availability_reminders'),
  '30 * * * *',
  'availability_reminders tire toutes les heures (docs/SCHEMA.md § 8)');

select tests_hl.egal(
  (select command from cron.job where jobname = 'availability_reminders'),
  'select public.cron_availability_reminders();',
  'la commande reste qualifiée et sans argument');

-- Les trois tâches horaires ne démarrent pas à la même seconde : elles
-- verrouilleraient les mêmes lignes de notification_outbox pour rien.
select tests_hl.egal(
  (select count(distinct schedule)::int from cron.job
    where jobname in ('availability_reminders', 'assignment_reminders',
                      'late_responders_report', 'lock_periods')),
  4, 'les quatre tâches horaires ont quatre minutes de démarrage distinctes');

select tests_hl.check(
  not has_function_privilege('authenticated',
    'public.station_notification_hour(uuid)', 'execute')
  and not has_function_privilege('anon',
    'public.station_notification_hour(uuid)', 'execute'),
  'station_notification_hour n''est appelable ni par authenticated ni par anon');

select tests_hl.check(
  not has_function_privilege('authenticated',
    'public.station_notification_window(uuid, timestamptz)', 'execute')
  and not has_function_privilege('anon',
    'public.station_notification_window(uuid, timestamptz)', 'execute'),
  'station_notification_window non plus');

-- `station_settings_valid` reste exécutable par tout le monde : la contrainte
-- `check` est évaluée sous l'identité de qui écrit, et une fonction non
-- exécutable rendrait toute mise à jour de caserne impossible (0011).
select tests_hl.check(
  has_function_privilege('authenticated',
    'public.station_settings_valid(jsonb)', 'execute'),
  'station_settings_valid reste exécutable : c''est le support d''une contrainte');

\echo ''
\echo 'Heure locale des notifications : OK'

rollback;
