-- Tests des rappels de saisie des disponibilités (migration 0016, ticket 015).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
-- 1. J-3 : un rappel par membre sans saisie, en push, avec la charge utile que
--    l'Edge Function sait lire (`period`, `deadline_at` ISO) et le bon lien.
-- 2. J-1 : le même monde, en courriel. Et rien les autres jours — ni J-4, ni J-2,
--    ni le jour même, ni la veille de l'ouverture.
-- 3. Un membre ayant saisi **au moins un créneau** ne reçoit rien. C'est le
--    critère d'acceptation du ticket. Une ligne `absent` compte comme une
--    réponse : le membre a dit quelque chose.
-- 4. Aucun doublon si la tâche tourne deux fois le même jour, ni si elle est
--    rejouée après un redémarrage de l'ordonnanceur. La garantie est la clé de
--    dédoublonnage de 0014, pas un état supplémentaire.
-- 5. Le fuseau de la caserne décide du jour : à un même instant, Midway (UTC-11)
--    et Kiritimati (UTC+14) ne sont pas à la même distance de leur date limite.
-- 6. Une période verrouillée et une caserne suspendue ne relancent personne ;
--    un membre `disabled` ou `invited` non plus.
-- 7. Chaque caserne a son rappel : deux casernes qui partagent un membre et un
--    mois ne se volent pas l'échéance (docs/PRD.md § 6.1).
-- 8. La tâche est planifiée, qualifiée, sans argument, et sa fonction n'est pas
--    appelable par un client.
--
-- Rien ici n'appelle l'Edge Function : `notify_post` est remplacée, le temps du
-- test, par une version qui ne fait pas d'appel HTTP — même procédé que
-- `notifications_test.sql`. La CI n'a ni edge-runtime ni Kong.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : le seed (caserne A = aaaaaaaa-…-001 « CIS Saint-Martin », admin
-- …100, membres …101 à …108 ; caserne B = bbbbbbbb-…-001), plus des périodes
-- créées ici dans des années qui ne croisent jamais celles du seed.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests;

create function tests.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

create function tests.denied(p_sql text, p_label text) returns void
language plpgsql as $$
declare
  n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n > 0 then
    raise exception 'ECHEC : % — % ligne(s) alors que ça devait être refusé', p_label, n;
  end if;
  raise notice '  ok   % (0 ligne)', p_label;
exception
  when insufficient_privilege then
    raise notice '  ok   % (refusé : %)', p_label, sqlerrm;
end $$;

-- La section 7 se place sous l'identité d'un admin : il doit pouvoir appeler les
-- assertions, sinon c'est le test qui échoue et non la règle qui est vérifiée.
grant usage on schema tests to authenticated, anon;
grant execute on all functions in schema tests to authenticated, anon;

-- ---------------------------------------------------------------------------
-- L'appel HTTP de la file est coupé, son effet de bord est gardé
-- ---------------------------------------------------------------------------
-- Même remplacement que dans `notifications_test.sql` : la vraie `notify_post`
-- lit Vault et appelle `net.http_post`. On garde le compteur de tentatives et le
-- verrou — ce qui permet de vérifier qu'un rejeu ne repose rien — et on coupe le
-- réseau. Le remplacement est annulé avec la transaction.
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

-- ---------------------------------------------------------------------------
-- Le décor : une période ouverte en juillet 2031 pour la caserne A, date limite
-- le 15 juin 2031 à 23:59:59 heure de Paris. Aucun membre n'a saisi.
-- ---------------------------------------------------------------------------
-- Les deux instants de référence sont pris à 09:00 UTC, l'heure de la tâche.
--   - J-3 = 12 juin 2031, 09:00 UTC (11:00 à Paris, donc bien le 12 sur place)
--   - J-1 = 14 juin 2031, 09:00 UTC
\set periode_id '''eeeeeeee-0000-4000-8000-000000000001'''
\set caserne_a '''aaaaaaaa-0000-4000-8000-000000000001'''
\set caserne_b '''bbbbbbbb-0000-4000-8000-000000000001'''

insert into periods (id, station_id, year, month, status, deadline_at) values
  (:periode_id, :caserne_a, 2031, 7, 'open',
   make_timestamptz(2031, 6, 15, 23, 59, 59, 'Europe/Paris'));

-- Le seed garnit les mois M+1 et M+2 de l'année courante, jamais 2031 : le
-- dénominateur de ce fichier est donc bien « tous les membres actifs ».
select tests.check(
  (select count(*) from memberships
    where station_id = :caserne_a and status = 'active') = 9,
  'décor : 9 appartenances actives dans la caserne A (1 admin + 8 membres)');

select tests.check(
  (select count(*) from availabilities
    where station_id = :caserne_a
      and date >= '2031-07-01' and date < '2031-08-01') = 0,
  'décor : personne n''a saisi juillet 2031');

\echo ''
\echo '== 1. J-3 : le push part à tous ceux qui n''ont rien saisi'

savepoint avant_j3;

select cron_availability_reminders('2031-06-12 09:00:00+00') as n_j3 \gset

select tests.check(
  :'n_j3'::int = 9,
  'neuf rappels mis en file, un par membre actif sans saisie');

select tests.check(
  (select count(*) from notification_outbox
    where type = 'availability_reminder'
      and dedupe_key like 'availability_reminder:' || :caserne_a || ':2031-07:j-3:%') = 9,
  'une ligne de file par membre, clé « caserne:mois:échéance:membre »');

-- L'admin est un membre actif : il saisit ses dispos comme les autres et se fait
-- relancer comme les autres (docs/PRD.md § 6.2).
select tests.check(
  (select count(*) from notification_outbox
    where dedupe_key = 'availability_reminder:' || :caserne_a
                       || ':2031-07:j-3:aaaaaaaa-0000-4000-8000-000000000100') = 1,
  'l''admin aussi : il est membre actif, il saisit, donc il est relancé');

select tests.check(
  (select station_id = :caserne_a::uuid
      and channels = array['push', 'inapp']
      and recipients = jsonb_build_array(
            jsonb_build_object('user_id', 'aaaaaaaa-0000-4000-8000-000000000101'))
     from notification_outbox
    where dedupe_key = 'availability_reminder:' || :caserne_a
                       || ':2031-07:j-3:aaaaaaaa-0000-4000-8000-000000000101'),
  'J-3 part en push (+ inapp), à un seul destinataire nommé, dans sa caserne');

-- La charge utile est exactement celle que lit `construireContenu` côté Edge
-- Function : `period` en AAAA-MM, `deadline_at` en ISO 8601 UTC. 23:59:59 à
-- Paris en juin (UTC+2) = 21:59:59 UTC — et le rappel ne doit pas annoncer la
-- veille au membre.
select tests.check(
  (select payload = jsonb_build_object(
            'period', '2031-07',
            'deadline_at', '2031-06-15T21:59:59Z')
     from notification_outbox
    where dedupe_key = 'availability_reminder:' || :caserne_a
                       || ':2031-07:j-3:aaaaaaaa-0000-4000-8000-000000000101'),
  'la charge utile porte le mois et la date limite en ISO 8601 UTC');

-- Idempotence : deux tirs le même jour, un seul rappel.
select tests.check(
  cron_availability_reminders('2031-06-12 09:00:00+00') = 0,
  'un second tir le même jour ne met rien de plus en file');

-- Et pas seulement « rien de plus » : rien n'est reposté non plus. Un compteur
-- de tentatives qui monterait ferait repartir la demande vers l'Edge Function.
select tests.check(
  (select count(*) = 9 and bool_and(attempts = 1)
     from notification_outbox
    where dedupe_key like 'availability_reminder:' || :caserne_a || ':2031-07:j-3:%'),
  'le rejeu ne repose pas les demandes : aucun doublon d''envoi');

-- Même heure locale, heure UTC différente : la tâche rejouée après un
-- redémarrage de l'ordonnanceur ne double pas non plus.
select tests.check(
  cron_availability_reminders('2031-06-12 17:42:00+00') = 0,
  'un rejeu plus tard dans la même journée locale ne double pas le rappel');

rollback to savepoint avant_j3;

\echo ''
\echo '== 2. J-1 : le courriel, et rien les autres jours'

savepoint avant_j1;

select tests.check(
  cron_availability_reminders('2031-06-14 09:00:00+00') = 9,
  'neuf rappels à J-1');

select tests.check(
  (select channels = array['email', 'inapp']
     from notification_outbox
    where dedupe_key = 'availability_reminder:' || :caserne_a
                       || ':2031-07:j-1:aaaaaaaa-0000-4000-8000-000000000101'),
  'J-1 part en courriel (+ inapp) : docs/WORKFLOWS.md § 8');

-- Les deux échéances cohabitent : ce sont deux clés différentes, donc deux
-- rappels, comme le veut docs/WORKFLOWS.md § 7.
-- En deux instructions : dans une seule, le `count(*)` lirait le snapshot pris
-- avant l'appel et compterait les neuf lignes d'hier.
select tests.check(
  cron_availability_reminders('2031-06-12 09:00:00+00') = 9,
  'le J-3 du même mois part aussi : ce n''est pas la même échéance');

select tests.check(
  (select count(*) from notification_outbox where type = 'availability_reminder') = 18,
  'J-3 et J-1 cohabitent en file, neuf chacun');

rollback to savepoint avant_j1;

savepoint avant_jours_muets;

-- Tous les autres jours, la tâche ne doit rien faire : c'est ce qui la rend sûre
-- à lancer tous les jours à 09:00.
select tests.check(
  cron_availability_reminders('2031-06-11 09:00:00+00') = 0, 'J-4 : rien');
select tests.check(
  cron_availability_reminders('2031-06-13 09:00:00+00') = 0, 'J-2 : rien');
select tests.check(
  cron_availability_reminders('2031-06-15 09:00:00+00') = 0,
  'le jour de la date limite : rien — c''est trop tard pour un rappel utile');
select tests.check(
  cron_availability_reminders('2031-06-16 09:00:00+00') = 0,
  'après la date limite : rien');
select tests.check(
  cron_availability_reminders('2031-05-20 09:00:00+00') = 0,
  'un mois avant : rien');

select tests.check(
  (select count(*) from notification_outbox where type = 'availability_reminder') = 0,
  'et la file est restée vide sur tous ces jours');

rollback to savepoint avant_jours_muets;

\echo ''
\echo '== 3. Qui a saisi ne reçoit rien (critère d''acceptation du ticket)'

savepoint avant_saisie;

-- Un seul créneau suffit. C'est la lettre du ticket : « un membre ayant saisi au
-- moins un créneau ne reçoit pas de rappel ».
insert into availabilities (station_id, user_id, date, slot, status, set_by) values
  (:caserne_a, 'aaaaaaaa-0000-4000-8000-000000000101', '2031-07-03', 'day', 'available',
   'aaaaaaaa-0000-4000-8000-000000000101');

-- Et une ligne `absent` compte aussi : le membre a répondu « pas moi », ce qui
-- est une réponse. Le relancer reviendrait à ne pas l'avoir écouté.
insert into availabilities (station_id, user_id, date, slot, status, set_by) values
  (:caserne_a, 'aaaaaaaa-0000-4000-8000-000000000102', '2031-07-20', 'night', 'absent',
   'aaaaaaaa-0000-4000-8000-000000000102');

-- Une saisie sur un autre mois ne dispense de rien : la question est « as-tu
-- saisi *ce* mois-là ».
insert into availabilities (station_id, user_id, date, slot, status, set_by) values
  (:caserne_a, 'aaaaaaaa-0000-4000-8000-000000000103', '2031-08-03', 'day', 'available',
   'aaaaaaaa-0000-4000-8000-000000000103');

select tests.check(
  cron_availability_reminders('2031-06-12 09:00:00+00') = 7,
  'sept rappels : les deux membres qui ont saisi juillet sont épargnés');

select tests.check(
  not exists (
    select 1 from notification_outbox
     where dedupe_key like '%:2031-07:j-3:aaaaaaaa-0000-4000-8000-000000000101'
        or dedupe_key like '%:2031-07:j-3:aaaaaaaa-0000-4000-8000-000000000102'),
  'ni celui qui s''est dit disponible, ni celui qui s''est dit absent');

select tests.check(
  exists (
    select 1 from notification_outbox
     where dedupe_key like '%:2031-07:j-3:aaaaaaaa-0000-4000-8000-000000000103'),
  'celui qui n''a saisi qu''août est relancé pour juillet');

rollback to savepoint avant_saisie;

\echo ''
\echo '== 4. Le fuseau de la caserne décide du jour'

savepoint avant_fuseaux;

-- Deux casernes, deux bouts du monde, la même date limite locale : le 15 juin
-- 2031 à 23:59:59 chez elles. Vingt-cinq heures séparent les deux instants.
update stations set timezone = 'Pacific/Midway'     where id = :caserne_a;   -- UTC-11
update stations set timezone = 'Pacific/Kiritimati' where id = :caserne_b;   -- UTC+14

update periods set deadline_at = make_timestamptz(2031, 6, 15, 23, 59, 59, 'Pacific/Midway')
  where id = :periode_id;

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('eeeeeeee-0000-4000-8000-000000000002', :caserne_b, 2031, 7, 'open',
   make_timestamptz(2031, 6, 15, 23, 59, 59, 'Pacific/Kiritimati'));

-- Le 12 juin 2031 à 09:00 UTC : il est encore le 11 juin à Midway (22:00), et
-- déjà le 12 juin à Kiritimati (23:00). Midway est donc à J-4, Kiritimati à J-3.
-- Un calcul en UTC aurait relancé Midway un jour trop tôt.
select tests.check(
  cron_availability_reminders('2031-06-12 09:00:00+00') = 9,
  'le 12 juin 09:00 UTC : Kiritimati (déjà le 12) est à J-3, Midway (encore le 11) non');

select tests.check(
  (select count(*) from notification_outbox
    where station_id = :caserne_b::uuid and type = 'availability_reminder') = 9
  and (select count(*) from notification_outbox
        where station_id = :caserne_a::uuid and type = 'availability_reminder') = 0,
  'et les neuf rappels sont bien ceux de Kiritimati');

-- Vingt-quatre heures plus tard, Midway est à son tour le 12 : son J-3 arrive,
-- celui de Kiritimati est passé. Chaque caserne a eu son jour, une seule fois.
select tests.check(
  cron_availability_reminders('2031-06-13 09:00:00+00') = 9,
  'le lendemain : c''est au tour de Midway, ni un jour trop tôt ni un jour trop tard');

select tests.check(
  (select count(*) from notification_outbox
    where station_id = :caserne_a::uuid and type = 'availability_reminder') = 9,
  'neuf rappels pour Midway, et toujours neuf pour Kiritimati');

select tests.check(
  (select count(*) from notification_outbox where type = 'availability_reminder') = 18,
  'dix-huit au total : aucune caserne n''a été servie deux fois');

rollback to savepoint avant_fuseaux;

\echo ''
\echo '== 5. Période verrouillée, caserne suspendue, membre inactif'

savepoint avant_exclusions;

-- Une période verrouillée en avance par l'admin : il a décidé que la saisie
-- était close, la tâche ne le contredit pas.
update periods set status = 'locked', locked_at = now() where id = :periode_id;

select tests.check(
  cron_availability_reminders('2031-06-12 09:00:00+00') = 0,
  'une période verrouillée ne relance personne');

update periods set status = 'open', locked_at = null where id = :periode_id;

-- Une caserne suspendue est en lecture seule : lui demander de saisir, c'est lui
-- promettre un mur.
update subscriptions set status = 'suspended' where station_id = :caserne_a;

select tests.check(
  not station_writable(:caserne_a), 'décor : la caserne A est bien suspendue');

select tests.check(
  cron_availability_reminders('2031-06-12 09:00:00+00') = 0,
  'une caserne suspendue ne relance personne : l''application y est en lecture seule');

update subscriptions set status = 'active' where station_id = :caserne_a;

-- Un membre désactivé ne saisit plus rien ; un invité n'a pas encore de compte
-- dans la caserne. Ni l'un ni l'autre n'a de raison d'être relancé.
update memberships set status = 'disabled'
  where station_id = :caserne_a and user_id = 'aaaaaaaa-0000-4000-8000-000000000107';
update memberships set status = 'invited'
  where station_id = :caserne_a and user_id = 'aaaaaaaa-0000-4000-8000-000000000108';

select tests.check(
  cron_availability_reminders('2031-06-12 09:00:00+00') = 7,
  'ni un membre désactivé ni un invité ne sont relancés');

rollback to savepoint avant_exclusions;

\echo ''
\echo '== 6. Deux casernes ne se volent pas l''échéance d''un membre partagé'

savepoint avant_partage;

-- docs/PRD.md § 6.1 : « un utilisateur peut appartenir à plusieurs casernes ».
-- Membre1 de la caserne A rejoint la caserne B, qui ouvre le même mois.
insert into memberships (station_id, user_id, role, status, display_name)
values (:caserne_b, 'aaaaaaaa-0000-4000-8000-000000000101', 'member', 'active', 'Marie L.');

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('eeeeeeee-0000-4000-8000-000000000003', :caserne_b, 2031, 7, 'open',
   make_timestamptz(2031, 6, 15, 23, 59, 59, 'Europe/Paris'));

select tests.check(
  cron_availability_reminders('2031-06-12 09:00:00+00') = 19,
  '9 rappels pour A + 10 pour B : le membre partagé est relancé des deux côtés');

select tests.check(
  (select count(*) from notification_outbox
    where dedupe_key like '%:2031-07:j-3:aaaaaaaa-0000-4000-8000-000000000101') = 2,
  'deux rappels pour lui, un par caserne : chacune parle de son propre mois');

rollback to savepoint avant_partage;

\echo ''
\echo '== 7. La tâche est planifiée, la fonction n''est pas un bouton'

select tests.check(
  (select count(*) from cron.job
    where jobname = 'availability_reminders'
      and command = 'select public.cron_availability_reminders();') = 1,
  'la tâche availability_reminders est planifiée, qualifiée et sans argument');

select tests.check(
  (select schedule from cron.job where jobname = 'availability_reminders') = '0 9 * * *',
  'tous les jours à 09:00 (docs/SCHEMA.md § 8)');

select tests.check(
  not has_function_privilege('authenticated',
    'public.cron_availability_reminders(timestamptz)', 'execute')
  and not has_function_privilege('anon',
    'public.cron_availability_reminders(timestamptz)', 'execute'),
  'la fonction n''est appelable ni par authenticated ni par anon');

-- Et la file qu'elle remplit reste invisible depuis l'application : ces lignes
-- portent les charges utiles de toutes les casernes à la fois.
select tests.check(
  cron_availability_reminders('2031-06-12 09:00:00+00') = 9,
  'neuf rappels en file, prêts à être lus par qui n''y a pas droit');

set local role authenticated;
set local request.jwt.claims to '{"sub": "aaaaaaaa-0000-4000-8000-000000000100", "role": "authenticated"}';

select tests.denied(
  $$select * from notification_outbox where type = 'availability_reminder'$$,
  'un admin ne lit pas les rappels mis en file pour ses membres');

reset role;

\echo ''
\echo '== 8. Le taux de saisie de l''écran Périodes (déjà là depuis 0013)'

-- Second critère d'acceptation du ticket. Rien n'est ajouté ici : la vue existe
-- et l'écran la consomme. Le test constate qu'elle répond juste sur le décor de
-- ce fichier, pour que sa disparition casse aussi ce ticket-ci.
insert into availabilities (station_id, user_id, date, slot, status, set_by) values
  (:caserne_a, 'aaaaaaaa-0000-4000-8000-000000000101', '2031-07-03', 'day', 'available',
   'aaaaaaaa-0000-4000-8000-000000000101');

select tests.check(
  (select active_members = 9 and members_with_availability = 1
     from v_period_completion where period_id = :periode_id::uuid),
  'v_period_completion : 1 membre sur 9 a saisi juillet 2031');

\echo ''
\echo 'availability_reminders_test : OK'

rollback;
