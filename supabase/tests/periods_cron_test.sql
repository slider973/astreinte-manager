-- Tests du cycle de vie des périodes (migration 0012, ticket 014).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié
-- ------------------
-- 1. `period_deadline_at` (0011, réutilisée telle quelle) tient debout sur un
--    mois court : un jour limite de 30 ne peut pas tomber le 30 février.
-- 2. `cron_create_periods` crée M+1 et M+2 pour chaque caserne, et une seconde
--    exécution ne crée rien — l'idempotence, pas la promesse de l'idempotence.
-- 3. Le mois de référence est calculé dans le fuseau de **chaque caserne** :
--    à 02:00 UTC le 1er du mois, il n'est pas le même jour partout.
-- 4. `cron_lock_periods` verrouille ce qui est échu, ne verrouille pas ce qui ne
--    l'est pas, et le fuseau de la caserne décide de l'instant exact.
-- 5. Une période rouverte dont la date limite a été repoussée n'est pas
--    reverrouillée par la tâche suivante ; et rouvrir sans repousser la date
--    limite est refusé plutôt qu'annulé une heure plus tard.
-- 6. La réouverture est tracée dans `audit_log` (règle 7 du produit).
-- 7. `create_period` : réservée aux admins de la caserne, idempotente, refuse un
--    mois écoulé.
-- 8. Saisie d'un admin pour un membre : `set_by` imposé à l'auteur réel (même
--    s'il tente d'écrire autre chose) et entrée d'audit ; saisie d'un membre
--    pour lui-même : aucune entrée.
-- 9. Les deux tâches sont planifiées, et leurs fonctions ne sont pas appelables
--    par un client.
--
-- Rien ici n'attend l'ordonnanceur : les deux fonctions sont appelées
-- directement avec un instant de référence. La CI (.github/workflows/ci.yml)
-- couvre donc toute la logique sans dépendre de pg_cron pour l'exécuter.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : le seed (caserne A = aaaaaaaa-…-001 « CIS Saint-Martin », admin
-- …100, membres …101+ ; caserne B = bbbbbbbb-…-001, admin …100), plus les
-- périodes créées ici, toutes dans des années qui ne croisent jamais le seed.

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

-- L'écriture doit être refusée par une contrainte ou un déclencheur.
create function tests.echoue(p_sql text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — accepté alors que ça devait être refusé', p_label;
exception
  when others then
    if sqlerrm like 'ECHEC%' then raise; end if;
    raise notice '  ok   % (refusé : %)', p_label, left(sqlerrm, 60);
end $$;

-- Même chose, mais le motif du refus est vérifié : une erreur de syntaxe ne doit
-- pas passer pour une règle métier respectée.
create function tests.echoue_avec(p_sql text, p_motif text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — accepté alors que ça devait être refusé', p_label;
exception
  when others then
    if sqlerrm like 'ECHEC%' then raise; end if;
    if position(p_motif in sqlerrm) = 0 then
      raise exception 'ECHEC : % — refusé, mais pour « % » au lieu de « % »',
        p_label, left(sqlerrm, 80), p_motif;
    end if;
    raise notice '  ok   % (refusé : %)', p_label, p_motif;
end $$;

-- L'écriture doit passer et toucher au moins une ligne.
create function tests.allowed(p_sql text, p_label text) returns void
language plpgsql as $$
declare
  n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n < 1 then
    raise exception 'ECHEC : % — écriture autorisée attendue, 0 ligne touchée', p_label;
  end if;
  raise notice '  ok   % (% ligne(s))', p_label, n;
end $$;

-- L'écriture doit être refusée par la RLS : erreur, ou 0 ligne (une politique
-- `using` qui ne matche pas filtre silencieusement).
create function tests.denied(p_sql text, p_label text) returns void
language plpgsql as $$
declare
  n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n > 0 then
    raise exception 'ECHEC : % — % ligne(s) écrite(s) alors que ça devait être refusé', p_label, n;
  end if;
  raise notice '  ok   % (0 ligne, filtré par USING)', p_label;
exception
  when insufficient_privilege then
    raise notice '  ok   % (refusé : %)', p_label, sqlerrm;
  when raise_exception then
    if sqlerrm like 'ECHEC%' then raise; end if;
    raise notice '  ok   % (refusé par trigger : %)', p_label, sqlerrm;
end $$;

grant usage on schema tests to authenticated, anon;
grant execute on all functions in schema tests to authenticated, anon;

-- ===========================================================================
-- 1. period_deadline_at : la règle posée au ticket 010, réutilisée telle quelle
-- ===========================================================================
\echo ''
\echo '== 1. Date limite (period_deadline_at, migration 0011)'

select tests.check(
  period_deadline_at(2029, 7, 15, 'Europe/Paris')
    = make_timestamptz(2029, 6, 15, 23, 59, 59, 'Europe/Paris'),
  'juillet 2029 ferme le 15 juin à 23:59:59, heure de Paris');

select tests.check(
  period_deadline_at(2029, 1, 15, 'Europe/Paris')
    = make_timestamptz(2028, 12, 15, 23, 59, 59, 'Europe/Paris'),
  'janvier ferme en décembre de l''année précédente');

-- La contrainte `stations_settings_valide` borne le jour limite à 28 (0011),
-- mais une caserne créée avant cette contrainte peut porter 30 ou 31 : la
-- fonction doit retomber sur le dernier jour du mois court plutôt que d''échouer.
select tests.check(
  period_deadline_at(2029, 3, 30, 'Europe/Paris')
    = make_timestamptz(2029, 2, 28, 23, 59, 59, 'Europe/Paris'),
  'jour limite 30 pour mars 2029 : ramené au 28 février');

select tests.check(
  period_deadline_at(2028, 3, 31, 'Europe/Paris')
    = make_timestamptz(2028, 2, 29, 23, 59, 59, 'Europe/Paris'),
  'jour limite 31 pour mars 2028 : ramené au 29 février (année bissextile)');

select tests.check(
  period_deadline_at(2029, 7, 15, 'Pacific/Kiritimati')
    <> period_deadline_at(2029, 7, 15, 'Pacific/Midway'),
  'le même jour limite n''est pas le même instant selon le fuseau');

-- ===========================================================================
-- 2. cron_create_periods : M+1 et M+2, et pas deux fois
-- ===========================================================================
\echo ''
\echo '== 2. Création des périodes (cron_create_periods)'

savepoint avant_creation;

select tests.check(
  cron_create_periods('2029-06-10 12:00:00+00'::timestamptz) = 4,
  'première exécution : 2 périodes par caserne, 2 casernes');

select tests.check(
  (select count(*) from periods
    where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
      and year = 2029 and month in (7, 8)) = 2,
  'la caserne A a juillet et août 2029');

select tests.check(
  (select count(*) from periods
    where station_id = 'bbbbbbbb-0000-4000-8000-000000000001'
      and year = 2029 and month in (7, 8)) = 2,
  'la caserne B aussi');

select tests.check(
  (select status from periods
    where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
      and year = 2029 and month = 7) = 'open',
  'une période naît ouverte');

select tests.check(
  (select deadline_at from periods
    where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
      and year = 2029 and month = 7)
    = make_timestamptz(2029, 6, 15, 23, 59, 59, 'Europe/Paris'),
  'sa date limite vient de period_deadline_at, pas d''un second calcul');

-- Idempotence : c'est le point de vigilance du ticket. L'ordonnanceur peut
-- rejouer une tâche (redémarrage, reprise), et un admin peut avoir créé le mois
-- à la main la veille.
select tests.check(
  cron_create_periods('2029-06-10 12:00:00+00'::timestamptz) = 0,
  'seconde exécution : rien de créé');

select tests.check(
  (select count(*) from periods
    where year = 2029 and month in (7, 8)) = 4,
  'et toujours quatre périodes, pas huit');

-- Une période rouverte à dessein ne doit pas être ramenée à son état d'origine
-- par la tâche de création.
update periods
   set status = 'locked', deadline_at = '2029-06-01 00:00:00+00'
 where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
   and year = 2029 and month = 7;

select tests.check(
  cron_create_periods('2029-06-10 12:00:00+00'::timestamptz) = 0,
  'une période existante n''est pas recréée');

select tests.check(
  (select status from periods
    where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
      and year = 2029 and month = 7) = 'locked',
  'ni son statut réécrit');

select tests.check(
  (select deadline_at from periods
    where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
      and year = 2029 and month = 7) = '2029-06-01 00:00:00+00'::timestamptz,
  'ni sa date limite');

rollback to savepoint avant_creation;

-- ===========================================================================
-- 3. Le mois de référence se juge dans le fuseau de la caserne
-- ===========================================================================
\echo ''
\echo '== 3. Création : fuseau de la caserne'

savepoint avant_fuseaux;

-- L'ordonnanceur tire à 02:00 UTC le 1er du mois. À cet instant précis, il est
-- encore le 28 février à Midway (UTC-11) et déjà le 1er mars à Kiritimati
-- (UTC+14) : les deux casernes n'attendent pas les mêmes mois.
update stations set timezone = 'Pacific/Midway'
  where id = 'aaaaaaaa-0000-4000-8000-000000000001';
update stations set timezone = 'Pacific/Kiritimati'
  where id = 'bbbbbbbb-0000-4000-8000-000000000001';

select tests.check(
  cron_create_periods('2029-03-01 02:00:00+00'::timestamptz) = 4,
  'quatre périodes créées le 1er mars 2029 à 02:00 UTC');

select tests.check(
  (select array_agg(month order by month) from periods
    where station_id = 'aaaaaaaa-0000-4000-8000-000000000001' and year = 2029)
    = array[3, 4],
  'Midway (UTC-11), encore en février : mars et avril');

select tests.check(
  (select array_agg(month order by month) from periods
    where station_id = 'bbbbbbbb-0000-4000-8000-000000000001' and year = 2029)
    = array[4, 5],
  'Kiritimati (UTC+14), déjà en mars : avril et mai');

select tests.check(
  (select deadline_at from periods
    where station_id = 'bbbbbbbb-0000-4000-8000-000000000001'
      and year = 2029 and month = 4)
    = make_timestamptz(2029, 3, 15, 23, 59, 59, 'Pacific/Kiritimati'),
  'et la date limite est posée dans le fuseau de la caserne');

rollback to savepoint avant_fuseaux;

-- ===========================================================================
-- 4. cron_lock_periods : ce qui est échu, et rien d'autre
-- ===========================================================================
\echo ''
\echo '== 4. Verrouillage (cron_lock_periods)'

savepoint avant_verrouillage;

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('cccccccc-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001',
   2020, 5, 'open', make_timestamptz(2020, 4, 15, 23, 59, 59, 'Europe/Paris')),
  ('cccccccc-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001',
   2020, 6, 'open', make_timestamptz(2020, 5, 15, 23, 59, 59, 'Europe/Paris'));

select tests.check(
  cron_lock_periods('2020-05-01 00:00:00+00'::timestamptz) = 1,
  'une seule période échue au 1er mai 2020');

select tests.check(
  (select status from periods where id = 'cccccccc-0000-4000-8000-000000000001') = 'locked',
  'mai 2020, dont la date limite est passée, est verrouillée');

select tests.check(
  (select locked_at from periods where id = 'cccccccc-0000-4000-8000-000000000001')
    = '2020-05-01 00:00:00+00'::timestamptz,
  'locked_at porte l''instant du verrouillage');

select tests.check(
  (select status from periods where id = 'cccccccc-0000-4000-8000-000000000002') = 'open',
  'juin 2020, encore en saisie, reste ouverte');

-- Idempotence : la tâche tourne toutes les heures. Une période déjà verrouillée
-- ne doit pas voir son `locked_at` réécrit à chaque passage — ce serait effacer
-- la date à laquelle la saisie s'est réellement fermée.
select tests.check(
  cron_lock_periods('2020-05-02 00:00:00+00'::timestamptz) = 0,
  'seconde exécution une heure plus tard : rien à faire');

select tests.check(
  (select locked_at from periods where id = 'cccccccc-0000-4000-8000-000000000001')
    = '2020-05-01 00:00:00+00'::timestamptz,
  'et locked_at n''a pas bougé');

\echo ''
\echo '-- 4 bis. Le fuseau de la caserne décide de l''instant'

-- Juin 2020 arrive à échéance à son tour : on solde l'état précédent pour que
-- le comptage qui suit ne porte que sur les deux périodes du test de fuseau.
select cron_lock_periods('2020-06-01 00:00:00+00'::timestamptz);

-- Même mois, même jour limite, deux fuseaux : à 2020-06-16 00:00 UTC, la
-- caserne à UTC+14 a fermé depuis quatorze heures, celle à UTC-11 a encore onze
-- heures devant elle.
insert into periods (id, station_id, year, month, status, deadline_at) values
  ('cccccccc-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001',
   2020, 7, 'open', period_deadline_at(2020, 7, 15, 'Pacific/Kiritimati')),
  ('cccccccc-0000-4000-8000-000000000004', 'bbbbbbbb-0000-4000-8000-000000000001',
   2020, 7, 'open', period_deadline_at(2020, 7, 15, 'Pacific/Midway'));

select tests.check(
  cron_lock_periods('2020-06-16 00:00:00+00'::timestamptz) = 1,
  'une seule des deux est échue à cet instant');

select tests.check(
  (select status from periods where id = 'cccccccc-0000-4000-8000-000000000003') = 'locked',
  'la caserne à UTC+14 a fermé');

select tests.check(
  (select status from periods where id = 'cccccccc-0000-4000-8000-000000000004') = 'open',
  'celle à UTC-11 est encore ouverte');

-- =========================================================================
-- 5. Réouverture par un administrateur
-- =========================================================================
\echo ''
\echo '== 5. Réouverture d''une période verrouillée'

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

-- Rouvrir sans repousser la date limite : refusé tout de suite, plutôt
-- qu'accepté puis défait par la tâche horaire.
select tests.echoue_avec(
  $$update periods set status = 'open'
      where id = 'cccccccc-0000-4000-8000-000000000001'$$,
  'period_reopen_deadline_passed',
  'rouvrir sans repousser la date limite');

select tests.allowed(
  $$update periods
       set status = 'open', deadline_at = now() + interval '7 days'
     where id = 'cccccccc-0000-4000-8000-000000000001'$$,
  'un admin rouvre en repoussant la date limite d''une semaine');

reset role;

select tests.check(
  (select locked_at from periods where id = 'cccccccc-0000-4000-8000-000000000001') is null,
  'locked_at est effacé par la réouverture');

select tests.check(
  (select count(*) from audit_log
    where action = 'period.reopen'
      and entity_id = 'cccccccc-0000-4000-8000-000000000001'
      and actor_id = 'aaaaaaaa-0000-4000-8000-000000000100'
      and station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 1,
  'la réouverture est tracée dans audit_log (règle 7)');

select tests.check(
  (select data ->> 'deadline_avant' is not null and data ->> 'deadline_apres' is not null
     from audit_log
    where action = 'period.reopen'
      and entity_id = 'cccccccc-0000-4000-8000-000000000001'),
  'la trace dit d''où et vers quand la date limite a bougé');

-- Le point de vigilance du ticket : la tâche suivante ne doit pas défaire la
-- décision de l'admin.
select tests.check(
  (select status from periods where id = 'cccccccc-0000-4000-8000-000000000001') = 'open',
  'avant la tâche : la période est ouverte');

select cron_lock_periods();

select tests.check(
  (select status from periods where id = 'cccccccc-0000-4000-8000-000000000001') = 'open',
  'après la tâche horaire : toujours ouverte, la réouverture tient');

-- Un membre ordinaire ne rouvre rien (politique periods_update_admin, 0007).
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

select tests.denied(
  $$update periods set status = 'open', deadline_at = now() + interval '7 days'
      where id = 'cccccccc-0000-4000-8000-000000000003'$$,
  'un membre ne rouvre pas une période');

reset role;

-- L'admin de la caserne B non plus, sur une période de la caserne A.
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.denied(
  $$update periods set status = 'open', deadline_at = now() + interval '7 days'
      where id = 'cccccccc-0000-4000-8000-000000000003'$$,
  'l''admin de la caserne B ne rouvre pas une période de la caserne A');

select tests.check(
  (select count(*) from periods
    where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 0,
  'et il ne voit même pas les périodes de la caserne A');

reset role;

-- Une période est un mois : elle ne se déplace ni de caserne ni de date.
select tests.echoue_avec(
  $$update periods set month = 8 where id = 'cccccccc-0000-4000-8000-000000000003'$$,
  'period_key_immutable',
  'changer le mois d''une période existante');

select tests.echoue_avec(
  $$update periods set station_id = 'bbbbbbbb-0000-4000-8000-000000000001'
      where id = 'cccccccc-0000-4000-8000-000000000003'$$,
  'period_key_immutable',
  'déplacer une période vers une autre caserne');

-- Verrouiller à la main : l'action « verrouiller maintenant » de l'écran admin
-- est un simple update de statut, `locked_at` suit tout seul.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.allowed(
  $$update periods set status = 'locked'
      where id = 'cccccccc-0000-4000-8000-000000000001'$$,
  'un admin verrouille maintenant, sans attendre la date limite');

reset role;

select tests.check(
  (select locked_at from periods where id = 'cccccccc-0000-4000-8000-000000000001')
    is not null,
  'locked_at est posé par le déclencheur, pas par le client');

rollback to savepoint avant_verrouillage;

-- ===========================================================================
-- 6. create_period : « créer un mois » depuis l'écran d'administration
-- ===========================================================================
\echo ''
\echo '== 6. create_period'

savepoint avant_create_period;

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.check(
  (select status from create_period(
     'aaaaaaaa-0000-4000-8000-000000000001', 2031, 3)) = 'open',
  'un admin ouvre mars 2031 à la saisie');

select tests.check(
  (select deadline_at from create_period(
     'aaaaaaaa-0000-4000-8000-000000000001', 2031, 3))
    = make_timestamptz(2031, 2, 15, 23, 59, 59, 'Europe/Paris'),
  'la date limite est le 15 février 2031, heure de Paris');

select tests.check(
  (select count(*) from periods
    where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
      and year = 2031 and month = 3) = 1,
  'deux appels, une seule période : la fonction est idempotente');

select tests.echoue_avec(
  $$select create_period('aaaaaaaa-0000-4000-8000-000000000001', 2020, 1)$$,
  'period_month_in_past',
  'ouvrir un mois déjà écoulé');

select tests.echoue_avec(
  $$select create_period('aaaaaaaa-0000-4000-8000-000000000001', 2031, 13)$$,
  'period_month_invalid',
  'ouvrir un treizième mois');

select tests.echoue_avec(
  $$select create_period('bbbbbbbb-0000-4000-8000-000000000001', 2031, 3)$$,
  'forbidden',
  'l''admin de la caserne A n''ouvre pas un mois chez B');

reset role;

-- Un membre ordinaire n'ouvre pas de mois, même chez lui.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

select tests.echoue_avec(
  $$select create_period('aaaaaaaa-0000-4000-8000-000000000001', 2031, 4)$$,
  'forbidden',
  'un membre n''ouvre pas de mois');

reset role;

-- Caserne suspendue : l'application passe en lecture seule (docs/SCHEMA.md § 4).
update subscriptions set status = 'suspended'
  where station_id = 'aaaaaaaa-0000-4000-8000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.echoue_avec(
  $$select create_period('aaaaaaaa-0000-4000-8000-000000000001', 2031, 5)$$,
  'station_suspended',
  'une caserne suspendue n''ouvre pas de mois');

reset role;

rollback to savepoint avant_create_period;

-- ===========================================================================
-- 7. Saisie d'un administrateur pour un membre
-- ===========================================================================
\echo ''
\echo '== 7. set_by et audit de la saisie pour autrui'

savepoint avant_saisie;

-- Une période ouverte et une période verrouillée, loin du seed.
insert into periods (id, station_id, year, month, status, deadline_at, locked_at) values
  ('dddddddd-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001',
   2032, 4, 'open', make_timestamptz(2032, 3, 15, 23, 59, 59, 'Europe/Paris'), null),
  ('dddddddd-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001',
   2032, 5, 'locked', make_timestamptz(2032, 4, 15, 23, 59, 59, 'Europe/Paris'),
   make_timestamptz(2032, 4, 15, 23, 59, 59, 'Europe/Paris'));

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

-- L'admin écrit pour membre1 et tente de signer avec l'identifiant du membre :
-- c'est exactement la manœuvre que la colonne doit rendre impossible.
select tests.allowed(
  $$insert into availabilities (station_id, user_id, date, slot, status, set_by)
    values ('aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000101',
            '2032-04-10', 'day', 'available',
            'aaaaaaaa-0000-4000-8000-000000000101')$$,
  'un admin saisit pour membre1 sur une période ouverte');

reset role;

select tests.check(
  (select set_by from availabilities
    where user_id = 'aaaaaaaa-0000-4000-8000-000000000101'
      and date = '2032-04-10' and slot = 'day')
    = 'aaaaaaaa-0000-4000-8000-000000000100',
  'set_by porte l''admin, pas ce que l''admin a écrit');

select tests.check(
  (select count(*) from audit_log
    where action = 'availability.set_for_member'
      and station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
      and actor_id = 'aaaaaaaa-0000-4000-8000-000000000100'
      and data ->> 'user_id' = 'aaaaaaaa-0000-4000-8000-000000000101'
      and data ->> 'date' = '2032-04-10') = 1,
  'la saisie pour autrui est journalisée');

-- Période verrouillée : l'admin écrit toujours (docs/WORKFLOWS.md § 1).
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.allowed(
  $$insert into availabilities (station_id, user_id, date, slot, status)
    values ('aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000101',
            '2032-05-10', 'night', 'available')$$,
  'un admin saisit aussi sur une période verrouillée');

reset role;

-- Le membre, lui, est arrêté par la RLS : c'est le second critère du ticket.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

select tests.denied(
  $$insert into availabilities (station_id, user_id, date, slot, status)
    values ('aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000101',
            '2032-05-11', 'day', 'available')$$,
  'un membre n''écrit pas sur une période verrouillée');

-- Sur la période ouverte, il écrit pour lui-même, et tente de faire porter la
-- saisie par l'admin.
select tests.allowed(
  $$insert into availabilities (station_id, user_id, date, slot, status, set_by)
    values ('aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000101',
            '2032-04-11', 'night', 'available',
            'aaaaaaaa-0000-4000-8000-000000000100')$$,
  'un membre saisit sa propre disponibilité');

reset role;

select tests.check(
  (select set_by from availabilities
    where user_id = 'aaaaaaaa-0000-4000-8000-000000000101'
      and date = '2032-04-11' and slot = 'night')
    = 'aaaaaaaa-0000-4000-8000-000000000101',
  'set_by porte le membre : personne ne signe à la place d''un autre');

select tests.check(
  (select count(*) from audit_log
    where action = 'availability.set_for_member'
      and data ->> 'date' = '2032-04-11') = 0,
  'une saisie ordinaire ne remplit pas le journal d''audit');

-- Décocher pour un membre, c'est supprimer la ligne : ça se trace aussi.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.allowed(
  $$delete from availabilities
     where user_id = 'aaaaaaaa-0000-4000-8000-000000000101'
       and date = '2032-04-11' and slot = 'night'$$,
  'un admin efface la saisie d''un membre');

reset role;

select tests.check(
  (select count(*) from audit_log
    where action = 'availability.cleared_for_member'
      and actor_id = 'aaaaaaaa-0000-4000-8000-000000000100'
      and data ->> 'date' = '2032-04-11') = 1,
  'l''effacement pour autrui est journalisé');

-- Étanchéité : l'admin de B ne saisit rien pour un membre de A.
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-4000-8000-000000000100","role":"authenticated"}';

select tests.denied(
  $$insert into availabilities (station_id, user_id, date, slot, status)
    values ('aaaaaaaa-0000-4000-8000-000000000001',
            'aaaaaaaa-0000-4000-8000-000000000101',
            '2032-04-12', 'day', 'available')$$,
  'l''admin de la caserne B ne saisit pas pour un membre de la caserne A');

select tests.check(
  (select count(*) from availabilities
    where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 0,
  'et il ne lit aucune disponibilité de la caserne A');

reset role;

rollback to savepoint avant_saisie;

-- ===========================================================================
-- 8. Les tâches planifiées, et leur inaccessibilité depuis un client
-- ===========================================================================
\echo ''
\echo '== 8. pg_cron et droits d''exécution'

select tests.check(
  (select count(*) from cron.job
    where jobname = 'create_periods' and schedule = '0 2 1 * *' and active) = 1,
  'la tâche create_periods est planifiée le 1er du mois à 02:00');

select tests.check(
  (select count(*) from cron.job
    where jobname = 'lock_periods' and schedule = '0 * * * *' and active) = 1,
  'la tâche lock_periods est planifiée toutes les heures');

select tests.check(
  (select count(*) from cron.job
    where jobname in ('create_periods', 'lock_periods')) = 2,
  'et elles ne sont pas en double');

select tests.check(
  (select count(*) from cron.job
    where jobname in ('create_periods', 'lock_periods')
      and command not like 'select public.%') = 0,
  'les commandes sont qualifiées par le schéma : rien à détourner par search_path');

-- Une tâche tourne avec des droits élevés : sa fonction ne doit pas être un
-- bouton accessible au premier venu.
select tests.check(
  not has_function_privilege('authenticated', 'public.cron_create_periods(timestamptz)', 'execute')
  and not has_function_privilege('anon', 'public.cron_create_periods(timestamptz)', 'execute'),
  'cron_create_periods n''est appelable ni par authenticated ni par anon');

select tests.check(
  not has_function_privilege('authenticated', 'public.cron_lock_periods(timestamptz)', 'execute')
  and not has_function_privilege('anon', 'public.cron_lock_periods(timestamptz)', 'execute'),
  'cron_lock_periods non plus');

select tests.check(
  has_function_privilege('authenticated', 'public.create_period(uuid, integer, integer)', 'execute')
  and not has_function_privilege('anon', 'public.create_period(uuid, integer, integer)', 'execute'),
  'create_period est ouverte à authenticated, fermée à anon');

-- `search_path` figé sur toutes les fonctions posées ici (docs/SCHEMA.md § 3).
select tests.check(
  (select count(*) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'cron_create_periods', 'cron_lock_periods', 'create_period',
        'periods_guard_transition', 'periods_audit_reouverture',
        'availabilities_trace_auteur', 'availabilities_audit_saisie_admin')
      and not coalesce(p.proconfig, '{}') @> array['search_path=public, pg_temp']) = 0,
  'les sept fonctions figent search_path = public, pg_temp');

\echo ''
\echo 'periods_cron_test : OK'

rollback;
