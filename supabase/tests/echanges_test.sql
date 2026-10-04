-- Tests des échanges et cessions d'astreintes (migration 0041, ticket 073).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
--  1. Les deux réglages facultatifs de `stations.settings` : un vrai booléen,
--     une échéance de 1 à 168 heures.
--  2. Chaque refus de `request_exchange` : garde d'un autre, garde non acceptée,
--     planning non publié, trop tard, destinataire soi-même / inconnu /
--     désactivé / d'une autre caserne, échange sans destinataire, garde rendue
--     étrangère, déjà sur le créneau, plafonds d'astreintes et de weekends,
--     une seule demande ouverte par attribution (cédée comme rendue).
--  3. Une cession à un collègue, validée par l'administrateur : statuts,
--     `replaced_by`, attribution `accepted` du repreneur, journal, et
--     notifications à qui de droit — et à personne d'autre.
--  4. Un échange est **tout ou rien** : une condition qui ne tient plus sur le
--     second mouvement n'en laisse passer aucun ; puis un échange qui aboutit.
--  5. La demande « à la caserne » : seuls les disponibles la reçoivent et la
--     voient ; le premier qui accepte la prend ; elle ne se décline pas.
--  6. La validation automatique : seulement si le réglage est actif **et** si
--     le remplaçant avait déclaré une disponibilité ; sinon, l'administrateur.
--  7. L'expiration : la tâche, son idempotence, la fenêtre horaire locale, et
--     les fonctions qui refusent une demande échue même si la tâche est en
--     retard.
--  8. La suspension : rien ne se crée ni ne se valide ; une validation passe
--     `failed` avec son motif ; une clôture reste possible.
--  9. Annuler et décliner : qui le peut, qui est prévenu.
-- 10. Une garde retirée par l'administrateur (réattribution, annulation) fait
--     échouer la demande dans la même transaction.
-- 11. Le cloisonnement : rien d'une autre caserne, rien pour qui n'est pas
--     concerné, aucune écriture directe.
-- 12. `exchangeable_shifts_of` : les gardes de B que A peut demander, et rien
--     d'autre.
-- 13. La machine à états, les droits d'exécution et la tâche planifiée.
-- 14. « Pas pris ailleurs » (ticket 072) : un repreneur ou un demandeur
--     proposé ou accepté sur un créneau qui chevauche dans une autre caserne
--     est refusé à la demande, à l'accord et à la validation.
--
-- Les courses à deux sessions réelles (deux repreneurs en même temps ; une
-- validation pendant une réattribution) sont dans scripts/test_concurrence.sh.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
-- Fixtures sur mars 2029, que ni le seed ni les autres fichiers ne touchent.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_ech;

create function tests_ech.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

create function tests_ech.egal(p_obtenu anyelement, p_attendu anyelement, p_label text) returns void
language plpgsql as $$
begin
  if p_obtenu is distinct from p_attendu then
    raise exception 'ECHEC : % — obtenu [%], attendu [%]', p_label, p_obtenu, p_attendu;
  end if;
  raise notice '  ok   % = %', p_label, coalesce(p_obtenu::text, 'NULL');
end $$;

create function tests_ech.refuse(p_sql text, p_erreur text, p_label text) returns void
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

create function tests_ech.code(p_resultat jsonb, p_code text, p_label text) returns void
language plpgsql as $$
begin
  if (p_resultat ->> 'ok')::boolean is not false then
    raise exception 'ECHEC : % — la fonction a répondu ok (%), refus [%] attendu',
      p_label, p_resultat, p_code;
  end if;
  if p_resultat ->> 'code' is distinct from p_code then
    raise exception 'ECHEC : % — code [%] au lieu de [%] (%)',
      p_label, p_resultat ->> 'code', p_code, p_resultat;
  end if;
  raise notice '  ok   % (%)', p_label, p_code;
end $$;

create function tests_ech.ok(p_resultat jsonb, p_label text) returns jsonb
language plpgsql as $$
begin
  if (p_resultat ->> 'ok')::boolean is not true then
    raise exception 'ECHEC : % — %', p_label, p_resultat;
  end if;
  raise notice '  ok   %', p_label;
  return p_resultat;
end $$;

-- L'identité d'un appel : les fonctions lisent `auth.uid()`, donc les claims.
create function tests_ech.qui(p_user uuid) returns void
language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_user, 'role', 'authenticated')::text,
                    true);
$$;

-- Les destinataires d'une demande en file, triés, en texte : '{uuid,uuid}'.
create function tests_ech.dest(p_type text, p_station uuid default '07300000-0000-4000-8000-000000000001')
returns text
language sql security definer set search_path = public, pg_temp as $$
  select coalesce(array_agg(r ->> 'user_id' order by r ->> 'user_id')::text, '{}')
    from notification_outbox o, jsonb_array_elements(o.recipients) r
   where o.station_id = p_station and o.type::text = p_type;
$$;

create function tests_ech.nb(p_type text, p_station uuid default '07300000-0000-4000-8000-000000000001')
returns integer
language sql security definer set search_path = public, pg_temp as $$
  select count(*)::int from notification_outbox o
   where o.station_id = p_station and o.type::text = p_type;
$$;

grant usage on schema tests_ech to authenticated, anon;
grant execute on all functions in schema tests_ech to authenticated, anon;

-- `notify_post` sans réseau — même substitution que les autres fichiers.
create or replace function notify_post(p_outbox uuid) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update notification_outbox
     set attempts = attempts + 1, locked_until = now() + interval '2 minutes'
   where id = p_outbox and status = 'pending';
  return found;
end $$;

\echo ''
\echo '=== Échanges d''astreintes (0041) ==='

-- ===========================================================================
-- Fixtures
-- ===========================================================================
-- E « CIS Échanges » : Nadia admin, Bruno (A), Chloé (B), Damien (C),
-- Eve désactivée, Farid (F).  V « CIS Voisine 7 » : Gaëlle admin, Hugo membre.
\set E    '''07300000-0000-4000-8000-000000000001'''
\set V    '''07300000-0000-4000-8000-000000000002'''
\set ADM  '''07300000-0000-4000-8000-000000000100'''
\set A    '''07300000-0000-4000-8000-000000000101'''
\set B    '''07300000-0000-4000-8000-000000000102'''
\set C    '''07300000-0000-4000-8000-000000000103'''
\set D    '''07300000-0000-4000-8000-000000000104'''
\set F    '''07300000-0000-4000-8000-000000000105'''
\set VADM '''07300000-0000-4000-8000-000000000900'''
\set VM   '''07300000-0000-4000-8000-000000000901'''
\set S1   '''07300000-0000-4000-8000-000000000401'''
\set S2   '''07300000-0000-4000-8000-000000000402'''
\set S3   '''07300000-0000-4000-8000-000000000403'''
\set S4   '''07300000-0000-4000-8000-000000000404'''
\set S5   '''07300000-0000-4000-8000-000000000405'''
\set S6   '''07300000-0000-4000-8000-000000000406'''
\set S7   '''07300000-0000-4000-8000-000000000407'''
\set A1   '''07300000-0000-4000-8000-000000000501'''
\set A2   '''07300000-0000-4000-8000-000000000502'''
\set A3   '''07300000-0000-4000-8000-000000000503'''
\set A4   '''07300000-0000-4000-8000-000000000504'''
\set A5   '''07300000-0000-4000-8000-000000000505'''
\set A6   '''07300000-0000-4000-8000-000000000506'''
\set A7   '''07300000-0000-4000-8000-000000000507'''
\set PL   '''07300000-0000-4000-8000-000000000301'''

insert into stations (id, name, slug, timezone, settings) values
  (:E, 'CIS Échanges', 'cis-echanges', 'Europe/Paris',
   '{"day_start": "07:00", "day_end": "19:00",
     "required_day": 1, "required_night": 1,
     "availability_deadline_day": 15,
     "response_reminder_hours": 24, "response_email_hours": 48,
     "late_report_hours": 72}'::jsonb),
  (:V, 'CIS Voisine 7', 'cis-voisine-7', 'Europe/Paris',
   '{"day_start": "07:00", "day_end": "19:00",
     "required_day": 1, "required_night": 1,
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
  jsonb_build_object('first_name', u.prenom, 'last_name', u.nom),
  now(), now(), '', '', '', '', ''
from (values
  (:ADM::uuid,  'nadia@echanges.test',  'Nadia',  'Aloui'),
  (:A::uuid,    'bruno@echanges.test',  'Bruno',  'Bertin'),
  (:B::uuid,    'chloe@echanges.test',  'Chloé',  'Colin'),
  (:C::uuid,    'damien@echanges.test', 'Damien', 'Denis'),
  (:D::uuid,    'eve@echanges.test',    'Eve',    'Evrard'),
  (:F::uuid,    'farid@echanges.test',  'Farid',  'Fabre'),
  (:VADM::uuid, 'gaelle@voisine7.test', 'Gaëlle', 'Garnier'),
  (:VM::uuid,   'hugo@voisine7.test',   'Hugo',   'Henry')
) as u(id, email, prenom, nom);

insert into memberships (station_id, user_id, role, status, display_name) values
  (:E, :ADM,  'admin',  'active',   'Nadia A.'),
  (:E, :A,    'member', 'active',   'Bruno B.'),
  (:E, :B,    'member', 'active',   'Chloé C.'),
  (:E, :C,    'member', 'active',   'Damien D.'),
  (:E, :D,    'member', 'disabled', 'Eve E.'),
  (:E, :F,    'member', 'active',   'Farid F.'),
  (:V, :VADM, 'admin',  'active',   'Gaëlle G.'),
  (:V, :VM,   'member', 'active',   'Hugo H.');

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('07300000-0000-4000-8000-000000000201', :E, 2029, 3, 'locked', '2029-02-15 23:59:59+01'),
  ('07300000-0000-4000-8000-000000000202', :V, 2029, 3, 'locked', '2029-02-15 23:59:59+01'),
  ('07300000-0000-4000-8000-000000000203', :E,
   extract(year from current_date)::int, extract(month from current_date)::int,
   'locked', now() - interval '20 days');

insert into schedules (id, station_id, period_id, created_by) values
  (:PL, :E, '07300000-0000-4000-8000-000000000201', :ADM),
  ('07300000-0000-4000-8000-000000000302', :V, '07300000-0000-4000-8000-000000000202', :VADM),
  ('07300000-0000-4000-8000-000000000303', :E, '07300000-0000-4000-8000-000000000203', :ADM);

-- 1er mars 2029 est un jeudi : le 10 est un samedi.
insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  (:S1, :E, :PL, '2029-03-05', 'day',   1),
  (:S2, :E, :PL, '2029-03-05', 'night', 1),
  (:S3, :E, :PL, '2029-03-06', 'day',   1),
  (:S4, :E, :PL, '2029-03-10', 'day',   1),
  (:S5, :E, :PL, '2029-03-12', 'day',   1),
  (:S6, :V, '07300000-0000-4000-8000-000000000302', '2029-03-05', 'day', 1),
  (:S7, :E, '07300000-0000-4000-8000-000000000303', current_date, 'day', 1);

update schedules set status = 'published'
 where id in (:PL, '07300000-0000-4000-8000-000000000302', '07300000-0000-4000-8000-000000000303');

-- Toutes acceptées : A tient le 5 de jour, B le 5 de nuit et le samedi 10,
-- C le 6, F le 12. Hugo, dans la voisine, le 5 de jour.
insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, responded_at, created_by) values
  (:A1, :E, :S1, :A,  'accepted', now(), now(), :ADM),
  (:A2, :E, :S2, :B,  'accepted', now(), now(), :ADM),
  (:A3, :E, :S3, :C,  'accepted', now(), now(), :ADM),
  (:A4, :E, :S4, :B,  'accepted', now(), now(), :ADM),
  (:A5, :E, :S5, :F,  'accepted', now(), now(), :ADM),
  (:A6, :V, :S6, :VM, 'accepted', now(), now(), :VADM),
  (:A7, :E, :S7, :A,  'accepted', now(), now(), :ADM);

-- Disponibilités du 5 mars de jour : Damien et Farid libres, Chloé absente,
-- Eve (désactivée) libre. Bruno libre le 5 de nuit (pour l'échange auto).
insert into availabilities (station_id, user_id, date, slot, status, set_by) values
  (:E, :C, '2029-03-05', 'day',   'available', :C),
  (:E, :F, '2029-03-05', 'day',   'available', :F),
  (:E, :B, '2029-03-05', 'day',   'absent',    :B),
  (:E, :D, '2029-03-05', 'day',   'available', :D),
  (:E, :A, '2029-03-05', 'night', 'available', :A),
  (:V, :VM,'2029-03-05', 'day',   'available', :VM);

-- ===========================================================================
-- 1. Les réglages
-- ===========================================================================
\echo ''
\echo '--- 1. exchange_auto_approve et exchange_deadline_hours'
do $$
declare
  base jsonb := '{"day_start": "07:00", "day_end": "19:00", "required_day": 1,
    "required_night": 1, "availability_deadline_day": 15, "response_reminder_hours": 24,
    "response_email_hours": 48, "late_report_hours": 72}';
begin
  perform tests_ech.check(station_settings_valid(base), 'une caserne sans les clés reste valide');
  perform tests_ech.check(station_settings_valid(base || '{"exchange_auto_approve": true}'),
    'exchange_auto_approve = true accepté');
  perform tests_ech.check(not station_settings_valid(base || '{"exchange_auto_approve": "true"}'),
    'exchange_auto_approve = "true" (chaîne) refusé');
  perform tests_ech.check(not station_settings_valid(base || '{"exchange_auto_approve": 1}'),
    'exchange_auto_approve = 1 refusé');
  perform tests_ech.check(station_settings_valid(base || '{"exchange_deadline_hours": 1}')
    and station_settings_valid(base || '{"exchange_deadline_hours": 168}'),
    'exchange_deadline_hours de 1 à 168 accepté');
  perform tests_ech.check(not station_settings_valid(base || '{"exchange_deadline_hours": 0}')
    and not station_settings_valid(base || '{"exchange_deadline_hours": 169}')
    and not station_settings_valid(base || '{"exchange_deadline_hours": 2.5}'),
    'exchange_deadline_hours 0, 169 et 2.5 refusés');
  perform tests_ech.egal(station_exchange_deadline_hours('07300000-0000-4000-8000-000000000001'), 24,
    'échéance par défaut : 24 h');
  perform tests_ech.egal(station_exchange_auto_approve('07300000-0000-4000-8000-000000000001'), false,
    'validation automatique désactivée par défaut');
  -- Le 5 mars 2029, 07:00 à Paris (UTC+1), moins 24 h.
  perform tests_ech.egal(exchange_expires_at('07300000-0000-4000-8000-000000000401'),
    '2029-03-04 06:00:00+00'::timestamptz, 'échéance du 5 mars de jour');
  perform tests_ech.egal(exchange_expires_at('07300000-0000-4000-8000-000000000402'),
    '2029-03-04 18:00:00+00'::timestamptz, 'échéance du 5 mars de nuit (début à day_end)');
end $$;

-- ===========================================================================
-- 2. Les refus de request_exchange
-- ===========================================================================
\echo ''
\echo '--- 2. request_exchange refuse ce qu''il doit refuser'
savepoint s2;

-- Une proposition sans réponse de Farid, pour « non acceptée ».
insert into assignments (id, station_id, shift_id, user_id, status, proposed_at, created_by)
values ('07300000-0000-4000-8000-000000000508', :E, :S3, :F, 'proposed', now(), :ADM);

insert into availability_preferences (station_id, user_id, period_id, max_shifts, max_weekends)
values (:E, :B, '07300000-0000-4000-8000-000000000201', 2, 1);

set local role authenticated;
select tests_ech.qui(:A);

select tests_ech.code(request_exchange(:A2, :C), 'assignment_not_found',
  'la garde d''un autre est introuvable');
select tests_ech.code(request_exchange(:A6, :C), 'assignment_not_found',
  'une garde d''une autre caserne aussi');
select tests_ech.code(request_exchange(:A7, :C), 'too_late',
  'une garde d''aujourd''hui : l''échéance est passée');
select tests_ech.code(request_exchange(:A1, :A), 'target_is_self', 'pas à soi-même');
select tests_ech.code(request_exchange(:A1, :D), 'target_not_member', 'pas à un désactivé');
select tests_ech.code(request_exchange(:A1, :VM), 'target_not_member', 'pas à un pompier de la voisine');
select tests_ech.code(request_exchange(:A1, null, :A2), 'swap_requires_target',
  'un échange désigne un collègue');
select tests_ech.code(request_exchange(:A1, :C, :A2), 'return_assignment_not_found',
  'la garde rendue doit être celle du collègue');
select tests_ech.code(request_exchange(:A1, :B, :A6), 'return_assignment_not_found',
  'la garde rendue ne vient pas d''une autre caserne');

select tests_ech.qui(:F);
select tests_ech.code(request_exchange('07300000-0000-4000-8000-000000000508', :C),
  'assignment_not_accepted', 'une proposition sans réponse ne se cède pas');

-- Déjà sur le créneau : Farid a une proposition sur le 6, que Damien voudrait
-- lui céder.
select tests_ech.qui(:C);
select tests_ech.code(request_exchange(:A3, :F), 'already_assigned',
  'Farid a déjà une proposition sur le 6 : déjà sur le créneau');

-- Plafonds de Chloé : deux astreintes (elle en a deux), un weekend (elle en a un).
select tests_ech.qui(:A);
do $$
declare r jsonb;
begin
  r := request_exchange('07300000-0000-4000-8000-000000000501', '07300000-0000-4000-8000-000000000102');
  perform tests_ech.code(r, 'shift_quota_reached', 'une cession à Chloé dépasserait son plafond d''astreintes');
  perform tests_ech.egal(r ->> 'who', 'target', 'et le refus désigne le destinataire');
end $$;

-- En échange contre sa nuit du 5, la charge de Chloé ne bouge pas : le plafond
-- ne refuse plus. (Annulé aussitôt pour la suite.)
savepoint s2b;
select tests_ech.ok(request_exchange(:A1, :B, :A2),
  'un échange dans le même mois ne compte pas la garde quittée');
select tests_ech.code(request_exchange(:A1, :C), 'exchange_already_open',
  'une seule demande ouverte par garde cédée');
select tests_ech.qui(:B);
select tests_ech.code(request_exchange(:A2, :C), 'exchange_already_open',
  'la garde rendue d''une demande ouverte ne se cède pas ailleurs');
rollback to savepoint s2b;

-- Plafond de weekends : zéro weekend pour Farid, et Chloé lui cède le samedi.
reset role;
insert into availability_preferences (station_id, user_id, period_id, max_shifts, max_weekends)
values (:E, :F, '07300000-0000-4000-8000-000000000201', null, 0);
set local role authenticated;
select tests_ech.qui(:B);
select tests_ech.code(request_exchange(:A4, :F), 'weekend_quota_reached',
  'un samedi pour qui a un plafond de zéro weekend');

-- Planning qui n'est plus publié : archivé.
reset role;
update schedules set status = 'archived' where id = :PL;
set local role authenticated;
select tests_ech.qui(:A);
select tests_ech.code(request_exchange(:A1, :C), 'schedule_not_published',
  'pas sur un planning archivé');

reset role;
select tests_ech.egal((select count(*)::int from shift_exchanges where station_id = :E), 0,
  'aucun refus n''a écrit de demande');
rollback to savepoint s2;

-- ===========================================================================
-- 3. Une cession à un collègue, validée par l'administrateur
-- ===========================================================================
\echo ''
\echo '--- 3. Cession à Damien, validée par Nadia'
savepoint s3;
create temporary table t3 (cle text primary key, val jsonb);
grant all on t3 to authenticated;

set local role authenticated;
select tests_ech.qui(:A);
insert into t3 values ('req', tests_ech.ok(request_exchange(:A1, :C), 'Bruno cède le 5 de jour à Damien'));

reset role;
select tests_ech.egal((select val ->> 'status' from t3 where cle = 'req'), 'open', 'la demande naît ouverte');
select tests_ech.egal((select val ->> 'notified' from t3 where cle = 'req'), '1', 'un destinataire mis en file');
select tests_ech.egal(tests_ech.dest('exchange_requested'), format('{%s}', :C),
  'exchange_requested à Damien seul');
select tests_ech.egal((select expires_at from shift_exchanges where id = (select (val ->> 'exchange_id')::uuid from t3 where cle = 'req')),
  '2029-03-04 06:00:00+00'::timestamptz, 'échéance posée à la création');

set local role authenticated;
select tests_ech.qui(:C);
insert into t3 values ('rep', tests_ech.ok(
  respond_exchange((select (val ->> 'exchange_id')::uuid from t3 where cle = 'req')),
  'Damien accepte'));
reset role;
select tests_ech.egal((select val ->> 'status' from t3 where cle = 'rep'), 'accepted_by_peer',
  'la demande attend l''administrateur (réglage désactivé)');
select tests_ech.egal(tests_ech.dest('exchange_accepted'), format('{%s}', :ADM),
  'exchange_accepted aux administrateurs actifs seulement');
select tests_ech.egal((select status::text from assignments where id = :A1), 'accepted',
  'rien n''a bougé avant la validation');

set local role authenticated;
select tests_ech.qui(:A);
select tests_ech.code(decide_exchange((select (val ->> 'exchange_id')::uuid from t3 where cle = 'req'), true),
  'not_admin', 'Bruno ne valide pas sa propre demande');
select tests_ech.qui(:ADM);
insert into t3 values ('dec', tests_ech.ok(
  decide_exchange((select (val ->> 'exchange_id')::uuid from t3 where cle = 'req'), true),
  'Nadia valide'));

reset role;
do $$
declare
  e shift_exchanges;
  ancienne assignments;
  nouvelle assignments;
begin
  select * into e from shift_exchanges
   where station_id = '07300000-0000-4000-8000-000000000001';
  select * into ancienne from assignments where id = '07300000-0000-4000-8000-000000000501';
  select * into nouvelle from assignments where id = e.new_assignment_id;

  perform tests_ech.egal(e.status::text, 'approved', 'demande approved');
  perform tests_ech.egal(e.decided_by, '07300000-0000-4000-8000-000000000100'::uuid, 'validée par Nadia');
  perform tests_ech.egal(e.auto_approved, false, 'pas automatique');
  perform tests_ech.egal(e.taker_id, '07300000-0000-4000-8000-000000000103'::uuid, 'repreneur : Damien');
  perform tests_ech.check(e.accepted_at is not null and e.decided_at is not null and e.closed_at is not null,
    'horodatages posés : accord, décision, clôture');
  perform tests_ech.egal(ancienne.status::text, 'replaced', 'la garde de Bruno est replaced');
  perform tests_ech.egal(ancienne.replaced_by, nouvelle.id, 'replaced_by pointe la garde de Damien');
  perform tests_ech.egal(nouvelle.status::text, 'accepted', 'Damien est accepted, sans repasser par proposed');
  perform tests_ech.egal(nouvelle.user_id, '07300000-0000-4000-8000-000000000103'::uuid, 'au nom de Damien');
  perform tests_ech.egal(nouvelle.shift_id, '07300000-0000-4000-8000-000000000401'::uuid, 'sur le même créneau');
  perform tests_ech.egal(nouvelle.created_by, '07300000-0000-4000-8000-000000000100'::uuid, 'created_by : l''administrateur');
  perform tests_ech.egal(nouvelle.was_available, true, 'was_available relu dans ses disponibilités');
  perform tests_ech.check(nouvelle.proposed_at is not null and nouvelle.responded_at is not null,
    'proposed_at et responded_at posés');
  perform tests_ech.egal(tests_ech.dest('exchange_approved'),
    '{07300000-0000-4000-8000-000000000101,07300000-0000-4000-8000-000000000103}',
    'exchange_approved à Bruno et Damien, pas à Nadia qui a validé');
  perform tests_ech.egal(tests_ech.nb('assignment_cancelled') + tests_ech.nb('assignment_proposed'), 0,
    'ni assignment_cancelled ni assignment_proposed : l''échange se dit par ses propres notifications');
  perform tests_ech.egal(
    (select array_agg(action order by id)::text from audit_log
      where station_id = '07300000-0000-4000-8000-000000000001' and entity = 'shift_exchange'),
    '{exchange.requested,exchange.accepted,exchange.approved}', 'le journal raconte les trois gestes');
  perform tests_ech.egal(
    (select count(*)::int from assignments
      where shift_id = '07300000-0000-4000-8000-000000000401' and status in ('proposed', 'accepted')),
    1, 'toujours une seule garde active sur le créneau');
  perform tests_ech.egal(
    (select payload ->> 'auto_approved' from notification_outbox
      where type = 'exchange_approved' and station_id = '07300000-0000-4000-8000-000000000001'),
    'false', 'la notification dit que la validation n''était pas automatique');
end $$;

-- La garde de Damien vient d'un échange : elle est cessible à son tour, et
-- l'ancienne demande ne bloque rien.
set local role authenticated;
select tests_ech.qui(:ADM);
select tests_ech.code(decide_exchange((select (val ->> 'exchange_id')::uuid from t3 where cle = 'req'), true),
  'exchange_not_pending', 'une demande validée ne se valide pas deux fois');
reset role;
drop table t3;
rollback to savepoint s3;

-- ===========================================================================
-- 4. Un échange est tout ou rien
-- ===========================================================================
\echo ''
\echo '--- 4. Échange : tout ou rien'
create temporary table t4 (cle text primary key, val uuid);
grant all on t4 to authenticated;
savepoint s4;

set local role authenticated;
select tests_ech.qui(:A);
insert into t4 select 'x', (tests_ech.ok(request_exchange(:A1, :B, :A2),
  'Bruno propose son 5 de jour contre la nuit du 5 de Chloé') ->> 'exchange_id')::uuid;
select tests_ech.qui(:B);
select tests_ech.ok(respond_exchange((select val from t4)), 'Chloé accepte');

-- Pendant que la demande attend Nadia, Bruno reçoit une proposition sur la nuit
-- du 5 (un renfort, effectif porté à 2) : le second mouvement ne tient plus.
reset role;
update shifts set required_count = 2 where id = :S2;
insert into assignments (station_id, shift_id, user_id, status, proposed_at, created_by)
values (:E, :S2, :A, 'proposed', now(), :ADM);
delete from notification_outbox where station_id = :E;

set local role authenticated;
select tests_ech.qui(:ADM);
do $$
declare r jsonb;
begin
  r := decide_exchange((select val from t4), true);
  perform tests_ech.code(r, 'exchange_failed', 'la validation échoue');
  perform tests_ech.egal(r ->> 'reason_code', 'requester_already_assigned',
    'motif : Bruno est déjà sur la nuit du 5');
end $$;

reset role;
select tests_ech.egal((select status::text from shift_exchanges where id = (select val from t4)), 'failed',
  'la demande est failed');
select tests_ech.egal((select reason_code from shift_exchanges where id = (select val from t4)),
  'requester_already_assigned', 'avec son motif, dans la liste fermée');
select tests_ech.egal((select status::text from assignments where id = :A1), 'accepted',
  'la garde de Bruno n''a pas bougé');
select tests_ech.egal((select status::text from assignments where id = :A2), 'accepted',
  'celle de Chloé non plus : aucun des deux mouvements');
select tests_ech.egal((select count(*)::int from assignments where shift_id = :S1), 1,
  'aucune attribution créée sur le 5 de jour');
select tests_ech.egal((select count(*)::int from assignments where shift_id = :S2 and user_id = :A
                        and status = 'accepted'), 0, 'ni sur la nuit du 5');
select tests_ech.egal(tests_ech.nb('exchange_approved'), 0, 'aucune notification de validation');
select tests_ech.egal(tests_ech.dest('exchange_closed'),
  '{07300000-0000-4000-8000-000000000101,07300000-0000-4000-8000-000000000102}',
  'exchange_closed à Bruno et Chloé');
rollback to savepoint s4;

savepoint s4b;
set local role authenticated;
select tests_ech.qui(:A);
insert into t4 select 'y', (request_exchange(:A1, :B, :A2) ->> 'exchange_id')::uuid;
select tests_ech.qui(:B);
select tests_ech.ok(respond_exchange((select val from t4 where cle = 'y')), 'Chloé accepte l''échange');
select tests_ech.qui(:ADM);
select tests_ech.ok(decide_exchange((select val from t4 where cle = 'y'), true), 'Nadia valide l''échange');
reset role;
do $$
declare e shift_exchanges;
begin
  select * into e from shift_exchanges where status = 'approved'
     and station_id = '07300000-0000-4000-8000-000000000001';
  perform tests_ech.egal((select status::text from assignments where id = '07300000-0000-4000-8000-000000000501'),
    'replaced', 'la garde de Bruno est replaced');
  perform tests_ech.egal((select status::text from assignments where id = '07300000-0000-4000-8000-000000000502'),
    'replaced', 'celle de Chloé aussi');
  perform tests_ech.egal((select replaced_by from assignments where id = '07300000-0000-4000-8000-000000000501'),
    e.new_assignment_id, 'Bruno -> nouvelle garde de Chloé');
  perform tests_ech.egal((select replaced_by from assignments where id = '07300000-0000-4000-8000-000000000502'),
    e.new_return_assignment_id, 'Chloé -> nouvelle garde de Bruno');
  perform tests_ech.egal((select user_id::text || '/' || shift_id::text || '/' || status::text
                            from assignments where id = e.new_assignment_id),
    '07300000-0000-4000-8000-000000000102/07300000-0000-4000-8000-000000000401/accepted',
    'Chloé tient le 5 de jour');
  perform tests_ech.egal((select user_id::text || '/' || shift_id::text || '/' || status::text
                            from assignments where id = e.new_return_assignment_id),
    '07300000-0000-4000-8000-000000000101/07300000-0000-4000-8000-000000000402/accepted',
    'Bruno tient la nuit du 5');
  -- Chloé était « absente » le 5 de jour : la trace hors disponibilité est posée.
  perform tests_ech.egal((select was_available from assignments where id = e.new_assignment_id), false,
    'was_available faux pour Chloé, déclarée absente');
  perform tests_ech.check(exists (select 1 from audit_log where action = 'assignment.force'
                                     and entity_id = e.new_assignment_id),
    'et assignment.force journalise l''attribution hors disponibilité');
end $$;
rollback to savepoint s4b;
drop table t4;

-- ===========================================================================
-- 5. À la caserne
-- ===========================================================================
\echo ''
\echo '--- 5. Demande à la caserne : les disponibles, le premier qui accepte'
savepoint s5;
create temporary table t5 (val uuid);
grant all on t5 to authenticated;

set local role authenticated;
select tests_ech.qui(:A);
insert into t5 select (tests_ech.ok(request_exchange(:A1), 'Bruno cherche un remplaçant')
  ->> 'exchange_id')::uuid;

reset role;
select tests_ech.egal(tests_ech.dest('exchange_requested'),
  '{07300000-0000-4000-8000-000000000103,07300000-0000-4000-8000-000000000105}',
  'reçue par Damien et Farid seulement (disponibles, actifs)');
select tests_ech.egal((select kind::text || '/' || coalesce(target_id::text, 'caserne') from shift_exchanges
                        where id = (select val from t5)), 'give/caserne', 'une cession à la caserne');

set local role authenticated;
select tests_ech.qui(:C);
select tests_ech.egal((select count(*)::int from shift_exchanges), 1, 'Damien la voit');
select tests_ech.qui(:F);
select tests_ech.egal((select count(*)::int from shift_exchanges), 1, 'Farid la voit');
select tests_ech.qui(:B);
select tests_ech.egal((select count(*)::int from shift_exchanges), 0, 'Chloé, absente, ne la voit pas');
select tests_ech.code(respond_exchange((select val from t5)), 'not_available',
  'et ne peut pas la prendre');
select tests_ech.qui(:D);
select tests_ech.egal((select count(*)::int from shift_exchanges), 0, 'Eve, désactivée, ne la voit pas');
select tests_ech.qui(:VM);
select tests_ech.egal((select count(*)::int from shift_exchanges), 0,
  'Hugo, disponible le même jour dans la voisine, ne la voit pas');
select tests_ech.code(respond_exchange((select val from t5)), 'exchange_not_found',
  'et ne peut pas y répondre');
select tests_ech.qui(:C);
select tests_ech.code(respond_exchange((select val from t5), false), 'not_target',
  'une demande à la caserne ne se décline pas');
select tests_ech.qui(:A);
select tests_ech.code(respond_exchange((select val from t5)), 'exchange_not_found',
  'Bruno ne reprend pas sa propre garde');

select tests_ech.qui(:C);
select tests_ech.ok(respond_exchange((select val from t5)), 'Damien la prend le premier');
select tests_ech.qui(:F);
select tests_ech.code(respond_exchange((select val from t5)), 'exchange_not_open',
  'Farid arrive second : elle est prise');
select tests_ech.egal((select count(*)::int from shift_exchanges), 0,
  'et elle sort de sa vue');
select tests_ech.qui(:C);
select tests_ech.egal((select count(*)::int from shift_exchanges), 1, 'Damien, repreneur, la garde');
reset role;
select tests_ech.egal((select taker_id from shift_exchanges where id = (select val from t5)), :C::uuid,
  'le repreneur est Damien');
drop table t5;
rollback to savepoint s5;

-- ===========================================================================
-- 6. Validation automatique
-- ===========================================================================
\echo ''
\echo '--- 6. Validation automatique : réglage ET disponibilité déclarée'
savepoint s6;
update stations set settings = settings || '{"exchange_auto_approve": true}' where id = :E;
create temporary table t6 (cle text primary key, val jsonb);
grant all on t6 to authenticated;

-- a) Réglage actif, Damien disponible : validée tout de suite.
set local role authenticated;
select tests_ech.qui(:A);
insert into t6 values ('a', request_exchange(:A1, :C));
select tests_ech.qui(:C);
insert into t6 values ('ar', respond_exchange((select (val ->> 'exchange_id')::uuid from t6 where cle = 'a')));
reset role;
select tests_ech.egal((select val ->> 'status' from t6 where cle = 'ar'), 'approved', 'validée sans attendre');
select tests_ech.egal((select val ->> 'auto_approved' from t6 where cle = 'ar'), 'true', 'auto_approved rendu');
select tests_ech.egal((select auto_approved::text || '/' || coalesce(decided_by::text, 'personne')
                         from shift_exchanges where id = (select (val ->> 'exchange_id')::uuid from t6 where cle = 'a')),
  'true/personne', 'auto_approved, decided_by nul');
select tests_ech.egal((select created_by from assignments where id =
                         (select new_assignment_id from shift_exchanges
                           where id = (select (val ->> 'exchange_id')::uuid from t6 where cle = 'a'))),
  :C::uuid, 'created_by : le repreneur');
select tests_ech.egal(tests_ech.nb('exchange_accepted'), 0, 'aucune demande de validation aux admins');
select tests_ech.egal(
  (select string_agg((r ->> 'user_id') || ':' || (r -> 'payload' ->> 'audience'), ',' order by r ->> 'user_id')
     from notification_outbox o, jsonb_array_elements(o.recipients) r
    where o.station_id = :E and o.type = 'exchange_approved'),
  '07300000-0000-4000-8000-000000000100:admin,07300000-0000-4000-8000-000000000101:member',
  'Nadia est informée (audience admin), Bruno prévenu ; Damien, l''acteur, non');

-- b) Réglage actif, mais Chloé n'a rien déclaré sur le 6 : l'administrateur.
set local role authenticated;
select tests_ech.qui(:C);
insert into t6 values ('b', request_exchange(:A3, :B));
select tests_ech.qui(:B);
insert into t6 values ('br', respond_exchange((select (val ->> 'exchange_id')::uuid from t6 where cle = 'b')));
reset role;
select tests_ech.egal((select val ->> 'status' from t6 where cle = 'br'), 'accepted_by_peer',
  'sans disponibilité déclarée, la demande attend l''admin');
select tests_ech.egal(tests_ech.dest('exchange_accepted'), format('{%s}', :ADM), 'Nadia doit valider');

-- c) Réglage désactivé, Farid disponible : l'administrateur aussi.
update stations set settings = settings - 'exchange_auto_approve' where id = :E;
insert into availabilities (station_id, user_id, date, slot, status, set_by)
values (:E, :C, '2029-03-12', 'day', 'available', :C);
set local role authenticated;
select tests_ech.qui(:F);
insert into t6 values ('c2', request_exchange(:A5));
select tests_ech.qui(:C);
insert into t6 values ('cr', respond_exchange((select (val ->> 'exchange_id')::uuid from t6 where cle = 'c2')));
reset role;
select tests_ech.egal((select val ->> 'ok' from t6 where cle = 'c2'), 'true', 'demande de Farid créée');
select tests_ech.egal((select val ->> 'status' from t6 where cle = 'cr'), 'accepted_by_peer',
  'réglage désactivé : la disponibilité ne suffit pas');
drop table t6;
rollback to savepoint s6;

-- ===========================================================================
-- 7. Expiration
-- ===========================================================================
\echo ''
\echo '--- 7. Expiration'
create temporary table t7 (cle text primary key, val uuid);
grant all on t7 to authenticated;
savepoint s7;

set local role authenticated;
select tests_ech.qui(:A);
insert into t7 select 'o', (request_exchange(:A1, :C) ->> 'exchange_id')::uuid;
select tests_ech.qui(:C);
insert into t7 select 'f', (request_exchange(:A3) ->> 'exchange_id')::uuid;
reset role;

select tests_ech.egal(cron_expire_exchanges('2029-03-04 05:59:00+00'), 0, 'une minute avant : rien');
select tests_ech.egal(cron_expire_exchanges('2029-03-04 06:00:00+00'), 1,
  'à l''échéance du 5 : une demande close');
select tests_ech.egal((select status::text || '/' || reason_code from shift_exchanges where id = (select val from t7 where cle = 'o')),
  'expired/deadline_reached', 'expired, motif deadline_reached');
select tests_ech.egal(tests_ech.dest('exchange_closed'),
  '{07300000-0000-4000-8000-000000000101,07300000-0000-4000-8000-000000000103}',
  'Bruno et Damien prévenus');
-- 07:00 à Paris : avant la fenêtre (9 h par défaut) — sans sonnerie.
select tests_ech.egal((select channels::text from notification_outbox where station_id = :E and type = 'exchange_closed'),
  '{inapp}', 'hors de la fenêtre locale : inapp seul');
select tests_ech.egal(cron_expire_exchanges('2029-03-04 06:00:00+00'), 0, 'idempotente');
select tests_ech.egal(cron_expire_exchanges('2029-03-05 10:00:00+00'), 1,
  'la demande à la caserne du 6 expire à son tour');
select tests_ech.egal((select channels from notification_outbox where station_id = :E and type = 'exchange_closed'
                        and dedupe_key = 'exchange_closed:' || (select val from t7 where cle = 'f')), null,
  'à 11:00 locales : canaux par défaut');
select tests_ech.egal((select jsonb_array_length(recipients) from notification_outbox
                        where dedupe_key = 'exchange_closed:' || (select val from t7 where cle = 'f')), 1,
  'une demande à la caserne non prise : seul le demandeur est prévenu');
rollback to savepoint s7;

-- La tâche en retard ne rend pas une demande échue acceptable.
savepoint s7b;
set local role authenticated;
select tests_ech.qui(:A);
insert into t7 select 'x', (request_exchange(:A1, :C) ->> 'exchange_id')::uuid;
reset role;
alter table shift_exchanges disable trigger shift_exchanges_guard;
update shift_exchanges set expires_at = now() - interval '1 minute' where id = (select val from t7 where cle = 'x');
alter table shift_exchanges enable trigger shift_exchanges_guard;
set local role authenticated;
select tests_ech.qui(:C);
select tests_ech.code(respond_exchange((select val from t7 where cle = 'x')), 'exchange_expired',
  'une demande échue ne se prend plus, même avant le passage de la tâche');
reset role;
select tests_ech.egal((select status::text from shift_exchanges where id = (select val from t7 where cle = 'x')),
  'expired', 'et elle est close sur le coup');
rollback to savepoint s7b;
drop table t7;

-- ===========================================================================
-- 8. Suspension
-- ===========================================================================
\echo ''
\echo '--- 8. Caserne en lecture seule'
savepoint s8;
create temporary table t8 (cle text primary key, val uuid);
grant all on t8 to authenticated;

set local role authenticated;
select tests_ech.qui(:A);
insert into t8 select 'p', (request_exchange(:A1, :C) ->> 'exchange_id')::uuid;
select tests_ech.qui(:C);
select tests_ech.ok(respond_exchange((select val from t8 where cle = 'p')), 'Damien accepte avant la suspension');
select tests_ech.qui(:B);
insert into t8 select 'q', (request_exchange(:A4, :C) ->> 'exchange_id')::uuid;
select tests_ech.qui(:F);
insert into t8 select 'r', (request_exchange(:A5, :C) ->> 'exchange_id')::uuid;

reset role;
update subscriptions set status = 'suspended', suspended_at = now() where station_id = :E;

set local role authenticated;
select tests_ech.qui(:C);
select tests_ech.code(request_exchange(:A3, :F), 'station_suspended', 'aucune demande ne se crée');
select tests_ech.code(respond_exchange((select val from t8 where cle = 'q')), 'station_suspended',
  'aucune demande ne s''accepte');
select tests_ech.qui(:ADM);
do $$
declare r jsonb;
begin
  r := decide_exchange((select val from t8 where cle = 'p'), true);
  perform tests_ech.code(r, 'exchange_failed', 'aucune ne se valide');
  perform tests_ech.egal(r ->> 'reason_code', 'station_suspended', 'motif station_suspended');
end $$;
select tests_ech.qui(:C);
select tests_ech.ok(respond_exchange((select val from t8 where cle = 'q'), false),
  'décliner reste possible : rien ne change dans le planning');
select tests_ech.qui(:F);
select tests_ech.ok(cancel_exchange((select val from t8 where cle = 'r')), 'annuler aussi');
reset role;
select tests_ech.egal((select status::text from assignments where id = :A1), 'accepted', 'la garde de Bruno est intacte');
select tests_ech.egal((select decided_by from shift_exchanges where id = (select val from t8 where cle = 'p')), :ADM::uuid,
  'l''échec garde l''administrateur dont la validation n''a pas abouti');
drop table t8;
rollback to savepoint s8;

-- ===========================================================================
-- 9. Annuler et décliner
-- ===========================================================================
\echo ''
\echo '--- 9. Annuler, décliner'
savepoint s9;
create temporary table t9 (cle text primary key, val uuid);
grant all on t9 to authenticated;

set local role authenticated;
select tests_ech.qui(:A);
insert into t9 select 'a', (request_exchange(:A1, :C) ->> 'exchange_id')::uuid;
select tests_ech.qui(:C);
select tests_ech.code(cancel_exchange((select val from t9 where cle = 'a')), 'exchange_not_found',
  'le destinataire n''annule pas la demande d''un autre');
select tests_ech.qui(:ADM);
select tests_ech.code(cancel_exchange((select val from t9 where cle = 'a')), 'exchange_not_found',
  'l''administrateur non plus (décision du brief)');
select tests_ech.code(decide_exchange((select val from t9 where cle = 'a'), false), 'exchange_not_pending',
  'et il ne refuse pas une demande que personne n''a encore acceptée');
select tests_ech.qui(:A);
select tests_ech.ok(cancel_exchange((select val from t9 where cle = 'a')), 'Bruno annule');
select tests_ech.code(cancel_exchange((select val from t9 where cle = 'a')), 'exchange_not_open',
  'une seconde fois : déjà close');
select tests_ech.qui(:C);
select tests_ech.code(respond_exchange((select val from t9 where cle = 'a')), 'exchange_not_open',
  'Damien ne peut plus accepter');
reset role;
select tests_ech.egal(tests_ech.dest('exchange_closed'), format('{%s}', :C),
  'annulation : Damien prévenu, pas Bruno');
select tests_ech.egal((select reason_code || '/' || coalesce(decided_by::text, 'personne') from shift_exchanges
                        where id = (select val from t9 where cle = 'a')), 'requester_cancelled/personne',
  'motif requester_cancelled');

-- Bruno peut refaire une demande : la précédente est close.
set local role authenticated;
select tests_ech.qui(:A);
insert into t9 select 'b', (tests_ech.ok(request_exchange(:A1, :C), 'nouvelle demande après annulation') ->> 'exchange_id')::uuid;
select tests_ech.qui(:C);
select tests_ech.ok(respond_exchange((select val from t9 where cle = 'b'), false), 'Damien décline');
reset role;
select tests_ech.egal((select status::text || '/' || reason_code || '/' || decided_by::text from shift_exchanges
                        where id = (select val from t9 where cle = 'b')),
  format('rejected/peer_declined/%s', :C), 'rejected par Damien, qui est tracé');
select tests_ech.egal(tests_ech.dest('exchange_rejected'), format('{%s}', :A), 'Bruno prévenu du refus');

-- Accepté puis refusé par l'administrateur, avec un motif.
set local role authenticated;
select tests_ech.qui(:A);
insert into t9 select 'c', (request_exchange(:A1, :C) ->> 'exchange_id')::uuid;
select tests_ech.qui(:C);
select respond_exchange((select val from t9 where cle = 'c'));
select tests_ech.qui(:C);
select tests_ech.code(respond_exchange((select val from t9 where cle = 'c'), false), 'exchange_not_open',
  'Damien ne revient pas sur son accord (il passe par le chef)');
select tests_ech.qui(:ADM);
select tests_ech.ok(decide_exchange((select val from t9 where cle = 'c'), false, 'Damien est en formation ce jour-là'),
  'Nadia refuse avec un motif');
reset role;
select tests_ech.egal((select reason_code || '/' || reason || '/' || decided_by::text from shift_exchanges
                        where id = (select val from t9 where cle = 'c')),
  format('admin_rejected/Damien est en formation ce jour-là/%s', :ADM), 'motif et auteur conservés');
select tests_ech.egal((select array_agg(r ->> 'user_id' order by r ->> 'user_id')::text
                         from notification_outbox o, jsonb_array_elements(o.recipients) r
                        where o.dedupe_key = 'exchange_rejected:' || (select val from t9 where cle = 'c')),
  format('{%s,%s}', :A, :C), 'refus de l''admin : Bruno et Damien prévenus');
select tests_ech.egal((select payload ->> 'reason' from notification_outbox
                        where dedupe_key = 'exchange_rejected:' || (select val from t9 where cle = 'c')),
  'Damien est en formation ce jour-là', 'le motif voyage dans la notification');
drop table t9;
rollback to savepoint s9;

-- ===========================================================================
-- 10. Une garde retirée par l'administrateur
-- ===========================================================================
\echo ''
\echo '--- 10. Réattribution et annulation par l''admin font échouer la demande'
savepoint s10;
create temporary table t10 (cle text primary key, val uuid);
grant all on t10 to authenticated;

set local role authenticated;
select tests_ech.qui(:A);
insert into t10 select 'a', (request_exchange(:A1, :C) ->> 'exchange_id')::uuid;
reset role;
select tests_ech.qui(null);
-- `reassign_shift` est appelée par le rôle de service (auth.uid() nul).
select tests_ech.ok(reassign_shift(:S1, :F, :ADM, :A1), 'Nadia confie le 5 de jour à Farid');
select tests_ech.egal((select status::text || '/' || reason_code from shift_exchanges where id = (select val from t10 where cle = 'a')),
  'failed/assignment_changed', 'la demande échoue dans la même transaction');
select tests_ech.egal(tests_ech.dest('exchange_closed'), format('{%s,%s}', :A, :C),
  'Bruno et Damien prévenus');
set local role authenticated;
select tests_ech.qui(:C);
select tests_ech.code(respond_exchange((select val from t10 where cle = 'a')), 'exchange_not_open',
  'Damien ne peut plus la prendre');

select tests_ech.qui(:B);
insert into t10 select 'b', (request_exchange(:A4) ->> 'exchange_id')::uuid;
select tests_ech.qui(:ADM);
select tests_ech.ok(cancel_assignment(:A4, 'samedi supprimé'), 'Nadia annule le samedi de Chloé');
reset role;
select tests_ech.egal((select status::text || '/' || reason_code || '/' || coalesce(decided_by::text, 'personne')
                         from shift_exchanges where id = (select val from t10 where cle = 'b')),
  'failed/assignment_changed/personne', 'la demande à la caserne échoue aussi');
drop table t10;
rollback to savepoint s10;

-- ===========================================================================
-- 11. Cloisonnement
-- ===========================================================================
\echo ''
\echo '--- 11. Cloisonnement et écritures directes'
savepoint s11b;
create temporary table t11 (val uuid);
grant all on t11 to authenticated;
set local role authenticated;
select tests_ech.qui(:A);
insert into t11 select (request_exchange(:A1, :C) ->> 'exchange_id')::uuid;

select tests_ech.qui(:ADM);
select tests_ech.egal((select count(*)::int from shift_exchanges), 1, 'Nadia, admin, voit la demande de sa caserne');
select tests_ech.qui(:B);
select tests_ech.egal((select count(*)::int from shift_exchanges), 0,
  'Chloé, membre non concernée, ne voit pas une demande adressée à Damien');
select tests_ech.code(respond_exchange((select val from t11)), 'exchange_not_found',
  'et ne peut pas y répondre');
select tests_ech.qui(:VADM);
select tests_ech.egal((select count(*)::int from shift_exchanges), 0, 'l''admin de la voisine ne voit rien');
select tests_ech.code(decide_exchange((select val from t11), false), 'exchange_not_found',
  'et ne décide rien');
select tests_ech.qui(:VM);
select tests_ech.egal((select count(*)::int from shift_exchanges), 0, 'Hugo non plus');

select tests_ech.qui(:A);
select tests_ech.refuse(
  format($s$insert into shift_exchanges (station_id, kind, requester_id, assignment_id, shift_id, expires_at)
            values (%L, 'give', %L, %L, %L, now() + interval '1 day')$s$,
         '07300000-0000-4000-8000-000000000001', '07300000-0000-4000-8000-000000000101',
         '07300000-0000-4000-8000-000000000501', '07300000-0000-4000-8000-000000000401'),
  '42501', 'un client n''insère pas une demande directement');
select tests_ech.refuse(
  format($s$update shift_exchanges set status = 'approved' where id = %L$s$, (select val from t11)),
  '42501', 'ni ne la passe en approved');
select tests_ech.qui(:ADM);
select tests_ech.refuse(
  format($s$delete from shift_exchanges where id = %L$s$, (select val from t11)),
  '42501', 'un admin ne la supprime pas');

-- Désactivé après coup : Damien ne lit plus rien.
reset role;
update memberships set status = 'disabled' where station_id = :E and user_id = :C;
set local role authenticated;
select tests_ech.qui(:C);
select tests_ech.egal((select count(*)::int from shift_exchanges), 0,
  'une appartenance désactivée ne lit plus ses demandes');
select tests_ech.code(respond_exchange((select val from t11)), 'exchange_not_found',
  'ni n''y répond');
reset role;
select tests_ech.check(not has_table_privilege('anon', 'public.shift_exchanges', 'select'),
  'anon ne lit pas la table');
drop table t11;
rollback to savepoint s11b;

-- ===========================================================================
-- 12. exchangeable_shifts_of
-- ===========================================================================
\echo ''
\echo '--- 12. Les gardes de B que A peut demander'
savepoint s12;
-- Une proposition sans réponse de Chloé, qui ne doit pas sortir.
update shifts set required_count = 2 where id = :S3;
insert into assignments (station_id, shift_id, user_id, status, proposed_at, created_by)
values (:E, :S3, :B, 'proposed', now(), :ADM);

set local role authenticated;
select tests_ech.qui(:A);
select tests_ech.egal((select array_agg(assignment_id order by date, slot)::text from exchangeable_shifts_of(:B)),
  format('{%s,%s}', :A2, :A4), 'Bruno voit la nuit du 5 et le samedi 10 de Chloé, acceptées');
select tests_ech.egal((select count(*)::int from exchangeable_shifts_of(:A)), 0, 'rien pour soi-même');
select tests_ech.egal((select count(*)::int from exchangeable_shifts_of(:VM)), 0, 'rien d''un pompier de la voisine');
select tests_ech.egal((select count(*)::int from exchangeable_shifts_of(:D)), 0, 'rien d''un désactivé');
select tests_ech.qui(:VM);
select tests_ech.egal((select count(*)::int from exchangeable_shifts_of(:B)), 0,
  'Hugo ne lit rien de Chloé : pas de caserne partagée');
-- Engagée dans une demande ouverte : plus proposable.
select tests_ech.qui(:B);
select tests_ech.ok(request_exchange(:A4, :C), 'Chloé propose son samedi à Damien');
select tests_ech.qui(:A);
select tests_ech.egal((select array_agg(assignment_id)::text from exchangeable_shifts_of(:B)),
  format('{%s}', :A2), 'le samedi engagé n''est plus proposable');
select tests_ech.egal((select station_id from exchangeable_shifts_of(:B) limit 1), :E::uuid,
  'la caserne est rendue avec la garde');
reset role;
rollback to savepoint s12;

-- ===========================================================================
-- 13. Machine à états, droits, tâche planifiée
-- ===========================================================================
\echo ''
\echo '--- 13. Machine à états, droits, cron'
savepoint s13;
create temporary table t13 (val uuid);
grant all on t13 to authenticated;
set local role authenticated;
select tests_ech.qui(:A);
insert into t13 select (request_exchange(:A1, :C) ->> 'exchange_id')::uuid;
select tests_ech.ok(cancel_exchange((select val from t13)), 'annulée');
reset role;
select tests_ech.refuse(format($s$update shift_exchanges set status = 'open', closed_at = null, reason_code = null where id = %L$s$,
                               (select val from t13)),
  'exchange_closed', 'une demande close ne se rouvre pas, même pour le rôle de service');
rollback to savepoint s13;

savepoint s13b;
create temporary table t13 (val uuid);
grant all on t13 to authenticated;
set local role authenticated;
select tests_ech.qui(:A);
insert into t13 select (request_exchange(:A1, :C) ->> 'exchange_id')::uuid;
reset role;
select tests_ech.refuse(format($s$update shift_exchanges set status = 'approved' where id = %L$s$, (select val from t13)),
  'exchange_invalid_transition', 'open -> approved n''existe pas');
select tests_ech.refuse(format($s$update shift_exchanges set target_id = %L where id = %L$s$,
                               '07300000-0000-4000-8000-000000000105', (select val from t13)),
  'exchange_key_immutable', 'le destinataire ne se réécrit pas');
select tests_ech.refuse(format($s$update shift_exchanges set status = 'failed', closed_at = now(), reason_code = 'n_importe_quoi' where id = %L$s$,
                               (select val from t13)),
  '23514', 'un motif hors de la liste fermée est refusé');
select tests_ech.refuse(format($s$insert into shift_exchanges (station_id, kind, requester_id, assignment_id, shift_id, expires_at)
                                  values (%L, 'give', %L, %L, %L, now())$s$,
                               '07300000-0000-4000-8000-000000000001', '07300000-0000-4000-8000-000000000102',
                               '07300000-0000-4000-8000-000000000501', '07300000-0000-4000-8000-000000000401'),
  'exchange_assignment_mismatch', 'la garde cédée appartient au demandeur');
rollback to savepoint s13b;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.request_exchange(uuid, uuid, uuid)',
    'public.respond_exchange(uuid, boolean)',
    'public.decide_exchange(uuid, boolean, text)',
    'public.cancel_exchange(uuid)',
    'public.exchangeable_shifts_of(uuid)']
  loop
    perform tests_ech.check(has_function_privilege('authenticated', f, 'execute')
                            and not has_function_privilege('anon', f, 'execute'),
      f || ' : authenticated oui, anon non');
  end loop;

  foreach f in array array[
    'public.exchange_apply(uuid, uuid, boolean)',
    'public.exchange_close(uuid, exchange_status, text, uuid, text, timestamptz, text[])',
    'public.exchange_lock(uuid)',
    'public.exchange_rule_check(uuid, uuid, uuid, uuid)',
    'public.exchange_payload(uuid)',
    'public.cron_expire_exchanges(timestamptz)',
    'public.station_exchange_auto_approve(uuid)',
    'public.station_exchange_deadline_hours(uuid)']
  loop
    perform tests_ech.check(not has_function_privilege('authenticated', f, 'execute')
                            and not has_function_privilege('anon', f, 'execute'),
      f || ' : fermée aux clients');
  end loop;

  perform tests_ech.egal(
    (select schedule || ' | ' || command from cron.job where jobname = 'expire_exchanges'),
    '2-59/10 * * * * | select public.cron_expire_exchanges();',
    'la tâche expire_exchanges est planifiée, qualifiée, sans argument');
end $$;

-- ===========================================================================
-- 14. Pris ailleurs (ticket 072) : deux casernes
-- ===========================================================================
\echo ''
\echo '--- 14. Pas pris sur un créneau qui chevauche dans une autre caserne'
savepoint s14;
create temporary table t14 (cle text primary key, val uuid);
grant all on t14 to authenticated;

-- Damien et Bruno servent aussi dans la voisine. Bruno y tient la nuit du 5
-- (chevauche la nuit du 5 chez nous), Damien rien encore.
insert into memberships (station_id, user_id, role, status, display_name) values
  (:V, :C, 'member', 'active', 'Damien D.'),
  (:V, :A, 'member', 'active', 'Bruno B.');
insert into shifts (id, station_id, schedule_id, date, slot, required_count) values
  ('07300000-0000-4000-8000-000000000408', :V, '07300000-0000-4000-8000-000000000302', '2029-03-05', 'night', 1),
  ('07300000-0000-4000-8000-000000000409', :V, '07300000-0000-4000-8000-000000000302', '2029-03-06', 'day', 1);
update shifts set required_count = 2 where id = :S6;
insert into assignments (station_id, shift_id, user_id, status, proposed_at, responded_at, created_by) values
  (:V, '07300000-0000-4000-8000-000000000408', :A, 'accepted', now(), now(), :VADM),
  -- Le 6 de jour chez la voisine ne chevauche pas le 5 de jour : sans effet.
  (:V, '07300000-0000-4000-8000-000000000409', :C, 'accepted', now(), now(), :VADM);

set local role authenticated;
select tests_ech.qui(:A);
insert into t14 select 'libre', (tests_ech.ok(request_exchange(:A1, :C),
  'Damien, pris le 6 ailleurs, reste libre le 5 : demande acceptée') ->> 'exchange_id')::uuid;
select tests_ech.qui(:C);
select tests_ech.ok(respond_exchange((select val from t14 where cle = 'libre')), 'Damien accepte');

-- Entre l'accord et la validation, la voisine propose Damien le 5 de jour.
reset role;
insert into assignments (station_id, shift_id, user_id, status, proposed_at, created_by)
values (:V, :S6, :C, 'proposed', now(), :VADM);

set local role authenticated;
select tests_ech.qui(:ADM);
do $$
declare r jsonb;
begin
  r := decide_exchange((select val from t14 where cle = 'libre'), true);
  perform tests_ech.code(r, 'exchange_failed', 'la validation échoue');
  perform tests_ech.egal(r ->> 'reason_code', 'peer_taken_elsewhere',
    'motif peer_taken_elsewhere : Damien est proposé ailleurs sur le même créneau');
end $$;
reset role;
select tests_ech.egal((select status::text from assignments where id = :A1), 'accepted',
  'la garde de Bruno n''a pas bougé');

-- Désormais pris : une nouvelle demande à Damien est refusée d'emblée…
set local role authenticated;
select tests_ech.qui(:A);
do $$
declare r jsonb;
begin
  r := request_exchange('07300000-0000-4000-8000-000000000501', '07300000-0000-4000-8000-000000000103');
  perform tests_ech.code(r, 'taken_elsewhere', 'demande à un collègue pris ailleurs refusée');
  perform tests_ech.egal(r ->> 'who', 'target', 'le refus désigne le destinataire');
  perform tests_ech.check(r::text not like '%07300000-0000-4000-8000-000000000002%'
                          and r::text not like '%Voisine%',
    'et ne dit rien de l''autre caserne');
end $$;

-- … et une demande à la caserne ne lui parvient pas.
insert into t14 select 'caserne', (request_exchange(:A1) ->> 'exchange_id')::uuid;
reset role;
select tests_ech.egal(
  (select array_agg(r ->> 'user_id' order by r ->> 'user_id')::text
     from notification_outbox o, jsonb_array_elements(o.recipients) r
    where o.dedupe_key = 'exchange_requested:' || (select val from t14 where cle = 'caserne')),
  format('{%s}', :F), 'à la caserne : Farid seul, Damien pris ailleurs n''est pas sollicité');
set local role authenticated;
select tests_ech.qui(:C);
select tests_ech.code(respond_exchange((select val from t14 where cle = 'caserne')), 'taken_elsewhere',
  'et s''il la reprend quand même, la règle le refuse');
select tests_ech.qui(:A);
select cancel_exchange((select val from t14 where cle = 'caserne'));

-- Le demandeur d'un échange : Bruno tient la nuit du 5 dans la voisine, il ne
-- peut pas demander la nuit du 5 de Chloé en retour.
do $$
declare r jsonb;
begin
  r := request_exchange('07300000-0000-4000-8000-000000000501', '07300000-0000-4000-8000-000000000102',
                        '07300000-0000-4000-8000-000000000502');
  perform tests_ech.code(r, 'taken_elsewhere', 'échange refusé : le demandeur est pris ailleurs');
  perform tests_ech.egal(r ->> 'who', 'requester', 'le refus désigne le demandeur');
end $$;

-- À la validation : Bruno libre au moment de la demande, pris ensuite.
reset role;
update assignments set status = 'cancelled'
 where station_id = :V and user_id = :A and shift_id = '07300000-0000-4000-8000-000000000408';
set local role authenticated;
select tests_ech.qui(:A);
insert into t14 select 'swap', (tests_ech.ok(request_exchange(:A1, :B, :A2),
  'libéré ailleurs, Bruno peut proposer l''échange') ->> 'exchange_id')::uuid;
select tests_ech.qui(:B);
select respond_exchange((select val from t14 where cle = 'swap'));
reset role;
update shifts set required_count = 2 where id = '07300000-0000-4000-8000-000000000408';
insert into assignments (station_id, shift_id, user_id, status, proposed_at, created_by)
values (:V, '07300000-0000-4000-8000-000000000408', :A, 'proposed', null, :VADM);
set local role authenticated;
select tests_ech.qui(:ADM);
do $$
declare r jsonb;
begin
  r := decide_exchange((select val from t14 where cle = 'swap'), true);
  perform tests_ech.egal(r ->> 'reason_code', 'requester_taken_elsewhere',
    'un brouillon de la voisine suffit : requester_taken_elsewhere, tout ou rien');
end $$;
reset role;
select tests_ech.egal((select status::text || '/' || (select status::text from assignments where id = :A2)
                         from assignments where id = :A1),
  'accepted/accepted', 'aucune des deux gardes n''a bougé');
drop table t14;
rollback to savepoint s14;

\echo ''
\echo '=== Échanges d''astreintes : tous les tests passent ==='

rollback;
